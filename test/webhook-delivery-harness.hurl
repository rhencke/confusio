# Harness webhook delivery tests — run by Phase 21 in test-unit.sh.
#
# Harness embeds the event type in the JSON body (payload.eventType),
# so no event-type header is needed.  All fixtures include "eventType" in the body.
#
# For every event type supported by the Harness backend, this file:
#   1. Resets the mock delivery target log.
#   2. POSTs the fixture to /webhooks/harness.
#   3. Queries the delivery target and asserts exactly one delivery was recorded with
#      the correct github_event, a UUID delivery ID, and confusio in the User-Agent.

# ── pipeline_execution_started → workflow_run: in_progress ───────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/harness
Content-Type: application/json
file,fixtures/webhooks/harness/pipeline_execution_started.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "workflow_run"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.action" == "in_progress"
jsonpath "$[0].body_json.workflow_run.name" == "my-pipeline"
jsonpath "$[0].body_json.workflow_run.status" == "in_progress"
jsonpath "$[0].body_json.workflow_run.head_branch" == "main"
jsonpath "$[0].body_json.workflow_run.head_sha" == "abc123def456"
jsonpath "$[0].body_json.repository.full_name" == "myorg/my-repo"

# ── pipeline_execution_success → workflow_run: completed/success ──────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/harness
Content-Type: application/json
file,fixtures/webhooks/harness/pipeline_execution_success.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "workflow_run"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.action" == "completed"
jsonpath "$[0].body_json.workflow_run.status" == "completed"
jsonpath "$[0].body_json.workflow_run.conclusion" == "success"
jsonpath "$[0].body_json.workflow_run.run_number" == 1

# ── pipeline_execution_failed → workflow_run: completed/failure ───────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/harness
Content-Type: application/json
file,fixtures/webhooks/harness/pipeline_execution_failed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "workflow_run"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.action" == "completed"
jsonpath "$[0].body_json.workflow_run.status" == "completed"
jsonpath "$[0].body_json.workflow_run.conclusion" == "failure"
jsonpath "$[0].body_json.workflow_run.head_branch" == "feature-branch"

# ── pipeline_execution_aborted → workflow_run: completed/cancelled ────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/harness
Content-Type: application/json
file,fixtures/webhooks/harness/pipeline_execution_aborted.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "workflow_run"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.action" == "completed"
jsonpath "$[0].body_json.workflow_run.status" == "completed"
jsonpath "$[0].body_json.workflow_run.conclusion" == "cancelled"
jsonpath "$[0].body_json.workflow_run.head_sha" == "ddd444eee555"

# ── stage_execution_started → workflow_job: in_progress ──────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/harness
Content-Type: application/json
file,fixtures/webhooks/harness/stage_execution_started.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "workflow_job"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.action" == "in_progress"
jsonpath "$[0].body_json.workflow_job.name" == "Build Stage"
jsonpath "$[0].body_json.workflow_job.status" == "in_progress"
jsonpath "$[0].body_json.repository.full_name" == "myorg/my-repo"

# ── stage_execution_success → workflow_job: completed/success ────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/harness
Content-Type: application/json
file,fixtures/webhooks/harness/stage_execution_success.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "workflow_job"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.action" == "completed"
jsonpath "$[0].body_json.workflow_job.name" == "Build Stage"
jsonpath "$[0].body_json.workflow_job.status" == "completed"
jsonpath "$[0].body_json.workflow_job.conclusion" == "success"

# ── stage_execution_failed → workflow_job: completed/failure ─────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/harness
Content-Type: application/json
file,fixtures/webhooks/harness/stage_execution_failed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "workflow_job"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.action" == "completed"
jsonpath "$[0].body_json.workflow_job.name" == "Test Stage"
jsonpath "$[0].body_json.workflow_job.status" == "completed"
jsonpath "$[0].body_json.workflow_job.conclusion" == "failure"

# ── stage_execution_aborted → workflow_job: completed/cancelled ───────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/harness
Content-Type: application/json
file,fixtures/webhooks/harness/stage_execution_aborted.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "workflow_job"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.action" == "completed"
jsonpath "$[0].body_json.workflow_job.name" == "Deploy Stage"
jsonpath "$[0].body_json.workflow_job.status" == "completed"
jsonpath "$[0].body_json.workflow_job.conclusion" == "cancelled"
