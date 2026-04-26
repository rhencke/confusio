# Bitbucket Cloud webhook delivery tests — run by Phase 11 in test-unit.sh.
#
# For every event × action triple supported by the Bitbucket Cloud backend, this file:
#   1. Resets the mock delivery target log.
#   2. POSTs the fixture to /webhooks/bitbucket with the appropriate X-Event-Key header.
#   3. Queries the delivery target and asserts exactly one delivery was recorded with
#      the correct github_event, a UUID delivery ID, and confusio in the User-Agent.
#
# Fixtures live in test/fixtures/webhooks/bitbucket/ — one file per event × action.
# All assertions use the "github" delivery shape (default).
#
# Bitbucket Cloud uses the X-Event-Key header for event type identification.

# ── issues: opened ────────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: issue:created
file,fixtures/webhooks/bitbucket/issues-opened.json;
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

# ── issues: edited ────────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: issue:updated
file,fixtures/webhooks/bitbucket/issues-edited.json;
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

# ── issues: closed ────────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: issue:updated
file,fixtures/webhooks/bitbucket/issues-closed.json;
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

# ── issues: reopened ──────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: issue:updated
file,fixtures/webhooks/bitbucket/issues-reopened.json;
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

# ── issue_comment: created ────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: issue:comment_created
file,fixtures/webhooks/bitbucket/issue_comment-created.json;
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

# ── pull_request: opened ──────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: pullrequest:created
file,fixtures/webhooks/bitbucket/pull_request-opened.json;
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

# ── pull_request: synchronize ─────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: pullrequest:updated
file,fixtures/webhooks/bitbucket/pull_request-synchronize.json;
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

# ── pull_request: closed (merged) ─────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: pullrequest:fulfilled
file,fixtures/webhooks/bitbucket/pull_request-closed-merged.json;
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

# ── pull_request: closed (declined) ───────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: pullrequest:rejected
file,fixtures/webhooks/bitbucket/pull_request-closed-declined.json;
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

# ── pull_request_review: submitted (approved) ─────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: pullrequest:approved
file,fixtures/webhooks/bitbucket/pull_request_review-submitted-approved.json;
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

# ── pull_request_review: dismissed ────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: pullrequest:unapproved
file,fixtures/webhooks/bitbucket/pull_request_review-dismissed.json;
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

# ── status: success (commit_status_created) ───────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: repo:commit_status_created
file,fixtures/webhooks/bitbucket/status-created-success.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "status"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── status: pending (commit_status_updated) ───────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: repo:commit_status_updated
file,fixtures/webhooks/bitbucket/status-updated-pending.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "status"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── push: push ────────────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: repo:push
file,fixtures/webhooks/bitbucket/push.json;
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

# ── create: create (branch creation via repo:push with created=true) ──────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: repo:push
file,fixtures/webhooks/bitbucket/create.json;
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

# ── delete: delete (branch deletion via repo:push with closed=true) ───────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: repo:push
file,fixtures/webhooks/bitbucket/delete.json;
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

# ── fork: fork ────────────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: repo:fork
file,fixtures/webhooks/bitbucket/fork.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "fork"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
