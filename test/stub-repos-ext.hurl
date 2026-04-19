# Repo content & metadata — minimum coverage stub.
# Uses only endpoints that return 404 across all backends (no backend implements them).
# Backends with partial repos-ext support should override this with a backend-specific file.

# POST /repos/{owner}/{repo}/merge-upstream → 404 (no backend implements this)
POST http://{{host}}/repos/octocat/hello-world/merge-upstream
Content-Type: application/json
{"branch": "main"}

HTTP 404

# Webhook delivery and ping endpoints — no backend has native handlers for these yet,
# so the default stubs apply universally.

# GET /repos/{owner}/{repo}/hooks/{hook_id}/deliveries → [] (default stub)
GET http://{{host}}/repos/octocat/hello-world/hooks/1/deliveries

HTTP 200
[Asserts]
body == "[]"

# GET /repos/{owner}/{repo}/hooks/{hook_id}/deliveries/{delivery_id} → 404 (default stub)
GET http://{{host}}/repos/octocat/hello-world/hooks/1/deliveries/1

HTTP 404

# POST /repos/{owner}/{repo}/hooks/{hook_id}/pings → 204 (default stub)
POST http://{{host}}/repos/octocat/hello-world/hooks/1/pings
Content-Type: application/json
{}

HTTP 204
