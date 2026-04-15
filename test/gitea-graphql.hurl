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
