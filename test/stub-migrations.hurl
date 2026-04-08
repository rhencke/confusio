# Migrations API — default stubs for backends without native migration support.
# List endpoints return empty arrays (200); single-resource endpoints return 501.

# --- Organization migrations ---

# GET /orgs/{org}/migrations — empty list
GET http://{{host}}/orgs/testorg/migrations
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# POST /orgs/{org}/migrations — not supported
POST http://{{host}}/orgs/testorg/migrations
Authorization: token testtoken
Content-Type: application/json
{"repositories": ["testorg/hello-world"]}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /orgs/{org}/migrations/{migration_id} — not supported
GET http://{{host}}/orgs/testorg/migrations/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /orgs/{org}/migrations/{migration_id}/archive — not supported
GET http://{{host}}/orgs/testorg/migrations/1/archive
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /orgs/{org}/migrations/{migration_id}/archive — not supported
DELETE http://{{host}}/orgs/testorg/migrations/1/archive
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /orgs/{org}/migrations/{migration_id}/repos/{repo_name}/lock — not supported
DELETE http://{{host}}/orgs/testorg/migrations/1/repos/hello-world/lock
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /orgs/{org}/migrations/{migration_id}/repositories — empty list
GET http://{{host}}/orgs/testorg/migrations/1/repositories
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# --- Source imports (deprecated) ---

# GET /repos/{owner}/{repo}/import — not supported
GET http://{{host}}/repos/octocat/hello-world/import
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PUT /repos/{owner}/{repo}/import — not supported
PUT http://{{host}}/repos/octocat/hello-world/import
Authorization: token testtoken
Content-Type: application/json
{"vcs_url": "https://example.com/repo.git"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PATCH /repos/{owner}/{repo}/import — not supported
PATCH http://{{host}}/repos/octocat/hello-world/import
Authorization: token testtoken
Content-Type: application/json
{"vcs_username": "user", "vcs_password": "pass"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /repos/{owner}/{repo}/import — not supported
DELETE http://{{host}}/repos/octocat/hello-world/import
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/import/authors — empty list
GET http://{{host}}/repos/octocat/hello-world/import/authors
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# PATCH /repos/{owner}/{repo}/import/authors/{author_id} — not supported
PATCH http://{{host}}/repos/octocat/hello-world/import/authors/1
Authorization: token testtoken
Content-Type: application/json
{"email": "user@example.com", "name": "User"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/import/large_files — empty list
GET http://{{host}}/repos/octocat/hello-world/import/large_files
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# PATCH /repos/{owner}/{repo}/import/lfs — not supported
PATCH http://{{host}}/repos/octocat/hello-world/import/lfs
Authorization: token testtoken
Content-Type: application/json
{"use_lfs": "opt_in"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# --- User migrations ---

# GET /user/migrations — empty list
GET http://{{host}}/user/migrations
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# POST /user/migrations — not supported
POST http://{{host}}/user/migrations
Authorization: token testtoken
Content-Type: application/json
{"repositories": ["octocat/hello-world"]}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /user/migrations/{migration_id} — not supported
GET http://{{host}}/user/migrations/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /user/migrations/{migration_id}/archive — not supported
GET http://{{host}}/user/migrations/1/archive
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /user/migrations/{migration_id}/archive — not supported
DELETE http://{{host}}/user/migrations/1/archive
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /user/migrations/{migration_id}/repos/{repo_name}/lock — not supported
DELETE http://{{host}}/user/migrations/1/repos/hello-world/lock
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /user/migrations/{migration_id}/repositories — empty list
GET http://{{host}}/user/migrations/1/repositories
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"
