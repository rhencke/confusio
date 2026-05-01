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
jsonpath "$[0].body_json.action" == "pushed"

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
jsonpath "$[0].body_json.bug" == "/bugs/1234"

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
jsonpath "$[0].body_json.bug_comment" == "/bugs/1234/comments/5"

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
jsonpath "$[0].body_json.merge_proposal" == "/~fido/confusio/+git/feature/+merge/42"

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
jsonpath "$[0].body_json.build" == "/~fido/confusio/+git/main/+build/77"

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
jsonpath "$[0].body_json.status" == "Currently building"

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
jsonpath "$[0].body_json.status" == "Successfully built"

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
jsonpath "$[0].body_json.status" == "Cancelled build"

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
jsonpath "$[0].body_json.source_package_name" == "confusio"

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
jsonpath "$[0].body_json.package_name" == "confusio"

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
jsonpath "$[0].body_json.source_package_name" == "confusio"
