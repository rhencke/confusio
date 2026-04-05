# Search API assertions — Gitea backend (also covers forgejo, codeberg, gogs, notabug).

# GET /search/repositories?q=hello
GET http://{{host}}/search/repositories?q=hello

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" isInteger
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection
jsonpath "$.items[0].name" == "hello-world"
jsonpath "$.items[0].owner.login" == "octocat"

# GET /search/users?q=octocat
GET http://{{host}}/search/users?q=octocat

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" isInteger
jsonpath "$.incomplete_results" == false
jsonpath "$.items" isCollection
jsonpath "$.items[0].login" == "octocat"
