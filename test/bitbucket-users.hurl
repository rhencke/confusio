# GET /user
GET http://{{host}}/user
HTTP 200
[Asserts]
jsonpath "$.login" == "octocat"
jsonpath "$.node_id" isString

# GET /users/octocat
GET http://{{host}}/users/octocat
HTTP 200
[Asserts]
jsonpath "$.login" == "octocat"

# GET /user/followers — Bitbucket has no followers, returns 404
GET http://{{host}}/user/followers
HTTP 404
