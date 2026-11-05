BEGIN;
SET LOCAL request.jwt.claims = '{"role":"service_role"}';
DO $$
DECLARE r jsonb; fixture_id uuid:=gen_random_uuid();
BEGIN
 IF has_function_privilege('anon','public.rio_readonly_request(text,text,text,uuid,text,integer,uuid)','execute') OR has_function_privilege('authenticated','public.rio_readonly_request(text,text,text,uuid,text,integer,uuid)','execute') THEN RAISE EXCEPTION 'public RPC access'; END IF;
 IF has_schema_privilege('anon','rio_integration','usage') OR has_schema_privilege('authenticated','rio_integration','usage') THEN RAISE EXCEPTION 'public schema access'; END IF;
 INSERT INTO rio_integration.api_clients(client_id,token_sha256,enabled,permissions,expires_at) VALUES('rio',repeat('a',64),true,ARRAY['read_approved_posts'],now()+interval '5 minutes');
 r:=public.rio_readonly_request(repeat('b',64),'rio','health/auth',gen_random_uuid()); IF (r->>'status')::int<>401 THEN RAISE EXCEPTION 'wrong key'; END IF;
 r:=public.rio_readonly_request(repeat('a',64),'rio','health/auth',gen_random_uuid()); IF (r->>'status')::int<>200 THEN RAISE EXCEPTION 'valid key %',r; END IF;
 UPDATE rio_integration.api_clients SET revoked_at=now() WHERE client_id='rio';
 r:=public.rio_readonly_request(repeat('a',64),'rio','health/auth',gen_random_uuid()); IF (r->>'status')::int<>401 THEN RAISE EXCEPTION 'revoked key'; END IF;
 UPDATE rio_integration.api_clients SET revoked_at=null,expires_at=now()-interval '1 second' WHERE client_id='rio';
 r:=public.rio_readonly_request(repeat('a',64),'rio','health/auth',gen_random_uuid()); IF (r->>'status')::int<>401 THEN RAISE EXCEPTION 'expired key'; END IF;
 UPDATE rio_integration.api_clients SET expires_at=now()+interval '5 minutes',permissions='{}' WHERE client_id='rio';
 r:=public.rio_readonly_request(repeat('a',64),'rio','health/auth',gen_random_uuid()); IF (r->>'status')::int<>403 THEN RAISE EXCEPTION 'scope'; END IF;
 UPDATE rio_integration.api_clients SET permissions=ARRAY['read_approved_posts'] WHERE client_id='rio';
 -- Synthetic rows exist only in this rolled-back transaction. Never externally visible.
 INSERT INTO rio_integration.publish_queue(id,source_worker,destination,caption,content_sha256,approval_status,approved_by,approved_at,approval_fingerprint,state) VALUES(fixture_id,'mary','cigar30_facebook','TEST ONLY','test','approved','Tony',now(),'test','approved');
 r:=public.rio_readonly_request(repeat('a',64),'rio','approved-posts',gen_random_uuid()); IF jsonb_array_length(r->'data')<>1 THEN RAISE EXCEPTION 'approved filter'; END IF;
 UPDATE rio_integration.publish_queue SET approval_status='pending' WHERE publish_queue.id=fixture_id;
 r:=public.rio_readonly_request(repeat('a',64),'rio','approved-posts',gen_random_uuid()); IF jsonb_array_length(r->'data')<>0 THEN RAISE EXCEPTION 'pending leaked'; END IF;
 UPDATE rio_integration.publish_queue SET approval_status='approved',destination='unmapped_facebook' WHERE publish_queue.id=fixture_id;
 r:=public.rio_readonly_request(repeat('a',64),'rio','approved-posts',gen_random_uuid()); IF jsonb_array_length(r->'data')<>0 THEN RAISE EXCEPTION 'unmapped leaked'; END IF;
 r:=public.rio_readonly_request(repeat('a',64),'rio','claim-post',gen_random_uuid()); IF (r->>'status')::int<>405 THEN RAISE EXCEPTION 'write accepted'; END IF;
 INSERT INTO rio_integration.audit_log(action,actor,detail) SELECT 'rate_fixture','rio','{"authenticated":true}'::jsonb FROM generate_series(1,60);
 r:=public.rio_readonly_request(repeat('a',64),'rio','health/auth',gen_random_uuid()); IF (r->>'status')::int<>429 THEN RAISE EXCEPTION 'rate limit'; END IF;
END $$;
ROLLBACK;
SELECT 'database security, authentication, filtering, rate limit assertions passed; fixtures rolled back' as result;
