# Pages API assertions — stub defaults (no native support on any backend).
# All endpoints return 501 except the builds list which returns [].

# GET /repos/{owner}/{repo}/pages — not supported
GET http://{{host}}/repos/octocat/hello-world/pages
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/pages/builds — no builds (empty list)
GET http://{{host}}/repos/octocat/hello-world/pages/builds
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# POST /repos/{owner}/{repo}/pages — not supported
POST http://{{host}}/repos/octocat/hello-world/pages
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
jsonpath "$.message" isString

# PUT /repos/{owner}/{repo}/pages — not supported
PUT http://{{host}}/repos/octocat/hello-world/pages
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
jsonpath "$.message" isString

# DELETE /repos/{owner}/{repo}/pages — not supported
DELETE http://{{host}}/repos/octocat/hello-world/pages
Authorization: token testtoken

HTTP 501
[Asserts]
jsonpath "$.message" isString

# POST /repos/{owner}/{repo}/pages/builds — not supported
POST http://{{host}}/repos/octocat/hello-world/pages/builds
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/pages/builds/latest — not supported
GET http://{{host}}/repos/octocat/hello-world/pages/builds/latest
Authorization: token testtoken

HTTP 501
[Asserts]
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/pages/builds/{build_id} — not supported
GET http://{{host}}/repos/octocat/hello-world/pages/builds/1
Authorization: token testtoken

HTTP 501
[Asserts]
jsonpath "$.message" isString

# POST /repos/{owner}/{repo}/pages/deployments — not supported
POST http://{{host}}/repos/octocat/hello-world/pages/deployments
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/pages/deployments/{deployment_id} — not supported
GET http://{{host}}/repos/octocat/hello-world/pages/deployments/1
Authorization: token testtoken

HTTP 501
[Asserts]
jsonpath "$.message" isString

# POST /repos/{owner}/{repo}/pages/deployments/{deployment_id}/cancel — not supported
POST http://{{host}}/repos/octocat/hello-world/pages/deployments/1/cancel
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/pages/health — not supported
GET http://{{host}}/repos/octocat/hello-world/pages/health
Authorization: token testtoken

HTTP 501
[Asserts]
jsonpath "$.message" isString
