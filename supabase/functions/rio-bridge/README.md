# Rio read-only production bridge

Authorized by Tony's RIO BRIDGE PRODUCTION ACTIVATION assignment, 2026-10-26.
This is the read-only subset of PR #11. All routes require the dedicated Rio credential (including health, intentionally stricter than the draft contract).

GET /health, /health/auth, /approved-posts only. Header Authorization: Bearer <dedicated key>; X-Rio-Client-Id: rio.
No claims, reports, scheduling, publishing, automatic retries, or queue mutations exist.
The existing rio-health-readonly function, publisher-api and jo-command-ingress are unchanged.

Credentials use 32 cryptographically random bytes with rio_ prefix, stored only as SHA-256. An enabled client must have exactly read_approved_posts permission and a future expiration. Revocation and rate limit are checked in the database on every call. 60 authenticated requests/minute, serialized across instances. Errors and reads append request IDs and statuses to audit_log; no tokens or content are logged. Audit failure returns 503 before content is released.

Private schema remains inaccessible to anon/authenticated. The public RPC has EXECUTE revoked from PUBLIC/anon/authenticated; service_role only, with an additional auth.role check. SECURITY DEFINER is intentionally required to access the private schema; search_path is empty and identifiers are qualified. No table grants are added. Rio never receives a Supabase credential.

Database names remain canonical internally: state and cigar30_facebook/cigar30_instagram. API names map to status and facebook_page_cigar30/instagram_cigar30jax. media_urls must contain contract media objects with order/type/mime/url/hash_sha256. Legacy string arrays or aggregate-only media hashes fail closed. No approval is manufactured or backfilled.

Fingerprints use compact JSON.stringify UTF-8 with contract insertion order caption,destination,media,scheduled_publish_time; media fields hash_sha256,mime,order. UTC timestamps omit .000 when no fractional seconds. Caption is not normalized. This explicit canonicalization and the tests must be adopted by the approval writer before real posts are returned. The bridge recomputes the fingerprint before every response. Media byte retrieval and verification remain Rio's responsibility before any later approved publishing phase.

limit defaults to 20, maximum 50. cursor is the last scanned UUID, ordered by UUID; empty pages can still carry a next cursor when corrupt approvals are filtered. Unauthorized destinations are refused. No CORS headers. Non-GET requests, including bodies, are refused without consuming the body.

Tests: node --test supabase/functions/rio-bridge/core.test.mjs
Database assertions: supabase/repairs/rio_readonly_bridge_test.sql (transaction rolls back all synthetic fixtures).

Deployment: apply supabase/repairs/rio_readonly_bridge.sql using authorized management tooling; deploy index.ts and core.mjs as rio-bridge with verify_jwt=false. No external dependencies.

Remaining production step: use a secure credential provisioning channel on Rio/Muse to generate/deliver a fresh key, persist only its hash, set expiry and read-only scope, and have Rio perform its own read-only test. Do not put plaintext credentials in chat, GitHub, or repository files. The activation test credential is revoked after verification; it is not a lasting Rio connection.
