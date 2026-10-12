const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { stripTypeScriptTypes } = require('node:module');
const source = fs.readFileSync(__dirname + '/index.ts', 'utf8').replace(/^import .*;\n/gm, '');
const code = stripTypeScriptTypes(source);
let handler, scenario='success', writes=[], calls=[];
const sql = async () => { writes.push('vault'); return []; };
sql.end = async () => {};
vm.runInNewContext(code, {
 URL, URLSearchParams, Response, crypto, console:{log(){}},
 Deno:{env:{get:k=>({YOUTUBE_CLIENT_ID:'test-client',YOUTUBE_CLIENT_SECRET:'test-secret',SUPABASE_URL:'https://example.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'test-service',SUPABASE_DB_URL:'test-db'})[k]},serve:fn=>handler=fn},
 postgres:()=>sql,
 createClient:()=>({rpc:async(name)=>{assert.equal(name,'store_youtube_refresh_token');writes.push(name);return {error:null};}}),
 fetch:async url=>{
 calls.push(String(url));
 if(String(url)==='https://oauth2.googleapis.com/token') return Response.json(scenario==='no-refresh'?{access_token:'test-access'}:{access_token:'test-access',refresh_token:'test-refresh',expires_in:3600});
 if(String(url).startsWith('https://www.googleapis.com/youtube/v3/channels')) return Response.json({items:[{id:scenario==='wrong-channel'?'wrong':'UCtca_WIfD_mhFSNfg_JvHgw'}]});
 throw Error('Unexpected network call: '+url);
 }
});
(async()=>{
 const start=await handler(new Request('https://example.supabase.co/functions/v1/youtube-oauth-helper'));
 assert.equal(start.status,302);
 const u=new URL(start.headers.get('location')), state=u.searchParams.get('state');
 assert(u.searchParams.get('scope').includes('youtube.force-ssl'));
 assert(start.headers.get('set-cookie').includes('Secure; HttpOnly; SameSite=Lax; Max-Age=600'));
 const second=await handler(new Request('https://example.supabase.co/functions/v1/youtube-oauth-helper'));
 assert.notEqual(new URL(second.headers.get('location')).searchParams.get('state'),state);
 const bad=await handler(new Request('https://example.supabase.co/?code=test&state=wrong'));
 assert.equal(bad.status,403);assert.equal(calls.length,0);assert.equal(writes.length,0);
 const request=()=>new Request('https://example.supabase.co/?code=test&state='+state,{headers:{cookie:'__Host-jo_youtube_state='+state}});
 scenario='no-refresh';assert.equal((await handler(request())).status,400);assert.equal(writes.length,0);
 scenario='wrong-channel';assert.equal((await handler(request())).status,400);assert.equal(writes.length,0);
 scenario='success';const ok=await handler(request());assert.equal(ok.status,200);
 assert(ok.headers.get('set-cookie').includes('Max-Age=0'));
 assert(writes.includes('store_youtube_refresh_token'));
 assert(!calls.some(x=>x.includes('publisher-worker')));
 assert(!source.includes('.from(\'publish_jobs\')'));
 console.log('PASS: unique cookie-bound state; rejected unbound callback; missing offline access; wrong-channel guard; credential storage; no queue restart.');
})().catch(e=>{console.error(e);process.exitCode=1;});
