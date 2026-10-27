-- Read-only queue access; only credential metadata and append-only audit are written.
ALTER TABLE rio_integration.api_clients ADD COLUMN IF NOT EXISTS permissions text[] NOT NULL DEFAULT '{}';
ALTER TABLE rio_integration.api_clients ADD COLUMN IF NOT EXISTS expires_at timestamptz;
REVOKE ALL ON SCHEMA rio_integration FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL TABLES IN SCHEMA rio_integration FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.rio_readonly_request(p_hash text, p_client text, p_operation text, p_request_id uuid, p_destination text DEFAULT NULL, p_limit int DEFAULT 20, p_cursor uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE c rio_integration.api_clients%ROWTYPE; code int := 200; err text; result jsonb; n int;
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service only' USING ERRCODE='42501'; END IF;
 SELECT * INTO c FROM rio_integration.api_clients WHERE client_id=p_client FOR UPDATE;
 IF c.client_id IS NULL OR p_client <> 'rio' OR NOT c.enabled OR c.revoked_at IS NOT NULL OR c.expires_at IS NULL OR c.expires_at <= now() OR c.token_sha256 IS DISTINCT FROM p_hash THEN
   code:=401; err:='unauthorized';
 ELSIF NOT ('read_approved_posts'=ANY(c.permissions)) OR c.permissions <> ARRAY['read_approved_posts']::text[] THEN
   code:=403; err:='insufficient_scope';
 ELSE
   -- Row lock serializes checks across all edge instances.
   SELECT count(*) INTO n FROM rio_integration.audit_log WHERE actor='rio' AND created_at > now()-interval '1 minute' AND detail->>'authenticated'='true';
   IF n >= 60 THEN code:=429; err:='rate_limited';
   ELSIF p_operation='health' THEN result:=jsonb_build_object('service','rio-bridge','status','ok','publishing_enabled',false,'approval_required',true);
   ELSIF p_operation='health/auth' THEN result:=jsonb_build_object('authenticated_client','rio','schema','rio_integration','database','ok','permissions',c.permissions,'publishing_enabled',false);
   ELSIF p_operation='approved-posts' THEN
     IF p_limit NOT BETWEEN 1 AND 50 OR (p_destination IS NOT NULL AND p_destination NOT IN ('cigar30_facebook','cigar30_instagram')) THEN code:=400; err:='invalid_query';
     ELSE
       SELECT coalesce(jsonb_agg(to_jsonb(q)), '[]'::jsonb) INTO result FROM (
         SELECT id,source_worker,destination,caption,media_urls,scheduled_for,approved_by,approved_at,approval_fingerprint,state
         FROM rio_integration.publish_queue WHERE state='approved' AND approval_status='approved' AND approved_by='Tony' AND approved_at IS NOT NULL AND approval_fingerprint IS NOT NULL AND claimed_by IS NULL AND claimed_at IS NULL
         AND destination IN ('cigar30_facebook','cigar30_instagram') AND (p_destination IS NULL OR destination=p_destination) AND (p_cursor IS NULL OR id>p_cursor)
         ORDER BY id LIMIT p_limit
       ) q;
     END IF;
   ELSE code:=405; err:='read_only'; END IF;
 END IF;
 INSERT INTO rio_integration.audit_log(action,actor,detail) VALUES ('bridge_read',CASE WHEN code=401 THEN 'unauthenticated' ELSE 'rio' END,jsonb_build_object('request_id',p_request_id,'operation',CASE WHEN p_operation IN ('health','health/auth','approved-posts') THEN p_operation ELSE 'denied' END,'http_status',code,'authenticated',code<>401,'error',err));
 RETURN jsonb_build_object('status',code,'data',CASE WHEN code=200 THEN result ELSE NULL END,'error',err);
END $$;
REVOKE ALL ON FUNCTION public.rio_readonly_request(text,text,text,uuid,text,int,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rio_readonly_request(text,text,text,uuid,text,int,uuid) TO service_role;
