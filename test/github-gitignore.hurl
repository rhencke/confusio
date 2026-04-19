# Gitignore API — GitHub backend (webhook-only; no upstream API configured).
# confusio returns 404 for all gitignore template requests.

GET http://{{host}}/gitignore/templates

HTTP 404
