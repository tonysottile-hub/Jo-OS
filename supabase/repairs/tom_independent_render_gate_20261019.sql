CREATE OR REPLACE FUNCTION jo_core.read_execution_gate(p_action text,p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $fn$
DECLARE b public.video_builds; ready boolean:=false; proof jsonb; missing jsonb; ids jsonb;
BEGIN
 IF p_action IN ('jo_core.dependency_acceptance','jo_core.fleet_business_acceptance') THEN
  ids:=p_input->'required_job_ids';
  IF jsonb_typeof(ids) IS DISTINCT FROM 'array' OR jsonb_array_length(ids)=0 THEN
   RETURN jsonb_build_object('ready',false,'reason','Explicit downstream acceptance jobs are required');
  END IF;
  SELECT jsonb_agg(jsonb_build_object('job_id',x.id,'status',j.status,'error',j.last_error))
  INTO missing FROM jsonb_array_elements_text(ids) x(id)
  LEFT JOIN team_v4.jobs j ON j.job_id=x.id::uuid
  WHERE j.job_id IS NULL OR j.status<>'done' OR j.last_verified_at IS NULL
   OR NOT EXISTS (SELECT 1 FROM team_v4.verification_results v WHERE v.job_id=j.job_id
     AND v.status='passed' AND coalesce(v.evidence->>'external_work_verified','false')='true');
  -- Broad fleet completion requires its own independent acceptance receipt.
  IF p_action='jo_core.fleet_business_acceptance' THEN
   ready:=missing IS NULL AND EXISTS (
     SELECT 1 FROM team_v4.verification_results v
     WHERE v.verification_target='fleet_business_acceptance' AND v.status='passed'
       AND v.evidence @> '{"external_work_verified":true,"delivery_verified":true,"repeated_unattended_execution":true,"gstack_delegation_verified":true}'::jsonb
       AND v.evidence->'required_workers' @> '["jo","tom","mary","steve","jeff"]'::jsonb
       AND v.checked_at>now()-interval '24 hours');
   RETURN jsonb_build_object('ready',ready,'reason','Fleet business acceptance requires downstream outcomes and a fresh independent acceptance receipt','unfinished_dependencies',coalesce(missing,'[]'::jsonb),'external_work_verified',ready);
  END IF;
  RETURN jsonb_build_object('ready',missing IS NULL,'reason','Awaiting independently verified downstream business outcomes','unfinished_dependencies',coalesce(missing,'[]'::jsonb),'external_work_verified',false);
 END IF;
 SELECT * INTO b FROM public.video_builds WHERE id=(p_input->>'build_id')::uuid;
 IF b.id IS NULL THEN RETURN jsonb_build_object('ready',false,'reason','Build not found'); END IF;
 IF p_action='unmapped.tom.research_script' THEN
  ready:=length(coalesce(b.asset_manifest->>'script',''))>0
   AND jsonb_typeof(b.asset_manifest->'research_sources')='array'
   AND jsonb_array_length(b.asset_manifest->'research_sources')>=2
   AND b.asset_manifest->>'research_verified_at' IS NOT NULL
   AND EXISTS (SELECT 1 FROM jo_core.research_packages r WHERE lower(r.topic_key)=lower(b.topic)
      AND r.status='verified' AND r.script=b.asset_manifest->>'script');
 ELSIF p_action='unmapped.tom.media_render' THEN
  ready:=b.output_storage_path IS NOT NULL AND EXISTS(SELECT 1 FROM storage.objects o
    WHERE o.bucket_id='publisher-videos' AND o.name=b.output_storage_path);
 ELSIF p_action='unmapped.tom.independent_render_qa' THEN
  SELECT count(*)=3 AND bool_and(coalesce((q.detail->>'passed')::boolean,false))
   AND bool_and(coalesce(q.detail->'evidence'->>'artifact_id'=p_input->>'artifact_id',false))
  INTO ready FROM (
   SELECT DISTINCT ON (stage) stage,detail FROM public.video_build_logs
   WHERE build_id=b.id AND stage IN ('qa_technical','qa_visual','qa_audio')
   ORDER BY stage,created_at DESC,id DESC
  ) q;
 ELSIF p_action='unmapped.tom.publish_qa' THEN
  SELECT jsonb_build_object('video_id',t.external_post_id,'public_url',t.external_url,'verification_id',v.verification_target)
  INTO proof FROM public.publish_targets t
  JOIN team_v4.verification_results v ON v.status='passed'
    AND v.mechanism IN ('youtube_api_worker_proof','publisher_log_youtube_verified')
    AND coalesce(v.evidence->>'video_id',v.evidence->>'youtube_video_id')=t.external_post_id
  WHERE t.job_id=b.publish_job_id AND t.platform='youtube' AND t.status='published'
    AND t.external_url IS NOT NULL
    AND b.asset_manifest->'perceptual_review'->>'passed'='true'
    AND b.asset_manifest->>'publish_authorized'='true'
  ORDER BY v.checked_at DESC LIMIT 1;
  ready:=proof IS NOT NULL;
 ELSE RAISE EXCEPTION 'Unsupported execution gate %',p_action; END IF;
 RETURN jsonb_build_object('ready',coalesce(ready,false),'build_id',b.id,'build_status',b.status,
  'blocker_stage',b.blocker_stage,'artifact',b.output_storage_path,'destination_proof',proof,
  'reason',CASE WHEN coalesce(ready,false) THEN 'Durable stage evidence found'
    WHEN b.blocker_stage IS NOT NULL THEN 'Build blocked: '||b.blocker_stage
    ELSE 'Awaiting durable evidence for '||p_action END,
  'external_work_verified',proof IS NOT NULL,'checked_at',now());
END $fn$;
REVOKE ALL ON FUNCTION jo_core.read_execution_gate(text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION jo_core.read_execution_gate(text,jsonb) TO service_role;

INSERT INTO jo_core.capability_registry(action,handler,executor,enabled,risk,reason)
VALUES ('unmapped.tom.independent_render_qa','execution_gate','native_sql',true,'read_only',
'Checks independent technical, visual and audio receipts for the exact artifact; does not publish')
ON CONFLICT(action) DO NOTHING;
INSERT INTO team_v4.job_steps(job_id,step_index,action,input,idempotency_key)
SELECT job_id,0,'unmapped.tom.independent_render_qa',
'{"build_id":"666e8f83-1f40-4229-88ec-d66fbdaee3b6","artifact_id":12172991782,"publish_authorized":false}'::jsonb,
'hamilton-recovery-independent-artifact-12172991782'
FROM team_v4.jobs WHERE job_id='46773a2a-9b09-4e35-9136-f4b5f180ae53'
 AND current_step_index=0 AND (lease_expires_at IS NULL OR lease_expires_at<now())
ON CONFLICT DO NOTHING;
INSERT INTO jo_core.events(worker_key,job_id,event_type,detail)
VALUES('tom','46773a2a-9b09-4e35-9136-f4b5f180ae53','missing_step_repaired',
'{"action":"unmapped.tom.independent_render_qa","publication_authorized":false,"business_completion":false}'::jsonb);
