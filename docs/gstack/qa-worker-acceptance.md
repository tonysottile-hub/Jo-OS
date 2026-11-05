# G Stack QA worker v2 — deployment contract

Deployed Supabase function: `gstack-qa-worker` in project `pubnivjjeofxqvmttuzh`.

The function requires a valid JWT **and** the exact service-role bearer token. It accepts only `POST` requests with `task=check_evidence_shape` and `job_ref` matching `gstack-qa-...`. It returns evidence shape checks but **never verifies evidence authenticity** and performs no writes.

## Controlled acceptance tests (owner-controlled environment)

1. Without authorization, `POST` must return 401/403.
2. With an ordinary authenticated user JWT, `POST` must return 401.
3. With the service-role credential, `GET` must report `writes_enabled=false` and `verification_enabled=false`.
4. With service-role credential, submit a synthetic `check_evidence_shape` request containing `source`, `observation`, `observed_at`, and `proof_ref`. Expect `shape_valid=true`, `verification_status=unverified`, and `writes_performed=false`.
5. Submit missing evidence; expect `shape_valid=false`. Submit unsupported task; expect 400.
6. Confirm `gstack.department_agents`, `gstack.agent_memory_checkpoints`, `gstack.memory_promotions`, and business publishing tables are unchanged.

Do not put service-role keys in GitHub, workflow logs, screenshots, or ChatGPT. Store credentials only in authorized secret storage. This function does **not** schedule or dispatch work, and a successful acceptance test must not be described as a working clone.

## Deployment note

The live function is v2. GitHub contains this operational contract, not the deployed source. Production activation requires an independent verifier, job dispatch, and end-to-end proof.
