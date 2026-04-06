# Gitignore API assertions — Gitea backend.

# GET /gitignore/templates
GET http://{{host}}/gitignore/templates

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0]" == "C"

# GET /gitignore/templates/{name}
GET http://{{host}}/gitignore/templates/C

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" == "C"
jsonpath "$.source" isString

# Unknown template returns 404
GET http://{{host}}/gitignore/templates/Nonexistent

HTTP 404
