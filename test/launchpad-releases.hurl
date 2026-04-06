# Launchpad backend releases API assertions.
# Launchpad has no GitHub-compatible releases API — all release endpoints return 404.

# GET /repos/{owner}/{repo}/releases
GET http://{{host}}/repos/octocat/hello-world/releases

HTTP 404

# POST /repos/{owner}/{repo}/releases
POST http://{{host}}/repos/octocat/hello-world/releases
Content-Type: application/json
{"tag_name": "v1.0"}

HTTP 404

# GET /repos/{owner}/{repo}/releases/latest
GET http://{{host}}/repos/octocat/hello-world/releases/latest

HTTP 404

# GET /repos/{owner}/{repo}/releases/tags/{tag}
GET http://{{host}}/repos/octocat/hello-world/releases/tags/v1.0

HTTP 404

# GET /repos/{owner}/{repo}/releases/{release_id}
GET http://{{host}}/repos/octocat/hello-world/releases/1

HTTP 404

# PATCH /repos/{owner}/{repo}/releases/{release_id}
PATCH http://{{host}}/repos/octocat/hello-world/releases/1
Content-Type: application/json
{"name": "Updated"}

HTTP 404

# DELETE /repos/{owner}/{repo}/releases/{release_id}
DELETE http://{{host}}/repos/octocat/hello-world/releases/1

HTTP 404

# GET /repos/{owner}/{repo}/releases/{release_id}/assets
GET http://{{host}}/repos/octocat/hello-world/releases/1/assets

HTTP 404

# POST /repos/{owner}/{repo}/releases/{release_id}/assets
POST http://{{host}}/repos/octocat/hello-world/releases/1/assets
Content-Type: application/octet-stream
hex,deadbeef;

HTTP 404

# GET /repos/{owner}/{repo}/releases/assets/{asset_id}
GET http://{{host}}/repos/octocat/hello-world/releases/assets/1

HTTP 404

# PATCH /repos/{owner}/{repo}/releases/assets/{asset_id}
PATCH http://{{host}}/repos/octocat/hello-world/releases/assets/1
Content-Type: application/json
{"name": "updated.zip"}

HTTP 404

# DELETE /repos/{owner}/{repo}/releases/assets/{asset_id}
DELETE http://{{host}}/repos/octocat/hello-world/releases/assets/1

HTTP 404
