# Tuleap backend repos API assertions.
# owner = project shortname, repo = git repository name within that project.

# GET /repos/{owner}/{repo}: two-step lookup (project by shortname, git repo by name)
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

# Repo not found (project exists but repo name doesn't match) → 404
GET http://{{host}}/repos/octocat/no-such-repo

HTTP 404

# Project not found → 404
GET http://{{host}}/repos/nonexist/anything

HTTP 404

# GET /orgs/{org}/repos — git repositories in a Tuleap project
GET http://{{host}}/orgs/octocat/repos

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" isString
jsonpath "$[0].full_name" isString
jsonpath "$[0].owner.login" isString
