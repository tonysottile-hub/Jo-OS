-- Repair conflicting status writers and concurrent lease recovery.

CREATE OR REPLACE FUNCTION jo_core.run_team_watchdog()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare reaped int; closed int; synced jsonb; mgr jsonb; pubsync jsonb; autonext jsonb;
prod jsonb; research jsonb; dispatchj jsonb; marymgr jsonb; marymerch jsonb;
stevemgr jsonb; jeffmgr jsonb; verification_sync jsonb; result jsonb;
begin
 reaped:=team_v4.reap_expired_leases();
 closed:=team_v4.close_completed_jobs();
 pubsync:=jo_core.sync_published_builds();

 begin autonext:=jo_core.ensure_tom_next_job();
 exception when others then autonext:=jsonb_build_object('created',false,'error',sqlerrm); end;

 begin prod:=jo_core.run_tom_production_handoff_tick();
 exception when others then prod:=jsonb_build_object('claimed',false,'error',sqlerrm); end;

 begin research:=jo_core.run_tom_research_seed_tick();
 exception when others then research:=jsonb_build_object('advanced',false,'error',sqlerrm); end;

 begin dispatchj:=jo_core.run_tom_media_narration_dispatch_tick();
 exception when others then dispatchj:=jsonb_build_object('requested',false,'error',sqlerrm); end;

 begin marymgr:=jo_core.run_mary_manager_cycle();
 exception when others then marymgr:=jsonb_build_object('ran',false,'error',sqlerrm); end;

 begin marymerch:=jo_core.run_mary_merch_cycle();
 exception when others then marymerch:=jsonb_build_object('ran',false,'error',sqlerrm); end;


 begin stevemgr:=jo_core.run_steve_manager_cycle();
 exception when others then stevemgr:=jsonb_build_object('ran',false,'error',sqlerrm); end;

 begin jeffmgr:=jo_core.run_jeff_manager_cycle();
 exception when others then jeffmgr:=jsonb_build_object('ran',false,'error',sqlerrm); end;

 begin verification_sync:=jo_core.refresh_steve_jeff_verification();
 exception when others then verification_sync:=jsonb_build_object('error',sqlerrm); end;

 begin mgr:=jo_core.run_manager_cycle();
 exception when others then mgr:=jsonb_build_object('ran',false,'error',sqlerrm); end;

 -- Synchronize after managers; assignment is not execution evidence.
 synced:=jo_core.sync_worker_state();

 result:=jsonb_build_object(
   'reaped_leases',reaped,'closed_jobs',closed,'published_sync',pubsync,
   'tom_autonext',autonext,'tom_production',prod,'tom_research',research,'tom_dispatch',dispatchj,
   'mary_kdp',marymgr,'mary_merch',marymerch,
   'steve_manager',stevemgr,'jeff_manager',jeffmgr,
   'verification_sync',verification_sync,
   'worker_state',synced,'manager',mgr,'ran_at',now()
 );
 insert into jo_core.events(worker_key,event_type,detail) values('jo','team_watchdog',result);
 return result;
end
$function$;


CREATE OR REPLACE FUNCTION jo_core.run_jeff_manager_cycle()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o record; j record; blockers jsonb; result jsonb;
begin
  select * into o from jo_core.objectives
  where worker_key='jeff' and objective_type='admin_support' and status='active'
  for update skip locked limit 1;
  if o.objective_id is null then return jsonb_build_object('ran',false,'reason','no_active_objective'); end if;

  select * into j
  from jo_core.jeff_work_items
  where status in ('working','waiting_verification','queued')
  order by case status when 'working' then 0 when 'waiting_verification' then 1 else 2 end,priority
  limit 1;

  if j.item_key is not null and j.status='queued' then
    update jo_core.jeff_work_items set status='working',updated_at=now()
    where item_key=j.item_key
    returning * into j;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'item_key',item_key,'title',title,'status',status,'owner_action_required',owner_action_required,'last_error',last_error
  ) order by priority),'[]'::jsonb)
  into blockers
  from jo_core.jeff_work_items
  where status in ('blocked_owner','blocked_external');

  result:=jsonb_build_object(
    'ran',true,
    'current_item',case when j.item_key is null then null else jsonb_build_object(
      'item_key',j.item_key,'lane',j.lane,'title',j.title,'status',j.status,'config',j.config
    ) end,
    'blockers',blockers,
    'next_action',case
      when j.item_key='personal_email_triage' then 'triage personal Gmail, verify labels/archive/draft state, and surface only messages that need Tony'
      when j.item_key='admin_followups' then 'close the oldest executable personal/admin follow-up and verify the system-of-record state'
      when j.item_key='mary_social_catchup' then 'prepare one prior missed-drop Facebook/LinkedIn catch-up package without duplicating Mary current drop'
      when j.item_key='team_blocker_support' then 'remove the highest-value concrete blocker for another worker and return evidence to its owner'
      when j.item_key='zero_cost_revenue_research' then 'produce one evidence-backed zero-cost opportunity brief'
      when j.item_key is null then 'monitor owner-only blockers without letting them freeze Jeff'
      else 'advance current Jeff item with verified evidence'
    end,
    'ran_at',now()
  );

  update jo_core.objectives
  set last_run_at=now(),next_run_at=date_trunc('hour',now())+interval '1 hour',updated_at=now()
  where objective_id=o.objective_id;

  -- Worker status is derived by sync_worker_state from jobs and live leases.

  insert into jo_core.events(worker_key,event_type,detail) values('jeff','manager_cycle',result);
  return result;
end
$function$;


CREATE OR REPLACE FUNCTION jo_core.run_steve_manager_cycle()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o record; s record; blockers jsonb; result jsonb;
begin
  select * into o from jo_core.objectives
  where worker_key='steve' and objective_type='mcr_launch' and status='active'
  for update skip locked limit 1;
  if o.objective_id is null then return jsonb_build_object('ran',false,'reason','no_active_objective'); end if;

  if exists(
    select 1 from jo_core.steve_launch_stages
    where stage_key='clean_rerun' and status='verified'
  ) then
    update jo_core.steve_launch_stages
    set status='pending',updated_at=now()
    where stage_key='live_mode_conversion' and status='parked';
  end if;

  if exists(
    select 1 from jo_core.steve_launch_stages
    where stage_key='live_mode_conversion' and status='verified'
  ) then
    update jo_core.steve_launch_stages
    set status='pending',updated_at=now()
    where stage_key='first_paying_customer' and status='parked';
  end if;

  select x.* into s
  from jo_core.steve_launch_stages x
  where x.status in ('working','pending')
    and (
      not (x.evidence ? 'depends_on')
      or exists(
        select 1 from jo_core.steve_launch_stages dep
        where dep.stage_key=x.evidence->>'depends_on'
          and dep.status='verified'
      )
    )
    and (
      not (x.evidence ? 'requires')
      or not exists(
        select 1
        from jsonb_array_elements_text(x.evidence->'requires') req(stage_key)
        left join jo_core.steve_launch_stages dep on dep.stage_key=req.stage_key
        where dep.stage_key is null or dep.status<>'verified'
      )
    )
  order by case when x.status='working' then 0 else 1 end,x.sequence_no
  limit 1;

  if s.stage_key is not null and s.status='pending' then
    update jo_core.steve_launch_stages set status='working',updated_at=now()
    where stage_key=s.stage_key
    returning * into s;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'stage_key',stage_key,'title',title,'status',status,'owner_action_required',owner_action_required,
    'external_system',external_system,'last_error',last_error
  ) order by sequence_no),'[]'::jsonb)
  into blockers
  from jo_core.steve_launch_stages
  where status in ('blocked_owner','blocked_external');

  result:=jsonb_build_object(
    'ran',true,
    'current_stage',case when s.stage_key is null then null else jsonb_build_object(
      'stage_key',s.stage_key,'title',s.title,'status',s.status,'external_system',s.external_system,
      'evidence',s.evidence
    ) end,
    'blockers',blockers,
    'next_action',case
      when s.stage_key='owner_notification' then 'exercise and verify owner notification path using safe test data and persisted evidence'
      when s.stage_key='real_reply_capture' then 'run real reply capture and verify provider + database state transition'
      when s.stage_key='sandbox_billing_success' then 'run fresh sandbox payment and verify persisted business-state change'
      when s.stage_key='clean_rerun' then 'run the entire customer journey in one clean verified sequence'
      when s.stage_key='live_mode_conversion' then 'convert verified sandbox configuration to LIVE only after owner approval/credentials'
      when s.stage_key='first_paying_customer' then 'begin approved first-customer outreach and verify first payment'
      when s.stage_key is null then 'continue remediation of blocked dependencies and preserve verified components'
      else 'advance current launch stage with authoritative proof'
    end,
    'ran_at',now()
  );

  update jo_core.objectives
  set last_run_at=now(),next_run_at=date_trunc('hour',now())+interval '1 hour',updated_at=now()
  where objective_id=o.objective_id;

  -- Worker status is derived by sync_worker_state from jobs and live leases.

  insert into jo_core.events(worker_key,event_type,detail) values('steve','manager_cycle',result);
  return result;
end
$function$;


CREATE OR REPLACE FUNCTION team_v4.reap_expired_leases()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE j record; n integer := 0; recovered_status team_v4.job_status;
BEGIN
  -- Concurrent minute ticks must not divide expired jobs and then deadlock on runs.
  IF NOT pg_try_advisory_xact_lock(hashtextextended('team_v4.reap_expired_leases',0)) THEN RETURN 0; END IF;
  FOR j IN
    SELECT * FROM team_v4.jobs
    WHERE lease_expires_at < now()
    FOR UPDATE SKIP LOCKED
  LOOP
    recovered_status := j.status;
    IF j.status IN ('queued','in_progress','stalled') THEN
      recovered_status := CASE WHEN j.attempts + 1 >= j.max_attempts
        THEN 'failed'::team_v4.job_status ELSE 'stalled'::team_v4.job_status END;
      UPDATE team_v4.jobs SET status=recovered_status,
        attempts=attempts+1, no_progress_cycles=no_progress_cycles+1,
        last_error=CASE WHEN recovered_status='failed'
          THEN 'Worker lease expired; retry budget exhausted'
          ELSE 'Worker lease expired; bounded retry pending' END,
        lease_owner=NULL, lease_expires_at=NULL
      WHERE job_id=j.job_id;
      INSERT INTO team_v4.execution_attempts
        (job_id,step_index,worker_id,started_at,finished_at,result,error,checkpoint)
      VALUES (j.job_id,j.current_step_index,coalesce(j.lease_owner,'lease-reaper'),
        least(j.lease_expires_at,now()),now(),'transient_failure',
        'Worker lease expired without completion',
        jsonb_build_object('source','scheduled_lease_recovery','attempts',j.attempts+1,
          'max_attempts',j.max_attempts,'resulting_status',recovered_status));
      n := n+1;
    ELSE
      -- A stale lease must never resurrect done/cancelled work, erase an owner
      -- blocker, or rerun a step already awaiting independent verification.
      UPDATE team_v4.jobs SET lease_owner=NULL,lease_expires_at=NULL
      WHERE job_id=j.job_id;
    END IF;
    INSERT INTO jo_core.events(worker_key,job_id,event_type,detail)
    VALUES(lower(j.role::text),j.job_id,'worker_lease_recovered',
      jsonb_build_object('previous_status',j.status,'resulting_status',recovered_status,
        'previous_lease_owner',j.lease_owner,'expired_at',j.lease_expires_at,
        'external_work_verified',false,'owner_escalation_created',false));
  END LOOP;
  UPDATE team_v4.worker_runs SET ended_at=now(),
    outcome='lease_expired',failure_reason='Lease expired before valid worker completion'
  WHERE run_id IN (SELECT run_id FROM team_v4.worker_runs
    WHERE ended_at IS NULL AND lease_expires_at<now() FOR UPDATE SKIP LOCKED);
  RETURN n;
END $function$;
