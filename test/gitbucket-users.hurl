# GET /user
GET http://{{host}}/user
HTTP 200
[Asserts]
jsonpath "$.login" == "octocat"
jsonpath "$.id" isInteger

# GET /users/octocat
GET http://{{host}}/users/octocat
HTTP 200
[Asserts]
jsonpath "$.login" == "octocat"

# GET /users
GET http://{{host}}/users
HTTP 200
[Asserts]
jsonpath "$" isCollection

# GET /user/followers
GET http://{{host}}/user/followers
HTTP 200
[Asserts]
jsonpath "$" isCollection

# GET /user/following
GET http://{{host}}/user/following
HTTP 200
[Asserts]
jsonpath "$" isCollection

# GET /user/following/hubot — 204
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

# GET /user/emails
GET http://{{host}}/user/emails
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

# GET /user/blocks — GitBucket has no blocking, returns 404
GET http://{{host}}/user/blocks
HTTP 404
