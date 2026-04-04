# GET /user — authenticated user
GET http://{{host}}/user
HTTP 200
[Asserts]
jsonpath "$.login" == "octocat"
jsonpath "$.id" isInteger
jsonpath "$.node_id" isString
jsonpath "$.name" isString
jsonpath "$.email" isString
jsonpath "$.followers" isInteger
jsonpath "$.following" isInteger

# GET /users/octocat — public user
GET http://{{host}}/users/octocat
HTTP 200
[Asserts]
jsonpath "$.login" == "octocat"
jsonpath "$.id" isInteger

# GET /users — list users
GET http://{{host}}/users
HTTP 200
[Asserts]
jsonpath "$" isCollection

# GET /user/followers
GET http://{{host}}/user/followers
HTTP 200
[Asserts]
jsonpath "$" isCollection
jsonpath "$[0].login" isString

# GET /user/following
GET http://{{host}}/user/following
HTTP 200
[Asserts]
jsonpath "$" isCollection

# GET /user/following/{username} — 204 if following
GET http://{{host}}/user/following/hubot
HTTP 204

# GET /users/octocat/followers
GET http://{{host}}/users/octocat/followers
HTTP 200
[Asserts]
jsonpath "$" isCollection

# GET /users/octocat/following
GET http://{{host}}/users/octocat/following
HTTP 200
[Asserts]
jsonpath "$" isCollection

# GET /user/keys
GET http://{{host}}/user/keys
HTTP 200
[Asserts]
jsonpath "$" isCollection

# GET /user/keys/1
GET http://{{host}}/user/keys/1
HTTP 200
[Asserts]
jsonpath "$.id" isInteger

# GET /users/octocat/keys
GET http://{{host}}/users/octocat/keys
HTTP 200
[Asserts]
jsonpath "$" isCollection

# GET /user/gpg_keys
GET http://{{host}}/user/gpg_keys
HTTP 200
[Asserts]
jsonpath "$" isCollection

# GET /users/octocat/gpg_keys
GET http://{{host}}/users/octocat/gpg_keys
HTTP 200
[Asserts]
jsonpath "$" isCollection

# GET /user/emails
GET http://{{host}}/user/emails
HTTP 200
[Asserts]
jsonpath "$" isCollection
jsonpath "$[0].email" isString

# GET /user/public_emails — only verified
GET http://{{host}}/user/public_emails
HTTP 200
[Asserts]
jsonpath "$" isCollection
jsonpath "$[0].email" == "octocat@github.com"
jsonpath "$[0].verified" == true

# GET /user/blocks — Gitea has no blocking API, returns 404
GET http://{{host}}/user/blocks
HTTP 404
