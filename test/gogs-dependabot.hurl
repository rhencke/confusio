# Dependabot API — Gogs backend.
# Gogs has no native Dependabot API.
# Alert and secret list endpoints return empty collections; per-resource endpoints return 501.

# GET /enterprises/{enterprise}/dependabot/alerts — no Gogs equivalent; returns empty list
GET http://{{host}}/enterprises/testenterprise/dependabot/alerts
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /orgs/{org}/dependabot/alerts — no Gogs equivalent; returns empty list
GET http://{{host}}/orgs/testorg/dependabot/alerts
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /orgs/{org}/dependabot/secrets — no Gogs equivalent; returns empty envelope
GET http://{{host}}/orgs/testorg/dependabot/secrets
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.secrets" isCollection

# GET /orgs/{org}/dependabot/secrets/public-key — no Gogs equivalent
GET http://{{host}}/orgs/testorg/dependabot/secrets/public-key
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /orgs/{org}/dependabot/secrets/{secret_name} — no Gogs equivalent
GET http://{{host}}/orgs/testorg/dependabot/secrets/MY_SECRET
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PUT /orgs/{org}/dependabot/secrets/{secret_name} — no Gogs equivalent
PUT http://{{host}}/orgs/testorg/dependabot/secrets/MY_SECRET
Authorization: token testtoken
Content-Type: application/json
{"encrypted_value": "abc", "key_id": "1"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /orgs/{org}/dependabot/secrets/{secret_name} — no Gogs equivalent
DELETE http://{{host}}/orgs/testorg/dependabot/secrets/MY_SECRET
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /orgs/{org}/dependabot/secrets/{secret_name}/repositories — no Gogs equivalent; returns empty envelope
GET http://{{host}}/orgs/testorg/dependabot/secrets/MY_SECRET/repositories
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.repositories" isCollection

# PUT /orgs/{org}/dependabot/secrets/{secret_name}/repositories — no Gogs equivalent
PUT http://{{host}}/orgs/testorg/dependabot/secrets/MY_SECRET/repositories
Authorization: token testtoken
Content-Type: application/json
{"selected_repository_ids": [1]}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PUT /orgs/{org}/dependabot/secrets/{secret_name}/repositories/{repository_id} — no Gogs equivalent
PUT http://{{host}}/orgs/testorg/dependabot/secrets/MY_SECRET/repositories/1
Authorization: token testtoken
Content-Length: 0

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /orgs/{org}/dependabot/secrets/{secret_name}/repositories/{repository_id} — no Gogs equivalent
DELETE http://{{host}}/orgs/testorg/dependabot/secrets/MY_SECRET/repositories/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /organizations/{org}/dependabot/repository-access — no Gogs equivalent
GET http://{{host}}/organizations/testorg/dependabot/repository-access
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PATCH /organizations/{org}/dependabot/repository-access — no Gogs equivalent
PATCH http://{{host}}/organizations/testorg/dependabot/repository-access
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PUT /organizations/{org}/dependabot/repository-access/default-level — no Gogs equivalent
PUT http://{{host}}/organizations/testorg/dependabot/repository-access/default-level
Authorization: token testtoken
Content-Type: application/json
{"default_level": "public"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/dependabot/alerts — no Gogs equivalent; returns empty list
GET http://{{host}}/repos/octocat/hello-world/dependabot/alerts
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /repos/{owner}/{repo}/dependabot/alerts/{alert_number} — no Gogs equivalent
GET http://{{host}}/repos/octocat/hello-world/dependabot/alerts/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PATCH /repos/{owner}/{repo}/dependabot/alerts/{alert_number} — no Gogs equivalent
PATCH http://{{host}}/repos/octocat/hello-world/dependabot/alerts/1
Authorization: token testtoken
Content-Type: application/json
{"state": "dismissed"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/dependabot/secrets — no Gogs equivalent; returns empty envelope
GET http://{{host}}/repos/octocat/hello-world/dependabot/secrets
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.secrets" isCollection

# GET /repos/{owner}/{repo}/dependabot/secrets/public-key — no Gogs equivalent
GET http://{{host}}/repos/octocat/hello-world/dependabot/secrets/public-key
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/dependabot/secrets/{secret_name} — no Gogs equivalent
GET http://{{host}}/repos/octocat/hello-world/dependabot/secrets/MY_SECRET
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PUT /repos/{owner}/{repo}/dependabot/secrets/{secret_name} — no Gogs equivalent
PUT http://{{host}}/repos/octocat/hello-world/dependabot/secrets/MY_SECRET
Authorization: token testtoken
Content-Type: application/json
{"encrypted_value": "abc", "key_id": "1"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /repos/{owner}/{repo}/dependabot/secrets/{secret_name} — no Gogs equivalent
DELETE http://{{host}}/repos/octocat/hello-world/dependabot/secrets/MY_SECRET
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString
