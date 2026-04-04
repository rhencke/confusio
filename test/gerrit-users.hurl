# Gerrit backend users API assertions.

# GET /user — authenticated user (maps to GET /a/accounts/self)
GET http://{{host}}/user

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.login" == "octocat"
jsonpath "$.id" isInteger
jsonpath "$.name" isString
jsonpath "$.email" isString

# GET /users/{username} — user by username (maps to GET /a/accounts/{username})
GET http://{{host}}/users/octocat

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.login" == "octocat"
jsonpath "$.id" isInteger

# GET /users — list active accounts (maps to GET /a/accounts/?q=is:active)
GET http://{{host}}/users

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].login" isString
