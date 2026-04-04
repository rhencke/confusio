# Repos API assertions — Gitea backend.

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
jsonpath "$" count == 1
jsonpath "$[0].name" == "hello-world"
jsonpath "$[0].owner.login" isString

# GET /orgs/{org}/repos
GET http://{{host}}/orgs/testorg/repos

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" count == 1
jsonpath "$[0].name" == "org-repo"

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
jsonpath "$[0].name" == "v1.0"
jsonpath "$[0].commit.sha" isString

# GET /repos/{owner}/{repo}/teams — not implemented (returns 404)
GET http://{{host}}/repos/octocat/hello-world/teams

HTTP 404

# Teams API (/orgs/{org}/teams) -----------------------------------------------

# GET /orgs/{org}/teams — list teams
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
jsonpath "$.id" == 1
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

# GET /orgs/{org}/teams/{team_slug}/repos
GET http://{{host}}/orgs/testorg/teams/core/repos

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection

# GET /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo} — repo in team
GET http://{{host}}/orgs/testorg/teams/core/repos/testorg/hello-world

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /orgs/{org}/teams/{team_slug}/invitations — Gitea has none
GET http://{{host}}/orgs/testorg/teams/core/invitations

HTTP 200
[Asserts]
body == "[]"

# GET /orgs/{org}/teams/{team_slug}/teams — no nested teams in Gitea
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

# GET /teams/{team_id}/repos/{owner}/{repo} — repo in team
GET http://{{host}}/teams/1/repos/testorg/hello-world

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /teams/{team_id}/invitations — Gitea has none
GET http://{{host}}/teams/1/invitations

HTTP 200
[Asserts]
body == "[]"

# GET /teams/{team_id}/teams — no nested teams in Gitea
GET http://{{host}}/teams/1/teams

HTTP 200
[Asserts]
body == "[]"

# Method not allowed: PUT /repos/{owner}/{repo} is not a registered route
# Use PATCH (wrong method for /repos/…) to verify 405 without body requirement
DELETE http://{{host}}/user/repos

HTTP 405

# Repo not found → 404
GET http://{{host}}/repos/nonexist/notareal

HTTP 404
