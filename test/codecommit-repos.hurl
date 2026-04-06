# AWS CodeCommit backend repos API assertions.
# CodeCommit has no owner concept; {owner} is ignored in single-repo lookups.

# GET /repos/{owner}/{repo}: owner ignored, looks up repo by name
GET http://{{host}}/repos/ignored-owner/hello-world

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" == "hello-world"
jsonpath "$.full_name" == "hello-world"
jsonpath "$.description" isString
jsonpath "$.private" == true
jsonpath "$.default_branch" isString

# Repo not found → 404 (CodeCommit returns 400 RepositoryDoesNotExistException;
# confusio maps this to 404)
GET http://{{host}}/repos/ignored-owner/no-such-repo

HTTP 404

# GET /repositories — all CodeCommit repos in the account
GET http://{{host}}/repositories

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" isString

# GET /repos/{owner}/{repo}/branches — list branches
GET http://{{host}}/repos/ignored-owner/hello-world/branches

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" isString
jsonpath "$[0].commit" isCollection
jsonpath "$[0].protected" isBoolean
