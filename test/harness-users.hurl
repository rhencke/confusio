# Harness Code Users API
# GET /user
GET http://{{host}}/user
HTTP 200
[Asserts]
jsonpath "$.login" == "octocat"
jsonpath "$.id" isInteger
jsonpath "$.type" == "User"

# PATCH /user
PATCH http://{{host}}/user
Content-Type: application/json
{}
HTTP 200
[Asserts]
jsonpath "$.login" == "octocat"
