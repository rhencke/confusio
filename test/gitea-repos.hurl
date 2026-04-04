# Repos API assertions — Gitea backend.

# GET /repos/{owner}/{repo}
GET http://{{host}}/repos/octocat/hello-world

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" == "hello-world"
jsonpath "$.full_name" == "octocat/hello-world"
jsonpath "$.owner.login" isString
jsonpath "$.default_branch" isString
jsonpath "$.private" isBoolean
jsonpath "$.visibility" isString

# GET /user/repos
GET http://{{host}}/user/repos

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" count == 1
jsonpath "$[0].name" == "hello-world"
jsonpath "$[0].owner.login" isString

# GET /orgs/{org}/repos
GET http://{{host}}/orgs/testorg/repos

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" count == 1
jsonpath "$[0].name" == "org-repo"

# GET /repos/{owner}/{repo}/topics
GET http://{{host}}/repos/octocat/hello-world/topics

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.names" isCollection

# GET /repos/{owner}/{repo}/languages
GET http://{{host}}/repos/octocat/hello-world/languages

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /repos/{owner}/{repo}/contributors
GET http://{{host}}/repos/octocat/hello-world/contributors

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection

# GET /repos/{owner}/{repo}/tags
GET http://{{host}}/repos/octocat/hello-world/tags

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" == "v1.0"
jsonpath "$[0].commit.sha" isString

# GET /repos/{owner}/{repo}/teams — not implemented (returns 501)
GET http://{{host}}/repos/octocat/hello-world/teams

HTTP 501

# Method not allowed: PUT /repos/{owner}/{repo} is not a registered route
# Use PATCH (wrong method for /repos/…) to verify 405 without body requirement
DELETE http://{{host}}/user/repos

HTTP 405
