# Migrations API — GitLab backend.
# GitLab has a per-project export API (POST /projects/:id/export,
# GET /projects/:id/export/download) but no org- or user-level migration
# concept matching GitHub's stateful multi-repo model. confusio returns
# fixed responses; the GitLab export API is not proxied.

# GET /orgs/{org}/migrations — no migrations (empty list)
GET http://{{host}}/orgs/testorg/migrations
Authorization: Bearer testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# POST /orgs/{org}/migrations — not supported
POST http://{{host}}/orgs/testorg/migrations
Authorization: Bearer testtoken
Content-Type: application/json
{"repositories": ["hello-world"]}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /orgs/{org}/migrations/{migration_id} — not found
GET http://{{host}}/orgs/testorg/migrations/1
Authorization: Bearer testtoken

HTTP 404

# GET /orgs/{org}/migrations/{migration_id}/archive — not found
GET http://{{host}}/orgs/testorg/migrations/1/archive
Authorization: Bearer testtoken

HTTP 404

# DELETE /orgs/{org}/migrations/{migration_id}/archive — not found
DELETE http://{{host}}/orgs/testorg/migrations/1/archive
Authorization: Bearer testtoken

HTTP 404

# DELETE /orgs/{org}/migrations/{migration_id}/repos/{repo_name}/lock — not found
DELETE http://{{host}}/orgs/testorg/migrations/1/repos/hello-world/lock
Authorization: Bearer testtoken

HTTP 404

# GET /orgs/{org}/migrations/{migration_id}/repositories — no repos (empty list)
GET http://{{host}}/orgs/testorg/migrations/1/repositories
Authorization: Bearer testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# GET /user/migrations — no migrations (empty list)
GET http://{{host}}/user/migrations
Authorization: Bearer testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# POST /user/migrations — not supported
POST http://{{host}}/user/migrations
Authorization: Bearer testtoken
Content-Type: application/json
{"repositories": ["octocat/hello-world"]}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /user/migrations/{migration_id} — not found
GET http://{{host}}/user/migrations/1
Authorization: Bearer testtoken

HTTP 404

# GET /user/migrations/{migration_id}/archive — not found
GET http://{{host}}/user/migrations/1/archive
Authorization: Bearer testtoken

HTTP 404

# DELETE /user/migrations/{migration_id}/archive — not found
DELETE http://{{host}}/user/migrations/1/archive
Authorization: Bearer testtoken

HTTP 404

# DELETE /user/migrations/{migration_id}/repos/{repo_name}/lock — not found
DELETE http://{{host}}/user/migrations/1/repos/hello-world/lock
Authorization: Bearer testtoken

HTTP 404

# GET /user/migrations/{migration_id}/repositories — no repos (empty list)
GET http://{{host}}/user/migrations/1/repositories
Authorization: Bearer testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# Source imports — deprecated May 2023, all return 410 Gone.

# GET /repos/{owner}/{repo}/import
GET http://{{host}}/repos/octocat/hello-world/import
Authorization: Bearer testtoken

HTTP 410
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PUT /repos/{owner}/{repo}/import
PUT http://{{host}}/repos/octocat/hello-world/import
Authorization: Bearer testtoken
Content-Type: application/json
{"vcs_url": "https://example.com/repo.git"}

HTTP 410

# PATCH /repos/{owner}/{repo}/import
PATCH http://{{host}}/repos/octocat/hello-world/import
Authorization: Bearer testtoken
Content-Type: application/json
{"vcs": "git"}

HTTP 410

# DELETE /repos/{owner}/{repo}/import
DELETE http://{{host}}/repos/octocat/hello-world/import
Authorization: Bearer testtoken

HTTP 410

# GET /repos/{owner}/{repo}/import/authors
GET http://{{host}}/repos/octocat/hello-world/import/authors
Authorization: Bearer testtoken

HTTP 410

# PATCH /repos/{owner}/{repo}/import/authors/{author_id}
PATCH http://{{host}}/repos/octocat/hello-world/import/authors/1
Authorization: Bearer testtoken
Content-Type: application/json
{"email": "test@example.com"}

HTTP 410

# GET /repos/{owner}/{repo}/import/large_files
GET http://{{host}}/repos/octocat/hello-world/import/large_files
Authorization: Bearer testtoken

HTTP 410

# PATCH /repos/{owner}/{repo}/import/lfs
PATCH http://{{host}}/repos/octocat/hello-world/import/lfs
Authorization: Bearer testtoken
Content-Type: application/json
{"use_lfs": true}

HTTP 410
