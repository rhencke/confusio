# GET /user — authenticated user
GET http://{{host}}/user
HTTP 200
[Asserts]
jsonpath "$.login" == "octocat"
jsonpath "$.id" isInteger
jsonpath "$.node_id" isString
jsonpath "$.name" isString

# GET /users/octocat — resolve by username
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
jsonpath "$[0].login" isString

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

# GET /users/octocat/keys — requires username→ID lookup
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

# GET /user/followers — GitLab has no followers, returns 404
GET http://{{host}}/user/followers
HTTP 404
