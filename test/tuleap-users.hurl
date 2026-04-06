# Tuleap backend users API assertions.

# GET /users/{username} — find Tuleap user by username
GET http://{{host}}/users/octocat

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.login" == "octocat"
jsonpath "$.id" isInteger
jsonpath "$.name" isString
jsonpath "$.type" == "User"

# GET /users/{username} — user not found → 404
GET http://{{host}}/users/nosuchuser

HTTP 404

# GET /users — list Tuleap users
GET http://{{host}}/users

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].login" isString
