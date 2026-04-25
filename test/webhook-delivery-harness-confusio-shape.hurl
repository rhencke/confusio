# Harness webhook delivery test — "confusio" shape variant — run by Phase 22 in test-unit.sh.
#
# When webhook_target_shape=confusio, the outbound delivery uses X-Confusio-* headers
# instead of X-GitHub-* headers.  This file spot-checks one event from each of the
# major event families to confirm the header switch happens correctly.

# ── pipeline_execution_started → workflow_run: in_progress — confusio shape ──

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
jsonpath "$[0].confusio_event" == "workflow_run"
jsonpath "$[0].confusio_source" == "harness"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""

# ── pipeline_execution_success → workflow_run: completed — confusio shape ─────

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
jsonpath "$[0].confusio_event" == "workflow_run"
jsonpath "$[0].confusio_source" == "harness"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""

# ── stage_execution_started → workflow_job: in_progress — confusio shape ──────

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
jsonpath "$[0].confusio_event" == "workflow_job"
jsonpath "$[0].confusio_source" == "harness"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""

# ── stage_execution_success → workflow_job: completed — confusio shape ────────

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
jsonpath "$[0].confusio_event" == "workflow_job"
jsonpath "$[0].confusio_source" == "harness"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
