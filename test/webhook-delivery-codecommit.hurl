# CodeCommit webhook delivery tests.
#
# CodeCommit payloads are identified from the body. These fixtures cover native
# repository triggers, SNS notification envelopes, and EventBridge state changes.

# -- CodeCommit trigger record -> push ---------------------------------------

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
jsonpath "$[0].github_event" == "push"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.ref" == "refs/heads/main"
jsonpath "$[0].body_json.before" == "1111111111111111111111111111111111111111"
jsonpath "$[0].body_json.after" == "2222222222222222222222222222222222222222"
jsonpath "$[0].body_json.repository.full_name" == "hello-world"
jsonpath "$[0].body_json.repository.owner.login" == "123456789012"
jsonpath "$[0].body_json.sender.login" == "alice"

# -- SNS Notification envelope -> push ---------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/push-sns.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "push"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "refs/heads/dev"
jsonpath "$[0].body_json.before" == "2222222222222222222222222222222222222222"
jsonpath "$[0].body_json.after" == "3333333333333333333333333333333333333333"
jsonpath "$[0].body_json.sender.login" == "bob"

# -- EventBridge repository state change -> push -----------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/push-eventbridge.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "push"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "refs/heads/main"
jsonpath "$[0].body_json.before" == "3333333333333333333333333333333333333333"
jsonpath "$[0].body_json.after" == "4444444444444444444444444444444444444444"
jsonpath "$[0].body_json.repository.clone_url" == "https://git-codecommit.us-east-1.amazonaws.com/v1/repos/hello-world"
jsonpath "$[0].body_json.sender.login" == "carol"
