CREATE OR REPLACE FUNCTION team_v4.close_completed_jobs()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n integer;
begin
 update team_v4.jobs j set status='done',last_verified_at=now()
 where j.status in ('in_progress','verify_pending') and j.current_step_index>0
 and not exists(select 1 from team_v4.job_steps next_s where next_s.job_id=j.job_id and next_s.step_index=j.current_step_index)
 and exists (
  select 1 from team_v4.job_steps s
  where s.job_id=j.job_id and s.step_index=j.current_step_index-1
  and s.result in ('success','advanced')
  and exists (
   select 1 from team_v4.verification_results v
   where v.job_id=j.job_id and v.status='passed' and v.checked_at>=s.completed_at
   and v.evidence<>'{}'::jsonb
   and (
    (v.evidence->>'external_work_verified'='true' and v.evidence->>'delivery_verified'='true')
    or (
      s.action='web.public_audit' and s.input->>'scope'='public_read_only'
      and v.mechanism='independent_urllib_get'
      and v.evidence->>'passed'='true'
      and v.evidence->>'worker'=lower(j.role::text)
      and v.evidence->>'cloud_run_id'=s.input->>'cloud_run_id'
      and exists(select 1 from jo_core.cloud_audit_runs ar
        cross join lateral jsonb_array_elements(ar.evidence->'verification') av
        where ar.run_id::text=s.input->>'cloud_run_id'
        and ar.commit_sha=v.evidence->>'commit_sha'
        and av->>'worker'=lower(j.role::text) and av->>'passed'='true'
        and av->>'sha256'=v.evidence->>'sha256')
    )
    or (
      v.evidence->>'scope'='internal_database_action_only'
      and v.evidence->>'external_work_verified'='false'
      and v.evidence->>'delivery_verified'='false'
      and coalesce((s.input->>'read_only')::boolean,false)
      and coalesce((s.input->>'no_external_publication')::boolean,false)
      and j.outcome_description ilike '%internal database action only%'
    )
   )
  )
 );
 get diagnostics n=row_count; return n;
end $function$;