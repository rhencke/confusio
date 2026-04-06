# Boot-path checks — used by both unit (mock) and integration (live gitea.com) tests.
#
# TODO: additional platform integration tests:
#   - codeberg.org  (Forgejo-based, Gitea-compatible API)
#   - Self-hosted Gitea: set base_url in CLI args in CI matrix

GET http://{{host}}/

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "{}"

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
