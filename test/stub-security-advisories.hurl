# Security advisories — no native GitHub-compatible advisory API

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
