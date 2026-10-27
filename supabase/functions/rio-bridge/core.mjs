export const destinations = {facebook_page_cigar30:'cigar30_facebook',instagram_cigar30jax:'cigar30_instagram'};
export async function sha256(text) { return [...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(text)))].map(x=>x.toString(16).padStart(2,'0')).join(''); }
export async function approvedPost(q) {
  const destination=Object.keys(destinations).find(k=>destinations[k]===q.destination);
  if (!destination || q.state!=='approved' || q.approved_by!=='Tony' || !q.approved_at || typeof q.caption!=='string' || !Array.isArray(q.media_urls) || !q.media_urls.length) return null;
  const media=q.media_urls;
  if (media.some((m,i)=>!m || m.order!==i+1 || !/^[a-f0-9]{64}$/.test(m.hash_sha256) || !['image/jpeg','image/png','video/mp4'].includes(m.mime) || !['image','video'].includes(m.type) || typeof m.url!=='string' || !m.url.startsWith('https://'))) return null;
  let scheduled=null;
  if(q.scheduled_for) {const d=new Date(q.scheduled_for); if(!Number.isFinite(d.getTime())) return null; scheduled=d.toISOString().replace('.000Z','Z');}
  // Contract key order and compact UTF-8 JSON. Media URL is a locator; hash binds bytes.
  const canonical={caption:q.caption,destination,media:media.map(m=>({hash_sha256:m.hash_sha256,mime:m.mime,order:m.order})),scheduled_publish_time:scheduled};
  if(q.approval_fingerprint !== 'sha256:'+await sha256(JSON.stringify(canonical))) return null;
  return {post_id:q.id,source:q.source_worker,destination,caption:q.caption,media:media.map(({order,type,mime,url,hash_sha256})=>({order,type,mime,url,hash_sha256})),scheduled_publish_time:scheduled,approved_by:q.approved_by,approved_at:q.approved_at,approval_fingerprint:q.approval_fingerprint,status:'approved'};
}
export function makeHandler(rpc) { return async req=>{
  const request_id=crypto.randomUUID();
  const reply=(status,data=null,error=null)=>new Response(JSON.stringify({ok:status===200,data,error:error?{code:error}:null,request_id}),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff',...(status===429?{'Retry-After':'60'}:{}),...(status===405?{Allow:'GET'}:{})}});
  try {
    const url=new URL(req.url); const path=url.pathname.replace(/^\/functions\/v1\/rio-bridge\/?/,'').replace(/^\/rio-bridge\/?/,'');
    const auth=req.headers.get('authorization')||'';
    const key=/^Bearer (rio_[a-f0-9]{64})$/.exec(auth)?.[1];
    const client=req.headers.get('x-rio-client-id');
    const limit=url.searchParams.get('limit')||'20'; const cursor=url.searchParams.get('cursor'); const destination=url.searchParams.get('destination');
    const badQuery=[...url.searchParams.keys()].some(k=>!['limit','cursor','destination'].includes(k)) || !/^(?:[1-9]|[1-4][0-9]|50)$/.test(limit) || (cursor && !/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/.test(cursor)) || (destination && !Object.hasOwn(destinations,destination));
    const operation=req.method==='GET' && ['health','health/auth','approved-posts'].includes(path) && !badQuery ? path : 'denied';
    const result=await rpc({p_hash:key?await sha256(key):'',p_client:client==='rio'?'rio':'unknown',p_operation:operation,p_request_id:request_id,p_destination:destination?destinations[destination]||null:null,p_limit:badQuery?20:Number(limit),p_cursor:badQuery?null:cursor});
    if(result.status!==200) return reply(result.status,null,result.error);
    if(path==='approved-posts') {
      const posts=(await Promise.all(result.data.map(approvedPost))).filter(Boolean);
      return reply(200,{posts,next_cursor:result.data.length===Number(limit)?result.data.at(-1).id:null,publishing_enabled:false});
    }
    return reply(200,result.data);
  } catch {return reply(503,null,'bridge_unavailable');}
}; }
