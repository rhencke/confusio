# 12 — Request Batching, Caching, and Cost-Limit Enforcement

## What this document covers

Three orthogonal concerns share one document because they all interact with the request
lifecycle around `graphql_handler`:

1. **Batching** — a single HTTP request carrying multiple GraphQL operations as a JSON
   array.
2. **Request-scoped caching** — deduplicating REST calls within a single query execution
   (the DataLoader pattern).
3. **Cost-limit enforcement** — rejecting queries whose estimated cost exceeds a
   configurable ceiling before execution begins.

Cross-request caching (e.g. response-level HTTP caching or Automatic Persisted Queries)
is explicitly out of scope; see the rationale section below.

## Batching

### What it is

Clients can send an array of operation objects instead of a single object:

```json
[
  { "query": "{ viewer { login } }" },
  { "query": "{ repository(owner:\"octocat\", name:\"hello-world\") { stargazerCount } }" }
]
```

The server executes each operation independently and returns a parallel array of
`{"data": ..., "errors": [...]}` objects:

```json
[
  { "data": { "viewer": { "login": "octocat" } } },
  { "data": { "repository": { "stargazerCount": 1234 } } }
]
```

GitHub's API supports batching.  Relay Modern and some Apollo clients use it to reduce
round-trips.

### Phase 1 decision: reject batches

Batching complicates cost accounting, error isolation, and the response envelope.  Phase 1
rejects batch requests with a clear error:

```lua
-- graphql_handler — top of body decode block
local raw = GetBody() or ""
local req = DecodeJson(raw)
if type(req) == "table" and req[1] ~= nil then
  -- Array body → batch request
  respond_json(400, {
    errors = {{ message = "GraphQL request batching is not supported; send one operation per request." }}
  })
  return
end
```

HTTP 400 (not 200) is used here because the request body is structurally valid JSON but
the format is not accepted, analogous to a content-type mismatch.  This is a
request-level error before any GraphQL processing.

### Phase 2 batch implementation

When batching is implemented in Phase 2, `graphql_handler` detects the array case and
iterates:

```lua
if type(req) == "table" and req[1] ~= nil then
  local results = {}
  for i, item in ipairs(req) do
    results[i] = execute_single(item)  -- returns {data=..., errors=...} table
  end
  set_preamble(200)
  Write(EncodeJson(results))
  return
end
```

`execute_single` is a refactored extraction of the current `graphql_handler` body
(parse → validate → execute → assemble result table).  The outer handler either calls
`execute_single` once (single request) or iterates it (batch).

Each operation in a batch is independent:
- Separate `ctx` per operation (separate `errors`, `path`, `cache`).
- Separate cost estimation per operation.
- A failure in one operation does not affect others.
- Operations execute sequentially (Redbean is single-threaded).

### Batch cost accounting

Each operation in a batch is charged its individual estimated cost.  The cost is reported
per operation in its own `rateLimit` field, not summed across the batch.  Total enforcement
(if any) is per-operation, not per-batch.

## Request-scoped caching (DataLoader pattern)

### The problem

A single query may request the same resource multiple times through different paths.  For
example:

```graphql
{
  repository(owner: "octocat", name: "hello-world") {
    owner { login avatarUrl }
  }
  viewer {
    repositories(first: 5) {
      nodes {
        owner { login avatarUrl }
      }
    }
  }
}
```

If each `owner` field triggers a separate `GET /users/{login}` call, and the same login
appears five times in the viewer's repositories, that is five identical REST round-trips.

### Solution: `ctx.cache`

A request-scoped cache table is added to `ctx`:

```lua
local ctx = {
  doc        = doc,
  variables  = variables,
  errors     = {},
  path       = {},
  rate_cost  = 0,
  cache      = {},   -- ← new: keyed by cache_key string, value = cached result
}
```

A helper in `graphql_executor.lua` wraps the cache lookup:

```lua
-- Call fetch_fn() and cache the result under cache_key for this request.
-- Returns the cached result on subsequent calls with the same key.
-- fetch_fn must return a value (may be nil, which is also cached to avoid re-fetching
-- a known-missing resource).
local CACHE_MISS = {}  -- unique sentinel: distinguishes "not yet fetched" from "fetched nil"

function graphql_cached(ctx, cache_key, fetch_fn)
  local hit = ctx.cache[cache_key]
  if hit == nil then
    -- Not yet fetched
    local result = fetch_fn()
    ctx.cache[cache_key] = (result == nil) and CACHE_MISS or result
    return result
  elseif hit == CACHE_MISS then
    return nil   -- previously fetched, was nil
  else
    return hit
  end
end
```

### Cache key convention

Cache keys are strings of the form `"TypeName:local_id"` — the same as the decoded node
ID local part, prefixed with the type name:

| Scenario | Cache key |
|---|---|
| User by login | `"User:octocat"` |
| Repository by owner/repo | `"Repository:octocat/hello-world"` |
| Issue | `"Issue:octocat/hello-world/42"` |

Connection results (paginated lists) are **not** cached — their content varies by
pagination arguments, making a stable key impractical without including all args.

### Usage in resolvers

```lua
graphql_resolvers["Repository.owner"] = function(parent, args, ctx)
  local login = parent.owner and parent.owner.login
  if not login then return nil end
  return graphql_cached(ctx, "User:" .. login, function()
    local data = graphql_fetch_or_error(fetch_json, base() .. "/users/" .. login, ctx, nil)
    if not data then return nil end
    return graphql_translate_user(translate_user(data))
  end)
end
```

The same pattern applies to `Query.user`, `Query.organization`, `node.User`, etc.
Resolvers that are naturally called once per query (e.g. `Query.repository`) may omit
caching; the benefit is marginal when there is only one call site.

### Cache scope

`ctx.cache` is created fresh per `graphql_handler` invocation (or per `execute_single`
call in a batch).  There is **no cross-request cache**.  Confusio runs in Redbean's
uniprocess model; global mutable state shared between requests is unsafe without locking
(Redbean processes requests sequentially, but the zip is read-only and there is no
persistent heap between requests).  Cross-request caching would also require cache
invalidation, TTL management, and memory bounding — complexity that is not justified for
this use case.

## Cost-limit enforcement

### Purpose

A deeply nested query can trigger an arbitrarily large number of REST calls.  Without a
guard, a client (or a misconfigured tool) can exhaust the upstream backend's rate limit in
a single request:

```graphql
{
  search(query: "language:lua", type: REPOSITORY, first: 100) {
    nodes { ... on Repository {
      issues(first: 100) {
        nodes {
          comments(first: 100) { nodes { body } }
        }
      }
    }}
  }
}
```

Estimated cost: 100 × 100 × 100 = 1 000 000 — one million REST calls for a single query.

### Configurable ceiling

A `GRAPHQL_MAX_COST` constant in `graphql_executor.lua` sets the ceiling.  The default is
`10000` (enough for practical GitHub CLI and Octokit queries; well below the
million-call worst case):

```lua
-- internal/graphql_executor.lua
local GRAPHQL_MAX_COST = 10000
```

This value can be overridden at server start by setting a SCRIPTARG or environment variable
in Phase 2; in Phase 1 the constant suffices.

### Enforcement point

After cost estimation (see [10-auth-ratelimit.md](10-auth-ratelimit.md)), before execution:

```lua
local cost = estimate_query_cost(op, variables)
ctx.rate_cost = cost

if cost > GRAPHQL_MAX_COST then
  respond_graphql(nil, {{
    message    = "query cost " .. tostring(cost) .. " exceeds maximum allowed cost of "
                 .. tostring(GRAPHQL_MAX_COST),
    extensions = {
      code             = "BAD_USER_INPUT",
      estimatedCost    = cost,
      maxAllowedCost   = GRAPHQL_MAX_COST,
    },
  }})
  return
end
```

The response uses `data: null` (request error before execution) and HTTP 200 (all
well-formed GraphQL responses use 200 per the spec).

### Introspection exemption

The introspection query (`__schema`, `__type`) is exempt from cost enforcement.
`estimate_query_cost` returns 0 for meta-fields; after the `math.max(1, cost)` floor it
returns 1, well below any practical ceiling.  No special-casing is needed.

### Cost estimate accuracy

The estimator in `estimate_query_cost` (defined in [10-auth-ratelimit.md](10-auth-ratelimit.md))
computes a product of connection argument values.  It may undercount when:

- A query uses variables for `first`/`last` values that are not statically visible.
- Fragment spreads fan out into large selections (fragments not walked in Phase 1).

An undercounted estimate means the guard lets through a query that is more expensive than
it appears.  This is acceptable: the guard targets runaway queries, not billing-accurate
enforcement.  The upstream backend's own rate limiting is the ultimate backstop.

When variable values are used for `first`/`last`, `coerce_arg_value` resolves them from
`ctx.variables` (see [06-fragments-vars-directives.md](06-fragments-vars-directives.md)):

```lua
local function coerce_arg_value(value_node, variables)
  if value_node.kind == "Variable" then
    return variables[value_node.name.value]
  elseif value_node.kind == "IntValue" then
    return tonumber(value_node.value)
  end
  return nil
end
```

If a variable is absent or not a number, the argument contributes 0 to the cost product
(i.e. the connection is treated as not paginated), which is the conservative direction for
client usability (we don't want to reject valid queries with missing optional variables).

## Out-of-scope: cross-request caching and APQ

### Why no cross-request cache

- **No shared state**: Redbean's zip is read-only; there is no writable shared memory
  between requests in the uniprocess model.
- **Invalidation complexity**: cached REST resources can become stale after mutations.
  Without a cache invalidation protocol, stale reads would silently serve outdated data.
- **Not necessary for correctness**: REST caching (ETags, `Cache-Control`) is the
  appropriate layer for HTTP response caching; the GitHub API emits `Cache-Control` headers
  that HTTP intermediaries (CDN, reverse proxy) can honour.

### Why no APQ (Automatic Persisted Queries)

APQ requires a persistent store keyed by query hash to map `{ extensions: { persistedQuery: { sha256Hash } } }`
to the original query string.  No such store exists in confusio's architecture and none is
planned.  Phase 1 rejects APQ requests:

```lua
-- Detect APQ: body has no "query" field but has extensions.persistedQuery
if type(req.extensions) == "table" and req.extensions.persistedQuery then
  respond_graphql(nil, {{
    message    = "Persisted queries are not supported; send the full query string.",
    extensions = { code = "PERSISTED_QUERY_NOT_SUPPORTED" },
  }})
  return
end
```

The `PERSISTED_QUERY_NOT_SUPPORTED` extension code is the standard Apollo APQ error code;
clients that speak APQ will fall back to sending the full query string when they receive it.

## Summary of request lifecycle with all additions

```
POST /graphql
  1. Decode body
     a. Array body → 400 (Phase 1) or batch execution (Phase 2)
     b. APQ body (no query, has extensions.persistedQuery) → error
     c. Missing/non-string query field → error
  2. Parse document
  3. Select operation (by operationName or sole operation)
  4. Reject mutation/subscription (Phase 1 only)
  5. Validate (field existence, leaf/composite)
  6. Estimate cost → reject if cost > GRAPHQL_MAX_COST
  7. Build ctx (includes ctx.cache = {})
  8. Execute operation (resolvers may use graphql_cached)
  9. respond_graphql(data, ctx.errors)
```

## Testing

Unit tests in `test/graphql-batching-caching.lua`:

- Array body returns HTTP 400 with expected error message (Phase 1 rejection).
- APQ body (no `query`, has `extensions.persistedQuery`) returns error with
  `code = "PERSISTED_QUERY_NOT_SUPPORTED"`.
- `estimate_query_cost` for a 100×100 nested connection → `10000`.
- Cost enforcement: query with cost `> GRAPHQL_MAX_COST` returns `data: null` and
  `extensions.estimatedCost` in the error.
- Cost enforcement: query with cost exactly `GRAPHQL_MAX_COST` is allowed through.
- `graphql_cached` on first call invokes `fetch_fn` and returns result.
- `graphql_cached` on second call with same key returns cached result without calling
  `fetch_fn` again.
- `graphql_cached` caches a `nil` result (via `CACHE_MISS` sentinel): second call returns
  `nil` without invoking `fetch_fn`.
- Request-scoped isolation: two separate `ctx` tables with the same cache key return
  independent results (no cross-request bleed).
- Introspection query (`{ __schema { types { name } } }`) passes cost enforcement
  (estimated cost = 1, well below ceiling).
