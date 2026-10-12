BEGIN;
DO $test$
DECLARE blocked uuid; ready uuid; broken uuid; selected uuid; old_heartbeat timestamptz;
BEGIN
 INSERT INTO team_v4.jobs(role,outcome_description,status,priority,blocking_reason,escalation_flag,escalation_reason)
 VALUES('Jeff','TRANSACTIONAL TEST: owner blocker','blocked_owner',-300,'owner_credential_needed',true,'Synthetic owner-only credential gate') RETURNING job_id INTO blocked;
 INSERT INTO team_v4.jobs(role,outcome_description,status,priority)
 VALUES('Jeff','TRANSACTIONAL TEST: missing step','queued',-200) RETURNING job_id INTO broken;
 INSERT INTO team_v4.jobs(role,outcome_description,status,priority)
 VALUES('Jeff','TRANSACTIONAL TEST: executable audit','queued',-100) RETURNING job_id INTO ready;
 INSERT INTO team_v4.job_steps(job_id,step_index,action,input)
 VALUES(ready,0,'Spot-check external verification evidence for jobs claiming completion; reject unsupported completion claims',
 '{"read_only":true,"no_external_publication":true}');
 SELECT last_heartbeat_at INTO old_heartbeat FROM jo_core.worker_state WHERE worker_key='jeff';
 PERFORM jo_core.sync_worker_state();
 SELECT current_job_id INTO selected FROM jo_core.team_status WHERE worker_key='jeff';
 IF selected IS DISTINCT FROM ready THEN RAISE EXCEPTION 'Executable job not selected over owner/technical blockers'; END IF;
 IF NOT EXISTS(SELECT 1 FROM jo_core.team_status WHERE worker_key='jeff' AND job_status='queued' AND live_state='idle' AND blocking_reason IS NULL)
 THEN RAISE EXCEPTION 'Queued work falsely reported executing'; END IF;
 IF EXISTS(SELECT 1 FROM jo_core.worker_state WHERE worker_key='jeff' AND last_heartbeat_at IS DISTINCT FROM old_heartbeat)
 THEN RAISE EXCEPTION 'Sync manufactured heartbeat'; END IF;
 IF NOT EXISTS(SELECT 1 FROM jo_core.worker_job_diagnostics WHERE job_id=broken AND execution_blocker='missing_current_step' AND derived_state='error')
 THEN RAISE EXCEPTION 'Missing step not diagnosed'; END IF;
 UPDATE team_v4.jobs SET lease_owner='transaction-test',lease_expires_at=now()+interval '5 minutes',status='in_progress' WHERE job_id=ready;
 PERFORM jo_core.sync_worker_state();
 IF NOT EXISTS(SELECT 1 FROM jo_core.team_status WHERE worker_key='jeff' AND current_job_id=ready AND job_status='in_progress' AND live_state='working')
 THEN RAISE EXCEPTION 'Live lease not represented accurately'; END IF;
 IF EXISTS(SELECT 1 FROM jo_core.team_status s JOIN team_v4.jobs j ON j.job_id=s.current_job_id WHERE s.job_status<>j.status::text OR lower(j.role::text)<>s.worker_key)
 THEN RAISE EXCEPTION 'Dashboard combines different jobs'; END IF;
 IF NOT EXISTS(SELECT 1 FROM team_v4.jobs WHERE job_id=blocked AND status='blocked_owner' AND escalation_flag)
 THEN RAISE EXCEPTION 'Owner gate changed'; END IF;
END $test$;
ROLLBACK;