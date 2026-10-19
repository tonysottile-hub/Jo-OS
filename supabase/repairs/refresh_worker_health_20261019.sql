CREATE OR REPLACE FUNCTION jo_core.refresh_worker_health()
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $fn$
BEGIN
INSERT INTO jo_core.worker_health(worker_key,expected_count,verified_count,missing_count,recovering_count,recurring_failure_count,stale_work_count,health_status,calculated_at)
SELECT w.worker_key,
 (SELECT count(*) FROM jo_core.expected_results e WHERE e.worker_key=w.worker_key),
 (SELECT count(*) FROM jo_core.expected_results e WHERE e.worker_key=w.worker_key AND e.state='verified' AND nullif(e.verification_evidence,'') IS NOT NULL),
 (SELECT count(*) FROM jo_core.expected_results e WHERE e.worker_key=w.worker_key AND e.due_at<now() AND NOT (e.state='verified' AND nullif(e.verification_evidence,'') IS NOT NULL)),
 (SELECT count(*) FROM team_v4.jobs j WHERE lower(j.role::text)=w.worker_key AND j.status::text='stalled' AND j.attempts<j.max_attempts AND NOT j.escalation_flag),
 (SELECT count(*) FROM team_v4.jobs j WHERE lower(j.role::text)=w.worker_key AND j.status::text NOT IN ('done','canceled','cancelled') AND j.no_progress_cycles>=3),
 (SELECT count(*) FROM team_v4.jobs j WHERE lower(j.role::text)=w.worker_key AND j.status::text NOT IN ('done','canceled','cancelled','failed') AND coalesce(j.last_progress_at,j.created_at)<now()-interval '1 hour'),
 CASE WHEN ws.state='blocked' THEN 'blocked'
      WHEN ws.state='error' THEN 'degraded'
      WHEN ws.last_heartbeat_at IS NULL OR ws.last_heartbeat_at<now()-interval '2 hours' THEN 'attention'
      ELSE 'unknown' END,
 now()
FROM jo_core.workers w LEFT JOIN jo_core.worker_state ws USING(worker_key) WHERE w.active
ON CONFLICT(worker_key) DO UPDATE SET expected_count=excluded.expected_count,verified_count=excluded.verified_count,missing_count=excluded.missing_count,recovering_count=excluded.recovering_count,recurring_failure_count=excluded.recurring_failure_count,stale_work_count=excluded.stale_work_count,health_status=excluded.health_status,calculated_at=excluded.calculated_at;
RETURN jsonb_build_object('checked_at',now(),'scope','operational_health_only','business_acceptance',false);
END $fn$;
REVOKE ALL ON FUNCTION jo_core.refresh_worker_health() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION jo_core.refresh_worker_health() TO service_role;
SELECT cron.schedule('jo-worker-health-refresh','* * * * *','select jo_core.refresh_worker_health();');
SELECT jo_core.refresh_worker_health();