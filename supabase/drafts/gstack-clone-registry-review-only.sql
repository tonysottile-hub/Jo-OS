-- JO OS G Stack clone registry schema, REVIEW-ONLY draft.
-- Do not deploy before identifying a real approved G Stack template source and reviewing RLS.
-- Existing Jo OS schemas/tables remain untouched.
begin;
create schema if not exists gstack;
create table if not exists gstack.templates (
 template_id text not null,
 version text not null,
 approved boolean not null default false,
 source_ref text not null,
 capabilities jsonb not null default '[]'::jsonb,
 tool_allowlist jsonb not null default '[]'::jsonb,
 instructions_ref text,
 resource_limits jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 primary key(template_id,version)
);
create table if not exists gstack.department_agents (
 agent_id uuid primary key default gen_random_uuid(),
 provision_request_key text not null unique,
 template_id text not null,
 template_version text not null,
 manager_key text not null check(manager_key in ('jo','tom','mary','steve','jeff')),
 status text not null default 'idle' check(status in ('idle','working','suspended','retired')),
 permissions jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 last_execution_at timestamptz,
 last_verified_at timestamptz,
 foreign key(template_id,template_version) references gstack.templates(template_id,version)
);
create table if not exists gstack.agent_memory_checkpoints (
 checkpoint_id uuid primary key default gen_random_uuid(),
 agent_id uuid not null references gstack.department_agents(agent_id),
 manager_key text not null check(manager_key in ('jo','tom','mary','steve','jeff')),
 job_ref text not null,
 claim text not null,
 evidence_ref text,
 sensitivity text not null default 'department' check(sensitivity in ('department','company_candidate','restricted')),
 verification_status text not null default 'unverified' check(verification_status in ('unverified','verified','rejected')),
 verified_at timestamptz,
 check(verification_status <> 'verified' or (evidence_ref is not null and verified_at is not null)),
 created_at timestamptz not null default now()
);
create table if not exists gstack.memory_promotions (
 promotion_id uuid primary key default gen_random_uuid(),
 checkpoint_id uuid not null unique references gstack.agent_memory_checkpoints(checkpoint_id),
 manager_key text not null check(manager_key in ('jo','tom','mary','steve','jeff')),
 decision text not null check(decision in ('approved','rejected')),
 verification_ref text,
 company_memory_key text,
 reason text,
 decided_at timestamptz not null default now(),
 check(decision <> 'approved' or (verification_ref is not null and company_memory_key is not null))
);
alter table gstack.templates enable row level security;
alter table gstack.department_agents enable row level security;
alter table gstack.agent_memory_checkpoints enable row level security;
alter table gstack.memory_promotions enable row level security;
-- SECURITY REVIEW REQUIRED BEFORE DEPLOYMENT:
-- The database constraints alone do not prove template approval, agent-manager ownership,
-- checkpoint-manager match, or verified status at promotion time.
-- Implement these as SECURITY DEFINER functions with fixed search_path and strict role checks,
-- or as triggers plus tightly restricted grants. Do not grant direct client INSERT/UPDATE.
-- Require template approved=true, reject suspended/retired agents, enforce manager ownership,
-- require verified checkpoint and company_candidate sensitivity for promotion.
-- Do not copy credentials or customer data into templates, agents or company memory.
-- No client policies. Server-side service roles only until explicit auth model is tested.
commit;
