# Jo OS — G Stack departmental agent cloning and memory charter

Status: approved organizational direction; implementation and end-to-end verification pending. This document is policy, not evidence that provisioning works.

## Chain of command
Owner -> Jo (COO) -> Tom, Mary, Steve, Jeff -> permanent departmental agent instances.
Jo may also maintain her own executive agents for operations audit, recovery, briefings, memory stewardship, resource coordination, and quality verification.

## Clone lifecycle
1. Manager requests a capability and checks the approved G Stack registry before creating anything.
2. Provision a distinct agent instance from a versioned template; preserve the original template.
3. Assign a persistent agent ID, manager ID, department, capabilities, permitted tools, budgets and scoped memory.
4. The instance remains assigned to its manager when idle; idle agents do not require continuously running compute.
5. Jo can audit, suspend, reassign or retire instances. Retirement preserves authorized durable lessons.
6. No unapproved spending, paid accounts, publication, legal commitments, external messaging, credential copying or privilege escalation.

## Memory chain
Agent -> its manager's department memory -> manager verification -> company memory bank.
Company memory -> authorized managers -> their agents.
Each checkpoint records job ID, agent ID, observation, result, supporting evidence, confidence, timestamp, sensitivity and provenance. Mark claims as unverified until evidence is checked. Never promote a heartbeat or mere task assignment as success.
Managers decide what is reusable; Jo audits promotions and can quarantine disputed or sensitive claims.
Keep secrets, customer data, financial details and restricted department context out of company-wide memory unless explicitly permitted. Enforce server-side authorization, not just prompt instructions.
A master template update must not overwrite an instance's departmental memory.

## Independence and evidence
Each department and Jo's executive agents must have independently scheduled/triggered execution, leases, checkpoints, recovery and proof. A manager's outage must not stop already-authorized work. A clone's completion requires destination evidence where relevant.
Jo's 7:30 AM and 7:30 PM Eastern briefings must report verified results, misses, recovery and owner-only blockers, and must be proven delivered rather than only generated.

## Acceptance tests before calling this operational
- Discover a real approved G Stack template and clone it without altering the master.
- Clone the same template into two departments with distinct IDs and isolated memory.
- Verify clone-to-manager checkpoint and manager-to-company promotion with provenance and access controls.
- Verify company-to-manager-to-clone knowledge retrieval with no cross-department private leakage.
- Verify independent scheduled work, no-spend guard, revocation, recovery and audit trail.
- Verify Jo can oversee her own clones and department clones without becoming a single point of failure.
- Re-run end-to-end checks and retain evidence; NO PROOF = NOT DONE.
