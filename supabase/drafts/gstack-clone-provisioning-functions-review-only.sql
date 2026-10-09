-- REVIEW ONLY. Requires gstack-clone-registry-review-only.sql first.
-- The service-role backend must authenticate the caller and derive manager_key
-- from its trusted identity. Never accept manager_key from an untrusted client.
-- Grant EXECUTE only to a reviewed backend role after deployment.

create or replace function gstack.provision_department_agent(
 p_request_key text, p_template_id text, p_version text, p_manager_key text
) returns uuid
language plpgsql security definer set search_path = pg_catalog, gstack, pg_temp
as $$
declare v_id uuid; v_existing record;
begin
 if current_user <> 'postgres' and session_user <> 'postgres' then
   raise exception 'Provisioning restricted to trusted database backend';
 end if;
 if p_request_key is null or length(trim(p_request_key)) < 8 then
   raise exception 'Idempotency key required';
 end if;
 if p_manager_key not in ('jo','tom','mary','steve','jeff') then
   raise exception 'Unknown manager';
 end if;
 if not exists(select 1 from gstack.templates
   where template_id=p_template_id and version=p_version and approved) then
   raise exception 'Template is not approved';
 end if;
 select agent_id,template_id,template_version,manager_key into v_existing
 from gstack.department_agents where provision_request_key=p_request_key;
 if found then
   if v_existing.template_id<>p_template_id or v_existing.template_version<>p_version
      or v_existing.manager_key<>p_manager_key then
     raise exception 'Idempotency key reused with different inputs';
   end if;
   return v_existing.agent_id;
 end if;
 insert into gstack.department_agents
 (provision_request_key,template_id,template_version,manager_key)
 values(p_request_key,p_template_id,p_version,p_manager_key)
 on conflict(provision_request_key) do nothing returning agent_id into v_id;
 if v_id is null then
   select agent_id,template_id,template_version,manager_key into v_existing
   from gstack.department_agents where provision_request_key=p_request_key;
   if v_existing.template_id<>p_template_id or v_existing.template_version<>p_version
      or v_existing.manager_key<>p_manager_key then
     raise exception 'Concurrent idempotency conflict';
   end if;
   v_id:=v_existing.agent_id;
 end if;
 return v_id;
end $$;

create or replace function gstack.submit_agent_checkpoint(
 p_agent_id uuid,p_manager_key text,p_job_ref text,p_claim text,
 p_evidence_ref text,p_sensitivity text
) returns uuid
language plpgsql security definer set search_path = pg_catalog,gstack,pg_temp
as $$
declare v_id uuid;
begin
 if current_user <> 'postgres' and session_user <> 'postgres' then
   raise exception 'Checkpoint restricted to trusted database backend';
 end if;
 if not exists(select 1 from gstack.department_agents where agent_id=p_agent_id
   and manager_key=p_manager_key and status in ('idle','working')) then
   raise exception 'Agent not active under manager';
 end if;
 if nullif(trim(p_job_ref),'') is null or nullif(trim(p_claim),'') is null then
   raise exception 'Job and claim required';
 end if;
 insert into gstack.agent_memory_checkpoints
 (agent_id,manager_key,job_ref,claim,evidence_ref,sensitivity)
 values(p_agent_id,p_manager_key,p_job_ref,p_claim,p_evidence_ref,p_sensitivity)
 returning checkpoint_id into v_id;
 return v_id;
end $$;

-- Promotion must be a separate reviewed transaction:
-- lock checkpoint + agent; verify manager ownership, evidence, sensitivity,
-- verification status, and a trusted verifier; insert promotion; then insert
-- an approved, versioned jo_core.shared_knowledge record atomically.
-- Do not auto-promote checkpoints from the submission function.
revoke all on function gstack.provision_department_agent(text,text,text,text) from public;
revoke all on function gstack.submit_agent_checkpoint(uuid,text,text,text,text,text) from public;
