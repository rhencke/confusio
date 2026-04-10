# Activity API — minimal stubs for backends without native Activity support.
# List endpoints return empty arrays (200); mark-as-read endpoints return 205 Reset Content;
# star/watch/unsubscribe mutation endpoints return 204 No Content;
# per-resource GET endpoints (thread, subscription check) return 404 Not Found;
# feeds and subscription set endpoints return 501 Not Implemented.

# GET /events
GET http://{{host}}/events
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# GET /feeds
GET http://{{host}}/feeds
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /networks/{owner}/{repo}/events
GET http://{{host}}/networks/octocat/hello-world/events
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# GET /notifications
GET http://{{host}}/notifications
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# PUT /notifications
PUT http://{{host}}/notifications
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 205

# GET /notifications/threads/{thread_id}
GET http://{{host}}/notifications/threads/1
Authorization: token testtoken

HTTP 404
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PATCH /notifications/threads/{thread_id}
PATCH http://{{host}}/notifications/threads/1
Authorization: token testtoken

HTTP 205

# DELETE /notifications/threads/{thread_id}
DELETE http://{{host}}/notifications/threads/1
Authorization: token testtoken

HTTP 204

# GET /notifications/threads/{thread_id}/subscription
GET http://{{host}}/notifications/threads/1/subscription
Authorization: token testtoken

HTTP 404
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PUT /notifications/threads/{thread_id}/subscription
PUT http://{{host}}/notifications/threads/1/subscription
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /notifications/threads/{thread_id}/subscription
DELETE http://{{host}}/notifications/threads/1/subscription
Authorization: token testtoken

HTTP 204

# GET /orgs/{org}/events
GET http://{{host}}/orgs/testorg/events
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# GET /repos/{owner}/{repo}/events
GET http://{{host}}/repos/octocat/hello-world/events
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# GET /repos/{owner}/{repo}/notifications
GET http://{{host}}/repos/octocat/hello-world/notifications
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# PUT /repos/{owner}/{repo}/notifications
PUT http://{{host}}/repos/octocat/hello-world/notifications
Authorization: token testtoken
Content-Type: application/json
{}

HTTP 205

# GET /repos/{owner}/{repo}/stargazers
GET http://{{host}}/repos/octocat/hello-world/stargazers
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# GET /repos/{owner}/{repo}/subscribers
GET http://{{host}}/repos/octocat/hello-world/subscribers
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# GET /repos/{owner}/{repo}/subscription
GET http://{{host}}/repos/octocat/hello-world/subscription
Authorization: token testtoken

HTTP 404
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PUT /repos/{owner}/{repo}/subscription
PUT http://{{host}}/repos/octocat/hello-world/subscription
Authorization: token testtoken
Content-Type: application/json
{"subscribed": true, "ignored": false}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# DELETE /repos/{owner}/{repo}/subscription
DELETE http://{{host}}/repos/octocat/hello-world/subscription
Authorization: token testtoken

HTTP 204

# GET /user/starred
GET http://{{host}}/user/starred
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# GET /user/starred/{owner}/{repo}
GET http://{{host}}/user/starred/octocat/hello-world
Authorization: token testtoken

HTTP 404
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# PUT /user/starred/{owner}/{repo}
PUT http://{{host}}/user/starred/octocat/hello-world
Authorization: token testtoken

HTTP 204

# DELETE /user/starred/{owner}/{repo}
DELETE http://{{host}}/user/starred/octocat/hello-world
Authorization: token testtoken

HTTP 204

# GET /user/subscriptions
GET http://{{host}}/user/subscriptions
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# GET /users/{username}/events
GET http://{{host}}/users/octocat/events
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# GET /users/{username}/events/orgs/{org}
GET http://{{host}}/users/octocat/events/orgs/testorg
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# GET /users/{username}/events/public
GET http://{{host}}/users/octocat/events/public
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# GET /users/{username}/received_events
GET http://{{host}}/users/octocat/received_events
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# GET /users/{username}/received_events/public
GET http://{{host}}/users/octocat/received_events/public
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# GET /users/{username}/starred
GET http://{{host}}/users/octocat/starred
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# GET /users/{username}/subscriptions
GET http://{{host}}/users/octocat/subscriptions
Authorization: token testtoken

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"
