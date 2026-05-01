# Kallithea webhook delivery test — "confusio" shape variant.
#
# When webhook_target_shape=confusio, Kallithea deliveries use X-Confusio-*
# headers and normalized event envelopes instead of GitHub-compatible headers.

# ── PUSH_HOOK update -> push -------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/kallithea
Content-Type: application/json
file,fixtures/webhooks/kallithea/push.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "push"
jsonpath "$[0].confusio_source" == "kallithea"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "push"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:05:00Z"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.ref" == "refs/heads/main"
jsonpath "$[0].body_json.payload.head_commit.id" == "5a1e9f3d7c2b4a6e8f90123456789abcdef01234"

# ── PUSH_HOOK create -> create ----------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/kallithea
Content-Type: application/json
file,fixtures/webhooks/kallithea/create.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "create"
jsonpath "$[0].confusio_source" == "kallithea"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "create"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.payload.ref" == "feature-branch"
jsonpath "$[0].body_json.payload.ref_type" == "branch"

# ── PUSH_HOOK delete -> delete ----------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/kallithea
Content-Type: application/json
file,fixtures/webhooks/kallithea/delete.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "delete"
jsonpath "$[0].confusio_source" == "kallithea"
jsonpath "$[0].body_json.type" == "delete"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.payload.ref" == "stale-branch"
jsonpath "$[0].body_json.payload.ref_type" == "branch"

# ── CREATE_REPO_HOOK -> repository.created ----------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/kallithea
Content-Type: application/json
file,fixtures/webhooks/kallithea/repository-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "repository"
jsonpath "$[0].confusio_source" == "kallithea"
jsonpath "$[0].body_json.type" == "repository.created"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T09:00:00Z"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.action" == "created"

# ── DELETE_REPO_HOOK -> repository.deleted ----------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/kallithea
Content-Type: application/json
file,fixtures/webhooks/kallithea/repository-deleted.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "repository"
jsonpath "$[0].confusio_source" == "kallithea"
jsonpath "$[0].body_json.type" == "repository.deleted"
jsonpath "$[0].body_json.occurred_at" == "1705312800"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.payload.action" == "deleted"

# ── CREATE_PULLREQUEST_HOOK -> pull_request.opened --------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/kallithea
Content-Type: application/json
file,fixtures/webhooks/kallithea/pull_request-opened.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "kallithea"
jsonpath "$[0].body_json.type" == "pull_request.opened"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T11:00:00Z"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.action" == "opened"
jsonpath "$[0].body_json.payload.pull_request.number" == 7
