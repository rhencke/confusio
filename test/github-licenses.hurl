# Licenses API — GitHub backend (webhook-only; no upstream API configured).
# confusio returns 501 for all license template requests.

GET http://{{host}}/licenses

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
