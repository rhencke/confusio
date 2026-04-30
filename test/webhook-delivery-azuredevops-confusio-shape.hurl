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
jsonpath "$[0].body_json.id" isString
jsonpath "$[0].body_json.type" == "issue.opened"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:00:00Z"
jsonpath "$[0].body_json.actor.login" == "alice@example.com"
jsonpath "$[0].body_json.payload.action" == "opened"
jsonpath "$[0].body_json.payload.issue.number" == 1

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
jsonpath "$[0].body_json.type" == "issue.comment.created"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T12:00:00Z"
jsonpath "$[0].body_json.actor.login" == "bob@example.com"
jsonpath "$[0].body_json.payload.issue.number" == 1
jsonpath "$[0].body_json.payload.comment.body" == "This is a comment on the work item"

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
jsonpath "$[0].body_json.type" == "pull_request.opened"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:00:00Z"
jsonpath "$[0].body_json.actor.login" == "alice@example.com"
jsonpath "$[0].body_json.repository.full_name" == "myproject/my-repo"
jsonpath "$[0].body_json.payload.pull_request.number" == 42

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
jsonpath "$[0].body_json.type" == "pull_request.review.submitted"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T11:00:00Z"
jsonpath "$[0].body_json.actor.login" == "bob@example.com"
jsonpath "$[0].body_json.repository.full_name" == "myproject/my-repo"
jsonpath "$[0].body_json.payload.review.state" == "APPROVED"

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
jsonpath "$[0].body_json.type" == "workflow.run.completed"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:10:00Z"
jsonpath "$[0].body_json.payload.workflow_run.name" == "CI Pipeline"
jsonpath "$[0].body_json.payload.workflow_run.conclusion" == "success"
jsonpath "$[0].body_json.payload.workflow_run.head_sha" == "abc123def456"

# ── git.push → push — confusio shape ─────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/git.push.json;
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
jsonpath "$[0].body_json.type" == "push"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:00:00Z"
jsonpath "$[0].body_json.actor.login" == "bob@example.com"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.after" == "f1d2d2f924e986ac86fdf7b36c94bcdf32beec15"

# ── release created → release — confusio shape ───────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/release-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "release"
jsonpath "$[0].confusio_source" == "azuredevops"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "release.published"
jsonpath "$[0].body_json.payload.release.name" == "Release-1"

# ── deployment started → deployment — confusio shape ─────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/deployment-started.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "deployment"
jsonpath "$[0].confusio_source" == "azuredevops"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "deployment.created"
jsonpath "$[0].body_json.payload.deployment.environment" == "Production"

# ── deployment completed → deployment_status — confusio shape ────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/deployment-completed-success.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "deployment_status"
jsonpath "$[0].confusio_source" == "azuredevops"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "deployment.status.created"
jsonpath "$[0].body_json.payload.deployment_status.state" == "success"

# ── deployment approval completed → deployment_review — confusio shape ───────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/deployment-approval-completed-approved.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "deployment_review"
jsonpath "$[0].confusio_source" == "azuredevops"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "deployment.review.approved"
jsonpath "$[0].body_json.payload.approver.login" == "alice@example.com"

# ── Advanced Security code alert created → code_scanning_alert — confusio shape

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/advsec-code-alert-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "code_scanning_alert"
jsonpath "$[0].confusio_source" == "azuredevops"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "code_scanning_alert.created"
jsonpath "$[0].body_json.payload.alert.number" == 101

# ── Advanced Security dependency state changed → dependabot_alert — confusio shape

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/advsec-dependency-alert-state-changed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "dependabot_alert"
jsonpath "$[0].confusio_source" == "azuredevops"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "dependabot_alert.dismissed"
jsonpath "$[0].body_json.payload.alert.dependency.package.name" == "lodash"

# ── Advanced Security secret alert updated → secret_scanning_alert — confusio shape

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/advsec-secret-alert-updated.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "secret_scanning_alert"
jsonpath "$[0].confusio_source" == "azuredevops"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "secret_scanning_alert.validated"
jsonpath "$[0].body_json.payload.alert.secret_type" == "github_personal_access_token"
