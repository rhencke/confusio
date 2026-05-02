# SourceForge webhook delivery test - "confusio" shape variant.
#
# SourceForge / Allura repo-push events are inferred from the JSON body and
# delivered as normalized push/create/delete envelopes.

# -- repo-push ref update -> push --------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourceforge
Content-Type: application/json
file,fixtures/webhooks/sourceforge/push.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "push"
jsonpath "$[0].confusio_source" == "sourceforge"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "push"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:05:00Z"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.ref" == "refs/heads/main"
jsonpath "$[0].body_json.payload.head_commit.id" == "2222222222222222222222222222222222222222"

# -- branch create -> create -------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourceforge
Content-Type: application/json
file,fixtures/webhooks/sourceforge/create.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "create"
jsonpath "$[0].confusio_source" == "sourceforge"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "create"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.payload.ref" == "feature/sourceforge-fixtures"
jsonpath "$[0].body_json.payload.ref_type" == "branch"

# -- branch delete -> delete -------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourceforge
Content-Type: application/json
file,fixtures/webhooks/sourceforge/delete.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "delete"
jsonpath "$[0].confusio_source" == "sourceforge"
jsonpath "$[0].body_json.type" == "delete"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.payload.ref" == "feature/sourceforge-fixtures"
jsonpath "$[0].body_json.payload.ref_type" == "branch"

# -- tag create -> create ----------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourceforge
Content-Type: application/json
file,fixtures/webhooks/sourceforge/tag-create.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "create"
jsonpath "$[0].confusio_source" == "sourceforge"
jsonpath "$[0].body_json.type" == "create"
jsonpath "$[0].body_json.payload.ref" == "v1.0.0"
jsonpath "$[0].body_json.payload.ref_type" == "tag"

# -- tag delete -> delete ----------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourceforge
Content-Type: application/json
file,fixtures/webhooks/sourceforge/tag-delete.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "delete"
jsonpath "$[0].confusio_source" == "sourceforge"
jsonpath "$[0].body_json.type" == "delete"
jsonpath "$[0].body_json.payload.ref" == "v1.0.0"
jsonpath "$[0].body_json.payload.ref_type" == "tag"
