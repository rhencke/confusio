# RhodeCode webhook delivery tests.
#
# RhodeCode integration webhooks identify the event in the JSON body, or provide
# ref / pull request fields that let confusio infer the GitHub event family.

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
jsonpath "$[0].github_event" == "push"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.ref" == "refs/heads/main"
jsonpath "$[0].body_json.before" == "1111111111111111111111111111111111111111"
jsonpath "$[0].body_json.after" == "2222222222222222222222222222222222222222"
jsonpath "$[0].body_json.head_commit.id" == "2222222222222222222222222222222222222222"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.sender.login" == "alice"

# -- PUSH_HOOK create -> create ----------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/rhodecode
Content-Type: application/json
file,fixtures/webhooks/rhodecode/create.json;
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

# -- PUSH_HOOK delete -> delete ----------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/rhodecode
Content-Type: application/json
file,fixtures/webhooks/rhodecode/delete.json;
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

# -- CREATE_PULLREQUEST_HOOK -> pull_request opened --------------------------

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
jsonpath "$[0].github_event" == "pull_request"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "opened"
jsonpath "$[0].body_json.number" == 7
jsonpath "$[0].body_json.pull_request.title" == "Add webhook fixtures"
jsonpath "$[0].body_json.pull_request.head.repo.full_name" == "alice/hello-world"
jsonpath "$[0].body_json.pull_request.base.repo.full_name" == "octocat/hello-world"

# -- pull_request closed -> pull_request closed ------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/rhodecode
Content-Type: application/json
file,fixtures/webhooks/rhodecode/pull_request-closed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "pull_request"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "closed"
jsonpath "$[0].body_json.number" == 8
jsonpath "$[0].body_json.pull_request.state" == "closed"

# -- CREATE_REPO_HOOK -> repository created ----------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/rhodecode
Content-Type: application/json
file,fixtures/webhooks/rhodecode/repository-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "repository"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "created"
jsonpath "$[0].body_json.repository.full_name" == "octocat/new-repo"
jsonpath "$[0].body_json.repository.private" == true
