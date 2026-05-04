# Confusio-to-confusio inbound delivery tests — normalized shape.
#
# A normalized inbound envelope should stay normalized after fanout while using a
# fresh delivery id for the outbound attempt.

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/confusio
Content-Type: application/json
X-Confusio-Event: push
file,fixtures/webhooks/confusio/push.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "push"
jsonpath "$[0].confusio_source" == "confusio"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.id" isString
jsonpath "$[0].body_json.type" == "push"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T12:00:00Z"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.ref" == "refs/heads/main"
jsonpath "$[0].body_json.payload.after" == "2222222222222222222222222222222222222222"
