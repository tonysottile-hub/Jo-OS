-- Applied and verified in production 2026-10-15.
-- Preserve publication gate; only passed perceptual reviews qualify for handoff.
-- Blocked attempts do not count as progress; retry delay uses no-progress cycles.
BEGIN;
CREATE OR REPLACE FUNCTION jo_core.run_manager_cycle()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o record; handoff jsonb; ready_count int; active_jobs int; result jsonb;
active_prod int; qa_blocked int; storage_blocked int; sidelined int; other_unfinished int;
next_build record; next_action text;
begin
 select * into o from jo_core.objectives
 where worker_key='tom' and objective_type='backlog_catchup' and status='active'
 for update skip locked limit 1;
 if o.objective_id is null then return jsonb_build_object('ran',false,'reason','no_active_objective'); end if;

 select count(*) into ready_count
 from public.video_builds vb
 where vb.publish_job_id is null
   and vb.status='stored'
   and vb.blocker_stage is null
   and vb.output_storage_path is not null
   and coalesce((vb.asset_manifest->>'publish_authorized')::boolean,false)=true
   and vb.asset_manifest->'perceptual_review'->>'passed'='true'
   and exists(select 1 from storage.objects so where so.bucket_id='publisher-videos' and so.name=vb.output_storage_path);

 if ready_count>0 then handoff:=jo_core.run_tom_build_handoff_tick();
 else handoff:=jsonb_build_object('claimed',false,'reason','no_verified_stored_build'); end if;

 select count(*) into active_prod
 from public.video_builds vb
 where vb.publish_job_id is null
   and vb.status not in ('published','failed','stored','handed_off')
   and vb.blocker_stage is null
   and lower(coalesce(vb.topic,'')) not like '%road reflector%';

 select count(*) into qa_blocked
 from public.video_builds vb
 where vb.publish_job_id is null and vb.status='blocked'
   and vb.blocker_stage in ('visual_qc','audio_qc','technical_qc','qa');

 select count(*) into storage_blocked
 from public.video_builds vb
 where vb.publish_job_id is null and vb.status='blocked' and vb.blocker_stage='storage';

 select count(*) into sidelined
 from public.video_builds vb
 where vb.publish_job_id is null and lower(coalesce(vb.topic,'')) like '%road reflector%';

 select count(*) into other_unfinished
 from public.video_builds vb
 where vb.publish_job_id is null
   and vb.status not in ('published','failed')
   and vb.blocker_stage is not null
   and vb.blocker_stage not in ('visual_qc','audio_qc','technical_qc','qa','storage')
   and lower(coalesce(vb.topic,'')) not like '%road reflector%';

 select vb.id,vb.topic,vb.title,vb.status,vb.blocker_stage,vb.output_storage_path,
        vb.asset_manifest->>'production_stage' as production_stage
 into next_build
 from public.video_builds vb
 where vb.publish_job_id is null
   and vb.status not in ('published','failed','stored','handed_off')
   and vb.blocker_stage is null
   and lower(coalesce(vb.topic,'')) not like '%road reflector%'
 order by case when vb.asset_manifest->>'source'='jo_os_natural_assignment' then 0 else 1 end, vb.updated_at desc
 limit 1;

 if next_build.id is not null then
   next_action:=case
    when next_build.status='qc_passed' and next_build.output_storage_path is null then 'ingest_verified_render'
    when next_build.output_storage_path is null and coalesce(next_build.production_stage,'')='media_and_narration' then 'produce_media_and_narration'
    when next_build.output_storage_path is null then 'advance_production'
    else 'verify_artifact_then_qa'
   end;
 else next_action:='recover_blocked_backlog'; end if;

 select count(*) into active_jobs
 from team_v4.jobs
 where role='Tom' and status in ('queued','in_progress','verify_pending');

 result:=jsonb_build_object(
  'objective_id',o.objective_id,
  'ready_to_publish',ready_count,
  'publish_handoff',handoff,
  'build_classes',jsonb_build_object(
    'active_production',active_prod,
    'qa_blocked',qa_blocked,
    'storage_blocked',storage_blocked,
    'sidelined',sidelined,
    'other_blocked',other_unfinished
  ),
  'next_build',case when next_build.id is null then null else jsonb_build_object(
    'id',next_build.id,'topic',next_build.topic,'title',next_build.title,
    'status',next_build.status,'production_stage',next_build.production_stage,
    'blocker_stage',next_build.blocker_stage
  ) end,
  'next_action',next_action,
  'active_tom_jobs',active_jobs,
  'ran_at',now()
 );

 update jo_core.objectives
 set last_run_at=now(),next_run_at=date_trunc('hour',now())+interval '1 hour',updated_at=now()
 where objective_id=o.objective_id;

 insert into jo_core.events(worker_key,event_type,detail) values('jo','manager_cycle',result);
 insert into jo_core.events(worker_key,event_type,detail) values('tom','catchup_cycle',result);
 return result;
end
$function$
;

CREATE OR REPLACE FUNCTION jo_core.run_tom_build_handoff_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare b record; q record; out jsonb;
begin
 select vb.* into b
 from public.video_builds vb
 where vb.publish_job_id is null
   and vb.status='stored'
   and vb.blocker_stage is null
   and vb.output_storage_path is not null
   and coalesce((vb.asset_manifest->>'publish_authorized')::boolean,false)=true
   and vb.asset_manifest->'perceptual_review'->>'passed'='true'
   and exists(select 1 from storage.objects so where so.bucket_id='publisher-videos' and so.name=vb.output_storage_path)
 order by vb.updated_at asc
 for update skip locked limit 1;

 if b.id is null then return jsonb_build_object('claimed',false,'reason','no_verified_stored_build'); end if;

 select * into q from public.video_build_logs
 where build_id=b.id and stage='qa_passed'
 order by created_at desc limit 1;

 if q.build_id is null then
   return jsonb_build_object('claimed',true,'queued',false,'build_id',b.id,'reason','explicit QA evidence missing');
 end if;

 out:=jo_core.enqueue_tom_youtube_publish(b.output_storage_path,b.title,coalesce(b.title,b.topic),b.kind);
 update public.video_builds
 set status='handed_off',
     publish_job_id=(out->>'publish_job_id')::uuid,
     updated_at=now()
 where id=b.id;

 insert into public.video_build_logs(build_id,stage,detail)
 values(b.id,'jo_core_youtube_handoff',out||jsonb_build_object('source_qa_stage',q.stage));

 insert into jo_core.events(worker_key,event_type,detail)
 values('tom','build_handed_to_youtube',jsonb_build_object('build_id',b.id,'publish',out));

 return jsonb_build_object('claimed',true,'queued',true,'build_id',b.id,'publish',out);
end
$function$
;

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
END $function$
;

CREATE OR REPLACE FUNCTION team_v4.finish_worker_run(p_run_id uuid, p_tool_calls integer DEFAULT 0, p_checkpoint boolean DEFAULT false, p_verification boolean DEFAULT false, p_blocker boolean DEFAULT false, p_outcome text DEFAULT NULL::text, p_failure_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'team_v4', 'public'
AS $function$
declare v_job uuid; v_progress boolean;
begin
 select job_id into v_job from team_v4.worker_runs where run_id=p_run_id for update;
 if v_job is null then raise exception 'unknown run'; end if;
 v_progress:=p_checkpoint or p_verification;
 update team_v4.worker_runs set ended_at=now(),tool_calls_made=greatest(0,p_tool_calls),checkpoint_written=p_checkpoint,verification_written=p_verification,blocker_written=p_blocker,outcome=p_outcome,failure_reason=case when v_progress then p_failure_reason else coalesce(p_failure_reason,'worker cycle ended without checkpoint, verification, or structured blocker') end where run_id=p_run_id;
 if v_progress then update team_v4.jobs set lease_owner=null,lease_expires_at=null,no_progress_cycles=0,last_progress_at=now() where job_id=v_job;
 elsif p_blocker then
 update team_v4.jobs set lease_owner=null,lease_expires_at=null,no_progress_cycles=no_progress_cycles+1 where job_id=v_job;
 else update team_v4.jobs set lease_owner=null,lease_expires_at=null,no_progress_cycles=no_progress_cycles+1,last_error='worker cycle ended without progress',status=case when no_progress_cycles+1>=2 then 'stalled'::team_v4.job_status else status end,escalation_flag=case when no_progress_cycles+1>=2 then true else escalation_flag end,escalation_reason=case when no_progress_cycles+1>=2 then 'Loop breaker: two worker cycles ended without checkpoint, verification, or structured blocker.' else escalation_reason end where job_id=v_job;
 end if;
end $function$
;
COMMIT;
