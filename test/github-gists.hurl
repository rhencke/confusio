# Gists API — GitHub backend (webhook-only; no upstream API configured).
# List endpoints return empty arrays; mutation endpoints return 501.

GET http://{{host}}/gists
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

POST http://{{host}}/gists
Authorization: token testtoken
Content-Type: application/json
{"files": {"hello.txt": {"content": "Hello World"}}, "public": false}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString
