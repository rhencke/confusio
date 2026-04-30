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
jsonpath "$[0].body_json.id" isString
jsonpath "$[0].body_json.type" == "issue.opened"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:00:00Z"
jsonpath "$[0].body_json.actor.login" == "octocat"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.action" == "opened"
jsonpath "$[0].body_json.payload.issue.number" == 1

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
jsonpath "$[0].body_json.type" == "issue.comment.created"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T11:00:00Z"
jsonpath "$[0].body_json.actor.login" == "octocat"
jsonpath "$[0].body_json.payload.comment.id" == 101

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
jsonpath "$[0].body_json.type" == "pull_request.opened"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T14:00:00Z"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.pull_request.number" == 1

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
jsonpath "$[0].body_json.type" == "workflow.run.completed"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T16:05:00Z"
jsonpath "$[0].body_json.payload.workflow_run.conclusion" == "success"
jsonpath "$[0].body_json.payload.workflow_run.head_sha" == "abc123"

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
jsonpath "$[0].body_json.type" == "workflow.job.completed"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T16:03:00Z"
jsonpath "$[0].body_json.payload.workflow_job.name" == "test"
jsonpath "$[0].body_json.payload.workflow_job.conclusion" == "success"

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
jsonpath "$[0].body_json.type" == "push"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:00:00+00:00"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.after" == "da1560886d4f094c3e6c9ef40349f7d38b5d27d0"

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
jsonpath "$[0].body_json.type" == "release.published"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:00:00Z"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.release.tag_name" == "v1.0.0"

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
jsonpath "$[0].body_json.type" == "deployment.created"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T16:00:00Z"
jsonpath "$[0].body_json.payload.deployment.id" == 15
jsonpath "$[0].body_json.payload.deployment.environment" == "production"

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
jsonpath "$[0].body_json.type" == "member.added"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.member.login" == "bob"

# ── organization: created — confusio shape ────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: System Hook
file,fixtures/webhooks/gitlab/organization-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "organization"
jsonpath "$[0].confusio_source" == "gitlab"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "organization.created"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:00:00.000Z"
jsonpath "$[0].body_json.payload.organization.login" == "engineering"

# ── membership: added — confusio shape ────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: System Hook
file,fixtures/webhooks/gitlab/membership-added.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "membership"
jsonpath "$[0].confusio_source" == "gitlab"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "membership.added"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:00:00Z"
jsonpath "$[0].body_json.payload.member.login" == "bob"
jsonpath "$[0].body_json.payload.team.name" == "Engineering"

# ── code_scanning_alert: created — confusio shape ────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Vulnerability Hook
file,fixtures/webhooks/gitlab/code_scanning_alert-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "code_scanning_alert"
jsonpath "$[0].confusio_source" == "gitlab"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "code_scanning_alert.created"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T12:10:00Z"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.alert.rule.name" == "Unsafe eval"

# ── personal_access_token_request: created — confusio shape ──────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Resource Access Token Hook
file,fixtures/webhooks/gitlab/personal_access_token_request-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "personal_access_token_request"
jsonpath "$[0].confusio_source" == "gitlab"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "personal_access_token_request.created"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.personal_access_token_request.token_name" == "build-token"

# ── issues: opened work item — confusio shape ────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Issue Hook
file,fixtures/webhooks/gitlab/issues-opened-work_item.json;
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
jsonpath "$[0].body_json.type" == "issue.opened"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:00:00Z"
jsonpath "$[0].body_json.payload.issue.number" == 2
jsonpath "$[0].body_json.payload.issue.title" == "Plan task"
