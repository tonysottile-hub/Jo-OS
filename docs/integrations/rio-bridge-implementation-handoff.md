# Rio Bridge Implementation Handoff — For Jo OS (Jo, Mary, Tom)

**Issue:** Jo OS GitHub Issue #10
**Contract:** See `rio-bridge-api-contract.md` in the same folder. That contract is normative. If this handoff and the contract disagree, the contract wins.
**Date:** October 25, 2026
**Status:** READY FOR JO OS REVIEW AND BRANCH IMPLEMENTATION — bridge NOT deployed, NOT authenticated, NOT tested.

## 1. What Jo OS needs to do, in order

### Step 1 — Review (Jo)
- Review the API contract, especially: authentication, fingerprint, claim atomicity/idempotency, report evidence rules, and uncertain-outcome handling.
- Confirm the authorized destinations list: Cigar 30 Facebook Page and @cigar30jax Instagram only.
- Confirm Unmapped America destinations are still **out of scope** until Tony confirms them. Do not add them silently.

### Step 2 — Implement on a separate branch
- Create a branch from main, for example: `feature/rio-bridge`
- Implement the Supabase Edge Function `rio-bridge` only. Do not modify `publisher-api` or `jo-command-ingress` except for a regression test proving they are unchanged.
- Implement exactly these operations:
  - `GET /health`
  - `GET /health/auth`
  - `GET /approved-posts`
  - `POST /claim-post`
  - `POST /report-result`
- Store Rio credentials as hashes in `rio_integration.api_clients`. Never commit a plaintext key, a service-role key, or an owner JWT to the repo.
- Keep RLS on, with anon/authenticated access revoked, per Issue #10.

### Step 3 — Automated tests (required, must pass before review)
Run all of these, and keep them in the repo with the bridge:

**Authentication**
- [ ] No header → 401
- [ ] Wrong key → 401
- [ ] Revoked key → 401
- [ ] Valid dedicated Rio key → 200 on `/health/auth`, with `authenticated_client: "rio"`
- [ ] Owner JWT / service-role key presented as a Rio credential → rejected (must not be accepted as Rio auth)

**Approvals**
- [ ] Draft post → excluded from `/approved-posts`
- [ ] Unapproved post → excluded, and claim → 403
- [ ] Approved post with authorized destination → included
- [ ] Post with an unauthorized destination (including any Unmapped destination not yet authorized) → excluded, claim → 403

**Exact-content fingerprints**
- [ ] Correct fingerprint → claim succeeds
- [ ] Changed caption (even one character, including whitespace) → fingerprint mismatch, claim blocked
- [ ] Reordered media → fingerprint mismatch, claim blocked
- [ ] Changed media hash → fingerprint mismatch, claim blocked
- [ ] Changed scheduled time → fingerprint mismatch, claim blocked

**Duplicate prevention**
- [ ] Two concurrent claims for the same approved post → exactly one wins, the other gets 409
- [ ] Same `claim_id` replayed → 200, `already_claimed: true`, no second state change
- [ ] Identical `report-result` replayed → 200, `duplicate: true`, no second state change
- [ ] Report with a `claim_id` that does not own the post → 403

**Uncertain publishing outcomes**
- [ ] `published` without `live_url` and `platform_post_id` → 422, post stays not-published
- [ ] `uncertain` report → post becomes `uncertain`, never `published`, and is not auto-requeued
- [ ] `failed` report → post becomes `failed`, with error and platform-check notes in the audit log
- [ ] Claim expiry → post does not auto-return to `approved` without manual Jo OS review if Rio reported uncertain

**Regression**
- [ ] Existing `publisher-api` tests pass unchanged
- [ ] Existing `jo-command-ingress` tests pass unchanged

### Step 4 — Review and merge
- Jo reviews the branch and the test results.
- Tony approves production deployment only after review and passing tests. No direct-to-production deploy from a local machine without review.
- Merge to main only after the checklist above is green.

### Step 5 — Deploy through the existing authorized production workflow
- Deploy `rio-bridge` through Jo OS's existing authorized Supabase Edge Function deployment workflow.
- Do not deploy a second, ad-hoc production function, and do not change the existing publishing functions' deployment.
- Record the deployed base URL and version in Issue #10 after deployment. Rio will use exactly that base URL.

### Step 6 — Provision Rio's restricted identity (secure flow only)
- Create one dedicated row in `rio_integration.api_clients` for client `rio`, with permissions: `read_approved_posts`, `claim_post`, `report_result` only.
- Generate a dedicated API key, store only its hash, and deliver the plaintext key to Rio through a secure credential flow — never in chat, email, a GitHub comment, or a repo file.
- Set a rotation reminder. Revocation is: disable/delete the `rio` client row.

### Step 7 — Rio's read-only connection test (Rio runs this, Jo verifies)
1. `GET /health` → expect 200, service `rio-bridge`.
2. `GET /health/auth` with the dedicated Rio key → expect 200, `authenticated_client: "rio"`.
3. `GET /approved-posts` → expect 200, and only approved, authorized posts (possibly an empty list — an empty list is a valid pass if no test assignment exists yet).
4. Rio reports the exact endpoint, HTTP status, and response evidence to Tony and to Jo OS in Issue #10.
5. Only after (2) passes may anyone say "authenticated connection works".

## 2. First acceptance test (after Steps 1–7 pass)

1. Mary or Tom supplies one test post. Tony approves the exact caption, media, order, destination, and time in Jo OS.
2. Jo OS creates the approved assignment in `publish_queue` with its approval fingerprint.
3. Rio retrieves it, recomputes the fingerprint, claims it, and shows Tony the exact proposed post in Muse.
4. Tony approves that exact post for Meta publishing.
5. Rio publishes to the approved destination only (Cigar 30 Facebook Page or @cigar30jax).
6. Rio reads the live post back from Meta, compares caption/media/destination, and reports `platform_post_id`, live URL, status, and evidence via `report-result`.
7. Jo OS independently verifies the live URL and confirms the result is recorded in `publish_queue` and `audit_log`.
8. If the result is uncertain at any step, Rio reports `uncertain`, does not retry, and Jo OS handles recovery manually.

No paid ads in the acceptance test. No unapproved artwork. No modified Cigar 30 logo.

## 3. What Rio will do on its side

- Poll `GET /approved-posts` only within granted permissions, on a schedule Tony approves.
- Claim before publishing, publish only the claimed fingerprint, verify live, report with evidence.
- Report failures to Jo OS for recovery, with post ID, claim ID, error, and what platform check was performed.
- Never publish a post that Jo OS has not approved, never publish to an unauthorized destination, and never retry after an uncertain outcome without checking the platform first.
- Continue background monitoring only within the permissions granted.

## 4. Current blockers (as of October 25, 2026)

- [ ] Bridge Edge Function `rio-bridge` not deployed — deployment was blocked. Jo OS to identify the specific deployment blocker.
- [ ] No dedicated Rio API credential provisioned.
- [ ] No authenticated connection test passed.
- [ ] No social content published through this bridge.
- [ ] GitHub access for Muse: GitHub OAuth is not yet connected in Muse. Tony must authorize GitHub and select the Jo-OS repository before Rio can post this contract directly to Issue #10. Until then, this handoff file is the deliverable for Jo to use.
- [ ] Unmapped America destinations unconfirmed.

## 5. For Issue #10 — comment text Jo can paste (if Rio cannot post directly yet)

> Rio bridge contract and implementation handoff prepared October 25, 2026.
>
> Contract covers: `health`, `health/auth`, `approved-posts`, `claim-post` (atomic, idempotent), and `report-result` (evidence-required).
>
> Security: dedicated least-privilege Rio API client only, key stored as hash, no owner JWT, no service-role key shared with Rio, no publishing without Tony approval of the exact post, no retry after uncertain outcome without a platform check, no changes to `publisher-api` or `jo-command-ingress`, no production deployment without review and passing tests.
>
> Required tests: authentication, approvals, exact-content fingerprints, duplicate prevention, uncertain outcomes, and regression for existing publishing functions.
>
> Status: bridge NOT deployed, NOT authenticated, NOT tested. Next step is Jo OS review, branch implementation, tests, reviewed deployment, credential provisioning via secure flow, then Rio's read-only authenticated test.
>
> Files: `rio-bridge-api-contract.md` and `rio-bridge-implementation-handoff.md` (delivered by Rio).
