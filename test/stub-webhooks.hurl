# POST /webhooks/{backend} — webhook receive pipeline
#
# The receiver intercepts all /webhooks/* paths before routing.  Tests below
# cover the six pipeline stages uniformly across every backend.

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
GET http://{{host}}/webhooks/gitea

HTTP 405
[Asserts]
jsonpath "$.message" == "Method Not Allowed"

# Format: wrong Content-Type → 400
POST http://{{host}}/webhooks/gitea
Content-Type: text/plain
{}

HTTP 400
[Asserts]
jsonpath "$.message" == "Content-Type must be application/json"

# Parse: invalid JSON body → 400
POST http://{{host}}/webhooks/gitea
Content-Type: application/json
`not-valid-json`

HTTP 400
[Asserts]
jsonpath "$.message" == "Invalid JSON body"

# Dispatch: valid request with an event type that has no registered handler → 422
# Use a deliberately bogus event so this remains true for every configured backend.
POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: confusio_unknown_event
{}

HTTP 422
[Asserts]
jsonpath "$.message" == "Unrecognised event type: confusio_unknown_event"
