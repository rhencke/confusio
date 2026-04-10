# Dependabot API — Azure DevOps Advanced Security backend.
# Dependency alerts proxy to ADO Advanced Security API (alertType=dependency).
# Secrets and repository-access have no ADO equivalent and return 501.

# GET /enterprises/{enterprise}/dependabot/alerts — no ADO equivalent; returns empty list
GET http://{{host}}/enterprises/testenterprise/dependabot/alerts
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /orgs/{org}/dependabot/alerts — no ADO equivalent; returns empty list
GET http://{{host}}/orgs/testorg/dependabot/alerts
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /repos/{owner}/{repo}/dependabot/alerts → GET /{owner}/_apis/advancedsecurity/alerts/{repo}?alertType=dependency
GET http://{{host}}/repos/octocat/hello-world/dependabot/alerts
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$[0].number" == 2
jsonpath "$[0].state" == "open"
jsonpath "$[0].security_advisory.cve_id" == "CVE-2019-10744"
jsonpath "$[0].security_advisory.severity" == "high"
jsonpath "$[0].security_advisory.summary" isString
jsonpath "$[0].dependency.package.name" == "lodash"
jsonpath "$[0].dependency.package.ecosystem" == "npm"

# GET /repos/{owner}/{repo}/dependabot/alerts/{alert_number} → GET /{owner}/_apis/advancedsecurity/alerts/{repo}/{alertId}
GET http://{{host}}/repos/octocat/hello-world/dependabot/alerts/2
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.number" == 2
jsonpath "$.state" == "open"
jsonpath "$.security_advisory.cve_id" == "CVE-2019-10744"
jsonpath "$.dependency.package.name" == "lodash"

# PATCH /repos/{owner}/{repo}/dependabot/alerts/{alert_number} → PATCH /{owner}/_apis/advancedsecurity/alerts/{repo}/{alertId}
PATCH http://{{host}}/repos/octocat/hello-world/dependabot/alerts/2
Authorization: token testtoken
Content-Type: application/json
{"state": "dismissed", "dismissed_reason": "tolerable_risk"}

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.number" == 2
jsonpath "$.state" == "dismissed"
jsonpath "$.dismissed_at" isString

# GET /orgs/{org}/dependabot/secrets — no ADO equivalent
GET http://{{host}}/orgs/testorg/dependabot/secrets
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.secrets" isCollection

# GET /orgs/{org}/dependabot/secrets/public-key — no ADO equivalent
GET http://{{host}}/orgs/testorg/dependabot/secrets/public-key
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /orgs/{org}/dependabot/secrets/{secret_name} — no ADO equivalent
GET http://{{host}}/orgs/testorg/dependabot/secrets/MY_SECRET
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PUT /orgs/{org}/dependabot/secrets/{secret_name} — no ADO equivalent
PUT http://{{host}}/orgs/testorg/dependabot/secrets/MY_SECRET
Authorization: token testtoken
Content-Type: application/json
{"encrypted_value": "abc", "key_id": "1"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /orgs/{org}/dependabot/secrets/{secret_name} — no ADO equivalent
DELETE http://{{host}}/orgs/testorg/dependabot/secrets/MY_SECRET
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /orgs/{org}/dependabot/secrets/{secret_name}/repositories — no ADO equivalent
GET http://{{host}}/orgs/testorg/dependabot/secrets/MY_SECRET/repositories
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.repositories" isCollection

# PUT /orgs/{org}/dependabot/secrets/{secret_name}/repositories — no ADO equivalent
PUT http://{{host}}/orgs/testorg/dependabot/secrets/MY_SECRET/repositories
Authorization: token testtoken
Content-Type: application/json
{"selected_repository_ids": [1]}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PUT /orgs/{org}/dependabot/secrets/{secret_name}/repositories/{repository_id} — no ADO equivalent
PUT http://{{host}}/orgs/testorg/dependabot/secrets/MY_SECRET/repositories/1
Authorization: token testtoken
Content-Length: 0

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /orgs/{org}/dependabot/secrets/{secret_name}/repositories/{repository_id} — no ADO equivalent
DELETE http://{{host}}/orgs/testorg/dependabot/secrets/MY_SECRET/repositories/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /organizations/{org}/dependabot/repository-access — no ADO equivalent
GET http://{{host}}/organizations/testorg/dependabot/repository-access
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PATCH /organizations/{org}/dependabot/repository-access — no ADO equivalent
PATCH http://{{host}}/organizations/testorg/dependabot/repository-access
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PUT /organizations/{org}/dependabot/repository-access/default-level — no ADO equivalent
PUT http://{{host}}/organizations/testorg/dependabot/repository-access/default-level
Authorization: token testtoken
Content-Type: application/json
{"default_level": "public"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/dependabot/secrets — no ADO equivalent
GET http://{{host}}/repos/octocat/hello-world/dependabot/secrets
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.secrets" isCollection

# GET /repos/{owner}/{repo}/dependabot/secrets/public-key — no ADO equivalent
GET http://{{host}}/repos/octocat/hello-world/dependabot/secrets/public-key
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/dependabot/secrets/{secret_name} — no ADO equivalent
GET http://{{host}}/repos/octocat/hello-world/dependabot/secrets/MY_SECRET
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PUT /repos/{owner}/{repo}/dependabot/secrets/{secret_name} — no ADO equivalent
PUT http://{{host}}/repos/octocat/hello-world/dependabot/secrets/MY_SECRET
Authorization: token testtoken
Content-Type: application/json
{"encrypted_value": "abc", "key_id": "1"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /repos/{owner}/{repo}/dependabot/secrets/{secret_name} — no ADO equivalent
DELETE http://{{host}}/repos/octocat/hello-world/dependabot/secrets/MY_SECRET
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString
