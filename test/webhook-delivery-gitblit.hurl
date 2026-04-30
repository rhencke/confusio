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
jsonpath "$[0].body_json.event" == "post-receive"
jsonpath "$[0].body_json.commands[0].type" == "UPDATE"

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
jsonpath "$[0].body_json.commands[0].refName" == "refs/heads/feature-branch"

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
jsonpath "$[0].body_json.commands[0].refName" == "refs/heads/stale-branch"
