# /goal — JO OS FULL AUTONOMOUS PRODUCTION RECOVERY

**Owner:** Tony Sottile  
**Date:** October 19, 2026  
**Priority:** CRITICAL  
**Execution mode:** Autonomous production recovery  
**Mission:** Restore Jo, Tom, Mary, Steve, and Jeff to independently verified reliable production operation.

> This is an execution assignment, not a plan or documentation-only task. Discover → Diagnose → Repair → Deploy → Test → Execute → Independently Verify → Recover → Continue. **NO PROOF = NOT DONE.** Do not require Tony to say “next.” Follow AGENTS.md; this assignment does not supersede security, owner approval, or provider restrictions.

## Systems to inspect

- GitHub: `tonysottile-hub/Jo-OS`. Read AGENTS.md, workflows, latest commits, checkpoints and execution logs before changing anything.
- Primary Supabase: `pubnivjjeofxqvmttuzh`: `jo_core` (management, workers, scheduling and memory), `team_v4` (jobs, execution, leases and verification), `public` (production/publishing), `gstack` (where installed).
- Missed Call Rescue Supabase: `ibiuhwxypusbuurtmyzk`.
- Authorized destinations: YouTube, Fourthwall, TikTok Shop, Facebook/LinkedIn where authorized, Stripe TEST, Twilio subject to provider approval, Gmail and other explicitly authorized integrations.
- Destination-side evidence is authoritative; database labels and successful job triggers alone do not prove an outcome.

## Historical checkpoint — RECHECK LIVE, do not treat as current status

- Jeff previously completed independent public website audit with GitHub evidence.
- Tom previously completed research/video production; public publishing remains unverified.
- Hamilton, Nevada long-form rendered in GitHub Actions run `39224054576`, artifact `12172991782`, approximately 157 seconds, 1920x1080 H.264/AAC. Automated render QA passed; human-independent content QA and YouTube publication unverified.
- Hamilton job `46773a2a-9b09-4e35-9136-f4b5f180ae53` was `verify_pending` with no active lease. Render request had `publish_authorized: false`. **Do not publish unless authorization is established.**
- Historical counts: Tom 3 failed/5 stalled/1 awaiting verification; Mary 5 stalled/3 awaiting verification/4 in progress; Jo 2 stalled; Steve and Jeff owner-blocked.
- Do not restart verified work or duplicate Tom's separately running recovery worker.

## Priority zero — verified owner-visible progress reporting

Make verified progress reporting an early recovery priority, alongside safe recovery of Jo's central execution loop. Reuse the existing Jeff/Jo reporting workflow and existing scheduled tasks; **do not create duplicate automations** or consume an additional task slot.

- Deliver owner-visible briefings at **7:30 AM and 7:30 PM America/New_York**, using the already authorized delivery channel. Confirm delivery at the destination, not merely a created briefing row, log or job.
- Report Jo's manager/watchdog health, each worker's real status, confirmed outputs and destination evidence links, failed or stalled work, current recovery action, and genuine owner-only blockers.
- For Tom, only count public YouTube links as published; for Mary, include live verified product links; for Steve, isolate TEST evidence and provider approvals; for Jeff, confirm briefing and inbox-monitor delivery.
- Between briefings, notify Tony **only** when a new major milestone is independently verified or a genuine owner-only action is required. Do not spam ordinary retries or report historical successes as new.
- Record `scheduled_at`, `delivered_at`, destination/message identifier (if available), independent verifier, and failures/retries in durable Jo OS state.
- **Jeff is the designated reporting backup to Jo.** If Jo's reporting pipeline is unavailable, delayed beyond its delivery deadline, or fails verification, Jeff should claim a separately identified reporting-failover job with a bounded lease, gather fresh read-only evidence directly from authoritative systems, and deliver the scheduled owner briefing through an already authorized route. If Jo recovers mid-run, enforce idempotency to avoid duplicate deliveries. Jeff may not independently certify his own output: a separate verifier or destination receipt must confirm delivery. Jeff may not override owner approvals, access new credentials, or take unrestricted control of Jo's manager role. Escalate if both primary and backup delivery routes fail.
- On missed delivery, retry with bounded backoff, verify receipt, and open a recovery incident without stopping other worker lanes. After repair, verify **at least two consecutive scheduled briefing deliveries** and demonstrate unattended recovery from a delivery failure.
- Never declare progress-reporting restored based solely on GitHub edits, successful cron triggers, database rows or a test that did not deliver the report to Tony.

## Jo — central manager (first infrastructure priority)

Maintain live heartbeats, unique worker identities, bounded job leases, automatic detection of failures/stalls/expired leases, bounded retries with backoff, independent verification, durable checkpoints/failure memory, owner-only escalation and continuation of unrelated work during single-lane failures. Inspect and repair executors, watchdog and scheduled functions without disrupting known-good components. Demonstrate multiple unattended recovery cycles.

## Tom — Unmapped America

- One Short daily; long-form every Monday, Wednesday and Friday. Track and recover Shorts and long-form backlogs separately, using zero-additional-cost distribution.
- Inspect actual channel, OAuth, publisher, renderer, media storage, QA and publishing records.
- Independently QA Hamilton; never publish while `publish_authorized=false` absent later explicit authorization.
- Coordinate with existing hourly worker. Public YouTube URL on the correct channel is required to count an item as published.
- Accept only after repeated scheduled publications with valid content and public destination proof.

## Mary — Cigar 30

- Official owner-approved Cigar 30 chest logo only; left-chest shield and large approved back art. Never invent approval or publish unapproved art. Men's sizes through 5XL where supported. No unauthorized spending.
- Inspect Fourthwall and TikTok Shop; recheck October 19 checkpoint of 29 active, 0 pending and 0 denied.
- Find approved items missing, hidden, incorrectly configured or unpublished; restore only approved backlog. Follow Thursday approval/publishing direction.
- Prepare promotional videos for approved products and Facebook/LinkedIn drafts; publish to social channels only with specific authorization.
- Verify public customer product pages, design accuracy, sizes and visibility. Do not reactivate canceled Canva trial.

## Steve — Missed Call Rescue

Inspect MCR Supabase, Stripe TEST integration, Twilio approval/status, onboarding and logs. Verify isolated no-charge test journey: signup → test payment → onboarding → missed-call detection → automatic SMS → reply capture → business notification → payment-failure handling → cancellation. Use synthetic/test identities only; no real customer messages or live charges. Isolate actual provider/credential approvals and continue unblocked engineering. Accept only with independently verified isolated end-to-end results and later approved provider-dependent checks.

## Jeff — administration

Restore visible 7:30 AM and 7:30 PM Eastern briefings, authorized hourly inbox monitoring, preservation of customer/vendor/event/financial/security email, and evidence-backed website monitoring. Verify briefing delivery itself, not just database insertion. Require repeated accurate delivery with links/evidence.

## G Stack and durable memory

Verify specialist agents truly execute; files/config definitions alone do not establish installation. Delegation chain: **Jo → Worker Manager → Specialist Clone → Worker Manager → Shared Company Memory**. Test permission-limited delegation, evidence return, Jo reporting, durable memory read/write, interrupted-worker recovery and prevention of unauthorized actions. Supabase operational state remains authoritative.

## Milestones in order

1. Jeff web audit — previously verified; don't reannounce.
2. Tom research and video production — previously verified; public posting is separate.
3. Mary and Steve execute authorized workflows independently.
4. Shared reporting and automated recovery.
5. All five workers pass end-to-end acceptance tests and repeated unattended recovery cycles.

For each milestone persist: actual execution, independent verifier, evidence URL/location, timestamp, limitations and next action. Do not claim 100% completion before each worker passes all applicable acceptance checks and repeat unattended cycles.

## Execution and safety rules

- Carry out approved low-risk non-destructive repairs without routine owner prompts; avoid duplicate scheduled jobs and preserve five-active-task arrangement.
- Claim jobs with unique worker ID/bounded lease and release/close them safely.
- Maintain precise evidence, checkpoints, actionable recovery notes; never replace verified truth with optimistic status.
- No new charges, higher tiers, exposed credentials, destructive changes, unapproved publishing, live customer outreach, or personal medical information in operations.
- Escalate only actual owner-only login/MFA, legal, sensitive credential, spending, or approval actions.
- Report to Tony only major newly verified milestones or true owner blockers; put routine details into Jo OS.

## Terminal acceptance standard

Jo, Tom, Mary, Steve and Jeff independently execute authorized work, deliver real independently verified destination outcomes, accurately report, retain memory and recover ordinary failures without repeated user intervention.

**Start by reading AGENTS.md and current production checkpoints, then execute the highest-priority safe repair.** Committing this directive is not proof that recovery has started or succeeded.
