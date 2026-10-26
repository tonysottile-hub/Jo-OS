CREATE TABLE public.jo_acceptance_runs (
 run_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 slot bigint NOT NULL UNIQUE,
 state text NOT NULL DEFAULT 'running' CHECK(state IN ('running','passed','retry','exhausted')),
 attempt integer NOT NULL DEFAULT 1 CHECK(attempt BETWEEN 1 AND 3),
 lease_token uuid NOT NULL DEFAULT gen_random_uuid(),
 lease_expires_at timestamptz NOT NULL DEFAULT now()+interval '3 minutes',
 next_attempt_at timestamptz NOT NULL DEFAULT now(),
 evidence jsonb NOT NULL DEFAULT '{}'::jsonb,
 error_code text,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.jo_acceptance_runs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.jo_acceptance_runs FROM anon,authenticated;
GRANT SELECT ON public.jo_acceptance_runs TO service_role;
CREATE FUNCTION public.jo_claim_acceptance() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.jo_acceptance_runs; s bigint:=floor(extract(epoch from now())/21600)::bigint;
BEGIN
 IF NOT pg_try_advisory_xact_lock(56432026) THEN RETURN NULL; END IF;
 SELECT * INTO r FROM public.jo_acceptance_runs WHERE slot=s FOR UPDATE;
 IF r.run_id IS NULL THEN
  INSERT INTO public.jo_acceptance_runs(slot) VALUES(s) RETURNING * INTO r;
 ELSIF r.state IN ('passed','exhausted') OR r.next_attempt_at>now() OR (r.state='running' AND r.lease_expires_at>now()) THEN
  RETURN NULL;
 ELSIF r.attempt>=3 THEN
  UPDATE public.jo_acceptance_runs SET state='exhausted',error_code='retry_budget_exhausted',updated_at=now() WHERE run_id=r.run_id;
  RETURN NULL;
 ELSE
  UPDATE public.jo_acceptance_runs SET attempt=attempt+1,state='running',lease_token=gen_random_uuid(),lease_expires_at=now()+interval '3 minutes',updated_at=now() WHERE run_id=r.run_id RETURNING * INTO r;
 END IF;
 RETURN to_jsonb(r);
END $$;
CREATE FUNCTION public.jo_finish_acceptance(p_run_id uuid,p_token uuid,p_passed boolean,p_evidence jsonb,p_error text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 UPDATE public.jo_acceptance_runs SET
 state=CASE WHEN p_passed THEN 'passed' WHEN attempt>=3 THEN 'exhausted' ELSE 'retry' END,
 evidence=p_evidence,error_code=p_error,lease_expires_at=now(),
 next_attempt_at=now()+interval '5 minutes'*power(2,attempt-1),updated_at=now()
 WHERE run_id=p_run_id AND lease_token=p_token AND state='running' AND lease_expires_at>clock_timestamp();
 RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.jo_claim_acceptance() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.jo_finish_acceptance(uuid,uuid,boolean,jsonb,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.jo_claim_acceptance(),public.jo_finish_acceptance(uuid,uuid,boolean,jsonb,text) TO service_role;

CREATE OR REPLACE FUNCTION public.jo_finish_acceptance(p_run_id uuid,p_token uuid,p_passed boolean,p_evidence jsonb,p_error text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 UPDATE public.jo_acceptance_runs SET
 state=CASE WHEN p_passed THEN 'passed' WHEN attempt>=3 THEN 'exhausted' ELSE 'retry' END,
 evidence=p_evidence||jsonb_build_object('attempt_history',coalesce(evidence->'attempt_history','[]'::jsonb)||jsonb_build_array(jsonb_build_object('attempt',attempt,'passed',p_passed,'error',p_error,'at',now(),'evidence',p_evidence))),error_code=p_error,lease_expires_at=now(),
 next_attempt_at=now()+interval '5 minutes'*power(2,attempt-1),updated_at=now()
 WHERE run_id=p_run_id AND lease_token=p_token AND state='running' AND lease_expires_at>clock_timestamp();
 RETURN FOUND;
END $$;
