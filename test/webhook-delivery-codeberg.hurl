# Codeberg webhook delivery tests — run by the Codeberg delivery phase in test-unit.sh.
#
# For every event × action triple supported by the Codeberg backend, this file:
#   1. Resets the mock delivery target log.
#   2. POSTs the fixture to /webhooks/codeberg with the appropriate X-Gitea-Event header.
#   3. Queries the delivery target and asserts exactly one delivery was recorded with
#      the correct github_event, a UUID delivery ID, and confusio in the User-Agent.
#
# Fixtures live in test/fixtures/webhooks/codeberg/ — one file per event × action.
# All assertions use the "github" delivery shape (default).

# ── issues: opened ────────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: issues
file,fixtures/webhooks/codeberg/issues-opened.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: issues
file,fixtures/webhooks/codeberg/issues-edited.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: issues
file,fixtures/webhooks/codeberg/issues-closed.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: issues
file,fixtures/webhooks/codeberg/issues-reopened.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: issues
file,fixtures/webhooks/codeberg/issues-labeled.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: issues
file,fixtures/webhooks/codeberg/issues-unlabeled.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: issues
file,fixtures/webhooks/codeberg/issues-assigned.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: issues
file,fixtures/webhooks/codeberg/issues-unassigned.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: issue_comment
file,fixtures/webhooks/codeberg/issue_comment-created.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: issue_comment
file,fixtures/webhooks/codeberg/issue_comment-edited.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: issue_comment
file,fixtures/webhooks/codeberg/issue_comment-deleted.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: label
file,fixtures/webhooks/codeberg/label-created.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: label
file,fixtures/webhooks/codeberg/label-edited.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: label
file,fixtures/webhooks/codeberg/label-deleted.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: milestone
file,fixtures/webhooks/codeberg/milestone-created.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: milestone
file,fixtures/webhooks/codeberg/milestone-closed.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: milestone
file,fixtures/webhooks/codeberg/milestone-reopened.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: milestone
file,fixtures/webhooks/codeberg/milestone-edited.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: milestone
file,fixtures/webhooks/codeberg/milestone-deleted.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: pull_request
file,fixtures/webhooks/codeberg/pull_request-opened.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: pull_request
file,fixtures/webhooks/codeberg/pull_request-closed.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: pull_request
file,fixtures/webhooks/codeberg/pull_request-reopened.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: pull_request
file,fixtures/webhooks/codeberg/pull_request-edited.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: pull_request
file,fixtures/webhooks/codeberg/pull_request-synchronize.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: pull_request
file,fixtures/webhooks/codeberg/pull_request-labeled.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: pull_request
file,fixtures/webhooks/codeberg/pull_request-unlabeled.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: pull_request
file,fixtures/webhooks/codeberg/pull_request-assigned.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: pull_request
file,fixtures/webhooks/codeberg/pull_request-unassigned.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: pull_request
file,fixtures/webhooks/codeberg/pull_request-review_requested.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: pull_request
file,fixtures/webhooks/codeberg/pull_request-review_request_removed.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: merge_group
file,fixtures/webhooks/codeberg/merge_group-checks_requested.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: merge_group
file,fixtures/webhooks/codeberg/merge_group-destroyed.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: pull_request_review
file,fixtures/webhooks/codeberg/pull_request_review-submitted.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: pull_request_review
file,fixtures/webhooks/codeberg/pull_request_review-edited.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: pull_request_review
file,fixtures/webhooks/codeberg/pull_request_review-dismissed.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: pull_request_review_comment
file,fixtures/webhooks/codeberg/pull_request_review_comment-created.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: pull_request_review_comment
file,fixtures/webhooks/codeberg/pull_request_review_comment-edited.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: pull_request_review_comment
file,fixtures/webhooks/codeberg/pull_request_review_comment-deleted.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: workflow_run
file,fixtures/webhooks/codeberg/workflow_run-requested.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: workflow_run
file,fixtures/webhooks/codeberg/workflow_run-in_progress.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: workflow_run
file,fixtures/webhooks/codeberg/workflow_run-completed.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: workflow_job
file,fixtures/webhooks/codeberg/workflow_job-queued.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: workflow_job
file,fixtures/webhooks/codeberg/workflow_job-in_progress.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: workflow_job
file,fixtures/webhooks/codeberg/workflow_job-completed.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: workflow_job
file,fixtures/webhooks/codeberg/workflow_job-waiting.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: status
file,fixtures/webhooks/codeberg/status-success.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: status
file,fixtures/webhooks/codeberg/status-pending.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: status
file,fixtures/webhooks/codeberg/status-failure.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: push
file,fixtures/webhooks/codeberg/push.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: create
file,fixtures/webhooks/codeberg/create.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: delete
file,fixtures/webhooks/codeberg/delete.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: fork
file,fixtures/webhooks/codeberg/fork.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: release
file,fixtures/webhooks/codeberg/release-published.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: release
file,fixtures/webhooks/codeberg/release-edited.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: release
file,fixtures/webhooks/codeberg/release-deleted.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: release
file,fixtures/webhooks/codeberg/release-prereleased.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: repository
file,fixtures/webhooks/codeberg/repository-created.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: repository
file,fixtures/webhooks/codeberg/repository-deleted.json;
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

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: repository
file,fixtures/webhooks/codeberg/repository-renamed.json;
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

# ── gollum: created ───────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: gollum
file,fixtures/webhooks/codeberg/gollum-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "gollum"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── gollum: edited ────────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: gollum
file,fixtures/webhooks/codeberg/gollum-edited.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "gollum"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── deploy_key: created ───────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: deploy_key
file,fixtures/webhooks/codeberg/deploy_key-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "deploy_key"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── deploy_key: deleted ───────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: deploy_key
file,fixtures/webhooks/codeberg/deploy_key-deleted.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "deploy_key"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── member: added ─────────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: collaborator
file,fixtures/webhooks/codeberg/member-added.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "member"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── member: removed ───────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: collaborator
file,fixtures/webhooks/codeberg/member-removed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "member"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── star: created ─────────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: star
file,fixtures/webhooks/codeberg/star-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "star"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── star: deleted ─────────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: star
file,fixtures/webhooks/codeberg/star-deleted.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "star"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── watch: started ────────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: watch
file,fixtures/webhooks/codeberg/watch-started.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "watch"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── discussion: created ───────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: discussion
file,fixtures/webhooks/codeberg/discussion-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "discussion"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── discussion: edited ────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: discussion
file,fixtures/webhooks/codeberg/discussion-edited.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "discussion"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── discussion: deleted ───────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: discussion
file,fixtures/webhooks/codeberg/discussion-deleted.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "discussion"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── discussion: closed ────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: discussion
file,fixtures/webhooks/codeberg/discussion-closed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "discussion"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── discussion: reopened ──────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: discussion
file,fixtures/webhooks/codeberg/discussion-reopened.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "discussion"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── discussion: labeled ───────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: discussion
file,fixtures/webhooks/codeberg/discussion-labeled.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "discussion"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── discussion: unlabeled ─────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: discussion
file,fixtures/webhooks/codeberg/discussion-unlabeled.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "discussion"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── discussion_comment: created ───────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: discussion_comment
file,fixtures/webhooks/codeberg/discussion_comment-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "discussion_comment"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── discussion_comment: edited ────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: discussion_comment
file,fixtures/webhooks/codeberg/discussion_comment-edited.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "discussion_comment"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── discussion_comment: deleted ───────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: discussion_comment
file,fixtures/webhooks/codeberg/discussion_comment-deleted.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "discussion_comment"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
# ── package: published ────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: package
file,fixtures/webhooks/codeberg/package-published.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "package"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── package: deleted ──────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: package
file,fixtures/webhooks/codeberg/package-deleted.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "package"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"

# ── ping: ping ────────────────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Event: ping
file,fixtures/webhooks/codeberg/ping.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "ping"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
