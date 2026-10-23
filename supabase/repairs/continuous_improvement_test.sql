begin;
do $$
declare a jsonb; b jsonb;
begin
 a:=public.jo_improvement_claim();
 if a is null then raise exception 'fixture slot already occupied'; end if;
 b:=public.jo_improvement_claim();
 if b is not null then raise exception 'duplicate lease allowed'; end if;
 if public.jo_improvement_finish((a->>'id')::uuid,gen_random_uuid(),'{}') then raise exception 'stale lease accepted'; end if;
 update jo_core.improvement_runs set started_at=now()-interval '11 minutes' where id=(a->>'id')::uuid;
 b:=public.jo_improvement_claim();
 if b is null or b->>'lease_token'=a->>'lease_token' then raise exception 'lease not recovered'; end if;
 update jo_core.improvement_runs set attempts=3,started_at=now()-interval '11 minutes' where id=(a->>'id')::uuid;
 if public.jo_improvement_claim() is not null then raise exception 'retry budget bypass'; end if;
 if has_function_privilege('anon','public.jo_improvement_claim()','execute') or has_table_privilege('authenticated','jo_core.improvement_runs','select') then raise exception 'public access'; end if;
end $$;
rollback;