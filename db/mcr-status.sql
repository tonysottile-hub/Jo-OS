CREATE OR REPLACE FUNCTION public.jo_core_record_mcr_status(p_health jsonb,p_twilio jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE previous text; current_status text; changed boolean;
BEGIN
 IF p_health->>'ok'<>'true' OR p_twilio->>'ok'<>'true' THEN RAISE EXCEPTION 'Invalid provider check'; END IF;
 current_status:=p_twilio->>'campaign_status';
 IF current_status IS NULL THEN RAISE EXCEPTION 'Missing campaign status'; END IF;
 SELECT evidence->>'campaign_status' INTO previous FROM jo_core.steve_launch_stages WHERE stage_key='twilio_a2p' FOR UPDATE;
 changed:=previous IS DISTINCT FROM current_status;
 UPDATE jo_core.steve_launch_stages SET evidence=evidence||jsonb_build_object('campaign_status',current_status,'brand_status',p_twilio->>'brand_status','campaign_errors',p_twilio->'campaign_errors','checked_at',now(),'stripe_configured',p_health->'stripeConfigured','missing_secrets',p_health->'missingSecrets','cloud_status_monitor',true),
 status=CASE WHEN current_status IN ('VERIFIED','APPROVED') THEN 'verified' ELSE 'blocked_external' END,
 verified_at=CASE WHEN current_status IN ('VERIFIED','APPROVED') THEN now() ELSE NULL END,
 last_error=CASE WHEN current_status IN ('VERIFIED','APPROVED') THEN NULL ELSE 'Twilio campaign: '||current_status END,updated_at=now()
 WHERE stage_key='twilio_a2p';
 UPDATE jo_core.steve_launch_stages SET status=CASE WHEN p_health->>'stripeConfigured'='true' THEN 'pending' ELSE 'blocked_owner' END,
 last_error=CASE WHEN p_health->>'stripeConfigured'='true' THEN 'Credential present; TEST mode must be verified before billing tests' ELSE 'Install Stripe TEST secret as STRIPE_SECRET_KEY in MCR project ibiuhwxypusbuurtmyzk' END,
 evidence=evidence||jsonb_build_object('checked_at',now(),'runtime_configured',p_health->'stripeConfigured'),updated_at=now()
 WHERE stage_key='stripe_test_secret' AND status<>'verified';
 INSERT INTO jo_core.events(worker_key,event_type,detail) VALUES('steve',CASE WHEN changed THEN 'mcr_provider_status_changed' ELSE 'mcr_provider_status_checked' END,
 jsonb_build_object('previous',previous,'current',current_status,'health',p_health,'campaign_errors',p_twilio->'campaign_errors','checked_at',now(),'launch_complete',false));
 RETURN jsonb_build_object('changed',changed,'campaign_status',current_status,'stripe_configured',p_health->'stripeConfigured','launch_complete',false);
END $$;
REVOKE ALL ON FUNCTION public.jo_core_record_mcr_status(jsonb,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.jo_core_record_mcr_status(jsonb,jsonb) TO service_role;

