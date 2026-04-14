# Pull requests API — no native support; list endpoints return [], individual → 404.

# GET /repos/{owner}/{repo}/pulls → []
GET http://{{host}}/repos/octocat/hello-world/pulls

HTTP 200
[Asserts]
body == "[]"

# GET /repos/{owner}/{repo}/pulls/{pull_number} → 404
GET http://{{host}}/repos/octocat/hello-world/pulls/1

HTTP 404

# POST /repos/{owner}/{repo}/pulls → 404
POST http://{{host}}/repos/octocat/hello-world/pulls
Content-Type: application/json
{"title": "Fix", "head": "feature", "base": "main"}

HTTP 404
