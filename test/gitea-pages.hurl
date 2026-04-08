# Pages API assertions — Gitea backend.
# Gitea has no native Pages API; confusio probes for a "gh-pages" branch to
# synthesize GET /repos/{owner}/{repo}/pages.  All write/build/deployment
# endpoints fall back to 501 pages_not_implemented.

# GET /repos/{owner}/{repo}/pages — no gh-pages branch → 404
GET http://{{host}}/repos/octocat/hello-world/pages
Authorization: token testtoken

HTTP 404

# GET /repos/{owner}/{repo}/pages — gh-pages branch exists → synthesized 200
GET http://{{host}}/repos/octocat/pages-repo/pages
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.status" == "built"
jsonpath "$.source.branch" == "gh-pages"
jsonpath "$.source.path" == "/"
jsonpath "$.public" == true
jsonpath "$.build_type" == "legacy"

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
header "Content-Type" == "application/json; charset=utf-8"
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
