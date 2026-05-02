# Phabricator webhook delivery tests — native body-typed object families.
#
# Phabricator embeds the native object family in object.type (or a PHID prefix);
# no event-type header is required.

# -- TASK -> issues: opened ---------------------------------------------------

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
jsonpath "$[0].github_event" == "issues"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.action" == "opened"
jsonpath "$[0].body_json.issue.number" == 123
jsonpath "$[0].body_json.issue.title" == "Fix the task"
jsonpath "$[0].body_json.repository.full_name" == "octocat/confusio"

# -- TASK comment -> issue_comment: created ----------------------------------

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
jsonpath "$[0].github_event" == "issue_comment"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.action" == "created"
jsonpath "$[0].body_json.issue.number" == 123
jsonpath "$[0].body_json.comment.id" == 456
jsonpath "$[0].body_json.comment.body" == "I can reproduce this."

# -- DREV -> pull_request: opened --------------------------------------------

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
jsonpath "$[0].github_event" == "pull_request"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.action" == "opened"
jsonpath "$[0].body_json.number" == 45
jsonpath "$[0].body_json.pull_request.title" == "Review this change"
jsonpath "$[0].body_json.pull_request.head.ref" == "feature-phab"
jsonpath "$[0].body_json.pull_request.base.ref" == "main"

# -- DIFF -> pull_request: synchronize ---------------------------------------

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
jsonpath "$[0].github_event" == "pull_request"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.action" == "synchronize"
jsonpath "$[0].body_json.number" == 45
jsonpath "$[0].body_json.pull_request.head.sha" == "fedcba654321"

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
jsonpath "$[0].github_event" == "push"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.ref" == "refs/heads/main"
jsonpath "$[0].body_json.after" == "abcdef123456"
jsonpath "$[0].body_json.commits[0].message" == "Push through Diffusion"
jsonpath "$[0].body_json.repository.full_name" == "octocat/confusio"

# -- REPO -> repository: created ---------------------------------------------

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
jsonpath "$[0].github_event" == "repository"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.action" == "created"
jsonpath "$[0].body_json.repository.name" == "confusio"
jsonpath "$[0].body_json.repository.full_name" == "octocat/confusio"

# -- HMBD -> workflow_run: completed -----------------------------------------

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
jsonpath "$[0].github_event" == "workflow_run"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.action" == "completed"
jsonpath "$[0].body_json.workflow_run.name" == "unit tests"
jsonpath "$[0].body_json.workflow_run.status" == "completed"
jsonpath "$[0].body_json.workflow_run.conclusion" == "success"

# -- HMBT -> workflow_job: completed -----------------------------------------

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
jsonpath "$[0].github_event" == "workflow_job"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.action" == "completed"
jsonpath "$[0].body_json.workflow_job.name" == "lint"
jsonpath "$[0].body_json.workflow_job.status" == "completed"
jsonpath "$[0].body_json.workflow_job.conclusion" == "failure"
