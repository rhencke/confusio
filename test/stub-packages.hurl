# Packages API — no native packages registry; all list endpoints return [],
# individual-resource endpoints return 404.

# GET /orgs/{org}/packages → []
GET http://{{host}}/orgs/testorg/packages

HTTP 200
[Asserts]
body == "[]"

# GET /orgs/{org}/packages/{package_type}/{package_name} → 404
GET http://{{host}}/orgs/testorg/packages/container/web-app

HTTP 404

# GET /orgs/{org}/packages/{package_type}/{package_name}/versions → []
GET http://{{host}}/orgs/testorg/packages/container/web-app/versions

HTTP 200
[Asserts]
body == "[]"

# GET /orgs/{org}/packages/{package_type}/{package_name}/versions/{id} → 404
GET http://{{host}}/orgs/testorg/packages/container/web-app/versions/1

HTTP 404

# DELETE /orgs/{org}/packages/{package_type}/{package_name} → 404
DELETE http://{{host}}/orgs/testorg/packages/container/web-app

HTTP 404

# DELETE /orgs/{org}/packages/{package_type}/{package_name}/versions/{id} → 404
DELETE http://{{host}}/orgs/testorg/packages/container/web-app/versions/1

HTTP 404

# POST /orgs/{org}/packages/{package_type}/{package_name}/restore → 404
POST http://{{host}}/orgs/testorg/packages/container/web-app/restore
Content-Length: 0

HTTP 404

# POST /orgs/{org}/packages/{package_type}/{package_name}/versions/{id}/restore → 404
POST http://{{host}}/orgs/testorg/packages/container/web-app/versions/1/restore
Content-Length: 0

HTTP 404

# GET /user/packages → []
GET http://{{host}}/user/packages

HTTP 200
[Asserts]
body == "[]"

# GET /user/packages/{package_type}/{package_name} → 404
GET http://{{host}}/user/packages/npm/my-lib

HTTP 404

# GET /user/packages/{package_type}/{package_name}/versions → []
GET http://{{host}}/user/packages/npm/my-lib/versions

HTTP 200
[Asserts]
body == "[]"

# GET /user/packages/{package_type}/{package_name}/versions/{id} → 404
GET http://{{host}}/user/packages/npm/my-lib/versions/1

HTTP 404

# DELETE /user/packages/{package_type}/{package_name} → 404
DELETE http://{{host}}/user/packages/npm/my-lib

HTTP 404

# DELETE /user/packages/{package_type}/{package_name}/versions/{id} → 404
DELETE http://{{host}}/user/packages/npm/my-lib/versions/1

HTTP 404

# POST /user/packages/{package_type}/{package_name}/restore → 404
POST http://{{host}}/user/packages/npm/my-lib/restore
Content-Length: 0

HTTP 404

# POST /user/packages/{package_type}/{package_name}/versions/{id}/restore → 404
POST http://{{host}}/user/packages/npm/my-lib/versions/1/restore
Content-Length: 0

HTTP 404

# GET /users/{username}/packages → []
GET http://{{host}}/users/octocat/packages

HTTP 200
[Asserts]
body == "[]"

# GET /users/{username}/packages/{package_type}/{package_name} → 404
GET http://{{host}}/users/octocat/packages/npm/my-lib

HTTP 404

# GET /users/{username}/packages/{package_type}/{package_name}/versions → []
GET http://{{host}}/users/octocat/packages/npm/my-lib/versions

HTTP 200
[Asserts]
body == "[]"

# GET /users/{username}/packages/{package_type}/{package_name}/versions/{id} → 404
GET http://{{host}}/users/octocat/packages/npm/my-lib/versions/1

HTTP 404

# DELETE /users/{username}/packages/{package_type}/{package_name} → 404
DELETE http://{{host}}/users/octocat/packages/npm/my-lib

HTTP 404

# DELETE /users/{username}/packages/{package_type}/{package_name}/versions/{id} → 404
DELETE http://{{host}}/users/octocat/packages/npm/my-lib/versions/1

HTTP 404

# POST /users/{username}/packages/{package_type}/{package_name}/restore → 404
POST http://{{host}}/users/octocat/packages/npm/my-lib/restore
Content-Length: 0

HTTP 404

# POST /users/{username}/packages/{package_type}/{package_name}/versions/{id}/restore → 404
POST http://{{host}}/users/octocat/packages/npm/my-lib/versions/1/restore
Content-Length: 0

HTTP 404
