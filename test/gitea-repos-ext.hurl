# Extended repos API assertions — branches, commits, contents, releases, keys, hooks, etc.

# GET /repos/{owner}/{repo}/branches
GET http://{{host}}/repos/octocat/hello-world/branches

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" == "main"
jsonpath "$[0].commit.sha" isString

# GET /repos/{owner}/{repo}/branches/{branch} — commit.id translated to commit.sha
GET http://{{host}}/repos/octocat/hello-world/branches/main

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" == "main"
jsonpath "$.commit.sha" isString

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

# GET /repos/{owner}/{repo}/commits/{ref}/statuses
GET http://{{host}}/repos/octocat/hello-world/commits/abc123/statuses

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection

# GET /repos/{owner}/{repo}/commits/{ref}/status (combined)
GET http://{{host}}/repos/octocat/hello-world/commits/abc123/status

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /repos/{owner}/{repo}/readme
GET http://{{host}}/repos/octocat/hello-world/readme

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" isString
jsonpath "$.type" == "file"

# GET /repos/{owner}/{repo}/contents/{path}
GET http://{{host}}/repos/octocat/hello-world/contents/README.md

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" isString
jsonpath "$.type" == "file"

# GET /repos/{owner}/{repo}/tarball/{ref} — redirects to upstream archive URL
GET http://{{host}}/repos/octocat/hello-world/tarball/main
[Options]
location: false

HTTP 302
[Asserts]
header "Location" contains "/archive/main.tar.gz"

# GET /repos/{owner}/{repo}/zipball/{ref} — redirects to upstream archive URL
GET http://{{host}}/repos/octocat/hello-world/zipball/main
[Options]
location: false

HTTP 302
[Asserts]
header "Location" contains "/archive/main.zip"

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

# GET /repos/{owner}/{repo}/forks — fork objects translated to GitHub repo format
GET http://{{host}}/repos/octocat/hello-world/forks

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" isString
jsonpath "$[0].owner.login" isString

# GET /repos/{owner}/{repo}/releases
GET http://{{host}}/repos/octocat/hello-world/releases

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].id" isInteger
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

# GET /repos/{owner}/{repo}/releases/{release_id}
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
jsonpath "$.id" == 1

# GET /repos/{owner}/{repo}/hooks
GET http://{{host}}/repos/octocat/hello-world/hooks

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection

# GET /repos/{owner}/{repo}/hooks/{hook_id}
GET http://{{host}}/repos/octocat/hello-world/hooks/1

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == 1

# GET /repos/{owner}/{repo}/compare/{basehead}
GET http://{{host}}/repos/octocat/hello-world/compare/main...develop

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /repos/{owner}/{repo}/comments
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
jsonpath "$.id" == 1

# GET /users/{username}/repos
GET http://{{host}}/users/octocat/repos

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" isString

# GitHub-specific endpoints → 404 from Gitea backend
GET http://{{host}}/repos/octocat/hello-world/activity

HTTP 404

GET http://{{host}}/repos/octocat/hello-world/branches/main/protection

HTTP 404

GET http://{{host}}/repos/octocat/hello-world/rulesets

HTTP 404

# Stats/traffic → 501 (Gitea has no GitHub-compatible analytics)
GET http://{{host}}/repos/octocat/hello-world/stats/code_frequency

HTTP 501

GET http://{{host}}/repos/octocat/hello-world/traffic/views

HTTP 501

# Deployments → 501 (Gitea has no deployments API)
GET http://{{host}}/repos/octocat/hello-world/deployments

HTTP 501
