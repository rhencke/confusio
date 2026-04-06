# AWS CodeCommit backend repos API assertions.
# {owner} must always be "codecommit"; any other value returns 404.

# GET /repos/{owner}/{repo}: owner must be "codecommit"
GET http://{{host}}/repos/codecommit/hello-world

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" == "hello-world"
jsonpath "$.full_name" == "hello-world"
jsonpath "$.description" isString
jsonpath "$.private" == true
jsonpath "$.default_branch" isString

# Wrong owner → 404
GET http://{{host}}/repos/wrong-owner/hello-world

HTTP 404

# Repo not found → 404 (CodeCommit returns 400 RepositoryDoesNotExistException;
# confusio maps this to 404)
GET http://{{host}}/repos/codecommit/no-such-repo

HTTP 404

# GET /repositories — all CodeCommit repos in the account
GET http://{{host}}/repositories

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" isString

# page > 1 is not supported (CodeCommit uses cursor-based pagination)
GET http://{{host}}/repositories?page=2

HTTP 422

# GET /repos/{owner}/{repo}/branches — list branches
GET http://{{host}}/repos/codecommit/hello-world/branches

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" isString
jsonpath "$[0].commit" isCollection
jsonpath "$[0].protected" isBoolean

# Wrong owner → 404
GET http://{{host}}/repos/wrong-owner/hello-world/branches

HTTP 404
