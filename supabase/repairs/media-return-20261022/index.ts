import { createClient } from "npm:@supabase/supabase-js@2";
import { matchingRun } from "./media_correlation.js";
const repo="https://api.github.com/repos/tonysottile-hub/Jo-OS";
Deno.serve(async(req)=>{
 if(req.method!=="POST")return new Response("Method Not Allowed",{status:405});
 const token=req.headers.get("x-jo-scheduler-token")||"",url=Deno.env.get("SUPABASE_URL")!,keys=JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS")||"{}"),service=keys.default||Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!token||!service)return Response.json({error:"unauthorized"},{status:401});
 const sb=createClient(url,service,{auth:{persistSession:false}}),{data:ok}=await sb.rpc("jo_core_verify_scheduler_bridge",{p_token:token});if(ok!==true)return Response.json({error:"unauthorized"},{status:401});
 const gt=Deno.env.get("JO_GITHUB_TOKEN");if(!gt)return Response.json({error:"github_secret_missing"},{status:500});
 const h:any={Authorization:`Bearer ${gt}`,Accept:"application/vnd.github+json","X-GitHub-Api-Version":"2022-11-28","User-Agent":"Jo-OS-Media-Return"};
 const {data:rows,error:e}=await sb.rpc("jo_core_github_dispatch_candidates");if(e)return Response.json({error:e.message},{status:500});
 const out:any[]=[];
 for(const d of rows||[]){
   const rr=await fetch(`${repo}/actions/workflows/commons-media-test.yml/runs?event=workflow_dispatch&per_page=30`,{headers:h});
   if(!rr.ok){out.push({dispatch_id:d.dispatch_id,state:"lookup_failed",http:rr.status});continue}
   const runs=(await rr.json()).workflow_runs||[];
   const run=matchingRun(runs,d);
   if(!run){
     if(Date.now()-Date.parse(d.created_at)>15*60*1000){
       const applied=await sb.rpc("jo_core_apply_github_dispatch_result",{p_dispatch_id:d.dispatch_id,p_state:"failed",p_run_id:null,p_status:null,p_conclusion:null,p_artifact_id:null,p_artifact_name:null,p_error:"No commit-matched workflow run within 15 minutes"});
       out.push({dispatch_id:d.dispatch_id,state:applied.error?"apply_failed":"failed",reason:"commit_matched_run_missing"});
     }else out.push({dispatch_id:d.dispatch_id,state:"waiting_for_commit_matched_run"});
     continue;
   }
   if(run.status!=="completed"){await sb.rpc("jo_core_apply_github_dispatch_result",{p_dispatch_id:d.dispatch_id,p_state:"running",p_run_id:run.id,p_status:run.status,p_conclusion:null,p_artifact_id:null,p_artifact_name:null,p_error:null});out.push({dispatch_id:d.dispatch_id,state:"running",run_id:run.id});continue}
   if(run.conclusion!=="success"){await sb.rpc("jo_core_apply_github_dispatch_result",{p_dispatch_id:d.dispatch_id,p_state:"failed",p_run_id:run.id,p_status:run.status,p_conclusion:run.conclusion,p_artifact_id:null,p_artifact_name:null,p_error:"Commons workflow: "+run.conclusion});out.push({dispatch_id:d.dispatch_id,state:"failed",run_id:run.id,conclusion:run.conclusion});continue}
   const ar=await fetch(`${repo}/actions/runs/${run.id}/artifacts?name=commons-media`,{headers:h});const arts=ar.ok?((await ar.json()).artifacts||[]):[];const art=arts.find((a:any)=>!a.expired&&a.name==="commons-media");
   if(!art){out.push({dispatch_id:d.dispatch_id,state:"waiting_for_artifact",run_id:run.id});continue}
   await sb.rpc("jo_core_apply_github_dispatch_result",{p_dispatch_id:d.dispatch_id,p_state:"media_ready",p_run_id:run.id,p_status:run.status,p_conclusion:run.conclusion,p_artifact_id:art.id,p_artifact_name:art.name,p_error:null});
   out.push({dispatch_id:d.dispatch_id,state:"media_ready",run_id:run.id,artifact_id:art.id});
 }
 return Response.json({ok:true,checked:(rows||[]).length,results:out});
});