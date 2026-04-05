# GitBucket backend repos API assertions.
# GitBucket exposes a GitHub-compatible API; confusio passes responses through unchanged.

# GET /repos/{owner}/{repo}
GET http://{{host}}/repos/octocat/hello-world

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" == "hello-world"
jsonpath "$.full_name" == "octocat/hello-world"
jsonpath "$.owner.login" isString
jsonpath "$.default_branch" isString
jsonpath "$.private" isBoolean
jsonpath "$.visibility" isString

# GET /user/repos
GET http://{{host}}/user/repos

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" isString

# GET /orgs/{org}/repos
GET http://{{host}}/orgs/testorg/repos

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection

# GET /repos/{owner}/{repo}/topics
GET http://{{host}}/repos/octocat/hello-world/topics

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.names" isCollection

# GET /repos/{owner}/{repo}/languages
GET http://{{host}}/repos/octocat/hello-world/languages

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /repos/{owner}/{repo}/contributors
GET http://{{host}}/repos/octocat/hello-world/contributors

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection

# GET /repos/{owner}/{repo}/tags
GET http://{{host}}/repos/octocat/hello-world/tags

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" isString
jsonpath "$[0].commit.sha" isString

# GET /repos/{owner}/{repo}/teams — GitBucket implements this (GitHub-compatible)
GET http://{{host}}/repos/octocat/hello-world/teams

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection

# GET /repos/{owner}/{repo}/branches
GET http://{{host}}/repos/octocat/hello-world/branches

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" == "main"
jsonpath "$[0].commit.sha" isString

# GET /repos/{owner}/{repo}/branches/{branch}
GET http://{{host}}/repos/octocat/hello-world/branches/main

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" == "main"
jsonpath "$.commit.sha" isString

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

# GET /repos/{owner}/{repo}/commits/{ref}
GET http://{{host}}/repos/octocat/hello-world/commits/abc123

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.sha" isString

# GET /repos/{owner}/{repo}/commits/{ref}/statuses — uses /statuses/{sha} upstream
GET http://{{host}}/repos/octocat/hello-world/commits/abc123/statuses

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].state" isString

# GET /repos/{owner}/{repo}/commits/{ref}/status — combined status
GET http://{{host}}/repos/octocat/hello-world/commits/abc123/status

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.state" isString

# GET /repos/{owner}/{repo}/commits/{commit_sha}/comments
GET http://{{host}}/repos/octocat/hello-world/commits/abc123/comments

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection

# GET /repos/{owner}/{repo}/readme
GET http://{{host}}/repos/octocat/hello-world/readme

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" isString
jsonpath "$.type" == "file"
jsonpath "$.encoding" == "base64"

# GET /repos/{owner}/{repo}/contents/{path}
GET http://{{host}}/repos/octocat/hello-world/contents/README.md

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" isString
jsonpath "$.type" == "file"

# GET /repos/{owner}/{repo}/tarball/{ref} — redirects to upstream GitBucket tarball
GET http://{{host}}/repos/octocat/hello-world/tarball/main
[Options]
location: false

HTTP 302
[Asserts]
header "Location" contains "/tarball/main"

# GET /repos/{owner}/{repo}/zipball/{ref}
GET http://{{host}}/repos/octocat/hello-world/zipball/main
[Options]
location: false

HTTP 302
[Asserts]
header "Location" contains "/zipball/main"

# GET /repos/{owner}/{repo}/compare/{basehead}
GET http://{{host}}/repos/octocat/hello-world/compare/main...develop

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /repos/{owner}/{repo}/collaborators
GET http://{{host}}/repos/octocat/hello-world/collaborators

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection

# GET /repos/{owner}/{repo}/collaborators/{username} — 204 if collaborator
GET http://{{host}}/repos/octocat/hello-world/collaborators/octocat

HTTP 204

# GET /repos/{owner}/{repo}/collaborators/{username}/permission
GET http://{{host}}/repos/octocat/hello-world/collaborators/octocat/permission

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.permission" isString

# GET /repos/{owner}/{repo}/forks
GET http://{{host}}/repos/octocat/hello-world/forks

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection

# GET /repos/{owner}/{repo}/releases
GET http://{{host}}/repos/octocat/hello-world/releases

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].tag_name" isString

# GET /repos/{owner}/{repo}/releases/latest
GET http://{{host}}/repos/octocat/hello-world/releases/latest

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.tag_name" isString

# GET /repos/{owner}/{repo}/releases/tags/{tag}
GET http://{{host}}/repos/octocat/hello-world/releases/tags/v1.0

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.tag_name" == "v1.0"

# GET /repos/{owner}/{repo}/releases/{release_id} — GitBucket implements this
GET http://{{host}}/repos/octocat/hello-world/releases/1

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == 1

# GET /repos/{owner}/{repo}/releases/{release_id}/assets
GET http://{{host}}/repos/octocat/hello-world/releases/1/assets

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection

# GET /repos/{owner}/{repo}/releases/assets/{asset_id}
GET http://{{host}}/repos/octocat/hello-world/releases/assets/1

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" isInteger

# GET /repos/{owner}/{repo}/keys
GET http://{{host}}/repos/octocat/hello-world/keys

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection

# GET /repos/{owner}/{repo}/keys/{key_id}
GET http://{{host}}/repos/octocat/hello-world/keys/1

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" isInteger

# GET /repos/{owner}/{repo}/hooks
GET http://{{host}}/repos/octocat/hello-world/hooks

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].id" isInteger

# GET /repos/{owner}/{repo}/hooks/{hook_id}
GET http://{{host}}/repos/octocat/hello-world/hooks/1

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" isInteger

# GET /repos/{owner}/{repo}/hooks/{hook_id}/config — extracts config sub-object
GET http://{{host}}/repos/octocat/hello-world/hooks/1/config

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.url" isString

# GET /repos/{owner}/{repo}/comments — repo-level commit comments
GET http://{{host}}/repos/octocat/hello-world/comments

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection

# GET /repos/{owner}/{repo}/comments/{comment_id}
GET http://{{host}}/repos/octocat/hello-world/comments/1

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" isInteger

# GET /users/{username}/repos
GET http://{{host}}/users/octocat/repos

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" isString

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

# Stats/traffic/deployments → 501
GET http://{{host}}/repos/octocat/hello-world/stats/code_frequency

HTTP 404

GET http://{{host}}/repos/octocat/hello-world/traffic/views

HTTP 404

GET http://{{host}}/repos/octocat/hello-world/deployments

HTTP 404

# Repo not found → 404
GET http://{{host}}/repos/nonexist/notareal

HTTP 404

# Branch not found → 404
GET http://{{host}}/repos/octocat/hello-world/branches/nosuchbranch

HTTP 404

# Commit not found → 404
GET http://{{host}}/repos/octocat/hello-world/commits/deadbeefdeadbeef

HTTP 404

# Teams API (/orgs/{org}/teams) -----------------------------------------------

# GET /orgs/{org}/teams
GET http://{{host}}/orgs/testorg/teams

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].id" isInteger
jsonpath "$[0].slug" isString
jsonpath "$[0].permission" isString

# GET /orgs/{org}/teams/{team_slug}
GET http://{{host}}/orgs/testorg/teams/core

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.slug" == "core"
jsonpath "$.permission" isString

# GET /orgs/{org}/teams/{team_slug}/members
GET http://{{host}}/orgs/testorg/teams/core/members

HTTP 200
[Asserts]
jsonpath "$" isCollection
jsonpath "$[0].login" isString

# GET /orgs/{org}/teams/{team_slug}/memberships/{username}
GET http://{{host}}/orgs/testorg/teams/core/memberships/octocat

HTTP 200
[Asserts]
jsonpath "$.role" isString
jsonpath "$.state" == "active"

# GET /orgs/{org}/teams/{team_slug}/repos
GET http://{{host}}/orgs/testorg/teams/core/repos

HTTP 200
[Asserts]
jsonpath "$" isCollection

# GET /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}
GET http://{{host}}/orgs/testorg/teams/core/repos/octocat/hello-world

HTTP 200
[Asserts]
jsonpath "$.name" isString

# GET /orgs/{org}/teams/{team_slug}/invitations
GET http://{{host}}/orgs/testorg/teams/core/invitations

HTTP 200
[Asserts]
body == "[]"

# GET /orgs/{org}/teams/{team_slug}/teams
GET http://{{host}}/orgs/testorg/teams/core/teams

HTTP 200
[Asserts]
body == "[]"

# Legacy team-by-id API (/teams/{team_id}) ----------------------------------------

# GET /user/teams
GET http://{{host}}/user/teams

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].id" isInteger
jsonpath "$[0].name" isString
jsonpath "$[0].slug" isString

# GET /teams/{team_id}
GET http://{{host}}/teams/1

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == 1
jsonpath "$.name" == "core"
jsonpath "$.slug" == "core"
jsonpath "$.permission" isString

# GET /teams/{team_id} — unknown ID → 404
GET http://{{host}}/teams/999

HTTP 404

# GET /teams/{team_id}/members
GET http://{{host}}/teams/1/members

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].login" isString

# GET /teams/{team_id}/members/{username} — deprecated legacy, member → 204
GET http://{{host}}/teams/1/members/octocat

HTTP 204

# GET /teams/{team_id}/memberships/{username} — member → 200
GET http://{{host}}/teams/1/memberships/octocat

HTTP 200
[Asserts]
jsonpath "$.role" isString
jsonpath "$.state" == "active"

# GET /teams/{team_id}/repos
GET http://{{host}}/teams/1/repos

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection

# GET /teams/{team_id}/repos/{owner}/{repo}
GET http://{{host}}/teams/1/repos/testorg/hello-world

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /teams/{team_id}/invitations — GitBucket has none
GET http://{{host}}/teams/1/invitations

HTTP 200
[Asserts]
body == "[]"

# GET /teams/{team_id}/teams — no nested teams in GitBucket
GET http://{{host}}/teams/1/teams

HTTP 200
[Asserts]
body == "[]"

# Security advisories — GitBucket has no native GitHub-compatible advisory API

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
