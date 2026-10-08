import {createClient} from "jsr:@supabase/supabase-js@2.95.0";
import {unzipSync,strFromU8} from "npm:fflate@0.8.2";
Deno.serve(async(req)=>{
 if(req.method!=="POST")return new Response("Method not allowed",{status:405});
 const db=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false}});
 const token=req.headers.get("x-jo-scheduler-token")||"";
 if(!token)return Response.json({error:"unauthorized"},{status:403});
 const auth=await db.rpc("jo_core_verify_scheduler_bridge",{p_token:token});
 if(auth.error||auth.data!==true)return Response.json({error:"unauthorized"},{status:403});
 try{
 const gh=Deno.env.get("JO_GITHUB_TOKEN");if(!gh)throw new Error("github_secret_missing");
 const base="https://api.github.com/repos/tonysottile-hub/Jo-OS";
 const headers={Authorization:"Bearer "+gh,Accept:"application/vnd.github+json","User-Agent":"Jo-OS-Audit-Verifier"};
 async function get(path:string){const r=await fetch(base+path,{headers,signal:AbortSignal.timeout(15000)});if(!r.ok)throw new Error("github_http_"+r.status);return r.json();}
 const runs=await get("/actions/workflows/browser-audit.yml/runs?branch=main&status=completed&per_page=1");
 const run=runs.workflow_runs?.[0];
 if(!run)return Response.json({imported:false,reason:"no_completed_main_run"});
 if(run.conclusion!=="success"||run.path!==".github/workflows/browser-audit.yml")throw new Error("workflow_failed");
 const artifacts=await get("/actions/runs/"+run.id+"/artifacts");
 const artifact=artifacts.artifacts?.find((x:any)=>x.name==="jo-public-browser-evidence"&&!x.expired);
 if(!artifact||artifact.size_in_bytes>5000000)throw new Error("artifact_missing_or_oversized");
 const redirect=await fetch(base+"/actions/artifacts/"+artifact.id+"/zip",{headers,redirect:"manual",signal:AbortSignal.timeout(15000)});
 const location=redirect.headers.get("location");if(!location)throw new Error("artifact_redirect_missing");
 const u=new URL(location);
 if(u.protocol!=="https:"||!(u.hostname.endsWith(".blob.core.windows.net")||u.hostname.endsWith(".actions.githubusercontent.com")))throw new Error("artifact_host_denied");
 const response=await fetch(location,{redirect:"error",signal:AbortSignal.timeout(20000)});
 if(!response.ok)throw new Error("artifact_download_failed");
 const bytes=new Uint8Array(await response.arrayBuffer());if(bytes.length>5000000)throw new Error("artifact_too_large");
 const files=unzipSync(bytes,{filter:f=>f.name==="result.json"&&f.originalSize<1000000});
 if(!files["result.json"])throw new Error("result_missing");
 const evidence=JSON.parse(strFromU8(files["result.json"]));
 const saved=await db.rpc("jo_core_import_cloud_audit",{p_run_id:run.id,p_sha:run.head_sha,p_evidence:evidence});
 if(saved.error)throw new Error("evidence_persist_failed:"+saved.error.message);
 return Response.json({ok:true,run_id:run.id,result:saved.data});
 }catch(e){return Response.json({ok:false,error:String((e as Error).message).slice(0,180)},{status:502});}
});
