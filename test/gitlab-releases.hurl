# Releases API — GitLab has a native releases API.
# GitLab releases use tag_name as identifier; confusio maps integer release_id to tag_name.

# GET /repos/{owner}/{repo}/releases
GET http://{{host}}/repos/octocat/hello-world/releases

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].id" == 1
jsonpath "$[0].tag_name" == "v1.0"
jsonpath "$[0].name" isString

# GET /repos/{owner}/{repo}/releases/latest
GET http://{{host}}/repos/octocat/hello-world/releases/latest

HTTP 200
[Asserts]
jsonpath "$.tag_name" == "v1.0"

# GET /repos/{owner}/{repo}/releases/tags/{tag}
GET http://{{host}}/repos/octocat/hello-world/releases/tags/v1.0

HTTP 200
[Asserts]
jsonpath "$.tag_name" == "v1.0"

# GET /repos/{owner}/{repo}/releases/{release_id}
GET http://{{host}}/repos/octocat/hello-world/releases/1

HTTP 200
[Asserts]
jsonpath "$.tag_name" == "v1.0"
