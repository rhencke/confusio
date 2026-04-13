# Gists API — Bitbucket Snippets.
# GitHub gist IDs are encoded as "workspace~encoded_id" by the backend.

# GET /gists — list auth user's snippets
GET http://{{host}}/gists
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$[0].id" == "octocat~pHANT4"
jsonpath "$[0].description" == "Hello snippet"
jsonpath "$[0].public" == true
jsonpath "$[0].owner.login" == "octocat"
jsonpath "$[0].files['hello.txt'].filename" == "hello.txt"

# GET /gists/public — list all public snippets
GET http://{{host}}/gists/public
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$[0].id" == "octocat~pHANT4"

# GET /gists/starred — no Bitbucket equivalent; returns empty list
GET http://{{host}}/gists/starred
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# POST /gists — create a snippet
POST http://{{host}}/gists
Authorization: token testtoken
Content-Type: application/json
{"files": {"hello.txt": {"content": "Hello World"}}, "description": "Hello snippet", "public": true}

HTTP 201
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == "octocat~pHANT4"

# GET /gists/{gist_id}
GET http://{{host}}/gists/octocat~pHANT4
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == "octocat~pHANT4"
jsonpath "$.description" == "Hello snippet"
jsonpath "$.public" == true
jsonpath "$.owner.login" == "octocat"
jsonpath "$.files['hello.txt'].filename" == "hello.txt"

# PATCH /gists/{gist_id}
PATCH http://{{host}}/gists/octocat~pHANT4
Authorization: token testtoken
Content-Type: application/json
{"description": "Updated snippet"}

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == "octocat~pHANT4"

# GET /gists/{gist_id}/comments
GET http://{{host}}/gists/octocat~pHANT4/comments
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$[0].id" == 1
jsonpath "$[0].body" == "A comment"
jsonpath "$[0].user.login" == "octocat"

# POST /gists/{gist_id}/comments
POST http://{{host}}/gists/octocat~pHANT4/comments
Authorization: token testtoken
Content-Type: application/json
{"body": "A comment"}

HTTP 201
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == 1
jsonpath "$.body" == "A comment"

# GET /gists/{gist_id}/comments/{comment_id}
GET http://{{host}}/gists/octocat~pHANT4/comments/1
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == 1
jsonpath "$.body" == "A comment"

# PATCH /gists/{gist_id}/comments/{comment_id}
PATCH http://{{host}}/gists/octocat~pHANT4/comments/1
Authorization: token testtoken
Content-Type: application/json
{"body": "Updated comment"}

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == 1

# DELETE /gists/{gist_id}/comments/{comment_id}
DELETE http://{{host}}/gists/octocat~pHANT4/comments/1
Authorization: token testtoken

HTTP 204

# GET /gists/{gist_id}/commits
GET http://{{host}}/gists/octocat~pHANT4/commits
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$[0].version" == "deadbeef1234"
jsonpath "$[0].user.login" == "octocat"

# GET /gists/{gist_id}/forks
GET http://{{host}}/gists/octocat~pHANT4/forks
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# POST /gists/{gist_id}/forks — no Bitbucket equivalent
POST http://{{host}}/gists/octocat~pHANT4/forks
Authorization: token testtoken
Content-Length: 0

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /gists/{gist_id}/star — check if watching
GET http://{{host}}/gists/octocat~pHANT4/star
Authorization: token testtoken

HTTP 204

# PUT /gists/{gist_id}/star — watch
PUT http://{{host}}/gists/octocat~pHANT4/star
Authorization: token testtoken
Content-Length: 0

HTTP 204

# DELETE /gists/{gist_id}/star — unwatch
DELETE http://{{host}}/gists/octocat~pHANT4/star
Authorization: token testtoken

HTTP 204

# GET /gists/{gist_id}/{sha} — specific revision
GET http://{{host}}/gists/octocat~pHANT4/deadbeef1234
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == "octocat~pHANT4"

# DELETE /gists/{gist_id}
DELETE http://{{host}}/gists/octocat~pHANT4
Authorization: token testtoken

HTTP 204

# GET /users/{username}/gists
GET http://{{host}}/users/octocat/gists
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$[0].id" == "octocat~pHANT4"
jsonpath "$[0].owner.login" == "octocat"
