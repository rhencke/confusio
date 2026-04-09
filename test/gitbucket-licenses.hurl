# Licenses API assertions — GitBucket backend.

# GET /licenses
GET http://{{host}}/licenses

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].key" isString
jsonpath "$[0].name" isString

# GET /licenses/{license}
GET http://{{host}}/licenses/mit

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.key" == "mit"
jsonpath "$.name" == "MIT License"
jsonpath "$.body" isString

# GET /repos/{owner}/{repo}/license
GET http://{{host}}/repos/octocat/hello-world/license

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" isString
jsonpath "$.content" isString
jsonpath "$.license.key" == "mit"
