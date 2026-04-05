# GET /rate_limit — gitbucket exposes /api/v3/rate_limit (GitHub v3-compatible).
# confusio proxies to it and returns just the `rate` key.

GET http://{{host}}/rate_limit

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.rate.limit" == 60
jsonpath "$.rate.used" == 0
jsonpath "$.rate.remaining" == 60
jsonpath "$.rate.reset" isInteger
