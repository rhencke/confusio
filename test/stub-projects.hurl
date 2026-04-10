# Projects API — minimal stubs for backends without native Projects support.
# List endpoints return empty arrays (200); per-resource and mutation endpoints return 501.

# GET /orgs/{org}/projectsV2
GET http://{{host}}/orgs/testorg/projectsV2
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /orgs/{org}/projectsV2/{project_number}
GET http://{{host}}/orgs/testorg/projectsV2/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /orgs/{org}/projectsV2/{project_number}/drafts
POST http://{{host}}/orgs/testorg/projectsV2/1/drafts
Authorization: token testtoken
Content-Type: application/json
{"title": "Draft issue"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /orgs/{org}/projectsV2/{project_number}/fields
GET http://{{host}}/orgs/testorg/projectsV2/1/fields
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# POST /orgs/{org}/projectsV2/{project_number}/fields
POST http://{{host}}/orgs/testorg/projectsV2/1/fields
Authorization: token testtoken
Content-Type: application/json
{"name": "Status"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /orgs/{org}/projectsV2/{project_number}/fields/{field_id}
GET http://{{host}}/orgs/testorg/projectsV2/1/fields/42
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /orgs/{org}/projectsV2/{project_number}/items
GET http://{{host}}/orgs/testorg/projectsV2/1/items
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# POST /orgs/{org}/projectsV2/{project_number}/items
POST http://{{host}}/orgs/testorg/projectsV2/1/items
Authorization: token testtoken
Content-Type: application/json
{"contentId": "I_123"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /orgs/{org}/projectsV2/{project_number}/items/{item_id}
GET http://{{host}}/orgs/testorg/projectsV2/1/items/7
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PATCH /orgs/{org}/projectsV2/{project_number}/items/{item_id}
PATCH http://{{host}}/orgs/testorg/projectsV2/1/items/7
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /orgs/{org}/projectsV2/{project_number}/items/{item_id}
DELETE http://{{host}}/orgs/testorg/projectsV2/1/items/7
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /orgs/{org}/projectsV2/{project_number}/views
POST http://{{host}}/orgs/testorg/projectsV2/1/views
Authorization: token testtoken
Content-Type: application/json
{"name": "My view"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /orgs/{org}/projectsV2/{project_number}/views/{view_number}/items
GET http://{{host}}/orgs/testorg/projectsV2/1/views/2/items
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# POST /user/{user_id}/projectsV2/{project_number}/drafts
POST http://{{host}}/user/1/projectsV2/1/drafts
Authorization: token testtoken
Content-Type: application/json
{"title": "Draft issue"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /users/{user_id}/projectsV2/{project_number}/views
POST http://{{host}}/users/1/projectsV2/1/views
Authorization: token testtoken
Content-Type: application/json
{"name": "My view"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /users/{username}/projectsV2
GET http://{{host}}/users/octocat/projectsV2
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /users/{username}/projectsV2/{project_number}
GET http://{{host}}/users/octocat/projectsV2/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /users/{username}/projectsV2/{project_number}/fields
GET http://{{host}}/users/octocat/projectsV2/1/fields
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# POST /users/{username}/projectsV2/{project_number}/fields
POST http://{{host}}/users/octocat/projectsV2/1/fields
Authorization: token testtoken
Content-Type: application/json
{"name": "Status"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /users/{username}/projectsV2/{project_number}/fields/{field_id}
GET http://{{host}}/users/octocat/projectsV2/1/fields/42
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /users/{username}/projectsV2/{project_number}/items
GET http://{{host}}/users/octocat/projectsV2/1/items
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# POST /users/{username}/projectsV2/{project_number}/items
POST http://{{host}}/users/octocat/projectsV2/1/items
Authorization: token testtoken
Content-Type: application/json
{"contentId": "I_123"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /users/{username}/projectsV2/{project_number}/items/{item_id}
GET http://{{host}}/users/octocat/projectsV2/1/items/7
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PATCH /users/{username}/projectsV2/{project_number}/items/{item_id}
PATCH http://{{host}}/users/octocat/projectsV2/1/items/7
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /users/{username}/projectsV2/{project_number}/items/{item_id}
DELETE http://{{host}}/users/octocat/projectsV2/1/items/7
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /users/{username}/projectsV2/{project_number}/views/{view_number}/items
GET http://{{host}}/users/octocat/projectsV2/1/views/2/items
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
