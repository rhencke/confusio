# Confusio-to-confusio inbound delivery tests — GitHub shape.
#
# Confusio receives its own normalized envelope, verifies the normalized event
# header/body pairing, and can emit GitHub-compatible payloads where the payload
# carries GitHub-compatible fields.

# -- push normalized envelope -> GitHub push ---------------------------------

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
jsonpath "$[0].github_event" == "push"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.ref" == "refs/heads/main"
jsonpath "$[0].body_json.before" == "1111111111111111111111111111111111111111"
jsonpath "$[0].body_json.after" == "2222222222222222222222222222222222222222"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.sender.login" == "alice"
jsonpath "$[0].body_json.head_commit.id" == "2222222222222222222222222222222222222222"

# -- issue.opened normalized envelope -> GitHub issues/opened ----------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/confusio
Content-Type: application/json
X-Confusio-Event: issues
file,fixtures/webhooks/confusio/issue-opened.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "issues"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "opened"
jsonpath "$[0].body_json.issue.number" == 7
jsonpath "$[0].body_json.issue.title" == "Normalized issue"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.sender.login" == "bob"

# -- mismatched header/body event is rejected --------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/confusio
Content-Type: application/json
X-Confusio-Event: issues
file,fixtures/webhooks/confusio/push.json;
HTTP 422
[Asserts]
jsonpath "$.message" == "Confusio event header/body mismatch"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 0
