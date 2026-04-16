# GraphQL API — Sourcehut backend.
# Sourcehut scope: Query.repository, Query.viewer, Repository.issues.
# No Query.user (no arbitrary-user lookup), no Repository.pullRequests.

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
jsonpath "$.data.repository.description" == "My first repo"

# POST /graphql — Repository.owner is inlined by the translator
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

# POST /graphql — Query.viewer returns the authenticated user
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ viewer { login name isViewer } }"}

HTTP 200
[Asserts]
jsonpath "$.data.viewer.login" == "octocat"
jsonpath "$.data.viewer.name" == "octocat"
jsonpath "$.data.viewer.isViewer" == true

# POST /graphql — Repository.issues returns an IssueConnection
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { issues { nodes { number title state } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.issues.nodes" isCollection
jsonpath "$.data.repository.issues.nodes[0].number" == 1
jsonpath "$.data.repository.issues.nodes[0].title" == "Found a bug"
jsonpath "$.data.repository.issues.nodes[0].state" == "OPEN"

# POST /graphql — node(Issue) fetches an issue by encoded node ID
# Node ID for Issue:octocat/hello-world/1 = SXNzdWU6b2N0b2NhdC9oZWxsby13b3JsZC8x
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ node(id: \"SXNzdWU6b2N0b2NhdC9oZWxsby13b3JsZC8x\") { ... on Issue { number title state } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.node.number" == 1
jsonpath "$.data.node.title" == "Found a bug"
jsonpath "$.data.node.state" == "OPEN"
