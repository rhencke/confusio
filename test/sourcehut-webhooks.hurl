# Sourcehut webhook normalizer tests.
#
# Sourcehut embeds the event name in the JSON body. Trust-the-network mode is
# used here, so X-Payload-Signature is omitted.

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/repository-created.json;

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/repository-edited.json;

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/repository-deleted.json;

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/create.json;

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/delete.json;

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/push.json;

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/push-pre_receive.json;

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/issues-opened.json;

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/issues-opened-event_created.json;

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/issues-edited.json;

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/issues-deleted.json;

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/issue_comment-created.json;

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/issues-labeled.json;

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/issues-unlabeled.json;

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/issues-closed.json;

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/issues-reopened.json;

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/issues-assigned.json;

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/issues-unassigned.json;

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/label-created.json;

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/label-edited.json;

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/label-deleted.json;

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/workflow_run-requested.json;

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/workflow_run-in_progress.json;

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/workflow_run-completed.json;

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/pull_request-opened.json;

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"
