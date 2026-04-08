# Markdown API assertions — GitLab native rendering.

# POST /markdown — rendered HTML extracted from GitLab JSON response
POST http://{{host}}/markdown
Authorization: Bearer testtoken
Content-Type: application/json
{"text": "Hello **world**"}

HTTP 200
[Asserts]
header "Content-Type" contains "text/html"
body contains "Hello"

# POST /markdown/raw — rendered HTML extracted from GitLab JSON response
POST http://{{host}}/markdown/raw
Authorization: Bearer testtoken
Content-Type: text/plain
`Hello **world**`

HTTP 200
[Asserts]
header "Content-Type" contains "text/html"
body contains "Hello"
