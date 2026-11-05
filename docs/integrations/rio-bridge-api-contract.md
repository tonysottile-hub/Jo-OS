# Rio Bridge API Contract — Jo OS Meta Publishing Integration

**Owner:** Tony Sottile
**Role:** Rio (Muse) — Meta Social Media Publishing Specialist, reporting to Jo
**Issue:** Jo OS GitHub Issue #10 — Integrate Rio (Muse) as approval-gated Meta publishing specialist
**Date:** October 25, 2026
**Status:** DRAFT FOR REVIEW — bridge NOT deployed, NOT authenticated, NOT tested. Do not claim the connection works until a real authenticated read succeeds.

## 1. Purpose

Give Rio a single, dedicated, least-privilege HTTPS bridge to Jo OS so Rio can:

1. Retrieve only fully approved publishing assignments.
2. Claim an assignment atomically, so it cannot be published twice.
3. Publish only the exact caption, media, order, destination, and time approved by Tony.
4. Report the platform post ID, live URL, publication status, and supporting evidence back to Jo OS.
5. Report failures and uncertain outcomes for Jo OS recovery, without retrying blindly.

This bridge does **not** replace Meta publishing. Rio still publishes through its supported Meta tools (Facebook Page, Instagram) and verifies the live post independently. Jo OS independently verifies the result.

## 2. Non-goals and hard constraints

- No owner JWT.
- No Supabase service-role key shared with Rio, in chat, in a file, in code, or in logs.
- No publishing without Tony's approval of the exact post.
- No advertising spend, ever, without Tony's explicit authorization. This contract has no ad-spend field.
- No modification to existing working functions `publisher-api` and `jo-command-ingress`.
- No production deployment without review and passing automated tests.
- No retry after an uncertain outcome until the platform is checked first.
- No claiming success without a verified live URL (for a live post) or a verified scheduled state (for a scheduled post).
- Unmapped America destinations are **not** authorized until Tony/Jo confirm them. The bridge must reject any Unmapped destination until it is added to the authorized list by Jo OS.

## 3. Authorized destinations

| Destination key | Platform | Account / Page |
|---|---|---|
| `facebook_page_cigar30` | Facebook Page | Cigar 30 |
| `instagram_cigar30jax` | Instagram | @cigar30jax |

Any other destination key must be rejected with `403 destination_not_authorized`.

## 4. Transport and authentication

- Transport: HTTPS only.
- Base URL: supplied by Jo OS after deployment, in the form:
  `https://<supabase-project-url>/functions/v1/rio-bridge`
  Jo OS fills in the production project URL at deployment time. Rio must never hard-code a service-role key to derive it.
- Authentication: dedicated Rio API client.
  - Header: `Authorization: Bearer <rio_api_key>`
  - Header: `X-Rio-Client-Id: rio`
  - The key is provisioned by Jo OS into `rio_integration.api_clients` as a **hash only**. The plaintext key is shown to Rio once, through a secure credential flow, and is never stored in the repo, in chat, or in logs.
  - The Edge Function validates the key hash server-side. It may use the service role **only inside the Edge Function** to reach the private `rio_integration` schema. That key never leaves the server.
  - Revocation: Jo OS revokes by disabling/deleting the `rio` row in `api_clients`. A revoked key must return `401`.
- Rate limiting: at least 60 requests per minute per client, with `429` and a `Retry-After` header. Rate-limit responses must not be treated as a publish failure.
- Request size: reject bodies over 256 KB with `413`.
- CORS: do not enable browser CORS for this bridge. It is a server-to-server API for Rio only.
- Logging: log actor, action, post ID, claim ID, outcome, and timestamp to `rio_integration.audit_log`. Never log API keys, tokens, or media bytes.

## 5. Common envelope

All responses are JSON:

```json
{
  "ok": true,
  "data": {},
  "error": null,
  "request_id": "uuid"
}
```

On error:

```json
{
  "ok": false,
  "data": null,
  "error": {
    "code": "unauthorized",
    "message": "Human-readable, no secrets",
    "retryable": false
  },
  "request_id": "uuid"
}
```

HTTP status codes:

| Code | Meaning |
|---|---|
| 200 | Success, including idempotent replay |
| 400 | Validation error |
| 401 | Missing, invalid, or revoked Rio credential |
| 403 | Destination not authorized, or post not approved |
| 404 | Post or claim not found |
| 409 | Already claimed by another claim, or fingerprint mismatch on claim |
| 413 | Body too large |
| 422 | Fingerprint mismatch on report, or missing evidence for a claimed success |
| 429 | Rate limited |
| 500 | Server error, retryable only for safe reads, never for a publish |
| 503 | Database unavailable |

## 6. Exact-content fingerprint

The fingerprint is the single guard against publishing a changed post.

### 6.1 Canonical payload

Build this JSON object, with keys sorted, UTF-8, no extra whitespace, and media in exact order:

```json
{
  "caption": "<exact caption, byte-for-byte>",
  "destination": "facebook_page_cigar30",
  "media": [
    {
      "hash_sha256": "<sha256 hex of the exact media file bytes>",
      "mime": "image/jpeg",
      "order": 1
    }
  ],
  "scheduled_publish_time": "2026-10-26T14:00:00Z"
}
```

Rules:

- `caption` is byte-for-byte. Do not trim, rewrap, or normalize it. If a platform rejects leading/trailing spaces, Jo OS must fix the approved caption and re-approve it, not silently trim it.
- `media` order matters. A reordered carousel is a different fingerprint.
- `scheduled_publish_time` is ISO 8601 UTC, or `null` for immediate publish.
- For Cigar 30, the media hash must match the official approved artwork. A generated or altered logo will have a different hash and must be rejected by the approval workflow before it reaches Rio.

### 6.2 Fingerprint value

```
fingerprint = "sha256:" + hex(sha256(canonical_json_utf8))
```

Jo OS stores `approval_fingerprint` at Tony approval time. Rio recomputes the fingerprint from the exact content it is about to publish and compares it before claiming and before publishing. Any mismatch stops the job and is reported as `fingerprint_mismatch`, with no publish attempt.

## 7. Endpoints

### 7.1 GET /health — liveness (no auth required for liveness only)

Response:

```json
{
  "ok": true,
  "data": {
    "service": "rio-bridge",
    "status": "ok",
    "version": "1.0.0"
  },
  "error": null,
  "request_id": "uuid"
}
```

This proves the function is deployed. It does **not** prove authentication or database access.

### 7.2 GET /health/auth — authenticated connection test (REQUIRED first test)

Headers: Rio Bearer key.

Response:

```json
{
  "ok": true,
  "data": {
    "authenticated_client": "rio",
    "schema": "rio_integration",
    "database": "ok",
    "permissions": ["read_approved_posts", "claim_post", "report_result"]
  },
  "error": null,
  "request_id": "uuid"
}
```

This is the first test Rio runs after credential provisioning. A `200` here, with `authenticated_client: "rio"`, is the minimum evidence for "authenticated connection works". Anything less is not a pass.

### 7.3 GET /approved-posts — retrieve only approved assignments

Headers: Rio Bearer key.

Query parameters:

- `destination` (optional): `facebook_page_cigar30` or `instagram_cigar30jax`
- `limit` (optional, default 20, max 50)
- `cursor` (optional, opaque pagination cursor)

Response — only posts where:

- `status = 'approved'`
- Tony approval is recorded, with `approved_by = 'Tony'` and a non-null `approved_at` and `approval_fingerprint`
- Destination is authorized
- The post is not already claimed, published, scheduled, failed, or uncertain

```json
{
  "ok": true,
  "data": {
    "posts": [
      {
        "post_id": "uuid",
        "source": "mary",
        "destination": "facebook_page_cigar30",
        "caption": "<exact caption>",
        "media": [
          {
            "order": 1,
            "type": "image",
            "mime": "image/jpeg",
            "url": "https://<jo-os-approved-media-url>/file.jpg",
            "hash_sha256": "<sha256 hex>"
          }
        ],
        "scheduled_publish_time": null,
        "approved_by": "Tony",
        "approved_at": "2026-10-26T13:00:00Z",
        "approval_fingerprint": "sha256:<hex>",
        "status": "approved"
      }
    ],
    "next_cursor": null
  },
  "error": null,
  "request_id": "uuid"
}
```

Notes:

- Media URLs must be URLs Rio can actually download for Meta publishing, or Jo OS must supply the file bytes through an approved channel. A URL Rio cannot fetch is a blocker, not a reason to substitute media.
- Draft, unapproved, claimed, published, scheduled, failed, and uncertain posts must **never** appear here.
- Unmapped America posts must **never** appear here until their destinations are authorized.

### 7.4 POST /claim-post — atomic, idempotent claim

Request:

```json
{
  "post_id": "uuid",
  "claim_id": "uuid-generated-by-rio",
  "fingerprint": "sha256:<hex>"
}
```

Server behavior — in a single transaction:

```sql
UPDATE rio_integration.publish_queue
SET status = 'claimed',
    claim_id = $claim_id,
    claimed_by = 'rio',
    claimed_at = now(),
    claim_expires_at = now() + interval '15 minutes'
WHERE id = $post_id
  AND status = 'approved'
  AND approval_fingerprint = $fingerprint
RETURNING *;
```

- If 1 row is returned: `200`, `claimed: true`.
- If the same `claim_id` already owns this post: `200`, `claimed: true`, `already_claimed: true` — idempotent replay, no state change.
- If 0 rows and the post is already claimed by a different claim: `409`, `code: "already_claimed"`.
- If 0 rows and the fingerprint does not match: `409`/`422`, `code: "fingerprint_mismatch"`, no publish.
- If the post is not approved: `403`, `code: "not_approved"`.

Rio must claim **before** publishing, and must publish only the claimed post, with the claimed fingerprint.

Claim expiry: 15 minutes. After expiry, Jo OS may return the post to `approved` **only after manual review** if Rio reported uncertain, or if Rio never reported. Expiry alone must never auto-requeue a post that Rio may have published.

### 7.5 POST /report-result — report outcome, with evidence

Request:

```json
{
  "post_id": "uuid",
  "claim_id": "uuid",
  "outcome": "published",
  "platform_post_id": "<platform id, if published>",
  "live_url": "https://www.facebook.com/<post-url> OR https://www.instagram.com/<post-url>",
  "published_at": "2026-10-26T14:00:00Z",
  "scheduled_publish_time": null,
  "evidence": {
    "verified_by": "rio",
    "verified_at": "2026-10-26T14:01:00Z",
    "platform_readback": "live post read back from Meta, caption and media order match"
  },
  "error": null
}
```

Outcome values:

| Outcome | Required fields | Server transition |
|---|---|---|
| `published` | `platform_post_id`, `live_url`, `published_at`, `evidence` | `claimed` → `published` |
| `scheduled` | `platform_post_id` or scheduled ID, `scheduled_publish_time`, `evidence` | `claimed` → `scheduled` |
| `failed` | `error.code`, `error.message`, platform check performed | `claimed` → `failed` |
| `uncertain` | `error.code`, `error.message`, platform check performed, what was checked | `claimed` → `uncertain` |

Rules:

- A `published` report without `live_url` and `platform_post_id` is rejected with `422`. Rio must not claim success without evidence.
- A `scheduled` report must include the verified scheduled time and timezone.
- An `uncertain` report must **never** be converted to `published` by the server.
- Report is idempotent by `(post_id, claim_id)`: an identical second report returns `200` with `duplicate: true` and makes no second state change.
- A report with a `claim_id` that does not own the post is rejected with `403`.
- Every report appends a row to `rio_integration.audit_log` with post ID, claim ID, actor `rio`, action, outcome, timestamp, and request ID.

## 8. Rio client workflow (normative)

1. Poll `GET /approved-posts` (background job only, within granted permissions).
2. For each candidate, recompute the fingerprint from caption, media hashes, order, destination, and scheduled time. Stop on mismatch.
3. Claim with a fresh UUID `claim_id`.
4. Present the exact post to Tony in Muse and obtain the Meta write approval for that exact version. For the first acceptance test, this is a separate, explicit Tony approval step.
5. Publish through the supported Meta tool for that destination only.
6. Read the live post back from Meta and compare caption, media order, and destination.
7. Report with evidence via `POST /report-result`.
8. If the publish result is uncertain, timeout, or malformed:
   - Do **not** retry automatically.
   - Check the platform first (Page/Instagram read-back, scheduled list, draft list).
   - Report `uncertain` with what was checked.
   - Leave recovery to Jo OS manual review. Do not re-claim the same post without a new Jo OS decision.

## 9. Database notes (for Jo OS implementation, not for Rio to access directly)

Existing private schema, per Issue #10:

- `rio_integration.publish_queue`
- `rio_integration.audit_log`
- `rio_integration.api_clients`

Requirements:

- RLS on, anon/authenticated access revoked.
- Only the Edge Function service role may read/write this schema, server-side only.
- `api_clients` stores key hashes, client name, permissions, created/revoked timestamps. Never store plaintext keys.
- `publish_queue` status transitions must be enforced in the Edge Function, not left to direct client writes.
- `audit_log` is append-only for Rio actions.

## 10. Acceptance criteria

The bridge is accepted only when **all** of these pass:

1. `GET /health` returns `200`.
2. `GET /health/auth` returns `200` with `authenticated_client: "rio"`, using the dedicated Rio credential only.
3. `GET /approved-posts` returns only approved, authorized posts, and excludes drafts, unapproved, claimed, published, and Unmapped posts.
4. A test claim is atomic and idempotent (concurrent claims: exactly one wins; same `claim_id` replay: no duplicate).
5. A fingerprint mismatch blocks claim and publish.
6. A `published` report without a live URL is rejected.
7. An `uncertain` report does not mark a post published, and does not auto-requeue it.
8. A duplicate report does not change state a second time.
9. Existing `publisher-api` and `jo-command-ingress` still pass their tests unchanged.
10. First live test: one specifically Tony-approved test post, published to an authorized destination, with a public URL returned and Jo OS recording confirmed.

Until (2) passes, the connection is **not** verified.
