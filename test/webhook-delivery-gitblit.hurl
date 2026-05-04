# Gitblit webhook delivery tests.
#
# Gitblit embeds the event type in the JSON body as "event": "post-receive".
# Ref commands are normalized to the matching GitHub event family.

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
jsonpath "$[0].github_event" == "push"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.ref" == "refs/heads/main"
jsonpath "$[0].body_json.before" == "6dcb09b5b57875f334f61aebed695e2e4193db5e"
jsonpath "$[0].body_json.after" == "f1d2d2f924e986ac86fdf7b36c94bcdf32beec15"
jsonpath "$[0].body_json.head_commit.id" == "f1d2d2f924e986ac86fdf7b36c94bcdf32beec15"

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
jsonpath "$[0].github_event" == "create"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "feature-branch"
jsonpath "$[0].body_json.ref_type" == "branch"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"

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
jsonpath "$[0].github_event" == "delete"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "stale-branch"
jsonpath "$[0].body_json.ref_type" == "branch"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
