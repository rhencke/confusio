# Checks API assertions — RhodeCode backend (stub only; no native CI build system).

# POST /repos/{owner}/{repo}/check-runs — stub
POST http://{{host}}/repos/octocat/hello-world/check-runs
Content-Type: application/json
```json
{
  "name": "ci/test",
  "head_sha": "abc123",
  "status": "in_progress",
  "details_url": "https://ci.example.com/build/1",
  "output": { "title": "Build started", "summary": "Build started" }
}
```

HTTP 201
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" isInteger
jsonpath "$.status" isString

# GET /repos/{owner}/{repo}/check-runs/{check_run_id} — stub
GET http://{{host}}/repos/octocat/hello-world/check-runs/42

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == 42
jsonpath "$.status" isString
jsonpath "$.output" isCollection

# PATCH /repos/{owner}/{repo}/check-runs/{check_run_id} — stub
PATCH http://{{host}}/repos/octocat/hello-world/check-runs/42
Content-Type: application/json
```json
{
  "status": "completed",
  "conclusion": "success"
}
```

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == 42
jsonpath "$.status" isString

# GET /repos/{owner}/{repo}/check-runs/{check_run_id}/annotations — always []
GET http://{{host}}/repos/octocat/hello-world/check-runs/42/annotations

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
body == "[]"

# POST /repos/{owner}/{repo}/check-runs/{check_run_id}/rerequest — stub 201
POST http://{{host}}/repos/octocat/hello-world/check-runs/42/rerequest
Content-Length: 0

HTTP 201

# GET /repos/{owner}/{repo}/commits/{ref}/check-runs — always empty (no CI system)
GET http://{{host}}/repos/octocat/hello-world/commits/abc123/check-runs

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.check_runs" isCollection

# POST /repos/{owner}/{repo}/check-suites — stub
POST http://{{host}}/repos/octocat/hello-world/check-suites
Content-Type: application/json
```json
{"head_sha": "abc123"}
```

HTTP 201
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" isInteger
jsonpath "$.status" isString

# PATCH /repos/{owner}/{repo}/check-suites/preferences — stub
PATCH http://{{host}}/repos/octocat/hello-world/check-suites/preferences
Content-Type: application/json
```json
{"auto_trigger_checks": [{"app_id": 1, "setting": true}]}
```

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"

# GET /repos/{owner}/{repo}/check-suites/{check_suite_id} — stub
GET http://{{host}}/repos/octocat/hello-world/check-suites/1

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" == 1
jsonpath "$.status" isString

# GET /repos/{owner}/{repo}/check-suites/{check_suite_id}/check-runs — empty
GET http://{{host}}/repos/octocat/hello-world/check-suites/1/check-runs

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.check_runs" isCollection

# POST /repos/{owner}/{repo}/check-suites/{check_suite_id}/rerequest — stub 201
POST http://{{host}}/repos/octocat/hello-world/check-suites/1/rerequest
Content-Length: 0

HTTP 201

# GET /repos/{owner}/{repo}/commits/{ref}/check-suites — empty
GET http://{{host}}/repos/octocat/hello-world/commits/abc123/check-suites

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.total_count" == 0
jsonpath "$.check_suites" isCollection
