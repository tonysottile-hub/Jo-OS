# Jo OS — ECC-assisted development rollout

Status: integration planning branch; ECC CLI installation and runtime activation NOT yet verified.

Reference: https://github.com/WorldFlowAI/everything-claude-code
Review the upstream repository and pin an audited commit before installation. Do not run unreviewed third-party hooks or grant production secrets to agents.

## Acceptance gates (no proof = not done)
1. Inventory current Jo OS code, Supabase schema/functions, workflows, secrets boundaries and production dependencies.
2. Evaluate ECC compatibility with the chosen coding environment; install only approved, pinned components in an isolated development workspace.
3. Memory: persist/retrieve scoped conversations and task history; verify across independent sessions; enforce access controls and retention.
4. Browser automation: allowlisted domains, session isolation, owner approvals for purchases/sends/destructive actions, audit logs, timeout and recovery; test end to end.
5. Tom: verify daily YouTube short and M/W/F long uploads by published platform IDs, including catch-up lane.
6. Mary: test authorized Facebook/LinkedIn publishing and capture published IDs.
7. Steve: verify complete MCR signup-to-cancellation flow without using real customer data in tests.
8. Jeff: verify email/admin actions and evidence trails.
9. Jo: reliable morning/evening briefings, dispatch, monitoring, retries, alerts, dashboard, and proof-backed reporting.
10. Run automated unit/integration/security tests and controlled staging smoke tests; report measured coverage, not assumed 80%.
11. Production release only after reviewed changes, rollback plan, verified end-to-end checks and explicit approvals where required.

Never interpret an active Edge Function or healthy Supabase project as proof of successful publishing.
