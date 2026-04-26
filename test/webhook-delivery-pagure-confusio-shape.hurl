# Pagure webhook delivery test — "confusio" shape variant — run by Phase 24 in test-unit.sh.
#
# When webhook_target_shape=confusio, the outbound delivery uses X-Confusio-* headers
# instead of X-GitHub-* headers.  This file spot-checks one event from each of the
# major event families to confirm the header switch happens correctly.

# ── issue.new → issues: opened — confusio shape ───────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Event: issue.new
file,fixtures/webhooks/pagure/issue.new.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "issues"
jsonpath "$[0].confusio_source" == "pagure"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""

# ── issue.comment.added → issue_comment: created — confusio shape ─────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Event: issue.comment.added
file,fixtures/webhooks/pagure/issue.comment.added.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "issue_comment"
jsonpath "$[0].confusio_source" == "pagure"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""

# ── pull-request.new → pull_request: opened — confusio shape ─────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Event: pull-request.new
file,fixtures/webhooks/pagure/pull-request.new.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "pagure"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""

# ── pull-request.closed → pull_request: closed — confusio shape ───────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Event: pull-request.closed
file,fixtures/webhooks/pagure/pull-request.closed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "pagure"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""

# ── git.receive (push) → push — confusio shape ───────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Event: git.receive
file,fixtures/webhooks/pagure/git.receive-push.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "push"
jsonpath "$[0].confusio_source" == "pagure"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
