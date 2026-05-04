# Launchpad webhook delivery test - "confusio" shape variant.
#
# Spot-checks normalized envelope metadata across Launchpad's native event
# families.

# -- git:push:0.1 -> push -----------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/launchpad
Content-Type: application/json
X-Launchpad-Event-Type: git:push:0.1
file,fixtures/webhooks/launchpad/git-push.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "push"
jsonpath "$[0].confusio_source" == "launchpad"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "push"
jsonpath "$[0].body_json.repository.full_name" == "fido/main"
jsonpath "$[0].body_json.payload.ref" == "refs/heads/main"
jsonpath "$[0].body_json.payload.after" == "2222222222222222222222222222222222222222"

# -- bug:0.1 created -> issue.opened -----------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/launchpad
Content-Type: application/json
X-Launchpad-Event-Type: bug:0.1
file,fixtures/webhooks/launchpad/bug-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "issues"
jsonpath "$[0].confusio_source" == "launchpad"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "issue.opened"
jsonpath "$[0].body_json.repository.full_name" == "launchpad/confusio"
jsonpath "$[0].body_json.payload.issue.number" == 1234
jsonpath "$[0].body_json.payload.issue.title" == "Webhook bug"

# -- merge-proposal:0.1 created -> pull_request.opened ------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/launchpad
Content-Type: application/json
X-Launchpad-Event-Type: merge-proposal:0.1
file,fixtures/webhooks/launchpad/merge-proposal-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "pull_request"
jsonpath "$[0].confusio_source" == "launchpad"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "pull_request.opened"
jsonpath "$[0].body_json.repository.full_name" == "fido/main"
jsonpath "$[0].body_json.payload.number" == 42
jsonpath "$[0].body_json.payload.pull_request.title" == "Add the good feature"

# -- ci:build:0.1 created -> workflow.run.requested --------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/launchpad
Content-Type: application/json
X-Launchpad-Event-Type: ci:build:0.1
file,fixtures/webhooks/launchpad/ci-build-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "workflow_run"
jsonpath "$[0].confusio_source" == "launchpad"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "workflow.run.requested"
jsonpath "$[0].body_json.payload.workflow_run.id" == 77
jsonpath "$[0].body_json.payload.workflow_run.status" == "queued"

# -- archive:source-package-upload:0.1 accepted -> package.published ----------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/launchpad
Content-Type: application/json
X-Launchpad-Event-Type: archive:source-package-upload:0.1
file,fixtures/webhooks/launchpad/source-package-accepted.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].confusio_event" == "package"
jsonpath "$[0].confusio_source" == "launchpad"
jsonpath "$[0].github_event" == ""
jsonpath "$[0].body_json.type" == "package.published"
jsonpath "$[0].body_json.payload.package.name" == "confusio"
jsonpath "$[0].body_json.payload.package.package_version.name" == "1.2.3"
