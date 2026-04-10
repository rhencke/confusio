# Projects API — Azure DevOps backend.
# Azure DevOps has no native equivalent to GitHub's ProjectsV2 kanban API.
# All 26 endpoints use defaults: list endpoints return empty arrays, per-resource and mutation endpoints return 501.

# GET /orgs/{org}/projectsV2 — no ADO equivalent; returns empty list
GET http://{{host}}/orgs/testorg/projectsV2
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /orgs/{org}/projectsV2/{project_number} — no ADO equivalent
GET http://{{host}}/orgs/testorg/projectsV2/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /orgs/{org}/projectsV2/{project_number}/drafts — no ADO equivalent
POST http://{{host}}/orgs/testorg/projectsV2/1/drafts
Authorization: token testtoken
Content-Type: application/json
{"title": "Draft issue"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /orgs/{org}/projectsV2/{project_number}/fields — no ADO equivalent; returns empty list
GET http://{{host}}/orgs/testorg/projectsV2/1/fields
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# POST /orgs/{org}/projectsV2/{project_number}/fields — no ADO equivalent
POST http://{{host}}/orgs/testorg/projectsV2/1/fields
Authorization: token testtoken
Content-Type: application/json
{"name": "Status"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /orgs/{org}/projectsV2/{project_number}/fields/{field_id} — no ADO equivalent
GET http://{{host}}/orgs/testorg/projectsV2/1/fields/42
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /orgs/{org}/projectsV2/{project_number}/items — no ADO equivalent; returns empty list
GET http://{{host}}/orgs/testorg/projectsV2/1/items
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# POST /orgs/{org}/projectsV2/{project_number}/items — no ADO equivalent
POST http://{{host}}/orgs/testorg/projectsV2/1/items
Authorization: token testtoken
Content-Type: application/json
{"contentId": "I_123"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /orgs/{org}/projectsV2/{project_number}/items/{item_id} — no ADO equivalent
GET http://{{host}}/orgs/testorg/projectsV2/1/items/7
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PATCH /orgs/{org}/projectsV2/{project_number}/items/{item_id} — no ADO equivalent
PATCH http://{{host}}/orgs/testorg/projectsV2/1/items/7
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /orgs/{org}/projectsV2/{project_number}/items/{item_id} — no ADO equivalent
DELETE http://{{host}}/orgs/testorg/projectsV2/1/items/7
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /orgs/{org}/projectsV2/{project_number}/views — no ADO equivalent
POST http://{{host}}/orgs/testorg/projectsV2/1/views
Authorization: token testtoken
Content-Type: application/json
{"name": "My view"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /orgs/{org}/projectsV2/{project_number}/views/{view_number}/items — no ADO equivalent; returns empty list
GET http://{{host}}/orgs/testorg/projectsV2/1/views/2/items
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# POST /user/{user_id}/projectsV2/{project_number}/drafts — no ADO equivalent
POST http://{{host}}/user/1/projectsV2/1/drafts
Authorization: token testtoken
Content-Type: application/json
{"title": "Draft issue"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /users/{user_id}/projectsV2/{project_number}/views — no ADO equivalent
POST http://{{host}}/users/1/projectsV2/1/views
Authorization: token testtoken
Content-Type: application/json
{"name": "My view"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /users/{username}/projectsV2 — no ADO equivalent; returns empty list
GET http://{{host}}/users/octocat/projectsV2
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /users/{username}/projectsV2/{project_number} — no ADO equivalent
GET http://{{host}}/users/octocat/projectsV2/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /users/{username}/projectsV2/{project_number}/fields — no ADO equivalent; returns empty list
GET http://{{host}}/users/octocat/projectsV2/1/fields
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# POST /users/{username}/projectsV2/{project_number}/fields — no ADO equivalent
POST http://{{host}}/users/octocat/projectsV2/1/fields
Authorization: token testtoken
Content-Type: application/json
{"name": "Status"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /users/{username}/projectsV2/{project_number}/fields/{field_id} — no ADO equivalent
GET http://{{host}}/users/octocat/projectsV2/1/fields/42
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /users/{username}/projectsV2/{project_number}/items — no ADO equivalent; returns empty list
GET http://{{host}}/users/octocat/projectsV2/1/items
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# POST /users/{username}/projectsV2/{project_number}/items — no ADO equivalent
POST http://{{host}}/users/octocat/projectsV2/1/items
Authorization: token testtoken
Content-Type: application/json
{"contentId": "I_123"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /users/{username}/projectsV2/{project_number}/items/{item_id} — no ADO equivalent
GET http://{{host}}/users/octocat/projectsV2/1/items/7
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PATCH /users/{username}/projectsV2/{project_number}/items/{item_id} — no ADO equivalent
PATCH http://{{host}}/users/octocat/projectsV2/1/items/7
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /users/{username}/projectsV2/{project_number}/items/{item_id} — no ADO equivalent
DELETE http://{{host}}/users/octocat/projectsV2/1/items/7
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /users/{username}/projectsV2/{project_number}/views/{view_number}/items — no ADO equivalent; returns empty list
GET http://{{host}}/users/octocat/projectsV2/1/views/2/items
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
