BEGIN;
DO $test$
DECLARE k text; e timestamptz; stored text; r text;
BEGIN
 FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   IF has_function_privilege(r,'rio_integration.provision_readonly_owner()','execute') THEN RAISE EXCEPTION 'Unprivileged execution: %',r; END IF;
 END LOOP;
 SELECT credential,expires_at INTO k,e FROM rio_integration.provision_readonly_owner();
 IF k !~ '^rio_[a-f0-9]{64}$' THEN RAISE EXCEPTION 'Key format'; END IF;
 SELECT token_sha256 INTO stored FROM rio_integration.api_clients WHERE client_id='rio' AND enabled AND revoked_at IS NULL AND permissions=ARRAY['read_approved_posts'];
 IF stored IS DISTINCT FROM encode(extensions.digest(k,'sha256'),'hex') OR e<>now()+interval '7 days' THEN RAISE EXCEPTION 'Hash/scope/expiry mismatch'; END IF;
 BEGIN
   PERFORM rio_integration.provision_readonly_owner();
   RAISE EXCEPTION 'Duplicate provisioning accepted' USING ERRCODE='23514';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM NOT LIKE 'An active Rio credential already exists%' THEN RAISE; END IF;
 END;
 IF EXISTS (SELECT 1 FROM rio_integration.audit_log WHERE detail::text LIKE '%'||k||'%') THEN RAISE EXCEPTION 'Secret in audit'; END IF;
END $test$;
ROLLBACK;
SELECT 'PASS: owner-only ACL, 256-bit key format, matching hash, read-only scope, seven-day expiry, replacement prevention, no plaintext audit; generated test key and changes rolled back' AS result;