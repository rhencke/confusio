# POST /webhooks/{backend} — webhook receive pipeline
#
# The receiver intercepts all /webhooks/* paths before routing.  Tests below
# cover route validation plus the method, format, and parse stages uniformly
# across every backend.

# Route: unknown backend → 404
POST http://{{host}}/webhooks/notabackend
Content-Type: application/json
{}

HTTP 404
[Asserts]
jsonpath "$.message" == "Not Found"

# Route: extra path segment → 404 (receiver requires exactly /webhooks/{backend})
POST http://{{host}}/webhooks/gitea/extra
Content-Type: application/json
{}

HTTP 404
[Asserts]
jsonpath "$.message" == "Not Found"

# Method: non-POST → 405
GET http://{{host}}/webhooks/{{backend}}

HTTP 405
[Asserts]
jsonpath "$.message" == "Method Not Allowed"

# Format: wrong Content-Type → 400
POST http://{{host}}/webhooks/{{backend}}
Content-Type: text/plain
{}

HTTP 400
[Asserts]
jsonpath "$.message" == "Content-Type must be application/json"

# Parse: invalid JSON body → 400
POST http://{{host}}/webhooks/{{backend}}
Content-Type: application/json
`not-valid-json`

HTTP 400
[Asserts]
jsonpath "$.message" == "Invalid JSON body"
