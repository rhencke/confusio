# Gitea webhook delivery tests — run by Phase 7 in test-unit.sh.
#
# For every event × action triple supported by the Gitea backend, this file:
#   1. Resets the mock delivery target log.
#   2. POSTs the fixture to /webhooks/gitea with the appropriate X-Gitea-Event header.
#   3. Queries the delivery target and asserts exactly one delivery was recorded with
#      the correct github_event, a UUID delivery ID, and confusio in the User-Agent.
#
# Fixtures live in test/fixtures/webhooks/gitea/ — one file per event × action.
# All assertions use the "github" delivery shape (default).

# ── issues: opened ────────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: issues
file,fixtures/webhooks/gitea/issues-opened.json;
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

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: issues
file,fixtures/webhooks/gitea/issues-edited.json;
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

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: issues
file,fixtures/webhooks/gitea/issues-closed.json;
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

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: issues
file,fixtures/webhooks/gitea/issues-reopened.json;
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

# ── issues: labeled ───────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: issues
file,fixtures/webhooks/gitea/issues-labeled.json;
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

# ── issues: unlabeled ─────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: issues
file,fixtures/webhooks/gitea/issues-unlabeled.json;
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

# ── issues: assigned ──────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: issues
file,fixtures/webhooks/gitea/issues-assigned.json;
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

# ── issues: unassigned ────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: issues
file,fixtures/webhooks/gitea/issues-unassigned.json;
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

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: issue_comment
file,fixtures/webhooks/gitea/issue_comment-created.json;
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

# ── issue_comment: edited ─────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: issue_comment
file,fixtures/webhooks/gitea/issue_comment-edited.json;
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

# ── issue_comment: deleted ────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: issue_comment
file,fixtures/webhooks/gitea/issue_comment-deleted.json;
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

# ── label: created ────────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: label
file,fixtures/webhooks/gitea/label-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "label"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── label: edited ─────────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: label
file,fixtures/webhooks/gitea/label-edited.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "label"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── label: deleted ────────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: label
file,fixtures/webhooks/gitea/label-deleted.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "label"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── milestone: created ────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: milestone
file,fixtures/webhooks/gitea/milestone-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "milestone"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── milestone: closed ─────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: milestone
file,fixtures/webhooks/gitea/milestone-closed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "milestone"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── milestone: reopened ───────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: milestone
file,fixtures/webhooks/gitea/milestone-reopened.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "milestone"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── milestone: edited ─────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: milestone
file,fixtures/webhooks/gitea/milestone-edited.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "milestone"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── milestone: deleted ────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: milestone
file,fixtures/webhooks/gitea/milestone-deleted.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "milestone"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── pull_request: opened ──────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request
file,fixtures/webhooks/gitea/pull_request-opened.json;
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

# ── pull_request: closed ──────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request
file,fixtures/webhooks/gitea/pull_request-closed.json;
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

# ── pull_request: reopened ────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request
file,fixtures/webhooks/gitea/pull_request-reopened.json;
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

# ── pull_request: edited ──────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request
file,fixtures/webhooks/gitea/pull_request-edited.json;
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

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request
file,fixtures/webhooks/gitea/pull_request-synchronize.json;
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

# ── pull_request: labeled ─────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request
file,fixtures/webhooks/gitea/pull_request-labeled.json;
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

# ── pull_request: unlabeled ───────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request
file,fixtures/webhooks/gitea/pull_request-unlabeled.json;
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

# ── pull_request: assigned ────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request
file,fixtures/webhooks/gitea/pull_request-assigned.json;
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

# ── pull_request: unassigned ──────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request
file,fixtures/webhooks/gitea/pull_request-unassigned.json;
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

# ── pull_request: review_requested ────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request
file,fixtures/webhooks/gitea/pull_request-review_requested.json;
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

# ── pull_request: review_request_removed ──────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request
file,fixtures/webhooks/gitea/pull_request-review_request_removed.json;
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

# ── merge_group: checks_requested ─────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: merge_group
file,fixtures/webhooks/gitea/merge_group-checks_requested.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "merge_group"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── merge_group: destroyed ────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: merge_group
file,fixtures/webhooks/gitea/merge_group-destroyed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "merge_group"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── pull_request_review: submitted ────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request_review
file,fixtures/webhooks/gitea/pull_request_review-submitted.json;
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

# ── pull_request_review: edited ───────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request_review
file,fixtures/webhooks/gitea/pull_request_review-edited.json;
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

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request_review
file,fixtures/webhooks/gitea/pull_request_review-dismissed.json;
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

# ── pull_request_review_comment: created ──────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request_review_comment
file,fixtures/webhooks/gitea/pull_request_review_comment-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "pull_request_review_comment"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── pull_request_review_comment: edited ───────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request_review_comment
file,fixtures/webhooks/gitea/pull_request_review_comment-edited.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "pull_request_review_comment"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── pull_request_review_comment: deleted ──────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request_review_comment
file,fixtures/webhooks/gitea/pull_request_review_comment-deleted.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "pull_request_review_comment"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── workflow_run: requested ───────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: workflow_run
file,fixtures/webhooks/gitea/workflow_run-requested.json;
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

# ── workflow_run: in_progress ─────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: workflow_run
file,fixtures/webhooks/gitea/workflow_run-in_progress.json;
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

# ── workflow_run: completed ───────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: workflow_run
file,fixtures/webhooks/gitea/workflow_run-completed.json;
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

# ── workflow_job: queued ──────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: workflow_job
file,fixtures/webhooks/gitea/workflow_job-queued.json;
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

# ── workflow_job: in_progress ─────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: workflow_job
file,fixtures/webhooks/gitea/workflow_job-in_progress.json;
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

# ── workflow_job: completed ───────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: workflow_job
file,fixtures/webhooks/gitea/workflow_job-completed.json;
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

# ── workflow_job: waiting ─────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: workflow_job
file,fixtures/webhooks/gitea/workflow_job-waiting.json;
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

# ── status: success ───────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: status
file,fixtures/webhooks/gitea/status-success.json;
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

# ── status: pending ───────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: status
file,fixtures/webhooks/gitea/status-pending.json;
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

# ── status: failure ───────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: status
file,fixtures/webhooks/gitea/status-failure.json;
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

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: push
file,fixtures/webhooks/gitea/push.json;
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

# ── create: create ────────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: create
file,fixtures/webhooks/gitea/create.json;
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

# ── delete: delete ────────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: delete
file,fixtures/webhooks/gitea/delete.json;
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

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: fork
file,fixtures/webhooks/gitea/fork.json;
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

# ── release: published ────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: release
file,fixtures/webhooks/gitea/release-published.json;
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

# ── release: edited ───────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: release
file,fixtures/webhooks/gitea/release-edited.json;
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

# ── release: deleted ──────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: release
file,fixtures/webhooks/gitea/release-deleted.json;
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

# ── release: prereleased ──────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: release
file,fixtures/webhooks/gitea/release-prereleased.json;
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

# ── repository: created ───────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: repository
file,fixtures/webhooks/gitea/repository-created.json;
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

# ── repository: deleted ───────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: repository
file,fixtures/webhooks/gitea/repository-deleted.json;
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

# ── repository: renamed ───────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: repository
file,fixtures/webhooks/gitea/repository-renamed.json;
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
