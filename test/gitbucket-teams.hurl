# Teams API — GitBucket supports org teams.

# GET /orgs/{org}/teams
GET http://{{host}}/orgs/testorg/teams

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].id" == 1
jsonpath "$[0].slug" == "core"
jsonpath "$[0].name" isString
