# Sourcehut webhook delivery tests.
#
# Sourcehut GraphQL webhook payloads embed the native event name in the JSON
# body, so no event-type header is required.  These fixtures cover the native
# sourcehut events translated by the backend and verify github-shaped fanout.

# -- REPO_CREATED -> repository: created -------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/repository-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "repository"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.action" == "created"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"
jsonpath "$[0].body_json.sender.login" == "octocat"

# -- REPO_UPDATE -> repository: edited ---------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/repository-edited.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "repository"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "edited"
jsonpath "$[0].body_json.repository.description" == "Updated description"

# -- REPO_DELETED -> repository: deleted -------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/repository-deleted.json;
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

# -- GIT_POST_RECEIVE branch create -> create --------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/create.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "create"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "feature"
jsonpath "$[0].body_json.ref_type" == "branch"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"

# -- GIT_POST_RECEIVE branch delete -> delete --------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/delete.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "delete"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "feature"
jsonpath "$[0].body_json.ref_type" == "branch"

# -- GIT_POST_RECEIVE ref update -> push -------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/push.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "push"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "refs/heads/main"
jsonpath "$[0].body_json.before" == "abc123def456abc123def456abc123def456abcd"
jsonpath "$[0].body_json.after" == "def456abc123def456abc123def456abc123def4"
jsonpath "$[0].body_json.commits[0].id" == "def456abc123def456abc123def456abc123def4"

# -- GIT_PRE_RECEIVE ref update -> push --------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/push-pre_receive.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "push"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "refs/heads/main"
jsonpath "$[0].body_json.after" == "def456abc123def456abc123def456abc123def4"

# -- TICKET_CREATED -> issues: opened ----------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/issues-opened.json;
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
jsonpath "$[0].body_json.issue.number" == 1
jsonpath "$[0].body_json.issue.title" == "Found a bug"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"

# -- EVENT_CREATED ticket creation -> issues: opened -------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/issues-opened-event_created.json;
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
jsonpath "$[0].body_json.issue.number" == 2
jsonpath "$[0].body_json.issue.title" == "New ticket from activity stream"

# -- TICKET_UPDATE -> issues: edited -----------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/issues-edited.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "issues"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "edited"
jsonpath "$[0].body_json.issue.title" == "Found a bug (updated)"

# -- TICKET_DELETED -> issues: deleted ---------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/issues-deleted.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "issues"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "deleted"
jsonpath "$[0].body_json.issue.number" == 1

# -- EVENT_CREATED comment -> issue_comment: created -------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/issue_comment-created.json;
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
jsonpath "$[0].body_json.issue.number" == 1
jsonpath "$[0].body_json.comment.body" == "I can reproduce this."

# -- EVENT_CREATED label added -> issues: labeled ----------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/issues-labeled.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "issues"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "labeled"
jsonpath "$[0].body_json.label.name" == "bug"

# -- EVENT_CREATED label removed -> issues: unlabeled ------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/issues-unlabeled.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "issues"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "unlabeled"
jsonpath "$[0].body_json.label.name" == "bug"

# -- EVENT_CREATED status resolved -> issues: closed -------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/issues-closed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "issues"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "closed"
jsonpath "$[0].body_json.issue.state" == "closed"

# -- EVENT_CREATED status reopened -> issues: reopened -----------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/issues-reopened.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "issues"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "reopened"
jsonpath "$[0].body_json.issue.state" == "open"

# -- EVENT_CREATED assigned user -> issues: assigned -------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/issues-assigned.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "issues"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "assigned"
jsonpath "$[0].body_json.assignee.login" == "bob"

# -- EVENT_CREATED unassigned user -> issues: unassigned ---------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/issues-unassigned.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "issues"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "unassigned"
jsonpath "$[0].body_json.assignee.login" == "bob"

# -- LABEL_CREATED -> label: created -----------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/label-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "label"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "created"
jsonpath "$[0].body_json.label.name" == "bug"
jsonpath "$[0].body_json.repository.full_name" == "octocat/hello-world"

# -- LABEL_UPDATE -> label: edited ------------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/label-edited.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "label"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "edited"
jsonpath "$[0].body_json.label.color" == "0075ca"

# -- LABEL_DELETED -> label: deleted ----------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/label-deleted.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "label"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "deleted"
jsonpath "$[0].body_json.label.name" == "bug"

# -- JOB_CREATED -> workflow_run: requested ----------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/workflow_run-requested.json;
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
jsonpath "$[0].body_json.workflow_run.name" == "ci/test"
jsonpath "$[0].body_json.workflow_run.status" == "queued"

# -- JOB_UPDATED running -> workflow_run: in_progress ------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/workflow_run-in_progress.json;
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
jsonpath "$[0].body_json.workflow_run.status" == "in_progress"

# -- JOB_UPDATED success -> workflow_run: completed --------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/workflow_run-completed.json;
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
jsonpath "$[0].body_json.workflow_run.status" == "completed"
jsonpath "$[0].body_json.workflow_run.conclusion" == "success"

# -- PATCHSET_RECEIVED -> pull_request: opened -------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
file,fixtures/webhooks/sourcehut/pull_request-opened.json;
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
jsonpath "$[0].body_json.pull_request.title" == "Add feature"
jsonpath "$[0].body_json.pull_request.base.ref" == "main"
