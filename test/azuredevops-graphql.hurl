# GraphQL API — Azure DevOps backend.
# ADO scope: Query.repository only; no viewer (no GET /user), no issues
# (Work Items are a fundamentally different model).

# POST /graphql — __typename on the Query root is always resolved
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ __typename }"}

HTTP 200
[Asserts]
jsonpath "$.data.__typename" == "Query"

# POST /graphql — Query.repository returns a repository by owner and name
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { name nameWithOwner description } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.name" == "hello-world"
jsonpath "$.data.repository.nameWithOwner" == "octocat/hello-world"
jsonpath "$.data.repository.description" == "Test project"

# POST /graphql — Repository.owner is inlined by the translator (no sub-resolver)
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { owner { login } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.owner.login" == "octocat"

# POST /graphql — Repository scalar fields
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { isPrivate isFork isArchived defaultBranchRef { name } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.isPrivate" == false
jsonpath "$.data.repository.isFork" == false
jsonpath "$.data.repository.isArchived" == false
jsonpath "$.data.repository.defaultBranchRef.name" == "main"

# POST /graphql — Query.viewer is not resolved (ADO has no GET /user)
# When no Query.viewer resolver is registered, the GraphQL executor returns
# null for the field. EncodeJson drops nil keys, so viewer is absent.
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ viewer { login } }"}

HTTP 200
[Asserts]
jsonpath "$.data.viewer" not exists
