# Bitbucket Datacenter webhook delivery test — "confusio" shape variant — run by Phase 14 in test-unit.sh.
#
# When webhook_target_shape=confusio, the outbound delivery uses X-Confusio-* headers
# instead of X-GitHub-* headers.  This file spot-checks one event from each of the
# major event families to confirm the header switch happens correctly.
#
# Two {{variables}} are injected by the harness:
#   {{host}}   — confusio  (port 18080)
#   {{target}} — mock delivery target (port 18082)

# ── pull_request: opened — confusio shape ─────────────────────────────────────

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
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "bitbucket_datacenter"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.id" isString
jsonpath "$[0].body_json.type" == "pull_request.opened"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:00:00Z"
jsonpath "$[0].body_json.actor.login" == "octocat"
jsonpath "$[0].body_json.repository.full_name" == "OCTO/hello-world"
jsonpath "$[0].body_json.payload.pull_request.number" == 1

# ── pull_request_review: submitted (approved) — confusio shape ────────────────

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
jsonpath "$[0].confusio_event" == "pull_request_review"
jsonpath "$[0].confusio_source" == "bitbucket_datacenter"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "pull_request.review.submitted"
jsonpath "$[0].body_json.actor.login" == "reviewer"
jsonpath "$[0].body_json.payload.review.state" == "APPROVED"

# ── status: success — confusio shape ──────────────────────────────────────────

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
jsonpath "$[0].confusio_event" == "status"
jsonpath "$[0].confusio_source" == "bitbucket_datacenter"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "status.success"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:05:00Z"
jsonpath "$[0].body_json.repository.full_name" == "OCTO/hello-world"
jsonpath "$[0].body_json.payload.sha" == "abc1234567890abcdef1234567890abcdef12345"
jsonpath "$[0].body_json.payload.context" == "my-ci/build"

# ── push: push — confusio shape ───────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket_datacenter
Content-Type: application/json
X-Event-Key: repo:refs_changed
file,fixtures/webhooks/bitbucket_datacenter/push.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "push"
jsonpath "$[0].confusio_source" == "bitbucket_datacenter"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "push"
jsonpath "$[0].body_json.actor.login" == "bob"
jsonpath "$[0].body_json.repository.full_name" == "OCTOCAT/hello-world"
jsonpath "$[0].body_json.payload.after" == "f1d2d2f924e986ac86fdf7b36c94bcdf32beec15"
