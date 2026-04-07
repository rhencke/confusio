# Anonymous access — AWS CodeCommit backend.
# Verifies that unauthenticated requests are forwarded correctly when the
# backend allows anonymous access.
# Note: CodeCommit requires owner == "codecommit" for repo endpoints.

# GET / — no Authorization header → should succeed
GET http://{{host}}/

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "{}"

# GET /repos/codecommit/hello-world — anonymous read
GET http://{{host}}/repos/codecommit/hello-world

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" == "hello-world"
