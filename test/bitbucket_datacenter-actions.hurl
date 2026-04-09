# Actions API — bitbucket_datacenter backend.
# Bitbucket Datacenter has Pipelines but no GitHub Actions API equivalent.
# All Actions endpoints use the default handlers: empty lists or 501.
# Enterprise cache — 501
GET http://{{host}}/enterprises/myenterprise/actions/cache/retention-limit
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# Org runner groups — empty
GET http://{{host}}/orgs/testorg/actions/runner-groups
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.runner_groups" isEmpty

# Org runners — empty
GET http://{{host}}/orgs/testorg/actions/runners
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.runners" isEmpty

# Org secrets — empty
GET http://{{host}}/orgs/testorg/actions/secrets
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.secrets" isEmpty

# Org variables — empty
GET http://{{host}}/orgs/testorg/actions/variables
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.variables" isEmpty

# Repo artifacts — empty
GET http://{{host}}/repos/octocat/hello-world/actions/artifacts
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.artifacts" isEmpty

# Repo runners — empty
GET http://{{host}}/repos/octocat/hello-world/actions/runners
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.runners" isEmpty

# Repo workflow runs — empty
GET http://{{host}}/repos/octocat/hello-world/actions/runs
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.workflow_runs" isEmpty

# Repo secrets — empty
GET http://{{host}}/repos/octocat/hello-world/actions/secrets
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.secrets" isEmpty

# Repo variables — empty
GET http://{{host}}/repos/octocat/hello-world/actions/variables
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.variables" isEmpty

# Repo workflows — empty
GET http://{{host}}/repos/octocat/hello-world/actions/workflows
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.workflows" isEmpty

# Repo permissions — not supported
GET http://{{host}}/repos/octocat/hello-world/actions/permissions
Authorization: token testtoken

HTTP 501
[Asserts]
jsonpath "$.message" isString
