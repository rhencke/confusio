# No native users API — all user endpoints return 404.

GET http://{{host}}/user

HTTP 404

GET http://{{host}}/users/octocat

HTTP 404

GET http://{{host}}/users

HTTP 404
