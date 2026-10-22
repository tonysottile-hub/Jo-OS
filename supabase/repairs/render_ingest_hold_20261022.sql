CREATE OR REPLACE FUNCTION public.jo_core_apply_render_ingest(p_build_id uuid,p_storage_path text,p_artifact_id bigint,p_size bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE r jo_core.production_runs;
BEGIN
 PERFORM 1 FROM public.video_builds WHERE id=p_build_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'build missing'; END IF;
 SELECT * INTO r FROM jo_core.production_runs WHERE build_id=p_build_id AND stage='render' AND state='render_ready' AND artifact_id=p_artifact_id ORDER BY id DESC LIMIT 1;
 IF r.id IS NULL THEN RAISE EXCEPTION 'artifact does not belong to a ready render for build'; END IF;
 IF p_storage_path IS DISTINCT FROM 'tom-builds/'||p_build_id::text||'.mp4' THEN RAISE EXCEPTION 'storage path/build mismatch'; END IF;
 IF NOT EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='publisher-videos' AND name=p_storage_path) THEN RAISE EXCEPTION 'storage object missing'; END IF;
 UPDATE public.video_builds SET output_storage_path=p_storage_path,status='stored',
 asset_manifest=coalesce(asset_manifest,'{}'::jsonb)||jsonb_build_object('publish_authorized',false,'render_ingested_at',now(),'render_ingested_artifact_id',p_artifact_id,'render_ingested_run_id',r.run_id),
 updated_at=now() WHERE id=p_build_id;
 INSERT INTO public.video_build_logs(build_id,stage,detail) VALUES(p_build_id,'render_ingested_to_storage',jsonb_build_object('artifact_id',p_artifact_id,'run_id',r.run_id,'storage_path',p_storage_path,'size',p_size,'verified_storage_object',true,'publish_authorized',false,'at',now()));
 INSERT INTO jo_core.events(worker_key,event_type,detail) VALUES('tom','render_ingested_to_storage',jsonb_build_object('build_id',p_build_id,'artifact_id',p_artifact_id,'storage_path',p_storage_path,'size',p_size,'publish_authorized',false));
END $function$;

-- Rollback-only regression:
BEGIN;
DO $test$
DECLARE b uuid:='a15769f4-c661-4a5e-b7bd-6ce3c364185c'; denied boolean:=false;
BEGIN
 PERFORM public.jo_core_apply_render_ingest(b,'tom-builds/'||b||'.mp4',11896815380,1);
 IF (SELECT asset_manifest->>'publish_authorized' FROM public.video_builds WHERE id=b) IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'ingest elevated publication permission'; END IF;
 BEGIN
  PERFORM public.jo_core_apply_render_ingest(b,'tom-builds/'||b||'.mp4',-1,1);
 EXCEPTION WHEN raise_exception THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'uncorrelated artifact accepted'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.jo_core_apply_render_ingest(b,'tom-builds/other.mp4',11896815380,1);
 EXCEPTION WHEN raise_exception THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'wrong storage path accepted'; END IF;
END $test$;
ROLLBACK;