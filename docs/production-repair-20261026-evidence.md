# Production repair evidence — October 26, 2026

Status: PARTIAL REPAIR; full production acceptance is not satisfied.

## Deployed repair

Migration production_reconciliation_and_gstack_draft_handoff:
- 133 Team V4 jobs classified in jo_core.production_reconciliation. ID a54dce5f-e3ba-4633-a0a0-dc19b70e0685.
- Three Mary in_progress jobs with no lease/live run repaired to stalled, with audit events, without retrying or changing approvals. Zero orphaned in_progress remain.
- Five bounded-draft specialists registered, one per manager, bound to the existing jo-draft-executor v1. These are limited drafting roles, not general autonomous tool-using agents or vendor qa-only agents.
- Immutable manager assignment, active/approved template checks, draft-to-unverified-checkpoint handoff, private RLS tables, and five-minute cloud dispatch schedule.
- Schedule cannot enable inference: it requires enabled policy, model, approval reference, and eligible tasks.
- Five worker-specific tasks persisted as blocked pending provider key and owner inference policy.
- No real model execution, real checkpoint or memory promotion occurred. Counts: 5 registered agents, 0 real checkpoints, 0 promotions.
- Existing Rio, publisher-api, jo-command-ingress and other Edge Functions were not redeployed.

## Tests

Transactionally rolled-back tests pass for agent assignment, cross-manager rejection, checkpoint handoff, unverified promotion rejection, and private permissions. Synthetic output was never committed. Reconciliation rerun accounts for all 133, repairs zero additional jobs, preserves done and owner-blocked states.
Advisors: no new executable SECURITY DEFINER exposure; two expected RLS-with-no-policy informational entries for private new tables.

## Reconciliation counts

| Classification | Jobs |
|---|---:|
| Done with separate verification record, scope still needs review | 58 |
| Done without separate verification record | 25 |
| Adapter available, inspect evidence before recovery | 27 |
| Independent verification required | 5 |
| Downstream dependency gate | 5 |
| Missing current step | 2 |
| Missing executable handler | 3 |
| Owner dependency | 2 |
| Failed/quarantined, review before retry | 6 |

A missing separate verification record does not prove external work never happened. No bulk rerun, blind retry, or false completion was applied.

## Runtime blocker — live proof

Authenticated cloud capability probe request 299433 returned HTTP 200:
openai_api_key_present=false; anthropic_api_key_present=false; tavily_api_key_present=false.
Draft runtime policy: enabled=false, model=null, approval_reference=null, daily_call_limit=5.
Required owner step: install OPENAI_API_KEY through Supabase Edge Function secrets, select/authorize model and spending ceiling. Then revalidate provider access, enable bounded policy, release the five blocked tasks, and verify actual model response -> manager review -> independent checkpoint verification -> memory promotion. A key alone does not implement missing business tool handlers.

## Existing external evidence checked this turn

Mary scheduled GitHub run 40427924891, main a6821ee1a5590c531a592e58c49def52814626ac, succeeded; independent HTTP storefront check recorded 2026-10-27 00:41:25 UTC. Scope is public pages only, not checkout or autonomous merchandise production.
Jeff scheduled run 40428501419 on same main succeeded; public cigars30jax.com HTTP 200 recorded 00:46:48 UTC. Does not prove inbox work or briefing delivery.
Both run status/event=schedule independently read from GitHub and matched stored cloud_audit_runs.

## Worker acceptance still outstanding

- Jo: all-worker business acceptance stalled. Cloud schedules succeeded repeatedly, but scheduler success does not prove execution of missing handlers.
- Mary: registered Christmas completion record contains four PUBLIC products and historical cart evidence, explicitly autonomous_mary_execution_proven=false. Current recurring public-page audit succeeds. Broad artwork, cart, checkout, TikTok and independent production requirements remain separate.
- Tom: Hamilton render job 46773a2a-9b09-4e35-9136-f4b5f180ae53 remains verify_pending; stored automated QA covers 12 checks and a 157-second artifact, but full perceptual review is absent and publish_authorized=false. No publishing performed.
- Steve: latest stored provider status at 2026-10-27 00:07 UTC reports Twilio campaign FAILED; MCR STRIPE_SECRET_KEY missing. Prior isolated message/STOP test is not production SMS or billing acceptance.
- Jeff: public website checks proven; personal/admin job remains owner-credential-blocked. No message or briefing delivery was claimed.

No purchase, model spend, Meta publishing, SMS, or approval bypass occurred.
