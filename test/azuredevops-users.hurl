# Azure DevOps backend users API.
# azuredevops.lua does not implement user endpoints; all return 404.

# GET /user — not implemented
GET http://{{host}}/user
HTTP 404

# GET /users/octocat — not implemented
GET http://{{host}}/users/octocat
HTTP 404
