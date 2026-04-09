# Licenses API assertions — Bitbucket Data Center backend.
# BBS has no license template API — GET /licenses and GET /licenses/{license} return 501.

# GET /licenses
GET http://{{host}}/licenses

HTTP 501

# GET /licenses/{license}
GET http://{{host}}/licenses/mit

HTTP 501

# GET /repos/{owner}/{repo}/license — fetched via BBS raw endpoint
GET http://{{host}}/repos/octocat/hello-world/license

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" isString
jsonpath "$.content" isString
jsonpath "$.encoding" == "base64"
