# Code Scanning API — CodeCommit backend.
# CodeCommit has no native code scanning API.
# List endpoints return empty collections; per-resource endpoints return 501.

# GET /orgs/{org}/code-scanning/alerts — no CodeCommit equivalent; returns empty list
GET http://{{host}}/orgs/testorg/code-scanning/alerts
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /repos/{owner}/{repo}/code-scanning/alerts — no CodeCommit equivalent; returns empty list
GET http://{{host}}/repos/codecommit/hello-world/code-scanning/alerts
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /repos/{owner}/{repo}/code-scanning/alerts/{alert_number} — no CodeCommit equivalent
GET http://{{host}}/repos/codecommit/hello-world/code-scanning/alerts/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PATCH /repos/{owner}/{repo}/code-scanning/alerts/{alert_number} — no CodeCommit equivalent
PATCH http://{{host}}/repos/codecommit/hello-world/code-scanning/alerts/1
Authorization: token testtoken
Content-Type: application/json
{"state": "dismissed"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/autofix — no CodeCommit equivalent
GET http://{{host}}/repos/codecommit/hello-world/code-scanning/alerts/1/autofix
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/autofix — no CodeCommit equivalent
POST http://{{host}}/repos/codecommit/hello-world/code-scanning/alerts/1/autofix
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/autofix/commits — no CodeCommit equivalent
POST http://{{host}}/repos/codecommit/hello-world/code-scanning/alerts/1/autofix/commits
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/instances — returns empty list
GET http://{{host}}/repos/codecommit/hello-world/code-scanning/alerts/1/instances
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /repos/{owner}/{repo}/code-scanning/analyses — no CodeCommit equivalent; returns empty list
GET http://{{host}}/repos/codecommit/hello-world/code-scanning/analyses
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /repos/{owner}/{repo}/code-scanning/analyses/{analysis_id} — no CodeCommit equivalent
GET http://{{host}}/repos/codecommit/hello-world/code-scanning/analyses/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /repos/{owner}/{repo}/code-scanning/analyses/{analysis_id} — no CodeCommit equivalent
DELETE http://{{host}}/repos/codecommit/hello-world/code-scanning/analyses/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/codeql/databases — no CodeCommit equivalent
GET http://{{host}}/repos/codecommit/hello-world/code-scanning/codeql/databases
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/codeql/databases/{language} — no CodeCommit equivalent
GET http://{{host}}/repos/codecommit/hello-world/code-scanning/codeql/databases/python
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /repos/{owner}/{repo}/code-scanning/codeql/databases/{language} — no CodeCommit equivalent
DELETE http://{{host}}/repos/codecommit/hello-world/code-scanning/codeql/databases/python
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /repos/{owner}/{repo}/code-scanning/codeql/variant-analyses — no CodeCommit equivalent
POST http://{{host}}/repos/codecommit/hello-world/code-scanning/codeql/variant-analyses
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/codeql/variant-analyses/{id} — no CodeCommit equivalent
GET http://{{host}}/repos/codecommit/hello-world/code-scanning/codeql/variant-analyses/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/codeql/variant-analyses/{id}/repos/{owner}/{repo} — no CodeCommit equivalent
GET http://{{host}}/repos/codecommit/hello-world/code-scanning/codeql/variant-analyses/1/repos/codecommit/hello-world
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/default-setup — no CodeCommit equivalent
GET http://{{host}}/repos/codecommit/hello-world/code-scanning/default-setup
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PATCH /repos/{owner}/{repo}/code-scanning/default-setup — no CodeCommit equivalent
PATCH http://{{host}}/repos/codecommit/hello-world/code-scanning/default-setup
Authorization: token testtoken
Content-Type: application/json
{"state": "configured"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /repos/{owner}/{repo}/code-scanning/sarifs — no CodeCommit equivalent
POST http://{{host}}/repos/codecommit/hello-world/code-scanning/sarifs
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/sarifs/{sarif_id} — no CodeCommit equivalent
GET http://{{host}}/repos/codecommit/hello-world/code-scanning/sarifs/abc123
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString
