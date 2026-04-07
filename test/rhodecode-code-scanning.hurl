# Code Scanning API — RhodeCode backend.
# RhodeCode has no native code scanning API.
# List endpoints return empty collections; per-resource endpoints return 501.

# GET /orgs/{org}/code-scanning/alerts — no RhodeCode equivalent; returns empty list
GET http://{{host}}/orgs/testorg/code-scanning/alerts
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /repos/{owner}/{repo}/code-scanning/alerts — no RhodeCode equivalent; returns empty list
GET http://{{host}}/repos/octocat/hello-world/code-scanning/alerts
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /repos/{owner}/{repo}/code-scanning/alerts/{alert_number} — no RhodeCode equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/alerts/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PATCH /repos/{owner}/{repo}/code-scanning/alerts/{alert_number} — no RhodeCode equivalent
PATCH http://{{host}}/repos/octocat/hello-world/code-scanning/alerts/1
Authorization: token testtoken
Content-Type: application/json
{"state": "dismissed"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/autofix — no RhodeCode equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/alerts/1/autofix
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/autofix — no RhodeCode equivalent
POST http://{{host}}/repos/octocat/hello-world/code-scanning/alerts/1/autofix
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/autofix/commits — no RhodeCode equivalent
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

# GET /repos/{owner}/{repo}/code-scanning/analyses — no RhodeCode equivalent; returns empty list
GET http://{{host}}/repos/octocat/hello-world/code-scanning/analyses
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /repos/{owner}/{repo}/code-scanning/analyses/{analysis_id} — no RhodeCode equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/analyses/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /repos/{owner}/{repo}/code-scanning/analyses/{analysis_id} — no RhodeCode equivalent
DELETE http://{{host}}/repos/octocat/hello-world/code-scanning/analyses/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/codeql/databases — no RhodeCode equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/codeql/databases
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/codeql/databases/{language} — no RhodeCode equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/codeql/databases/python
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /repos/{owner}/{repo}/code-scanning/codeql/databases/{language} — no RhodeCode equivalent
DELETE http://{{host}}/repos/octocat/hello-world/code-scanning/codeql/databases/python
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /repos/{owner}/{repo}/code-scanning/codeql/variant-analyses — no RhodeCode equivalent
POST http://{{host}}/repos/octocat/hello-world/code-scanning/codeql/variant-analyses
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/codeql/variant-analyses/{id} — no RhodeCode equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/codeql/variant-analyses/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/codeql/variant-analyses/{id}/repos/{owner}/{repo} — no RhodeCode equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/codeql/variant-analyses/1/repos/octocat/hello-world
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/default-setup — no RhodeCode equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/default-setup
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PATCH /repos/{owner}/{repo}/code-scanning/default-setup — no RhodeCode equivalent
PATCH http://{{host}}/repos/octocat/hello-world/code-scanning/default-setup
Authorization: token testtoken
Content-Type: application/json
{"state": "configured"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /repos/{owner}/{repo}/code-scanning/sarifs — no RhodeCode equivalent
POST http://{{host}}/repos/octocat/hello-world/code-scanning/sarifs
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/sarifs/{sarif_id} — no RhodeCode equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/sarifs/abc123
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString
