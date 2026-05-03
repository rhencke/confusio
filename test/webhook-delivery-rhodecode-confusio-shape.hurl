# RhodeCode webhook delivery test — "confusio" shape variant.
#
# Spot-checks normalized envelope metadata for supported RhodeCode families.

# -- PUSH_HOOK update -> push -------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/rhodecode
Content-Type: application/json
file,fixtures/webhooks/rhodecode/push.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "push"
jsonpath "$[0].confusio_source" == "rhodecode"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "push"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.ref" == "refs/heads/main"
jsonpath "$[0].body_json.payload.after" == "2222222222222222222222222222222222222222"

# -- CREATE_PULLREQUEST_HOOK -> pull_request.opened --------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/rhodecode
Content-Type: application/json
file,fixtures/webhooks/rhodecode/pull_request-opened.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "rhodecode"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "pull_request.opened"
jsonpath "$[0].body_json.payload.number" == 7
jsonpath "$[0].body_json.payload.pull_request.title" == "Add webhook fixtures"
