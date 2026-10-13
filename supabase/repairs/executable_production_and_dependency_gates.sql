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
CREATE OR REPLACE FUNCTION jo_core.run_capability_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE c record; s record; v_role team_v4.role_name; v_actions text[]; v_handler text; outj jsonb; v_reaped integer; v_quarantined integer; v_count integer:=0;
BEGIN
 SELECT array_agg(action) INTO v_actions FROM jo_core.capability_registry WHERE enabled AND executor='native_sql';
 FOREACH v_role IN ARRAY ARRAY['Jo','Tom','Steve','Mary','Jeff']::team_v4.role_name[] LOOP
 SELECT * INTO c FROM team_v4.claim_next_capability_job('jo-core-cron',v_role,v_actions,300) LIMIT 1;
 IF c.job_id IS NULL THEN CONTINUE; END IF;
 SELECT * INTO s FROM team_v4.job_steps WHERE job_id=c.job_id AND step_index=c.current_step_index;
 SELECT handler INTO v_handler FROM jo_core.capability_registry WHERE action=s.action AND enabled AND executor='native_sql';
 BEGIN
 IF v_handler='echo' THEN outj:=jsonb_build_object('echo',s.input,'acceptance_evidence',false);
 ELSIF v_handler='recover' THEN
 v_reaped:=team_v4.reap_expired_leases();
 UPDATE team_v4.jobs SET status='failed',last_error=coalesce(last_error,'Retry budget exhausted'),lease_owner=NULL,lease_expires_at=NULL
 WHERE attempts>=max_attempts AND status IN ('queued','stalled') AND (lease_expires_at IS NULL OR lease_expires_at<now());
 GET DIAGNOSTICS v_quarantined=ROW_COUNT;
 outj:=jsonb_build_object('expired_leases_reaped',v_reaped,'exhausted_jobs_quarantined',v_quarantined,'remaining',jo_core.evidence_snapshot());
 ELSIF v_handler='execution_gate' THEN
 outj:=jo_core.read_execution_gate(s.action,s.input);
 IF coalesce((outj->>'ready')::boolean,false)=false THEN
  PERFORM team_v4.complete_worker_step(c.run_id,c.job_id,c.current_step_index,'jo-core-cron','blocked',outj,
    jsonb_build_object('action',s.action,'scope','execution_gate'),outj->>'reason',false,1,'external_dependency',NULL);
  CONTINUE;
 END IF;
 ELSIF v_handler='audit' THEN outj:=jo_core.evidence_snapshot();
 ELSIF v_handler='briefing' THEN outj:=jo_core.generate_briefing(CASE WHEN extract(hour FROM now() AT TIME ZONE 'America/New_York')<12 THEN 'morning' ELSE 'evening' END);
 ELSE RAISE EXCEPTION 'Handler not implemented'; END IF;
 PERFORM team_v4.complete_worker_step(c.run_id,c.job_id,c.current_step_index,'jo-core-cron','success',outj,
 jsonb_build_object('action',s.action,'handler',v_handler,'executed_at',now(),'memory',jo_core.recall(lower(v_role::text),'',5)),NULL,(v_handler<>'echo' AND NOT (v_handler='execution_gate' AND s.action IN ('unmapped.tom.research_script','unmapped.tom.media_render'))),1,NULL,NULL);
 INSERT INTO jo_core.events(worker_key,job_id,event_type,detail) VALUES(lower(v_role::text),c.job_id,'capability_executed',jsonb_build_object('action',s.action,'handler',v_handler,'proof',outj));
 v_count:=v_count+1;
 EXCEPTION WHEN OTHERS THEN
 PERFORM team_v4.complete_worker_step(c.run_id,c.job_id,c.current_step_index,'jo-core-cron','transient_failure','{}',
 jsonb_build_object('handler',v_handler),SQLERRM,false,1,'unknown_structural',NULL);
 END;
 END LOOP;
 RETURN jsonb_build_object('executed',v_count,'checked_at',now());
END $function$
;
INSERT INTO jo_core.capability_registry(action,handler,executor,enabled,risk,reason)
SELECT a,'execution_gate','native_sql',true,'read_only','Read actual durable stage/dependency evidence; never bypass QA, credentials, or publication approval'
FROM unnest(ARRAY['unmapped.tom.research_script','unmapped.tom.media_render','unmapped.tom.publish_qa','jo_core.dependency_acceptance','jo_core.fleet_business_acceptance']) a
ON CONFLICT(action) DO UPDATE SET handler=excluded.handler,executor=excluded.executor,enabled=true,risk=excluded.risk,reason=excluded.reason,updated_at=now();
INSERT INTO team_v4.job_steps(job_id,step_index,action,input,idempotency_key)
VALUES
('974b9ffc-bef2-4cc3-bb6e-d6a6f74c8d77',0,'Spot-check external verification evidence for jobs claiming completion; reject unsupported completion claims','{"read_only":true,"no_external_publication":true}','thanksgiving-oversight-evidence-audit'),
('974b9ffc-bef2-4cc3-bb6e-d6a6f74c8d77',1,'jo_core.dependency_acceptance','{"required_job_ids":["78cd7cdb-f1b7-416b-87a7-c7ee74ccf8e8"]}','thanksgiving-oversight-business-gate'),
('b5ea681b-814c-4829-9fbe-40b1ad6af8d0',2,'unmapped.tom.media_render','{"build_id":"666e8f83-1f40-4229-88ec-d66fbdaee3b6","publish_authorized":false}','hamilton-long-render-gate'),
('b5ea681b-814c-4829-9fbe-40b1ad6af8d0',3,'unmapped.tom.publish_qa','{"build_id":"666e8f83-1f40-4229-88ec-d66fbdaee3b6","requires_human_review":true,"requires_destination_verification":true}','hamilton-long-publish-gate')
ON CONFLICT DO NOTHING;
UPDATE team_v4.job_steps SET input=input||'{"required_job_ids":["300d0cf7-be3e-4cea-a669-7e15eb2d758e","78cd7cdb-f1b7-416b-87a7-c7ee74ccf8e8","703c84a2-01ca-4460-9583-e10015a65db9","2aeb1c49-f2aa-4a96-9af8-62795e49642c"]}'::jsonb
WHERE job_id='6032246c-9196-4e1a-b31d-9314ec592d04' AND action='jo_core.fleet_business_acceptance' AND completed_at IS NULL;


CREATE OR REPLACE FUNCTION jo_core.dispatch_github_production(p_build_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare req_id bigint;
begin
 if not exists (
   select 1 from public.video_builds
   where id=p_build_id
     and coalesce((asset_manifest->>'publish_authorized')::boolean,false)=false
     and blocker_stage is null
     and asset_manifest->>'production_stage'='media_and_narration'
 ) then return jsonb_build_object('dispatched',false,'reason','build_not_dispatchable'); end if;
 select net.http_post(
   url:='https://pubnivjjeofxqvmttuzh.supabase.co/functions/v1/jo-core-github-dispatch',
   headers:=jsonb_build_object('Content-Type','application/json','x-jo-scheduler-token',(select decrypted_secret from vault.decrypted_secrets where name='publisher_scheduler_bridge_token' limit 1)),
   timeout_milliseconds:=60000,
   body:=jsonb_build_object('build_id',p_build_id,'action','produce_media_and_narration')
 ) into req_id;
 insert into jo_core.events(worker_key,event_type,detail) values('tom','github_production_dispatch',jsonb_build_object('build_id',p_build_id,'request_id',req_id));
 return jsonb_build_object('dispatched',true,'request_id',req_id,'build_id',p_build_id);
end $function$
;