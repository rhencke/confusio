# Activity API — GitHub backend (webhook-only; no upstream API configured).
# List endpoints return empty arrays; mutation/detail endpoints return 501.

GET http://{{host}}/events
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

GET http://{{host}}/notifications
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"
