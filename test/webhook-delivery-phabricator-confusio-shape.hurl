# Phabricator webhook delivery test — "confusio" shape variant.
#
# Spot-checks every translated Phabricator event family with X-Confusio-* headers
# and normalized envelope bodies.

# -- TASK -> issue.opened -----------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/phabricator
Content-Type: application/json
file,fixtures/webhooks/phabricator/task-opened.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "issues"
jsonpath "$[0].confusio_source" == "phabricator"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "issue.opened"
jsonpath "$[0].body_json.occurred_at" == "2024-03-09T16:01:40Z"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.repository.full_name" == "octocat/confusio"
jsonpath "$[0].body_json.payload.issue.number" == 123

# -- TASK comment -> issue.comment.created -----------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/phabricator
Content-Type: application/json
file,fixtures/webhooks/phabricator/task-comment-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "issue_comment"
jsonpath "$[0].confusio_source" == "phabricator"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "issue.comment.created"
jsonpath "$[0].body_json.occurred_at" == "2024-03-09T16:03:20Z"
jsonpath "$[0].body_json.actor.login" == "bob"
jsonpath "$[0].body_json.payload.comment.body" == "I can reproduce this."

# -- DREV -> pull_request.opened ---------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/phabricator
Content-Type: application/json
file,fixtures/webhooks/phabricator/differential-opened.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "phabricator"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "pull_request.opened"
jsonpath "$[0].body_json.occurred_at" == "2024-03-09T16:05:00Z"
jsonpath "$[0].body_json.payload.number" == 45
jsonpath "$[0].body_json.payload.pull_request.head.ref" == "feature-phab"

# -- DIFF -> pull_request.synchronize ----------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/phabricator
Content-Type: application/json
file,fixtures/webhooks/phabricator/differential-synchronize.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "phabricator"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "pull_request.synchronize"
jsonpath "$[0].body_json.occurred_at" == "2024-03-09T16:06:40Z"
jsonpath "$[0].body_json.payload.pull_request.head.sha" == "fedcba654321"

# -- CMIT -> push -------------------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/phabricator
Content-Type: application/json
file,fixtures/webhooks/phabricator/commit-push.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "push"
jsonpath "$[0].confusio_source" == "phabricator"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "push"
jsonpath "$[0].body_json.occurred_at" == "2024-03-09T16:08:20Z"
jsonpath "$[0].body_json.payload.ref" == "refs/heads/main"
jsonpath "$[0].body_json.payload.after" == "abcdef123456"

# -- REPO -> repository.created ----------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/phabricator
Content-Type: application/json
file,fixtures/webhooks/phabricator/repository-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "repository"
jsonpath "$[0].confusio_source" == "phabricator"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "repository.created"
jsonpath "$[0].body_json.occurred_at" == "2024-03-09T16:10:00Z"
jsonpath "$[0].body_json.repository.full_name" == "octocat/confusio"

# -- HMBD -> workflow_run.completed ------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/phabricator
Content-Type: application/json
file,fixtures/webhooks/phabricator/harbormaster-build-completed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "workflow_run"
jsonpath "$[0].confusio_source" == "phabricator"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "workflow.run.completed"
jsonpath "$[0].body_json.occurred_at" == "2024-03-09T16:13:20Z"
jsonpath "$[0].body_json.payload.workflow_run.conclusion" == "success"

# -- HMBT -> workflow_job.completed ------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/phabricator
Content-Type: application/json
file,fixtures/webhooks/phabricator/harbormaster-target-completed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "workflow_job"
jsonpath "$[0].confusio_source" == "phabricator"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "workflow_job.completed"
jsonpath "$[0].body_json.occurred_at" == "2024-03-09T16:13:30Z"
jsonpath "$[0].body_json.payload.workflow_job.conclusion" == "failure"
