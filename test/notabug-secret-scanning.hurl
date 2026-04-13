# Secret Scanning API — Notabug backend.
# Notabug has no native secret scanning API.
# List endpoints return empty collections (200); per-resource and mutation endpoints return 501.

# GET /orgs/{org}/secret-scanning/alerts
GET http://{{host}}/orgs/testorg/secret-scanning/alerts
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /orgs/{org}/secret-scanning/pattern-configurations
GET http://{{host}}/orgs/testorg/secret-scanning/pattern-configurations
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PATCH /orgs/{org}/secret-scanning/pattern-configurations
PATCH http://{{host}}/orgs/testorg/secret-scanning/pattern-configurations
Authorization: token testtoken
Content-Type: application/json
{"pattern_config_version": "0ujsswThIGTUYm2K8FjOOfXtY1K"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/secret-scanning/alerts
GET http://{{host}}/repos/octocat/hello-world/secret-scanning/alerts
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /repos/{owner}/{repo}/secret-scanning/alerts/{alert_number}
GET http://{{host}}/repos/octocat/hello-world/secret-scanning/alerts/1
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PATCH /repos/{owner}/{repo}/secret-scanning/alerts/{alert_number}
PATCH http://{{host}}/repos/octocat/hello-world/secret-scanning/alerts/1
Authorization: token testtoken
Content-Type: application/json
{"state": "resolved", "resolution": "false_positive"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/secret-scanning/alerts/{alert_number}/locations
GET http://{{host}}/repos/octocat/hello-world/secret-scanning/alerts/1/locations
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# POST /repos/{owner}/{repo}/secret-scanning/push-protection-bypasses
POST http://{{host}}/repos/octocat/hello-world/secret-scanning/push-protection-bypasses
Authorization: token testtoken
Content-Type: application/json
{"reason": "will_fix_later", "placeholder_id": "2k4dM4tseyC5lPIsjl5emX9sPNk"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/secret-scanning/scan-history
GET http://{{host}}/repos/octocat/hello-world/secret-scanning/scan-history
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString
