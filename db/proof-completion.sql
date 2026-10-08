CREATE OR REPLACE FUNCTION team_v4.close_completed_jobs()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE n integer;
BEGIN
 UPDATE team_v4.jobs j SET status='done',last_verified_at=now()
 WHERE j.status IN ('in_progress','verify_pending') AND j.current_step_index>0
 AND NOT EXISTS(SELECT 1 FROM team_v4.job_steps s WHERE s.job_id=j.job_id AND s.step_index=j.current_step_index)
 AND EXISTS(SELECT 1 FROM team_v4.job_steps s WHERE s.job_id=j.job_id AND s.step_index=j.current_step_index-1 AND s.result IN ('success','advanced')
 AND EXISTS(SELECT 1 FROM team_v4.verification_results v WHERE v.job_id=j.job_id AND v.status='passed' AND v.checked_at>=s.completed_at AND v.evidence<>'{}'::jsonb));
 GET DIAGNOSTICS n=ROW_COUNT;RETURN n;
END $$;
REVOKE ALL ON FUNCTION team_v4.close_completed_jobs() FROM PUBLIC,anon,authenticated;

