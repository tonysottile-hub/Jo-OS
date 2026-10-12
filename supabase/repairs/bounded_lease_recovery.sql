-- Preserve terminal/blocked outcomes, retry expired executable work within its
-- existing budget, and retain evidence of each failed execution.
CREATE OR REPLACE FUNCTION team_v4.reap_expired_leases()
RETURNS integer LANGUAGE plpgsql SET search_path TO '' AS $function$
DECLARE j record; n integer := 0; recovered_status team_v4.job_status;
BEGIN
  FOR j IN
    SELECT * FROM team_v4.jobs
    WHERE lease_expires_at < now()
    FOR UPDATE SKIP LOCKED
  LOOP
    recovered_status := j.status;
    IF j.status IN ('queued','in_progress','stalled') THEN
      recovered_status := CASE WHEN j.attempts + 1 >= j.max_attempts
        THEN 'failed'::team_v4.job_status ELSE 'stalled'::team_v4.job_status END;
      UPDATE team_v4.jobs SET status=recovered_status,
        attempts=attempts+1, no_progress_cycles=no_progress_cycles+1,
        last_error=CASE WHEN recovered_status='failed'
          THEN 'Worker lease expired; retry budget exhausted'
          ELSE 'Worker lease expired; bounded retry pending' END,
        lease_owner=NULL, lease_expires_at=NULL
      WHERE job_id=j.job_id;
      INSERT INTO team_v4.execution_attempts
        (job_id,step_index,worker_id,started_at,finished_at,result,error,checkpoint)
      VALUES (j.job_id,j.current_step_index,coalesce(j.lease_owner,'lease-reaper'),
        least(j.lease_expires_at,now()),now(),'transient_failure',
        'Worker lease expired without completion',
        jsonb_build_object('source','scheduled_lease_recovery','attempts',j.attempts+1,
          'max_attempts',j.max_attempts,'resulting_status',recovered_status));
      n := n+1;
    ELSE
      -- A stale lease must never resurrect done/cancelled work, erase an owner
      -- blocker, or rerun a step already awaiting independent verification.
      UPDATE team_v4.jobs SET lease_owner=NULL,lease_expires_at=NULL
      WHERE job_id=j.job_id;
    END IF;
    INSERT INTO jo_core.events(worker_key,job_id,event_type,detail)
    VALUES(lower(j.role::text),j.job_id,'worker_lease_recovered',
      jsonb_build_object('previous_status',j.status,'resulting_status',recovered_status,
        'previous_lease_owner',j.lease_owner,'expired_at',j.lease_expires_at,
        'external_work_verified',false,'owner_escalation_created',false));
  END LOOP;
  UPDATE team_v4.worker_runs SET ended_at=now(),
    outcome='lease_expired',failure_reason='Lease expired before valid worker completion'
  WHERE ended_at IS NULL AND lease_expires_at<now();
  RETURN n;
END $function$;
