# Issues API assertions — Pagure backend.
# Pagure uses tags (strings) instead of labels; no colors, no milestones.

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
jsonpath "$[0].labels[0].name" == "bug"

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
jsonpath "$.labels[0].name" == "bug"

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

# GET /repos/{owner}/{repo}/labels — Pagure has no repo-level labels → empty list
GET http://{{host}}/repos/octocat/hello-world/labels

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
