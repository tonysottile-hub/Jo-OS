CREATE OR REPLACE FUNCTION jo_core.detect_recovery_incidents()
RETURNS jsonb LANGUAGE plpgsql SET search_path TO '' AS $body$
DECLARE x record; k text; n integer:=0;
BEGIN
 IF NOT pg_try_advisory_xact_lock(hashtextextended('jo_core.detect_recovery_incidents',0)) THEN RETURN '{"busy":true}'::jsonb; END IF;
 FOR x IN
 select lower(j.role::text) worker_key,'job:'||j.job_id::text fingerprint,
 'recurring_no_progress' failure_class,
 'Recovery budget reached for job '||j.job_id::text summary,
 coalesce(j.last_error,'No progress') cause
 from team_v4.jobs j where j.status in ('stalled','failed') and (j.no_progress_cycles>=j.max_attempts or j.attempts>=j.max_attempts)
 union all
 select 'jeff','briefing:'||b.briefing_id::text,'missing_delivery',
 'Scheduled briefing lacks destination receipt', 'Briefing '||b.briefing_id::text||' remains undelivered'
 from jo_core.briefings b where b.scheduled_for<now()-interval '15 minutes' and b.scheduled_for>now()-interval '2 days' and b.delivered_at is null
 LOOP
 k:='autonomous-recovery:'||x.fingerprint;
 IF NOT EXISTS(select 1 from jo_core.failure_memory where failure_fingerprint=k) THEN
 insert into jo_core.failure_memory(worker_key,failure_fingerprint,failure_class,summary,root_cause,status)
 values(x.worker_key,k,x.failure_class,x.summary,x.cause,'diagnosing');
 insert into jo_core.events(worker_key,event_type,detail) values(x.worker_key,'recovery_incident_detected',jsonb_build_object('fingerprint',k,'cause',x.cause,'owner_action_required',false,'business_completion',false));
 n:=n+1;
 ELSE
 update jo_core.failure_memory set last_seen_at=now(),root_cause=x.cause where failure_fingerprint=k;
 END IF;
 END LOOP;
 RETURN jsonb_build_object('new_incidents',n,'observed_at',now());
END $body$;
REVOKE ALL ON FUNCTION jo_core.detect_recovery_incidents() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION jo_core.detect_recovery_incidents() TO service_role;
CREATE OR REPLACE FUNCTION team_v4.claim_next_capability_job(p_worker_id text, p_role team_v4.role_name, p_allowed_actions text[], p_lease_seconds integer DEFAULT 300)
 RETURNS TABLE(job_id uuid, role team_v4.role_name, outcome_description text, status team_v4.job_status, current_step_index integer, priority integer, lease_expires_at timestamp with time zone, run_id uuid)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE v_job team_v4.jobs%rowtype; v_run uuid; v_exp timestamptz;
BEGIN
 v_exp:=now()+make_interval(secs=>least(900,greatest(60,p_lease_seconds)));
 SELECT j.* INTO v_job FROM team_v4.jobs j
 JOIN team_v4.job_steps s ON s.job_id=j.job_id AND s.step_index=j.current_step_index
 WHERE j.status IN ('queued','in_progress','stalled') AND NOT j.escalation_flag AND j.role=p_role
 AND (j.no_progress_cycles<j.max_attempts OR j.blocking_reason IS DISTINCT FROM 'external_dependency' OR
 CASE WHEN EXISTS(select 1 from jo_core.capability_registry cr where cr.action=s.action and cr.handler='execution_gate')
 THEN coalesce((jo_core.read_execution_gate(s.action,s.input)->>'ready')::boolean,false) ELSE false END)
 AND j.attempts<j.max_attempts AND s.completed_at IS NULL AND s.action=ANY(p_allowed_actions)
 AND (j.lease_owner IS NULL OR j.lease_expires_at<now())
 AND NOT EXISTS(SELECT 1 FROM team_v4.worker_runs r WHERE r.job_id=j.job_id AND r.ended_at IS NULL AND r.lease_expires_at>now())
 AND (j.status<>'stalled' OR NOT EXISTS(SELECT 1 FROM team_v4.execution_attempts a WHERE a.job_id=j.job_id AND a.finished_at>now()-make_interval(secs=>least(3600,60*power(2,least(greatest(j.attempts,j.no_progress_cycles),5)))::integer)))
 AND (j.dependency_job_id IS NULL OR EXISTS(SELECT 1 FROM team_v4.jobs d WHERE d.job_id=j.dependency_job_id AND d.status='done'))
 ORDER BY j.priority,j.last_progress_at FOR UPDATE OF j SKIP LOCKED LIMIT 1;
 IF NOT FOUND THEN RETURN; END IF;
 UPDATE team_v4.jobs j SET lease_owner=p_worker_id,lease_expires_at=v_exp,status='in_progress',cycle_count=j.cycle_count+1 WHERE j.job_id=v_job.job_id;
 INSERT INTO team_v4.worker_runs(job_id,worker_id,step_index,lease_expires_at) VALUES(v_job.job_id,p_worker_id,v_job.current_step_index,v_exp) RETURNING team_v4.worker_runs.run_id INTO v_run;
 RETURN QUERY SELECT v_job.job_id,v_job.role,v_job.outcome_description,'in_progress'::team_v4.job_status,v_job.current_step_index,v_job.priority,v_exp,v_run;
END $function$;
CREATE OR REPLACE FUNCTION jo_core.run_capability_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE v_worker_id text:='jo-core-cron-'||gen_random_uuid()::text; c record; s record; v_role team_v4.role_name; v_actions text[]; v_handler text; outj jsonb; v_reaped integer; v_quarantined integer; v_count integer:=0;
BEGIN
 SELECT array_agg(action) INTO v_actions FROM jo_core.capability_registry WHERE enabled AND executor='native_sql';
 FOREACH v_role IN ARRAY ARRAY['Jo','Tom','Steve','Mary','Jeff']::team_v4.role_name[] LOOP
 SELECT * INTO c FROM team_v4.claim_next_capability_job(v_worker_id,v_role,v_actions,300) LIMIT 1;
 IF c.job_id IS NULL THEN CONTINUE; END IF;
 SELECT * INTO s FROM team_v4.job_steps WHERE job_id=c.job_id AND step_index=c.current_step_index;
 SELECT handler INTO v_handler FROM jo_core.capability_registry WHERE action=s.action AND enabled AND executor='native_sql';
 BEGIN
 IF v_handler='echo' THEN outj:=jsonb_build_object('echo',s.input,'acceptance_evidence',false);
 ELSIF v_handler='recover' THEN
 v_reaped:=team_v4.reap_expired_leases();
 UPDATE team_v4.jobs SET status='failed',last_error=coalesce(last_error,'Retry budget exhausted'),lease_owner=NULL,lease_expires_at=NULL
 WHERE attempts>=max_attempts AND status IN ('queued','stalled') AND (lease_expires_at IS NULL OR lease_expires_at<now());
 GET DIAGNOSTICS v_quarantined=ROW_COUNT;
 outj:=jsonb_build_object('expired_leases_reaped',v_reaped,'exhausted_jobs_quarantined',v_quarantined,'remaining',jo_core.evidence_snapshot());
 ELSIF v_handler='execution_gate' THEN
 outj:=jo_core.read_execution_gate(s.action,s.input);
 IF coalesce((outj->>'ready')::boolean,false)=false THEN
  PERFORM team_v4.complete_worker_step(c.run_id,c.job_id,c.current_step_index,v_worker_id,'blocked',outj,
    jsonb_build_object('action',s.action,'scope','execution_gate'),outj->>'reason',false,1,'external_dependency',NULL);
  CONTINUE;
 END IF;
 ELSIF v_handler='audit' THEN outj:=jo_core.evidence_snapshot();
 ELSIF v_handler='briefing' THEN outj:=jo_core.generate_briefing(CASE WHEN extract(hour FROM now() AT TIME ZONE 'America/New_York')<12 THEN 'morning' ELSE 'evening' END);
 ELSE RAISE EXCEPTION 'Handler not implemented'; END IF;
 PERFORM team_v4.complete_worker_step(c.run_id,c.job_id,c.current_step_index,v_worker_id,'success',outj,
 jsonb_build_object('action',s.action,'handler',v_handler,'executed_at',now(),'memory',jo_core.recall(lower(v_role::text),'',5)),NULL,(v_handler<>'echo' AND NOT (v_handler='execution_gate' AND s.action IN ('unmapped.tom.research_script','unmapped.tom.media_render'))),1,NULL,NULL);
 INSERT INTO jo_core.events(worker_key,job_id,event_type,detail) VALUES(lower(v_role::text),c.job_id,'capability_executed',jsonb_build_object('action',s.action,'handler',v_handler,'proof',outj));
 v_count:=v_count+1;
 EXCEPTION WHEN OTHERS THEN
 PERFORM team_v4.complete_worker_step(c.run_id,c.job_id,c.current_step_index,v_worker_id,'transient_failure','{}',
 jsonb_build_object('handler',v_handler),SQLERRM,false,1,'unknown_structural',NULL);
 END;
 END LOOP;
 RETURN jsonb_build_object('executed',v_count,'checked_at',now());
END $function$;
CREATE OR REPLACE FUNCTION jo_core.run_team_watchdog()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare reaped int; closed int; synced jsonb; mgr jsonb; pubsync jsonb; autonext jsonb;
prod jsonb; research jsonb; dispatchj jsonb; marymgr jsonb; marymerch jsonb;
stevemgr jsonb; jeffmgr jsonb; verification_sync jsonb; result jsonb;
begin
 perform jo_core.detect_recovery_incidents();
 reaped:=team_v4.reap_expired_leases();
 closed:=team_v4.close_completed_jobs();
 pubsync:=jo_core.sync_published_builds();

 begin autonext:=jo_core.ensure_tom_next_job();
 exception when others then autonext:=jsonb_build_object('created',false,'error',sqlerrm); end;

 begin prod:=jo_core.run_tom_production_handoff_tick();
 exception when others then prod:=jsonb_build_object('claimed',false,'error',sqlerrm); end;

 begin research:=jo_core.run_tom_research_seed_tick();
 exception when others then research:=jsonb_build_object('advanced',false,'error',sqlerrm); end;

 begin dispatchj:=jo_core.run_tom_media_narration_dispatch_tick();
 exception when others then dispatchj:=jsonb_build_object('requested',false,'error',sqlerrm); end;

 begin marymgr:=jo_core.run_mary_manager_cycle();
 exception when others then marymgr:=jsonb_build_object('ran',false,'error',sqlerrm); end;

 begin marymerch:=jo_core.run_mary_merch_cycle();
 exception when others then marymerch:=jsonb_build_object('ran',false,'error',sqlerrm); end;


 begin stevemgr:=jo_core.run_steve_manager_cycle();
 exception when others then stevemgr:=jsonb_build_object('ran',false,'error',sqlerrm); end;

 begin jeffmgr:=jo_core.run_jeff_manager_cycle();
 exception when others then jeffmgr:=jsonb_build_object('ran',false,'error',sqlerrm); end;

 begin verification_sync:=jo_core.refresh_steve_jeff_verification();
 exception when others then verification_sync:=jsonb_build_object('error',sqlerrm); end;

 begin mgr:=jo_core.run_manager_cycle();
 exception when others then mgr:=jsonb_build_object('ran',false,'error',sqlerrm); end;

 -- Synchronize after managers; assignment is not execution evidence.
 synced:=jo_core.sync_worker_state();

 result:=jsonb_build_object(
   'reaped_leases',reaped,'closed_jobs',closed,'published_sync',pubsync,
   'tom_autonext',autonext,'tom_production',prod,'tom_research',research,'tom_dispatch',dispatchj,
   'mary_kdp',marymgr,'mary_merch',marymerch,
   'steve_manager',stevemgr,'jeff_manager',jeffmgr,
   'verification_sync',verification_sync,
   'worker_state',synced,'manager',mgr,'ran_at',now()
 );
 insert into jo_core.events(worker_key,event_type,detail) values('jo','team_watchdog',result);
 return result;
end
$function$;