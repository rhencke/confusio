GET http://{{host}}/

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "{}"

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
