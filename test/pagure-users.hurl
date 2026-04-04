# Pagure Users API
# GET /user (two-step: /-/whoami then /user/{username})
GET http://{{host}}/user
HTTP 200
[Asserts]
jsonpath "$.login" == "octocat"
jsonpath "$.type" == "User"

# GET /users/{username}
GET http://{{host}}/users/octocat
HTTP 200
[Asserts]
jsonpath "$.login" == "octocat"
jsonpath "$.type" == "User"

# GET /users
GET http://{{host}}/users
HTTP 200
[Asserts]
jsonpath "$[0].login" isString
jsonpath "$[0].type" == "User"
