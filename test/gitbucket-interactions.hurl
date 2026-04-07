# Interactions API assertions — GitBucket backend (stub defaults, no native support).

# GET /orgs/{org}/interaction-limits — no restrictions in effect
GET http://{{host}}/orgs/testorg/interaction-limits
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "{}"

# PUT /orgs/{org}/interaction-limits — echoes limit back (not enforced)
PUT http://{{host}}/orgs/testorg/interaction-limits
Authorization: token testtoken
Content-Type: application/json
{"limit": "collaborators_only"}

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.limit" == "collaborators_only"

# DELETE /orgs/{org}/interaction-limits — no restrictions to remove
DELETE http://{{host}}/orgs/testorg/interaction-limits
Authorization: token testtoken

HTTP 204

# GET /repos/{owner}/{repo}/interaction-limits — no restrictions in effect
GET http://{{host}}/repos/octocat/hello-world/interaction-limits
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "{}"

# PUT /repos/{owner}/{repo}/interaction-limits — echoes limit back (not enforced)
PUT http://{{host}}/repos/octocat/hello-world/interaction-limits
Authorization: token testtoken
Content-Type: application/json
{"limit": "collaborators_only"}

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.limit" == "collaborators_only"

# DELETE /repos/{owner}/{repo}/interaction-limits — no restrictions to remove
DELETE http://{{host}}/repos/octocat/hello-world/interaction-limits
Authorization: token testtoken

HTTP 204

# GET /user/interaction-limits — no restrictions in effect
GET http://{{host}}/user/interaction-limits
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "{}"

# PUT /user/interaction-limits — echoes limit back (not enforced)
PUT http://{{host}}/user/interaction-limits
Authorization: token testtoken
Content-Type: application/json
{"limit": "collaborators_only"}

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.limit" == "collaborators_only"

# DELETE /user/interaction-limits — no restrictions to remove
DELETE http://{{host}}/user/interaction-limits
Authorization: token testtoken

HTTP 204
