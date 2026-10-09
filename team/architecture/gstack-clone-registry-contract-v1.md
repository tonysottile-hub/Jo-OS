# G Stack clone registry — implementation contract (v1)

Status: specification and integration boundary; NOT an active provisioner.

## Existing live sources
Supabase project pubnivjjeofxqvmttuzh has jo_core.capability_registry (action, handler, executor, enabled, risk, reason, updated_at) and jo_core.shared_knowledge (scope, scope_key, status, provenance, revision). Neither is a registry of clonable agent templates or persistent clone instances. Never present capability_registry entries as hireable agents without explicit template metadata and a tested provisioner.

## Required data model
- gstack_templates: template_id, version, approved, capability_set, tool_allowlist, instruction_ref, resource_limits, provenance, source_revision.
- department_agents: agent_id, template_id, template_version, manager_key, department_key, status, permissions_ref, created_at, last_execution_at, last_verified_at. Manager key must be jo, tom, mary, steve, or jeff.
- agent_assignments: assignment_id, agent_id, job_id, status, lease, checkpoint_ref, verification_ref, retry_state.
- agent_memory_checkpoints: checkpoint_id, agent_id, manager_key, job_id, claim, outcome, evidence_ref, sensitivity, verified_status, recorded_at.
- department_memory_promotions: checkpoint_id, manager_key, verification_ref, decision, company_memory_key, promoted_at, reason.

## Nonnegotiable guards
Master templates remain unchanged by cloning. Every clone gets a distinct persistent ID and scoped permissions. Only approved templates and existing zero-additional-cost resources are allowed. No credential duplication, unapproved publishing, spending, legal commitments, or external communications. A clone may not self-promote company memory; its manager verifies and approves promotion, with Jo audit oversight. Sensitive information stays private and company reads obey server-side authorization. Persist rejected promotions with reasons.

## Deployment order
1. Discover and verify actual G Stack template source, version, permissions and licensing.
2. Add schema with constraints, RLS, manager-specific access and audit events in a reviewed migration.
3. Build idempotent clone provisioner with template version pinning, manager quotas and safe retries.
4. Implement clone -> manager checkpoint and manager -> company memory promotion.
5. Connect company -> manager -> clone retrieval and independent scheduled execution.
6. Test clone isolation, owner approval gates, recovery, and real evidence before marking live.

## Acceptance
Clone a single approved template into Tom and Jeff with unique IDs, no shared private memory, correct manager ownership and persistent idle status. Verify authorized lessons can be promoted by each manager into jo_core.shared_knowledge with evidence, then read by authorized departments. Verify Jo's own executive clone and that an unavailable Jo does not halt other authorized departments. Keep Tom's production pipeline untouched during rollout.
