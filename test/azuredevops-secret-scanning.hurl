# Secret Scanning API — Azure DevOps Advanced Security (GHAzDO) backend.
# Repo-level list/get/update proxy to ADO Advanced Security with alertType=secret.
# Org-level list returns empty; locations, push-protection bypasses, and scan history
# have no ADO equivalent and return 501 or empty list.

# GET /orgs/{org}/secret-scanning/alerts — no ADO org-level endpoint; returns empty list
GET http://{{host}}/orgs/testorg/secret-scanning/alerts
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /orgs/{org}/secret-scanning/pattern-configurations — no ADO equivalent
GET http://{{host}}/orgs/testorg/secret-scanning/pattern-configurations
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PATCH /orgs/{org}/secret-scanning/pattern-configurations — no ADO equivalent
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
jsonpath "$[0].number" == 3
jsonpath "$[0].state" == "open"
jsonpath "$[0].secret_type" isString
jsonpath "$[0].secret_type_display_name" isString

# GET /repos/{owner}/{repo}/secret-scanning/alerts/{alert_number}
GET http://{{host}}/repos/octocat/hello-world/secret-scanning/alerts/3
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.number" == 3
jsonpath "$.state" == "open"
jsonpath "$.secret_type" == "github-personal-access-token"
jsonpath "$.secret_type_display_name" == "GitHub Personal Access Token"

# PATCH /repos/{owner}/{repo}/secret-scanning/alerts/{alert_number}
PATCH http://{{host}}/repos/octocat/hello-world/secret-scanning/alerts/3
Authorization: token testtoken
Content-Type: application/json
{"state": "dismissed", "resolution": "revoked", "resolution_comment": "Token has been rotated"}

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.number" == 3
jsonpath "$.state" == "dismissed"
jsonpath "$.resolution" == "revoked"

# GET /repos/{owner}/{repo}/secret-scanning/alerts/{alert_number}/locations — no ADO equivalent; returns empty list
GET http://{{host}}/repos/octocat/hello-world/secret-scanning/alerts/3/locations
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# POST /repos/{owner}/{repo}/secret-scanning/push-protection-bypasses — no ADO equivalent
POST http://{{host}}/repos/octocat/hello-world/secret-scanning/push-protection-bypasses
Authorization: token testtoken
Content-Type: application/json
{"reason": "will_fix_later", "placeholder_id": "2k4dM4tseyC5lPIsjl5emX9sPNk"}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/secret-scanning/scan-history — no ADO equivalent
GET http://{{host}}/repos/octocat/hello-world/secret-scanning/scan-history
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString
