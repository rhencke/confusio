# Sourcehut webhook delivery test — "confusio" shape variant.
#
# Spot-checks each translated Sourcehut event family with X-Confusio-* headers
# and normalized envelope bodies.

# -- REPO_CREATED -> repository.created --------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/repository-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "repository"
jsonpath "$[0].confusio_source" == "sourcehut"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "repository.created"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:00:00Z"
jsonpath "$[0].body_json.actor.login" == "octocat"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"

# -- GIT_POST_RECEIVE ref update -> push -------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/push.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "push"
jsonpath "$[0].confusio_source" == "sourcehut"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "push"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T11:10:00Z"
jsonpath "$[0].body_json.payload.ref" == "refs/heads/main"
jsonpath "$[0].body_json.payload.head_commit.id" == "def456abc123def456abc123def456abc123def4"

# -- TICKET_CREATED -> issue.opened ------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/issues-opened.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "issues"
jsonpath "$[0].confusio_source" == "sourcehut"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "issue.opened"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T12:00:00Z"
jsonpath "$[0].body_json.payload.issue.number" == 1

# -- EVENT_CREATED comment -> issue.comment.created --------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/issue_comment-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "issue_comment"
jsonpath "$[0].confusio_source" == "sourcehut"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "issue.comment.created"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T12:15:00Z"
jsonpath "$[0].body_json.payload.comment.body" == "I can reproduce this."

# -- LABEL_CREATED -> label.created ------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/label-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "label"
jsonpath "$[0].confusio_source" == "sourcehut"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "label.created"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T13:00:00Z"
jsonpath "$[0].body_json.payload.label.name" == "bug"

# -- JOB_UPDATED success -> workflow.run.completed ---------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/workflow_run-completed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "workflow_run"
jsonpath "$[0].confusio_source" == "sourcehut"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "workflow.run.completed"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T14:05:00Z"
jsonpath "$[0].body_json.payload.workflow_run.conclusion" == "success"

# -- PATCHSET_RECEIVED -> pull_request.opened --------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/pull_request-opened.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "sourcehut"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "pull_request.opened"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T15:00:00Z"
jsonpath "$[0].body_json.payload.number" == 7
jsonpath "$[0].body_json.payload.pull_request.title" == "Add feature"
