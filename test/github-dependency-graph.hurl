# Dependency Graph API — GitHub backend (webhook-only; no upstream API configured).
# All endpoints return 501.

GET http://{{host}}/repos/octocat/hello-world/dependency-graph/compare/main...feature
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString
