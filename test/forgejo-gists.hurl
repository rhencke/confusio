# Gists API — Forgejo (Gitea-compatible) has no native gist equivalent.
# List endpoints return empty arrays (200); per-resource and mutation endpoints return 501.

# GET /gists
GET http://{{host}}/gists
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# POST /gists
POST http://{{host}}/gists
Authorization: token testtoken
Content-Type: application/json
{"files": {"hello.txt": {"content": "Hello World"}}, "public": false}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /gists/public
GET http://{{host}}/gists/public
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# GET /gists/starred
GET http://{{host}}/gists/starred
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# GET /gists/{gist_id}
GET http://{{host}}/gists/aa5a315d61ae9438b18d
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PATCH /gists/{gist_id}
PATCH http://{{host}}/gists/aa5a315d61ae9438b18d
Authorization: token testtoken
Content-Type: application/json
{"description": "updated"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /gists/{gist_id}
DELETE http://{{host}}/gists/aa5a315d61ae9438b18d
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /gists/{gist_id}/comments
GET http://{{host}}/gists/aa5a315d61ae9438b18d/comments
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# POST /gists/{gist_id}/comments
POST http://{{host}}/gists/aa5a315d61ae9438b18d/comments
Authorization: token testtoken
Content-Type: application/json
{"body": "A comment"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /gists/{gist_id}/comments/{comment_id}
GET http://{{host}}/gists/aa5a315d61ae9438b18d/comments/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PATCH /gists/{gist_id}/comments/{comment_id}
PATCH http://{{host}}/gists/aa5a315d61ae9438b18d/comments/1
Authorization: token testtoken
Content-Type: application/json
{"body": "Updated comment"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /gists/{gist_id}/comments/{comment_id}
DELETE http://{{host}}/gists/aa5a315d61ae9438b18d/comments/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /gists/{gist_id}/commits
GET http://{{host}}/gists/aa5a315d61ae9438b18d/commits
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# GET /gists/{gist_id}/forks
GET http://{{host}}/gists/aa5a315d61ae9438b18d/forks
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# POST /gists/{gist_id}/forks
POST http://{{host}}/gists/aa5a315d61ae9438b18d/forks
Authorization: token testtoken
Content-Length: 0

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /gists/{gist_id}/star
GET http://{{host}}/gists/aa5a315d61ae9438b18d/star
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PUT /gists/{gist_id}/star
PUT http://{{host}}/gists/aa5a315d61ae9438b18d/star
Authorization: token testtoken
Content-Length: 0

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /gists/{gist_id}/star
DELETE http://{{host}}/gists/aa5a315d61ae9438b18d/star
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /gists/{gist_id}/{sha}
GET http://{{host}}/gists/aa5a315d61ae9438b18d/deadbeef1234
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /users/{username}/gists
GET http://{{host}}/users/octocat/gists
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"
