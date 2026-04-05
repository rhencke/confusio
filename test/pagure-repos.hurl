# Pagure backend repos API assertions.
# Uses /api/0/; branches have no commit SHAs; tags are names only.

# GET /repos/{owner}/{repo}
GET http://{{host}}/repos/octocat/hello-world

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" == "hello-world"
jsonpath "$.full_name" isString
jsonpath "$.owner.login" isString
jsonpath "$.default_branch" isString
jsonpath "$.private" isBoolean

# GET /repos/{owner}/{repo}/topics — Pagure uses project tags as topics
GET http://{{host}}/repos/octocat/hello-world/topics

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.names" isCollection

# GET /user/repos — needs /-/whoami first
GET http://{{host}}/user/repos

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection

# GET /orgs/{org}/repos — Pagure namespace
GET http://{{host}}/orgs/testorg/repos

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection

# GET /repos/{owner}/{repo}/branches — names only, SHA is empty string
GET http://{{host}}/repos/octocat/hello-world/branches

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" isString

# Branch protection → 404
GET http://{{host}}/repos/octocat/hello-world/branches/main/protection

HTTP 404

# GET /repos/{owner}/{repo}/commits
GET http://{{host}}/repos/octocat/hello-world/commits

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].sha" isString

# GET /repos/{owner}/{repo}/tags — names only, SHA is empty string
GET http://{{host}}/repos/octocat/hello-world/tags

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" isString

# GET /repos/{owner}/{repo}/readme — fetched from raw bytes
GET http://{{host}}/repos/octocat/hello-world/readme

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.type" == "file"
jsonpath "$.encoding" == "base64"
jsonpath "$.name" isString

# GET /repos/{owner}/{repo}/contents/{path}
GET http://{{host}}/repos/octocat/hello-world/contents/README.md

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.type" == "file"
jsonpath "$.encoding" == "base64"

# GET /repos/{owner}/{repo}/forks — from repo object
GET http://{{host}}/repos/octocat/hello-world/forks

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection

# GET /users/{username}/repos
GET http://{{host}}/users/octocat/repos

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection

# GET /repositories
GET http://{{host}}/repositories

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection

# GitHub-specific endpoints → 404
GET http://{{host}}/repos/octocat/hello-world/activity

HTTP 404

GET http://{{host}}/repos/octocat/hello-world/rulesets

HTTP 404

# Not-implemented endpoints → 501
GET http://{{host}}/repos/octocat/hello-world/languages

HTTP 404

GET http://{{host}}/repos/octocat/hello-world/contributors

HTTP 404

GET http://{{host}}/repos/octocat/hello-world/teams

HTTP 404

GET http://{{host}}/repos/octocat/hello-world/releases

HTTP 404

GET http://{{host}}/repos/octocat/hello-world/deployments

HTTP 404

# Repo not found → 404
GET http://{{host}}/repos/nonexist/notareal

HTTP 404


# Teams API — no native support; list endpoints return [], individual → 404

# GET /orgs/{org}/teams → []
GET http://{{host}}/orgs/testorg/teams

HTTP 200
[Asserts]
body == "[]"

# GET /orgs/{org}/teams/{team_slug} → 404 (no teams)
GET http://{{host}}/orgs/testorg/teams/core

HTTP 404

# GET /orgs/{org}/teams/{team_slug}/members → []
GET http://{{host}}/orgs/testorg/teams/core/members

HTTP 200
[Asserts]
body == "[]"

# GET /orgs/{org}/teams/{team_slug}/repos → []
GET http://{{host}}/orgs/testorg/teams/core/repos

HTTP 200
[Asserts]
body == "[]"

# GET /orgs/{org}/teams/{team_slug}/invitations → []
GET http://{{host}}/orgs/testorg/teams/core/invitations

HTTP 200
[Asserts]
body == "[]"

# GET /orgs/{org}/teams/{team_slug}/teams → []
GET http://{{host}}/orgs/testorg/teams/core/teams

HTTP 200
[Asserts]
body == "[]"

# Legacy team-by-id API (/teams/{team_id}) — no native support; list endpoints return [], individual → 404

# GET /user/teams → []
GET http://{{host}}/user/teams

HTTP 200
[Asserts]
body == "[]"

# GET /teams/{team_id} → 404 (no teams)
GET http://{{host}}/teams/1

HTTP 404

# GET /teams/{team_id}/members → []
GET http://{{host}}/teams/1/members

HTTP 200
[Asserts]
body == "[]"

# GET /teams/{team_id}/repos → []
GET http://{{host}}/teams/1/repos

HTTP 200
[Asserts]
body == "[]"

# GET /teams/{team_id}/invitations → []
GET http://{{host}}/teams/1/invitations

HTTP 200
[Asserts]
body == "[]"

# GET /teams/{team_id}/teams → []
GET http://{{host}}/teams/1/teams

HTTP 200
[Asserts]
body == "[]"

# GET /teams/{team_id}/members/{username} → 404
GET http://{{host}}/teams/1/members/octocat

HTTP 404

# GET /teams/{team_id}/memberships/{username} → 404
GET http://{{host}}/teams/1/memberships/octocat

HTTP 404

# GET /teams/{team_id}/repos/{owner}/{repo} → 404
GET http://{{host}}/teams/1/repos/testorg/hello-world

HTTP 404


# Security advisories — Pagure has no native GitHub-compatible advisory API

# GET /advisories → []
GET http://{{host}}/advisories

HTTP 200
[Asserts]
body == "[]"

# GET /advisories/{ghsa_id} → 404
GET http://{{host}}/advisories/GHSA-1234-5678-9012

HTTP 404

# GET /orgs/{org}/security-advisories → []
GET http://{{host}}/orgs/testorg/security-advisories

HTTP 200
[Asserts]
body == "[]"

# GET /repos/{owner}/{repo}/security-advisories → []
GET http://{{host}}/repos/octocat/hello-world/security-advisories

HTTP 200
[Asserts]
body == "[]"

# GET /repos/{owner}/{repo}/security-advisories/{ghsa_id} → 404
GET http://{{host}}/repos/octocat/hello-world/security-advisories/GHSA-1234-5678-9012

HTTP 404
