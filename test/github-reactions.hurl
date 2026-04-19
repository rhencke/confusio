# Reactions API — GitHub backend (webhook-only; no upstream API configured).
# GET endpoints return empty arrays; create and delete return 501.

GET http://{{host}}/repos/octocat/hello-world/issues/1/reactions
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

POST http://{{host}}/repos/octocat/hello-world/issues/1/reactions
Authorization: token testtoken
Content-Type: application/json
{"content": "+1"}

HTTP 501
[Asserts]
jsonpath "$.message" isString
