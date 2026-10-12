import { createClient } from "npm:@supabase/supabase-js@2";
Deno.serve(async(req)=>{
  if(req.method!=="POST") return new Response("Method Not Allowed",{status:405});
  const scheduler=req.headers.get("x-jo-scheduler-token")||"";
  const url=Deno.env.get("SUPABASE_URL")!;
  const keys=JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS")||"{}");
  const service=keys.default||Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!scheduler||!service) return Response.json({ok:false,error:"unauthorized"},{status:401});
  const sb=createClient(url,service,{auth:{persistSession:false}});
  const {data:ok}=await sb.rpc("jo_core_verify_scheduler_bridge",{p_token:scheduler});
  if(ok!==true) return Response.json({ok:false,error:"unauthorized"},{status:401});
  const body=await req.json().catch(()=>({}));
  const id=String(body.video_id||"").trim();
  const privacy=String(body.privacy||"private");
  if(!/^[A-Za-z0-9_-]{11}$/.test(id)||!["private","unlisted"].includes(privacy))
    return Response.json({ok:false,error:"invalid_request"},{status:400});
  const cid=Deno.env.get("YOUTUBE_CLIENT_ID"),secret=Deno.env.get("YOUTUBE_CLIENT_SECRET");
  const {data:refresh,error}=await sb.rpc("get_youtube_refresh_token");
  if(!cid||!secret||error||!refresh) return Response.json({ok:false,error:"youtube_auth_unavailable"},{status:500});
  const tr=await fetch("https://oauth2.googleapis.com/token",{method:"POST",headers:{"Content-Type":"application/x-www-form-urlencoded"},body:new URLSearchParams({client_id:cid,client_secret:secret,refresh_token:String(refresh),grant_type:"refresh_token"})});
  const tj=await tr.json();
  if(!tr.ok||!tj.access_token) return Response.json({ok:false,error:"token_refresh_failed",provider_status:tr.status,provider_error:typeof tj.error==="string"?tj.error:"unknown"},{status:502});
  const yr=await fetch("https://www.googleapis.com/youtube/v3/videos?part=status",{method:"PUT",headers:{Authorization:"Bearer "+tj.access_token,"Content-Type":"application/json"},body:JSON.stringify({id,status:{privacyStatus:privacy}})});
  const yj=await yr.json().catch(()=>({}));
  if(!yr.ok) return Response.json({ok:false,error:"youtube_update_failed",detail:yj},{status:502});
  return Response.json({ok:true,video_id:id,privacy:yj?.status?.privacyStatus||privacy});
});