CREATE TABLE jo_core.production_reconciliation (
 reconciliation_id uuid NOT NULL, job_id uuid NOT NULL REFERENCES team_v4.jobs(job_id),
 worker_key text NOT NULL, observed_status text NOT NULL, classification text NOT NULL,
 current_action text, handler text, last_verification_id bigint, observed_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(reconciliation_id,job_id)
);
ALTER TABLE jo_core.production_reconciliation ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON jo_core.production_reconciliation FROM PUBLIC,anon,authenticated;
CREATE FUNCTION jo_core.reconcile_production_jobs()
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE rid uuid:=gen_random_uuid(); repaired int;
BEGIN
 -- Only orphaned progress with no live worker may be repaired. Never requeue.
 WITH fixed AS (
 UPDATE team_v4.jobs j SET status='stalled',blocking_reason='unknown_structural',
 last_error='Reconciled orphaned in_progress: no lease or live run; requires executable next step, not blind retry',updated_at=now()
 WHERE status='in_progress' AND lease_owner IS NULL AND lease_expires_at IS NULL
 AND updated_at<now()-interval '1 hour'
 AND NOT EXISTS (SELECT 1 FROM team_v4.worker_runs r WHERE r.job_id=j.job_id AND r.ended_at IS NULL AND r.lease_expires_at>now())
 RETURNING job_id,role)
 INSERT INTO jo_core.events(worker_key,job_id,event_type,detail)
 SELECT lower(role::text),job_id,'orphaned_progress_repaired',jsonb_build_object('reconciliation_id',rid,'external_work_verified',false,'requeued',false) FROM fixed;
 GET DIAGNOSTICS repaired=ROW_COUNT;
 INSERT INTO jo_core.production_reconciliation(reconciliation_id,job_id,worker_key,observed_status,classification,current_action,handler,last_verification_id)
 SELECT rid,j.job_id,lower(j.role::text),j.status::text,
 CASE WHEN j.status='done' AND v.verification_id IS NULL THEN 'done_without_verification_record'
 WHEN j.status='done' THEN 'done_requires_scope_review'
 WHEN j.status='blocked_owner' THEN 'owner_dependency'
 WHEN j.status='verify_pending' THEN 'independent_verification_required'
 WHEN j.status='failed' THEN 'quarantined_review_before_retry'
 WHEN s.step_id IS NULL THEN 'missing_current_step'
 WHEN c.action IS NULL OR NOT c.enabled THEN 'missing_executable_handler'
 WHEN c.handler='execution_gate' THEN 'downstream_dependency_gate'
 ELSE 'adapter_available_inspect_evidence' END,s.action,c.handler,v.verification_id
 FROM team_v4.jobs j LEFT JOIN team_v4.job_steps s ON s.job_id=j.job_id AND s.step_index=j.current_step_index
 LEFT JOIN jo_core.capability_registry c ON c.action=s.action
 LEFT JOIN LATERAL(SELECT verification_id FROM team_v4.verification_results WHERE job_id=j.job_id ORDER BY checked_at DESC,verification_id DESC LIMIT 1)v ON true;
 RETURN jsonb_build_object('reconciliation_id',rid,'jobs',(SELECT count(*) FROM jo_core.production_reconciliation WHERE reconciliation_id=rid),'orphaned_progress_repaired',repaired);
END $$;
REVOKE ALL ON FUNCTION jo_core.reconcile_production_jobs() FROM PUBLIC,anon,authenticated,service_role;

INSERT INTO gstack.templates(template_id,version,approved,source_ref,capabilities,tool_allowlist,instructions_ref,resource_limits)
VALUES('bounded-draft','1.0.0',true,'supabase:jo-draft-executor:v1:109092e945b28830232b9ae9043e4bfa85fb16dbbece4e145a4ce992f8f4b2ec',
'["draft_from_supplied_evidence"]','[]','jo-draft-executor/core.mjs',
'{"external_writes":false,"publishing":false,"shell_access":false,"max_output_tokens":1000,"max_runtime_seconds":45,"requires_owner_inference_policy":true}');
INSERT INTO gstack.department_agents(provision_request_key,template_id,template_version,manager_key,status,permissions)
SELECT 'bounded-draft-v1-'||k,'bounded-draft','1.0.0',k,'idle','{"draft_only":true,"external_writes":false,"completion_authority":false}'::jsonb
FROM unnest(ARRAY['jo','mary','tom','steve','jeff'])k;
ALTER TABLE jo_core.draft_tasks ADD COLUMN agent_id uuid REFERENCES gstack.department_agents(agent_id);
CREATE TABLE gstack.draft_handoffs(task_id uuid PRIMARY KEY REFERENCES jo_core.draft_tasks(task_id),checkpoint_id uuid UNIQUE NOT NULL REFERENCES gstack.agent_memory_checkpoints(checkpoint_id),created_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE gstack.draft_handoffs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON gstack.draft_handoffs FROM PUBLIC,anon,authenticated;
CREATE FUNCTION gstack.bind_draft_agent()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
 IF NEW.agent_id IS NULL THEN
 SELECT a.agent_id INTO NEW.agent_id FROM gstack.department_agents a JOIN gstack.templates t ON t.template_id=a.template_id AND t.version=a.template_version
 WHERE a.provision_request_key='bounded-draft-v1-'||NEW.worker_key AND a.manager_key=NEW.worker_key AND a.status IN ('idle','working') AND t.approved;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM gstack.department_agents a JOIN gstack.templates t ON t.template_id=a.template_id AND t.version=a.template_version WHERE a.agent_id=NEW.agent_id AND a.manager_key=NEW.worker_key AND a.template_id='bounded-draft' AND a.status IN ('idle','working') AND t.approved) THEN RAISE EXCEPTION 'No authorized draft specialist for manager'; END IF;
 IF TG_OP='UPDATE' AND (NEW.agent_id IS DISTINCT FROM OLD.agent_id OR NEW.worker_key IS DISTINCT FROM OLD.worker_key) THEN RAISE EXCEPTION 'Draft assignment immutable'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER bind_gstack_draft BEFORE INSERT OR UPDATE ON jo_core.draft_tasks FOR EACH ROW EXECUTE FUNCTION gstack.bind_draft_agent();
CREATE FUNCTION gstack.record_draft_handoff()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE cp uuid;
BEGIN
 IF NEW.state='qa_pending' AND OLD.state IS DISTINCT FROM NEW.state THEN
 IF NEW.draft IS NULL OR NEW.provider_response_id IS NULL THEN RAISE EXCEPTION 'Draft evidence required'; END IF;
 INSERT INTO gstack.agent_memory_checkpoints(agent_id,manager_key,job_ref,claim,evidence_ref,sensitivity)
 VALUES(NEW.agent_id,NEW.worker_key,'draft:'||NEW.task_id,'Draft produced; manager review and independent verification required. No business completion claimed.',
 'jo_core.draft_tasks:'||NEW.task_id,'department') RETURNING checkpoint_id INTO cp;
 INSERT INTO gstack.draft_handoffs(task_id,checkpoint_id) VALUES(NEW.task_id,cp);
 UPDATE gstack.department_agents SET last_execution_at=now() WHERE agent_id=NEW.agent_id;
 INSERT INTO jo_core.events(worker_key,event_type,detail) VALUES(NEW.worker_key,'specialist_draft_handoff',jsonb_build_object('task_id',NEW.task_id,'checkpoint_id',cp,'business_completion_verified',false));
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER record_gstack_handoff AFTER UPDATE ON jo_core.draft_tasks FOR EACH ROW EXECUTE FUNCTION gstack.record_draft_handoff();
REVOKE ALL ON FUNCTION gstack.bind_draft_agent(),gstack.record_draft_handoff() FROM PUBLIC,anon,authenticated,service_role;

-- This schedule cannot authorize spend. It does nothing until the owner policy
-- is explicitly enabled, a model/reference exists, and a task is eligible.
SELECT cron.schedule('gstack-bounded-draft-dispatch','*/5 * * * *',$cron$
SELECT net.http_post(url:='https://pubnivjjeofxqvmttuzh.supabase.co/functions/v1/jo-draft-executor',
headers:=jsonb_build_object('Content-Type','application/json','x-jo-scheduler-token',(select decrypted_secret from vault.decrypted_secrets where name='publisher_scheduler_bridge_token')),body:='{}'::jsonb)
WHERE EXISTS(SELECT 1 FROM jo_core.draft_runtime_policy WHERE enabled AND model IS NOT NULL AND approval_reference IS NOT NULL)
AND EXISTS(SELECT 1 FROM jo_core.draft_tasks WHERE state IN ('pending','retry') AND next_attempt_at<=now() AND attempt<3);
$cron$);
