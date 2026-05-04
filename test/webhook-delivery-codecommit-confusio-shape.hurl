# CodeCommit webhook delivery test — "confusio" shape variant.
#
# Spot-checks CodeCommit's normalized envelope for body-derived ref events.

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/create-eventbridge.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "create"
jsonpath "$[0].confusio_source" == "codecommit"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "create"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T12:06:00Z"
jsonpath "$[0].body_json.actor.login" == "grace"
jsonpath "$[0].body_json.repository.full_name" == "hello-world"
jsonpath "$[0].body_json.payload.ref" == "v2.0.0"
jsonpath "$[0].body_json.payload.ref_type" == "tag"

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/pull_request_review-submitted.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "pull_request_review"
jsonpath "$[0].confusio_source" == "codecommit"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "pull_request.review.submitted"
jsonpath "$[0].body_json.actor.login" == "xavier"
jsonpath "$[0].body_json.payload.review.state" == "approved"
jsonpath "$[0].body_json.payload.pull_request.number" == 42

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/branch_protection_rule-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "branch_protection_rule"
jsonpath "$[0].confusio_source" == "codecommit"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "branch_protection_rule.created"
jsonpath "$[0].body_json.actor.login" == "zara"
jsonpath "$[0].body_json.payload.rule.node_id" == "rule-created"
jsonpath "$[0].body_json.payload.rule.codecommit.pull_request_id" == "42"

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/pull_request_review_comment-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "pull_request_review_comment"
jsonpath "$[0].confusio_source" == "codecommit"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "pull_request.review_comment.created"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T14:10:00Z"
jsonpath "$[0].body_json.actor.login" == "trent"
jsonpath "$[0].body_json.repository.full_name" == "hello-world"
jsonpath "$[0].body_json.payload.action" == "created"
jsonpath "$[0].body_json.payload.comment.node_id" == "pr-comment-created"
jsonpath "$[0].body_json.payload.pull_request.number" == 42

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/pull_request-opened.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "codecommit"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "pull_request.opened"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T13:00:00Z"
jsonpath "$[0].body_json.actor.login" == "mallory"
jsonpath "$[0].body_json.repository.full_name" == "hello-world"
jsonpath "$[0].body_json.payload.action" == "opened"
jsonpath "$[0].body_json.payload.pull_request.number" == 42
jsonpath "$[0].body_json.payload.pull_request.head.ref" == "webhook-parser"

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

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/delete-eventbridge.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "delete"
jsonpath "$[0].confusio_source" == "codecommit"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "delete"
jsonpath "$[0].body_json.occurred_at" == "2024-01-15T12:09:00Z"
jsonpath "$[0].body_json.actor.login" == "judy"
jsonpath "$[0].body_json.repository.full_name" == "hello-world"
jsonpath "$[0].body_json.payload.ref" == "v2.0.0"
jsonpath "$[0].body_json.payload.ref_type" == "tag"
