# Gitignore API assertions — Launchpad backend.
# Launchpad does not expose the gitignore API — confusio returns 404.

# GET /gitignore/templates
GET http://{{host}}/gitignore/templates

HTTP 404

# GET /gitignore/templates/{name}
GET http://{{host}}/gitignore/templates/C

HTTP 404
