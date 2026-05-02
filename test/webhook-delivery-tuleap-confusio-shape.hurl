# Tuleap webhook delivery test - "confusio" shape variant.
#
# Spot-checks every translated Tuleap fixture family with X-Confusio-* headers
# and normalized envelope bodies.

# -- project_create -> project.created ---------------------------------------

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
jsonpath "$[0].confusio_event" == "project"
jsonpath "$[0].confusio_source" == "tuleap"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "project.created"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:00:00+00:00"
jsonpath "$[0].body_json.payload.project.name" == "Hello World"

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
jsonpath "$[0].confusio_event" == "push"
jsonpath "$[0].confusio_source" == "tuleap"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "push"
jsonpath "$[0].body_json.payload.ref" == "refs/heads/main"
jsonpath "$[0].body_json.payload.pusher.email" == "alice@example.com"

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
jsonpath "$[0].confusio_event" == "create"
jsonpath "$[0].confusio_source" == "tuleap"
jsonpath "$[0].body_json.type" == "create"
jsonpath "$[0].body_json.payload.ref" == "feature/tuleap-fixtures"
jsonpath "$[0].body_json.payload.ref_type" == "branch"

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
jsonpath "$[0].confusio_event" == "delete"
jsonpath "$[0].confusio_source" == "tuleap"
jsonpath "$[0].body_json.type" == "delete"
jsonpath "$[0].body_json.payload.ref" == "feature/tuleap-fixtures"
jsonpath "$[0].body_json.payload.ref_type" == "branch"

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
jsonpath "$[0].confusio_event" == "create"
jsonpath "$[0].confusio_source" == "tuleap"
jsonpath "$[0].body_json.type" == "create"
jsonpath "$[0].body_json.payload.ref" == "v1.0.0"
jsonpath "$[0].body_json.payload.ref_type" == "tag"

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
jsonpath "$[0].confusio_event" == "delete"
jsonpath "$[0].confusio_source" == "tuleap"
jsonpath "$[0].body_json.type" == "delete"
jsonpath "$[0].body_json.payload.ref" == "v1.0.0"
jsonpath "$[0].body_json.payload.ref_type" == "tag"

# -- artifact create -> issue.opened -----------------------------------------

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
jsonpath "$[0].confusio_event" == "issues"
jsonpath "$[0].confusio_source" == "tuleap"
jsonpath "$[0].body_json.type" == "issue.opened"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.payload.issue.number" == 75291

# -- artifact update -> issue.edited -----------------------------------------

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
jsonpath "$[0].confusio_event" == "issues"
jsonpath "$[0].confusio_source" == "tuleap"
jsonpath "$[0].body_json.type" == "issue.edited"
jsonpath "$[0].body_json.actor.login" == "bob"
jsonpath "$[0].body_json.payload.issue.state" == "open"
