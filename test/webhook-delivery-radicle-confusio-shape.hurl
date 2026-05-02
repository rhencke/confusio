# Radicle webhook delivery test — "confusio" shape variant.
#
# When webhook_target_shape=confusio, Radicle deliveries use X-Confusio-*
# headers and normalized event envelopes instead of GitHub-compatible headers.

# ── push ref update -> push -------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/radicle
Content-Type: application/json
file,fixtures/webhooks/radicle/push.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "push"
jsonpath "$[0].confusio_source" == "radicle"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "push"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:05:00Z"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.ref" == "refs/heads/main"
jsonpath "$[0].body_json.payload.head_commit.id" == "2222222222222222222222222222222222222222"

# ── branch create -> create -------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/radicle
Content-Type: application/json
file,fixtures/webhooks/radicle/create.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "create"
jsonpath "$[0].confusio_source" == "radicle"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "create"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.payload.ref" == "feature/radicle-fixtures"
jsonpath "$[0].body_json.payload.ref_type" == "branch"

# ── branch delete -> delete -------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/radicle
Content-Type: application/json
file,fixtures/webhooks/radicle/delete.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "delete"
jsonpath "$[0].confusio_source" == "radicle"
jsonpath "$[0].body_json.type" == "delete"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.payload.ref" == "feature/radicle-fixtures"
jsonpath "$[0].body_json.payload.ref_type" == "branch"

# ── tag create -> create ----------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/radicle
Content-Type: application/json
file,fixtures/webhooks/radicle/tag-create.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "create"
jsonpath "$[0].confusio_source" == "radicle"
jsonpath "$[0].body_json.type" == "create"
jsonpath "$[0].body_json.payload.ref" == "v1.0.0"
jsonpath "$[0].body_json.payload.ref_type" == "tag"

# ── tag delete -> delete ----------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/radicle
Content-Type: application/json
file,fixtures/webhooks/radicle/tag-delete.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "delete"
jsonpath "$[0].confusio_source" == "radicle"
jsonpath "$[0].body_json.type" == "delete"
jsonpath "$[0].body_json.payload.ref" == "v1.0.0"
jsonpath "$[0].body_json.payload.ref_type" == "tag"

# ── patch created -> pull_request.opened -----------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/radicle
Content-Type: application/json
file,fixtures/webhooks/radicle/patch-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "radicle"
jsonpath "$[0].body_json.type" == "pull_request.opened"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:30:00Z"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.action" == "opened"
jsonpath "$[0].body_json.payload.pull_request.number" == 1

# ── patch updated -> pull_request.synchronize ------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/radicle
Content-Type: application/json
file,fixtures/webhooks/radicle/patch-updated.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "radicle"
jsonpath "$[0].body_json.type" == "pull_request.synchronize"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:50:00Z"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.payload.action" == "synchronize"
jsonpath "$[0].body_json.payload.pull_request.head.sha" == "5555555555555555555555555555555555555555"
