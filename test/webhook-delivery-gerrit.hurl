# Gerrit webhook delivery tests — run by Phase 17 in test-unit.sh.
#
# Gerrit embeds the event type in the JSON body (payload.type),
# so no event-type header is needed.  All fixtures include "type" in the body.
#
# For every event type supported by the Gerrit backend, this file:
#   1. Resets the mock delivery target log.
#   2. POSTs the fixture to /webhooks/gerrit.
#   3. Queries the delivery target and asserts exactly one delivery was recorded with
#      the correct github_event, a UUID delivery ID, and confusio in the User-Agent.

# ── comment-added (approved) → pull_request_review: submitted/APPROVED ────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
file,fixtures/webhooks/gerrit/comment-added-approved.json;
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
jsonpath "$[0].body_json.action" == "submitted"
jsonpath "$[0].body_json.review.state" == "APPROVED"
jsonpath "$[0].body_json.pull_request.number" == 1001

# ── reviewer-added → pull_request: review_requested ─────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
file,fixtures/webhooks/gerrit/reviewer-added.json;
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
jsonpath "$[0].body_json.action" == "review_requested"
jsonpath "$[0].body_json.requested_reviewer.login" == "nina"
jsonpath "$[0].body_json.pull_request.number" == 1004

# ── reviewer-deleted → pull_request: review_request_removed ─────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
file,fixtures/webhooks/gerrit/reviewer-deleted.json;
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
jsonpath "$[0].body_json.action" == "review_request_removed"
jsonpath "$[0].body_json.requested_reviewer.login" == "nina"

# ── vote-deleted → pull_request_review: dismissed ───────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
file,fixtures/webhooks/gerrit/vote-deleted.json;
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
jsonpath "$[0].body_json.action" == "dismissed"
jsonpath "$[0].body_json.review.state" == "DISMISSED"

# ── ref-updated → push ──────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
file,fixtures/webhooks/gerrit/ref-updated-push.json;
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
jsonpath "$[0].body_json.ref" == "refs/heads/main"
jsonpath "$[0].body_json.before" == "1111111111111111111111111111111111111111"
jsonpath "$[0].body_json.after" == "2222222222222222222222222222222222222222"

# ── ref-updated → create ────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
file,fixtures/webhooks/gerrit/ref-updated-create.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "create"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "feature/ref-map"
jsonpath "$[0].body_json.ref_type" == "branch"

# ── ref-updated → delete ────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
file,fixtures/webhooks/gerrit/ref-updated-delete.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "delete"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "v1.0.0"
jsonpath "$[0].body_json.ref_type" == "tag"

# ── batch-ref-updated → push ────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
file,fixtures/webhooks/gerrit/batch-ref-updated.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "push"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "refs/heads/release"

# ── project-created → repository: created ──────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
file,fixtures/webhooks/gerrit/project-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "repository"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "created"
jsonpath "$[0].body_json.repository.full_name" == "myorg/new-repo"

# ── project-deleted → repository: deleted ──────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
file,fixtures/webhooks/gerrit/project-deleted.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "repository"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "deleted"
jsonpath "$[0].body_json.repository.full_name" == "myorg/old-repo"

# ── project-head-updated → repository: edited ──────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
file,fixtures/webhooks/gerrit/project-head-updated.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "repository"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "edited"
jsonpath "$[0].body_json.changes.repository.default_branch.from" == "master"
jsonpath "$[0].body_json.repository.full_name" == "myorg/my-repo"

# ── patchset-created (first patch set) → pull_request: opened ───────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
file,fixtures/webhooks/gerrit/patchset-created-opened.json;
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
jsonpath "$[0].body_json.action" == "opened"
jsonpath "$[0].body_json.pull_request.number" == 1002

# ── patchset-created (later patch set) → pull_request: synchronize ──────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
file,fixtures/webhooks/gerrit/patchset-created-synchronize.json;
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
jsonpath "$[0].body_json.action" == "synchronize"
jsonpath "$[0].body_json.pull_request.head.sha" == "333ccc444ddd"

# ── change-merged → pull_request: closed / merged ───────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
file,fixtures/webhooks/gerrit/change-merged.json;
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
jsonpath "$[0].body_json.action" == "closed"
jsonpath "$[0].body_json.pull_request.merged" == true

# ── change-abandoned → pull_request: closed / not merged ────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
file,fixtures/webhooks/gerrit/change-abandoned.json;
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
jsonpath "$[0].body_json.action" == "closed"
jsonpath "$[0].body_json.pull_request.merged" == false

# ── change-restored → pull_request: reopened ────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
file,fixtures/webhooks/gerrit/change-restored.json;
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
jsonpath "$[0].body_json.action" == "reopened"
jsonpath "$[0].body_json.pull_request.state" == "open"

# ── topic-changed → pull_request: edited ────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
file,fixtures/webhooks/gerrit/topic-changed.json;
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
jsonpath "$[0].body_json.action" == "edited"
jsonpath "$[0].body_json.changes.topic.to" == "checkout-v2"

# ── hashtags-changed (added) → pull_request: labeled ────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
file,fixtures/webhooks/gerrit/hashtags-changed-added.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "pull_request"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "labeled"
jsonpath "$[0].body_json.label.name" == "docs"

# ── hashtags-changed (removed) → pull_request: unlabeled ────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
file,fixtures/webhooks/gerrit/hashtags-changed-removed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "pull_request"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "unlabeled"
jsonpath "$[0].body_json.label.name" == "checkout"

# ── wip-state-changed → pull_request: edited ────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
file,fixtures/webhooks/gerrit/wip-state-changed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "pull_request"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "edited"
jsonpath "$[0].body_json.changes.draft.to" == true

# ── private-state-changed → pull_request: edited ────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
file,fixtures/webhooks/gerrit/private-state-changed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "pull_request"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "edited"
jsonpath "$[0].body_json.changes.private.to" == true

# ── assignee-changed (assigned) → pull_request: assigned ────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
file,fixtures/webhooks/gerrit/assignee-changed-assigned.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "pull_request"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "assigned"
jsonpath "$[0].body_json.assignee.login" == "dana"

# ── assignee-changed (unassigned) → pull_request: unassigned ────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
file,fixtures/webhooks/gerrit/assignee-changed-unassigned.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "pull_request"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "unassigned"
jsonpath "$[0].body_json.changes.assignee.from.login" == "dana"

# ── comment-added (changes_requested) → pull_request_review: submitted/CHANGES_REQUESTED

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
file,fixtures/webhooks/gerrit/comment-added-changes_requested.json;
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
jsonpath "$[0].body_json.action" == "submitted"
jsonpath "$[0].body_json.review.state" == "CHANGES_REQUESTED"

# ── comment-added (no vote) → pull_request_review: submitted/COMMENTED ────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
file,fixtures/webhooks/gerrit/comment-added-commented.json;
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
jsonpath "$[0].body_json.action" == "submitted"
jsonpath "$[0].body_json.review.state" == "COMMENTED"
