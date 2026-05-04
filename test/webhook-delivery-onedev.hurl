# OneDev webhook delivery tests.
#
# OneDev embeds the native event type in the JSON body as "type".
# These fixture tests cover the distinct normalized delivery families
# registered by backends/onedev.lua.

# -- RefUpdated update -> push ------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/onedev
Content-Type: application/json
file,fixtures/webhooks/onedev/push.json;
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
jsonpath "$[0].body_json.after" == "5a1e9f3d7c2b4a6e8f90123456789abcdef01234"

# -- RefUpdated create -> create --------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/onedev
Content-Type: application/json
file,fixtures/webhooks/onedev/create.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "create"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "feature-branch"
jsonpath "$[0].body_json.ref_type" == "branch"

# -- RefUpdated delete -> delete --------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/onedev
Content-Type: application/json
file,fixtures/webhooks/onedev/delete.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "delete"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "stale-branch"
jsonpath "$[0].body_json.ref_type" == "branch"

# -- IssueOpened -> issues opened -------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/onedev
Content-Type: application/json
file,fixtures/webhooks/onedev/issues-opened.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "issues"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "opened"
jsonpath "$[0].body_json.issue.title" == "Bug report"

# -- IssueChanged closed -> issues closed -----------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/onedev
Content-Type: application/json
file,fixtures/webhooks/onedev/issues-closed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "issues"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "closed"
jsonpath "$[0].body_json.issue.state" == "closed"

# -- IssueCommentCreated -> issue_comment created ---------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/onedev
Content-Type: application/json
file,fixtures/webhooks/onedev/issue_comment-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "issue_comment"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "created"
jsonpath "$[0].body_json.comment.body" == "Confirmed, I can reproduce this."

# -- PullRequestOpened -> pull_request opened -------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/onedev
Content-Type: application/json
file,fixtures/webhooks/onedev/pull_request-opened.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "pull_request"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "opened"
jsonpath "$[0].body_json.number" == 9

# -- PullRequestChanged added commits -> pull_request synchronize ------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/onedev
Content-Type: application/json
file,fixtures/webhooks/onedev/pull_request-synchronize.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "pull_request"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "synchronize"
jsonpath "$[0].body_json.pull_request.head.ref" == "feature"

# -- PullRequestCodeCommentCreated -> pull_request_review_comment created ----

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/onedev
Content-Type: application/json
file,fixtures/webhooks/onedev/pull_request_review_comment-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "pull_request_review_comment"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "created"
jsonpath "$[0].body_json.comment.path" == "src/app.lua"

# -- BuildFinished SUCCESSFUL -> workflow_run completed ----------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/onedev
Content-Type: application/json
file,fixtures/webhooks/onedev/workflow_run-completed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "workflow_run"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "completed"
jsonpath "$[0].body_json.workflow_run.conclusion" == "success"

# -- PackPublished -> package published -------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/onedev
Content-Type: application/json
file,fixtures/webhooks/onedev/package-published.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "package"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "published"
jsonpath "$[0].body_json.package.name" == "hello-world"
