# 10 — Authentication Passthrough and Rate Limit Accounting

## What this document covers

GraphQL queries on GitHub require authentication in the same way as REST calls: a Bearer
token in the `Authorization` header.  This document specifies how confusio's existing
authentication passthrough applies to `POST /graphql`, how the `backend_allow_anonymous`
gate works for the GraphQL route, and how confusio synthesises a plausible `rateLimit`
response for clients that request it.

## Authentication passthrough

### How it already works

Confusio's transport layer (`internal/transport.lua`) copies the incoming `Authorization`
header verbatim into every outgoing `fetch_json` call via `make_fetch_opts`.  The GraphQL
handler calls the same `fetch_json` closure that all REST resolvers use; no special
treatment of the header is needed.

```
Client → POST /graphql  Authorization: Bearer ghp_xxx
confusio → GET /repos/{o}/{r}  Authorization: Bearer ghp_xxx   (from make_fetch_opts)
```

The same auth scheme mapping applies:

| Backend | Header sent upstream |
|---------|---------------------|
| GitHub-compatible (Gitea, Forgejo, GitBucket, …) | `Authorization: token <tok>` |
| GitLab | `Authorization: Bearer <tok>` |
| Azure DevOps | `Authorization: Basic base64(:tok)` |
| Bitbucket Cloud | `Authorization: Basic base64(tok)` |

The GraphQL handler does not inspect, validate, or transform the token.  All auth errors
from upstream backends surface as field errors with `extensions.code = "FORBIDDEN"` (HTTP
401/403 from the backend → `graphql_error` with `"FORBIDDEN"` code), per the error model
in [09-errors.md](09-errors.md).

### `backend_allow_anonymous` gate

The existing `OnHttpRequest` gate in `internal/dispatch.lua` runs before route matching.
It applies to every path, including `/graphql`:

```lua
-- internal/dispatch.lua (existing logic, unchanged)
if not backend_allow_anonymous then
  if not GetHeader("Authorization") then
    respond_json(401, { message = "This instance requires authentication." })
    return
  end
end
```

No changes needed.  GraphQL requests to a closed instance without a token receive the
same 401 as REST requests.

### `viewer` resolver

The `viewer` root field resolves the authenticated user.  It maps to `GET /user` (the
REST "get authenticated user" endpoint), identical to the REST handler:

```lua
-- backends/<name>.lua  (in graphql_resolvers section)
graphql_resolvers["Query.viewer"] = function(parent, args, ctx)
  local data = graphql_fetch_or_error(fetch_json, base() .. "/user", ctx, nil)
  if not data then return nil end
  return graphql_translate_user(translate_user(data))
end
```

If the request is unauthenticated and the backend rejects `/user`, `graphql_fetch_or_error`
records a `FORBIDDEN` error and returns `nil`.  The client receives:

```json
{
  "data": { "viewer": null },
  "errors": [{ "message": "upstream error 401 fetching /user",
               "extensions": { "code": "FORBIDDEN" } }]
}
```

## Rate limit model

### GitHub's model

GitHub charges a "node cost" per query against a 5 000-point hourly budget:

- Each connection field's cost = the `first`/`last` argument value (default 1 if omitted).
- Nested connections multiply: `repository { issues(first:10) { nodes { comments(first:5) } } }`
  costs 10 × 5 = 50 nodes for the comments connections alone.
- Scalar leaf fields cost 0.
- The introspection query is free.
- Mutation operations cost 1 point each for the mutation itself, plus node costs in the
  selection set.

GitHub clients routinely include `rateLimit { cost remaining resetAt }` in every query to
track consumption and avoid throttling.

### Confusio's position

Confusio does not bill by node cost — it proxies REST calls.  No per-query billing
infrastructure exists, and the upstream backends (Gitea, GitLab, etc.) have their own rate
limits that are independent of GitHub's scheme.

The approach is to **synthesise a plausible `rateLimit` response** that:

1. Does not break clients that query `rateLimit`.
2. Reports infinite or very-large remaining capacity, since there is no real budget to
   enforce.
3. Reports a non-zero `cost` so that clients that log cost for observability purposes
   receive a meaningful value.

This mirrors the REST default already in `internal/defaults.lua`:

```lua
-- existing REST default (GET /rate_limit)
local limit = 999999
respond_json(200, {
  rate = { limit = limit, used = 0, remaining = limit, reset = os.time() + 3600 }
})
```

### `Query.rateLimit` resolver

Registered in `graphql_executor.lua` (not in backend files — the response is the same
for all backends):

```lua
-- internal/graphql_executor.lua
graphql_resolvers["Query.rateLimit"] = function(parent, args, ctx)
  local limit = 999999
  local reset = os.time() + 3600
  return {
    limit     = limit,
    cost      = ctx.rate_cost or 1,
    remaining = limit,
    nodeCount = 0,
    resetAt   = os.date("!%Y-%m-%dT%H:%M:%SZ", reset),
  }
end
```

The `RateLimit` type fields (from GitHub's schema):

| Field | Type | Returned value |
|-------|------|----------------|
| `limit` | `Int!` | `999999` |
| `cost` | `Int!` | estimated query cost (see below) |
| `remaining` | `Int!` | `999999` |
| `nodeCount` | `Int!` | `0` |
| `resetAt` | `DateTime!` | now + 1 hour (ISO 8601 UTC) |
| `used` | `Int!` | `0` |

### Query cost estimation

`ctx.rate_cost` is populated by `estimate_query_cost(op, variables)` — a lightweight pass
over the operation's field nodes that counts connection argument values.  It runs once per
request, before execution, and stores the result in `ctx`:

```lua
-- internal/graphql_executor.lua
local function estimate_query_cost(op, variables)
  local cost = 0
  local function walk(selection_set, multiplier)
    if not selection_set then return end
    for _, sel in ipairs(selection_set.selections) do
      if sel.kind == "Field" then
        local first = 0
        if sel.arguments then
          for _, arg in ipairs(sel.arguments) do
            if arg.name.value == "first" or arg.name.value == "last" then
              local v = coerce_arg_value(arg.value, variables)
              if type(v) == "number" then first = v end
            end
          end
        end
        if first > 0 then
          cost = cost + multiplier * first
          walk(sel.selectionSet, multiplier * first)
        else
          walk(sel.selectionSet, multiplier)
        end
      elseif sel.kind == "InlineFragment" or sel.kind == "FragmentSpread" then
        walk(sel.selectionSet, multiplier)
      end
    end
  end
  walk(op.selectionSet, 1)
  return math.max(1, cost)
end
```

Cost estimation is best-effort.  It does not account for:

- Fragment spreads that fan out (fragments are not walked in this pass — Phase 2 item).
- `@skip`/`@include` reducing actual execution.
- Mutations (treated as cost 1 each; total cost = 1 + selection-set node cost).

The estimation is only used to populate `rateLimit.cost` for clients that observe it.
It has no enforcement effect.

### `dryRun` argument

GitHub's `rateLimit(dryRun: Boolean)` argument, when `true`, returns the estimated cost of
the query without executing it.  Phase 1 ignores `dryRun` — the resolver always returns
the estimate, whether or not the query has executed.  This is acceptable: the value is an
estimate either way.

### Upstream rate-limit headers

Some backends return `X-RateLimit-Limit` / `X-RateLimit-Remaining` / `X-RateLimit-Reset`
headers on REST responses.  Confusio does not forward these to the client on the GraphQL
endpoint — they would not match the GitHub schema field types, and `graphql_fetch` (as
defined in `graphql_translators.lua`) discards response headers.

If a backend returns HTTP 429, `graphql_fetch_or_error` maps it to a field error with
`extensions.code = "RATE_LIMITED"`.  The query continues executing other fields where
possible; the rate-limited field returns `null`.

## `dryRun`-only queries

Some clients send a query whose only root field is `rateLimit(dryRun: true)` to probe
remaining capacity before a heavy query.  These queries execute the `rateLimit` resolver,
which does not call `fetch_json`.  They complete without any backend round-trips and return
immediately with the synthesised values.

## Token identity and `viewer`

GitHub clients sometimes use `viewer { login }` as a lightweight identity check.  The
`viewer` resolver always makes exactly one REST call (`GET /user`).  If the token is valid,
the user object is returned.  If the token is absent or invalid, a `FORBIDDEN` error is
recorded.

There is no token caching.  Each `viewer` field in a query triggers one `GET /user` call.
In practice, clients include `viewer` at most once per query.

## No per-query auth escalation

GitHub supports fine-grained personal access tokens (FGPATs) with per-repository scopes.
Confusio does not inspect token scopes.  If a resolver call fails with HTTP 403 (scope
insufficient), the field returns `null` and a `FORBIDDEN` error is recorded.  The client
must re-authenticate with broader scopes if needed.

GitHub Apps installation tokens and GHES enterprise tokens are handled identically — they
are forwarded as-is.  Confusio does not manage token refresh or rotation.

## Load order

`graphql_executor.lua` registers `Query.rateLimit` and `Query.viewer` early in its global
initialization block.  Backend files may override `Query.viewer` if their user-endpoint
path differs from the Gitea default (`/user`), but most Gitea-family backends share the
same path and do not need to override it.

```
.init.lua load order (GraphQL additions):
  internal/graphql_parser.lua
  internal/graphql_schema_data.lua    ← generated
  internal/graphql_schema.lua
  internal/graphql_translators.lua
  internal/graphql_executor.lua       ← registers Query.rateLimit, Query.viewer
  backends/<name>.lua                 ← may override Query.viewer
```

## Testing

Unit tests in `test/graphql-auth-ratelimit.lua`:

- `Query.rateLimit` with no prior cost estimation returns `cost = 1`, `remaining = 999999`,
  `resetAt` matching `!%Y-%m-%dT%H:%M:%SZ` format.
- `estimate_query_cost` on `{ repository { issues(first: 10) { nodes { title } } } }`
  returns `10`.
- `estimate_query_cost` on `{ repository { issues(first: 10) { nodes { comments(first: 5) { nodes { body } } } } } }`
  returns `50` (10 × 5).
- `estimate_query_cost` on `{ viewer { login } }` (no connection arguments) returns `1`
  (floor of `math.max(1, 0)`).
- `Query.viewer` with a mock `GET /user` returning a user object returns a translated
  `User` with `__typename = "User"`.
- `Query.viewer` when `fetch_json` returns 401 appends `code = "FORBIDDEN"` to `ctx.errors`
  and returns `nil`.
- `backend_allow_anonymous = false` with no `Authorization` header: `graphql_handler` is
  never called; the gate in `dispatch.lua` returns 401 (existing behaviour, covered by
  existing anon tests).
- A 429 from `graphql_fetch_or_error` appends `code = "RATE_LIMITED"` and returns `nil`.
- `dryRun = true` on `rateLimit` returns the same synthesised values as `dryRun = false`
  (Phase 1 ignores the argument).
