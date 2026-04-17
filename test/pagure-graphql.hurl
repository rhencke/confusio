# GraphQL API — Pagure backend.
# Pagure scope: Query.viewer, Query.user, Query.repository,
# Repository.issues, Repository.refs, Issue.comments, Query.search.
# No pull requests, reviews, releases, or labels (Pagure has no equivalent APIs).

# POST /graphql — __typename on the Query root is always resolved
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ __typename }"}

HTTP 200
[Asserts]
jsonpath "$.data.__typename" == "Query"

# POST /graphql — Query.viewer returns the authenticated user
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "{ viewer { login name isViewer } }"}

HTTP 200
[Asserts]
jsonpath "$.data.viewer.login" == "octocat"
jsonpath "$.data.viewer.name" == "The Octocat"
jsonpath "$.data.viewer.isViewer" == true

# POST /graphql — Query.user returns a user by login
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ user(login: \"octocat\") { login name } }"}

HTTP 200
[Asserts]
jsonpath "$.data.user.login" == "octocat"
jsonpath "$.data.user.name" == "The Octocat"

# POST /graphql — Query.repository returns a repository by owner and name
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { name nameWithOwner description } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.name" == "hello-world"
jsonpath "$.data.repository.nameWithOwner" == "octocat/hello-world"
jsonpath "$.data.repository.description" == "My first repo"

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

# POST /graphql — node(Repository) fetches a repository by encoded node ID
# Node ID for Repository:octocat/hello-world = UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ node(id: \"UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk\") { ... on Repository { name nameWithOwner } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.node.name" == "hello-world"
jsonpath "$.data.node.nameWithOwner" == "octocat/hello-world"

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

# POST /graphql — Issue.comments returns embedded comments
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { issues { nodes { number comments { nodes { body author { login } } } } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.issues.nodes[0].number" == 1
jsonpath "$.data.repository.issues.nodes[0].comments.nodes" isCollection
jsonpath "$.data.repository.issues.nodes[0].comments.nodes[0].body" == "This is a comment"
jsonpath "$.data.repository.issues.nodes[0].comments.nodes[0].author.login" == "octocat"

# POST /graphql — node(IssueComment) fetches a comment by encoded node ID
# Node ID for IssueComment:octocat/hello-world/1/1 = SXNzdWVDb21tZW50Om9jdG9jYXQvaGVsbG8td29ybGQvMS8x
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ node(id: \"SXNzdWVDb21tZW50Om9jdG9jYXQvaGVsbG8td29ybGQvMS8x\") { ... on IssueComment { body author { login } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.node.body" == "This is a comment"
jsonpath "$.data.node.author.login" == "octocat"

# POST /graphql — Repository.refs returns a RefConnection (branches)
# Pagure branch list has no commit SHAs; target is absent.
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { refs { nodes { name } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.refs.nodes" isCollection
jsonpath "$.data.repository.refs.nodes[0].name" == "main"

# POST /graphql — Query.search REPOSITORY returns a SearchResultItemConnection
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ search(query: \"hello\", type: REPOSITORY, first: 5) { repositoryCount nodes { ... on Repository { name nameWithOwner } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.search.repositoryCount" == 1
jsonpath "$.data.search.nodes" isCollection
jsonpath "$.data.search.nodes[0].name" == "hello-world"
jsonpath "$.data.search.nodes[0].nameWithOwner" == "octocat/hello-world"

# POST /graphql — Query.search USER returns a SearchResultItemConnection
# Pagure /users returns login names only; no full profile is fetched per result.
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ search(query: \"octocat\", type: USER, first: 5) { userCount nodes { ... on User { login } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.search.userCount" == 1
jsonpath "$.data.search.nodes" isCollection
jsonpath "$.data.search.nodes[0].login" == "octocat"
