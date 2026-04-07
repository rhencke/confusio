# Code Scanning API — Azure DevOps Advanced Security (GHAzDO) backend.
# Alerts and analyses proxy to ADO Advanced Security API.
# Endpoints without an ADO equivalent return 501.

# GET /orgs/{org}/code-scanning/alerts — no ADO org-level endpoint; returns empty list
GET http://{{host}}/orgs/testorg/code-scanning/alerts
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /repos/{owner}/{repo}/code-scanning/alerts
GET http://{{host}}/repos/octocat/hello-world/code-scanning/alerts
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$[0].number" == 1
jsonpath "$[0].state" == "open"
jsonpath "$[0].rule.id" isString
jsonpath "$[0].tool.name" isString

# GET /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}
GET http://{{host}}/repos/octocat/hello-world/code-scanning/alerts/1
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.number" == 1
jsonpath "$.state" == "open"
jsonpath "$.rule.id" isString
jsonpath "$.tool.name" isString

# PATCH /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}
PATCH http://{{host}}/repos/octocat/hello-world/code-scanning/alerts/1
Authorization: token testtoken
Content-Type: application/json
{"state": "dismissed", "dismissed_reason": "won't fix", "dismissed_comment": "Not exploitable"}

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.number" == 1
jsonpath "$.state" == "dismissed"

# GET /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/autofix — no ADO equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/alerts/1/autofix
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/autofix — no ADO equivalent
POST http://{{host}}/repos/octocat/hello-world/code-scanning/alerts/1/autofix
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/autofix/commits — no ADO equivalent
POST http://{{host}}/repos/octocat/hello-world/code-scanning/alerts/1/autofix/commits
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/instances — returns empty list
GET http://{{host}}/repos/octocat/hello-world/code-scanning/alerts/1/instances
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /repos/{owner}/{repo}/code-scanning/analyses
GET http://{{host}}/repos/octocat/hello-world/code-scanning/analyses
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$[0].id" == 10
jsonpath "$[0].commit_sha" isString
jsonpath "$[0].tool.name" isString

# GET /repos/{owner}/{repo}/code-scanning/analyses/{analysis_id} — no direct ADO equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/analyses/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /repos/{owner}/{repo}/code-scanning/analyses/{analysis_id} — no ADO equivalent
DELETE http://{{host}}/repos/octocat/hello-world/code-scanning/analyses/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/codeql/databases — no ADO equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/codeql/databases
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/codeql/databases/{language} — no ADO equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/codeql/databases/python
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /repos/{owner}/{repo}/code-scanning/codeql/databases/{language} — no ADO equivalent
DELETE http://{{host}}/repos/octocat/hello-world/code-scanning/codeql/databases/python
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /repos/{owner}/{repo}/code-scanning/codeql/variant-analyses — no ADO equivalent
POST http://{{host}}/repos/octocat/hello-world/code-scanning/codeql/variant-analyses
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/codeql/variant-analyses/{id} — no ADO equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/codeql/variant-analyses/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/codeql/variant-analyses/{id}/repos/{owner}/{repo} — no ADO equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/codeql/variant-analyses/1/repos/octocat/hello-world
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/default-setup — no ADO equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/default-setup
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PATCH /repos/{owner}/{repo}/code-scanning/default-setup — no ADO equivalent
PATCH http://{{host}}/repos/octocat/hello-world/code-scanning/default-setup
Authorization: token testtoken
Content-Type: application/json
{"state": "configured"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /repos/{owner}/{repo}/code-scanning/sarifs
POST http://{{host}}/repos/octocat/hello-world/code-scanning/sarifs
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 202
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" isString

# GET /repos/{owner}/{repo}/code-scanning/sarifs/{sarif_id} — no ADO equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/sarifs/abc123
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString
