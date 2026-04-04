# GitLab backend repos API assertions.
# Verifies translation from GitLab API responses to GitHub format.

# GET /repos/{owner}/{repo} — translate GitLab project to GitHub repo format
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
jsonpath "$[0].owner.login" isString

# GET /orgs/{org}/repos
GET http://{{host}}/orgs/testorg/repos

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection

# GET /repos/{owner}/{repo}/topics — extracted from GitLab project object
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

# GET /repos/{owner}/{repo}/contributors — name/commits translated to login/contributions
GET http://{{host}}/repos/octocat/hello-world/contributors

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].login" isString
jsonpath "$[0].contributions" isInteger

# GET /repos/{owner}/{repo}/tags — commit.id translated to commit.sha
GET http://{{host}}/repos/octocat/hello-world/tags

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" isString
jsonpath "$[0].commit.sha" isString

# GET /repos/{owner}/{repo}/teams — GitLab returns 404 (no equivalent)
GET http://{{host}}/repos/octocat/hello-world/teams

HTTP 404

# GET /repos/{owner}/{repo}/branches — commit.id exposed as commit.sha
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

# Branch protection endpoints — GitHub-specific, return 404
GET http://{{host}}/repos/octocat/hello-world/branches/main/protection

HTTP 404

# GET /repos/{owner}/{repo}/commits
GET http://{{host}}/repos/octocat/hello-world/commits

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].sha" isString

# GET /repos/{owner}/{repo}/commits/{ref} — id translated to sha
GET http://{{host}}/repos/octocat/hello-world/commits/abc123

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.sha" isString

# GET /repos/{owner}/{repo}/commits/{ref}/statuses — status translated to state
GET http://{{host}}/repos/octocat/hello-world/commits/abc123/statuses

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].state" isString
jsonpath "$[0].context" isString

# GET /repos/{owner}/{repo}/commits/{ref}/status — combined status
GET http://{{host}}/repos/octocat/hello-world/commits/abc123/status

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.state" isString
jsonpath "$.statuses" isCollection

# GET /repos/{owner}/{repo}/commits/{commit_sha}/comments
GET http://{{host}}/repos/octocat/hello-world/commits/abc123/comments

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection

# GET /repos/{owner}/{repo}/readme — GitLab file object translated to GitHub format
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

# GET /repos/{owner}/{repo}/tarball/{ref} — redirects to GitLab archive
GET http://{{host}}/repos/octocat/hello-world/tarball/main
[Options]
location: false

HTTP 302
[Asserts]
header "Location" contains "archive.tar.gz"

# GET /repos/{owner}/{repo}/zipball/{ref}
GET http://{{host}}/repos/octocat/hello-world/zipball/main
[Options]
location: false

HTTP 302
[Asserts]
header "Location" contains "archive.zip"

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
jsonpath "$[0].login" isString

# GET /repos/{owner}/{repo}/collaborators/{username} — 204 if collaborator
GET http://{{host}}/repos/octocat/hello-world/collaborators/octocat

HTTP 204

# GET /repos/{owner}/{repo}/collaborators/{username}/permission
GET http://{{host}}/repos/octocat/hello-world/collaborators/octocat/permission

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.permission" isString

# GET /repos/{owner}/{repo}/forks — fork list translated to GitHub repo format
GET http://{{host}}/repos/octocat/hello-world/forks

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" isString
jsonpath "$[0].owner.login" isString
jsonpath "$[0].fork" == true

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

# GET /repos/{owner}/{repo}/releases/{release_id} — not implemented in GitLab
GET http://{{host}}/repos/octocat/hello-world/releases/1

HTTP 501

# GET /repos/{owner}/{repo}/keys — deploy keys passthrough
GET http://{{host}}/repos/octocat/hello-world/keys

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].id" isInteger

# GET /repos/{owner}/{repo}/keys/{key_id}
GET http://{{host}}/repos/octocat/hello-world/keys/1

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" isInteger

# GET /repos/{owner}/{repo}/hooks — webhooks passthrough
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

# GET /repos/{owner}/{repo}/hooks/{hook_id}/config — extract url field
GET http://{{host}}/repos/octocat/hello-world/hooks/1/config

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.url" isString

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

# Stats/traffic/deployments — not implemented in GitLab → 501
GET http://{{host}}/repos/octocat/hello-world/stats/code_frequency

HTTP 501

GET http://{{host}}/repos/octocat/hello-world/traffic/views

HTTP 501

GET http://{{host}}/repos/octocat/hello-world/deployments

HTTP 501
