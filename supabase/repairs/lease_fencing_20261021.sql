-- Lease fencing and bounded generic claims; preserves business verification gates.
CREATE OR REPLACE FUNCTION team_v4.complete_worker_step(p_run_id uuid, p_job_id uuid, p_step_index integer, p_worker_id text, p_result team_v4.attempt_result, p_output jsonb DEFAULT '{}'::jsonb, p_checkpoint jsonb DEFAULT '{}'::jsonb, p_error text DEFAULT NULL::text, p_verify_pending boolean DEFAULT false, p_tool_calls integer DEFAULT 1, p_blocking_reason team_v4.blocking_reason DEFAULT NULL::team_v4.blocking_reason, p_escalation_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'team_v4', 'public'
AS $function$
declare
  v_run team_v4.worker_runs%rowtype;
  v_owner_blocker boolean;
begin
  -- Lock job before run, matching the lease reaper. Fence stale workers.
  perform 1 from team_v4.jobs j
  where j.job_id=p_job_id and j.lease_owner=p_worker_id
    and j.lease_expires_at>clock_timestamp() and j.current_step_index=p_step_index
    and j.status='in_progress'
  for update;
  if not found then raise exception 'stale_or_invalid_job_lease'; end if;
  select * into v_run
  from team_v4.worker_runs
  where run_id=p_run_id
    and job_id=p_job_id
    and step_index=p_step_index
    and ended_at is null
    and lease_expires_at>clock_timestamp()
  for update;

  if not found then
    raise exception 'open worker run not found for run %, job %, step %', p_run_id, p_job_id, p_step_index;
  end if;

  if p_worker_id is not null and v_run.worker_id <> p_worker_id then
    raise exception 'worker mismatch for run %', p_run_id;
  end if;

  insert into team_v4.execution_attempts(
    job_id, step_index, worker_id, started_at, finished_at, result, error, checkpoint
  ) values (
    p_job_id, p_step_index, coalesce(p_worker_id,v_run.worker_id),
    v_run.started_at, now(), p_result, p_error, coalesce(p_checkpoint,'{}'::jsonb)
  );

  update team_v4.job_steps
  set result=p_result,
      output=coalesce(p_output,'{}'::jsonb),
      completed_at=case when p_result in ('advanced','success') then now() else null end
  where job_id=p_job_id and step_index=p_step_index;

  if p_result in ('advanced','success') then
    update team_v4.jobs
    set current_step_index=greatest(current_step_index,p_step_index+1),
        attempts=0,
        last_error=null,
        status=case when p_verify_pending then 'verify_pending'::team_v4.job_status
                    else 'in_progress'::team_v4.job_status end,
        blocking_reason=null,
        escalation_flag=false,
        escalation_reason=null
    where job_id=p_job_id;

    perform team_v4.finish_worker_run(
      p_run_id,
      greatest(coalesce(p_tool_calls,0),0),
      true,false,false,
      'checkpoint_written',
      null
    );

  elsif p_result in ('blocked','structural_failure') then
    v_owner_blocker := p_blocking_reason in (
      'owner_credential_needed'::team_v4.blocking_reason,
      'owner_decision_needed'::team_v4.blocking_reason,
      'owner_approval_needed'::team_v4.blocking_reason
    );

    update team_v4.jobs
    set status=case when v_owner_blocker then 'blocked_owner'::team_v4.job_status
                    else 'stalled'::team_v4.job_status end,
        last_error=coalesce(p_error,p_result::text),
        blocking_reason=p_blocking_reason,
        escalation_flag=v_owner_blocker,
        escalation_reason=case when v_owner_blocker
          then coalesce(p_escalation_reason,p_error,'Specific owner action required')
          else null end
    where job_id=p_job_id;

    if v_owner_blocker then
      insert into team_v4.escalations(job_id,reason,specific_question)
      values(
        p_job_id,
        coalesce(p_escalation_reason,p_error,'Specific owner action required'),
        coalesce(p_escalation_reason,p_error,'What exact owner action is required?')
      );
    end if;

    perform team_v4.finish_worker_run(
      p_run_id,
      greatest(coalesce(p_tool_calls,0),0),
      false,false,true,
      'structured_blocker_written',
      p_error
    );

  else
    update team_v4.jobs
    set status='stalled',
        attempts=attempts+1,
        last_error=coalesce(p_error,p_result::text),
        blocking_reason=p_blocking_reason
    where job_id=p_job_id;

    perform team_v4.finish_worker_run(
      p_run_id,
      greatest(coalesce(p_tool_calls,0),0),
      false,false,false,
      p_result::text,
      coalesce(p_error,p_result::text)
    );
  end if;

  return jsonb_build_object(
    'ok',true,
    'run_id',p_run_id,
    'job_id',p_job_id,
    'step_index',p_step_index,
    'result',p_result
  );
end;
$function$;

CREATE OR REPLACE FUNCTION team_v4.finish_worker_run(p_run_id uuid, p_tool_calls integer DEFAULT 0, p_checkpoint boolean DEFAULT false, p_verification boolean DEFAULT false, p_blocker boolean DEFAULT false, p_outcome text DEFAULT NULL::text, p_failure_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'team_v4', 'public'
AS $function$
declare v_job uuid; v_progress boolean;
begin
 perform 1 from team_v4.jobs j join team_v4.worker_runs r on r.job_id=j.job_id
 where r.run_id=p_run_id and r.ended_at is null
   and r.lease_expires_at>clock_timestamp() and j.lease_expires_at>clock_timestamp()
   and j.lease_owner=r.worker_id
 for update of j;
 if not found then raise exception 'stale_or_invalid_job_lease'; end if;
 select job_id into v_job from team_v4.worker_runs where run_id=p_run_id for update;
 if v_job is null then raise exception 'unknown run'; end if;
 v_progress:=p_checkpoint or p_verification;
 update team_v4.worker_runs set ended_at=now(),tool_calls_made=greatest(0,p_tool_calls),checkpoint_written=p_checkpoint,verification_written=p_verification,blocker_written=p_blocker,outcome=p_outcome,failure_reason=case when v_progress then p_failure_reason else coalesce(p_failure_reason,'worker cycle ended without checkpoint, verification, or structured blocker') end where run_id=p_run_id;
 if v_progress then update team_v4.jobs set lease_owner=null,lease_expires_at=null,no_progress_cycles=0,last_progress_at=now() where job_id=v_job;
 elsif p_blocker then
 update team_v4.jobs set lease_owner=null,lease_expires_at=null,no_progress_cycles=no_progress_cycles+1 where job_id=v_job;
 else update team_v4.jobs set lease_owner=null,lease_expires_at=null,no_progress_cycles=no_progress_cycles+1,last_error='worker cycle ended without progress',status=case when no_progress_cycles+1>=2 then 'stalled'::team_v4.job_status else status end,escalation_flag=case when no_progress_cycles+1>=2 then true else escalation_flag end,escalation_reason=case when no_progress_cycles+1>=2 then 'Loop breaker: two worker cycles ended without checkpoint, verification, or structured blocker.' else escalation_reason end where job_id=v_job;
 end if;
end $function$;

CREATE OR REPLACE FUNCTION team_v4.claim_next_job(p_worker_id text, p_role team_v4.role_name DEFAULT NULL::team_v4.role_name, p_lease_seconds integer DEFAULT 300)
 RETURNS TABLE(job_id uuid, role team_v4.role_name, outcome_description text, status team_v4.job_status, current_step_index integer, priority integer, lease_expires_at timestamp with time zone, run_id uuid)
 LANGUAGE plpgsql
 SET search_path TO 'team_v4', 'public'
AS $function$
declare v_job team_v4.jobs%rowtype; v_run uuid; v_exp timestamptz;
begin
 v_exp:=now()+make_interval(secs=>least(900,greatest(60,p_lease_seconds)));
 select * into v_job from team_v4.jobs j where j.status in ('queued','in_progress','stalled') and j.escalation_flag=false and j.attempts<j.max_attempts
 and exists(select 1 from team_v4.job_steps s where s.job_id=j.job_id and s.step_index=j.current_step_index and s.completed_at is null)
 and not exists(select 1 from team_v4.worker_runs r where r.job_id=j.job_id and r.ended_at is null and r.lease_expires_at>now())
 and (j.status<>'stalled' or not exists(select 1 from team_v4.execution_attempts a where a.job_id=j.job_id and a.finished_at>now()-make_interval(secs=>least(3600,60*power(2,least(greatest(j.attempts,j.no_progress_cycles),5)))::integer))) and (p_role is null or j.role=p_role) and (j.lease_owner is null or j.lease_expires_at<now()) and (j.dependency_job_id is null or exists(select 1 from team_v4.jobs d where d.job_id=j.dependency_job_id and d.status='done')) order by j.priority,j.last_progress_at for update skip locked limit 1;
 if not found then return; end if;
 update team_v4.jobs j set lease_owner=p_worker_id,lease_expires_at=v_exp,status='in_progress',cycle_count=j.cycle_count+1 where j.job_id=v_job.job_id;
 insert into team_v4.worker_runs(job_id,worker_id,step_index,lease_expires_at) values(v_job.job_id,p_worker_id,v_job.current_step_index,v_exp) returning team_v4.worker_runs.run_id into v_run;
 return query select v_job.job_id,v_job.role,v_job.outcome_description,'in_progress'::team_v4.job_status,v_job.current_step_index,v_job.priority,v_exp,v_run;
end $function$;
