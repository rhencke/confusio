# Kallithea webhook delivery tests.
#
# Kallithea embeds the event type in the JSON body, so no event-type header is
# required.  The receiver normalizes ref, repository, and pull request hooks to
# GitHub event families before delivery.

# ── PUSH_HOOK update -> push -------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/kallithea
Content-Type: application/json
file,fixtures/webhooks/kallithea/push.json;
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
jsonpath "$[0].body_json.hook" == "PUSH_HOOK"
jsonpath "$[0].body_json.refs[0].ref" == "refs/heads/main"

# ── PUSH_HOOK create -> create ----------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/kallithea
Content-Type: application/json
file,fixtures/webhooks/kallithea/create.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "create"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.refs[0].name" == "feature-branch"

# ── PUSH_HOOK delete -> delete ----------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/kallithea
Content-Type: application/json
file,fixtures/webhooks/kallithea/delete.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "delete"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.pushed_revs[0]" == "delete_branch=>stale-branch"

# ── CREATE_REPO_HOOK -> repository created ----------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/kallithea
Content-Type: application/json
file,fixtures/webhooks/kallithea/repository-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "repository"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.hook" == "CREATE_REPO_HOOK"
jsonpath "$[0].body_json.action" == "created"

# ── DELETE_REPO_HOOK -> repository deleted ----------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/kallithea
Content-Type: application/json
file,fixtures/webhooks/kallithea/repository-deleted.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "repository"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.hook" == "DELETE_REPO_HOOK"
jsonpath "$[0].body_json.action" == "deleted"

# ── CREATE_PULLREQUEST_HOOK -> pull_request opened --------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/kallithea
Content-Type: application/json
file,fixtures/webhooks/kallithea/pull_request-opened.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "pull_request"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.hook" == "CREATE_PULLREQUEST_HOOK"
jsonpath "$[0].body_json.pull_request.id" == 7
