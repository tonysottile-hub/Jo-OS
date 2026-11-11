# Tom recovery — 2026-11-11

Status: NOT OPERATIONAL. Inspection around 18:00–18:15 America/New_York.
No deployment, public upload, authorization flag, scheduler, or queue was changed.

## Exact failures

1. Storage-to-queue is held, not broken by a dead timer. Live `jo_core.run_tom_build_handoff_tick` requires `stored`, no blocker, existing object, `publish_authorized=true`, perceptual review passed, and a `qa_passed` log. Bodie has no approval or perceptual review. Its null error/blocker obscures the reason it cannot advance.
2. YouTube refresh fails now. A fresh authenticated invocation of the existing `jo-core-youtube-insights` returned HTTP 500, `youtube token refresh failed`. That endpoint refreshes credentials before any channel reads or internal metrics writes and cannot upload. Current error does not expose Google's exact reason. Historical event `youtube_auth_recovery_diagnosed`, 2026-10-12 20:48:53 UTC, records HTTP 400 `invalid_grant`. Refresh credential metadata has not changed since October 5. Do not claim a freshly observed invalid_grant; the fresh result is generic refresh failure.
3. Publisher version 17 does not filter `scheduled_for`, enforce `max_attempts`, atomically claim jobs, or persist the external ID immediately after upload. Retrying after successful upload but failed verification can duplicate videos. Do not activate a new cadence before these are repaired and tested.

## Workflow evidence

| Stage | Bodie evidence | Limitation |
|---|---|---|
| Topic/script | Manifest contains Bodie script and official-source references; research log Nov 2 | This run did not independently revalidate factual claims |
| Narration | Production run 41367963374, narration_ready | Full audio not auditioned |
| Media | Automated report counts eight distinct sources | Exact licenses/credits not retrieved |
| Render | Run 41368109821, render_ready | GitHub artifacts list now empty; artifact 13107629439 returns 404 |
| QA | Automated report: 45.833333 s, 1080x1920 H264, AAC, -16.9 dB mean | Perceptual review false; reported measurements not independently repeated |
| Storage | publisher-videos/tom-builds/fd8a0708-fccf-460d-a429-71ece159573e.mp4, 3,894,545 bytes, metadata updated Nov 2 | Private bytes not downloaded; metadata is not proof of playback |
| Queue | publish_job_id null, publish_authorized false | No next publishing job exists |
| YouTube | No Bodie publish record; fresh OAuth refresh fails | Channel-wide duplicate check blocked by auth |

Live queue: zero queued/processing/failed publish jobs. Latest recorded publication remains Silver Peak, video `-fjwwiXI5vs`, October 7; not independently replayed during this inspection.
Cron jobs 2, 7, 22, 23, 29 show recent executions. A successful cron return is not successful downstream work. Cloud functions execute without ChatGPT, but autonomous production-to-publication is not established.

## Prepared change and exact approval scope

New `jo-tom-readiness` Edge Function, scheduler-token authenticated using the existing verifier. Pin supabase-js 2.57.4. No SQL/schema change.

- POST `{}` performs one time-limited refresh and a channel read. Returns only sanitized diagnostics, verified expected channel, and required upload/read scopes. Unknown scopes fail closed.
- POST with `build_id` returns QA/owner approval states.
- Explicit `review_download:true` additionally signs only that build's canonical private MP4 path for 300 seconds. Treat returned URL as sensitive; never put it in logs or committed evidence.
- Does not set approval, enqueue, upload, update privacy, or alter existing schedules. Authentication success is not publication readiness.
- Deploy with gateway JWT verification disabled ONLY because scheduler authentication is enforced inside the handler; anonymous/invalid scheduler requests are tested to fail before accessing OAuth credentials.
- Rollback: remove/disable this new diagnostic function. Existing production functions are untouched.

Validation: 12 Node behavioral tests pass, including unauthorized access, path substitution, wrong channel, missing scopes, provider errors, bounded requests, and no writes. Existing OAuth helper callback regression suite passes. No live deployment test yet; Deno runtime type-check not available in local environment.

## Owner actions and continuation

1. Reconnect through the existing helper: https://pubnivjjeofxqvmttuzh.supabase.co/functions/v1/youtube-oauth-helper . Select the Google account/channel for Unmapped America and complete consent. Never share tokens in chat. Live helper version 17 has cookie-bound state and does not restart the queue.
2. Approve deployment of ONLY the new diagnostic function. This is not approval to publish Bodie or change the publisher.
3. Use the diagnostic to verify refreshed access and download the exact stored Bodie bytes. Hash, decode, inspect frames and listen to the full mix. Recover source manifest/licenses and required attribution; check channel duplicates. If provenance cannot be recovered, rebuild from verified assets rather than approving unknown rights.
4. Prepare a separately reviewed publisher repair: atomic claim/lease fencing, scheduled-date enforcement, bounded backoff, durable resumable upload identity, reconciliation before any retry, explicit owner/QA guards, and failure escalation. Persist provenance and review evidence beyond GitHub's seven-day artifact retention.
5. Propose Tuesday/Thursday/Saturday Shorts and alternate Sunday long-form using America/New_York; publishing hour and first Sunday anchor remain to be agreed. No schedule was created or claimed.
6. Present exact approved media, title, description/credits and destination before one public upload. Independently verify public video ID, playback, visibility and timestamp after approval. Then test cloud recovery and schedule execution.

Remaining required proof: actual video/audio/license/duplicate QA; production repair and deployment; one approved public upload; next scheduled job; bounded recovery under cloud execution. These are NOT complete.
