# GET /rate_limit — gitea exposes /api/v1/rate_limit.
# confusio proxies to it and returns just the `rate` key.

GET http://{{host}}/rate_limit

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.rate.limit" == 5000
jsonpath "$.rate.used" == 0
jsonpath "$.rate.remaining" == 5000
jsonpath "$.rate.reset" isInteger
