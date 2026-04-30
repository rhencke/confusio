# Bitbucket Cloud webhook delivery test — "confusio" shape variant — run by Phase 12 in test-unit.sh.
#
# When webhook_target_shape=confusio, the outbound delivery uses X-Confusio-* headers
# instead of X-GitHub-* headers.  This file spot-checks one event from each of the
# major event families to confirm the header switch happens correctly.
#
# Two {{variables}} are injected by the harness:
#   {{host}}   — confusio  (port 18080)
#   {{target}} — mock delivery target (port 18082)

# ── issues: opened — confusio shape ──────────────────────────────────────────

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
jsonpath "$[0].confusio_event" == "issues"
jsonpath "$[0].confusio_source" == "bitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.id" isString
jsonpath "$[0].body_json.type" == "issue.opened"
jsonpath "$[0].body_json.actor.login" == "octocat"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.action" == "opened"
jsonpath "$[0].body_json.payload.issue.number" == 1

# ── issue_comment: created — confusio shape ───────────────────────────────────

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
jsonpath "$[0].confusio_event" == "issue_comment"
jsonpath "$[0].confusio_source" == "bitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "issue.comment.created"
jsonpath "$[0].body_json.actor.login" == "octocat"
jsonpath "$[0].body_json.payload.comment.id" == 101

# ── commit_comment: created — confusio shape ─────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: repo:commit_comment_created
file,fixtures/webhooks/bitbucket/commit_comment-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "commit_comment"
jsonpath "$[0].confusio_source" == "bitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "commit_comment.created"
jsonpath "$[0].body_json.actor.login" == "octocat"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.comment.id" == 303
jsonpath "$[0].body_json.payload.comment.commit_id" == "abc1234567890abcdef1234567890abcdef12345"
jsonpath "$[0].body_json.payload.comment.path" == "src/main.lua"
jsonpath "$[0].body_json.payload.comment.line" == 42

# ── pull_request: opened — confusio shape ─────────────────────────────────────

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
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "bitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "pull_request.opened"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.pull_request.number" == 1

# ── pull_request_review: submitted (approved) — confusio shape ────────────────

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
jsonpath "$[0].confusio_event" == "pull_request_review"
jsonpath "$[0].confusio_source" == "bitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "pull_request.review.submitted"
jsonpath "$[0].body_json.actor.login" == "reviewer"
jsonpath "$[0].body_json.payload.review.state" == "APPROVED"

# ── pull_request_review: submitted (changes requested) — confusio shape ──────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: pullrequest:changes_request_created
file,fixtures/webhooks/bitbucket/pull_request_review-submitted-changes_requested.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "pull_request_review"
jsonpath "$[0].confusio_source" == "bitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "pull_request.review.submitted"
jsonpath "$[0].body_json.actor.login" == "reviewer"
jsonpath "$[0].body_json.payload.review.state" == "CHANGES_REQUESTED"
jsonpath "$[0].body_json.payload.review.submitted_at" == "2024-01-15T11:15:00+00:00"

# ── pull_request_review_comment: created — confusio shape ────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: pullrequest:comment_created
file,fixtures/webhooks/bitbucket/pull_request_review_comment-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "pull_request_review_comment"
jsonpath "$[0].confusio_source" == "bitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "pull_request.review_comment.created"
jsonpath "$[0].body_json.actor.login" == "reviewer"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.comment.id" == 401
jsonpath "$[0].body_json.payload.comment.path" == "src/main.lua"
jsonpath "$[0].body_json.payload.comment.position" == 42
jsonpath "$[0].body_json.payload.pull_request.number" == 1

# ── status: success — confusio shape ──────────────────────────────────────────

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
jsonpath "$[0].confusio_event" == "status"
jsonpath "$[0].confusio_source" == "bitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "status.success"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:05:00+00:00"
jsonpath "$[0].body_json.payload.sha" == "abc1234567890abcdef1234567890abcdef12345"
jsonpath "$[0].body_json.payload.context" == "my-ci/build"

# ── push: push — confusio shape ───────────────────────────────────────────────

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
jsonpath "$[0].confusio_event" == "push"
jsonpath "$[0].confusio_source" == "bitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "push"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.after" == "da1560886d4f094c3e6c9ef40349f7d38b5d27d0"
