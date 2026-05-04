# Launchpad webhook delivery tests.
#
# Launchpad sends the event type in X-Launchpad-Event-Type. These fixtures cover
# every currently supported native Launchpad event family and assert one outbound
# delivery with the normalized GitHub event family.

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
jsonpath "$[0].github_event" == "push"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.ref" == "refs/heads/main"
jsonpath "$[0].body_json.before" == "1111111111111111111111111111111111111111"
jsonpath "$[0].body_json.after" == "2222222222222222222222222222222222222222"
jsonpath "$[0].body_json.repository.full_name" == "fido/main"

# -- ping -> ping -------------------------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/launchpad
Content-Type: application/json
X-Launchpad-Event-Type: ping
file,fixtures/webhooks/launchpad/ping.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "ping"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.hook_id" == 42

# -- bug:0.1 created -> issues ------------------------------------------------

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
jsonpath "$[0].github_event" == "issues"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "opened"
jsonpath "$[0].body_json.issue.number" == 1234
jsonpath "$[0].body_json.issue.title" == "Webhook bug"
jsonpath "$[0].body_json.repository.full_name" == "launchpad/confusio"

# -- bug:comment:0.1 created -> issue_comment --------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/launchpad
Content-Type: application/json
X-Launchpad-Event-Type: bug:comment:0.1
file,fixtures/webhooks/launchpad/bug-comment-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "issue_comment"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "created"
jsonpath "$[0].body_json.issue.number" == 1234
jsonpath "$[0].body_json.comment.id" == 5
jsonpath "$[0].body_json.comment.body" == "Woof, found the bug."

# -- merge-proposal:0.1 created -> pull_request -------------------------------

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
jsonpath "$[0].github_event" == "pull_request"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "opened"
jsonpath "$[0].body_json.number" == 42
jsonpath "$[0].body_json.pull_request.title" == "Add the good feature"
jsonpath "$[0].body_json.pull_request.head.repo.full_name" == "fido/feature"
jsonpath "$[0].body_json.pull_request.base.repo.full_name" == "fido/main"

# -- ci:build:0.1 created -> workflow_run -------------------------------------

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
jsonpath "$[0].github_event" == "workflow_run"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "requested"
jsonpath "$[0].body_json.workflow_run.id" == 77
jsonpath "$[0].body_json.workflow_run.status" == "queued"
jsonpath "$[0].body_json.workflow_run.head_sha" == "3333333333333333333333333333333333333333"

# -- livefs:build:0.1 building -> workflow_run --------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/launchpad
Content-Type: application/json
X-Launchpad-Event-Type: livefs:build:0.1
file,fixtures/webhooks/launchpad/livefs-build-building.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "workflow_run"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "in_progress"
jsonpath "$[0].body_json.workflow_run.id" == 87
jsonpath "$[0].body_json.workflow_run.status" == "in_progress"

# -- snap:build:0.1 success -> workflow_run -----------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/launchpad
Content-Type: application/json
X-Launchpad-Event-Type: snap:build:0.1
file,fixtures/webhooks/launchpad/snap-build-success.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "workflow_run"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "completed"
jsonpath "$[0].body_json.workflow_run.id" == 88
jsonpath "$[0].body_json.workflow_run.conclusion" == "success"

# -- ocirecipe:build:0.1 cancelled -> workflow_run ----------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/launchpad
Content-Type: application/json
X-Launchpad-Event-Type: ocirecipe:build:0.1
file,fixtures/webhooks/launchpad/ocirecipe-build-cancelled.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "workflow_run"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "completed"
jsonpath "$[0].body_json.workflow_run.id" == 89
jsonpath "$[0].body_json.workflow_run.conclusion" == "cancelled"

# -- archive:binary-build:0.1 failed -> workflow_run --------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/launchpad
Content-Type: application/json
X-Launchpad-Event-Type: archive:binary-build:0.1
file,fixtures/webhooks/launchpad/archive-binary-build-failed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "workflow_run"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "completed"
jsonpath "$[0].body_json.workflow_run.id" == 99
jsonpath "$[0].body_json.workflow_run.conclusion" == "failure"

# -- archive:source-package-upload:0.1 accepted -> package --------------------

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
jsonpath "$[0].github_event" == "package"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "published"
jsonpath "$[0].body_json.package.name" == "confusio"
jsonpath "$[0].body_json.package.package_version.name" == "1.2.3"

# -- archive:binary-package-upload:0.1 rejected -> package --------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/launchpad
Content-Type: application/json
X-Launchpad-Event-Type: archive:binary-package-upload:0.1
file,fixtures/webhooks/launchpad/binary-package-rejected.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "package"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "updated"
jsonpath "$[0].body_json.package.name" == "confusio"
jsonpath "$[0].body_json.package.package_version.metadata.status" == "Rejected"
