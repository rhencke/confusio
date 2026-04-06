# Search API assertions — AWS CodeCommit backend.
# Repositories are searched by filtering the full repo list by name.

GET http://{{host}}/search/repositories?q=hello

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 1
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection
jsonpath "$.items[0].name" isString

# page > 1 is not supported (CodeCommit uses cursor-based pagination)
GET http://{{host}}/search/repositories?q=hello&page=2

HTTP 422

# Unsupported search endpoints return empty envelope
GET http://{{host}}/search/users?q=octocat

HTTP 200
[Asserts]
jsonpath "$.total_count" == 0
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection

GET http://{{host}}/search/issues?q=bug

HTTP 200
[Asserts]
jsonpath "$.total_count" == 0
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection

GET http://{{host}}/search/commits?q=fix

HTTP 200
[Asserts]
jsonpath "$.total_count" == 0
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection

GET http://{{host}}/search/code?q=addClass

HTTP 200
[Asserts]
jsonpath "$.total_count" == 0
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection
