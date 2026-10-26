import { createClient } from "npm:@supabase/supabase-js@2.95.0";
const AUTH="https://pubnivjjeofxqvmttuzh.supabase.co/functions/v1/jo-core-capability-probe";
const PHONE="+12025550102";
Deno.serve(async(req)=>{
 if(req.method!=="POST") return new Response("Method not allowed",{status:405});
 const token=req.headers.get("x-jo-scheduler-token");
 if(!token) return Response.json({error:"unauthorized"},{status:403});
 try {
  const auth=await fetch(AUTH,{method:"POST",headers:{"x-jo-scheduler-token":token,"content-type":"application/json"},body:"{}",signal:AbortSignal.timeout(10000)});
  if(!auth.ok) return Response.json({error:"unauthorized"},{status:403});
 } catch { return Response.json({error:"auth_service_unavailable"},{status:503}); }
 const url=Deno.env.get("SUPABASE_URL")!;
 const keys=JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS")||"{}");
 const key=keys.default||Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!key) return Response.json({error:"runtime_not_configured"},{status:503});
 const db=createClient(url,key,{auth:{persistSession:false}});
 const {data:run,error:claimError}=await db.rpc("jo_claim_acceptance");
 if(claimError) return Response.json({error:"claim_failed"},{status:500});
 if(!run) return Response.json({ok:true,claimed:false});
 let fixture:any=null;
 let evidence:any={scope:"isolated_simulated_application_flow",live_launch_verified:false,billing_verified:false,real_sms_verified:false};
 let errorCode:string|null=null;
 try {
  const {data,error}=await db.from("businesses").insert({
   name:"JO_CLOUD_ISOLATED_"+run.run_id+"_"+run.attempt,
   owner_phone:"+12025550101",owner_email:"cloud-test@example.invalid",
   status:"canceled",billing_status:"unpaid",setup_status:"suspended"
  }).select("id,admin_token,status,twilio_number,stripe_customer_id,stripe_subscription_id").single();
  if(error||!data) throw Error("fixture_create_failed");
  fixture=data;
  evidence.fixture_id=fixture.id;
  if(fixture.status!=="canceled"||fixture.twilio_number||fixture.stripe_customer_id||fixture.stripe_subscription_id) throw Error("fixture_not_isolated");
  const calls:any[]=[];
  async function call(route:string,body?:string){
   if(!["missed","reply"].includes(route)) throw Error("route_denied");
   const response=await fetch(url+"/functions/v1/mcr/test/"+route,{
    method:"POST",headers:{"content-type":"application/json"},
    body:JSON.stringify({admin_token:fixture.admin_token,customer_phone:PHONE,...(body?{body}:{})}),
    signal:AbortSignal.timeout(12000)
   });
   const result=await response.json();
   calls.push({route,http_status:response.status,step:result.step||null,status:result.status||null,suppressed:result.suppressed===true});
   if(!response.ok||result.ok!==true) throw Error("test_endpoint_failed");
   return result;
  }
  await call("missed");
  for(const body of ["Isolated cloud test service","Test vehicle","Tomorrow morning","00000"]) await call("reply",body);
  const {data:lead,error:leadError}=await db.from("leads").select("id,status,step,service,vehicle,preferred_time,zip_code").eq("business_id",fixture.id).eq("customer_phone",PHONE).single();
  if(leadError||!lead||lead.status!=="qualified"||lead.step!=="done"||lead.service!=="Isolated cloud test service"||lead.vehicle!=="Test vehicle"||lead.preferred_time!=="Tomorrow morning"||lead.zip_code!=="00000") throw Error("independent_qualification_readback_failed");
  evidence.qualification=lead;
  const {data:messages,error:messageError}=await db.from("message_log").select("direction,provider_sid,to_number").eq("business_id",fixture.id);
  if(messageError||!messages) throw Error("message_readback_failed");
  const outbound=messages.filter(m=>m.direction==="outbound_simulated");
  if(messages.some(m=>m.provider_sid||!["outbound_simulated","inbound"].includes(m.direction))||outbound.length!==6||outbound.filter(m=>m.to_number==="+12025550101").length!==1) throw Error("simulation_or_notification_verification_failed");
  await call("reply","STOP");
  const suppressed=await call("missed");
  const {data:stopped,error:stopError}=await db.from("leads").select("status,step").eq("id",lead.id).single();
  const {data:after,error:afterError}=await db.from("message_log").select("id,direction,provider_sid").eq("business_id",fixture.id);
  if(stopError||afterError||stopped?.status!=="opted_out"||suppressed.suppressed!==true||!after||after.length!==messages.length+1||after.some(m=>m.provider_sid)) throw Error("stop_suppression_readback_failed");
  const {data:finalFixture,error:fixtureError}=await db.from("businesses").select("status,billing_status,twilio_number,stripe_customer_id,stripe_subscription_id").eq("id",fixture.id).single();
  if(fixtureError||finalFixture?.status!=="canceled"||finalFixture?.billing_status!=="unpaid"||finalFixture?.twilio_number||finalFixture?.stripe_customer_id||finalFixture?.stripe_subscription_id) throw Error("fixture_isolation_lost");
  evidence={...evidence,calls,qualified_verified:true,stop_verified:true,suppression_verified:true,simulated_outbound:6,provider_messages:0,fixture_inactive:true,verified_at:new Date().toISOString()};
 } catch(e) {
  const safe=new Set(["fixture_create_failed","fixture_not_isolated","route_denied","test_endpoint_failed","independent_qualification_readback_failed","message_readback_failed","simulation_or_notification_verification_failed","stop_suppression_readback_failed","fixture_isolation_lost"]);
  errorCode=safe.has((e as Error).message)?(e as Error).message:"execution_failed_or_timed_out";
 }
 const {data:accepted,error:finishError}=await db.rpc("jo_finish_acceptance",{p_run_id:run.run_id,p_token:run.lease_token,p_passed:errorCode===null,p_evidence:evidence,p_error:errorCode});
 if(finishError||accepted!==true) return Response.json({error:"completion_fence_rejected",run_id:run.run_id},{status:409});
 return Response.json({ok:errorCode===null,run_id:run.run_id,attempt:run.attempt,evidence,error:errorCode});
});
