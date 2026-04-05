# GET /rate_limit — confusio returns a fixed unlimited response for all backends
# since no provider has a GitHub-compatible rate limit API.

GET http://{{host}}/rate_limit

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.resources.core.limit" == 999999
jsonpath "$.resources.core.used" == 0
jsonpath "$.resources.core.remaining" == 999999
jsonpath "$.resources.core.reset" isInteger
jsonpath "$.resources.search.limit" == 999999
jsonpath "$.resources.search.used" == 0
jsonpath "$.resources.search.remaining" == 999999
jsonpath "$.resources.search.reset" isInteger
jsonpath "$.rate.limit" == 999999
jsonpath "$.rate.used" == 0
jsonpath "$.rate.remaining" == 999999
jsonpath "$.rate.reset" isInteger
