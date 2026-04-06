# Meta API assertions — Codeberg backend.
# All four meta endpoints are self-contained (no backend call) and return the same
# response regardless of provider.

# GET /meta
GET http://{{host}}/meta

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.verifiable_password_authentication" isBoolean
jsonpath "$.hooks" isCollection
jsonpath "$.web" isCollection
jsonpath "$.api" isCollection
jsonpath "$.git" isCollection

# GET /octocat
GET http://{{host}}/octocat

HTTP 200
[Asserts]
header "Content-Type" == "application/octocat-stream"

# GET /versions
GET http://{{host}}/versions

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0]" isString

# GET /zen
GET http://{{host}}/zen

HTTP 200
[Asserts]
header "Content-Type" startsWith "text/plain"
