# Gists API — GitLab Snippets.
# GitLab snippet IDs are integers; confusio stringifies them as gist IDs.

# GET /gists — list auth user's snippets
GET http://{{host}}/gists
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$[0].id" == "36"
jsonpath "$[0].description" == "Hello snippet"
jsonpath "$[0].public" == true
jsonpath "$[0].owner.login" == "octocat"
jsonpath "$[0].files['hello.txt'].filename" == "hello.txt"

# GET /gists/public — list public snippets
GET http://{{host}}/gists/public
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$[0].id" == "36"

# GET /gists/starred — no GitLab equivalent; returns empty list
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
jsonpath "$.id" == "36"

# GET /gists/{gist_id}
GET http://{{host}}/gists/36
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == "36"
jsonpath "$.description" == "Hello snippet"
jsonpath "$.public" == true
jsonpath "$.owner.login" == "octocat"
jsonpath "$.files['hello.txt'].filename" == "hello.txt"

# PATCH /gists/{gist_id}
PATCH http://{{host}}/gists/36
Authorization: token testtoken
Content-Type: application/json
{"description": "Updated snippet"}

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == "36"

# GET /gists/{gist_id}/comments
GET http://{{host}}/gists/36/comments
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$[0].id" == 1
jsonpath "$[0].body" == "A comment"
jsonpath "$[0].user.login" == "octocat"

# POST /gists/{gist_id}/comments
POST http://{{host}}/gists/36/comments
Authorization: token testtoken
Content-Type: application/json
{"body": "A comment"}

HTTP 201
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == 1
jsonpath "$.body" == "A comment"

# GET /gists/{gist_id}/comments/{comment_id}
GET http://{{host}}/gists/36/comments/1
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == 1
jsonpath "$.body" == "A comment"

# PATCH /gists/{gist_id}/comments/{comment_id}
PATCH http://{{host}}/gists/36/comments/1
Authorization: token testtoken
Content-Type: application/json
{"body": "Updated comment"}

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == 1

# DELETE /gists/{gist_id}/comments/{comment_id}
DELETE http://{{host}}/gists/36/comments/1
Authorization: token testtoken

HTTP 204

# GET /gists/{gist_id}/commits — no GitLab equivalent; returns empty list
GET http://{{host}}/gists/36/commits
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# GET /gists/{gist_id}/forks — no GitLab equivalent; returns empty list
GET http://{{host}}/gists/36/forks
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# POST /gists/{gist_id}/forks — no GitLab equivalent
POST http://{{host}}/gists/36/forks
Authorization: token testtoken
Content-Length: 0

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /gists/{gist_id}/star — no GitLab equivalent
GET http://{{host}}/gists/36/star
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PUT /gists/{gist_id}/star — no GitLab equivalent
PUT http://{{host}}/gists/36/star
Authorization: token testtoken
Content-Length: 0

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /gists/{gist_id}/star — no GitLab equivalent
DELETE http://{{host}}/gists/36/star
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /gists/{gist_id}/{sha} — no GitLab equivalent
GET http://{{host}}/gists/36/deadbeef1234
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /gists/{gist_id}
DELETE http://{{host}}/gists/36
Authorization: token testtoken

HTTP 204

# GET /users/{username}/gists
GET http://{{host}}/users/octocat/gists
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$[0].id" == "36"
jsonpath "$[0].owner.login" == "octocat"
