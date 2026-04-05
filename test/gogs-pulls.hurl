# Pull Requests API assertions — Gogs backend.

# GET /repos/{owner}/{repo}/pulls
GET http://{{host}}/repos/octocat/hello-world/pulls

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].number" == 1
jsonpath "$[0].title" == "A great PR"
jsonpath "$[0].state" == "open"
jsonpath "$[0].user.login" isString
jsonpath "$[0].head.ref" == "feature"
jsonpath "$[0].base.ref" == "main"
jsonpath "$[0].created_at" isString
jsonpath "$[0].updated_at" isString

# GET /repos/{owner}/{repo}/pulls/{pull_number}
GET http://{{host}}/repos/octocat/hello-world/pulls/1

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.number" == 1
jsonpath "$.title" == "A great PR"
jsonpath "$.state" == "open"
jsonpath "$.user.login" isString
jsonpath "$.head.ref" == "feature"
jsonpath "$.base.ref" == "main"
jsonpath "$.draft" == false
jsonpath "$.created_at" isString
jsonpath "$.updated_at" isString

# GET /repos/{owner}/{repo}/pulls/{pull_number}/commits
GET http://{{host}}/repos/octocat/hello-world/pulls/1/commits

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection

# GET /repos/{owner}/{repo}/pulls/{pull_number}/files
GET http://{{host}}/repos/octocat/hello-world/pulls/1/files

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection

# GET /repos/{owner}/{repo}/pulls/{pull_number}/merge — 204 when merged
GET http://{{host}}/repos/octocat/hello-world/pulls/1/merge

HTTP 204

# GET /repos/{owner}/{repo}/pulls/{pull_number}/requested_reviewers
GET http://{{host}}/repos/octocat/hello-world/pulls/1/requested_reviewers

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews
GET http://{{host}}/repos/octocat/hello-world/pulls/1/reviews

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].id" == 1
jsonpath "$[0].state" == "APPROVED"
jsonpath "$[0].body" isString
jsonpath "$[0].user.login" isString

# GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}
GET http://{{host}}/repos/octocat/hello-world/pulls/1/reviews/1

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == 1
jsonpath "$.state" == "APPROVED"
jsonpath "$.body" isString

# GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}/comments
GET http://{{host}}/repos/octocat/hello-world/pulls/1/reviews/1/comments

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].id" == 1
jsonpath "$[0].body" isString
jsonpath "$[0].path" isString
jsonpath "$[0].user.login" isString

# GET /repos/{owner}/{repo}/pulls/{pull_number}/comments (aggregated inline comments)
GET http://{{host}}/repos/octocat/hello-world/pulls/1/comments

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].id" == 1
jsonpath "$[0].body" isString
jsonpath "$[0].path" isString
