# GitLab webhook delivery test — "confusio" shape variant — run by Phase 10 in test-unit.sh.
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

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Issues Hook
file,fixtures/webhooks/gitlab/issues-opened.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "issues"
jsonpath "$[0].confusio_source" == "gitlab"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""

# ── issue_comment: created — confusio shape ───────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Note Hook
file,fixtures/webhooks/gitlab/issue_comment-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "issue_comment"
jsonpath "$[0].confusio_source" == "gitlab"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""

# ── pull_request: opened — confusio shape ─────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Merge Request Hook
file,fixtures/webhooks/gitlab/pull_request-opened.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "gitlab"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""

# ── workflow_run: completed — confusio shape ──────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Pipeline Hook
file,fixtures/webhooks/gitlab/workflow_run-completed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "workflow_run"
jsonpath "$[0].confusio_source" == "gitlab"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""

# ── workflow_job: completed — confusio shape ──────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Job Hook
file,fixtures/webhooks/gitlab/workflow_job-completed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "workflow_job"
jsonpath "$[0].confusio_source" == "gitlab"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""

# ── push: push — confusio shape ──────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Push Hook
file,fixtures/webhooks/gitlab/push.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "push"
jsonpath "$[0].confusio_source" == "gitlab"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""

# ── release: published — confusio shape ──────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Release Hook
file,fixtures/webhooks/gitlab/release-published.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "release"
jsonpath "$[0].confusio_source" == "gitlab"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""

# ── deployment: created — confusio shape ─────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Deployment Hook
file,fixtures/webhooks/gitlab/deployment-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "deployment"
jsonpath "$[0].confusio_source" == "gitlab"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""

# ── member: added — confusio shape ───────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Member Hook
file,fixtures/webhooks/gitlab/member-added.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "member"
jsonpath "$[0].confusio_source" == "gitlab"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
