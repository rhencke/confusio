# Git database API — GitHub backend (webhook-only; no upstream API configured).
# All git database endpoints return 501.

GET http://{{host}}/repos/octocat/hello-world/git/blobs/3a0f86fb8db8eea7ccbb9a95f325ddbedfb25e15

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString
