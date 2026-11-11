# Approved diagnostic deployment proof — November 11, 2026

Tony approved deployment in this conversation with “Let’s do it” following the explicit diagnostic-only approval request.

- Function: jo-tom-readiness, version 1, ACTIVE.
- Function ID: 063a974f-2052-41bc-8d0b-41d078eea209.
- Deployment bundle SHA256: b8fade1505ced8d918b8181db9423adbf1a81a6ae119047f0ca770ae5c075cf3.
- Retrieved deployed source equals the tested source in commit a873eb4504433e42a80ca1481d46ef1d5cef5bd2.
- Anonymous and invalid scheduler-token requests each returned HTTP 401.
- Authenticated request returned HTTP 200 at 2026-11-11T23:17:36.361Z.
- Google refresh returned HTTP 400 invalid_grant. owner_reauthorization_required=true.
- No upload, approval flag, queue, privacy setting, or schedule changed.

## Bodie actual bytes examined

Downloaded the private stored MP4 through a five-minute signed URL (URL intentionally not retained).
- Size: 3,894,545 bytes.
- SHA256: 8d270aa5798677535b2338f6777313ca7898c367d8682928c7524407f6c4a082.
- FFprobe: H264, 1080x1920, 45.833333 seconds; AAC audio, 44.733016 seconds.
- Full FFmpeg decode to null completed without reported errors.
- Audio mean -16.9 dB, peak -0.0 dB. This is technical evidence, not a full listening review.
- Sampled frames show historic buildings and a cropped town survey image at the end. No perceptual pass has been granted.
- Source workflow 41367957030 / job 125032073249 logs remain available and contain source titles, URLs and licenses, including CC BY 2.0 and public-domain declarations. This recovers provenance leads despite expired artifacts; individual rights verification, credits and matching all source images to the render remain outstanding.
- Render workflow 41368109821 / job 125032522937 reports success; this does not independently prove editorial quality.

## Remaining boundary

Only the diagnostic function was approved and deployed. PR #14 remains a draft; it is not merged.
The pipeline is NOT operational. Tony must reconnect through the existing youtube-oauth-helper using the Unmapped America account/channel.
After reauthorization: verify scopes/channel and channel duplicates; finish audio/visual/licensing review; implement and test publisher scheduling, atomic claims, bounded retries and upload reconciliation; obtain approval for that repair and the exact video; then verify an actual public upload and next scheduled job.
