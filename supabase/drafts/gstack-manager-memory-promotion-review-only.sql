-- REVIEW ONLY. Requires registry schema and reviewed backend authorization.
-- IMPORTANT: Only a trusted backend may call this after authenticating the manager.
-- Never expose this function through a public API or grant EXECUTE to anon/authenticated.
-- Does not approve unverified claims; it atomically records manager approval and company memory.
create or replace function gstack.promote_verified_checkpoint(
 p_checkpoint_id uuid,p_manager_key text,p_verification_ref text
) returns text
language plpgsql security definer set search_path=pg_catalog,gstack,jo_core,pg_temp
as $$
declare
 v_cp record;
 v_key text;
 v_revision integer;
 v_existing record;
begin
 if current_user <> 'postgres' and session_user <> 'postgres' then
   raise exception 'Promotion restricted to trusted database backend';
 end if;
 if nullif(trim(p_verification_ref),'') is null then
   raise exception 'Independent verification reference required';
 end if;
 select cp.*, a.manager_key as actual_manager, a.status as agent_status
 into v_cp
 from gstack.agent_memory_checkpoints cp
 join gstack.department_agents a on a.agent_id=cp.agent_id
 where cp.checkpoint_id=p_checkpoint_id for update of cp;
 if not found then raise exception 'Checkpoint not found'; end if;
 if v_cp.manager_key is distinct from p_manager_key
    or v_cp.actual_manager is distinct from p_manager_key then
   raise exception 'Manager does not own checkpoint';
 end if;
 if v_cp.agent_status not in ('idle','working') then
   raise exception 'Agent is not active';
 end if;
 if v_cp.sensitivity<>'company_candidate'
    or v_cp.verification_status<>'verified'
    or v_cp.verified_at is null
    or nullif(trim(v_cp.evidence_ref),'') is null then
   raise exception 'Checkpoint is not verified for company sharing';
 end if;
 v_key:='gstack.lesson.'||p_checkpoint_id::text;
 select decision,company_memory_key into v_existing
 from gstack.memory_promotions where checkpoint_id=p_checkpoint_id;
 if found then
   if v_existing.decision<>'approved' or v_existing.company_memory_key<>v_key then
     raise exception 'Checkpoint has conflicting promotion decision';
   end if;
   return v_key;
 end if;
 -- Stable unique memory key per checkpoint avoids overwriting unrelated knowledge.
 v_revision:=1;
 insert into jo_core.shared_knowledge
 (memory_key,scope,scope_key,category,content,status,source,source_reference,verified_at,revision)
 values(v_key,'organization',null,'lesson',v_cp.claim,'active',
        'gstack.manager_approved',v_cp.evidence_ref,v_cp.verified_at,v_revision);
 insert into gstack.memory_promotions
 (checkpoint_id,manager_key,decision,verification_ref,company_memory_key)
 values(p_checkpoint_id,p_manager_key,'approved',p_verification_ref,v_key);
 return v_key;
end $$;
revoke all on function gstack.promote_verified_checkpoint(uuid,text,text) from public;
-- Review needed: current_user/session_user checks must be tested with actual
-- Supabase service-role invocation; SECURITY DEFINER changes current_user.
-- Verify authorization in an audited gateway using JWT claims / service credentials.
-- Do not grant to clients. A caller-supplied manager key is NOT authentication.
-- Integration tests must include cross-manager denial, unverified denial,
-- sensitive-memory denial, duplicate retry, and atomic rollback on conflict.
