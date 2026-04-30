# Gerrit webhook delivery test — "confusio" shape variant — run by Phase 18 in test-unit.sh.
#
# When webhook_target_shape=confusio, the outbound delivery uses X-Confusio-* headers
# instead of X-GitHub-* headers.  This file verifies Gerrit pull_request_review
# and pull_request lifecycle events in confusio shape.

# ── comment-added (approved) → pull_request_review — confusio shape ───────────

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
jsonpath "$[0].confusio_event" == "pull_request_review"
jsonpath "$[0].confusio_source" == "gerrit"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.id" isString
jsonpath "$[0].body_json.type" == "pull_request.review.submitted"
jsonpath "$[0].body_json.occurred_at" == "1705312800"
jsonpath "$[0].body_json.actor.login" == "bob"
jsonpath "$[0].body_json.repository.full_name" == "myorg/my-repo"
jsonpath "$[0].body_json.payload.review.state" == "APPROVED"

# ── comment-added (changes_requested) → pull_request_review — confusio shape ──

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
jsonpath "$[0].confusio_event" == "pull_request_review"
jsonpath "$[0].confusio_source" == "gerrit"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "pull_request.review.submitted"
jsonpath "$[0].body_json.actor.login" == "bob"
jsonpath "$[0].body_json.payload.review.state" == "CHANGES_REQUESTED"

# ── comment-added (no vote) → pull_request_review — confusio shape ────────────

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
jsonpath "$[0].confusio_event" == "pull_request_review"
jsonpath "$[0].confusio_source" == "gerrit"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "pull_request.review.submitted"
jsonpath "$[0].body_json.occurred_at" == "1705316400"
jsonpath "$[0].body_json.actor.login" == "charlie"
jsonpath "$[0].body_json.payload.review.state" == "COMMENTED"

# ── patchset-created (first patch set) → pull_request.opened — confusio shape

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
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "gerrit"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "pull_request.opened"
jsonpath "$[0].body_json.occurred_at" == "1705311000"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.repository.full_name" == "myorg/my-repo"
jsonpath "$[0].body_json.payload.action" == "opened"
jsonpath "$[0].body_json.payload.pull_request.head.sha" == "111aaa222bbb"

# ── patchset-created (later patch set) → pull_request.synchronize — confusio shape

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
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "gerrit"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].body_json.type" == "pull_request.synchronize"
jsonpath "$[0].body_json.occurred_at" == "1705318200"
jsonpath "$[0].body_json.payload.action" == "synchronize"
jsonpath "$[0].body_json.payload.pull_request.head.sha" == "333ccc444ddd"

# ── change-merged → pull_request.closed / merged — confusio shape ───────────

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
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "gerrit"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].body_json.type" == "pull_request.closed"
jsonpath "$[0].body_json.occurred_at" == "1705321800"
jsonpath "$[0].body_json.actor.login" == "dana"
jsonpath "$[0].body_json.payload.action" == "closed"
jsonpath "$[0].body_json.payload.pull_request.state" == "closed"
jsonpath "$[0].body_json.payload.pull_request.merged" == true
jsonpath "$[0].body_json.payload.pull_request.merged_at" == "1705321800"

# ── change-abandoned → pull_request.closed / not merged — confusio shape ────

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
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "gerrit"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].body_json.type" == "pull_request.closed"
jsonpath "$[0].body_json.occurred_at" == "1705325400"
jsonpath "$[0].body_json.actor.login" == "eve"
jsonpath "$[0].body_json.payload.action" == "closed"
jsonpath "$[0].body_json.payload.pull_request.state" == "closed"
jsonpath "$[0].body_json.payload.pull_request.merged" == false
jsonpath "$[0].body_json.payload.reason" == "Superseded by another change"

# ── change-restored → pull_request.reopened — confusio shape ────────────────

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
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "gerrit"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].body_json.type" == "pull_request.reopened"
jsonpath "$[0].body_json.occurred_at" == "1705329000"
jsonpath "$[0].body_json.actor.login" == "eve"
jsonpath "$[0].body_json.payload.action" == "reopened"
jsonpath "$[0].body_json.payload.pull_request.state" == "open"
jsonpath "$[0].body_json.payload.reason" == "Back in scope"

# ── topic-changed → pull_request.edited — confusio shape ───────────────────

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
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "gerrit"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].body_json.type" == "pull_request.edited"
jsonpath "$[0].body_json.occurred_at" == "1705332600"
jsonpath "$[0].body_json.actor.login" == "bob"
jsonpath "$[0].body_json.payload.action" == "edited"
jsonpath "$[0].body_json.payload.changes.topic.from" == "checkout"
jsonpath "$[0].body_json.payload.changes.topic.to" == "checkout-v2"

# ── hashtags-changed (added) → pull_request.labeled — confusio shape ───────

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
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "gerrit"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].body_json.type" == "pull_request.labeled"
jsonpath "$[0].body_json.occurred_at" == "1705336200"
jsonpath "$[0].body_json.actor.login" == "cara"
jsonpath "$[0].body_json.payload.action" == "labeled"
jsonpath "$[0].body_json.payload.label.name" == "docs"
jsonpath "$[0].body_json.payload.pull_request.labels[0].name" == "docs"

# ── hashtags-changed (removed) → pull_request.unlabeled — confusio shape ───

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
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "gerrit"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].body_json.type" == "pull_request.unlabeled"
jsonpath "$[0].body_json.occurred_at" == "1705339800"
jsonpath "$[0].body_json.actor.login" == "cara"
jsonpath "$[0].body_json.payload.action" == "unlabeled"
jsonpath "$[0].body_json.payload.label.name" == "checkout"
jsonpath "$[0].body_json.payload.changes.labels.removed[0].name" == "checkout"

# ── wip-state-changed → pull_request.edited — confusio shape ───────────────

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
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "gerrit"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].body_json.type" == "pull_request.edited"
jsonpath "$[0].body_json.occurred_at" == "1705343400"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.payload.action" == "edited"
jsonpath "$[0].body_json.payload.pull_request.draft" == true
jsonpath "$[0].body_json.payload.changes.draft.to" == true

# ── private-state-changed → pull_request.edited — confusio shape ───────────

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
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "gerrit"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].body_json.type" == "pull_request.edited"
jsonpath "$[0].body_json.occurred_at" == "1705347000"
jsonpath "$[0].body_json.actor.login" == "bob"
jsonpath "$[0].body_json.payload.action" == "edited"
jsonpath "$[0].body_json.payload.changes.private.to" == true

# ── assignee-changed (assigned) → pull_request.assigned — confusio shape ───

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
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "gerrit"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].body_json.type" == "pull_request.assigned"
jsonpath "$[0].body_json.occurred_at" == "1705350600"
jsonpath "$[0].body_json.actor.login" == "bob"
jsonpath "$[0].body_json.payload.action" == "assigned"
jsonpath "$[0].body_json.payload.assignee.login" == "dana"

# ── assignee-changed (unassigned) → pull_request.unassigned — confusio shape

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
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "gerrit"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].body_json.type" == "pull_request.unassigned"
jsonpath "$[0].body_json.occurred_at" == "1705354200"
jsonpath "$[0].body_json.actor.login" == "bob"
jsonpath "$[0].body_json.payload.action" == "unassigned"
jsonpath "$[0].body_json.payload.changes.assignee.from.login" == "dana"
