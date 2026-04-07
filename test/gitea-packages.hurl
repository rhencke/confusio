# Packages API assertions — Gitea backend.

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
jsonpath "$[0].owner.login" isString

# GET /orgs/{org}/packages/{package_type}/{package_name} — get a package
GET http://{{host}}/orgs/testorg/packages/container/web-app

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.name" == "web-app"
jsonpath "$.package_type" == "container"
jsonpath "$.version_count" == 2
jsonpath "$.owner.login" isString

# GET /orgs/{org}/packages/{package_type}/{package_name}/versions — list versions
GET http://{{host}}/orgs/testorg/packages/container/web-app/versions

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].id" isInteger
jsonpath "$[0].name" isString
jsonpath "$[0].metadata.package_type" == "container"

# GET /orgs/{org}/packages/{package_type}/{package_name}/versions/{id} — get version
GET http://{{host}}/orgs/testorg/packages/container/web-app/versions/1

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == 1
jsonpath "$.name" == "1.0.0"
jsonpath "$.metadata.package_type" == "container"

# GET /orgs/{org}/packages/{package_type}/{package_name}/versions/{id} — not found
GET http://{{host}}/orgs/testorg/packages/container/web-app/versions/999

HTTP 404

# DELETE /orgs/{org}/packages/{package_type}/{package_name}/versions/{id} — delete version
DELETE http://{{host}}/orgs/testorg/packages/container/web-app/versions/1

HTTP 204

# DELETE /orgs/{org}/packages/{package_type}/{package_name} — delete all versions
DELETE http://{{host}}/orgs/testorg/packages/container/web-app

HTTP 204

# POST /orgs/{org}/packages/{package_type}/{package_name}/restore — no restore support
POST http://{{host}}/orgs/testorg/packages/container/web-app/restore
Content-Length: 0

HTTP 404

# POST /orgs/{org}/packages/.../versions/{id}/restore — no restore support
POST http://{{host}}/orgs/testorg/packages/container/web-app/versions/1/restore
Content-Length: 0

HTTP 404

# GET /user/packages — list packages for authenticated user
GET http://{{host}}/user/packages
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" isString

# GET /user/packages/{package_type}/{package_name} — get package for authenticated user
GET http://{{host}}/user/packages/npm/my-lib
Authorization: token testtoken

HTTP 200
[Asserts]
jsonpath "$.name" == "my-lib"
jsonpath "$.package_type" == "npm"

# GET /user/packages/{package_type}/{package_name}/versions — list versions
GET http://{{host}}/user/packages/npm/my-lib/versions
Authorization: token testtoken

HTTP 200
[Asserts]
jsonpath "$" isCollection

# GET /user/packages/{package_type}/{package_name}/versions/{id} — get version
GET http://{{host}}/user/packages/npm/my-lib/versions/10
Authorization: token testtoken

HTTP 200
[Asserts]
jsonpath "$.id" == 10
jsonpath "$.name" == "0.1.0"

# DELETE /user/packages/{package_type}/{package_name}/versions/{id} — delete version
DELETE http://{{host}}/user/packages/npm/my-lib/versions/10
Authorization: token testtoken

HTTP 204

# DELETE /user/packages/{package_type}/{package_name} — delete package
DELETE http://{{host}}/user/packages/npm/my-lib
Authorization: token testtoken

HTTP 204

# GET /users/{username}/packages — list packages for a user
GET http://{{host}}/users/octocat/packages

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].name" isString

# GET /users/{username}/packages/{package_type}/{package_name} — get package
GET http://{{host}}/users/octocat/packages/npm/my-lib

HTTP 200
[Asserts]
jsonpath "$.name" == "my-lib"
jsonpath "$.package_type" == "npm"

# GET /users/{username}/packages/{package_type}/{package_name}/versions — list versions
GET http://{{host}}/users/octocat/packages/npm/my-lib/versions

HTTP 200
[Asserts]
jsonpath "$" isCollection

# GET /users/{username}/packages/{package_type}/{package_name}/versions/{id} — get version
GET http://{{host}}/users/octocat/packages/npm/my-lib/versions/10

HTTP 200
[Asserts]
jsonpath "$.id" == 10
jsonpath "$.name" == "0.1.0"

# DELETE /users/{username}/packages/{package_type}/{package_name}/versions/{id} — delete version
DELETE http://{{host}}/users/octocat/packages/npm/my-lib/versions/10

HTTP 204

# DELETE /users/{username}/packages/{package_type}/{package_name} — delete package
DELETE http://{{host}}/users/octocat/packages/npm/my-lib

HTTP 204

# POST /users/{username}/packages/.../restore — no restore support
POST http://{{host}}/users/octocat/packages/npm/my-lib/restore
Content-Length: 0

HTTP 404

# POST /users/{username}/packages/.../versions/{id}/restore — no restore support
POST http://{{host}}/users/octocat/packages/npm/my-lib/versions/10/restore
Content-Length: 0

HTTP 404
