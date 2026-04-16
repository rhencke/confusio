# GraphQL API — Bitbucket Cloud backend.
# Tests for Query root fields and resolvers backed by the Bitbucket REST API v2.
# Bitbucket-specific: workspaces as orgs, no releases/labels, email always empty,
# PR reviews from participants, primary language only.

# POST /graphql — __typename on the Query root is always resolved
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ __typename }"}

HTTP 200
[Asserts]
jsonpath "$.data.__typename" == "Query"

# POST /graphql — parse error returns {"data":null,"errors":[...]}
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ unclosed_brace"}

HTTP 200
[Asserts]
jsonpath "$.data" == null
jsonpath "$.errors" isCollection

# POST /graphql — Query.viewer returns the authenticated user
POST http://{{host}}/graphql
Authorization: Basic dGVzdHRva2VuOg==
Content-Type: application/json
{"query": "{ viewer { login name isViewer } }"}

HTTP 200
[Asserts]
jsonpath "$.data.viewer.login" == "octocat"
jsonpath "$.data.viewer.name" == "Octocat"
jsonpath "$.data.viewer.isViewer" == true

# POST /graphql — Query.user returns a user by login
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ user(login: \"octocat\") { login name } }"}

HTTP 200
[Asserts]
jsonpath "$.data.user.login" == "octocat"
jsonpath "$.data.user.name" == "The Octocat"

# POST /graphql — Query.organization returns a workspace as an Organization
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ organization(login: \"octocat\") { login name } }"}

HTTP 200
[Asserts]
jsonpath "$.data.organization.login" == "octocat"
jsonpath "$.data.organization.name" == "Octocat"

# POST /graphql — Query.repository returns a repository by owner and name
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { name nameWithOwner description } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.name" == "hello-world"
jsonpath "$.data.repository.nameWithOwner" == "octocat/hello-world"
jsonpath "$.data.repository.description" == "My first repo"

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

# POST /graphql — Repository.owner is inlined by the translator (no sub-resolver)
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { owner { login } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.owner.login" == "octocat"

# POST /graphql — Repository.defaultBranchRef enriches the inline stub with commit SHA
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { defaultBranchRef { name target { oid } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.defaultBranchRef.name" == "main"
jsonpath "$.data.repository.defaultBranchRef.target.oid" == "abc123def456"

# POST /graphql — Repository.languages returns a LanguageConnection (primary only)
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { languages { totalCount nodes { name } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.languages.totalCount" == 1
jsonpath "$.data.repository.languages.nodes" isCollection
jsonpath "$.data.repository.languages.nodes[0].name" == "JavaScript"

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

# POST /graphql — Repository.milestones returns a MilestoneConnection
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { milestones { nodes { title state } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.milestones.nodes" isCollection
jsonpath "$.data.repository.milestones.nodes[0].title" == "v1.0"
jsonpath "$.data.repository.milestones.nodes[0].state" == "OPEN"

# POST /graphql — Repository.refs returns a RefConnection (branches)
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { refs { nodes { name target { oid } } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.refs.nodes" isCollection
jsonpath "$.data.repository.refs.nodes[0].name" == "main"
jsonpath "$.data.repository.refs.nodes[0].target.oid" == "abc123def456"

# POST /graphql — Issue.comments returns an IssueCommentConnection
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { issues { nodes { number comments { nodes { body author { login } } } } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.issues.nodes[0].number" == 1
jsonpath "$.data.repository.issues.nodes[0].comments.nodes" isCollection
jsonpath "$.data.repository.issues.nodes[0].comments.nodes[0].body" == "This is a comment"
jsonpath "$.data.repository.issues.nodes[0].comments.nodes[0].author.login" == "octocat"

# POST /graphql — PullRequest.commits returns a PullRequestCommitConnection
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { pullRequests { nodes { number commits { nodes { commit { oid } } } } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.pullRequests.nodes[0].number" == 1
jsonpath "$.data.repository.pullRequests.nodes[0].commits.nodes" isCollection
jsonpath "$.data.repository.pullRequests.nodes[0].commits.nodes[0].commit.oid" == "abc123def456"

# POST /graphql — PullRequest.reviews returns a PullRequestReviewConnection
# Bitbucket reviews are synthesized from PR participants with role=REVIEWER.
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { pullRequests { nodes { number reviews { nodes { state author { login } } } } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.pullRequests.nodes[0].number" == 1
jsonpath "$.data.repository.pullRequests.nodes[0].reviews.nodes" isCollection
jsonpath "$.data.repository.pullRequests.nodes[0].reviews.nodes[0].state" == "APPROVED"
jsonpath "$.data.repository.pullRequests.nodes[0].reviews.nodes[0].author.login" == "octocat"

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
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ search(query: \"octocat\", type: USER, first: 5) { userCount nodes { ... on User { login } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.search.userCount" == 1
jsonpath "$.data.search.nodes" isCollection
jsonpath "$.data.search.nodes[0].login" == "octocat"
