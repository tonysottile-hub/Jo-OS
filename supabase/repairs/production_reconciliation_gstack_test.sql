BEGIN;
DO $test$
DECLARE t uuid; a uuid; cp uuid;
BEGIN
 INSERT INTO jo_core.draft_tasks(idempotency_key,worker_key,objective,context,state)
 VALUES('repair-test-rollback','jo','Synthetic rolled-back handoff test','{}','pending') RETURNING task_id,agent_id INTO t,a;
 IF a IS NULL THEN RAISE EXCEPTION 'assignment missing'; END IF;
 BEGIN
 UPDATE jo_core.draft_tasks SET worker_key='mary' WHERE task_id=t;
 RAISE EXCEPTION 'cross-manager accepted' USING ERRCODE='23514';
 EXCEPTION WHEN raise_exception THEN
 IF SQLERRM NOT IN ('No authorized draft specialist for manager','Draft assignment immutable') THEN RAISE; END IF;
 END;
 UPDATE jo_core.draft_tasks SET state='qa_pending',draft='Synthetic test only',provider_response_id='test_not_real' WHERE task_id=t;
 SELECT checkpoint_id INTO cp FROM gstack.draft_handoffs WHERE task_id=t;
 IF cp IS NULL OR NOT EXISTS(SELECT 1 FROM gstack.agent_memory_checkpoints WHERE checkpoint_id=cp AND verification_status='unverified' AND manager_key='jo') THEN RAISE EXCEPTION 'handoff missing'; END IF;
 BEGIN
 PERFORM gstack.promote_verified_checkpoint(cp,'jo','test-independent-reference');
 RAISE EXCEPTION 'unverified promotion accepted' USING ERRCODE='23514';
 EXCEPTION WHEN raise_exception THEN
 IF SQLERRM<>'checkpoint not eligible' THEN RAISE; END IF;
 END;
 IF has_function_privilege('anon','jo_core.reconcile_production_jobs()','execute') OR has_function_privilege('authenticated','gstack.bind_draft_agent()','execute') THEN RAISE EXCEPTION 'public execution'; END IF;
END $test$;
ROLLBACK;
SELECT 'PASS: assignment, cross-manager denial, unverified handoff, unverified promotion denial, private permissions; synthetic evidence rolled back' AS result;