# Anonymous access — Launchpad backend.
# Verifies that unauthenticated requests are forwarded correctly when the
# backend allows anonymous access.

# GET / — no Authorization header → should succeed
GET http://{{host}}/

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "{}"
