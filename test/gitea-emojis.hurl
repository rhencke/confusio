GET http://{{host}}/emojis

HTTP 404
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" == "Not Found"
