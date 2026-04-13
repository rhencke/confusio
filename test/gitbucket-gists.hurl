# Gists API — GitBucket exposes a GitHub-compatible gists API at /api/v3/gists.

# GET /gists — list auth user's gists
GET http://{{host}}/gists
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$[0].id" == "aa5a315d61ae9438b18d"
jsonpath "$[0].description" == "Hello gist"
jsonpath "$[0].public" == true
jsonpath "$[0].owner.login" == "octocat"
jsonpath "$[0].files['hello.txt'].filename" == "hello.txt"

# GET /gists/public — list public gists
GET http://{{host}}/gists/public
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$[0].id" == "aa5a315d61ae9438b18d"

# GET /gists/starred — list starred gists
GET http://{{host}}/gists/starred
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$[0].id" == "aa5a315d61ae9438b18d"

# POST /gists — create a gist
POST http://{{host}}/gists
Authorization: token testtoken
Content-Type: application/json
{"files": {"hello.txt": {"content": "Hello World"}}, "description": "Hello gist", "public": true}

HTTP 201
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == "aa5a315d61ae9438b18d"

# GET /gists/{gist_id}
GET http://{{host}}/gists/aa5a315d61ae9438b18d
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == "aa5a315d61ae9438b18d"
jsonpath "$.description" == "Hello gist"
jsonpath "$.public" == true
jsonpath "$.owner.login" == "octocat"
jsonpath "$.files['hello.txt'].filename" == "hello.txt"

# PATCH /gists/{gist_id}
PATCH http://{{host}}/gists/aa5a315d61ae9438b18d
Authorization: token testtoken
Content-Type: application/json
{"description": "Updated gist"}

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == "aa5a315d61ae9438b18d"

# GET /gists/{gist_id}/comments
GET http://{{host}}/gists/aa5a315d61ae9438b18d/comments
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$[0].id" == 1
jsonpath "$[0].body" == "A comment"
jsonpath "$[0].user.login" == "octocat"

# POST /gists/{gist_id}/comments
POST http://{{host}}/gists/aa5a315d61ae9438b18d/comments
Authorization: token testtoken
Content-Type: application/json
{"body": "A comment"}

HTTP 201
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == 1
jsonpath "$.body" == "A comment"

# GET /gists/{gist_id}/comments/{comment_id}
GET http://{{host}}/gists/aa5a315d61ae9438b18d/comments/1
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == 1
jsonpath "$.body" == "A comment"

# PATCH /gists/{gist_id}/comments/{comment_id}
PATCH http://{{host}}/gists/aa5a315d61ae9438b18d/comments/1
Authorization: token testtoken
Content-Type: application/json
{"body": "Updated comment"}

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == 1

# DELETE /gists/{gist_id}/comments/{comment_id}
DELETE http://{{host}}/gists/aa5a315d61ae9438b18d/comments/1
Authorization: token testtoken

HTTP 204

# GET /gists/{gist_id}/commits
GET http://{{host}}/gists/aa5a315d61ae9438b18d/commits
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$[0].version" == "deadbeef1234"
jsonpath "$[0].user.login" == "octocat"

# GET /gists/{gist_id}/forks
GET http://{{host}}/gists/aa5a315d61ae9438b18d/forks
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# POST /gists/{gist_id}/forks — no GitBucket equivalent
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

HTTP 204

# PUT /gists/{gist_id}/star
PUT http://{{host}}/gists/aa5a315d61ae9438b18d/star
Authorization: token testtoken
Content-Length: 0

HTTP 204

# DELETE /gists/{gist_id}/star
DELETE http://{{host}}/gists/aa5a315d61ae9438b18d/star
Authorization: token testtoken

HTTP 204

# GET /gists/{gist_id}/{sha} — specific revision
GET http://{{host}}/gists/aa5a315d61ae9438b18d/deadbeef1234
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == "aa5a315d61ae9438b18d"

# DELETE /gists/{gist_id}
DELETE http://{{host}}/gists/aa5a315d61ae9438b18d
Authorization: token testtoken

HTTP 204

# GET /users/{username}/gists
GET http://{{host}}/users/octocat/gists
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$[0].id" == "aa5a315d61ae9438b18d"
jsonpath "$[0].owner.login" == "octocat"
