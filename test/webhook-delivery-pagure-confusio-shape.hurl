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
jsonpath "$[0].body_json.id" isString
jsonpath "$[0].body_json.type" == "issue.opened"
jsonpath "$[0].body_json.occurred_at" == "1705312800"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.repository.full_name" == "myorg/my-repo"
jsonpath "$[0].body_json.payload.issue.number" == 1
jsonpath "$[0].body_json.payload.issue.html_url" contains "/myorg/my-repo/issue/1"
jsonpath "$[0].body_json.payload.issue.milestone.title" == "v1.0"

# ── issue.status.change → issues: closed — confusio shape ────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Event: issue.status.change
file,fixtures/webhooks/pagure/issue.status.change-closed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "issues"
jsonpath "$[0].confusio_source" == "pagure"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "issue.closed"
jsonpath "$[0].body_json.occurred_at" == "1705320000"
jsonpath "$[0].body_json.actor.login" == "bob"
jsonpath "$[0].body_json.payload.issue.state" == "closed"
jsonpath "$[0].body_json.payload.issue.closed_at" == "1705320000"

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
jsonpath "$[0].body_json.type" == "issue.comment.created"
jsonpath "$[0].body_json.occurred_at" == "1705316400"
jsonpath "$[0].body_json.actor.login" == "bob"
jsonpath "$[0].body_json.payload.comment.id" == 100
jsonpath "$[0].body_json.payload.comment.body" == "I can reproduce this too."
jsonpath "$[0].body_json.payload.comment.html_url" contains "/myorg/my-repo/issue/1#comment-100"
jsonpath "$[0].body_json.payload.issue.html_url" contains "/myorg/my-repo/issue/1"

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
jsonpath "$[0].body_json.type" == "pull_request.opened"
jsonpath "$[0].body_json.occurred_at" == "1705312800"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.repository.full_name" == "myorg/my-repo"
jsonpath "$[0].body_json.payload.pull_request.number" == 5

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
jsonpath "$[0].body_json.type" == "pull_request.closed"
jsonpath "$[0].body_json.occurred_at" == "1705323600"
jsonpath "$[0].body_json.actor.login" == "bob"
jsonpath "$[0].body_json.payload.pull_request.state" == "closed"

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
jsonpath "$[0].body_json.type" == "push"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:00:00Z"
jsonpath "$[0].body_json.actor.login" == "bob"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.after" == "f1d2d2f924e986ac86fdf7b36c94bcdf32beec15"

# ── git.receive (create) → create — confusio shape ───────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Event: git.receive
file,fixtures/webhooks/pagure/create.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "create"
jsonpath "$[0].confusio_source" == "pagure"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "create"
jsonpath "$[0].body_json.actor.login" == "bob"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.ref" == "feature-branch"
jsonpath "$[0].body_json.payload.ref_type" == "branch"

# ── git.receive (delete) → delete — confusio shape ───────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Event: git.receive
file,fixtures/webhooks/pagure/delete.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "delete"
jsonpath "$[0].confusio_source" == "pagure"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "delete"
jsonpath "$[0].body_json.actor.login" == "bob"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.ref" == "stale-branch"
jsonpath "$[0].body_json.payload.ref_type" == "branch"

# ── project.forked → fork — confusio shape ───────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Event: project.forked
file,fixtures/webhooks/pagure/fork.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "fork"
jsonpath "$[0].confusio_source" == "pagure"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "fork"
jsonpath "$[0].body_json.actor.login" == "bob"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.forkee.full_name" == "forks/bob/hello-world"
