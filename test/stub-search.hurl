# Search API — no native search; all search endpoints return empty result sets.

GET http://{{host}}/search/repositories?q=test

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection

GET http://{{host}}/search/code?q=test

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection

GET http://{{host}}/search/commits?q=test

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection

GET http://{{host}}/search/issues?q=test

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection

GET http://{{host}}/search/labels?q=bug&repository_id=1

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection

GET http://{{host}}/search/topics?q=ruby

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection

GET http://{{host}}/search/users?q=tom

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection
