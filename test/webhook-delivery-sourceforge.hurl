# SourceForge webhook delivery tests.
#
# SourceForge / Allura repo-push deliveries do not carry an event header.
# confusio infers repo-push from the documented ref/update fields and maps it
# to GitHub-compatible push/create/delete deliveries.

# -- repo-push ref update -> push --------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourceforge
Content-Type: application/json
file,fixtures/webhooks/sourceforge/push.json;
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
jsonpath "$[0].body_json.commits[0].id" == "2222222222222222222222222222222222222222"

# -- branch create -> create -------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourceforge
Content-Type: application/json
file,fixtures/webhooks/sourceforge/create.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "create"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "feature/sourceforge-fixtures"
jsonpath "$[0].body_json.ref_type" == "branch"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.sender.login" == "alice"

# -- branch delete -> delete -------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourceforge
Content-Type: application/json
file,fixtures/webhooks/sourceforge/delete.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "delete"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "feature/sourceforge-fixtures"
jsonpath "$[0].body_json.ref_type" == "branch"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.sender.login" == "alice"

# -- tag create -> create ----------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourceforge
Content-Type: application/json
file,fixtures/webhooks/sourceforge/tag-create.json;
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

# -- tag delete -> delete ----------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourceforge
Content-Type: application/json
file,fixtures/webhooks/sourceforge/tag-delete.json;
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
