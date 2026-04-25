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
