# Issues API assertions — Harness Code backend.
# Harness Code has no native issue tracker; all endpoints fall back to defaults.

# GET /repos/{owner}/{repo}/issues → []
GET http://{{host}}/repos/octocat/hello-world/issues

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# GET /repos/{owner}/{repo}/issues/{issue_number} → 404
GET http://{{host}}/repos/octocat/hello-world/issues/1

HTTP 404

# GET /repos/{owner}/{repo}/issues/comments → []
GET http://{{host}}/repos/octocat/hello-world/issues/comments

HTTP 200
[Asserts]
body == "[]"

# GET /repos/{owner}/{repo}/issues/{issue_number}/comments → []
GET http://{{host}}/repos/octocat/hello-world/issues/1/comments

HTTP 200
[Asserts]
body == "[]"

# GET /repos/{owner}/{repo}/labels → []
GET http://{{host}}/repos/octocat/hello-world/labels

HTTP 200
[Asserts]
body == "[]"

# GET /repos/{owner}/{repo}/milestones → []
GET http://{{host}}/repos/octocat/hello-world/milestones

HTTP 200
[Asserts]
body == "[]"

# GET /repos/{owner}/{repo}/assignees → []
GET http://{{host}}/repos/octocat/hello-world/assignees

HTTP 200
[Asserts]
body == "[]"
