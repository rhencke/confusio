# GraphQL API — Bitbucket Data Center backend.
# BBS scope: Query.repository, Query.user, Repository.pullRequests.
# No viewer (no GET /user), no issues (BBS relies on Jira).

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
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { name nameWithOwner } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.name" == "hello-world"
jsonpath "$.data.repository.nameWithOwner" == "octocat/hello-world"

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

# POST /graphql — Query.user returns a user by login
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ user(login: \"octocat\") { login name } }"}

HTTP 200
[Asserts]
jsonpath "$.data.user.login" == "octocat"
jsonpath "$.data.user.name" == "The Octocat"

# POST /graphql — Repository.pullRequests returns a PullRequestConnection
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { pullRequests { nodes { number title state } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.pullRequests.nodes" isCollection
jsonpath "$.data.repository.pullRequests.nodes[0].number" == 1
jsonpath "$.data.repository.pullRequests.nodes[0].title" == "A great PR"
jsonpath "$.data.repository.pullRequests.nodes[0].state" == "MERGED"

# POST /graphql — node(PullRequest) fetches a PR by encoded node ID
# Node ID for PullRequest:octocat/hello-world/1 = UHVsbFJlcXVlc3Q6b2N0b2NhdC9oZWxsby13b3JsZC8x
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ node(id: \"UHVsbFJlcXVlc3Q6b2N0b2NhdC9oZWxsby13b3JsZC8x\") { ... on PullRequest { number title state } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.node.number" == 1
jsonpath "$.data.node.title" == "A great PR"
jsonpath "$.data.node.state" == "MERGED"
