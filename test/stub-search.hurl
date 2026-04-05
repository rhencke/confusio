# Search API assertions — backends with no native search support.
# All search endpoints return an empty GitHub-format result envelope.

GET http://{{host}}/search/repositories?q=hello

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection

GET http://{{host}}/search/users?q=octocat

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection

GET http://{{host}}/search/issues?q=bug

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection

GET http://{{host}}/search/commits?q=fix

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection

GET http://{{host}}/search/code?q=addClass

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
