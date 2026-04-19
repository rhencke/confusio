# GET /rate_limit — GitHub backend.
# confusio returns a synthetic unlimited response since no upstream is called.

GET http://{{host}}/rate_limit

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.rate.limit" == 999999
jsonpath "$.rate.used" == 0
jsonpath "$.rate.remaining" == 999999
jsonpath "$.rate.reset" isInteger
