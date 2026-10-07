# Jo OS Browser Worker Sandbox

NON-PRODUCTION prototype. No production credentials.

Acceptance:
1. permitted navigation succeeds
2. page instructions cannot expand authority
3. unauthorized destinations are denied by host policy
4. downloads/uploads/local file access default deny
5. bounded attempts and timeout
6. executor cannot self-certify completion
7. verifier independently checks expected result
8. evidence is emitted as structured JSON

Authority: READ_ONLY, PREPARE, EXECUTE, OWNER_ONLY.
Prototype permits READ_ONLY only.


<!-- acceptance-trigger: qwen4b-text-only -->
