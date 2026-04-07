# Packages API assertions — GitLab backend (org-level via group packages API).

# GET /orgs/{org}/packages — list packages
GET http://{{host}}/orgs/testorg/packages

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].id" isInteger
jsonpath "$[0].name" isString
jsonpath "$[0].package_type" isString
jsonpath "$[0].version_count" isInteger

# GET /orgs/{org}/packages/{package_type}/{package_name} — get a package
GET http://{{host}}/orgs/testorg/packages/npm/web-app

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" == "web-app"
jsonpath "$.package_type" == "npm"
jsonpath "$.version_count" == 2

# GET /orgs/{org}/packages/{package_type}/{package_name}/versions — list versions
GET http://{{host}}/orgs/testorg/packages/npm/web-app/versions

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].id" isInteger
jsonpath "$[0].name" isString
jsonpath "$[0].metadata.package_type" == "npm"

# GET /orgs/{org}/packages/{package_type}/{package_name}/versions/{id} — get version
GET http://{{host}}/orgs/testorg/packages/npm/web-app/versions/1

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == 1
jsonpath "$.name" == "1.0.0"

# GET /orgs/{org}/packages/{package_type}/{package_name}/versions/{id} — not found
GET http://{{host}}/orgs/testorg/packages/npm/web-app/versions/999

HTTP 404

# DELETE /orgs/{org}/packages/{package_type}/{package_name}/versions/{id} — delete version
DELETE http://{{host}}/orgs/testorg/packages/npm/web-app/versions/1

HTTP 204

# DELETE /orgs/{org}/packages/{package_type}/{package_name} — delete all versions
DELETE http://{{host}}/orgs/testorg/packages/npm/web-app

HTTP 204

# POST /orgs/{org}/packages/{package_type}/{package_name}/restore — no restore support
POST http://{{host}}/orgs/testorg/packages/npm/web-app/restore
Content-Length: 0

HTTP 404

# GET /user/packages — not implemented for GitLab (falls back to empty list)
GET http://{{host}}/user/packages

HTTP 200
[Asserts]
jsonpath "$" count == 0

# GET /users/{username}/packages — not implemented for GitLab (falls back to empty list)
GET http://{{host}}/users/octocat/packages

HTTP 200
[Asserts]
jsonpath "$" count == 0
