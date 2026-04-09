# Actions API — Gitea backend.
# Gitea supports secrets, variables, and runners (repo + org level).
# Secrets: list, get, and delete only — GitHub encrypts secrets with NaCl before
# sending; Gitea stores plaintext, so create/update returns 501.
# Variables: full CRUD (Gitea uses PUT for updates; confusio maps PATCH → PUT).
# Runners: list only.
# Workflow runs, artifacts, caches, jobs, OIDC, and permissions use default handlers.

# --- Enterprise-level (no Gitea equivalent → 501) ---

# GET /enterprises/{enterprise}/actions/cache/retention-limit
GET http://{{host}}/enterprises/myenterprise/actions/cache/retention-limit
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /enterprises/{enterprise}/actions/oidc/customization/properties/repo — empty list default
GET http://{{host}}/enterprises/myenterprise/actions/oidc/customization/properties/repo
Authorization: token testtoken

HTTP 200
[Asserts]
body == "[]"

# --- Organization-level cache (no Gitea equivalent → 501) ---

GET http://{{host}}/orgs/testorg/actions/cache/usage
Authorization: token testtoken

HTTP 501
[Asserts]
jsonpath "$.message" isString

# --- Organization runner groups (no Gitea equivalent → empty) ---

GET http://{{host}}/orgs/testorg/actions/runner-groups
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.runner_groups" isEmpty

# --- Organization runners (proxied from Gitea) ---

GET http://{{host}}/orgs/testorg/actions/runners
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 1
jsonpath "$.runners[0].id" == 2
jsonpath "$.runners[0].name" == "org-runner"
jsonpath "$.runners[0].os" == "linux"
jsonpath "$.runners[0].status" == "idle"
jsonpath "$.runners[0].busy" == false

# Runner downloads — empty list default
GET http://{{host}}/orgs/testorg/actions/runners/downloads
Authorization: token testtoken

HTTP 200
[Asserts]
body == "[]"

# --- Organization secrets (proxied from Gitea) ---

GET http://{{host}}/orgs/testorg/actions/secrets
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 1
jsonpath "$.secrets[0].name" == "ORG_SECRET"

# Get individual org secret
GET http://{{host}}/orgs/testorg/actions/secrets/ORG_SECRET
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" == "ORG_SECRET"

# Create/update org secret — not supported (NaCl encryption incompatibility)
PUT http://{{host}}/orgs/testorg/actions/secrets/NEW_SECRET
Authorization: token testtoken
Content-Type: application/json
{"encrypted_value": "base64value", "key_id": "key123"}

HTTP 501
[Asserts]
jsonpath "$.message" isString

# Delete org secret
DELETE http://{{host}}/orgs/testorg/actions/secrets/ORG_SECRET
Authorization: token testtoken

HTTP 204

# Org secrets public key — not supported
GET http://{{host}}/orgs/testorg/actions/secrets/public-key
Authorization: token testtoken

HTTP 501
[Asserts]
jsonpath "$.message" isString

# --- Organization variables (proxied from Gitea — full CRUD) ---

GET http://{{host}}/orgs/testorg/actions/variables
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 1
jsonpath "$.variables[0].name" == "ORG_VAR"
jsonpath "$.variables[0].value" == "org_value"

# Get individual org variable
GET http://{{host}}/orgs/testorg/actions/variables/ORG_VAR
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" == "ORG_VAR"
jsonpath "$.value" == "org_value"

# Create org variable
POST http://{{host}}/orgs/testorg/actions/variables
Authorization: token testtoken
Content-Type: application/json
{"name": "NEW_ORG_VAR", "value": "new_org_value"}

HTTP 201
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" == "NEW_ORG_VAR"
jsonpath "$.value" == "new_org_value"

# Update org variable (PATCH maps to Gitea PUT)
PATCH http://{{host}}/orgs/testorg/actions/variables/ORG_VAR
Authorization: token testtoken
Content-Type: application/json
{"value": "updated_value"}

HTTP 204

# Delete org variable
DELETE http://{{host}}/orgs/testorg/actions/variables/ORG_VAR
Authorization: token testtoken

HTTP 204

# --- Organization permissions (no Gitea equivalent → 501) ---

GET http://{{host}}/orgs/testorg/actions/permissions
Authorization: token testtoken

HTTP 501
[Asserts]
jsonpath "$.message" isString

# --- Repository artifacts (no Gitea equivalent → empty) ---

GET http://{{host}}/repos/octocat/hello-world/actions/artifacts
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.artifacts" isEmpty

# --- Repository cache (no Gitea equivalent → empty / 501) ---

GET http://{{host}}/repos/octocat/hello-world/actions/caches
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.actions_caches" isEmpty

GET http://{{host}}/repos/octocat/hello-world/actions/cache/usage
Authorization: token testtoken

HTTP 501
[Asserts]
jsonpath "$.message" isString

# --- Repository jobs (no Gitea equivalent → 501) ---

GET http://{{host}}/repos/octocat/hello-world/actions/jobs/1
Authorization: token testtoken

HTTP 501
[Asserts]
jsonpath "$.message" isString

# --- Repository runners (proxied from Gitea) ---

GET http://{{host}}/repos/octocat/hello-world/actions/runners
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 1
jsonpath "$.runners[0].id" == 1
jsonpath "$.runners[0].name" == "my-runner"
jsonpath "$.runners[0].os" == "linux"
jsonpath "$.runners[0].status" == "idle"
jsonpath "$.runners[0].busy" == false

# Runner downloads — empty list default
GET http://{{host}}/repos/octocat/hello-world/actions/runners/downloads
Authorization: token testtoken

HTTP 200
[Asserts]
body == "[]"

# --- Repository workflow runs (no Gitea equivalent → empty) ---

GET http://{{host}}/repos/octocat/hello-world/actions/runs
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.workflow_runs" isEmpty

GET http://{{host}}/repos/octocat/hello-world/actions/runs/1/jobs
Authorization: token testtoken

HTTP 200
[Asserts]
jsonpath "$.total_count" == 0
jsonpath "$.jobs" isEmpty

GET http://{{host}}/repos/octocat/hello-world/actions/runs/1/artifacts
Authorization: token testtoken

HTTP 200
[Asserts]
jsonpath "$.total_count" == 0
jsonpath "$.artifacts" isEmpty

# --- Repository secrets (proxied from Gitea) ---

GET http://{{host}}/repos/octocat/hello-world/actions/secrets
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 1
jsonpath "$.secrets[0].name" == "MY_SECRET"

# Get individual repo secret
GET http://{{host}}/repos/octocat/hello-world/actions/secrets/MY_SECRET
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" == "MY_SECRET"

# Create/update repo secret — not supported (NaCl encryption incompatibility)
PUT http://{{host}}/repos/octocat/hello-world/actions/secrets/NEW_SECRET
Authorization: token testtoken
Content-Type: application/json
{"encrypted_value": "base64value", "key_id": "key123"}

HTTP 501
[Asserts]
jsonpath "$.message" isString

# Delete repo secret
DELETE http://{{host}}/repos/octocat/hello-world/actions/secrets/MY_SECRET
Authorization: token testtoken

HTTP 204

# Repo secrets public key — not supported
GET http://{{host}}/repos/octocat/hello-world/actions/secrets/public-key
Authorization: token testtoken

HTTP 501
[Asserts]
jsonpath "$.message" isString

# Inherited org secrets view — empty (default)
GET http://{{host}}/repos/octocat/hello-world/actions/organization-secrets
Authorization: token testtoken

HTTP 200
[Asserts]
jsonpath "$.total_count" == 0
jsonpath "$.secrets" isEmpty

# --- Repository variables (proxied from Gitea — full CRUD) ---

GET http://{{host}}/repos/octocat/hello-world/actions/variables
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 1
jsonpath "$.variables[0].name" == "MY_VAR"
jsonpath "$.variables[0].value" == "my_value"

# Get individual repo variable
GET http://{{host}}/repos/octocat/hello-world/actions/variables/MY_VAR
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" == "MY_VAR"
jsonpath "$.value" == "my_value"

# Create repo variable
POST http://{{host}}/repos/octocat/hello-world/actions/variables
Authorization: token testtoken
Content-Type: application/json
{"name": "NEW_VAR", "value": "new_value"}

HTTP 201
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" == "NEW_VAR"
jsonpath "$.value" == "new_value"

# Update repo variable (PATCH maps to Gitea PUT)
PATCH http://{{host}}/repos/octocat/hello-world/actions/variables/MY_VAR
Authorization: token testtoken
Content-Type: application/json
{"value": "updated_value"}

HTTP 204

# Delete repo variable
DELETE http://{{host}}/repos/octocat/hello-world/actions/variables/MY_VAR
Authorization: token testtoken

HTTP 204

# Inherited org variables view — empty (default)
GET http://{{host}}/repos/octocat/hello-world/actions/organization-variables
Authorization: token testtoken

HTTP 200
[Asserts]
jsonpath "$.total_count" == 0
jsonpath "$.variables" isEmpty

# --- Repository workflows (no Gitea equivalent → empty) ---

GET http://{{host}}/repos/octocat/hello-world/actions/workflows
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.workflows" isEmpty

GET http://{{host}}/repos/octocat/hello-world/actions/workflows/1/runs
Authorization: token testtoken

HTTP 200
[Asserts]
jsonpath "$.total_count" == 0
jsonpath "$.workflow_runs" isEmpty

# --- Repository permissions (no Gitea equivalent → 501) ---

GET http://{{host}}/repos/octocat/hello-world/actions/permissions
Authorization: token testtoken

HTTP 501
[Asserts]
jsonpath "$.message" isString

# --- Repository OIDC (no Gitea equivalent → 501) ---

GET http://{{host}}/repos/octocat/hello-world/actions/oidc/customization/sub
Authorization: token testtoken

HTTP 501
[Asserts]
jsonpath "$.message" isString
