# Reactions API — GitLab maps GitHub reactions to award emojis.
# Issues: full GET/POST/DELETE support via /award_emoji.
# All other resource types (commit comments, issue comments, PR comments,
# releases): no practical mapping — GET returns [] (200), writes return 501.

# ── Commit comment reactions ───────────────────────────────────────────────────

GET http://{{host}}/repos/octocat/hello-world/comments/1/reactions
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

POST http://{{host}}/repos/octocat/hello-world/comments/1/reactions
Authorization: token testtoken
Content-Type: application/json
{"content": "+1"}

HTTP 501
[Asserts]
jsonpath "$.message" isString

DELETE http://{{host}}/repos/octocat/hello-world/comments/1/reactions/1
Authorization: token testtoken

HTTP 501
[Asserts]
jsonpath "$.message" isString

# ── Issue comment reactions ────────────────────────────────────────────────────

GET http://{{host}}/repos/octocat/hello-world/issues/comments/1/reactions
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

POST http://{{host}}/repos/octocat/hello-world/issues/comments/1/reactions
Authorization: token testtoken
Content-Type: application/json
{"content": "+1"}

HTTP 501
[Asserts]
jsonpath "$.message" isString

DELETE http://{{host}}/repos/octocat/hello-world/issues/comments/1/reactions/1
Authorization: token testtoken

HTTP 501
[Asserts]
jsonpath "$.message" isString

# ── Issue reactions ────────────────────────────────────────────────────────────

GET http://{{host}}/repos/octocat/hello-world/issues/1/reactions
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$[0].id" == 1
jsonpath "$[0].content" == "+1"
jsonpath "$[0].user.login" == "octocat"

POST http://{{host}}/repos/octocat/hello-world/issues/1/reactions
Authorization: token testtoken
Content-Type: application/json
{"content": "+1"}

HTTP 201
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == 1
jsonpath "$.content" == "+1"
jsonpath "$.user.login" == "octocat"

DELETE http://{{host}}/repos/octocat/hello-world/issues/1/reactions/1
Authorization: token testtoken

HTTP 204

DELETE http://{{host}}/repos/octocat/hello-world/issues/1/reactions/9999
Authorization: token testtoken

HTTP 404
[Asserts]
jsonpath "$.message" isString

# ── PR comment reactions ───────────────────────────────────────────────────────

GET http://{{host}}/repos/octocat/hello-world/pulls/comments/1/reactions
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

POST http://{{host}}/repos/octocat/hello-world/pulls/comments/1/reactions
Authorization: token testtoken
Content-Type: application/json
{"content": "+1"}

HTTP 501
[Asserts]
jsonpath "$.message" isString

DELETE http://{{host}}/repos/octocat/hello-world/pulls/comments/1/reactions/1
Authorization: token testtoken

HTTP 501
[Asserts]
jsonpath "$.message" isString

# ── Release reactions ──────────────────────────────────────────────────────────

GET http://{{host}}/repos/octocat/hello-world/releases/1/reactions
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

POST http://{{host}}/repos/octocat/hello-world/releases/1/reactions
Authorization: token testtoken
Content-Type: application/json
{"content": "+1"}

HTTP 501
[Asserts]
jsonpath "$.message" isString

DELETE http://{{host}}/repos/octocat/hello-world/releases/1/reactions/1
Authorization: token testtoken

HTTP 501
[Asserts]
jsonpath "$.message" isString
