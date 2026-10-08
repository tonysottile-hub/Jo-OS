-- Recovery foundation. Apply in a transaction; tests use ROLLBACK first.
CREATE TABLE IF NOT EXISTS jo_core.memory_revisions (
 memory_key text NOT NULL, revision integer NOT NULL CHECK(revision>0),
 content text NOT NULL CHECK(length(content) BETWEEN 1 AND 20000),
 worker_key text NOT NULL CHECK(worker_key IN ('jo','tom','steve','mary','jeff','all')),
 source text NOT NULL, source_at timestamptz NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT now(),
 correction_reason text, PRIMARY KEY(memory_key,revision)
);
ALTER TABLE jo_core.memory_revisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON jo_core.memory_revisions FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT ON jo_core.memory_revisions TO service_role;
CREATE OR REPLACE FUNCTION jo_core.remember(p_key text,p_content text,p_worker text,p_source text,p_source_at timestamptz,p_expected_revision integer DEFAULT 0,p_correction text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_revision integer; v_time timestamptz;
BEGIN
 IF length(trim(p_source))=0 OR p_source_at>now()+interval '5 minutes' THEN RAISE EXCEPTION 'Invalid provenance'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_key,0));
 SELECT revision,source_at INTO v_revision,v_time FROM jo_core.memory_revisions WHERE memory_key=p_key ORDER BY revision DESC LIMIT 1;
 IF coalesce(v_revision,0)<>p_expected_revision THEN RAISE EXCEPTION 'Memory revision conflict'; END IF;
 IF v_revision IS NOT NULL AND (p_source_at<v_time OR nullif(trim(p_correction),'') IS NULL) THEN RAISE EXCEPTION 'Correction requires current provenance and reason'; END IF;
 INSERT INTO jo_core.memory_revisions(memory_key,revision,content,worker_key,source,source_at,correction_reason)
 VALUES(p_key,coalesce(v_revision,0)+1,p_content,p_worker,p_source,p_source_at,p_correction);
 RETURN jsonb_build_object('key',p_key,'revision',coalesce(v_revision,0)+1,'persisted',true);
END $$;
CREATE OR REPLACE FUNCTION jo_core.recall(p_worker text,p_query text DEFAULT '',p_limit integer DEFAULT 10)
RETURNS jsonb LANGUAGE sql STABLE SET search_path='' AS $$
 WITH latest AS (SELECT DISTINCT ON(memory_key) * FROM jo_core.memory_revisions ORDER BY memory_key,revision DESC)
 SELECT coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) FROM (
 SELECT memory_key,revision,content,source,source_at,recorded_at,correction_reason,
 'instruction_context_only_live_operational_records_take_precedence'::text AS authority
 FROM latest WHERE worker_key IN ('all',p_worker)
 AND (p_query='' OR to_tsvector('english',memory_key||' '||content) @@ websearch_to_tsquery('english',p_query))
 ORDER BY source_at DESC LIMIT least(greatest(p_limit,1),50)) r
$$;
REVOKE ALL ON FUNCTION jo_core.remember(text,text,text,text,timestamptz,integer,text),jo_core.recall(text,text,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION jo_core.remember(text,text,text,text,timestamptz,integer,text),jo_core.recall(text,text,integer) TO service_role;

CREATE TABLE IF NOT EXISTS jo_core.capability_registry (
 action text PRIMARY KEY, handler text, executor text NOT NULL,
 enabled boolean NOT NULL DEFAULT false, risk text NOT NULL DEFAULT 'review_required',
 reason text NOT NULL, updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE jo_core.capability_registry ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON jo_core.capability_registry FROM PUBLIC,anon,authenticated;
GRANT SELECT ON jo_core.capability_registry TO service_role;
INSERT INTO jo_core.capability_registry(action,executor,reason)
SELECT DISTINCT action,'unimplemented','No executable handler; natural-language action must be translated and validated before execution'
FROM team_v4.job_steps ON CONFLICT(action) DO NOTHING;
INSERT INTO jo_core.capability_registry(action,handler,executor,enabled,risk,reason) VALUES
('jo_core.echo','echo','native_sql',true,'test','Diagnostic only; never production acceptance'),
('Attempt safe recovery/reassignment; create a specific escalation only when Tony action is genuinely unavoidable','recover','native_sql',true,'internal','Reap expired leases; quarantine exhausted attempts; checkpoint actual mutations'),
('Spot-check external verification evidence for jobs claiming completion; reject unsupported completion claims','audit','native_sql',true,'read_only','Inspect evidence records; never assert independent destination verification'),
('Produce the next 8 AM/8 PM briefing view from persisted V4 evidence only; briefing must not trigger worker re-audits','briefing','native_sql',true,'internal','Legacy action maps to current 7:30 Eastern evidence briefing'),
('jo_core.evidence_briefing','briefing','native_sql',true,'internal','Generate evidence briefing without claiming delivery'),
('unmapped.tom.production_handoff','jo_core.run_tom_production_handoff_tick','dedicated_cron',true,'internal','Existing claimed production adapter; QA remains required'),
('unmapped.tom.verify_youtube','jo_core.run_tom_youtube_verify_tick','dedicated_cron',true,'read_only','Existing publisher evidence adapter; destination verification tracked separately'),
('cigar30.mary.assignment','jo_core.run_mary_assignment_tick','dedicated_cron',true,'internal','Assignment preparation only'),
('cigar30.mary.artifact','jo_core.run_mary_artifact_tick','dedicated_cron',true,'internal','Manifest preparation only; does not establish artwork completion')
ON CONFLICT(action) DO UPDATE SET handler=excluded.handler,executor=excluded.executor,enabled=excluded.enabled,risk=excluded.risk,reason=excluded.reason,updated_at=now();

CREATE OR REPLACE FUNCTION team_v4.claim_next_capability_job(p_worker_id text,p_role team_v4.role_name,p_allowed_actions text[],p_lease_seconds integer DEFAULT 300)
RETURNS TABLE(job_id uuid,role team_v4.role_name,outcome_description text,status team_v4.job_status,current_step_index integer,priority integer,lease_expires_at timestamptz,run_id uuid)
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_job team_v4.jobs%rowtype; v_run uuid; v_exp timestamptz;
BEGIN
 v_exp:=now()+make_interval(secs=>least(900,greatest(60,p_lease_seconds)));
 SELECT j.* INTO v_job FROM team_v4.jobs j
 JOIN team_v4.job_steps s ON s.job_id=j.job_id AND s.step_index=j.current_step_index
 WHERE j.status IN ('queued','in_progress','stalled') AND NOT j.escalation_flag AND j.role=p_role
 AND j.attempts<j.max_attempts AND s.completed_at IS NULL AND s.action=ANY(p_allowed_actions)
 AND (j.lease_owner IS NULL OR j.lease_expires_at<now())
 AND NOT EXISTS(SELECT 1 FROM team_v4.worker_runs r WHERE r.job_id=j.job_id AND r.ended_at IS NULL AND r.lease_expires_at>now())
 AND (j.status<>'stalled' OR NOT EXISTS(SELECT 1 FROM team_v4.execution_attempts a WHERE a.job_id=j.job_id AND a.finished_at>now()-make_interval(secs=>least(3600,60*power(2,least(j.attempts,5)))::integer)))
 AND (j.dependency_job_id IS NULL OR EXISTS(SELECT 1 FROM team_v4.jobs d WHERE d.job_id=j.dependency_job_id AND d.status='done'))
 ORDER BY j.priority,j.last_progress_at FOR UPDATE OF j SKIP LOCKED LIMIT 1;
 IF NOT FOUND THEN RETURN; END IF;
 UPDATE team_v4.jobs j SET lease_owner=p_worker_id,lease_expires_at=v_exp,status='in_progress',cycle_count=j.cycle_count+1 WHERE j.job_id=v_job.job_id;
 INSERT INTO team_v4.worker_runs(job_id,worker_id,step_index,lease_expires_at) VALUES(v_job.job_id,p_worker_id,v_job.current_step_index,v_exp) RETURNING team_v4.worker_runs.run_id INTO v_run;
 RETURN QUERY SELECT v_job.job_id,v_job.role,v_job.outcome_description,'in_progress'::team_v4.job_status,v_job.current_step_index,v_job.priority,v_exp,v_run;
END $$;

CREATE OR REPLACE FUNCTION jo_core.evidence_snapshot()
RETURNS jsonb LANGUAGE sql STABLE SET search_path='' AS $$
 SELECT jsonb_build_object('checked_at',now(),'proof_standard','Heartbeat and assignment are not completion',
 'workers',(SELECT jsonb_agg(jsonb_build_object('worker',w.worker_key,
 'jobs',(SELECT coalesce(jsonb_agg(x),'[]'::jsonb) FROM (SELECT j.job_id,j.status,j.outcome_description,j.last_progress_at,j.last_verified_at,j.blocking_reason,j.last_error FROM team_v4.jobs j WHERE lower(j.role::text)=w.worker_key ORDER BY j.updated_at DESC LIMIT 8)x),
 'verification',(SELECT coalesce(jsonb_agg(x),'[]'::jsonb) FROM (SELECT v.job_id,v.verifier_id,v.mechanism,v.status,v.evidence,v.checked_at FROM team_v4.verification_results v JOIN team_v4.jobs j USING(job_id) WHERE lower(j.role::text)=w.worker_key ORDER BY v.checked_at DESC LIMIT 5)x)
 ) ORDER BY w.worker_key) FROM jo_core.workers w WHERE w.active),
 'unsupported_actions',(SELECT coalesce(jsonb_agg(x),'[]'::jsonb) FROM (SELECT j.role,s.action,count(*) AS jobs FROM team_v4.jobs j JOIN team_v4.job_steps s ON s.job_id=j.job_id AND s.step_index=j.current_step_index LEFT JOIN jo_core.capability_registry r ON r.action=s.action WHERE j.status NOT IN ('done','failed') AND NOT coalesce(r.enabled,false) GROUP BY j.role,s.action)x),
 'launch',(SELECT jsonb_agg(jsonb_build_object('stage',stage_key,'status',status,'error',last_error,'verified_at',verified_at)) FROM jo_core.steve_launch_stages),
 'delivery','Stored briefing is not proof of delivery')
$$;
CREATE OR REPLACE FUNCTION jo_core.run_capability_tick()
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE c record; s record; v_role team_v4.role_name; v_actions text[]; v_handler text; outj jsonb; v_reaped integer; v_quarantined integer; v_count integer:=0;
BEGIN
 SELECT array_agg(action) INTO v_actions FROM jo_core.capability_registry WHERE enabled AND executor='native_sql';
 FOREACH v_role IN ARRAY ARRAY['Jo','Tom','Steve','Mary','Jeff']::team_v4.role_name[] LOOP
 SELECT * INTO c FROM team_v4.claim_next_capability_job('jo-core-cron',v_role,v_actions,300) LIMIT 1;
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
 ELSIF v_handler='audit' THEN outj:=jo_core.evidence_snapshot();
 ELSIF v_handler='briefing' THEN outj:=jo_core.generate_briefing(CASE WHEN extract(hour FROM now() AT TIME ZONE 'America/New_York')<12 THEN 'morning' ELSE 'evening' END);
 ELSE RAISE EXCEPTION 'Handler not implemented'; END IF;
 PERFORM team_v4.complete_worker_step(c.run_id,c.job_id,c.current_step_index,'jo-core-cron','success',outj,
 jsonb_build_object('action',s.action,'handler',v_handler,'executed_at',now(),'memory',jo_core.recall(lower(v_role::text),'',5)),NULL,v_handler<>'echo',1,NULL,NULL);
 INSERT INTO jo_core.events(worker_key,job_id,event_type,detail) VALUES(lower(v_role::text),c.job_id,'capability_executed',jsonb_build_object('action',s.action,'handler',v_handler,'proof',outj));
 v_count:=v_count+1;
 EXCEPTION WHEN OTHERS THEN
 PERFORM team_v4.complete_worker_step(c.run_id,c.job_id,c.current_step_index,'jo-core-cron','transient_failure','{}',
 jsonb_build_object('handler',v_handler),SQLERRM,false,1,'unknown_structural',NULL);
 END;
 END LOOP;
 RETURN jsonb_build_object('executed',v_count,'checked_at',now());
END $$;

CREATE OR REPLACE FUNCTION public.jo_core_run_capabilities()
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$ SELECT jo_core.run_capability_tick() $$;
REVOKE ALL ON FUNCTION public.jo_core_run_capabilities() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.jo_core_run_capabilities() TO service_role;
REVOKE ALL ON FUNCTION jo_core.run_capability_tick(),jo_core.evidence_snapshot() FROM PUBLIC,anon,authenticated;
ALTER FUNCTION jo_core.active_worker_policies(text) SET search_path='';
ALTER FUNCTION jo_core.failure_recurrence_level(integer) SET search_path='';

DO $$ DECLARE t record; BEGIN
 FOR t IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('jo_core','team_v4') AND c.relkind='r' AND NOT c.relrowsecurity LOOP
 IF EXISTS(SELECT 1 FROM information_schema.role_table_grants g WHERE g.table_schema=t.nspname AND g.table_name=t.relname AND g.grantee IN ('anon','authenticated','PUBLIC')) THEN
 RAISE EXCEPTION 'Client policy review required for %.%',t.nspname,t.relname;
 END IF;
 EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY',t.nspname,t.relname);
 END LOOP;
END $$;

