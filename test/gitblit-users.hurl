# Gitblit backend users API assertions.

# GET /users/{username} — find Gitblit user by username
GET http://{{host}}/users/octocat

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.login" == "octocat"
jsonpath "$.name" isString
jsonpath "$.type" == "User"

# GET /users/{username} — user not found → 404
GET http://{{host}}/users/nosuchuser

HTTP 404

# GET /users — list Gitblit users
GET http://{{host}}/users

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].login" isString
