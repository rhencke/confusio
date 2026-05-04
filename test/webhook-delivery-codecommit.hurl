# CodeCommit webhook delivery tests.
#
# CodeCommit payloads are identified from the body. These fixtures cover native
# repository triggers, SNS notification envelopes, and EventBridge state changes.

# -- CodeCommit trigger record -> create -------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/create-record.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "create"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].body_json.ref" == "feature"
jsonpath "$[0].body_json.ref_type" == "branch"
jsonpath "$[0].body_json.master_branch" == "main"
jsonpath "$[0].body_json.repository.full_name" == "hello-world"
jsonpath "$[0].body_json.sender.login" == "frank"

# -- EventBridge referenceCreated -> create ----------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/create-eventbridge.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "create"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "v2.0.0"
jsonpath "$[0].body_json.ref_type" == "tag"
jsonpath "$[0].body_json.repository.clone_url" == "https://git-codecommit.us-east-1.amazonaws.com/v1/repos/hello-world"
jsonpath "$[0].body_json.sender.login" == "grace"

# -- SNS Notification envelope -> create -------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/create-sns.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "create"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "sns-feature"
jsonpath "$[0].body_json.ref_type" == "branch"
jsonpath "$[0].body_json.sender.login" == "heidi"

# -- CodeCommit trigger record -> push ---------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/push-record.json;
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
jsonpath "$[0].body_json.repository.full_name" == "hello-world"
jsonpath "$[0].body_json.repository.owner.login" == "123456789012"
jsonpath "$[0].body_json.sender.login" == "alice"

# -- SNS Notification envelope -> push ---------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/push-sns.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "push"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "refs/heads/dev"
jsonpath "$[0].body_json.before" == "2222222222222222222222222222222222222222"
jsonpath "$[0].body_json.after" == "3333333333333333333333333333333333333333"
jsonpath "$[0].body_json.sender.login" == "bob"

# -- SNS Notification envelope containing EventBridge -> push ----------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/push-sns-eventbridge.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "push"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "refs/heads/release"
jsonpath "$[0].body_json.before" == "4444444444444444444444444444444444444444"
jsonpath "$[0].body_json.after" == "5555555555555555555555555555555555555555"
jsonpath "$[0].body_json.sender.login" == "dana"

# -- Lambda-style SNS record envelope containing EventBridge -> push ----------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/push-sns-record.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "push"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "refs/tags/v1.2.3"
jsonpath "$[0].body_json.before" == "5555555555555555555555555555555555555555"
jsonpath "$[0].body_json.after" == "6666666666666666666666666666666666666666"
jsonpath "$[0].body_json.sender.login" == "erin"

# -- EventBridge repository state change -> push -----------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/push-eventbridge.json;
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
jsonpath "$[0].body_json.before" == "3333333333333333333333333333333333333333"
jsonpath "$[0].body_json.after" == "4444444444444444444444444444444444444444"
jsonpath "$[0].body_json.repository.clone_url" == "https://git-codecommit.us-east-1.amazonaws.com/v1/repos/hello-world"
jsonpath "$[0].body_json.sender.login" == "carol"

# -- CodeCommit trigger record -> delete -------------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/delete-record.json;
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
jsonpath "$[0].body_json.repository.full_name" == "hello-world"
jsonpath "$[0].body_json.sender.login" == "ivan"

# -- EventBridge referenceDeleted -> delete ----------------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/delete-eventbridge.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "delete"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "v2.0.0"
jsonpath "$[0].body_json.ref_type" == "tag"
jsonpath "$[0].body_json.repository.clone_url" == "https://git-codecommit.us-east-1.amazonaws.com/v1/repos/hello-world"
jsonpath "$[0].body_json.sender.login" == "judy"

# -- SNS Notification envelope containing EventBridge -> delete --------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/delete-sns-eventbridge.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "delete"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.ref" == "sns-feature"
jsonpath "$[0].body_json.ref_type" == "branch"
jsonpath "$[0].body_json.sender.login" == "kate"

# -- EventBridge pullRequestCreated -> pull_request opened -------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/pull_request-opened.json;
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
jsonpath "$[0].body_json.pull_request.number" == 42
jsonpath "$[0].body_json.pull_request.state" == "open"
jsonpath "$[0].body_json.pull_request.title" == "Add webhook parser"
jsonpath "$[0].body_json.pull_request.head.ref" == "webhook-parser"
jsonpath "$[0].body_json.pull_request.head.sha" == "2222222222222222222222222222222222222222"
jsonpath "$[0].body_json.pull_request.base.ref" == "main"
jsonpath "$[0].body_json.repository.full_name" == "hello-world"
jsonpath "$[0].body_json.sender.login" == "mallory"

# -- EventBridge pullRequestSourceBranchUpdated -> synchronize ---------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/pull_request-synchronize.json;
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
jsonpath "$[0].body_json.number" == 42
jsonpath "$[0].body_json.pull_request.head.sha" == "3333333333333333333333333333333333333333"
jsonpath "$[0].body_json.sender.login" == "nancy"

# -- EventBridge pullRequestStatusChanged -> closed --------------------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/pull_request-closed.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "pull_request"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "closed"
jsonpath "$[0].body_json.pull_request.state" == "closed"
jsonpath "$[0].body_json.pull_request.merged" == false
jsonpath "$[0].body_json.sender.login" == "oscar"

# -- EventBridge pullRequestMergeStatusUpdated -> closed merged --------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/pull_request-merged.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "pull_request"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "closed"
jsonpath "$[0].body_json.pull_request.state" == "closed"
jsonpath "$[0].body_json.pull_request.merged" == true
jsonpath "$[0].body_json.pull_request.merge_commit_sha" == "4444444444444444444444444444444444444444"
jsonpath "$[0].body_json.sender.login" == "peggy"

# -- SNS Notification envelope containing pull request update ----------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/pull_request-sns.json;
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
jsonpath "$[0].body_json.pull_request.head.sha" == "5555555555555555555555555555555555555555"
jsonpath "$[0].body_json.sender.login" == "quinn"

# -- EventBridge commentOnCommitCreated -> commit_comment created ------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/commit_comment-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "commit_comment"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "created"
jsonpath "$[0].body_json.comment.node_id" == "commit-comment-created"
jsonpath "$[0].body_json.comment.body" == "This commit comment came from CodeCommit."
jsonpath "$[0].body_json.comment.commit_id" == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
jsonpath "$[0].body_json.repository.full_name" == "hello-world"
jsonpath "$[0].body_json.sender.login" == "ruth"

# -- EventBridge commentOnCommitUpdated -> commit_comment edited -------------

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/commit_comment-edited.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "commit_comment"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "edited"
jsonpath "$[0].body_json.comment.node_id" == "commit-comment-edited"
jsonpath "$[0].body_json.comment.body" == "This CodeCommit commit comment was edited."
jsonpath "$[0].body_json.comment.commit_id" == "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
jsonpath "$[0].body_json.sender.login" == "sybil"

# -- EventBridge commentOnPullRequestCreated -> PR review comment created ----

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/pull_request_review_comment-created.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "pull_request_review_comment"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "created"
jsonpath "$[0].body_json.comment.node_id" == "pr-comment-created"
jsonpath "$[0].body_json.comment.body" == "This pull request comment came from CodeCommit."
jsonpath "$[0].body_json.pull_request.number" == 42
jsonpath "$[0].body_json.repository.full_name" == "hello-world"
jsonpath "$[0].body_json.sender.login" == "trent"

# -- EventBridge commentOnPullRequestUpdated -> PR review comment edited -----

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/pull_request_review_comment-edited.json;
HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "pull_request_review_comment"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].body_json.action" == "edited"
jsonpath "$[0].body_json.comment.node_id" == "pr-comment-edited"
jsonpath "$[0].body_json.comment.body" == "This CodeCommit pull request comment was edited."
jsonpath "$[0].body_json.pull_request.number" == 42
jsonpath "$[0].body_json.sender.login" == "ursula"

# -- EventBridge commentReactionCreated has no GitHub webhook equivalent -----

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/commit_comment-reaction-created.json;
HTTP 422
[Asserts]
jsonpath "$.message" == "CodeCommit comment reaction events have no GitHub webhook equivalent"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 0

# -- EventBridge commentReactionUpdated has no GitHub webhook equivalent -----

POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
file,fixtures/webhooks/codecommit/commit_comment-reaction-edited.json;
HTTP 422
[Asserts]
jsonpath "$.message" == "CodeCommit comment reaction events have no GitHub webhook equivalent"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "$" count == 0
