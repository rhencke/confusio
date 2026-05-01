# OneDev webhook delivery test — "confusio" shape variant.
#
# When webhook_target_shape=confusio, deliveries use X-Confusio-* headers
# and normalized envelopes instead of GitHub-compatible headers.

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
jsonpath "$[0].confusio_event" == "push"
jsonpath "$[0].confusio_source" == "onedev"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "push"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:05:00Z"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.ref" == "refs/heads/main"

# -- IssueOpened -> issues.opened -------------------------------------------

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
jsonpath "$[0].confusio_event" == "issues"
jsonpath "$[0].confusio_source" == "onedev"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "issue.opened"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.payload.action" == "opened"
jsonpath "$[0].body_json.payload.issue.number" == 7

# -- PullRequestChanged added commits -> pull_request.synchronize ------------

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
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "onedev"
jsonpath "$[0].body_json.type" == "pull_request.synchronize"
jsonpath "$[0].body_json.payload.action" == "synchronize"
jsonpath "$[0].body_json.payload.pull_request.number" == 9

# -- BuildFinished SUCCESSFUL -> workflow_run.completed ----------------------

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
jsonpath "$[0].confusio_event" == "workflow_run"
jsonpath "$[0].confusio_source" == "onedev"
jsonpath "$[0].body_json.type" == "workflow.run.completed"
jsonpath "$[0].body_json.payload.action" == "completed"
jsonpath "$[0].body_json.payload.workflow_run.conclusion" == "success"
