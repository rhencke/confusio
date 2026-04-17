# GraphQL API — Gitea backend.
# Tests for Query.viewer and other resolvers backed by the Gitea REST API.

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
{"query": "{ viewer { login name email location websiteUrl url isViewer isSiteAdmin } }"}

HTTP 200
[Asserts]
jsonpath "$.data.viewer.login" == "octocat"
jsonpath "$.data.viewer.name" == "The Octocat"
jsonpath "$.data.viewer.email" == "octocat@github.com"
jsonpath "$.data.viewer.location" == "San Francisco"
jsonpath "$.data.viewer.websiteUrl" == "https://github.blog"
jsonpath "$.data.viewer.url" == "http://localhost/octocat"
jsonpath "$.data.viewer.isViewer" == true
jsonpath "$.data.viewer.isSiteAdmin" == false

# POST /graphql — Query.user returns a user by login
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ user(login: \"octocat\") { login name email location websiteUrl url } }"}

HTTP 200
[Asserts]
jsonpath "$.data.user.login" == "octocat"
jsonpath "$.data.user.name" == "The Octocat"
jsonpath "$.data.user.email" == "octocat@github.com"
jsonpath "$.data.user.location" == "San Francisco"
jsonpath "$.data.user.websiteUrl" == "https://github.blog"
jsonpath "$.data.user.url" == "http://localhost/octocat"

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

# POST /graphql — node(Team) fetches a team by encoded node ID
# Node ID for Team:testorg/core = VGVhbTp0ZXN0b3JnL2NvcmU=
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ node(id: \"VGVhbTp0ZXN0b3JnL2NvcmU=\") { ... on Team { name slug } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.node.name" == "core"
jsonpath "$.data.node.slug" == "core"

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
jsonpath "$.data.repository.pullRequests.nodes[0].state" == "OPEN"

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

# POST /graphql — PullRequest.commits returns a CommitConnection
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { pullRequests { nodes { number commits { nodes { commit { oid } } } } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.pullRequests.nodes[0].number" == 1
jsonpath "$.data.repository.pullRequests.nodes[0].commits.nodes" isCollection

# POST /graphql — PullRequest.reviews returns a PullRequestReviewConnection
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { pullRequests { nodes { number reviews { nodes { state body author { login } } } } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.repository.pullRequests.nodes[0].number" == 1
jsonpath "$.data.repository.pullRequests.nodes[0].reviews.nodes" isCollection
jsonpath "$.data.repository.pullRequests.nodes[0].reviews.nodes[0].state" == "APPROVED"
jsonpath "$.data.repository.pullRequests.nodes[0].reviews.nodes[0].body" == "Looks good!"
jsonpath "$.data.repository.pullRequests.nodes[0].reviews.nodes[0].author.login" == "octocat"

# ---------------------------------------------------------------------------
# Backward pagination (last / before)
# ---------------------------------------------------------------------------

# POST /graphql — issues(last: 1): single-page repo; hasPreviousPage false, hasNextPage false.
# Mock returns X-Total: 1, so the two-pass resolves last_page = 1.
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { issues(last: 1) { totalCount pageInfo { hasNextPage hasPreviousPage startCursor endCursor } nodes { number } } } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.repository.issues.totalCount" == 1
jsonpath "$.data.repository.issues.pageInfo.hasNextPage" == false
jsonpath "$.data.repository.issues.pageInfo.hasPreviousPage" == false
jsonpath "$.data.repository.issues.pageInfo.startCursor" isString
jsonpath "$.data.repository.issues.nodes[0].number" == 1

# POST /graphql — issues(first: 1): capture endCursor for the before test below.
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { issues(first: 1) { pageInfo { endCursor } } } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.repository.issues.pageInfo.endCursor" isString
[Captures]
issues_page1_cursor: jsonpath "$.data.repository.issues.pageInfo.endCursor"

# POST /graphql — issues(last: 1, before: cursor(1)): nothing exists before page 1.
# hasNextPage = true (cursor page 1 exists), hasPreviousPage = false, nodes empty.
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ repository(owner: \"octocat\", name: \"hello-world\") { issues(last: 1, before: \"{{issues_page1_cursor}}\") { totalCount pageInfo { hasNextPage hasPreviousPage } nodes { number } } } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.repository.issues.totalCount" == 1
jsonpath "$.data.repository.issues.pageInfo.hasNextPage" == true
jsonpath "$.data.repository.issues.pageInfo.hasPreviousPage" == false
jsonpath "$.data.repository.issues.nodes[0]" not exists

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

# POST /graphql — Query.search ISSUE returns a SearchResultItemConnection
POST http://{{host}}/graphql
Content-Type: application/json
{"query": "{ search(query: \"bug\", type: ISSUE, first: 5) { issueCount nodes { ... on Issue { number title state } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.search.issueCount" == 1
jsonpath "$.data.search.nodes" isCollection
jsonpath "$.data.search.nodes[0].number" == 1
jsonpath "$.data.search.nodes[0].title" == "Found a bug"
jsonpath "$.data.search.nodes[0].state" == "OPEN"

# POST /graphql — Mutation.createRepository creates a repo for the authenticated user
# (no ownerId → POST /api/v1/user/repos)
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { createRepository(input: { name: \"hello-world\", visibility: PUBLIC }) { repository { name nameWithOwner description visibility isPrivate } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.createRepository.repository.name" == "hello-world"
jsonpath "$.data.createRepository.repository.nameWithOwner" == "octocat/hello-world"
jsonpath "$.data.createRepository.repository.description" == "My first repo"
jsonpath "$.data.createRepository.repository.visibility" == "PUBLIC"
jsonpath "$.data.createRepository.repository.isPrivate" == false
jsonpath "$.data.createRepository.clientMutationId" not exists

# POST /graphql — Mutation.createRepository with clientMutationId echoes it back
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { createRepository(input: { name: \"hello-world\", visibility: PUBLIC, clientMutationId: \"relay-99\" }) { repository { name } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.createRepository.repository.name" == "hello-world"
jsonpath "$.data.createRepository.clientMutationId" == "relay-99"

# POST /graphql — Mutation.createRepository with org ownerId creates under the org
# ownerId "T3JnYW5pemF0aW9uOnRlc3Rvcmc=" = base64("Organization:testorg")
# → POST /api/v1/orgs/testorg/repos
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { createRepository(input: { name: \"hello-world\", visibility: PUBLIC, ownerId: \"T3JnYW5pemF0aW9uOnRlc3Rvcmc=\" }) { repository { name nameWithOwner } } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.createRepository.repository.name" == "hello-world"
jsonpath "$.data.createRepository.repository.nameWithOwner" == "octocat/hello-world"

# POST /graphql — Mutation.createRepository creates a repo for the authenticated user
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { createRepository(input: { name: \"hello-world\", visibility: PUBLIC }) { repository { name nameWithOwner description } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.createRepository.repository.name" == "hello-world"
jsonpath "$.data.createRepository.repository.nameWithOwner" == "octocat/hello-world"
jsonpath "$.data.createRepository.repository.description" == "My first repo"
jsonpath "$.data.createRepository" exists

# POST /graphql — Mutation.createRepository echoes back clientMutationId
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { createRepository(input: { name: \"hello-world\", visibility: PUBLIC, clientMutationId: \"relay-42\" }) { repository { name } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.createRepository.repository.name" == "hello-world"
jsonpath "$.data.createRepository.clientMutationId" == "relay-42"

# POST /graphql — Mutation.createRepository with ownerId routes to org endpoint
# Node ID for Organization:testorg = T3JnYW5pemF0aW9uOnRlc3Rvcmc=
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { createRepository(input: { name: \"hello-world\", visibility: PUBLIC, ownerId: \"T3JnYW5pemF0aW9uOnRlc3Rvcmc=\" }) { repository { name nameWithOwner } } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.createRepository.repository.name" == "hello-world"
jsonpath "$.data.createRepository.repository.nameWithOwner" == "octocat/hello-world"

# POST /graphql — Mutation.createRepository without name returns BAD_USER_INPUT error
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { createRepository(input: { visibility: PUBLIC }) { repository { name } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.createRepository" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.updateRepository updates an existing repository
# Node ID for Repository:octocat/hello-world = UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { updateRepository(input: { repositoryId: \"UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk\", description: \"Updated description\" }) { repository { name nameWithOwner description } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.updateRepository.repository.name" == "hello-world"
jsonpath "$.data.updateRepository.repository.nameWithOwner" == "octocat/hello-world"
jsonpath "$.data.updateRepository.repository.description" == "My first repo"
jsonpath "$.data.updateRepository" exists

# POST /graphql — Mutation.updateRepository echoes back clientMutationId
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { updateRepository(input: { repositoryId: \"UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk\", name: \"hello-world\", clientMutationId: \"relay-99\" }) { repository { name } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.updateRepository.repository.name" == "hello-world"
jsonpath "$.data.updateRepository.clientMutationId" == "relay-99"

# POST /graphql — Mutation.updateRepository without repositoryId returns BAD_USER_INPUT error
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { updateRepository(input: { name: \"hello-world\" }) { repository { name } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.updateRepository" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.updateRepository with invalid repositoryId returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { updateRepository(input: { repositoryId: \"dXNlcjoxMjM=\" }) { repository { name } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.updateRepository" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.deleteRepository deletes a repository
# Node ID for Repository:octocat/hello-world = UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { deleteRepository(input: { repositoryId: \"UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk\" }) { clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.deleteRepository" exists

# POST /graphql — Mutation.deleteRepository echoes back clientMutationId
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { deleteRepository(input: { repositoryId: \"UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk\", clientMutationId: \"relay-del-1\" }) { clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.deleteRepository.clientMutationId" == "relay-del-1"

# POST /graphql — Mutation.deleteRepository without repositoryId returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { deleteRepository(input: {}) { clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.data.deleteRepository" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.deleteRepository with wrong node type returns BAD_USER_INPUT
# Node ID for User:octocat = VXNlcjpvY3RvY2F0
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { deleteRepository(input: { repositoryId: \"VXNlcjpvY3RvY2F0\" }) { clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.data.deleteRepository" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.createIssue creates an issue in a repository
# Node ID for Repository:octocat/hello-world = UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk
# → POST /api/v1/repos/octocat/hello-world/issues
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { createIssue(input: { repositoryId: \"UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk\", title: \"Found a bug\" }) { issue { number title state } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.createIssue.issue.number" == 1
jsonpath "$.data.createIssue.issue.title" == "Found a bug"
jsonpath "$.data.createIssue.issue.state" == "OPEN"
jsonpath "$.data.createIssue.clientMutationId" not exists

# POST /graphql — Mutation.createIssue echoes back clientMutationId
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { createIssue(input: { repositoryId: \"UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk\", title: \"Found a bug\", clientMutationId: \"issue-relay-1\" }) { issue { number } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.createIssue.issue.number" == 1
jsonpath "$.data.createIssue.clientMutationId" == "issue-relay-1"

# POST /graphql — Mutation.createIssue without repositoryId returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { createIssue(input: { title: \"Found a bug\" }) { issue { number } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.createIssue" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.createIssue without title returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { createIssue(input: { repositoryId: \"UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk\" }) { issue { number } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.createIssue" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.createIssue with wrong node type returns BAD_USER_INPUT
# Node ID for User:octocat = VXNlcjpvY3RvY2F0
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { createIssue(input: { repositoryId: \"VXNlcjpvY3RvY2F0\", title: \"Found a bug\" }) { issue { number } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.createIssue" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.updateIssue updates an issue
# Node ID for Issue:octocat/hello-world/1 = SXNzdWU6b2N0b2NhdC9oZWxsby13b3JsZC8x
# → PATCH /api/v1/repos/octocat/hello-world/issues/1
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { updateIssue(input: { id: \"SXNzdWU6b2N0b2NhdC9oZWxsby13b3JsZC8x\", title: \"Updated bug\" }) { issue { number title state } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.updateIssue.issue.number" == 1
jsonpath "$.data.updateIssue.issue.title" == "Found a bug"
jsonpath "$.data.updateIssue.issue.state" == "OPEN"
jsonpath "$.data.updateIssue.clientMutationId" not exists

# POST /graphql — Mutation.updateIssue echoes back clientMutationId
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { updateIssue(input: { id: \"SXNzdWU6b2N0b2NhdC9oZWxsby13b3JsZC8x\", clientMutationId: \"issue-relay-2\" }) { issue { number } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.updateIssue.clientMutationId" == "issue-relay-2"

# POST /graphql — Mutation.updateIssue without id returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { updateIssue(input: { title: \"foo\" }) { issue { number } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.updateIssue" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.updateIssue with wrong node type returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { updateIssue(input: { id: \"VXNlcjpvY3RvY2F0\" }) { issue { number } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.updateIssue" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.closeIssue closes an issue
# Node ID for Issue:octocat/hello-world/1 = SXNzdWU6b2N0b2NhdC9oZWxsby13b3JsZC8x
# → PATCH /api/v1/repos/octocat/hello-world/issues/1 (state=closed)
# Mock returns the ISSUE fixture unchanged (state stays "open"); tests the REST call path.
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { closeIssue(input: { issueId: \"SXNzdWU6b2N0b2NhdC9oZWxsby13b3JsZC8x\" }) { issue { number state } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.closeIssue.issue.number" == 1
jsonpath "$.data.closeIssue.issue.state" == "OPEN"
jsonpath "$.data.closeIssue.clientMutationId" not exists

# POST /graphql — Mutation.closeIssue echoes back clientMutationId
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { closeIssue(input: { issueId: \"SXNzdWU6b2N0b2NhdC9oZWxsby13b3JsZC8x\", clientMutationId: \"close-relay-1\" }) { issue { number } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.closeIssue.clientMutationId" == "close-relay-1"

# POST /graphql — Mutation.closeIssue without issueId returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { closeIssue(input: {}) { issue { number } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.closeIssue" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.reopenIssue reopens a closed issue
# → PATCH /api/v1/repos/octocat/hello-world/issues/1 (state=open)
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { reopenIssue(input: { issueId: \"SXNzdWU6b2N0b2NhdC9oZWxsby13b3JsZC8x\" }) { issue { number state } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.reopenIssue.issue.number" == 1
jsonpath "$.data.reopenIssue.issue.state" == "OPEN"
jsonpath "$.data.reopenIssue.clientMutationId" not exists

# POST /graphql — Mutation.reopenIssue echoes back clientMutationId
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { reopenIssue(input: { issueId: \"SXNzdWU6b2N0b2NhdC9oZWxsby13b3JsZC8x\", clientMutationId: \"reopen-relay-1\" }) { issue { number } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.reopenIssue.clientMutationId" == "reopen-relay-1"

# POST /graphql — Mutation.reopenIssue without issueId returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { reopenIssue(input: {}) { issue { number } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.reopenIssue" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.createPullRequest creates a pull request
# Node ID for Repository:octocat/hello-world = UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk
# → POST /api/v1/repos/octocat/hello-world/pulls
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { createPullRequest(input: { repositoryId: \"UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk\", title: \"A great PR\", headRefName: \"feature\", baseRefName: \"main\" }) { pullRequest { number title state headRefName baseRefName } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.createPullRequest.pullRequest.number" == 1
jsonpath "$.data.createPullRequest.pullRequest.title" == "A great PR"
jsonpath "$.data.createPullRequest.pullRequest.state" == "OPEN"
jsonpath "$.data.createPullRequest.pullRequest.headRefName" == "feature"
jsonpath "$.data.createPullRequest.pullRequest.baseRefName" == "main"
jsonpath "$.data.createPullRequest.clientMutationId" not exists

# POST /graphql — Mutation.createPullRequest echoes back clientMutationId
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { createPullRequest(input: { repositoryId: \"UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk\", title: \"A great PR\", headRefName: \"feature\", baseRefName: \"main\", clientMutationId: \"pr-relay-1\" }) { pullRequest { number } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.createPullRequest.pullRequest.number" == 1
jsonpath "$.data.createPullRequest.clientMutationId" == "pr-relay-1"

# POST /graphql — Mutation.createPullRequest without repositoryId returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { createPullRequest(input: { title: \"A great PR\", headRefName: \"feature\", baseRefName: \"main\" }) { pullRequest { number } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.createPullRequest" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.createPullRequest without title returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { createPullRequest(input: { repositoryId: \"UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk\", headRefName: \"feature\", baseRefName: \"main\" }) { pullRequest { number } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.createPullRequest" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.createPullRequest with wrong node type returns BAD_USER_INPUT
# Node ID for User:octocat = VXNlcjpvY3RvY2F0
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { createPullRequest(input: { repositoryId: \"VXNlcjpvY3RvY2F0\", title: \"A great PR\", headRefName: \"feature\", baseRefName: \"main\" }) { pullRequest { number } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.createPullRequest" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.updatePullRequest updates a pull request
# Node ID for PullRequest:octocat/hello-world/1 = UHVsbFJlcXVlc3Q6b2N0b2NhdC9oZWxsby13b3JsZC8x
# → PATCH /api/v1/repos/octocat/hello-world/pulls/1
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { updatePullRequest(input: { pullRequestId: \"UHVsbFJlcXVlc3Q6b2N0b2NhdC9oZWxsby13b3JsZC8x\", title: \"Updated PR\" }) { pullRequest { number title state } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.updatePullRequest.pullRequest.number" == 1
jsonpath "$.data.updatePullRequest.pullRequest.title" == "A great PR"
jsonpath "$.data.updatePullRequest.pullRequest.state" == "OPEN"
jsonpath "$.data.updatePullRequest.clientMutationId" not exists

# POST /graphql — Mutation.updatePullRequest echoes back clientMutationId
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { updatePullRequest(input: { pullRequestId: \"UHVsbFJlcXVlc3Q6b2N0b2NhdC9oZWxsby13b3JsZC8x\", clientMutationId: \"pr-relay-2\" }) { pullRequest { number } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.updatePullRequest.clientMutationId" == "pr-relay-2"

# POST /graphql — Mutation.updatePullRequest without pullRequestId returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { updatePullRequest(input: { title: \"Updated PR\" }) { pullRequest { number } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.updatePullRequest" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.updatePullRequest with wrong node type returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { updatePullRequest(input: { pullRequestId: \"VXNlcjpvY3RvY2F0\" }) { pullRequest { number } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.updatePullRequest" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.closePullRequest closes a pull request
# → PATCH /api/v1/repos/octocat/hello-world/pulls/1 (state=closed)
# Mock returns the PR fixture unchanged (state stays "open"); tests the REST call path.
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { closePullRequest(input: { pullRequestId: \"UHVsbFJlcXVlc3Q6b2N0b2NhdC9oZWxsby13b3JsZC8x\" }) { pullRequest { number state } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.closePullRequest.pullRequest.number" == 1
jsonpath "$.data.closePullRequest.pullRequest.state" == "OPEN"
jsonpath "$.data.closePullRequest.clientMutationId" not exists

# POST /graphql — Mutation.closePullRequest echoes back clientMutationId
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { closePullRequest(input: { pullRequestId: \"UHVsbFJlcXVlc3Q6b2N0b2NhdC9oZWxsby13b3JsZC8x\", clientMutationId: \"close-pr-relay-1\" }) { pullRequest { number } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.closePullRequest.clientMutationId" == "close-pr-relay-1"

# POST /graphql — Mutation.closePullRequest without pullRequestId returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { closePullRequest(input: {}) { pullRequest { number } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.closePullRequest" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.reopenPullRequest reopens a closed pull request
# → PATCH /api/v1/repos/octocat/hello-world/pulls/1 (state=open)
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { reopenPullRequest(input: { pullRequestId: \"UHVsbFJlcXVlc3Q6b2N0b2NhdC9oZWxsby13b3JsZC8x\" }) { pullRequest { number state } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.reopenPullRequest.pullRequest.number" == 1
jsonpath "$.data.reopenPullRequest.pullRequest.state" == "OPEN"
jsonpath "$.data.reopenPullRequest.clientMutationId" not exists

# POST /graphql — Mutation.reopenPullRequest echoes back clientMutationId
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { reopenPullRequest(input: { pullRequestId: \"UHVsbFJlcXVlc3Q6b2N0b2NhdC9oZWxsby13b3JsZC8x\", clientMutationId: \"reopen-pr-relay-1\" }) { pullRequest { number } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.reopenPullRequest.clientMutationId" == "reopen-pr-relay-1"

# POST /graphql — Mutation.reopenPullRequest without pullRequestId returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { reopenPullRequest(input: {}) { pullRequest { number } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.reopenPullRequest" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.mergePullRequest merges a pull request
# → POST /api/v1/repos/octocat/hello-world/pulls/1/merge (Gitea uses POST; returns 204)
# → GET /api/v1/repos/octocat/hello-world/pulls/1 (re-fetch; mock returns open PR)
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { mergePullRequest(input: { pullRequestId: \"UHVsbFJlcXVlc3Q6b2N0b2NhdC9oZWxsby13b3JsZC8x\" }) { pullRequest { number state } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.mergePullRequest.pullRequest.number" == 1
jsonpath "$.data.mergePullRequest.pullRequest.state" == "OPEN"
jsonpath "$.data.mergePullRequest.clientMutationId" not exists

# POST /graphql — Mutation.mergePullRequest echoes back clientMutationId
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { mergePullRequest(input: { pullRequestId: \"UHVsbFJlcXVlc3Q6b2N0b2NhdC9oZWxsby13b3JsZC8x\", clientMutationId: \"merge-pr-relay-1\" }) { pullRequest { number } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.mergePullRequest.clientMutationId" == "merge-pr-relay-1"

# POST /graphql — Mutation.mergePullRequest without pullRequestId returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { mergePullRequest(input: {}) { pullRequest { number } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.mergePullRequest" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.addComment adds a comment to an issue
# Node ID for Issue:octocat/hello-world/1 = SXNzdWU6b2N0b2NhdC9oZWxsby13b3JsZC8x
# → POST /api/v1/repos/octocat/hello-world/issues/1/comments
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { addComment(input: { subjectId: \"SXNzdWU6b2N0b2NhdC9oZWxsby13b3JsZC8x\", body: \"This is a comment\" }) { commentEdge { node { body } } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.addComment.commentEdge.node.body" == "This is a comment"
jsonpath "$.data.addComment.clientMutationId" not exists

# POST /graphql — Mutation.addComment with PullRequest subjectId uses the /issues/{n}/comments path
# Node ID for PullRequest:octocat/hello-world/1 = UHVsbFJlcXVlc3Q6b2N0b2NhdC9oZWxsby13b3JsZC8x
# → POST /api/v1/repos/octocat/hello-world/issues/1/comments (same path as issues)
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { addComment(input: { subjectId: \"UHVsbFJlcXVlc3Q6b2N0b2NhdC9oZWxsby13b3JsZC8x\", body: \"This is a comment\" }) { commentEdge { node { body } } } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.addComment.commentEdge.node.body" == "This is a comment"

# POST /graphql — Mutation.addComment echoes back clientMutationId
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { addComment(input: { subjectId: \"SXNzdWU6b2N0b2NhdC9oZWxsby13b3JsZC8x\", body: \"This is a comment\", clientMutationId: \"comment-relay-1\" }) { commentEdge { node { body } } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.addComment.commentEdge.node.body" == "This is a comment"
jsonpath "$.data.addComment.clientMutationId" == "comment-relay-1"

# POST /graphql — Mutation.addComment without subjectId returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { addComment(input: { body: \"This is a comment\" }) { commentEdge { node { body } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.addComment" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.addComment with wrong node type returns BAD_USER_INPUT
# Node ID for User:octocat = VXNlcjpvY3RvY2F0
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { addComment(input: { subjectId: \"VXNlcjpvY3RvY2F0\", body: \"This is a comment\" }) { commentEdge { node { body } } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.addComment" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.updateIssueComment updates a comment
# Node ID for IssueComment:octocat/hello-world/1 = SXNzdWVDb21tZW50Om9jdG9jYXQvaGVsbG8td29ybGQvMQ==
# → PATCH /api/v1/repos/octocat/hello-world/issues/comments/1
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { updateIssueComment(input: { id: \"SXNzdWVDb21tZW50Om9jdG9jYXQvaGVsbG8td29ybGQvMQ==\", body: \"Updated comment\" }) { issueComment { body } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.updateIssueComment.issueComment.body" == "This is a comment"
jsonpath "$.data.updateIssueComment.clientMutationId" not exists

# POST /graphql — Mutation.updateIssueComment echoes back clientMutationId
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { updateIssueComment(input: { id: \"SXNzdWVDb21tZW50Om9jdG9jYXQvaGVsbG8td29ybGQvMQ==\", body: \"Updated comment\", clientMutationId: \"comment-relay-2\" }) { issueComment { body } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.updateIssueComment.clientMutationId" == "comment-relay-2"

# POST /graphql — Mutation.updateIssueComment without id returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { updateIssueComment(input: { body: \"Updated comment\" }) { issueComment { body } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.updateIssueComment" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.updateIssueComment with wrong node type returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { updateIssueComment(input: { id: \"VXNlcjpvY3RvY2F0\", body: \"Updated comment\" }) { issueComment { body } } }"}

HTTP 200
[Asserts]
jsonpath "$.data.updateIssueComment" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.deleteIssueComment deletes a comment
# Node ID for IssueComment:octocat/hello-world/1 = SXNzdWVDb21tZW50Om9jdG9jYXQvaGVsbG8td29ybGQvMQ==
# → DELETE /api/v1/repos/octocat/hello-world/issues/comments/1
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { deleteIssueComment(input: { id: \"SXNzdWVDb21tZW50Om9jdG9jYXQvaGVsbG8td29ybGQvMQ==\" }) { clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.deleteIssueComment" exists
jsonpath "$.data.deleteIssueComment.clientMutationId" not exists

# POST /graphql — Mutation.deleteIssueComment echoes back clientMutationId
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { deleteIssueComment(input: { id: \"SXNzdWVDb21tZW50Om9jdG9jYXQvaGVsbG8td29ybGQvMQ==\", clientMutationId: \"comment-relay-3\" }) { clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.deleteIssueComment.clientMutationId" == "comment-relay-3"

# POST /graphql — Mutation.deleteIssueComment without id returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { deleteIssueComment(input: {}) { clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.data.deleteIssueComment" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.deleteIssueComment with wrong node type returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { deleteIssueComment(input: { id: \"VXNlcjpvY3RvY2F0\" }) { clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.data.deleteIssueComment" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.addStar stars a repository
# Node ID for Repository:octocat/hello-world = UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk
# → PUT /api/v1/user/starred/octocat/hello-world, then GET /api/v1/repos/octocat/hello-world
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { addStar(input: { starrableId: \"UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk\" }) { starrable { ... on Repository { nameWithOwner } } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.addStar.starrable.nameWithOwner" == "octocat/hello-world"
jsonpath "$.data.addStar.clientMutationId" not exists

# POST /graphql — Mutation.addStar echoes back clientMutationId
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { addStar(input: { starrableId: \"UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk\", clientMutationId: \"star-relay-1\" }) { clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.addStar.clientMutationId" == "star-relay-1"

# POST /graphql — Mutation.addStar without starrableId returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { addStar(input: {}) { clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.data.addStar" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.addStar with wrong node type returns BAD_USER_INPUT
# Node ID for User:octocat = VXNlcjpvY3RvY2F0
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { addStar(input: { starrableId: \"VXNlcjpvY3RvY2F0\" }) { clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.data.addStar" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.removeStar unstars a repository
# → DELETE /api/v1/user/starred/octocat/hello-world, then GET /api/v1/repos/octocat/hello-world
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { removeStar(input: { starrableId: \"UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk\" }) { starrable { ... on Repository { nameWithOwner } } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.removeStar.starrable.nameWithOwner" == "octocat/hello-world"
jsonpath "$.data.removeStar.clientMutationId" not exists

# POST /graphql — Mutation.removeStar echoes back clientMutationId
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { removeStar(input: { starrableId: \"UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk\", clientMutationId: \"star-relay-2\" }) { clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.removeStar.clientMutationId" == "star-relay-2"

# POST /graphql — Mutation.removeStar without starrableId returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { removeStar(input: {}) { clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.data.removeStar" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.removeStar with wrong node type returns BAD_USER_INPUT
# Node ID for User:octocat = VXNlcjpvY3RvY2F0
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { removeStar(input: { starrableId: \"VXNlcjpvY3RvY2F0\" }) { clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.data.removeStar" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.updateSubscription subscribes to a repository (SUBSCRIBED)
# Node ID for Repository:octocat/hello-world = UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk
# → PUT /api/v1/repos/octocat/hello-world/subscription, then GET /api/v1/repos/octocat/hello-world
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { updateSubscription(input: { subscribableId: \"UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk\", state: SUBSCRIBED }) { subscribable { ... on Repository { nameWithOwner } } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.updateSubscription.subscribable.nameWithOwner" == "octocat/hello-world"
jsonpath "$.data.updateSubscription.clientMutationId" not exists

# POST /graphql — Mutation.updateSubscription sets ignored state (IGNORED)
# → PUT /api/v1/repos/octocat/hello-world/subscription
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { updateSubscription(input: { subscribableId: \"UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk\", state: IGNORED }) { subscribable { ... on Repository { nameWithOwner } } } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.updateSubscription.subscribable.nameWithOwner" == "octocat/hello-world"

# POST /graphql — Mutation.updateSubscription unsubscribes (UNSUBSCRIBED)
# → DELETE /api/v1/repos/octocat/hello-world/subscription, then GET /api/v1/repos/octocat/hello-world
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { updateSubscription(input: { subscribableId: \"UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk\", state: UNSUBSCRIBED }) { subscribable { ... on Repository { nameWithOwner } } } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.updateSubscription.subscribable.nameWithOwner" == "octocat/hello-world"

# POST /graphql — Mutation.updateSubscription echoes back clientMutationId
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { updateSubscription(input: { subscribableId: \"UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk\", state: SUBSCRIBED, clientMutationId: \"sub-relay-1\" }) { clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.updateSubscription.clientMutationId" == "sub-relay-1"

# POST /graphql — Mutation.updateSubscription without subscribableId returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { updateSubscription(input: { state: SUBSCRIBED }) { clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.data.updateSubscription" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.updateSubscription without state returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { updateSubscription(input: { subscribableId: \"UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk\" }) { clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.data.updateSubscription" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.updateSubscription with wrong node type returns BAD_USER_INPUT
# Node ID for User:octocat = VXNlcjpvY3RvY2F0
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { updateSubscription(input: { subscribableId: \"VXNlcjpvY3RvY2F0\", state: SUBSCRIBED }) { clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.data.updateSubscription" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.createLabel creates a label in a repository
# Node ID for Repository:octocat/hello-world = UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk
# → POST /api/v1/repos/octocat/hello-world/labels
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { createLabel(input: { repositoryId: \"UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk\", name: \"bug\", color: \"d73a4a\" }) { label { name color } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.createLabel.label.name" == "bug"
jsonpath "$.data.createLabel.label.color" == "d73a4a"
jsonpath "$.data.createLabel.clientMutationId" not exists

# POST /graphql — Mutation.createLabel echoes back clientMutationId
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { createLabel(input: { repositoryId: \"UmVwb3NpdG9yeTpvY3RvY2F0L2hlbGxvLXdvcmxk\", name: \"bug\", color: \"d73a4a\", clientMutationId: \"label-relay-1\" }) { clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.createLabel.clientMutationId" == "label-relay-1"

# POST /graphql — Mutation.createLabel without repositoryId returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { createLabel(input: { name: \"bug\", color: \"d73a4a\" }) { clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.data.createLabel" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.createLabel with wrong node type returns BAD_USER_INPUT
# Node ID for User:octocat = VXNlcjpvY3RvY2F0
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { createLabel(input: { repositoryId: \"VXNlcjpvY3RvY2F0\", name: \"bug\", color: \"d73a4a\" }) { clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.data.createLabel" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.addLabelsToLabelable adds a label to an issue
# Node ID for Issue:octocat/hello-world/1 = SXNzdWU6b2N0b2NhdC9oZWxsby13b3JsZC8x
# Node ID for Label:octocat/hello-world/1 = TGFiZWw6b2N0b2NhdC9oZWxsby13b3JsZC8x
# → POST /api/v1/repos/octocat/hello-world/issues/1/labels, then GET /api/v1/repos/octocat/hello-world/issues/1
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { addLabelsToLabelable(input: { labelableId: \"SXNzdWU6b2N0b2NhdC9oZWxsby13b3JsZC8x\", labelIds: [\"TGFiZWw6b2N0b2NhdC9oZWxsby13b3JsZC8x\"] }) { labelable { ... on Issue { number title } } clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.addLabelsToLabelable.labelable.number" == 1
jsonpath "$.data.addLabelsToLabelable.labelable.title" isString
jsonpath "$.data.addLabelsToLabelable.clientMutationId" not exists

# POST /graphql — Mutation.addLabelsToLabelable echoes back clientMutationId
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { addLabelsToLabelable(input: { labelableId: \"SXNzdWU6b2N0b2NhdC9oZWxsby13b3JsZC8x\", labelIds: [\"TGFiZWw6b2N0b2NhdC9oZWxsby13b3JsZC8x\"], clientMutationId: \"label-relay-2\" }) { clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.errors" not exists
jsonpath "$.data.addLabelsToLabelable.clientMutationId" == "label-relay-2"

# POST /graphql — Mutation.addLabelsToLabelable without labelableId returns BAD_USER_INPUT
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { addLabelsToLabelable(input: { labelIds: [\"TGFiZWw6b2N0b2NhdC9oZWxsby13b3JsZC8x\"] }) { clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.data.addLabelsToLabelable" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"

# POST /graphql — Mutation.addLabelsToLabelable with wrong labelable node type returns BAD_USER_INPUT
# Node ID for User:octocat = VXNlcjpvY3RvY2F0
POST http://{{host}}/graphql
Authorization: token testtoken
Content-Type: application/json
{"query": "mutation { addLabelsToLabelable(input: { labelableId: \"VXNlcjpvY3RvY2F0\", labelIds: [\"TGFiZWw6b2N0b2NhdC9oZWxsby13b3JsZC8x\"] }) { clientMutationId } }"}

HTTP 200
[Asserts]
jsonpath "$.data.addLabelsToLabelable" not exists
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].extensions.code" == "BAD_USER_INPUT"
