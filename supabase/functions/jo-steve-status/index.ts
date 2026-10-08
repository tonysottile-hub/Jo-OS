import {createClient} from "jsr:@supabase/supabase-js@2.95.0";
Deno.serve(async(req)=>{
 if(req.method!=="POST")return new Response("Method not allowed",{status:405});
 const db=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false}});
 const token=req.headers.get("x-jo-scheduler-token")||"";
 if(!token)return Response.json({error:"unauthorized"},{status:403});
 const auth=await db.rpc("jo_core_verify_scheduler_bridge",{p_token:token});
 if(auth.error||auth.data!==true)return Response.json({error:"unauthorized"},{status:403});
 try{
 const base="https://ibiuhwxypusbuurtmyzk.supabase.co/functions/v1/mcr";
 const [a,b]=await Promise.all(["/health","/a2p/status"].map(p=>fetch(base+p,{redirect:"error",signal:AbortSignal.timeout(15000)})));
 if(!a.ok||!b.ok)throw new Error("MCR status endpoint unavailable");
 const result=await db.rpc("jo_core_record_mcr_status",{p_health:await a.json(),p_twilio:await b.json()});
 if(result.error)throw new Error("Status checkpoint failed");
 return Response.json({ok:true,result:result.data});
 }catch(e){return Response.json({error:(e as Error).message},{status:502});}
});
