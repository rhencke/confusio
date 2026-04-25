# Bitbucket Datacenter webhook delivery tests — run by Phase 13 in test-unit.sh.
#
# For every event × action triple supported by the Bitbucket Datacenter backend, this file:
#   1. Resets the mock delivery target log.
#   2. POSTs the fixture to /webhooks/bitbucket_datacenter with the appropriate X-Event-Key header.
#   3. Queries the delivery target and asserts exactly one delivery was recorded with
#      the correct github_event, a UUID delivery ID, and confusio in the User-Agent.
#
# Fixtures live in test/fixtures/webhooks/bitbucket_datacenter/ — one file per event × action.
# All assertions use the "github" delivery shape (default).
#
# Bitbucket Datacenter uses the X-Event-Key header for event type identification.

# ── pull_request: opened ──────────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket_datacenter
Content-Type: application/json
X-Event-Key: pr:opened
file,fixtures/webhooks/bitbucket_datacenter/pull_request-opened.json;
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

POST http://{{host}}/webhooks/bitbucket_datacenter
Content-Type: application/json
X-Event-Key: pr:modified
file,fixtures/webhooks/bitbucket_datacenter/pull_request-edited.json;
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

POST http://{{host}}/webhooks/bitbucket_datacenter
Content-Type: application/json
X-Event-Key: pr:from_ref_updated
file,fixtures/webhooks/bitbucket_datacenter/pull_request-synchronize.json;
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

POST http://{{host}}/webhooks/bitbucket_datacenter
Content-Type: application/json
X-Event-Key: pr:reviewer:updated
file,fixtures/webhooks/bitbucket_datacenter/pull_request-review_requested.json;
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

POST http://{{host}}/webhooks/bitbucket_datacenter
Content-Type: application/json
X-Event-Key: pr:reviewer:updated
file,fixtures/webhooks/bitbucket_datacenter/pull_request-review_request_removed.json;
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

POST http://{{host}}/webhooks/bitbucket_datacenter
Content-Type: application/json
X-Event-Key: pr:merged
file,fixtures/webhooks/bitbucket_datacenter/pull_request-closed-merged.json;
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

POST http://{{host}}/webhooks/bitbucket_datacenter
Content-Type: application/json
X-Event-Key: pr:declined
file,fixtures/webhooks/bitbucket_datacenter/pull_request-closed-declined.json;
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

# ── pull_request: closed (deleted) ────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket_datacenter
Content-Type: application/json
X-Event-Key: pr:deleted
file,fixtures/webhooks/bitbucket_datacenter/pull_request-closed-deleted.json;
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

POST http://{{host}}/webhooks/bitbucket_datacenter
Content-Type: application/json
X-Event-Key: pr:reviewer:approved
file,fixtures/webhooks/bitbucket_datacenter/pull_request_review-submitted-approved.json;
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

# ── pull_request_review: submitted (changes_requested) ────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket_datacenter
Content-Type: application/json
X-Event-Key: pr:reviewer:needs_work
file,fixtures/webhooks/bitbucket_datacenter/pull_request_review-submitted-changes_requested.json;
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

# ── status: success (build:status_created) ────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket_datacenter
Content-Type: application/json
X-Event-Key: build:status_created
file,fixtures/webhooks/bitbucket_datacenter/status-created-success.json;
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

# ── status: pending (build:status_updated) ────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket_datacenter
Content-Type: application/json
X-Event-Key: build:status_updated
file,fixtures/webhooks/bitbucket_datacenter/status-updated-pending.json;
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
