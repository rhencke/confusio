# Repo content & metadata — minimum coverage stub.
# Uses only endpoints that return 404 across all backends (no backend implements them).
# Backends with partial repos-ext support should override this with a backend-specific file.

# POST /repos/{owner}/{repo}/merge-upstream → 404 (no backend implements this)
POST http://{{host}}/repos/octocat/hello-world/merge-upstream
Content-Type: application/json
{"branch": "main"}

HTTP 404
