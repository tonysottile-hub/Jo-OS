CREATE OR REPLACE FUNCTION jo_core.run_tom_media_narration_dispatch_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare b record; recent boolean; outj jsonb;
begin
  select vb.id,vb.topic,vb.title into b
  from public.video_builds vb
  where vb.status='production_package_ready'
    and vb.blocker_stage is null
    and coalesce((vb.asset_manifest->>'publish_authorized')::boolean,false)=false
    and vb.asset_manifest->>'production_stage'='media_and_narration'
  order by vb.updated_at asc
  limit 1;

  if b.id is null then
    return jsonb_build_object('requested',false,'reason','no_dispatchable_build');
  end if;

  if (select count(*) from jo_core.github_dispatches where build_id=b.id and state='failed' and created_at>coalesce((select max(created_at) from jo_core.github_dispatches where build_id=b.id and state='media_ready'),'-infinity'::timestamptz))>=3 then
    update public.video_builds set status='blocked',blocker_stage='media',updated_at=now(),asset_manifest=asset_manifest||jsonb_build_object('recovery_required','media_retry_budget_exhausted','retry_limit',3) where id=b.id;
    insert into jo_core.events(worker_key,event_type,detail) values('tom','media_retries_quarantined',jsonb_build_object('build_id',b.id,'limit',3,'owner_action_required',false));
    return jsonb_build_object('requested',false,'reason','media_retry_budget_exhausted','build_id',b.id);
  end if;

  select exists(
    select 1 from jo_core.events e
    where e.worker_key='tom'
      and e.event_type='github_production_dispatch'
      and e.detail->>'build_id'=b.id::text
      and e.created_at > now()-interval '3 minutes'
  ) into recent;

  if recent then
    return jsonb_build_object('requested',false,'reason','recent_dispatch_request_exists','build_id',b.id);
  end if;

  outj:=jo_core.dispatch_github_production(b.id);
  return jsonb_build_object('requested',true,'build_id',b.id,'result',outj);
end
$function$;
