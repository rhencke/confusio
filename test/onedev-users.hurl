# OneDev Users API
# GET /users
GET http://{{host}}/users
HTTP 200
[Asserts]
jsonpath "$[0].login" == "octocat"
jsonpath "$[0].type" == "User"

# GET /users/{username}
GET http://{{host}}/users/octocat
HTTP 200
[Asserts]
jsonpath "$.login" == "octocat"
jsonpath "$.type" == "User"
