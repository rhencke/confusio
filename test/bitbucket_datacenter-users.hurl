# GET /users/octocat
GET http://{{host}}/users/octocat
HTTP 200
[Asserts]
jsonpath "$.login" == "octocat"
jsonpath "$.name" isString

# GET /users
GET http://{{host}}/users
HTTP 200
[Asserts]
jsonpath "$" isCollection
jsonpath "$[0].login" isString

# GET /user — Bitbucket DC has no authenticated user endpoint, returns 404
GET http://{{host}}/user
HTTP 404
