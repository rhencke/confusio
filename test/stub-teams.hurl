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
