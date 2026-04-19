# Meta API assertions — GitHub backend.
# All meta endpoints are confusio-native (no backend call needed).

# GET /meta
GET http://{{host}}/meta

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.verifiable_password_authentication" isBoolean
jsonpath "$.hooks" isCollection

# GET /zen
GET http://{{host}}/zen

HTTP 200
[Asserts]
header "Content-Type" startsWith "text/plain"
