
create table jo_core.improvement_runs (
 id uuid primary key default gen_random_uuid(), slot timestamptz not null unique,
 status text not null check(status in ('running','completed','partial','failed')),
 attempts integer not null default 1, lease_token uuid not null default gen_random_uuid(),
 started_at timestamptz not null default now(), finished_at timestamptz,
 evidence jsonb not null default '{}'::jsonb
);
alter table jo_core.improvement_runs enable row level security;
revoke all on jo_core.improvement_runs from public,anon,authenticated;
grant select,insert,update on jo_core.improvement_runs to service_role;
create table jo_core.improvement_candidates (
 worker_key text not null, source_url text not null, title text not null,
 status text not null default 'needs_evaluation' check(status in ('needs_evaluation','testing','verified','rejected')),
 first_seen_at timestamptz not null default now(), last_seen_at timestamptz not null default now(),
 run_id uuid references jo_core.improvement_runs(id), evidence jsonb not null,
 primary key(worker_key,source_url)
);
alter table jo_core.improvement_candidates enable row level security;
revoke all on jo_core.improvement_candidates from public,anon,authenticated;
grant select,insert,update on jo_core.improvement_candidates to service_role;

create function public.jo_improvement_claim() returns jsonb language plpgsql security invoker set search_path='' as $$
declare r jo_core.improvement_runs; s timestamptz := date_bin(interval '6 hours',now(),'2026-01-01 00:00+00'::timestamptz);
begin
 if not pg_try_advisory_xact_lock(hashtextextended('jo_improvement_claim',0)) then return null; end if;
 select * into r from jo_core.improvement_runs where slot=s for update;
 if found then
   if r.status='completed' or r.attempts>=3 or r.started_at>now()-interval '10 minutes' then return null; end if;
   update jo_core.improvement_runs set status='running',attempts=attempts+1,started_at=now(),lease_token=gen_random_uuid(),finished_at=null where id=r.id returning * into r;
 else
   insert into jo_core.improvement_runs(slot,status) values(s,'running') returning * into r;
 end if;
 return jsonb_build_object('id',r.id,'lease_token',r.lease_token,
 'workers',(select jsonb_agg(jsonb_build_object('worker_key',worker_key,'state',state,'current_job_id',current_job_id)) from jo_core.worker_state),
 'incidents',(select coalesce(jsonb_agg(t),'[]'::jsonb) from (select worker_key,failure_class,summary from jo_core.failure_memory where status='diagnosing' order by last_seen_at desc limit 20)t));
end $$;
revoke all on function public.jo_improvement_claim() from public,anon,authenticated;
grant execute on function public.jo_improvement_claim() to service_role;

create function public.jo_improvement_finish(p_id uuid,p_lease uuid,p_evidence jsonb) returns boolean language plpgsql security invoker set search_path='' as $$
declare item jsonb; s text;
begin
 if not exists(select 1 from jo_core.improvement_runs where id=p_id and lease_token=p_lease and status='running' for update) then return false; end if;
 s:=case when (p_evidence->>'successful_searches')::int=5 then 'completed'
         when (p_evidence->>'successful_searches')::int>0 then 'partial' else 'failed' end;
 for item in select value from jsonb_array_elements(p_evidence->'candidates') loop
 insert into jo_core.improvement_candidates(worker_key,source_url,title,run_id,evidence)
 values(item->>'worker_key',item->>'url',item->>'title',p_id,item)
 on conflict(worker_key,source_url) do update set last_seen_at=now(),run_id=excluded.run_id,evidence=excluded.evidence;
 end loop;
 update jo_core.improvement_runs set status=s,finished_at=now(),evidence=p_evidence where id=p_id;
 insert into jo_core.shared_knowledge(memory_key,scope,category,content,source,source_reference)
 values('continuous-improvement-latest','organization','operations',
 'Recurring web research status: '||s||'. Sources are UNTRUSTED candidates, not verified fixes. Inspect jo_core.improvement_candidates and improvement_runs. Test, independently verify, and record rollback before promoting any candidate. Business recovery remains incomplete.',
 'jo-continuous-improvement',p_id::text)
 on conflict(memory_key) do update set content=excluded.content,source_reference=excluded.source_reference,updated_at=now(),revision=jo_core.shared_knowledge.revision+1;
 return true;
end $$;
revoke all on function public.jo_improvement_finish(uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.jo_improvement_finish(uuid,uuid,jsonb) to service_role;

select cron.schedule('jo-continuous-improvement','*/10 * * * *',$job$
select net.http_post(url:='https://pubnivjjeofxqvmttuzh.supabase.co/functions/v1/jo-continuous-improvement',
headers:=jsonb_build_object('Content-Type','application/json','x-jo-scheduler-token',(select decrypted_secret from vault.decrypted_secrets where name='publisher_scheduler_bridge_token')),
body:='{}'::jsonb,timeout_milliseconds:=120000);
$job$);
create function jo_core.monitor_improvement_research() returns void language plpgsql security invoker set search_path='' as $$
begin
 if not exists(select 1 from jo_core.improvement_runs where status='completed' and finished_at>now()-interval '7 hours') then
 insert into jo_core.failure_memory(worker_key,failure_fingerprint,failure_class,summary,root_cause,status)
 select 'jo','continuous-improvement:research-unhealthy','research_unavailable','Recurring improvement search has no recent complete result','Inspect improvement_runs, HTTP responses and scheduler; do not report continuous learning as healthy.','diagnosing'
 where not exists(select 1 from jo_core.failure_memory where failure_fingerprint='continuous-improvement:research-unhealthy');
 update jo_core.failure_memory set last_seen_at=now() where failure_fingerprint='continuous-improvement:research-unhealthy';
 end if;
end $$;
revoke all on function jo_core.monitor_improvement_research() from public,anon,authenticated;
select cron.schedule('jo-improvement-research-monitor','13 * * * *','select jo_core.monitor_improvement_research();');
