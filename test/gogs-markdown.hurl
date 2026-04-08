# Markdown API assertions — Gitea native rendering.

# POST /markdown — rendered HTML
POST http://{{host}}/markdown
Authorization: token testtoken
Content-Type: application/json
{"text": "Hello **world**"}

HTTP 200
[Asserts]
header "Content-Type" contains "text/html"
body contains "Hello"

# POST /markdown/raw — rendered HTML
POST http://{{host}}/markdown/raw
Authorization: token testtoken
Content-Type: text/plain
`Hello **world**`

HTTP 200
[Asserts]
header "Content-Type" contains "text/html"
body contains "Hello"
