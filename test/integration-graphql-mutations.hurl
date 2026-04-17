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
# Repository mutation round-trip: createRepository → updateRepository → deleteRepository
#
# Uses a fixed repo name.  If a prior failed run left the repo behind,
# delete confusio-mutation-test from your gitea.com account and re-run.
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

# POST /graphql — deleteRepository: clean up the test repo (self-cleaning)
POST http://{{host}}/graphql
Authorization: token {{gitea_token}}
Content-Type: application/json
{"query": "mutation DeleteRepo($id: ID!) { deleteRepository(input: { repositoryId: $id }) { clientMutationId } }", "variables": {"id": "{{repo_id}}"}}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
