# Harness CI webhook normalizer tests — run by test-unit-harness.
#
# Harness CI embeds eventType in the JSON body (no event-type header).
# Trust-the-network mode (no CONFUSIO_WEBHOOK_SECRETS): X-Harness-Token omitted.
# Pipeline execution events → workflow_run.
# Stage execution events    → workflow_job.

# ── pipeline_execution_started → workflow_run / in_progress ──────────────────

POST http://{{host}}/webhooks/harness
Content-Type: application/json
{
  "eventType": "pipeline_execution_started",
  "accountId": "accountId",
  "orgIdentifier": "myOrg",
  "projectIdentifier": "myProject",
  "pipelineIdentifier": "CI_Pipeline",
  "planExecutionId": "exec-abc123",
  "runSequence": 1,
  "status": "Running",
  "startTs": 1705316400000,
  "triggerType": "WEBHOOK",
  "triggeredBy": {"name": "Alice", "email": "alice@example.com"},
  "moduleInfo": {"ci": {"branch": "main", "repoName": "hello-world", "commitSha": "abc123def456"}}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pipeline_execution_success → workflow_run / completed / success ───────────

POST http://{{host}}/webhooks/harness
Content-Type: application/json
{
  "eventType": "pipeline_execution_success",
  "accountId": "accountId",
  "orgIdentifier": "myOrg",
  "projectIdentifier": "myProject",
  "pipelineIdentifier": "CI_Pipeline",
  "planExecutionId": "exec-abc123",
  "runSequence": 1,
  "status": "Success",
  "startTs": 1705316400000,
  "endTs": 1705316700000,
  "triggerType": "WEBHOOK",
  "triggeredBy": {"name": "Alice", "email": "alice@example.com"},
  "moduleInfo": {"ci": {"branch": "main", "repoName": "hello-world", "commitSha": "abc123def456"}}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pipeline_execution_failed → workflow_run / completed / failure ────────────

POST http://{{host}}/webhooks/harness
Content-Type: application/json
{
  "eventType": "pipeline_execution_failed",
  "accountId": "accountId",
  "orgIdentifier": "myOrg",
  "projectIdentifier": "myProject",
  "pipelineIdentifier": "CI_Pipeline",
  "planExecutionId": "exec-def456",
  "runSequence": 2,
  "status": "Failed",
  "startTs": 1705320000000,
  "endTs": 1705320180000,
  "triggerType": "WEBHOOK",
  "triggeredBy": {"name": "Bob", "email": "bob@example.com"},
  "moduleInfo": {"ci": {"branch": "feature", "repoName": "hello-world", "commitSha": "deadbeef"}}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pipeline_execution_aborted → workflow_run / completed / cancelled ─────────

POST http://{{host}}/webhooks/harness
Content-Type: application/json
{
  "eventType": "pipeline_execution_aborted",
  "accountId": "accountId",
  "orgIdentifier": "myOrg",
  "projectIdentifier": "myProject",
  "pipelineIdentifier": "Deploy_Pipeline",
  "planExecutionId": "exec-ghi789",
  "runSequence": 3,
  "status": "Aborted",
  "startTs": 1705323600000,
  "endTs": 1705323660000,
  "triggerType": "MANUAL",
  "triggeredBy": {"name": "Alice", "email": "alice@example.com"},
  "moduleInfo": {"ci": {"branch": "main", "repoName": "hello-world"}}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── stage_execution_started → workflow_job / in_progress ─────────────────────

POST http://{{host}}/webhooks/harness
Content-Type: application/json
{
  "eventType": "stage_execution_started",
  "accountId": "accountId",
  "orgIdentifier": "myOrg",
  "projectIdentifier": "myProject",
  "pipelineIdentifier": "CI_Pipeline",
  "stageIdentifier": "build_stage",
  "stageName": "Build",
  "planExecutionId": "exec-abc123",
  "status": "Running",
  "startTs": 1705316410000,
  "triggeredBy": {"name": "Alice", "email": "alice@example.com"}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── stage_execution_success → workflow_job / completed / success ──────────────

POST http://{{host}}/webhooks/harness
Content-Type: application/json
{
  "eventType": "stage_execution_success",
  "accountId": "accountId",
  "orgIdentifier": "myOrg",
  "projectIdentifier": "myProject",
  "pipelineIdentifier": "CI_Pipeline",
  "stageIdentifier": "build_stage",
  "stageName": "Build",
  "planExecutionId": "exec-abc123",
  "status": "Success",
  "startTs": 1705316410000,
  "endTs": 1705316680000,
  "triggeredBy": {"name": "Alice", "email": "alice@example.com"}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── stage_execution_failed → workflow_job / completed / failure ───────────────

POST http://{{host}}/webhooks/harness
Content-Type: application/json
{
  "eventType": "stage_execution_failed",
  "accountId": "accountId",
  "orgIdentifier": "myOrg",
  "projectIdentifier": "myProject",
  "pipelineIdentifier": "CI_Pipeline",
  "stageIdentifier": "test_stage",
  "stageName": "Test",
  "planExecutionId": "exec-def456",
  "status": "Failed",
  "startTs": 1705320010000,
  "endTs": 1705320170000,
  "triggeredBy": {"name": "Bob", "email": "bob@example.com"}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── stage_execution_aborted → workflow_job / completed / cancelled ────────────

POST http://{{host}}/webhooks/harness
Content-Type: application/json
{
  "eventType": "stage_execution_aborted",
  "accountId": "accountId",
  "orgIdentifier": "myOrg",
  "projectIdentifier": "myProject",
  "pipelineIdentifier": "Deploy_Pipeline",
  "stageIdentifier": "deploy_stage",
  "stageName": "Deploy",
  "planExecutionId": "exec-ghi789",
  "status": "Aborted",
  "startTs": 1705323610000,
  "endTs": 1705323650000,
  "triggeredBy": {"name": "Alice", "email": "alice@example.com"}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"
