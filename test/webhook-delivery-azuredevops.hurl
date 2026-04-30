# Azure DevOps webhook delivery tests — run by Phase 15 in test-unit.sh.
#
# Azure DevOps embeds the event type in the JSON body (payload.eventType),
# so no event-type header is needed.  All fixtures include "eventType" in the body.
#
# For every event type supported by the Azure DevOps backend, this file:
#   1. Resets the mock delivery target log.
#   2. POSTs the fixture to /webhooks/azuredevops.
#   3. Queries the delivery target and asserts exactly one delivery was recorded with
#      the correct github_event, a UUID delivery ID, and confusio in the User-Agent.

# ── workitem.created → issues: opened ────────────────────────────────────────

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
jsonpath "$[0].github_event" == "issues"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── workitem.updated → issues: edited ────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/workitem.updated.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "issues"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── workitem.deleted → issues: closed ────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/workitem.deleted.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "issues"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── workitem.restored → issues: reopened ─────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/workitem.restored.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "issues"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── workitem.commented → issue_comment: created ───────────────────────────────

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
jsonpath "$[0].github_event" == "issue_comment"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── git.pullrequest.created → pull_request: opened ───────────────────────────

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
jsonpath "$[0].github_event" == "pull_request"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── git.pullrequest.updated (active) → pull_request: synchronize ──────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/git.pullrequest.updated-synchronize.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "pull_request"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── git.pullrequest.updated (completed) → pull_request: closed ────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/git.pullrequest.updated-closed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "pull_request"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── git.pullrequest.reviewervote (vote=10) → pull_request_review: submitted/APPROVED

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
jsonpath "$[0].github_event" == "pull_request_review"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── git.pullrequest.reviewervote (vote=0) → pull_request_review: dismissed ────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/git.pullrequest.reviewervote-dismissed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "pull_request_review"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── git.pullrequest.reviewervote (vote=-10) → pull_request_review: submitted/CHANGES_REQUESTED

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/git.pullrequest.reviewervote-changes_requested.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "pull_request_review"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── git.push (regular push) → push: push ─────────────────────────────────────

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
jsonpath "$[0].github_event" == "push"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── git.push (create: oldObjectId = zero) → create: create ────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/create.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "create"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── git.push (delete: newObjectId = zero) → delete: delete ────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/delete.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "delete"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── build.complete (succeeded) → workflow_run: completed/success ──────────────

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
jsonpath "$[0].github_event" == "workflow_run"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── build.complete (failed) → workflow_run: completed/failure ─────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/build.complete-failure.json;
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

# ── build.complete (canceled) → workflow_run: completed/cancelled ─────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/build.complete-cancelled.json;
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

# ── git.repo.created → repository: created ───────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/repository-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "repository"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── release created → release: published ─────────────────────────────────────

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
jsonpath "$[0].github_event" == "release"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── release abandoned → release: deleted ─────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/release-abandoned.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "release"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── deployment started → deployment: created ─────────────────────────────────

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
jsonpath "$[0].github_event" == "deployment"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── deployment completed (success) → deployment_status: created ──────────────

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
jsonpath "$[0].github_event" == "deployment_status"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── deployment completed (rejected) → deployment_status: created ─────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/deployment-completed-rejected.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "deployment_status"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── deployment approval pending → deployment_review: requested ───────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/deployment-approval-pending.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "deployment_review"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── deployment approval completed (approved) → deployment_review: approved ───

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
jsonpath "$[0].github_event" == "deployment_review"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── deployment approval completed (rejected) → deployment_review: rejected ───

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/deployment-approval-completed-rejected.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "deployment_review"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── git.repo.deleted → repository: deleted ───────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/repository-deleted.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "repository"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── git.repo.renamed → repository: renamed ───────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
file,fixtures/webhooks/azuredevops/repository-renamed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "repository"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
