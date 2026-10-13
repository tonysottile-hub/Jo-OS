begin;
select jo_core.run_jeff_manager_cycle();
select jo_core.run_steve_manager_cycle();
select jo_core.sync_worker_state();
do $t$
begin
 if exists(select 1 from jo_core.worker_state w join jo_core.team_status t using(worker_key) where w.state is distinct from t.live_state or w.current_job_id is distinct from t.current_job_id)
 then raise exception 'Worker status disagrees with live diagnostic'; end if;
 if exists(select 1 from team_v4.jobs j where j.job_id='974b9ffc-bef2-4cc3-bb6e-d6a6f74c8d77' and not exists(select 1 from team_v4.job_steps s where s.job_id=j.job_id and s.step_index=j.current_step_index))
 then raise exception 'Jo oversight still lacks current step'; end if;
 if (jo_core.read_execution_gate('unmapped.tom.publish_qa','{"build_id":"666e8f83-1f40-4229-88ec-d66fbdaee3b6"}')->>'ready')::boolean
 then raise exception 'Unpublished video incorrectly accepted'; end if;
 if (jo_core.read_execution_gate('jo_core.fleet_business_acceptance','{}')->>'ready')::boolean
 then raise exception 'Missing business acceptance evidence incorrectly accepted'; end if;
 if exists(select 1 from team_v4.jobs where job_id in ('974b9ffc-bef2-4cc3-bb6e-d6a6f74c8d77','b5ea681b-814c-4829-9fbe-40b1ad6af8d0','6032246c-9196-4e1a-b31d-9314ec592d04') and status='done')
 then raise exception 'Unfinished business job marked done'; end if;
end $t$;
select 'worker consistency and false-completion prevention passed' result;
rollback;