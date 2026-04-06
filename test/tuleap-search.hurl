# Search API assertions — Tuleap backend.
# Repositories search maps to Tuleap projects; users search maps to Tuleap users.

GET http://{{host}}/search/repositories?q=hello

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 1
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection
jsonpath "$.items[0].name" isString

GET http://{{host}}/search/users?q=octocat

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 1
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection
jsonpath "$.items[0].login" isString
jsonpath "$.items[0].type" == "User"

# Endpoints without native Tuleap support return empty envelope
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

GET http://{{host}}/search/labels?q=bug&repository_id=1

HTTP 200
[Asserts]
jsonpath "$.total_count" == 0
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection

GET http://{{host}}/search/topics?q=ruby

HTTP 200
[Asserts]
jsonpath "$.total_count" == 0
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection
