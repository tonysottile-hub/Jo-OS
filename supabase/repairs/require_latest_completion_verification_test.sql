BEGIN;
DO $test$
DECLARE j uuid; s text;
BEGIN
 INSERT INTO team_v4.jobs(role,outcome_description,status,current_step_index)
 VALUES('Jo','ROLLBACK TEST: completion proof freshness','verify_pending',1) RETURNING job_id INTO j;
 INSERT INTO team_v4.job_steps(job_id,step_index,action,result,completed_at)
 VALUES(j,0,'test.fixture','success',now()-interval '2 minutes');
 PERFORM team_v4.close_completed_jobs();
 SELECT status::text INTO s FROM team_v4.jobs WHERE job_id=j;
 IF s<>'verify_pending' THEN RAISE EXCEPTION 'No-proof job closed'; END IF;
 INSERT INTO team_v4.verification_results(job_id,verifier_id,mechanism,status,evidence,checked_at)
 VALUES(j,'rollback-test','rollback-test','passed','{"external_work_verified":true,"delivery_verified":true}',now()-interval '1 minute');
 INSERT INTO team_v4.verification_results(job_id,verifier_id,mechanism,status,evidence,checked_at)
 VALUES(j,'rollback-test','rollback-test','failed','{"reason":"newer failure"}',now());
 PERFORM team_v4.close_completed_jobs();
 SELECT status::text INTO s FROM team_v4.jobs WHERE job_id=j;
 IF s<>'verify_pending' THEN RAISE EXCEPTION 'Stale pass overrode newer failure'; END IF;
 -- Same timestamp tie must use the newer verification ID.
 INSERT INTO team_v4.verification_results(job_id,verifier_id,mechanism,status,evidence,checked_at)
 VALUES(j,'rollback-test','rollback-test','passed','{"external_work_verified":true,"delivery_verified":true}',now());
 PERFORM team_v4.close_completed_jobs();
 SELECT status::text INTO s FROM team_v4.jobs WHERE job_id=j;
 IF s<>'done' THEN RAISE EXCEPTION 'Fresh valid pass rejected'; END IF;
END $test$;
ROLLBACK;
SELECT 'PASS: no proof denied, stale pass after failure denied, latest valid pass accepted, timestamp tie handled; all fixtures rolled back' AS result;