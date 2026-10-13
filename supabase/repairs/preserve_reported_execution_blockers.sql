-- One diagnostic source for manager state and the dashboard. No job completion claims.
CREATE OR REPLACE VIEW jo_core.worker_job_diagnostics WITH (security_invoker=true) AS
WITH diagnosed AS (
 SELECT j.*,s.action,
 CASE
 WHEN j.status='blocked_owner' THEN coalesce(j.blocking_reason::text,'owner_action_required')
 WHEN j.status='failed' THEN 'failed'
 WHEN j.status='verify_pending' THEN NULL
 WHEN s.step_id IS NULL THEN 'missing_current_step'
 WHEN s.completed_at IS NOT NULL THEN 'current_step_already_completed'
 WHEN j.attempts>=j.max_attempts THEN 'retry_budget_exhausted'
 WHEN j.escalation_flag THEN coalesce(j.blocking_reason::text,'escalated')
 WHEN j.dependency_job_id IS NOT NULL AND NOT EXISTS
   (SELECT 1 FROM team_v4.jobs d WHERE d.job_id=j.dependency_job_id AND d.status='done')
   THEN 'dependency_not_verified'
 WHEN c.action IS NULL OR NOT c.enabled OR c.executor='unimplemented' THEN 'capability_unavailable'
 WHEN j.status='stalled' AND j.blocking_reason IS NOT NULL THEN j.blocking_reason::text
 WHEN j.status='stalled' AND EXISTS
   (SELECT 1 FROM team_v4.execution_attempts a WHERE a.job_id=j.job_id
    AND a.finished_at>now()-make_interval(secs=>least(3600,60*power(2,least(j.attempts,5)))::integer))
   THEN 'retry_backoff'
 ELSE NULL END AS execution_blocker,
 (j.lease_owner IS NOT NULL AND j.lease_expires_at>now()) OR EXISTS
   (SELECT 1 FROM team_v4.worker_runs r WHERE r.job_id=j.job_id AND r.ended_at IS NULL AND r.lease_expires_at>now())
   AS has_live_lease
 FROM team_v4.jobs j
 LEFT JOIN team_v4.job_steps s ON s.job_id=j.job_id AND s.step_index=j.current_step_index
 LEFT JOIN jo_core.capability_registry c ON c.action=s.action
 WHERE j.status<>'done'
)
SELECT d.*,
 CASE WHEN status='verify_pending' THEN 'waiting_verification'
      WHEN status='failed' OR execution_blocker IN
      ('missing_current_step','current_step_already_completed','retry_budget_exhausted','capability_unavailable') THEN 'error'
      WHEN execution_blocker IS NOT NULL AND execution_blocker<>'retry_backoff' THEN 'blocked'
      WHEN has_live_lease AND execution_blocker IS NULL THEN 'working'
      ELSE 'idle' END AS derived_state,
 CASE WHEN execution_blocker IS NULL AND status IN ('queued','in_progress','stalled') AND has_live_lease THEN 0
      WHEN execution_blocker IS NULL AND status IN ('queued','in_progress','stalled') THEN 1
      WHEN status='verify_pending' THEN 2
      WHEN execution_blocker='retry_backoff' THEN 3
      WHEN status='blocked_owner' THEN 5
      WHEN status='failed' THEN 6 ELSE 4 END AS selection_rank
FROM diagnosed d;

