# Reactions API assertions — Gitea backend.
# Gitea supports reactions on issues and issue comments.
# Commit comment, PR comment, and release reactions fall back to defaults.

# ── Issue reactions ────────────────────────────────────────────────────────────

# GET /repos/{owner}/{repo}/issues/{issue_number}/reactions
GET http://{{host}}/repos/octocat/hello-world/issues/1/reactions

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].id" isInteger
jsonpath "$[0].user.login" isString
jsonpath "$[0].content" == "+1"
jsonpath "$[0].created_at" isString

# POST /repos/{owner}/{repo}/issues/{issue_number}/reactions
POST http://{{host}}/repos/octocat/hello-world/issues/1/reactions
Content-Type: application/json
{"content": "+1"}

HTTP 201
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" isInteger
jsonpath "$.user.login" isString
jsonpath "$.content" == "+1"
jsonpath "$.created_at" isString

# DELETE /repos/{owner}/{repo}/issues/{issue_number}/reactions/{reaction_id}
# reaction_id 11 = user_id(1) * 10 + content_code("+1"=1)
DELETE http://{{host}}/repos/octocat/hello-world/issues/1/reactions/11

HTTP 204

# DELETE with unknown reaction_id → 404
DELETE http://{{host}}/repos/octocat/hello-world/issues/1/reactions/9999

HTTP 404

# ── Issue comment reactions ────────────────────────────────────────────────────

# GET /repos/{owner}/{repo}/issues/comments/{comment_id}/reactions
GET http://{{host}}/repos/octocat/hello-world/issues/comments/1/reactions

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].id" isInteger
jsonpath "$[0].user.login" isString
jsonpath "$[0].content" == "+1"
jsonpath "$[0].created_at" isString

# POST /repos/{owner}/{repo}/issues/comments/{comment_id}/reactions
POST http://{{host}}/repos/octocat/hello-world/issues/comments/1/reactions
Content-Type: application/json
{"content": "+1"}

HTTP 201
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" isInteger
jsonpath "$.user.login" isString
jsonpath "$.content" == "+1"

# DELETE /repos/{owner}/{repo}/issues/comments/{comment_id}/reactions/{reaction_id}
DELETE http://{{host}}/repos/octocat/hello-world/issues/comments/1/reactions/11

HTTP 204

# ── Commit comment reactions (no Gitea support — empty list / 501) ─────────────

# GET /repos/{owner}/{repo}/comments/{comment_id}/reactions
GET http://{{host}}/repos/octocat/hello-world/comments/1/reactions

HTTP 200
[Asserts]
body == "[]"

# POST /repos/{owner}/{repo}/comments/{comment_id}/reactions
POST http://{{host}}/repos/octocat/hello-world/comments/1/reactions
Content-Type: application/json
{"content": "+1"}

HTTP 501

# DELETE /repos/{owner}/{repo}/comments/{comment_id}/reactions/{reaction_id}
DELETE http://{{host}}/repos/octocat/hello-world/comments/1/reactions/1

HTTP 501

# ── PR comment reactions (no Gitea support — empty list / 501) ────────────────

# GET /repos/{owner}/{repo}/pulls/comments/{comment_id}/reactions
GET http://{{host}}/repos/octocat/hello-world/pulls/comments/1/reactions

HTTP 200
[Asserts]
body == "[]"

# POST /repos/{owner}/{repo}/pulls/comments/{comment_id}/reactions
POST http://{{host}}/repos/octocat/hello-world/pulls/comments/1/reactions
Content-Type: application/json
{"content": "+1"}

HTTP 501

# DELETE /repos/{owner}/{repo}/pulls/comments/{comment_id}/reactions/{reaction_id}
DELETE http://{{host}}/repos/octocat/hello-world/pulls/comments/1/reactions/1

HTTP 501

# ── Release reactions (no Gitea support — empty list / 501) ───────────────────

# GET /repos/{owner}/{repo}/releases/{release_id}/reactions
GET http://{{host}}/repos/octocat/hello-world/releases/1/reactions

HTTP 200
[Asserts]
body == "[]"

# POST /repos/{owner}/{repo}/releases/{release_id}/reactions
POST http://{{host}}/repos/octocat/hello-world/releases/1/reactions
Content-Type: application/json
{"content": "+1"}

HTTP 501

# DELETE /repos/{owner}/{repo}/releases/{release_id}/reactions/{reaction_id}
DELETE http://{{host}}/repos/octocat/hello-world/releases/1/reactions/1

HTTP 501
