CREATE OR REPLACE FUNCTION jo_core.verify_internal_checkpoints()
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE j record; s record; v_handler text; valid boolean; n integer:=0; proof jsonb;
BEGIN
 FOR j IN SELECT * FROM team_v4.jobs WHERE role='Jo' AND status='verify_pending' FOR UPDATE SKIP LOCKED LOOP
 SELECT * INTO s FROM team_v4.job_steps WHERE job_id=j.job_id AND step_index=j.current_step_index-1;
 SELECT handler INTO v_handler FROM jo_core.capability_registry WHERE action=s.action AND executor='native_sql' AND enabled;
 valid:=false;
 IF s.result='success' AND s.completed_at IS NOT NULL THEN
 IF v_handler='recover' THEN valid:=s.output ? 'expired_leases_reaped' AND NOT EXISTS(SELECT 1 FROM team_v4.jobs WHERE lease_expires_at<now()) AND NOT EXISTS(SELECT 1 FROM team_v4.worker_runs WHERE ended_at IS NULL AND lease_expires_at<now());
 ELSIF v_handler='audit' THEN valid:=jsonb_typeof(s.output->'workers')='array' AND jsonb_array_length(s.output->'workers')=5;
 ELSIF v_handler='briefing' THEN valid:=EXISTS(SELECT 1 FROM jo_core.briefings b WHERE b.briefing_id=(s.output->>'briefing_id')::bigint AND b.payload ? 'verified_outcomes');
 END IF;
 END IF;
 IF valid THEN
 proof:=jsonb_build_object('scope','internal_database_action_only','action',s.action,'step_index',s.step_index,'checked_at',now(),'external_work_verified',false,'delivery_verified',false);
 INSERT INTO team_v4.verification_results(job_id,verifier_id,mechanism,status,evidence,verification_target)
 VALUES(j.job_id,'independent-db-checkpoint-verifier','live_database_target_check','passed',proof,'internal_step_'||s.step_index);
 UPDATE team_v4.jobs SET status='in_progress',last_verified_at=now() WHERE job_id=j.job_id;
 n:=n+1;
 END IF;
 END LOOP;
 PERFORM team_v4.close_completed_jobs();
 RETURN jsonb_build_object('internal_steps_verified',n);
END $$;
REVOKE ALL ON FUNCTION jo_core.verify_internal_checkpoints() FROM PUBLIC,anon,authenticated;

