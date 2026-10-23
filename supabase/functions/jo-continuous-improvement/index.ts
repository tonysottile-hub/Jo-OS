import {createClient} from "jsr:@supabase/supabase-js@2.95.0";
const lanes = [
 {worker:"jo",query:"repo:supabase/supabase is:issue cron retry",doc:"https://supabase.com/docs/guides/functions/schedule-functions",test:"Inject a missed schedule; verify recovery and independent completion without an interactive session."},
 {worker:"tom",query:"repo:googleapis/google-api-python-client is:issue youtube upload",doc:"https://developers.google.com/youtube/data/guides/uploading_a_video",test:"Use approved place-specific media, verify QA and correct-channel delivery; preserve publication holds."},
 {worker:"mary",query:"repo:microsoft/playwright is:issue 403",doc:"https://playwright.dev/docs/best-practices",test:"Verify approved product identity, visibility and cart availability without modifying artwork or purchasing."},
 {worker:"steve",query:"repo:twilio/twilio-node is:issue messaging",doc:"https://www.twilio.com/docs/messaging/guides/debugging-common-issues",test:"Diagnose provider rejection; test in isolation; require provider approval before live messaging."},
 {worker:"jeff",query:"repo:googleapis/google-api-python-client is:issue gmail authentication",doc:"https://developers.google.com/workspace/gmail/api/guides",test:"Verify authorized mailbox access and actual destination receipt; never treat a saved draft as delivery."}
];
async function read(url:string) {
 const r=await fetch(url,{headers:{"User-Agent":"JoOS-Research/1.0","Accept":"application/json,text/html"},redirect:"error",signal:AbortSignal.timeout(10000)});
 if(!r.ok)throw new Error("HTTP "+r.status);
 const reader=r.body!.getReader(); let size=0; const chunks:Uint8Array[]=[];
 while(true){const {done,value}=await reader.read();if(done)break; size+=value.length;if(size>1000000){await reader.cancel();throw new Error("response_size_limit");} chunks.push(value);}
 const all=new Uint8Array(size);let offset=0;for(const c of chunks){all.set(c,offset);offset+=c.length;}
 return new TextDecoder().decode(all);
}
Deno.serve(async(req)=>{
 if(req.method!=="POST")return new Response("Method not allowed",{status:405});
 const db=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false}});
 const token=req.headers.get("x-jo-scheduler-token")||"";
 if(!token)return Response.json({error:"unauthorized"},{status:403});
 const auth=await db.rpc("jo_core_verify_scheduler_bridge",{p_token:token});
 if(auth.error||auth.data!==true)return Response.json({error:"unauthorized"},{status:403});
 const claim=await db.rpc("jo_improvement_claim");
 if(claim.error)return Response.json({error:"claim_failed"},{status:500});
 if(!claim.data)return Response.json({skipped:true,reason:"slot_completed_or_retry_budget_or_lease"});
 const results:any[]=[], candidates:any[]=[];
 // Only fixed, public queries leave the service. No customer records, errors or credentials are sent.
 for(const lane of lanes){
  const row:any={worker:lane.worker,query:lane.query,retrieved_at:new Date().toISOString(),search_ok:false};
  try{
   const data=JSON.parse(await read("https://api.github.com/search/issues?q="+encodeURIComponent(lane.query)+"&sort=updated&order=desc&per_page=3"));
   if(!Array.isArray(data.items))throw new Error("invalid_search_response");
   row.search_ok=true;row.total=data.total_count;
   for(const item of data.items){
    if(typeof item.html_url!=="string"||!item.html_url.startsWith("https://github.com/"))continue;
    candidates.push({worker_key:lane.worker,url:item.html_url,title:String(item.title).slice(0,300),updated_at:item.updated_at,
      provenance:"public_issue_search_untrusted",required_test:lane.test,applied:false,business_result_verified:false});
   }
  }catch(e){row.search_error=(e as Error).message;}
  results.push(row);
 }
 const docs=await Promise.all(lanes.map(async lane=>{
  try{const body=await read(lane.doc);const hash=Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(body)))).map(x=>x.toString(16).padStart(2,"0")).join("");
   return {worker:lane.worker,url:lane.doc,ok:true,sha256:hash,bytes:body.length,retrieved_at:new Date().toISOString()};
  }catch(e){return {worker:lane.worker,url:lane.doc,ok:false,error:(e as Error).message};}
 }));
 const evidence={results,docs,candidates,successful_searches:results.filter(x=>x.search_ok).length,
   observed_worker_state:claim.data.workers,open_incidents:claim.data.incidents,
   capabilities:{openai_key_present:!!Deno.env.get("OPENAI_API_KEY"),anthropic_key_present:!!Deno.env.get("ANTHROPIC_API_KEY"),tavily_key_present:!!Deno.env.get("TAVILY_API_KEY")},
   scope:"source_discovery_only",improvements_applied:0,business_completion:false};
 const finish=await db.rpc("jo_improvement_finish",{p_id:claim.data.id,p_lease:claim.data.lease_token,p_evidence:evidence});
 if(finish.error||finish.data!==true)return Response.json({error:"evidence_write_failed"},{status:500});
 return Response.json({run_id:claim.data.id,successful_searches:evidence.successful_searches,candidates:candidates.length,business_completion:false});
});
