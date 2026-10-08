CREATE TABLE IF NOT EXISTS jo_core.cloud_audit_runs(
 run_id bigint PRIMARY KEY, commit_sha text NOT NULL, evidence jsonb NOT NULL, recorded_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE jo_core.cloud_audit_runs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON jo_core.cloud_audit_runs FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.jo_core_import_cloud_audit(p_run_id bigint,p_sha text,p_evidence jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v jsonb; c jsonb; j uuid; r uuid; role_name team_v4.role_name; passed boolean; n integer:=0;
BEGIN
 IF p_sha !~ '^[a-f0-9]{40}$' OR p_run_id<1 OR jsonb_array_length(p_evidence->'verification')<>2 THEN RAISE EXCEPTION 'Invalid audit evidence'; END IF;
 INSERT INTO jo_core.cloud_audit_runs(run_id,commit_sha,evidence) VALUES(p_run_id,p_sha,p_evidence) ON CONFLICT DO NOTHING;
 IF NOT FOUND THEN RETURN jsonb_build_object('imported',false,'reason','already_recorded'); END IF;
 FOR v IN SELECT value FROM jsonb_array_elements(p_evidence->'verification') LOOP
 IF v->>'worker' NOT IN ('mary','jeff') THEN RAISE EXCEPTION 'Invalid worker'; END IF;
 SELECT value INTO c FROM jsonb_array_elements(p_evidence->'execution'->'results') WHERE value->>'worker'=v->>'worker' LIMIT 1;
 passed:=coalesce((v->>'passed')::boolean,false) AND coalesce((c->>'browser_passed')::boolean,false) AND v->>'mechanism'='independent_urllib_get';
 role_name:=CASE v->>'worker' WHEN 'mary' THEN 'Mary'::team_v4.role_name ELSE 'Jeff'::team_v4.role_name END;
 INSERT INTO team_v4.jobs(role,outcome_description,status,current_step_index,priority,max_attempts)
 VALUES(role_name,'Public browser audit: website availability and storefront navigation. Excludes branding, purchase, indexing, and publishing claims.','in_progress',0,60,3) RETURNING job_id INTO j;
 INSERT INTO team_v4.job_steps(job_id,step_index,action,input) VALUES(j,0,'web.public_audit',jsonb_build_object('cloud_run_id',p_run_id,'scope','public_read_only'));
 INSERT INTO team_v4.worker_runs(job_id,worker_id,step_index,lease_expires_at) VALUES(j,'cloud-browser-import',0,now()+interval '5 minutes') RETURNING run_id INTO r;
 PERFORM team_v4.complete_worker_step(r,j,0,'cloud-browser-import',CASE WHEN passed THEN 'success'::team_v4.attempt_result ELSE 'blocked'::team_v4.attempt_result END,c,
 jsonb_build_object('cloud_run_id',p_run_id,'commit_sha',p_sha,'memory',jo_core.recall(lower(role_name::text),'',5)),
 CASE WHEN passed THEN NULL ELSE coalesce(c->>'error','Browser or independent verification failed; inspect evidence') END,true,2,
 CASE WHEN passed THEN NULL ELSE 'external_dependency'::team_v4.blocking_reason END,NULL);
 INSERT INTO team_v4.verification_results(job_id,verifier_id,mechanism,status,evidence,verification_target)
 VALUES(j,'cloud-independent-http','independent_urllib_get',CASE WHEN passed THEN 'passed'::team_v4.verification_status ELSE 'failed'::team_v4.verification_status END,
 v||jsonb_build_object('cloud_run_id',p_run_id,'commit_sha',p_sha),'public_site_read_only');
 INSERT INTO jo_core.events(worker_key,job_id,event_type,detail) VALUES(lower(role_name::text),j,'cloud_browser_audit',v||jsonb_build_object('cloud_run_id',p_run_id));
 IF v->>'worker'='jeff' THEN UPDATE jo_core.jeff_work_items SET evidence=evidence||jsonb_build_object('cloud_public_availability',v,'cloud_run_id',p_run_id),updated_at=now() WHERE item_key='cigar30_search_visibility'; END IF;
 n:=n+1;
 END LOOP;
 PERFORM team_v4.close_completed_jobs();
 RETURN jsonb_build_object('imported',true,'jobs',n);
END $$;
REVOKE ALL ON FUNCTION public.jo_core_import_cloud_audit(bigint,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.jo_core_import_cloud_audit(bigint,text,jsonb) TO service_role;
INSERT INTO jo_core.capability_registry(action,handler,executor,enabled,risk,reason)
VALUES('web.public_audit','browser-audit.yml + jo-cloud-audit-return','github_actions',true,'read_only','Fixed public origins, no credentials or submissions; independent HTTP verification required')
ON CONFLICT(action) DO NOTHING;

