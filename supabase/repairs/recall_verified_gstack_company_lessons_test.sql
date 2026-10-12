BEGIN;
DO $test$
DECLARE aid uuid; cp uuid; privatecp uuid; key text; w text; returned jsonb;
BEGIN
 INSERT INTO gstack.templates(template_id,version,approved,source_ref)
 VALUES('transactional-memory-test','1',true,'test-only; rollback; not production approval');
 aid:=gstack.provision_department_agent('transaction-memory-provision','transactional-memory-test','1','jo');
 cp:=gstack.submit_agent_checkpoint(aid,'jo','test:memory','Memorybridgecanary verified company lesson','test:evidence:public','company_candidate');
 privatecp:=gstack.submit_agent_checkpoint(aid,'jo','test:private','Memorybridgecanary private department lesson','test:evidence:private','department');
 IF jsonb_array_length(jo_core.recall('tom','Memorybridgecanary',50))<>0 THEN RAISE EXCEPTION 'Unverified/private claim leaked'; END IF;
 PERFORM gstack.verify_agent_checkpoint(cp,'jo','test:evidence:public','test:independent-verification:public');
 key:=gstack.promote_verified_checkpoint(cp,'jo','test:independent-verification:public');
 FOREACH w IN ARRAY ARRAY['jo','tom','mary','steve','jeff'] LOOP
  returned:=jo_core.recall(w,'Memorybridgecanary',50);
  IF jsonb_array_length(returned)<>1 OR returned->0->>'memory_key'<>key THEN RAISE EXCEPTION 'Promoted lesson not recalled by %',w; END IF;
 END LOOP;
 UPDATE jo_core.shared_knowledge SET content='Tampered Memorybridgecanary lesson' WHERE memory_key=key;
 IF jsonb_array_length(jo_core.recall('tom','Memorybridgecanary',50))<>0 THEN RAISE EXCEPTION 'Changed claim passed provenance check'; END IF;
 UPDATE jo_core.shared_knowledge SET content='Memorybridgecanary verified company lesson',status='superseded' WHERE memory_key=key;
 IF jsonb_array_length(jo_core.recall('tom','Memorybridgecanary',50))<>0 THEN RAISE EXCEPTION 'Superseded lesson remains visible'; END IF;
 IF jsonb_array_length(jo_core.recall('unknown','',50))<>0 THEN RAISE EXCEPTION 'Unknown worker allowed'; END IF;
END $test$;
ROLLBACK;