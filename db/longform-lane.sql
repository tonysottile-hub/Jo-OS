CREATE OR REPLACE FUNCTION jo_core.run_tom_longform_manager_cycle()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o record; v_job uuid; v_cmd uuid; active_long int; result jsonb;
begin
 select * into o from jo_core.objectives
 where worker_key='tom' and objective_type='longform_backlog_catchup' and status='active'
 for update skip locked limit 1;
 if o.objective_id is null then return jsonb_build_object('ran',false,'reason','no_active_longform_objective'); end if;

 select count(*) into active_long
 from public.video_builds
 where kind='long' and publish_job_id is null
 and status not in ('published','failed','handed_off')
 and blocker_stage is null;

 if active_long=0 and not exists(select 1 from team_v4.jobs j join team_v4.job_steps s using(job_id) where j.role='Tom' and j.status in ('queued','in_progress','stalled') and s.action='unmapped.tom.production_handoff' and lower(s.input->>'instruction') like '%longform recovery lane%') then
   v_cmd:=gen_random_uuid();
   v_job:=jo_core.enqueue_tom_unmapped_assignment(
     v_cmd,
     'LONGFORM RECOVERY LANE ONLY. Create and advance the oldest genuinely missing Unmapped America Monday/Wednesday/Friday long-form video. kind must be long. Do not create a Short. Reconcile existing public/publish evidence first to prevent duplicates. Use the established forgotten America/lost places direction, research and fact-check, then production, render, QA, publish, and public YouTube verification. This lane is independent of daily Shorts.'
   );
 else
   v_job:=null;
 end if;

 update jo_core.objectives
 set last_run_at=now(), next_run_at=date_trunc('hour',now())+interval '1 hour', updated_at=now()
 where objective_id=o.objective_id;

 result:=jsonb_build_object('ran',true,'objective_id',o.objective_id,'active_long_builds',active_long,'created_job_id',v_job,'command_id',v_cmd,'ran_at',now());
 insert into jo_core.events(worker_key,job_id,event_type,detail)
 values('tom',v_job,'longform_manager_cycle',result);
 return result;
end $function$;
