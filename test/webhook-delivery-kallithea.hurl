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
jsonpath "$[0].body_json.ref" == "refs/heads/main"
jsonpath "$[0].body_json.before" == "95790bf891e76fee5db5ef17d2523a6f6e048239"
jsonpath "$[0].body_json.after" == "5a1e9f3d7c2b4a6e8f90123456789abcdef01234"
jsonpath "$[0].body_json.head_commit.id" == "5a1e9f3d7c2b4a6e8f90123456789abcdef01234"

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
jsonpath "$[0].body_json.ref" == "feature-branch"
jsonpath "$[0].body_json.ref_type" == "branch"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"

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
jsonpath "$[0].body_json.ref" == "stale-branch"
jsonpath "$[0].body_json.ref_type" == "branch"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"

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
jsonpath "$[0].body_json.action" == "created"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"

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
jsonpath "$[0].body_json.action" == "deleted"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"

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
jsonpath "$[0].body_json.action" == "opened"
jsonpath "$[0].body_json.number" == 7
jsonpath "$[0].body_json.pull_request.id" == 7
jsonpath "$[0].body_json.pull_request.title" == "Add webhook fixtures"
