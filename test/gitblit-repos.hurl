# Gitblit backend repos API assertions.
# Repository names follow the pattern "owner/repo.git".

# GET /repos/{owner}/{repo}: translated from GET_REPOSITORY RPC
GET http://{{host}}/repos/octocat/hello-world

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" == "hello-world"
jsonpath "$.full_name" == "octocat/hello-world"
jsonpath "$.owner.login" == "octocat"
jsonpath "$.description" isString
jsonpath "$.private" isBoolean
jsonpath "$.default_branch" isString

# Repo not found → 404
GET http://{{host}}/repos/octocat/no-such-repo

HTTP 404

# GET /orgs/{org}/repos — repos filtered by owner prefix
GET http://{{host}}/orgs/octocat/repos

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" isString
jsonpath "$[0].full_name" isString
jsonpath "$[0].owner.login" isString

# GET /users/{username}/repos — repos filtered by username prefix
GET http://{{host}}/users/octocat/repos

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" isString

# GET /repositories — all Gitblit repositories
GET http://{{host}}/repositories

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" isString
