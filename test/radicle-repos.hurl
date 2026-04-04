# Radicle backend repos API assertions.
# Owner param is ignored; repo = RID. Uses /api/v1/.

# GET /repos/{owner}/{rid}
GET http://{{host}}/repos/octocat/testrid

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" isString
jsonpath "$.owner.login" isString
jsonpath "$.default_branch" isString
jsonpath "$.private" isBoolean

# GET /user/repos
GET http://{{host}}/user/repos

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection

# GET /repos/{owner}/{rid}/tags
GET http://{{host}}/repos/octocat/testrid/tags

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" isString
jsonpath "$[0].commit.sha" isString

# GET /repos/{owner}/{rid}/branches
GET http://{{host}}/repos/octocat/testrid/branches

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" == "main"
jsonpath "$[0].commit.sha" isString

# GET /repos/{owner}/{rid}/branches/{branch}
GET http://{{host}}/repos/octocat/testrid/branches/main

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" == "main"
jsonpath "$.commit.sha" isString

# Branch protection → 404
GET http://{{host}}/repos/octocat/testrid/branches/main/protection

HTTP 404

# GET /repos/{owner}/{rid}/commits
GET http://{{host}}/repos/octocat/testrid/commits

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].sha" isString

# GET /repos/{owner}/{rid}/commits/{ref}
GET http://{{host}}/repos/octocat/testrid/commits/abc123

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.sha" isString

# GET /repos/{owner}/{rid}/readme
GET http://{{host}}/repos/octocat/testrid/readme

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.type" == "file"
jsonpath "$.encoding" == "base64"
jsonpath "$.name" isString

# GET /repos/{owner}/{rid}/contents/{path}
GET http://{{host}}/repos/octocat/testrid/contents/README.md

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.type" == "file"
jsonpath "$.encoding" == "base64"

# GET /users/{username}/repos — by delegate
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

# DELETE /repos — Radicle does not support deletion → 405
DELETE http://{{host}}/repos/octocat/testrid

HTTP 405

# GitHub-specific endpoints → 404
GET http://{{host}}/repos/octocat/testrid/activity

HTTP 404

GET http://{{host}}/repos/octocat/testrid/rulesets

HTTP 404

# Not-implemented endpoints → 501
GET http://{{host}}/repos/octocat/testrid/topics

HTTP 404

GET http://{{host}}/repos/octocat/testrid/languages

HTTP 404

GET http://{{host}}/repos/octocat/testrid/contributors

HTTP 404

GET http://{{host}}/repos/octocat/testrid/teams

HTTP 404

GET http://{{host}}/repos/octocat/testrid/forks

HTTP 404

GET http://{{host}}/repos/octocat/testrid/releases

HTTP 404

GET http://{{host}}/repos/octocat/testrid/deployments

HTTP 404

# Repo (RID) not found → 404
GET http://{{host}}/repos/octocat/notareal

HTTP 404

# Commit not found → 404
GET http://{{host}}/repos/octocat/testrid/commits/deadbeefdeadbeef

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
