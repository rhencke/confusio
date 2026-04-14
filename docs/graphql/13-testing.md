# 13 — Testing Strategy: GraphQL Hurl Fixtures and Mocks

## What this document covers

GraphQL support adds new test surface across the entire stack: parser, schema loader,
executor, translators, pagination, error model, node IDs, auth, and the end-to-end
HTTP flow.  This document specifies where each concern is tested, what the new test
files look like, how the mock servers are extended, and how the GraphQL group fits
into the existing `validate-tests` / `BACKEND_RULE` machinery.

## Test layers

| Layer | Tooling | What it covers |
|---|---|---|
| Unit | `redbean.com -i test/unit-graphql-*.lua` | Module APIs in isolation |
| HTTP integration | Hurl via `test/run-backend.sh` | End-to-end: client query → confusio → mock REST → GraphQL response |
| Integration (live) | Hurl via `test-integration.sh` | Live Gitea backend smoke test |

## Unit tests

### File layout

Each design document specifies a dedicated unit test file.  All are run by
`test/unit-init.lua` (or a new sibling driver — see below):

| Test file | Covers |
|---|---|
| `test/graphql-parser.lua` | Lexer, parser, AST shape |
| `test/graphql-schema.lua` | Schema loader, type lookup, introspection data |
| `test/graphql-executor.lua` | Field execution, resolver dispatch, selection walking |
| `test/graphql-translators.lua` | `graphql_translate_*` functions, field mapping |
| `test/graphql-fragments-vars.lua` | Fragment spread, variable coercion, @skip/@include |
| `test/graphql-pagination.lua` | Cursor encoding, connection assembly |
| `test/graphql-node-id.lua` | Node ID encode/decode, `Query.node`, `Query.nodes` |
| `test/graphql-errors.lua` | Error table format, path tracking, null propagation |
| `test/graphql-auth-ratelimit.lua` | `Query.rateLimit`, `Query.viewer`, cost estimation |
| `test/graphql-mutations.lua` | Phase 1 rejection, mutation resolver patterns |
| `test/graphql-batching-caching.lua` | Batch rejection, APQ rejection, `graphql_cached`, cost guard |

### Driver

The existing `test/unit-init.lua` loads `.init.lua` once and runs inline assertions.
The GraphQL unit tests need the GraphQL modules loaded but not the full dispatch
machinery.  A new driver `test/unit-graphql.lua` loads only the GraphQL-relevant
modules in the same pattern as `unit-init.lua`:

```lua
-- test/unit-graphql.lua
-- Runs all test/graphql-*.lua unit test files.
-- Usage: sh redbean.com -i test/unit-graphql.lua

-- Stub Redbean built-ins (same pattern as unit-init.lua)
local _last_status, _last_body = nil, ""
local _req_headers, _req_body = {}, nil

SetStatus = function(c) _last_status = c end
SetHeader  = function() end
Write      = function(s) _last_body = _last_body .. tostring(s) end
GetHeader  = function(k) return _req_headers[k] end
GetMethod  = function() return "POST" end
GetPath    = function() return "/graphql" end
GetBody    = function() return _req_body end
GetParam   = function() return nil end
Route      = function() end
EncodeBase64 = ... -- same stub used elsewhere
DecodeBase64 = ...
EncodeJson   = ...
DecodeJson   = ...

-- Redirect /zip/internal/ to filesystem
local _real_dofile = dofile
function dofile(path)
  if path and path:match("^/zip/backends/") then return end
  if path and path:match("^/zip/internal/") then
    return _real_dofile(path:sub(6))
  end
  return _real_dofile(path)
end

-- Load GraphQL modules in dependency order
dofile("internal/http.lua")
dofile("internal/graphql_parser.lua")
dofile("internal/graphql_schema_data.lua")
dofile("internal/graphql_schema.lua")
dofile("internal/graphql_translators.lua")
dofile("internal/graphql_executor.lua")

-- Run all graphql-*.lua test files
local pass, fail = 0, 0
local function run(file)
  local ok, err = pcall(dofile, file)
  if not ok then
    io.stderr:write("ERROR in " .. file .. ": " .. tostring(err) .. "\n")
    fail = fail + 1
  end
end

for _, f in ipairs({
  "test/graphql-parser.lua",
  "test/graphql-schema.lua",
  "test/graphql-executor.lua",
  "test/graphql-translators.lua",
  "test/graphql-fragments-vars.lua",
  "test/graphql-pagination.lua",
  "test/graphql-node-id.lua",
  "test/graphql-errors.lua",
  "test/graphql-auth-ratelimit.lua",
  "test/graphql-mutations.lua",
  "test/graphql-batching-caching.lua",
}) do run(f) end

-- Pass/fail counters are accumulated by the assert helper used across all files
if fail > 0 then os.exit(1) end
```

The `assert_eq`, `assert_contains`, and `PASS`/`FAIL` helpers are defined once in
`test/unit-graphql.lua` and used across all graphql-*.lua files (not redefined per file).

### Makefile integration

```makefile
test-unit-functions: redbean.com
	./redbean.com -i test/unit-init.lua
	./redbean.com -i test/unit-graphql.lua    # ← new
```

`test-unit-functions` is already a dependency of `test-unit`, so no other Makefile
changes are needed.

## HTTP integration tests (Hurl)

### The `graphql` catalog group

The `POST /graphql` endpoint is registered in a new `"graphql"` section in `endpoint_sections`:

```lua
{
  "graphql",
  {
    { "POST /graphql", "graphql_request", graphql_handler },
  },
},
```

This creates the `stub-graphql.hurl` fallback and the `<backend>-graphql.hurl` pattern,
consistent with every other catalog group.

### `test/stub-graphql.hurl`

The stub file tests behaviour when no backend is configured (or when the backend has no
GraphQL resolvers).  It exercises request-level errors that are backend-agnostic:

```hurl
# POST /graphql — no backend: stub returns an error
POST http://{{host}}/graphql
Content-Type: application/json
```json
{"query": "{ viewer { login } }"}
```

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.data" == null
jsonpath "$.errors" isCollection
jsonpath "$.errors[0].message" isString

# Malformed JSON body → HTTP 400
POST http://{{host}}/graphql
Content-Type: application/json
`not json`

HTTP 400
[Asserts]
jsonpath "$.errors[0].message" isString

# Parse error (syntax error in query)
POST http://{{host}}/graphql
Content-Type: application/json
```json
{"query": "{ viewer { "}
```

HTTP 200
[Asserts]
jsonpath "$.data" == null
jsonpath "$.errors[0].extensions.code" == "PARSE_ERROR"

# Validation error (non-existent field)
POST http://{{host}}/graphql
Content-Type: application/json
```json
{"query": "{ nonExistentField }"}
```

HTTP 200
[Asserts]
jsonpath "$.data" == null
jsonpath "$.errors[0].extensions.code" == "VALIDATION_ERROR"

# Batch request rejected in Phase 1
POST http://{{host}}/graphql
Content-Type: application/json
```json
[{"query": "{ viewer { login } }"}]
```

HTTP 400
[Asserts]
jsonpath "$.errors[0].message" isString

# Introspection: __typename on Query
POST http://{{host}}/graphql
Content-Type: application/json
```json
{"query": "{ __typename }"}
```

HTTP 200
[Asserts]
jsonpath "$.data.__typename" == "Query"
```

### `test/gitea-graphql.hurl`

This file tests the full end-to-end flow with a live mock Gitea backend.  It covers the
most common GitHub client query patterns:

```hurl
# viewer { login }
POST http://{{host}}/graphql
Authorization: Bearer test-token
Content-Type: application/json
```json
{"query": "{ viewer { login } }"}
```

HTTP 200
[Asserts]
jsonpath "$.data.viewer.login" isString
jsonpath "$.errors" not exists

# repository(owner, name) — scalar fields
POST http://{{host}}/graphql
Authorization: Bearer test-token
Content-Type: application/json
```json
{
  "query": "{ repository(owner: \"octocat\", name: \"hello-world\") { nameWithOwner description stargazerCount forkCount } }"
}
```

HTTP 200
[Asserts]
jsonpath "$.data.repository.nameWithOwner" == "octocat/hello-world"
jsonpath "$.data.repository.description" isString
jsonpath "$.data.repository.stargazerCount" isInteger
jsonpath "$.data.repository.forkCount" isInteger
jsonpath "$.errors" not exists

# repository.issues connection (forward pagination)
POST http://{{host}}/graphql
Authorization: Bearer test-token
Content-Type: application/json
```json
{
  "query": "{ repository(owner: \"octocat\", name: \"hello-world\") { issues(first: 2) { totalCount pageInfo { hasNextPage endCursor } nodes { number title state } } } }"
}
```

HTTP 200
[Asserts]
jsonpath "$.data.repository.issues.totalCount" isInteger
jsonpath "$.data.repository.issues.pageInfo.hasNextPage" isBoolean
jsonpath "$.data.repository.issues.nodes" isCollection
jsonpath "$.errors" not exists

# introspection: __schema.queryType.name
POST http://{{host}}/graphql
Authorization: Bearer test-token
Content-Type: application/json
```json
{"query": "{ __schema { queryType { name } } }"}
```

HTTP 200
[Asserts]
jsonpath "$.data.__schema.queryType.name" == "Query"
jsonpath "$.errors" not exists

# node() round-trip: repository node ID
POST http://{{host}}/graphql
Authorization: Bearer test-token
Content-Type: application/json
```json
{
  "query": "{ repository(owner: \"octocat\", name: \"hello-world\") { id } }"
}
```

HTTP 200
[Asserts]
jsonpath "$.data.repository.id" isString

# variables
POST http://{{host}}/graphql
Authorization: Bearer test-token
Content-Type: application/json
```json
{
  "query": "query GetRepo($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { nameWithOwner } }",
  "variables": { "owner": "octocat", "name": "hello-world" }
}
```

HTTP 200
[Asserts]
jsonpath "$.data.repository.nameWithOwner" == "octocat/hello-world"
jsonpath "$.errors" not exists

# rateLimit
POST http://{{host}}/graphql
Authorization: Bearer test-token
Content-Type: application/json
```json
{"query": "{ rateLimit { limit remaining cost resetAt } }"}
```

HTTP 200
[Asserts]
jsonpath "$.data.rateLimit.limit" isInteger
jsonpath "$.data.rateLimit.remaining" isInteger
jsonpath "$.data.rateLimit.cost" isInteger
jsonpath "$.data.rateLimit.resetAt" isString
jsonpath "$.errors" not exists
```

### Backends that share `stub-graphql.hurl`

Backends with no GraphQL resolver registration fall back to the stub, which only tests
request-level errors.  This is correct behaviour: those backends will eventually grow
`graphql_resolvers` entries, at which point a `<backend>-graphql.hurl` file is added.

Initially, only `gitea-graphql.hurl` exists.  All other backends use the stub.

## Mock server requirements

### No changes needed for Phase 1

Confusio's GraphQL layer translates queries into REST calls against the existing mock
endpoints.  The mock servers already handle:

- `GET /user` (viewer)
- `GET /repos/{owner}/{repo}` (repository)
- `GET /repos/{owner}/{repo}/issues` (issues connection)
- `GET /users/{login}` (user lookup)

No new mock routes are required.  When `test/gitea-graphql.hurl` sends a GraphQL query,
confusio calls the mock REST endpoints it already has.

### Mock data consistency

The mock must return data that round-trips cleanly through the GraphQL translator.  The
existing mock routes for `GET /repos/octocat/hello-world` and `GET /user` already return
shapes that the REST translator handles; the GraphQL translator layer builds on top of
those same shapes.

Any new mock routes added for GraphQL test coverage (e.g. for `node()` lookup tests)
follow the existing pattern in `test/mock-gitea.lua`:

```lua
-- In test/mock-gitea.lua OnHttpRequest
if GetMethod() == "GET" and GetPath() == "/user" then
  Write(EncodeJson({ login = "octocat", id = 1, ... }))
  return
end
```

## What `validate-tests` checks

`scripts/validate-tests.py` requires that every catalog group has at least one test file
per backend (either `<backend>-<group>.hurl` or `test/stub-<group>.hurl`).  Adding the
`graphql` group to `endpoint_sections` automatically adds it to the check.

Since `test/stub-graphql.hurl` exists from the start, `validate-tests` passes for every
backend.  The warning-free state is maintained.

## Integration test (live Gitea)

`test/test-integration.sh` runs against live gitea.com.  A new phase is added after the
existing REST phases:

```bash
# Phase N: GraphQL smoke test against live Gitea
run_graphql_phase test/gitea-graphql.hurl -- gitea https://gitea.com
```

Because gitea.com requires authentication for `/user`, the integration test skips
`viewer` and limits itself to unauthenticated queries (`repository`, `rateLimit`,
`__typename`).  The existing `GITEA_TOKEN` environment variable (used for REST
integration tests) is forwarded as the Bearer token if set.

## Test coverage targets

The unit and integration tests together should cover:

| Concern | Unit | Hurl |
|---|---|---|
| Lexer / parser | graphql-parser.lua | stub-graphql.hurl (parse error) |
| Schema validation | graphql-schema.lua | stub-graphql.hurl (validation error) |
| Field execution | graphql-executor.lua | gitea-graphql.hurl (real queries) |
| Translation | graphql-translators.lua | gitea-graphql.hurl (field values) |
| Fragments / variables | graphql-fragments-vars.lua | gitea-graphql.hurl (variables) |
| Pagination | graphql-pagination.lua | gitea-graphql.hurl (issues connection) |
| Node IDs | graphql-node-id.lua | gitea-graphql.hurl (id field) |
| Error envelope | graphql-errors.lua | stub-graphql.hurl (data:null) |
| Auth / rateLimit | graphql-auth-ratelimit.lua | gitea-graphql.hurl (rateLimit) |
| Mutations (Phase 1) | graphql-mutations.lua | (no hurl needed in Phase 1) |
| Batching / caching | graphql-batching-caching.lua | stub-graphql.hurl (batch 400) |
| Introspection | graphql-schema.lua | stub + gitea-graphql.hurl |

## Test naming conventions

| Pattern | Meaning |
|---|---|
| `test/graphql-*.lua` | Unit test file for a specific GraphQL module |
| `test/unit-graphql.lua` | Driver that loads all `graphql-*.lua` files |
| `test/stub-graphql.hurl` | Backend-agnostic HTTP assertions (request errors, introspection) |
| `test/<backend>-graphql.hurl` | Backend-specific GraphQL assertions (real resolver responses) |

These follow the same conventions as all other catalog groups (`stub-issues.hurl`,
`gitea-issues.hurl`, etc.).
