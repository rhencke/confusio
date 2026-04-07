# Code Scanning API — 501 Not Implemented for all backends.
# No backend has a native code scanning API equivalent.

# GET /orgs/{org}/code-scanning/alerts
GET http://{{host}}/orgs/testorg/code-scanning/alerts
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/alerts
GET http://{{host}}/repos/octocat/hello-world/code-scanning/alerts
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}
GET http://{{host}}/repos/octocat/hello-world/code-scanning/alerts/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PATCH /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}
PATCH http://{{host}}/repos/octocat/hello-world/code-scanning/alerts/1
Authorization: token testtoken
Content-Type: application/json
{"state": "dismissed"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/autofix
GET http://{{host}}/repos/octocat/hello-world/code-scanning/alerts/1/autofix
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/autofix
POST http://{{host}}/repos/octocat/hello-world/code-scanning/alerts/1/autofix
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/autofix/commits
POST http://{{host}}/repos/octocat/hello-world/code-scanning/alerts/1/autofix/commits
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/instances
GET http://{{host}}/repos/octocat/hello-world/code-scanning/alerts/1/instances
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/analyses
GET http://{{host}}/repos/octocat/hello-world/code-scanning/analyses
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/analyses/{analysis_id}
GET http://{{host}}/repos/octocat/hello-world/code-scanning/analyses/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /repos/{owner}/{repo}/code-scanning/analyses/{analysis_id}
DELETE http://{{host}}/repos/octocat/hello-world/code-scanning/analyses/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/codeql/databases
GET http://{{host}}/repos/octocat/hello-world/code-scanning/codeql/databases
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/codeql/databases/{language}
GET http://{{host}}/repos/octocat/hello-world/code-scanning/codeql/databases/python
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /repos/{owner}/{repo}/code-scanning/codeql/databases/{language}
DELETE http://{{host}}/repos/octocat/hello-world/code-scanning/codeql/databases/python
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /repos/{owner}/{repo}/code-scanning/codeql/variant-analyses
POST http://{{host}}/repos/octocat/hello-world/code-scanning/codeql/variant-analyses
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/codeql/variant-analyses/{codeql_variant_analysis_id}
GET http://{{host}}/repos/octocat/hello-world/code-scanning/codeql/variant-analyses/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/codeql/variant-analyses/{codeql_variant_analysis_id}/repos/{repo_owner}/{repo_name}
GET http://{{host}}/repos/octocat/hello-world/code-scanning/codeql/variant-analyses/1/repos/octocat/hello-world
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/default-setup
GET http://{{host}}/repos/octocat/hello-world/code-scanning/default-setup
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PATCH /repos/{owner}/{repo}/code-scanning/default-setup
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

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/code-scanning/sarifs/{sarif_id}
GET http://{{host}}/repos/octocat/hello-world/code-scanning/sarifs/abc123
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString
