-- Include manager-approved G Stack company lessons in the actual worker recall path.
-- Security invoker and existing table permissions/RLS remain unchanged.
CREATE OR REPLACE FUNCTION jo_core.recall(p_worker text,p_query text DEFAULT '',p_limit integer DEFAULT 10)
RETURNS jsonb LANGUAGE sql STABLE SET search_path='' AS $fn$
WITH latest AS (
 SELECT DISTINCT ON(memory_key) * FROM jo_core.memory_revisions ORDER BY memory_key,revision DESC
), memories AS (
 SELECT memory_key,revision,content,source,source_at,recorded_at,correction_reason
 FROM latest WHERE worker_key IN ('all',p_worker)
 UNION ALL
 SELECT sk.memory_key,sk.revision,sk.content,sk.source,sk.verified_at,sk.updated_at,
 'Manager-approved company lesson; verification='||vr.verification_ref AS correction_reason
 FROM jo_core.shared_knowledge sk
 JOIN gstack.memory_promotions mp ON mp.company_memory_key=sk.memory_key AND mp.decision='approved'
 JOIN gstack.agent_memory_checkpoints cp ON cp.checkpoint_id=mp.checkpoint_id
 JOIN gstack.verification_receipts vr ON vr.checkpoint_id=cp.checkpoint_id
 WHERE sk.scope='organization' AND sk.status='active' AND sk.verified_at IS NOT NULL
 AND sk.source='gstack.manager_approved'
 AND cp.sensitivity='company_candidate' AND cp.verification_status='verified'
 AND cp.manager_key=mp.manager_key AND vr.manager_key=mp.manager_key
 AND vr.evidence_ref=cp.evidence_ref AND sk.source_reference=cp.evidence_ref
 AND vr.verification_ref=mp.verification_ref
 AND sk.content=cp.claim
 AND NOT EXISTS(SELECT 1 FROM latest r WHERE r.memory_key=sk.memory_key)
)
SELECT coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) FROM (
 SELECT memory_key,revision,content,source,source_at,recorded_at,correction_reason,
 'instruction_context_only_live_operational_records_take_precedence'::text AS authority
 FROM memories
 WHERE p_worker IN ('jo','tom','mary','steve','jeff')
 AND (p_query='' OR to_tsvector('english',memory_key||' '||content) @@ websearch_to_tsquery('english',p_query))
 ORDER BY source_at DESC,memory_key LIMIT least(greatest(p_limit,1),50)
) r
$fn$;