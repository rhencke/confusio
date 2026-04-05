# GET /rate_limit — confusio returns a partial unlimited response for all backends
# since no provider has a GitHub-compatible rate limit API.
# Only the `rate` key is returned (partial compatibility).

GET http://{{host}}/rate_limit

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.rate.limit" == 999999
jsonpath "$.rate.used" == 0
jsonpath "$.rate.remaining" == 999999
jsonpath "$.rate.reset" isInteger
