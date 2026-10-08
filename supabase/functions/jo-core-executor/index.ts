import { createClient } from "jsr:@supabase/supabase-js@2.95.0";
Deno.serve(async(req)=>{
 if(req.method!=="POST")return new Response("Method not allowed",{status:405});
 const token=req.headers.get("Authorization")?.replace(/^Bearer /,"")||"";
 const keys=JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS")||"{}");
 const candidates=[Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),keys.default].filter(Boolean);
 const db=createClient(Deno.env.get("SUPABASE_URL")!,candidates[0],{auth:{persistSession:false}});
 if(!token || !candidates.includes(token)){
  const scheduler=req.headers.get("x-jo-scheduler-token")||"";
  if(!scheduler)return Response.json({error:"service_authorization_required"},{status:403});
  const {data:authorized,error:authError}=await db.rpc("jo_core_verify_scheduler_bridge",{p_token:scheduler});
  if(authError||authorized!==true)return Response.json({error:"service_authorization_required"},{status:403});
 }
 const {data,error}=await db.rpc("jo_core_run_capabilities");
 if(error)return Response.json({error:"capability_dispatch_failed"},{status:500});
 return Response.json({ok:true,result:data});
});