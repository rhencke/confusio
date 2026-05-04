# Tuleap webhook delivery tests.
#
# These fixture-based tests cover Tuleap project, Git, and tracker artifact
# events and verify GitHub-shaped fanout.

# -- project_create -> project: created --------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/tuleap
Content-Type: application/json
file,fixtures/webhooks/tuleap/project-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "project"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.action" == "created"
jsonpath "$[0].body_json.project.name" == "Hello World"
jsonpath "$[0].body_json.project.path_with_namespace" == "octocat/hello-world"

# -- git_push ref update -> push ---------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/tuleap
Content-Type: application/json
file,fixtures/webhooks/tuleap/push.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "push"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" not exists
jsonpath "$[0].body_json.ref" == "refs/heads/main"
jsonpath "$[0].body_json.before" == "1111111111111111111111111111111111111111"
jsonpath "$[0].body_json.after" == "2222222222222222222222222222222222222222"
jsonpath "$[0].body_json.repository.full_name" == "hello-world"
jsonpath "$[0].body_json.pusher.email" == "alice@example.com"

# -- branch create -> create -------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/tuleap
Content-Type: application/json
file,fixtures/webhooks/tuleap/create.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "create"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "feature/tuleap-fixtures"
jsonpath "$[0].body_json.ref_type" == "branch"
jsonpath "$[0].body_json.repository.full_name" == "hello-world"
jsonpath "$[0].body_json.sender.login" == "alice"

# -- branch delete -> delete -------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/tuleap
Content-Type: application/json
file,fixtures/webhooks/tuleap/delete.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "delete"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "feature/tuleap-fixtures"
jsonpath "$[0].body_json.ref_type" == "branch"
jsonpath "$[0].body_json.repository.full_name" == "hello-world"
jsonpath "$[0].body_json.sender.login" == "alice"

# -- tag create -> create ----------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/tuleap
Content-Type: application/json
file,fixtures/webhooks/tuleap/tag-create.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "create"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "v1.0.0"
jsonpath "$[0].body_json.ref_type" == "tag"
jsonpath "$[0].body_json.repository.full_name" == "hello-world"

# -- tag delete -> delete ----------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/tuleap
Content-Type: application/json
file,fixtures/webhooks/tuleap/tag-delete.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "delete"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "v1.0.0"
jsonpath "$[0].body_json.ref_type" == "tag"
jsonpath "$[0].body_json.repository.full_name" == "hello-world"

# -- artifact create -> issues: opened ---------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/tuleap
Content-Type: application/json
file,fixtures/webhooks/tuleap/artifact-created.json;
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
jsonpath "$[0].body_json.issue.number" == 75291
jsonpath "$[0].body_json.issue.title" == "Normalize Tuleap webhook payloads"
jsonpath "$[0].body_json.issue.user.login" == "alice"

# -- artifact update -> issues: edited ---------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/tuleap
Content-Type: application/json
file,fixtures/webhooks/tuleap/artifact-updated.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "issues"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "edited"
jsonpath "$[0].body_json.issue.number" == 75291
jsonpath "$[0].body_json.issue.state" == "open"
jsonpath "$[0].body_json.sender.login" == "bob"
