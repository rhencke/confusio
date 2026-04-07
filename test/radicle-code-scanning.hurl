# Code Scanning API — Radicle backend.
# Radicle has no native code scanning API.
# List endpoints return empty collections; per-resource endpoints return 501.

# GET /orgs/{org}/code-scanning/alerts — no Radicle equivalent; returns empty list
GET http://{{host}}/orgs/testorg/code-scanning/alerts
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /repos/{owner}/{repo}/code-scanning/alerts — no Radicle equivalent; returns empty list
GET http://{{host}}/repos/octocat/hello-world/code-scanning/alerts
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /repos/{owner}/{repo}/code-scanning/alerts/{alert_number} — no Radicle equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/alerts/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PATCH /repos/{owner}/{repo}/code-scanning/alerts/{alert_number} — no Radicle equivalent
PATCH http://{{host}}/repos/octocat/hello-world/code-scanning/alerts/1
Authorization: token testtoken
Content-Type: application/json
{"state": "dismissed"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/autofix — no Radicle equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/alerts/1/autofix
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/autofix — no Radicle equivalent
POST http://{{host}}/repos/octocat/hello-world/code-scanning/alerts/1/autofix
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/autofix/commits — no Radicle equivalent
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

# GET /repos/{owner}/{repo}/code-scanning/analyses — no Radicle equivalent; returns empty list
GET http://{{host}}/repos/octocat/hello-world/code-scanning/analyses
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /repos/{owner}/{repo}/code-scanning/analyses/{analysis_id} — no Radicle equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/analyses/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /repos/{owner}/{repo}/code-scanning/analyses/{analysis_id} — no Radicle equivalent
DELETE http://{{host}}/repos/octocat/hello-world/code-scanning/analyses/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/codeql/databases — no Radicle equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/codeql/databases
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/codeql/databases/{language} — no Radicle equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/codeql/databases/python
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /repos/{owner}/{repo}/code-scanning/codeql/databases/{language} — no Radicle equivalent
DELETE http://{{host}}/repos/octocat/hello-world/code-scanning/codeql/databases/python
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /repos/{owner}/{repo}/code-scanning/codeql/variant-analyses — no Radicle equivalent
POST http://{{host}}/repos/octocat/hello-world/code-scanning/codeql/variant-analyses
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/codeql/variant-analyses/{id} — no Radicle equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/codeql/variant-analyses/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/codeql/variant-analyses/{id}/repos/{owner}/{repo} — no Radicle equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/codeql/variant-analyses/1/repos/octocat/hello-world
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/default-setup — no Radicle equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/default-setup
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PATCH /repos/{owner}/{repo}/code-scanning/default-setup — no Radicle equivalent
PATCH http://{{host}}/repos/octocat/hello-world/code-scanning/default-setup
Authorization: token testtoken
Content-Type: application/json
{"state": "configured"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /repos/{owner}/{repo}/code-scanning/sarifs — no Radicle equivalent
POST http://{{host}}/repos/octocat/hello-world/code-scanning/sarifs
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/sarifs/{sarif_id} — no Radicle equivalent
GET http://{{host}}/repos/octocat/hello-world/code-scanning/sarifs/abc123
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString
