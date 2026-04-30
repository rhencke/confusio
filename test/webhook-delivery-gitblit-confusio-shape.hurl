# Gitblit webhook delivery test - "confusio" shape variant.

# -- UPDATE command -> push ---------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitblit
Content-Type: application/json
file,fixtures/webhooks/gitblit/push.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "push"
jsonpath "$[0].confusio_source" == "gitblit"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "push"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T10:00:00Z"
jsonpath "$[0].body_json.actor.login" == "bob"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.ref" == "refs/heads/main"
jsonpath "$[0].body_json.payload.before" == "6dcb09b5b57875f334f61aebed695e2e4193db5e"
jsonpath "$[0].body_json.payload.after" == "f1d2d2f924e986ac86fdf7b36c94bcdf32beec15"
jsonpath "$[0].body_json.payload.head_commit.id" == "f1d2d2f924e986ac86fdf7b36c94bcdf32beec15"

# -- CREATE command -> create -------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitblit
Content-Type: application/json
file,fixtures/webhooks/gitblit/create.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "create"
jsonpath "$[0].confusio_source" == "gitblit"
jsonpath "$[0].body_json.type" == "create"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T12:00:00Z"
jsonpath "$[0].body_json.actor.login" == "bob"
jsonpath "$[0].body_json.payload.ref" == "feature-branch"
jsonpath "$[0].body_json.payload.ref_type" == "branch"

# -- DELETE command -> delete -------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitblit
Content-Type: application/json
file,fixtures/webhooks/gitblit/delete.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "delete"
jsonpath "$[0].confusio_source" == "gitblit"
jsonpath "$[0].body_json.type" == "delete"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T12:00:00Z"
jsonpath "$[0].body_json.actor.login" == "bob"
jsonpath "$[0].body_json.payload.ref" == "stale-branch"
jsonpath "$[0].body_json.payload.ref_type" == "branch"
