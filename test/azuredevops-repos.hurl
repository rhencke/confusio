# Azure DevOps backend repos API assertions.
# ADO project = GitHub owner; ADO repository = GitHub repo name.

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

# GET /user/repos — lists across all ADO projects
GET http://{{host}}/user/repos

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" isString

# GET /orgs/{org}/repos — maps to ADO project repos
GET http://{{host}}/orgs/testorg/repos

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" == "org-repo"

# GET /repos/{owner}/{repo}/tags
GET http://{{host}}/repos/octocat/hello-world/tags

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" == "v1.0"
jsonpath "$[0].commit.sha" isString

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

# GET /repos/{owner}/{repo}/commits
GET http://{{host}}/repos/octocat/hello-world/commits

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].sha" isString
jsonpath "$[0].commit.message" isString

# GET /repos/{owner}/{repo}/commits/{ref}
GET http://{{host}}/repos/octocat/hello-world/commits/abc123

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.sha" isString
jsonpath "$.commit.message" isString

# GET /repos/{owner}/{repo}/readme — fetches items?path=/README.md
GET http://{{host}}/repos/octocat/hello-world/readme

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.type" == "file"
jsonpath "$.encoding" == "base64"
jsonpath "$.name" isString
jsonpath "$.content" isString

# GET /repos/{owner}/{repo}/contents/{path}
GET http://{{host}}/repos/octocat/hello-world/contents/README.md

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.type" == "file"
jsonpath "$.encoding" == "base64"
jsonpath "$.content" isString

# GET /repos/{owner}/{repo}/tarball/{ref} — redirects to ADO items download
GET http://{{host}}/repos/octocat/hello-world/tarball/main
[Options]
location: false

HTTP 302
[Asserts]
header "Location" contains "/_apis/git/repositories/hello-world/items"

# GET /repos/{owner}/{repo}/zipball/{ref}
GET http://{{host}}/repos/octocat/hello-world/zipball/main
[Options]
location: false

HTTP 302
[Asserts]
header "Location" contains "/_apis/git/repositories/hello-world/items"

# GET /repos/{owner}/{repo}/forks
GET http://{{host}}/repos/octocat/hello-world/forks

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection

# GET /repos/{owner}/{repo}/hooks — resolves repo ID then fetches subscriptions
GET http://{{host}}/repos/octocat/hello-world/hooks

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].id" isInteger
jsonpath "$[0].active" isBoolean
jsonpath "$[0].config.url" isString

# GET /users/{username}/repos — treats username as ADO project
GET http://{{host}}/users/octocat/repos

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" isString

# Repo not found → 404
GET http://{{host}}/repos/nonexist/notareal

HTTP 404

# Teams API (/orgs/{org}/teams) -----------------------------------------------

# GET /orgs/{org}/teams — list ADO project teams
GET http://{{host}}/orgs/testorg/teams

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].id" isInteger
jsonpath "$[0].name" isString
jsonpath "$[0].slug" isString
jsonpath "$[0].permission" isString

# GET /orgs/{org}/teams/{team_slug} — get team by slug
GET http://{{host}}/orgs/testorg/teams/core

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" == "core"
jsonpath "$.slug" == "core"
jsonpath "$.permission" isString

# GET /orgs/{org}/teams/{team_slug} — unknown slug → 404
GET http://{{host}}/orgs/testorg/teams/nosuchteam

HTTP 404

# GET /orgs/{org}/teams/{team_slug}/members
GET http://{{host}}/orgs/testorg/teams/core/members

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].login" isString

# GET /orgs/{org}/teams/{team_slug}/memberships/{username} — member → 200
GET http://{{host}}/orgs/testorg/teams/core/memberships/octocat

HTTP 200
[Asserts]
jsonpath "$.role" isString
jsonpath "$.state" == "active"

# GET /orgs/{org}/teams/{team_slug}/repos — ADO has no team-repo model; returns []
GET http://{{host}}/orgs/testorg/teams/core/repos

HTTP 200
[Asserts]
body == "[]"

# GET /orgs/{org}/teams/{team_slug}/invitations — no invitations in ADO
GET http://{{host}}/orgs/testorg/teams/core/invitations

HTTP 200
[Asserts]
body == "[]"

# GET /orgs/{org}/teams/{team_slug}/teams — no nested teams in ADO
GET http://{{host}}/orgs/testorg/teams/core/teams

HTTP 200
[Asserts]
body == "[]"

# Legacy team-by-id API (/teams/{team_id}) ----------------------------------------
# team_id is the ADO team GUID (e.g. "team-abc123").

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
GET http://{{host}}/teams/team-abc123

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == 0
jsonpath "$.name" == "core"
jsonpath "$.slug" == "core"
jsonpath "$.permission" isString

# GET /teams/{team_id} — unknown GUID → 404
GET http://{{host}}/teams/nonexist

HTTP 404

# GET /teams/{team_id}/members
GET http://{{host}}/teams/team-abc123/members

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].login" isString

# GET /teams/{team_id}/members/{username} — deprecated legacy, member → 204
GET http://{{host}}/teams/team-abc123/members/octocat

HTTP 204

# GET /teams/{team_id}/memberships/{username} — member → 200
GET http://{{host}}/teams/team-abc123/memberships/octocat

HTTP 200
[Asserts]
jsonpath "$.role" isString
jsonpath "$.state" == "active"

# GET /teams/{team_id}/repos — ADO has no team-repo model; returns []
GET http://{{host}}/teams/team-abc123/repos

HTTP 200
[Asserts]
body == "[]"

# GET /teams/{team_id}/repos/{owner}/{repo} — not supported in ADO
GET http://{{host}}/teams/team-abc123/repos/testorg/hello-world

HTTP 404

# GET /teams/{team_id}/invitations — no invitations in ADO
GET http://{{host}}/teams/team-abc123/invitations

HTTP 200
[Asserts]
body == "[]"

# GET /teams/{team_id}/teams — no child teams in ADO
GET http://{{host}}/teams/team-abc123/teams

HTTP 200
[Asserts]
body == "[]"
