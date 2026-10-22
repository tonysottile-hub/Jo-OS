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
 const results=[];
 for (const [workflow, artifactName, expected] of [
 ["jeff-public-audit.yml","jeff-public-web-evidence",["jeff"]],
 ["mary-storefront-audit.yml","mary-storefront-evidence",["mary"]]
 ] as const) { try {
 const runs=await get("/actions/workflows/"+workflow+"/runs?branch=main&status=completed&per_page=1");
 const run=runs.workflow_runs?.[0];
 if(!run)throw new Error("no_completed_main_run");
 if(Date.now()-Date.parse(run.updated_at)>86400000)throw new Error("audit_stale");
 if(!["success","failure"].includes(run.conclusion)||run.path!==".github/workflows/"+workflow)throw new Error("workflow_not_eligible");
 const artifacts=await get("/actions/runs/"+run.id+"/artifacts");
 const artifact=artifacts.artifacts?.find((x:any)=>x.name===artifactName&&!x.expired);
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
 if (!Array.isArray(evidence.verification)||evidence.verification.length!==1||evidence.verification[0].worker!==expected[0]||evidence.execution?.results?.length!==1||evidence.execution.results[0].worker!==expected[0])throw new Error("scope_mismatch");
 const saved=await db.rpc("jo_core_import_cloud_audit",{p_run_id:run.id,p_sha:run.head_sha,p_evidence:evidence});
 if(saved.error)throw new Error("evidence_persist_failed:"+saved.error.message);
 results.push({workflow,run_id:run.id,result:saved.data});
 }catch(e){results.push({workflow,error:String((e as Error).message).slice(0,180)});}
 }
 return Response.json({ok:results.every(r=>!("error" in r)),results});
 }catch(e){return Response.json({ok:false,error:String((e as Error).message).slice(0,180)},{status:502});}
});