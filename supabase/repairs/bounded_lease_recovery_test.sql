begin;
do $test$
declare retry_id uuid; exhausted_id uuid; done_id uuid; blocked_id uuid; verification_id uuid;
begin
insert into team_v4.jobs(role,outcome_description,status,lease_owner,lease_expires_at)
values('Jo','Rollback-only lease recovery test','in_progress','regression',now()-interval '1 minute') returning job_id into retry_id;
insert into team_v4.jobs(role,outcome_description,status,attempts,max_attempts,lease_owner,lease_expires_at)
values('Jo','Rollback-only exhausted budget test','in_progress',2,3,'regression',now()-interval '1 minute') returning job_id into exhausted_id;
insert into team_v4.jobs(role,outcome_description,status,lease_owner,lease_expires_at)
values('Jo','Rollback-only terminal preservation test','done','regression',now()-interval '1 minute') returning job_id into done_id;
insert into team_v4.jobs(role,outcome_description,status,escalation_flag,escalation_reason,blocking_reason,lease_owner,lease_expires_at)
values('Jo','Rollback-only owner blocker preservation test','blocked_owner',true,'Test credential required','owner_credential_needed','regression',now()-interval '1 minute') returning job_id into blocked_id;
insert into team_v4.jobs(role,outcome_description,status,lease_owner,lease_expires_at)
values('Jo','Rollback-only verification preservation test','verify_pending','regression',now()-interval '1 minute') returning job_id into verification_id;
perform team_v4.reap_expired_leases();
if not exists(select 1 from team_v4.jobs where job_id=retry_id and status='stalled' and attempts=1 and not escalation_flag and lease_owner is null) then raise exception 'retry failure'; end if;
if not exists(select 1 from team_v4.jobs where job_id=exhausted_id and status='failed' and attempts=3 and not escalation_flag) then raise exception 'budget failure'; end if;
if not exists(select 1 from team_v4.jobs where job_id=done_id and status='done' and attempts=0) then raise exception 'terminal failure'; end if;
if not exists(select 1 from team_v4.jobs where job_id=blocked_id and status='blocked_owner' and escalation_flag and blocking_reason='owner_credential_needed') then raise exception 'owner blocker failure'; end if;
if not exists(select 1 from team_v4.jobs where job_id=verification_id and status='verify_pending') then raise exception 'verification failure'; end if;
perform team_v4.reap_expired_leases();
if (select attempts from team_v4.jobs where job_id=retry_id)<>1 then raise exception 'idempotency failure'; end if;
if (select count(*) from team_v4.execution_attempts where job_id=retry_id)<>1 then raise exception 'failure evidence failure'; end if;
end $test$;
rollback;