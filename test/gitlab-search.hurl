# Search API assertions — GitLab backend.

# GET /search/repositories?q=hello → GitLab /search?scope=projects
GET http://{{host}}/search/repositories?q=hello

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" isInteger
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection
jsonpath "$.items[0].name" == "hello-world"
jsonpath "$.items[0].owner.login" == "octocat"

# GET /search/code?q=test — no native support; returns empty result set
GET http://{{host}}/search/code?q=test

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection

# GET /search/commits?q=test — no native support; returns empty result set
GET http://{{host}}/search/commits?q=test

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection

# GET /search/issues?q=test — no native support; returns empty result set
GET http://{{host}}/search/issues?q=test

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection

# GET /search/labels?q=bug — no native support; returns empty result set
GET http://{{host}}/search/labels?q=bug&repository_id=1

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection

# GET /search/topics?q=ruby — no native support; returns empty result set
GET http://{{host}}/search/topics?q=ruby

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection

# GET /search/users?q=octocat → GitLab /search?scope=users
GET http://{{host}}/search/users?q=octocat

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" isInteger
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection
jsonpath "$.items[0].login" == "octocat"
