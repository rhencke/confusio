# Azure DevOps webhook delivery test — "confusio" shape variant — run by Phase 16 in test-unit.sh.
#
# When webhook_target_shape=confusio, the outbound delivery uses X-Confusio-* headers
# instead of X-GitHub-* headers.  This file spot-checks one event from each of the
# major event families to confirm the header switch happens correctly.

# ── workitem.created → issues: opened — confusio shape ───────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/workitem.created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "issues"
jsonpath "$[0].confusio_source" == "azuredevops"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""

# ── workitem.commented → issue_comment: created — confusio shape ──────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/workitem.commented.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "issue_comment"
jsonpath "$[0].confusio_source" == "azuredevops"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""

# ── git.pullrequest.created → pull_request: opened — confusio shape ──────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/git.pullrequest.created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "azuredevops"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""

# ── git.pullrequest.reviewervote → pull_request_review — confusio shape ───────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/git.pullrequest.reviewervote-approved.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "pull_request_review"
jsonpath "$[0].confusio_source" == "azuredevops"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""

# ── build.complete → workflow_run — confusio shape ────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/build.complete-success.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "workflow_run"
jsonpath "$[0].confusio_source" == "azuredevops"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""

# ── git.push → push — confusio shape ─────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/git.push-push.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "push"
jsonpath "$[0].confusio_source" == "azuredevops"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
