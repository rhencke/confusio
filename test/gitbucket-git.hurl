# Git database API assertions — GitBucket backend.
# GitBucket exposes a GitHub-compatible API; all git database endpoints are
# proxied through unchanged. POST blobs/commits/trees return 501 (not implemented
# in GitBucket's API).

# GET /repos/{owner}/{repo}/git/blobs/{file_sha} — get a blob
GET http://{{host}}/repos/octocat/hello-world/git/blobs/3a0f86fb8db8eea7ccbb9a95f325ddbedfb25e15

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.sha" isString
jsonpath "$.content" isString
jsonpath "$.encoding" == "base64"
jsonpath "$.size" isInteger

# POST /repos/{owner}/{repo}/git/blobs — not supported
POST http://{{host}}/repos/octocat/hello-world/git/blobs
Content-Type: application/json
```json
{"content": "Q29udGVudCBvZiBibG9i", "encoding": "base64"}
```

HTTP 501

# GET /repos/{owner}/{repo}/git/commits/{commit_sha} — get a git commit
GET http://{{host}}/repos/octocat/hello-world/git/commits/abc123

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.sha" isString
jsonpath "$.message" isString

# POST /repos/{owner}/{repo}/git/commits — not supported
POST http://{{host}}/repos/octocat/hello-world/git/commits
Content-Type: application/json
```json
{"message": "my commit message", "tree": "9fb03799", "parents": ["abc123"]}
```

HTTP 501

# GET /repos/{owner}/{repo}/git/matching-refs/{ref} — list matching refs
GET http://{{host}}/repos/octocat/hello-world/git/matching-refs/heads/main

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$" isCollection
jsonpath "$[0].ref" isString
jsonpath "$[0].object.sha" isString

# GET /repos/{owner}/{repo}/git/ref/{ref} — get a single ref
GET http://{{host}}/repos/octocat/hello-world/git/ref/heads/main

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.ref" isString
jsonpath "$.object.sha" isString

# POST /repos/{owner}/{repo}/git/refs — create a ref
POST http://{{host}}/repos/octocat/hello-world/git/refs
Content-Type: application/json
```json
{"ref": "refs/heads/feature", "sha": "abc123def456"}
```

HTTP 201

# PATCH /repos/{owner}/{repo}/git/refs/{ref} — not supported
PATCH http://{{host}}/repos/octocat/hello-world/git/refs/heads/main
Content-Type: application/json
```json
{"sha": "abc123def456", "force": true}
```

HTTP 501

# DELETE /repos/{owner}/{repo}/git/refs/{ref} — delete a ref
DELETE http://{{host}}/repos/octocat/hello-world/git/refs/heads/feature

HTTP 204

# GET /repos/{owner}/{repo}/git/tags/{tag_sha} — get a tag object
GET http://{{host}}/repos/octocat/hello-world/git/tags/940bd336248efae0f9ee5bc7b2d5c985887b16ac

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.sha" isString
jsonpath "$.tag" isString

# POST /repos/{owner}/{repo}/git/tags — create a tag object
POST http://{{host}}/repos/octocat/hello-world/git/tags
Content-Type: application/json
```json
{"tag": "v2.0", "message": "Second release", "object": "abc123def456", "type": "commit"}
```

HTTP 201

# GET /repos/{owner}/{repo}/git/trees/{tree_sha} — get a tree
GET http://{{host}}/repos/octocat/hello-world/git/trees/9fb037999f264ba9a7fc6274d15fa3ae2ab98312

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.sha" isString
jsonpath "$.tree" isCollection

# POST /repos/{owner}/{repo}/git/trees — not supported
POST http://{{host}}/repos/octocat/hello-world/git/trees
Content-Type: application/json
```json
{"tree": [{"path": "README.md", "mode": "100644", "type": "blob", "sha": "3a0f86fb"}]}
```

HTTP 501
