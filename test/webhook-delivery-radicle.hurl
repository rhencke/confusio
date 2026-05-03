# Radicle webhook delivery tests.
#
# Radicle CI adapter requests embed the event family in event_type, so no
# event-type header is required.  Ref changes map to push/create/delete, and
# patch events map to pull_request actions.

# ── push ref update -> push -------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/radicle
Content-Type: application/json
file,fixtures/webhooks/radicle/push.json;
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
jsonpath "$[0].body_json.commits[0].id" == "2222222222222222222222222222222222222222"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.sender.login" == "alice"

# ── branch create -> create -------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/radicle
Content-Type: application/json
file,fixtures/webhooks/radicle/create.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "create"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "feature/radicle-fixtures"
jsonpath "$[0].body_json.ref_type" == "branch"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.sender.login" == "alice"

# ── branch delete -> delete -------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/radicle
Content-Type: application/json
file,fixtures/webhooks/radicle/delete.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "delete"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "feature/radicle-fixtures"
jsonpath "$[0].body_json.ref_type" == "branch"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.sender.login" == "alice"

# ── tag create -> create ----------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/radicle
Content-Type: application/json
file,fixtures/webhooks/radicle/tag-create.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "create"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "v1.0.0"
jsonpath "$[0].body_json.ref_type" == "tag"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"

# ── tag delete -> delete ----------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/radicle
Content-Type: application/json
file,fixtures/webhooks/radicle/tag-delete.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "delete"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "v1.0.0"
jsonpath "$[0].body_json.ref_type" == "tag"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"

# ── patch created -> pull_request opened -----------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/radicle
Content-Type: application/json
file,fixtures/webhooks/radicle/patch-created.json;
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
jsonpath "$[0].body_json.number" == 1
jsonpath "$[0].body_json.pull_request.title" == "Add checkout flow"
jsonpath "$[0].body_json.pull_request.base.ref" == "main"

# ── patch updated -> pull_request synchronize ------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/radicle
Content-Type: application/json
file,fixtures/webhooks/radicle/patch-updated.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "pull_request"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "synchronize"
jsonpath "$[0].body_json.number" == 1
jsonpath "$[0].body_json.pull_request.head.sha" == "5555555555555555555555555555555555555555"
