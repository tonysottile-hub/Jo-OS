const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { stripTypeScriptTypes } = require('node:module');
const { test } = require('node:test');
const code = stripTypeScriptTypes(fs.readFileSync(__dirname + '/index.ts', 'utf8').replace(/^import .*;\n/gm, ''));
const id = 'fd8a0708-fccf-460d-a429-71ece159573e';
function setup(options = {}) {
  const calls = []; let handler;
  const build = { id, title: 'Bodie', status: 'stored', output_storage_path: `tom-builds/${id}.mp4`, publish_job_id: null,
    asset_manifest: { publish_authorized: false, auto_qa: { passed: true } }, ...options.build };
  const sb = {
    rpc: async name => {
      calls.push(name);
      if (name === 'jo_core_verify_scheduler_bridge') return { data: !options.unauthorized };
      if (name === 'get_youtube_refresh_token') return { data: 'SECRET_REFRESH' };
      throw Error('Unexpected RPC mutation');
    },
    from: name => {
      assert.equal(name, 'video_builds');
      return { select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: build }) }) }) };
    },
    storage: { from: bucket => { assert.equal(bucket, 'publisher-videos'); return {
      createSignedUrl: async (path, ttl) => { assert.equal(path, `tom-builds/${id}.mp4`); assert.equal(ttl, 300); calls.push('sign'); return { data: { signedUrl: 'https://example.test/review' } }; },
    }; } },
  };
  vm.runInNewContext(code, { URLSearchParams, Response, AbortSignal, Date,
    Deno: { env: { get: k => ({ SUPABASE_URL: 'https://example.test', SUPABASE_SERVICE_ROLE_KEY: 'test', YOUTUBE_CLIENT_ID: 'client', YOUTUBE_CLIENT_SECRET: 'secret' })[k] }, serve: fn => handler = fn },
    createClient: () => sb,
    fetch: async (url, init) => {
      calls.push(url);
      if (options.timeout) throw Error('SECRET_TIMEOUT_DETAIL');
      if (url === 'https://oauth2.googleapis.com/token') {
        assert.equal(init.method, 'POST'); assert(init.signal);
        if (options.providerError) return Response.json({ error: options.providerError, error_description: 'SECRET_PROVIDER_DETAIL' }, { status: 400 });
        return Response.json({ access_token: 'SECRET_ACCESS', scope: options.noScope ? '' : 'https://www.googleapis.com/auth/youtube.upload https://www.googleapis.com/auth/youtube.readonly' });
      }
      assert(url.startsWith('https://www.googleapis.com/youtube/v3/channels?')); assert(!init.method || init.method === 'GET');
      return Response.json({ items: [{ id: options.wrongChannel ? 'wrong' : 'UCtca_WIfD_mhFSNfg_JvHgw' }] });
    },
  });
  return { calls, run: async (body = {}, headers = { 'x-jo-scheduler-token': 'test' }) => {
    const response = await handler(new Request('https://example.test', { method: 'POST', headers, body: JSON.stringify(body) }));
    const text = await response.text(); assert(!text.includes('SECRET_')); return { status: response.status, body: JSON.parse(text) };
  } };
}
test('missing credentials cause no external requests', async () => { const s = setup(); assert.equal((await s.run({}, {})).status, 401); assert.equal(s.calls.length, 0); });
test('invalid scheduler cannot inspect credentials', async () => { const s = setup({ unauthorized: true }); assert.equal((await s.run()).status, 401); assert.deepEqual(s.calls, ['jo_core_verify_scheduler_bridge']); });
test('invalid build id rejected before OAuth', async () => { const s = setup(); assert.equal((await s.run({ build_id: '../other' })).status, 400); assert.equal(s.calls.length, 1); });
test('invalid grant requires owner and does not retry', async () => { const s = setup({ providerError: 'invalid_grant' }); const r = await s.run(); assert.equal(r.body.youtube.owner_reauthorization_required, true); assert.equal(s.calls.filter(x => x.startsWith('https:')).length, 1); });
test('configuration failure not mislabeled reauthorization', async () => { const r = await setup({ providerError: 'invalid_client' }).run(); assert.equal(r.body.youtube.owner_reauthorization_required, false); });
test('wrong channel cannot pass', async () => { assert.equal((await setup({ wrongChannel: true }).run()).body.youtube.ok, false); });
test('missing scopes cannot pass', async () => { assert.equal((await setup({ noScope: true }).run()).body.youtube.ok, false); });
test('valid authentication never authorizes publication', async () => { const r = await setup().run(); assert.equal(r.body.youtube.ok, true); assert.equal(r.body.publish_authorized, false); });
test('Bodie QA hold visible; download explicit only', async () => { const s = setup(); const r = await s.run({ build_id: id }); assert.equal(r.body.build.perceptual_review_passed, false); assert.equal(r.body.build.owner_approved, false); assert(!s.calls.includes('sign')); });
test('review download available even when OAuth fails', async () => { const s = setup({ providerError: 'invalid_grant' }); const r = await s.run({ build_id: id, review_download: true }); assert.equal(r.body.build.review_download.expires_in_seconds, 300); assert(s.calls.includes('sign')); });
test('path substitution cannot sign another object', async () => { const s = setup({ build: { output_storage_path: 'other.mp4' } }); assert.equal((await s.run({ build_id: id, review_download: true })).status, 409); assert(!s.calls.includes('sign')); });
test('network failure is sanitized and retryable', async () => { const r = await setup({ timeout: true }).run(); assert.equal(r.status, 503); assert.equal(r.body.retryable, true); });
