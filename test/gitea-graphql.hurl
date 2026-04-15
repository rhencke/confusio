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
