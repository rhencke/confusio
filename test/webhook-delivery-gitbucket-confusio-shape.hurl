# GitBucket webhook delivery test — "confusio" shape variant — run by Phase 20 in test-unit.sh.
#
# When webhook_target_shape=confusio, the outbound delivery uses X-Confusio-* headers
# instead of X-GitHub-* headers.  This file spot-checks one event from each of the
# major event families to confirm the header switch happens correctly.

# ── issues: opened — confusio shape ──────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: issues
file,fixtures/webhooks/gitbucket/issues-opened.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "issues"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.id" isString
jsonpath "$[0].body_json.type" == "issue.opened"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:00:00Z"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.action" == "opened"
jsonpath "$[0].body_json.payload.issue.number" == 1

# ── issue_comment: created — confusio shape ───────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: issue_comment
file,fixtures/webhooks/gitbucket/issue_comment-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "issue_comment"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "issue.comment.created"
jsonpath "$[0].body_json.actor.login" == "bob"
jsonpath "$[0].body_json.payload.comment.id" == 200

# ── pull_request: opened — confusio shape ─────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: pull_request
file,fixtures/webhooks/gitbucket/pull_request-opened.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "pull_request.opened"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.pull_request.number" == 5

# ── pull_request_review: submitted — confusio shape ───────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: pull_request_review
file,fixtures/webhooks/gitbucket/pull_request_review-submitted.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "pull_request_review"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "pull_request.review.submitted"
jsonpath "$[0].body_json.payload.review.state" == "APPROVED"

# ── milestone: created — confusio shape ───────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: milestone
file,fixtures/webhooks/gitbucket/milestone-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "milestone"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "milestone.created"
jsonpath "$[0].body_json.payload.milestone.title" == "v1.0"

# ── push: push — confusio shape ──────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: push
file,fixtures/webhooks/gitbucket/push.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "push"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "push"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:00:00Z"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.after" == "abc123def456abc123def456abc123def456abc123"

# ── release: published — confusio shape ──────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: release
file,fixtures/webhooks/gitbucket/release-published.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "release"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "release.published"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:00:00Z"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.payload.release.tag_name" == "v1.0.0"

# ── code_scanning_alert: created — confusio shape ─────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: code_scanning_alert
file,fixtures/webhooks/gitbucket/code_scanning_alert-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "code_scanning_alert"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "code_scanning_alert.created"
jsonpath "$[0].body_json.payload.alert.number" == 1

# ── secret_scanning_alert: created — confusio shape ───────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: secret_scanning_alert
file,fixtures/webhooks/gitbucket/secret_scanning_alert-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "secret_scanning_alert"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "secret_scanning_alert.created"
jsonpath "$[0].body_json.payload.alert.number" == 1

# ── secret_scanning_alert_location: created — confusio shape ──────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: secret_scanning_alert_location
file,fixtures/webhooks/gitbucket/secret_scanning_alert_location-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "secret_scanning_alert_location"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "secret_scanning_alert.location.created"
jsonpath "$[0].body_json.payload.location.details.path" == "src/config.js"

# ── security_advisory: published — confusio shape ─────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: security_advisory
file,fixtures/webhooks/gitbucket/security_advisory-published.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "security_advisory"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "security_advisory.published"
jsonpath "$[0].body_json.payload.security_advisory.ghsa_id" == "GHSA-xx99-1234-5678"

# ── repository_advisory: published — confusio shape ───────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: repository_advisory
file,fixtures/webhooks/gitbucket/repository_advisory-published.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "repository_advisory"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "repository.advisory.published"
jsonpath "$[0].body_json.payload.repository_advisory.ghsa_id" == "GHSA-yy88-4321-8765"

# ── repository_vulnerability_alert: create — confusio shape ───────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: repository_vulnerability_alert
file,fixtures/webhooks/gitbucket/repository_vulnerability_alert-create.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "dependabot_alert"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "dependabot_alert.created"
jsonpath "$[0].body_json.payload.alert.id" == 1

# ── member: added — confusio shape ────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: member
file,fixtures/webhooks/gitbucket/member-added.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "member"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "member.added"
jsonpath "$[0].body_json.actor.login" == "octocat"
jsonpath "$[0].body_json.payload.member.login" == "bob"

# ── organization: member_added — confusio shape ───────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: organization
file,fixtures/webhooks/gitbucket/organization-member_added.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "organization"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "organization.member_added"
jsonpath "$[0].body_json.actor.login" == "octocat"
jsonpath "$[0].body_json.payload.organization.login" == "octocat"

# ── membership: added — confusio shape ────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: membership
file,fixtures/webhooks/gitbucket/membership-added.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "membership"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "membership.added"
jsonpath "$[0].body_json.payload.member.login" == "bob"
jsonpath "$[0].body_json.payload.team.name" == "core"

# ── team: created — confusio shape ────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: team
file,fixtures/webhooks/gitbucket/team-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "team"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "team.created"
jsonpath "$[0].body_json.payload.team.name" == "core"

# ── team_add — confusio shape ─────────────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: team_add
file,fixtures/webhooks/gitbucket/team_add.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "team_add"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "team.add"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.team.name" == "core"

# ── project: created — confusio shape ────────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: project
file,fixtures/webhooks/gitbucket/project-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "project"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "project.created"
jsonpath "$[0].body_json.payload.project.name" == "My Project"

# ── project_card: created — confusio shape ────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: project_card
file,fixtures/webhooks/gitbucket/project_card-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "project_card"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "project.card.created"
jsonpath "$[0].body_json.payload.project_card.id" == 1

# ── project_column: created — confusio shape ──────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: project_column
file,fixtures/webhooks/gitbucket/project_column-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "project_column"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "project.column.created"
jsonpath "$[0].body_json.payload.project_column.name" == "To Do"

# ── projects_v2: created — confusio shape ────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: projects_v2
file,fixtures/webhooks/gitbucket/projects_v2-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "projects_v2"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "projects_v2.created"
jsonpath "$[0].body_json.payload.projects_v2.title" == "My V2 Project"

# ── projects_v2_item: created — confusio shape ───────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: projects_v2_item
file,fixtures/webhooks/gitbucket/projects_v2_item-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "projects_v2_item"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "projects_v2.item.created"
jsonpath "$[0].body_json.payload.projects_v2_item.id" == 1

# ── projects_v2_status_update: created — confusio shape ──────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: projects_v2_status_update
file,fixtures/webhooks/gitbucket/projects_v2_status_update-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "projects_v2_status_update"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "projects_v2.status_update.created"
jsonpath "$[0].body_json.payload.projects_v2_status_update.id" == 1

# ── discussion: created — confusio shape ─────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: discussion
file,fixtures/webhooks/gitbucket/discussion-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "discussion"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "discussion.created"
jsonpath "$[0].body_json.payload.discussion.title" == "How do I configure X?"

# ── package: published — confusio shape ──────────────────────────────────────

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: package
file,fixtures/webhooks/gitbucket/package-published.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "package"
jsonpath "$[0].confusio_source" == "gitbucket"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "package.published"
jsonpath "$[0].body_json.payload.package.name" == "my-lib"
