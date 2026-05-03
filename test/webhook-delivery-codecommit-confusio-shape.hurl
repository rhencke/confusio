# CodeCommit webhook delivery test — "confusio" shape variant.
#
# Spot-checks CodeCommit's normalized envelope for body-derived push events.

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/push-record.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "push"
jsonpath "$[0].confusio_source" == "codecommit"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "push"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T12:00:00.000+0000"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.repository.full_name" == "hello-world"
jsonpath "$[0].body_json.payload.ref" == "refs/heads/main"
jsonpath "$[0].body_json.payload.after" == "2222222222222222222222222222222222222222"
