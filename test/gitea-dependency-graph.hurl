# Dependency Graph API assertions — Gitea backend.
# Gitea has no native dependency graph API; all three endpoints return 501.

# GET /repos/{owner}/{repo}/dependency-graph/compare/{basehead} — no Gitea equivalent
GET http://{{host}}/repos/octocat/hello-world/dependency-graph/compare/main...feature
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# GET /repos/{owner}/{repo}/dependency-graph/sbom — no Gitea equivalent
GET http://{{host}}/repos/octocat/hello-world/dependency-graph/sbom
Authorization: token testtoken

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString

# POST /repos/{owner}/{repo}/dependency-graph/snapshots — no Gitea equivalent
POST http://{{host}}/repos/octocat/hello-world/dependency-graph/snapshots
Authorization: token testtoken
Content-Type: application/json
{"version": 0, "sha": "abc123", "ref": "refs/heads/main", "job": {"id": "1", "correlator": "test"}, "detector": {"name": "test", "version": "1.0.0", "url": "https://example.com"}, "manifests": {}}

HTTP 501
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.message" isString
