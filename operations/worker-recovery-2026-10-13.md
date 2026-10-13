# Worker repair checkpoint — 2026-10-13

Production changes deployed to pubnivjjeofxqvmttuzh and committed in this repository:
- Removed manager overwrites that labeled selected work as live execution. Authoritative status sync now runs after managers.
- Added an advisory transaction lock and skip-locked run cleanup to expired-lease recovery.
- Restored the missing Jo Thanksgiving oversight steps and connected explicit dependency evidence checks.
- Connected Tom research, durable render, and publication evidence checks. Publication still requires perceptual review, authorization, and independent public-destination proof.
- Raised GitHub production handoff HTTP timeout from 5 to 60 seconds.
- Preserved stalled external dependencies as blocked rather than idle.

Verification: three consecutive scheduled cycles for cron jobs 1, 3, 15 and 28 succeeded after deployment. SQL rollback assertions passed for state consistency, existing oversight steps, rejection of unpublished video, missing fleet evidence, and prevention of false completion. No worker business job was marked done by these repairs.

Hamilton build 666e8f83-1f40-4229-88ec-d66fbdaee3b6 advanced from missing research into production preparation. GitHub media run 38392159334 reached sourcing and failed with 'Only 0 suitable Commons images downloaded'. Keep it blocked for media recovery; do not lower QA thresholds or repeat unchanged requests.

Still incomplete: legacy Rhyolite audio audition/duplicate decision; perceptual QA; Hamilton qualified licensed images; Mary product/storefront verification and missing publishing adapters; Jeff admin credential blocker. Fresh MCR health and A2P checks: STRIPE_SECRET_KEY missing; campaign IN_PROGRESS, errors empty. This is not full fleet recovery.
