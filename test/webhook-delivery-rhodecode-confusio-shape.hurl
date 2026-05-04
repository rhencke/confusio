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
jsonpath "$[0].confusio_event" == "create"
jsonpath "$[0].confusio_source" == "rhodecode"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "create"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.ref" == "feature-branch"
jsonpath "$[0].body_json.payload.ref_type" == "branch"

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
jsonpath "$[0].confusio_event" == "delete"
jsonpath "$[0].confusio_source" == "rhodecode"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "delete"
jsonpath "$[0].body_json.actor.login" == "alice"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.payload.ref" == "stale-branch"
jsonpath "$[0].body_json.payload.ref_type" == "branch"

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

# -- pull_request update -> pull_request.synchronize -------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/rhodecode
Content-Type: application/json
file,fixtures/webhooks/rhodecode/pull_request-synchronize.json;
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
jsonpath "$[0].body_json.type" == "pull_request.synchronize"
jsonpath "$[0].body_json.payload.number" == 7
jsonpath "$[0].body_json.payload.pull_request.head.sha" == "4444444444444444444444444444444444444444"

# -- pull_request closed -> pull_request.closed ------------------------------

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
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "rhodecode"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "pull_request.closed"
jsonpath "$[0].body_json.payload.number" == 8
jsonpath "$[0].body_json.payload.pull_request.state" == "closed"

# -- pull_request merged -> pull_request.closed ------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/rhodecode
Content-Type: application/json
file,fixtures/webhooks/rhodecode/pull_request-merged.json;
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
jsonpath "$[0].body_json.type" == "pull_request.closed"
jsonpath "$[0].body_json.payload.number" == 8
jsonpath "$[0].body_json.payload.pull_request.merged" == true
jsonpath "$[0].body_json.payload.pull_request.merge_commit_sha" == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

# -- pull_request reopen -> pull_request.reopened ----------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/rhodecode
Content-Type: application/json
file,fixtures/webhooks/rhodecode/pull_request-reopened.json;
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
jsonpath "$[0].body_json.type" == "pull_request.reopened"
jsonpath "$[0].body_json.payload.number" == 8
jsonpath "$[0].body_json.payload.pull_request.state" == "open"

# -- CREATE_REPO_HOOK -> repository.created ----------------------------------

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
jsonpath "$[0].confusio_event" == "repository"
jsonpath "$[0].confusio_source" == "rhodecode"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "repository.created"
jsonpath "$[0].body_json.actor.login" == "admin"
jsonpath "$[0].body_json.repository.full_name" == "octocat/new-repo"
jsonpath "$[0].body_json.payload.action" == "created"

# -- DELETE_REPO_HOOK -> repository.deleted ----------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/rhodecode
Content-Type: application/json
file,fixtures/webhooks/rhodecode/repository-deleted.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "repository"
jsonpath "$[0].confusio_source" == "rhodecode"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "repository.deleted"
jsonpath "$[0].body_json.actor.login" == "admin"
jsonpath "$[0].body_json.repository.full_name" == "octocat/old-repo"
jsonpath "$[0].body_json.payload.action" == "deleted"
