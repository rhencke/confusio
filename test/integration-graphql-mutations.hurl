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
