# Actions API — GitHub backend (webhook-only; no upstream API configured).
# All Actions endpoints use default handlers: empty lists or 501.

GET http://{{host}}/enterprises/myenterprise/actions/cache/retention-limit
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString
