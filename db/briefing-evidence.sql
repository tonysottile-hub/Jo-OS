CREATE OR REPLACE FUNCTION jo_core.generate_briefing(p_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_now timestamptz:=now();
  v_local timestamp;
  v_slot timestamptz;
  v_payload jsonb;
  v_id bigint;
begin
  if p_type not in ('morning','evening') then raise exception 'invalid briefing type'; end if;

  v_local:=v_now at time zone 'America/New_York';
  v_slot:=(
    date_trunc('day',v_local)
    + case when p_type='morning' then interval '7 hours 30 minutes' else interval '19 hours 30 minutes' end
  ) at time zone 'America/New_York';

  select jsonb_build_object(
    'briefing_type',p_type,
    'generated_at',v_now,
    'workers',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'worker_key',w.worker_key,
          'name',w.display_name,
          'business',w.primary_business_key,
          'state',coalesce(ws.state,'idle'),
          'job_id',ws.current_job_id,
          'current_work',ws.status_summary,
          'last_heartbeat_at',ws.last_heartbeat_at,
          'last_verified_at',ws.last_verified_at,
          'updated_at',ws.updated_at,
          'active_objective',(
            select jsonb_build_object(
              'type',o.objective_type,
              'objective',o.objective_text,
              'last_run_at',o.last_run_at,
              'next_run_at',o.next_run_at
            )
            from jo_core.objectives o
            where o.worker_key=w.worker_key and o.status='active'
            order by o.updated_at desc
            limit 1
          ),
          'owner_blockers',case
            when w.worker_key='steve' then coalesce((
              select jsonb_agg(jsonb_build_object(
                'stage_key',s.stage_key,'title',s.title,'status',s.status,'last_error',s.last_error
              ) order by s.sequence_no)
              from jo_core.steve_launch_stages s
              where s.status='blocked_owner'
            ),'[]'::jsonb)
            when w.worker_key='jeff' then coalesce((
              select jsonb_agg(jsonb_build_object(
                'item_key',x.item_key,'title',x.title,'status',x.status,'last_error',x.last_error
              ) order by x.priority)
              from jo_core.jeff_work_items x
              where x.status='blocked_owner'
            ),'[]'::jsonb)
            else '[]'::jsonb
          end
        )
        order by case w.worker_key when 'jo' then 1 when 'steve' then 2 when 'tom' then 3 when 'mary' then 4 when 'jeff' then 5 else 99 end
      )
      from jo_core.workers w
      left join jo_core.worker_state ws on ws.worker_key=w.worker_key
      where w.active=true
    ),'[]'::jsonb),
    'pending_approvals',coalesce((
      select jsonb_agg(to_jsonb(a) order by a.created_at)
      from jo_core.approvals a
      where a.status='pending'
    ),'[]'::jsonb),
    'active_objectives',coalesce((
      select jsonb_agg(jsonb_build_object(
        'worker',o.worker_key,
        'type',o.objective_type,
        'objective',o.objective_text,
        'last_run_at',o.last_run_at,
        'next_run_at',o.next_run_at
      ) order by o.worker_key,o.objective_type)
      from jo_core.objectives o
      where o.status='active'
    ),'[]'::jsonb)
  ) into v_payload;
  v_payload:=v_payload || jsonb_build_object('verified_outcomes',jo_core.evidence_snapshot(),'delivery_note','Available in authenticated dashboard; owner receipt not yet verified');

  insert into jo_core.briefings(briefing_type,scheduled_for,status,payload,delivery_channel)
  values(p_type,v_slot,'delivery_pending',v_payload,'dashboard')
  on conflict(briefing_type,scheduled_for)
  do update set
    generated_at=now(),
    payload=excluded.payload,
    status=case when jo_core.briefings.status='delivered' then 'delivered' else 'delivery_pending' end,
    delivery_error=null,
    delivery_channel='dashboard'
  returning briefing_id into v_id;

  insert into jo_core.events(worker_key,event_type,detail)
  values('jo','briefing_generated',jsonb_build_object(
    'briefing_id',v_id,'type',p_type,'scheduled_for',v_slot,'source','live_worker_state'
  ));

  return jsonb_build_object('briefing_id',v_id,'type',p_type,'scheduled_for',v_slot,'status','delivery_pending');
end
$function$;
