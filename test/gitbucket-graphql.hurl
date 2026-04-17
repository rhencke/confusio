# GraphQL API — GitBucket backend.
# Tests for Query root fields and resolvers backed by the GitBucket REST API.
# GitBucket is GitHub-compatible (/api/v3), so responses pass through to the
# shared graphql_translate_* helpers without intermediate REST translators.

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
Authorization: token testtoken
Content-Type: application/json
{"query": "{ viewer { login name email isViewer isSiteAdmin } }"}

HTTP 200
[Asserts]
jsonpath "$.data.viewer.login" == "octocat"
jsonpath "$.data.viewer.name" == "The Octocat"
jsonpath "$.data.viewer.email" == "octocat@github.com"
jsonpath "$.data.viewer.isViewer" == true
jsonpath "$.data.viewer.isSiteAdmin" == false

# POST /graphql — Query.user returns a user by login
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ user(login: \"octocat\") { login name } }"}

HTTP 200
[Asserts]
jsonpath "$.data.user.login" == "octocat"
jsonpath "$.data.user.name" == "The Octocat"

# POST /graphql — Query.organization returns an organization by login
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ organization(login: \"testorg\") { login name description } }"}

HTTP 200
[Asserts]
jsonpath "$.data.organization.login" == "testorg"
jsonpath "$.data.organization.name" == "Test Organization"
jsonpath "$.data.organization.description" == "A test org"

# POST /graphql — Query.repository returns a repository by owner and name
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { name nameWithOwner description } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.name" == "hello-world"
jsonpath "$.data.repository.nameWithOwner" == "octocat/hello-world"
jsonpath "$.data.repository.description" == "My first repo"

# POST /graphql — node(Release) fetches a release by encoded node ID
# Node ID for Release:octocat/hello-world/1 = UmVsZWFzZTpvY3RvY2F0L2hlbGxvLXdvcmxkLzE=
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ node(id: \"UmVsZWFzZTpvY3RvY2F0L2hlbGxvLXdvcmxkLzE=\") { ... on Release { tagName name isDraft isPrerelease } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.node.tagName" == "v1.0"
jsonpath "$.data.node.name" == "Release 1.0"
jsonpath "$.data.node.isDraft" == false
jsonpath "$.data.node.isPrerelease" == false

# POST /graphql — node(Label) fetches a label by encoded node ID
# Node ID for Label:octocat/hello-world/1 = TGFiZWw6b2N0b2NhdC9oZWxsby13b3JsZC8x
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ node(id: \"TGFiZWw6b2N0b2NhdC9oZWxsby13b3JsZC8x\") { ... on Label { name color } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.node.name" == "bug"
jsonpath "$.data.node.color" == "d73a4a"

# POST /graphql — node(Milestone) fetches a milestone by encoded node ID
# Node ID for Milestone:octocat/hello-world/1 = TWlsZXN0b25lOm9jdG9jYXQvaGVsbG8td29ybGQvMQ==
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ node(id: \"TWlsZXN0b25lOm9jdG9jYXQvaGVsbG8td29ybGQvMQ==\") { ... on Milestone { title state } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.node.title" == "v1.0"
jsonpath "$.data.node.state" == "OPEN"

# POST /graphql — node(Commit) fetches a commit by encoded node ID
# Node ID for Commit:octocat/hello-world/abc123 = Q29tbWl0Om9jdG9jYXQvaGVsbG8td29ybGQvYWJjMTIz
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ node(id: \"Q29tbWl0Om9jdG9jYXQvaGVsbG8td29ybGQvYWJjMTIz\") { ... on Commit { oid message } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.node.oid" == "abc123def456"
jsonpath "$.data.node.message" == "Initial commit"

# POST /graphql — node(Ref) fetches a branch ref by encoded node ID
# Node ID for Ref:octocat/hello-world/refs/heads/main = UmVmOm9jdG9jYXQvaGVsbG8td29ybGQvcmVmcy9oZWFkcy9tYWlu
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ node(id: \"UmVmOm9jdG9jYXQvaGVsbG8td29ybGQvcmVmcy9oZWFkcy9tYWlu\") { ... on Ref { name prefix } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.node.name" == "main"
jsonpath "$.data.node.prefix" == "refs/heads/"

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

# POST /graphql — Repository.languages returns a LanguageConnection
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { languages { totalCount totalSize nodes { name } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.languages.totalCount" == 2
jsonpath "$.data.repository.languages.totalSize" == 19134
jsonpath "$.data.repository.languages.nodes" isCollection

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

# POST /graphql — Repository.releases returns a ReleaseConnection
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { releases { nodes { tagName name isDraft isPrerelease } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.releases.nodes" isCollection
jsonpath "$.data.repository.releases.nodes[0].tagName" == "v1.0"
jsonpath "$.data.repository.releases.nodes[0].name" == "Release 1.0"
jsonpath "$.data.repository.releases.nodes[0].isDraft" == false
jsonpath "$.data.repository.releases.nodes[0].isPrerelease" == false

# POST /graphql — Repository.labels returns a LabelConnection
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { labels { nodes { name color } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.labels.nodes" isCollection
jsonpath "$.data.repository.labels.nodes[0].name" == "bug"
jsonpath "$.data.repository.labels.nodes[0].color" == "d73a4a"

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

# POST /graphql — Repository.collaborators returns a RepositoryCollaboratorConnection
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { collaborators { nodes { login } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.collaborators.nodes" isCollection
jsonpath "$.data.repository.collaborators.nodes[0].login" == "octocat"

# POST /graphql — PullRequest.commits returns a PullRequestCommitConnection
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { pullRequests { nodes { number commits { nodes { commit { oid message } } } } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.pullRequests.nodes[0].number" == 1
jsonpath "$.data.repository.pullRequests.nodes[0].commits.nodes" isCollection
jsonpath "$.data.repository.pullRequests.nodes[0].commits.nodes[0].commit.oid" == "abc123def456"

# POST /graphql — PullRequest.reviews returns a PullRequestReviewConnection
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { pullRequests { nodes { number reviews { nodes { state body author { login } } } } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.pullRequests.nodes[0].number" == 1
jsonpath "$.data.repository.pullRequests.nodes[0].reviews.nodes" isCollection
jsonpath "$.data.repository.pullRequests.nodes[0].reviews.nodes[0].state" == "APPROVED"
jsonpath "$.data.repository.pullRequests.nodes[0].reviews.nodes[0].body" == "LGTM"
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
