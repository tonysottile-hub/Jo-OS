# Production repair follow-up — October 27, 2026

Deployed require_latest_completion_verification. team_v4.close_completed_jobs now rejects an older passed receipt if any newer receipt exists, with verification_id as the tie-breaker for equal timestamps. Tests passed for no-proof denial, stale-pass/newer-failure denial, and latest-valid-pass acceptance; all fixtures rolled back.

Moved 25 historical done jobs with no separate verification_results record to verify_pending, preserving original verification_evidence and recording unsupported_completion_reopened events. No re-execution, publication, or evidence deletion. This does not assert the underlying work never occurred: several have useful historical artifacts and need independent verification. Live read now reports done_without_verification=0.

New reconciliation 44a744e3-f376-48aa-9a00-583aec2de2fc covers 139 jobs (up from 133 as scheduled audits add jobs); zero further orphaned progress states found.

PR #13 remains open. Five G Stack draft tasks remain blocked with provider_key_and_owner_inference_policy_required. Inference policy remains disabled, model=null, approval_reference=null, daily_call_limit=5. No spend authorization was inferred from keep going.

Current scheduled audit evidence is mixed: Jeff run 40610495129 has a passed public-page receipt; Mary run 40595215717 has independent HTTP 200/18 product URLs but a failed overall browser receipt. Those scopes were not conflated or relabeled. Full all-worker production acceptance remains incomplete.
