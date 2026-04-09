# Migrations API — CodeCommit backend.
# CodeCommit has no org/user migration export API matching GitHub's
# stateful multi-repo model. confusio returns fixed responses.

# GET /orgs/{org}/migrations — no migrations (empty list)
GET http://{{host}}/orgs/testorg/migrations

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# POST /orgs/{org}/migrations — not supported
POST http://{{host}}/orgs/testorg/migrations
Content-Type: application/json
{"repositories": ["hello-world"]}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /orgs/{org}/migrations/{migration_id} — not found
GET http://{{host}}/orgs/testorg/migrations/1

HTTP 404

# GET /orgs/{org}/migrations/{migration_id}/archive — not found
GET http://{{host}}/orgs/testorg/migrations/1/archive

HTTP 404

# DELETE /orgs/{org}/migrations/{migration_id}/archive — not found
DELETE http://{{host}}/orgs/testorg/migrations/1/archive

HTTP 404

# DELETE /orgs/{org}/migrations/{migration_id}/repos/{repo_name}/lock — not found
DELETE http://{{host}}/orgs/testorg/migrations/1/repos/hello-world/lock

HTTP 404

# GET /orgs/{org}/migrations/{migration_id}/repositories — no repos (empty list)
GET http://{{host}}/orgs/testorg/migrations/1/repositories

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# GET /user/migrations — no migrations (empty list)
GET http://{{host}}/user/migrations

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# POST /user/migrations — not supported
POST http://{{host}}/user/migrations
Content-Type: application/json
{"repositories": ["octocat/hello-world"]}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /user/migrations/{migration_id} — not found
GET http://{{host}}/user/migrations/1

HTTP 404

# GET /user/migrations/{migration_id}/archive — not found
GET http://{{host}}/user/migrations/1/archive

HTTP 404

# DELETE /user/migrations/{migration_id}/archive — not found
DELETE http://{{host}}/user/migrations/1/archive

HTTP 404

# DELETE /user/migrations/{migration_id}/repos/{repo_name}/lock — not found
DELETE http://{{host}}/user/migrations/1/repos/hello-world/lock

HTTP 404

# GET /user/migrations/{migration_id}/repositories — no repos (empty list)
GET http://{{host}}/user/migrations/1/repositories

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# Source imports — deprecated May 2023, all return 410 Gone.

# GET /repos/{owner}/{repo}/import
GET http://{{host}}/repos/octocat/hello-world/import

HTTP 410
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PUT /repos/{owner}/{repo}/import
PUT http://{{host}}/repos/octocat/hello-world/import
Content-Type: application/json
{"vcs_url": "https://example.com/repo.git"}

HTTP 410

# PATCH /repos/{owner}/{repo}/import
PATCH http://{{host}}/repos/octocat/hello-world/import
Content-Type: application/json
{"vcs": "git"}

HTTP 410

# DELETE /repos/{owner}/{repo}/import
DELETE http://{{host}}/repos/octocat/hello-world/import

HTTP 410

# GET /repos/{owner}/{repo}/import/authors
GET http://{{host}}/repos/octocat/hello-world/import/authors

HTTP 410

# PATCH /repos/{owner}/{repo}/import/authors/{author_id}
PATCH http://{{host}}/repos/octocat/hello-world/import/authors/1
Content-Type: application/json
{"email": "test@example.com"}

HTTP 410

# GET /repos/{owner}/{repo}/import/large_files
GET http://{{host}}/repos/octocat/hello-world/import/large_files

HTTP 410

# PATCH /repos/{owner}/{repo}/import/lfs
PATCH http://{{host}}/repos/octocat/hello-world/import/lfs
Content-Type: application/json
{"use_lfs": true}

HTTP 410
