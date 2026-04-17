# GraphQL mutation integration tests — require authentication.
# Run via test/test-integration.sh when GITEA_TOKEN is set.
#
# Tests are self-cleaning: any resource created in this file is deleted
# before the file exits so repeated runs leave gitea.com in a clean state.
#
# Required hurl variable:
#   gitea_token — Gitea personal access token with write:repository scope.
#
# The token is forwarded by test-integration.sh via --variable gitea_token=...
# when the GITEA_TOKEN environment variable is present.

# POST /graphql — authenticated mutation: __typename resolves on Mutation root.
# This is the baseline check: confirms auth works and mutations can execute.
POST http://{{host}}/graphql
Authorization: token {{gitea_token}}
Content-Type: application/json
{"query": "mutation { __typename }"}

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.data.__typename" == "Mutation"
jsonpath "$.errors" not exists

# -----------------------------------------------------------------------
# Repository mutation round-trip: createRepository → updateRepository
#
# The repo is kept alive for the issue/comment tests below and deleted
# at the very end of this file.  Uses a fixed repo name; if a prior
# failed run left it behind, manually delete confusio-mutation-test
# from your gitea.com account and re-run.
# -----------------------------------------------------------------------

# POST /graphql — createRepository: create a public test repo for the authenticated user
POST http://{{host}}/graphql
Authorization: token {{gitea_token}}
Content-Type: application/json
{"query": "mutation { createRepository(input: { name: \"confusio-mutation-test\", visibility: PUBLIC, description: \"Temporary confusio integration test repo\" }) { repository { id name nameWithOwner description visibility isPrivate } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.createRepository.repository.name" == "confusio-mutation-test"
jsonpath "$.data.createRepository.repository.nameWithOwner" isString
jsonpath "$.data.createRepository.repository.description" == "Temporary confusio integration test repo"
jsonpath "$.data.createRepository.repository.visibility" == "PUBLIC"
jsonpath "$.data.createRepository.repository.isPrivate" == false
jsonpath "$.data.createRepository.clientMutationId" not exists
[Captures]
repo_id: jsonpath "$.data.createRepository.repository.id"

# POST /graphql — updateRepository: update description and verify clientMutationId echo
POST http://{{host}}/graphql
Authorization: token {{gitea_token}}
Content-Type: application/json
{"query": "mutation UpdateRepo($id: ID!) { updateRepository(input: { repositoryId: $id, description: \"Updated by confusio integration test\", clientMutationId: \"repo-update-relay-1\" }) { repository { name description } clientMutationId } }", "variables": {"id": "{{repo_id}}"}}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.updateRepository.repository.name" == "confusio-mutation-test"
jsonpath "$.data.updateRepository.repository.description" == "Updated by confusio integration test"
jsonpath "$.data.updateRepository.clientMutationId" == "repo-update-relay-1"

# -----------------------------------------------------------------------
# Issue and comment mutation round-trip
#
# All resources live inside confusio-mutation-test; they are cleaned up
# when the repo is deleted at the end of this file.
# -----------------------------------------------------------------------

# POST /graphql — createIssue: open an issue in the test repo
POST http://{{host}}/graphql
Authorization: token {{gitea_token}}
Content-Type: application/json
{"query": "mutation CreateIssue($rid: ID!) { createIssue(input: { repositoryId: $rid, title: \"confusio integration test issue\", body: \"This issue was created by the confusio integration test suite.\" }) { issue { id number title body state } clientMutationId } }", "variables": {"rid": "{{repo_id}}"}}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.createIssue.issue.title" == "confusio integration test issue"
jsonpath "$.data.createIssue.issue.body" isString
jsonpath "$.data.createIssue.issue.state" == "OPEN"
jsonpath "$.data.createIssue.issue.number" isInteger
jsonpath "$.data.createIssue.clientMutationId" not exists
[Captures]
issue_id: jsonpath "$.data.createIssue.issue.id"

# POST /graphql — updateIssue: update title and echo clientMutationId
POST http://{{host}}/graphql
Authorization: token {{gitea_token}}
Content-Type: application/json
{"query": "mutation UpdateIssue($id: ID!) { updateIssue(input: { id: $id, title: \"confusio integration test issue (updated)\", clientMutationId: \"issue-update-relay-1\" }) { issue { title state } clientMutationId } }", "variables": {"id": "{{issue_id}}"}}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.updateIssue.issue.title" == "confusio integration test issue (updated)"
jsonpath "$.data.updateIssue.issue.state" == "OPEN"
jsonpath "$.data.updateIssue.clientMutationId" == "issue-update-relay-1"

# POST /graphql — addComment: add a comment to the issue
POST http://{{host}}/graphql
Authorization: token {{gitea_token}}
Content-Type: application/json
{"query": "mutation AddComment($sid: ID!) { addComment(input: { subjectId: $sid, body: \"confusio integration test comment\" }) { commentEdge { node { id body } } clientMutationId } }", "variables": {"sid": "{{issue_id}}"}}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.addComment.commentEdge.node.body" == "confusio integration test comment"
jsonpath "$.data.addComment.commentEdge.node.id" isString
jsonpath "$.data.addComment.clientMutationId" not exists
[Captures]
comment_id: jsonpath "$.data.addComment.commentEdge.node.id"

# POST /graphql — updateIssueComment: update the comment body and echo clientMutationId
POST http://{{host}}/graphql
Authorization: token {{gitea_token}}
Content-Type: application/json
{"query": "mutation UpdateComment($cid: ID!) { updateIssueComment(input: { id: $cid, body: \"confusio integration test comment (updated)\", clientMutationId: \"comment-update-relay-1\" }) { issueComment { body } clientMutationId } }", "variables": {"cid": "{{comment_id}}"}}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.updateIssueComment.issueComment.body" == "confusio integration test comment (updated)"
jsonpath "$.data.updateIssueComment.clientMutationId" == "comment-update-relay-1"

# POST /graphql — deleteIssueComment: delete the comment (tests delete path; issue cleaned up with repo)
POST http://{{host}}/graphql
Authorization: token {{gitea_token}}
Content-Type: application/json
{"query": "mutation DeleteComment($cid: ID!) { deleteIssueComment(input: { id: $cid }) { clientMutationId } }", "variables": {"cid": "{{comment_id}}"}}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists

# POST /graphql — closeIssue: close the test issue
POST http://{{host}}/graphql
Authorization: token {{gitea_token}}
Content-Type: application/json
{"query": "mutation CloseIssue($id: ID!) { closeIssue(input: { issueId: $id, clientMutationId: \"close-relay-1\" }) { issue { state } clientMutationId } }", "variables": {"id": "{{issue_id}}"}}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.closeIssue.issue.state" == "CLOSED"
jsonpath "$.data.closeIssue.clientMutationId" == "close-relay-1"

# POST /graphql — reopenIssue: reopen to verify the round-trip completes
POST http://{{host}}/graphql
Authorization: token {{gitea_token}}
Content-Type: application/json
{"query": "mutation ReopenIssue($id: ID!) { reopenIssue(input: { issueId: $id }) { issue { state } clientMutationId } }", "variables": {"id": "{{issue_id}}"}}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.reopenIssue.issue.state" == "OPEN"
jsonpath "$.data.reopenIssue.clientMutationId" not exists

# -----------------------------------------------------------------------
# Label mutation round-trip: createLabel → addLabelsToLabelable
#
# Label is created inside the test repo and added to the test issue.
# Both are cleaned up automatically when the repo is deleted at the end.
# -----------------------------------------------------------------------

# POST /graphql — createLabel: create a label in the test repo
POST http://{{host}}/graphql
Authorization: token {{gitea_token}}
Content-Type: application/json
{"query": "mutation CreateLabel($rid: ID!) { createLabel(input: { repositoryId: $rid, name: \"confusio-test\", color: \"0075ca\", description: \"confusio integration test label\", clientMutationId: \"label-create-relay-1\" }) { label { id name color } clientMutationId } }", "variables": {"rid": "{{repo_id}}"}}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.createLabel.label.name" == "confusio-test"
jsonpath "$.data.createLabel.label.color" isString
jsonpath "$.data.createLabel.label.id" isString
jsonpath "$.data.createLabel.clientMutationId" == "label-create-relay-1"
[Captures]
label_id: jsonpath "$.data.createLabel.label.id"

# POST /graphql — addLabelsToLabelable: attach the new label to the test issue
POST http://{{host}}/graphql
Authorization: token {{gitea_token}}
Content-Type: application/json
{"query": "mutation AddLabel($lid: ID!, $iid: ID!) { addLabelsToLabelable(input: { labelableId: $iid, labelIds: [$lid] }) { labelable { ... on Issue { number title } } clientMutationId } }", "variables": {"lid": "{{label_id}}", "iid": "{{issue_id}}"}}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.addLabelsToLabelable.labelable.number" isInteger
jsonpath "$.data.addLabelsToLabelable.clientMutationId" not exists

# -----------------------------------------------------------------------
# Star mutation round-trip: addStar → removeStar
#
# Uses the test repo (repo_id).  Toggling a star on your own repo is
# allowed on gitea.com; the unstar leaves the state clean.
# -----------------------------------------------------------------------

# POST /graphql — addStar: star the test repo
POST http://{{host}}/graphql
Authorization: token {{gitea_token}}
Content-Type: application/json
{"query": "mutation AddStar($id: ID!) { addStar(input: { starrableId: $id, clientMutationId: \"star-add-relay-1\" }) { starrable { ... on Repository { name } } clientMutationId } }", "variables": {"id": "{{repo_id}}"}}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.addStar.starrable.name" == "confusio-mutation-test"
jsonpath "$.data.addStar.clientMutationId" == "star-add-relay-1"

# POST /graphql — removeStar: unstar the test repo (restores state)
POST http://{{host}}/graphql
Authorization: token {{gitea_token}}
Content-Type: application/json
{"query": "mutation RemoveStar($id: ID!) { removeStar(input: { starrableId: $id }) { starrable { ... on Repository { name } } clientMutationId } }", "variables": {"id": "{{repo_id}}"}}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.removeStar.starrable.name" == "confusio-mutation-test"
jsonpath "$.data.removeStar.clientMutationId" not exists

# -----------------------------------------------------------------------
# Subscription mutation round-trip: updateSubscription SUBSCRIBED → UNSUBSCRIBED
#
# Subscribes to the test repo then immediately unsubscribes, leaving no
# lasting watch state on gitea.com.
# -----------------------------------------------------------------------

# POST /graphql — updateSubscription: subscribe to the test repo
POST http://{{host}}/graphql
Authorization: token {{gitea_token}}
Content-Type: application/json
{"query": "mutation Subscribe($id: ID!) { updateSubscription(input: { subscribableId: $id, state: SUBSCRIBED, clientMutationId: \"sub-relay-1\" }) { subscribable { ... on Repository { name } } clientMutationId } }", "variables": {"id": "{{repo_id}}"}}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.updateSubscription.subscribable.name" == "confusio-mutation-test"
jsonpath "$.data.updateSubscription.clientMutationId" == "sub-relay-1"

# POST /graphql — updateSubscription: unsubscribe (restores state)
POST http://{{host}}/graphql
Authorization: token {{gitea_token}}
Content-Type: application/json
{"query": "mutation Unsubscribe($id: ID!) { updateSubscription(input: { subscribableId: $id, state: UNSUBSCRIBED }) { subscribable { ... on Repository { name } } clientMutationId } }", "variables": {"id": "{{repo_id}}"}}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.updateSubscription.subscribable.name" == "confusio-mutation-test"
jsonpath "$.data.updateSubscription.clientMutationId" not exists

# -----------------------------------------------------------------------
# Cleanup: delete the test repo (cascades to all issues and comments)
# -----------------------------------------------------------------------

# POST /graphql — deleteRepository: clean up the test repo (self-cleaning)
POST http://{{host}}/graphql
Authorization: token {{gitea_token}}
Content-Type: application/json
{"query": "mutation DeleteRepo($id: ID!) { deleteRepository(input: { repositoryId: $id }) { clientMutationId } }", "variables": {"id": "{{repo_id}}"}}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
