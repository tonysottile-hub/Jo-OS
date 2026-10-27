-- Owner invokes ONLY inside the authenticated Supabase SQL Editor.
-- No plaintext key is written to a table, log, repository, or chat.
CREATE OR REPLACE FUNCTION rio_integration.provision_readonly_owner()
RETURNS TABLE (credential text, expires_at timestamptz)
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE new_key text; expiry timestamptz := now()+interval '7 days';
BEGIN
 IF current_user <> 'postgres' THEN
   RAISE EXCEPTION 'Owner admin session required' USING ERRCODE='42501';
 END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(710026,1);
 IF EXISTS (SELECT 1 FROM rio_integration.api_clients c WHERE c.client_id='rio' AND c.enabled AND c.revoked_at IS NULL AND c.expires_at>now()) THEN
   RAISE EXCEPTION 'An active Rio credential already exists. Revoke it explicitly before replacing it.';
 END IF;
 new_key := 'rio_' || pg_catalog.encode(extensions.gen_random_bytes(32),'hex');
 INSERT INTO rio_integration.api_clients AS c
   (client_id,token_sha256,enabled,permissions,expires_at,revoked_at)
 VALUES ('rio',pg_catalog.encode(extensions.digest(new_key,'sha256'),'hex'),true,ARRAY['read_approved_posts'],expiry,NULL)
 ON CONFLICT (client_id) DO UPDATE SET
   token_sha256=EXCLUDED.token_sha256,enabled=true,
   permissions=EXCLUDED.permissions,expires_at=EXCLUDED.expires_at,revoked_at=NULL;
 INSERT INTO rio_integration.audit_log(action,actor,detail)
 VALUES ('credential_provisioned','owner_admin',pg_catalog.jsonb_build_object('client_id','rio','permissions',ARRAY['read_approved_posts'],'expires_at',expiry));
 RETURN QUERY SELECT new_key,expiry;
END $$;
REVOKE ALL ON FUNCTION rio_integration.provision_readonly_owner() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION rio_integration.provision_readonly_owner() TO postgres;
COMMENT ON FUNCTION rio_integration.provision_readonly_owner() IS 'Owner SQL Editor only. Returns a new secret once; never invoke through an assistant tool or share result in chat. Seven-day read-only scope; refuses replacement of active credentials.';
