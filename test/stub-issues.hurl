# Issues API — no native support; list endpoints return [], individual → 404.

# GET /repos/{owner}/{repo}/issues → []
GET http://{{host}}/repos/octocat/hello-world/issues

HTTP 200
[Asserts]
body == "[]"

# GET /repos/{owner}/{repo}/issues/{issue_number} → 404
GET http://{{host}}/repos/octocat/hello-world/issues/1

HTTP 404

# POST /repos/{owner}/{repo}/issues → 404
POST http://{{host}}/repos/octocat/hello-world/issues
Content-Type: application/json
{"title": "Bug"}

HTTP 404
