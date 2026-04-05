# Issues API assertions — Bitbucket Cloud backend.
# Bitbucket issues use reporter (not user) and no labels; milestones have name not title.

# GET /repos/{owner}/{repo}/issues
GET http://{{host}}/repos/octocat/hello-world/issues

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].number" == 1
jsonpath "$[0].title" == "Found a bug"
jsonpath "$[0].state" == "open"
jsonpath "$[0].user.login" isString
jsonpath "$[0].created_at" isString
jsonpath "$[0].updated_at" isString

# GET /repos/{owner}/{repo}/issues/{issue_number}
GET http://{{host}}/repos/octocat/hello-world/issues/1

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.number" == 1
jsonpath "$.title" == "Found a bug"
jsonpath "$.state" == "open"
jsonpath "$.user.login" isString
jsonpath "$.created_at" isString
jsonpath "$.updated_at" isString
jsonpath "$.milestone.title" == "v1.0"
jsonpath "$.milestone.number" isInteger

# GET /repos/{owner}/{repo}/issues/{issue_number} — not found → 404
GET http://{{host}}/repos/octocat/hello-world/issues/9999

HTTP 404

# GET /repos/{owner}/{repo}/issues/{issue_number}/comments
GET http://{{host}}/repos/octocat/hello-world/issues/1/comments

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].body" isString
jsonpath "$[0].created_at" isString

# GET /repos/{owner}/{repo}/milestones
GET http://{{host}}/repos/octocat/hello-world/milestones

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].title" == "v1.0"
jsonpath "$[0].number" isInteger
jsonpath "$[0].state" == "open"
