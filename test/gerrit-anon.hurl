# Anonymous access — Gerrit backend.
# Verifies that unauthenticated requests are forwarded correctly when the
# backend allows anonymous access.

# GET / — no Authorization header → should succeed
GET http://{{host}}/

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "{}"

# GET /repos/octocat/hello-world — anonymous read
GET http://{{host}}/repos/octocat/hello-world

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" == "hello-world"
jsonpath "$.owner.login" isString
