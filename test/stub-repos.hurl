GET http://{{host}}/

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "{}"

# No native repos API — all repo endpoints return 404.

GET http://{{host}}/repos/octocat/hello-world

HTTP 404

GET http://{{host}}/user/repos

HTTP 404

GET http://{{host}}/orgs/testorg/repos

HTTP 404
