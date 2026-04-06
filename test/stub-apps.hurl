# Apps API — no native GitHub Apps equivalent.
# All Apps endpoints return 404.

# GET /app
GET http://{{host}}/app

HTTP 404

# GET /app/hook/config
GET http://{{host}}/app/hook/config

HTTP 404

# PATCH /app/hook/config
PATCH http://{{host}}/app/hook/config
Content-Type: application/json
{}

HTTP 404

# GET /app/hook/deliveries
GET http://{{host}}/app/hook/deliveries

HTTP 404

# GET /app/hook/deliveries/{delivery_id}
GET http://{{host}}/app/hook/deliveries/1

HTTP 404

# POST /app/hook/deliveries/{delivery_id}/attempts
POST http://{{host}}/app/hook/deliveries/1/attempts
Content-Type: application/json
{}

HTTP 404

# GET /app/installation-requests
GET http://{{host}}/app/installation-requests

HTTP 404

# GET /app/installations
GET http://{{host}}/app/installations

HTTP 404

# GET /app/installations/{installation_id}
GET http://{{host}}/app/installations/1

HTTP 404

# DELETE /app/installations/{installation_id}
DELETE http://{{host}}/app/installations/1

HTTP 404

# POST /app/installations/{installation_id}/access_tokens
POST http://{{host}}/app/installations/1/access_tokens
Content-Type: application/json
{}

HTTP 404

# PUT /app/installations/{installation_id}/suspended
PUT http://{{host}}/app/installations/1/suspended
Content-Type: application/json
{}

HTTP 404

# DELETE /app/installations/{installation_id}/suspended
DELETE http://{{host}}/app/installations/1/suspended

HTTP 404

# GET /apps/{app_slug}
GET http://{{host}}/apps/my-app

HTTP 404

# POST /app-manifests/{code}/conversions
POST http://{{host}}/app-manifests/abc123/conversions
Content-Type: application/json
{}

HTTP 404

# GET /installation/repositories
GET http://{{host}}/installation/repositories

HTTP 404

# DELETE /installation/token
DELETE http://{{host}}/installation/token

HTTP 404

# POST /applications/{client_id}/token
POST http://{{host}}/applications/myclientid/token
Content-Type: application/json
{"access_token": "testtoken"}

HTTP 404

# PATCH /applications/{client_id}/token
PATCH http://{{host}}/applications/myclientid/token
Content-Type: application/json
{"access_token": "testtoken"}

HTTP 404

# DELETE /applications/{client_id}/token
DELETE http://{{host}}/applications/myclientid/token

HTTP 404

# POST /applications/{client_id}/token/scoped
POST http://{{host}}/applications/myclientid/token/scoped
Content-Type: application/json
{"access_token": "testtoken"}

HTTP 404

# DELETE /applications/{client_id}/grant
DELETE http://{{host}}/applications/myclientid/grant

HTTP 404

# GET /orgs/{org}/installation
GET http://{{host}}/orgs/testorg/installation

HTTP 404

# GET /orgs/{org}/installations
GET http://{{host}}/orgs/testorg/installations

HTTP 404

# GET /repos/{owner}/{repo}/installation
GET http://{{host}}/repos/octocat/hello-world/installation

HTTP 404

# GET /user/installations
GET http://{{host}}/user/installations

HTTP 404

# GET /user/installations/{installation_id}/repositories
GET http://{{host}}/user/installations/1/repositories

HTTP 404

# PUT /user/installations/{installation_id}/repositories/{repository_id}
PUT http://{{host}}/user/installations/1/repositories/1
Content-Type: application/json
{}

HTTP 404

# DELETE /user/installations/{installation_id}/repositories/{repository_id}
DELETE http://{{host}}/user/installations/1/repositories/1

HTTP 404

# GET /users/{username}/installation
GET http://{{host}}/users/octocat/installation

HTTP 404
