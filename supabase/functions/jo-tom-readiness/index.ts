import { createClient } from 'npm:@supabase/supabase-js@2.57.4';

// Diagnostic only: never enqueue, authorize, upload, or modify a video.
const CHANNEL = 'UCtca_WIfD_mhFSNfg_JvHgw';
const SCOPES = ['https://www.googleapis.com/auth/youtube.upload', 'https://www.googleapis.com/auth/youtube.readonly'];
const reply = (body: unknown, status = 200) => Response.json(body, {
  status, headers: { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' },
});

Deno.serve(async (req) => {
  if (req.method !== 'POST') return reply({ error: 'method_not_allowed' }, 405);
  const scheduler = req.headers.get('x-jo-scheduler-token');
  if (!scheduler) return reply({ error: 'unauthorized' }, 401);
  try {
    const url = Deno.env.get('SUPABASE_URL');
    const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}');
    const key = keys.default || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!url || !key) return reply({ error: 'runtime_configuration_missing' }, 503);
    const sb = createClient(url, key, { auth: { persistSession: false } });
    const auth = await sb.rpc('jo_core_verify_scheduler_bridge', { p_token: scheduler });
    if (auth.error || auth.data !== true) return reply({ error: 'unauthorized' }, 401);
    const body = await req.json().catch(() => null);
    if (!body || (body.build_id && !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(body.build_id))) {
      return reply({ error: 'invalid_request' }, 400);
    }
    const result: any = { checked_at: new Date().toISOString(), diagnostic_only: true, publish_authorized: false };
    // One bounded OAuth attempt per invocation. Never return tokens/provider payloads.
    const cid = Deno.env.get('YOUTUBE_CLIENT_ID'), secret = Deno.env.get('YOUTUBE_CLIENT_SECRET');
    const refresh = await sb.rpc('get_youtube_refresh_token');
    if (!cid || !secret || refresh.error || !refresh.data) {
      result.youtube = { ok: false, reason: 'oauth_configuration_missing' };
    } else {
      const tr = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST', signal: AbortSignal.timeout(10000),
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ client_id: cid, client_secret: secret, refresh_token: String(refresh.data), grant_type: 'refresh_token' }),
      });
      const token = await tr.json().catch(() => ({}));
      if (!tr.ok || !token.access_token) {
        const reason = ['invalid_grant', 'invalid_client', 'unauthorized_client'].includes(token.error) ? token.error : 'token_refresh_failed';
        result.youtube = { ok: false, reason, provider_status: tr.status, owner_reauthorization_required: reason === 'invalid_grant' };
      } else {
        // Refresh responses normally include scope; absent scope is unverified, never presumed.
        const scopes = String(token.scope || '').split(/\s+/);
        const missing = SCOPES.filter(scope => !scopes.includes(scope));
        const cr = await fetch('https://www.googleapis.com/youtube/v3/channels?part=id,snippet&mine=true&maxResults=50', {
          headers: { Authorization: 'Bearer ' + token.access_token }, signal: AbortSignal.timeout(10000),
        });
        const channels = await cr.json().catch(() => ({}));
        const channel = Array.isArray(channels.items) && channels.items.find((c: any) => c.id === CHANNEL);
        result.youtube = { ok: cr.ok && !!channel && missing.length === 0,
          channel_verified: cr.ok && !!channel, channel_id: channel ? CHANNEL : null,
          required_scopes_verified: missing.length === 0, missing_or_unverified_scopes: missing };
      }
    }
    if (body.build_id) {
      const { data: build, error } = await sb.from('video_builds').select('id,title,status,blocker_stage,output_storage_path,publish_job_id,asset_manifest').eq('id', body.build_id).maybeSingle();
      if (error) return reply({ error: 'build_lookup_failed' }, 503);
      if (!build) return reply({ error: 'build_not_found' }, 404);
      const manifest = build.asset_manifest || {};
      result.build = { id: build.id, title: build.title, status: build.status, blocker_stage: build.blocker_stage,
        publish_job_id: build.publish_job_id, owner_approved: manifest.publish_authorized === true,
        perceptual_review_passed: manifest.perceptual_review?.passed === true,
        automated_qa_passed: manifest.auto_qa?.passed === true };
      if (body.review_download === true) {
        if (build.output_storage_path !== `tom-builds/${build.id}.mp4`) return reply({ error: 'storage_path_mismatch' }, 409);
        const signed = await sb.storage.from('publisher-videos').createSignedUrl(build.output_storage_path, 300);
        result.build.review_download = signed.error ? { error: 'storage_signing_failed' } : { url: signed.data.signedUrl, expires_in_seconds: 300 };
        // A signed URL is access to review bytes, not proof that the bytes passed QA.
      }
    }
    return reply(result);
  } catch {
    return reply({ error: 'diagnostic_unavailable', retryable: true }, 503);
  }
});
