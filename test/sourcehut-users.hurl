# Sourcehut Users API
# GET /user
GET http://{{host}}/user
HTTP 200
[Asserts]
jsonpath "$.login" == "octocat"
jsonpath "$.type" == "User"
