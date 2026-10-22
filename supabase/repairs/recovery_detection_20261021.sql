CREATE OR REPLACE FUNCTION jo_core.detect_recovery_incidents()
RETURNS jsonb LANGUAGE plpgsql SET search_path TO '' AS $body$
DECLARE x record; k text; n integer:=0;
BEGIN
 IF NOT pg_try_advisory_xact_lock(hashtextextended('jo_core.detect_recovery_incidents',0)) THEN RETURN '{"busy":true}'::jsonb; END IF;
 FOR x IN
 WITH recent_runs AS MATERIALIZED (select jobid,status,start_time from cron.job_run_details order by runid desc limit 500)
 select lower(j.role::text) worker_key,'job:'||j.job_id::text fingerprint,
 'recurring_no_progress' failure_class,
 'Recovery budget reached for job '||j.job_id::text summary,
 coalesce(j.last_error,'No progress') cause
 from team_v4.jobs j where j.status in ('stalled','failed') and (j.no_progress_cycles>=j.max_attempts or j.attempts>=j.max_attempts)
 union all
 select 'jeff','briefing:'||b.briefing_id::text,'missing_delivery',
 'Scheduled briefing lacks destination receipt', 'Briefing '||b.briefing_id::text||' remains undelivered'
 from jo_core.briefings b where b.scheduled_for<now()-interval '15 minutes' and b.scheduled_for>now()-interval '2 days' and b.delivered_at is null
 union all
 select lower(j.role::text),'missing-step:'||j.job_id::text,'missing_executable_step',
 'Executable job lacks its current step', 'Missing step '||j.current_step_index::text
 from team_v4.jobs j where j.status in ('queued','stalled','in_progress')
 and not exists(select 1 from team_v4.job_steps s where s.job_id=j.job_id and s.step_index=j.current_step_index)
 and not exists(select 1 from team_v4.verification_results v where v.job_id=j.job_id and v.status='passed')
 union all
 select 'jo','cron-failure:'||d.jobid::text,'scheduled_trigger_failure',
 'Scheduled SQL trigger failed', 'Cron job '||d.jobid::text||' requires log inspection'
 from (select distinct jobid from recent_runs where status='failed' and start_time>now()-interval '2 hours') d
 union all
 select 'jo','cron-missed:'||c.jobid::text,'missed_schedule',
 'Minute schedule has no successful trigger in five minutes','Cron job '||c.jobname
 from cron.job c where c.active and c.schedule='* * * * *'
 and not exists(select 1 from recent_runs d where d.jobid=c.jobid and d.status='succeeded' and d.start_time>now()-interval '5 minutes')
 LOOP
 k:='autonomous-recovery:'||x.fingerprint;
 IF NOT EXISTS(select 1 from jo_core.failure_memory where failure_fingerprint=k) THEN
 insert into jo_core.failure_memory(worker_key,failure_fingerprint,failure_class,summary,root_cause,status)
 values(x.worker_key,k,x.failure_class,x.summary,x.cause,'diagnosing');
 insert into jo_core.events(worker_key,event_type,detail) values(x.worker_key,'recovery_incident_detected',jsonb_build_object('fingerprint',k,'cause',x.cause,'owner_action_required',false,'business_completion',false));
 n:=n+1;
 ELSE
 update jo_core.failure_memory set last_seen_at=now(),root_cause=x.cause where failure_fingerprint=k;
 END IF;
 END LOOP;
 RETURN jsonb_build_object('new_incidents',n,'observed_at',now());
END $body$;
REVOKE ALL ON FUNCTION jo_core.detect_recovery_incidents() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION jo_core.detect_recovery_incidents() TO service_role;