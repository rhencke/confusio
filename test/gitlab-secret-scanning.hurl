# Secret Scanning API — GitLab backend.
# GitLab Secret Detection stores findings as vulnerabilities with report_type=secret_detection.
# List/get/update endpoints proxy to the GitLab vulnerabilities API.
# Alert locations, push-protection bypasses, pattern configurations, and scan history
# have no GitLab equivalent and fall back to defaults.

# GET /orgs/{org}/secret-scanning/alerts — via GET /groups/:org/vulnerabilities?report_type=secret_detection
GET http://{{host}}/orgs/testorg/secret-scanning/alerts
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$[0].number" == 2
jsonpath "$[0].state" == "open"
jsonpath "$[0].secret_type" isString
jsonpath "$[0].secret_type_display_name" isString

# GET /orgs/{org}/secret-scanning/pattern-configurations — no GitLab equivalent
GET http://{{host}}/orgs/testorg/secret-scanning/pattern-configurations
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PATCH /orgs/{org}/secret-scanning/pattern-configurations — no GitLab equivalent
PATCH http://{{host}}/orgs/testorg/secret-scanning/pattern-configurations
Authorization: token testtoken
Content-Type: application/json
{"pattern_config_version": "0ujsswThIGTUYm2K8FjOOfXtY1K"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/secret-scanning/alerts — via GET /projects/:id/vulnerabilities?report_type=secret_detection
GET http://{{host}}/repos/octocat/hello-world/secret-scanning/alerts
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$[0].number" == 2
jsonpath "$[0].state" == "open"
jsonpath "$[0].secret_type" == "gitlab_personal_access_token"
jsonpath "$[0].secret_type_display_name" == "GitLab Personal Access Token"

# GET /repos/{owner}/{repo}/secret-scanning/alerts/{alert_number} — via GET /projects/:id/vulnerabilities/:n
GET http://{{host}}/repos/octocat/hello-world/secret-scanning/alerts/2
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.number" == 2
jsonpath "$.state" == "open"
jsonpath "$.secret_type" == "gitlab_personal_access_token"
jsonpath "$.secret_type_display_name" == "GitLab Personal Access Token"

# PATCH /repos/{owner}/{repo}/secret-scanning/alerts/{alert_number} — via POST /vulnerabilities/:n/dismiss
PATCH http://{{host}}/repos/octocat/hello-world/secret-scanning/alerts/2
Authorization: token testtoken
Content-Type: application/json
{"state": "dismissed", "resolution": "false_positive"}

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.number" == 2
jsonpath "$.state" == "dismissed"
jsonpath "$.resolution" == "false_positive"

# GET /repos/{owner}/{repo}/secret-scanning/alerts/{alert_number}/locations — no GitLab equivalent; returns empty list
GET http://{{host}}/repos/octocat/hello-world/secret-scanning/alerts/2/locations
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# POST /repos/{owner}/{repo}/secret-scanning/push-protection-bypasses — no GitLab equivalent
POST http://{{host}}/repos/octocat/hello-world/secret-scanning/push-protection-bypasses
Authorization: token testtoken
Content-Type: application/json
{"reason": "will_fix_later", "placeholder_id": "2k4dM4tseyC5lPIsjl5emX9sPNk"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/secret-scanning/scan-history — no GitLab equivalent
GET http://{{host}}/repos/octocat/hello-world/secret-scanning/scan-history
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString
