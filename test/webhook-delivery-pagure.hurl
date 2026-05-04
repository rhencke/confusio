# Pagure webhook delivery tests — run by Phase 23 in test-unit.sh.
#
# Pagure uses X-Pagure-Event header to indicate the event type.
#
# For every event type supported by the Pagure backend, this file:
#   1. Resets the mock delivery target log.
#   2. POSTs the fixture to /webhooks/pagure with the appropriate X-Pagure-Event header.
#   3. Queries the delivery target and asserts exactly one delivery was recorded with
#      the correct github_event, a UUID delivery ID, and confusio in the User-Agent.

# ── issue.new → issues: opened ────────────────────────────────────────────────

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
jsonpath "$[0].github_event" == "issues"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.action" == "opened"
jsonpath "$[0].body_json.issue.title" == "Bug report"
jsonpath "$[0].body_json.repository.full_name" == "myorg/my-repo"

# ── issue.edit → issues: edited ───────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Event: issue.edit
file,fixtures/webhooks/pagure/issue.edit.json;
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
jsonpath "$[0].body_json.action" == "edited"
jsonpath "$[0].body_json.issue.number" == 1

# ── issue.status.change (closed) → issues: closed ────────────────────────────

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
jsonpath "$[0].github_event" == "issues"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.action" == "closed"
jsonpath "$[0].body_json.issue.state" == "closed"

# ── issue.status.change (reopened) → issues: reopened ────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Event: issue.status.change
file,fixtures/webhooks/pagure/issue.status.change-reopened.json;
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
jsonpath "$[0].body_json.action" == "reopened"
jsonpath "$[0].body_json.issue.state" == "open"

# ── issue.comment.added → issue_comment: created ─────────────────────────────

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
jsonpath "$[0].github_event" == "issue_comment"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.action" == "created"
jsonpath "$[0].body_json.comment.body" == "I can reproduce this too."

# ── pull-request.new → pull_request: opened ───────────────────────────────────

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
jsonpath "$[0].github_event" == "pull_request"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.action" == "opened"
jsonpath "$[0].body_json.number" == 5
jsonpath "$[0].body_json.pull_request.title" == "Add awesome feature"

# ── pull-request.updated → pull_request: synchronize ─────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Event: pull-request.updated
file,fixtures/webhooks/pagure/pull-request.updated.json;
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
jsonpath "$[0].body_json.number" == 5

# ── pull-request.closed → pull_request: closed ────────────────────────────────

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
jsonpath "$[0].github_event" == "pull_request"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.action" == "closed"
jsonpath "$[0].body_json.pull_request.state" == "closed"

# ── git.receive (push) → push: push ───────────────────────────────────────────

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
jsonpath "$[0].github_event" == "push"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.ref" == "refs/heads/main"
jsonpath "$[0].body_json.before" == "6dcb09b5b57875f334f61aebed695e2e4193db5e"
jsonpath "$[0].body_json.after" == "f1d2d2f924e986ac86fdf7b36c94bcdf32beec15"
jsonpath "$[0].body_json.head_commit.sha" == "f1d2d2f924e986ac86fdf7b36c94bcdf32beec15"

# ── git.receive (create) → create: create ────────────────────────────────────

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
jsonpath "$[0].github_event" == "create"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.ref" == "feature-branch"
jsonpath "$[0].body_json.ref_type" == "branch"

# ── git.receive (delete) → delete: delete ────────────────────────────────────

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
jsonpath "$[0].github_event" == "delete"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.ref" == "stale-branch"
jsonpath "$[0].body_json.ref_type" == "branch"

# ── project.forked → fork: fork ───────────────────────────────────────────────

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
jsonpath "$[0].github_event" == "fork"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.forkee.full_name" == "forks/bob/hello-world"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
