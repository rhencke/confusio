# GET / with backend=gitea — used by both unit and integration tests.
#
# TODO: additional platform integration tests:
#   - codeberg.org  (Forgejo-based, Gitea-compatible API)
#   - Self-hosted Gitea: set base_url in .confusio.lua in CI matrix

GET http://{{host}}/

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "{}"
