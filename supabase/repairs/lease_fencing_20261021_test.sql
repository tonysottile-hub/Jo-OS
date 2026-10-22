begin;
DO $test$
DECLARE j uuid; r uuid; blocked boolean:=false;
BEGIN
 insert into team_v4.jobs(role,outcome_description,priority,lease_owner,lease_expires_at,status)
 values('Jo','ISOLATED lease fencing regression',-999,'test-worker',now()+interval '5 minutes','in_progress') returning job_id into j;
 insert into team_v4.job_steps(job_id,step_index,action,input) values(j,0,'jo_core.echo','{}');
 insert into team_v4.worker_runs(job_id,worker_id,step_index,lease_expires_at)
 values(j,'test-worker',0,now()+interval '5 minutes') returning run_id into r;
 perform team_v4.complete_worker_step(r,j,0,'test-worker','success','{}','{}');
 if not exists(select 1 from team_v4.jobs where job_id=j and current_step_index=1 and lease_owner is null) then raise exception 'valid completion failed'; end if;
 begin perform team_v4.complete_worker_step(r,j,0,'test-worker','success','{}','{}');
 exception when others then if sqlerrm='stale_or_invalid_job_lease' then blocked:=true; else raise; end if; end;
 if not blocked then raise exception 'duplicate completion accepted'; end if;
 update team_v4.jobs set current_step_index=0,status='in_progress',lease_owner='replacement-worker',lease_expires_at=now()+interval '5 minutes' where job_id=j;
 update team_v4.worker_runs set ended_at=null,lease_expires_at=now()-interval '1 minute' where run_id=r;
 blocked:=false;
 begin perform team_v4.finish_worker_run(r,1,true);
 exception when others then if sqlerrm='stale_or_invalid_job_lease' then blocked:=true; else raise; end if; end;
 if not blocked then raise exception 'stale finisher accepted'; end if;
 if not exists(select 1 from team_v4.jobs where job_id=j and lease_owner='replacement-worker') then raise exception 'replacement lease corrupted'; end if;
 update team_v4.jobs set lease_owner='test-worker',lease_expires_at=now()-interval '1 minute' where job_id=j;
 blocked:=false;
 begin perform team_v4.complete_worker_step(r,j,0,'test-worker','success','{}','{}');
 exception when others then if sqlerrm='stale_or_invalid_job_lease' then blocked:=true; else raise; end if; end;
 if not blocked then raise exception 'expired completion accepted'; end if;
END $test$;
rollback;