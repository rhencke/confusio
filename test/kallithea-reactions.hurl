# Reactions API — Kallithea has no native reactions equivalent.
# GET endpoints return empty arrays (200); create and delete return 501.

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
body == "[]"

POST http://{{host}}/repos/octocat/hello-world/issues/1/reactions
Authorization: token testtoken
Content-Type: application/json
{"content": "+1"}

HTTP 501
[Asserts]
jsonpath "$.message" isString

DELETE http://{{host}}/repos/octocat/hello-world/issues/1/reactions/1
Authorization: token testtoken

HTTP 501
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
