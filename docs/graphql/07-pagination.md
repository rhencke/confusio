# 07 — Relay Cursor Pagination Mapping to REST Page Params

## What this document covers

GitHub's GraphQL API uses the [Relay Cursor Connection
specification](https://relay.dev/graphql/connections.htm) for all paginated lists.  REST
backends use page-number parameters (`page`, `per_page`/`limit`).  This document specifies
how confusio bridges the two: cursor encoding, URL construction for resolvers, connection
response assembly, and the Phase 1 restriction to forward pagination only.

## Relay Connection recap

Every paginated field in GitHub's GraphQL schema returns a `*Connection` type:

```graphql
type IssueConnection {
  totalCount: Int!
  pageInfo:   PageInfo!
  nodes:      [Issue]
  edges:      [IssueEdge]
}
type IssueEdge {
  cursor: String!
  node:   Issue
}
type PageInfo {
  hasNextPage:     Boolean!
  hasPreviousPage: Boolean!
  startCursor:     String
  endCursor:       String
}
```

Clients paginate forward by passing `first: N, after: <endCursor>` and repeating until
`pageInfo.hasNextPage` is false.  Backward pagination uses `last: N, before: <startCursor>`.

`nodes` is a GitHub extension (not part of the base Relay spec): a shortcut to
`edges { node }` that most clients prefer.  Both must be present in the response because
clients may request either.

## Cursor encoding

Confusio uses **page-number cursors**: a cursor encodes a 1-based page index.

```
cursor = EncodeBase64("page:" .. tostring(page_number))
```

Examples:

| Page | Cursor (base64 of `page:N`) |
|------|-----------------------------|
| 1 | `"cGFnZTox"` |
| 2 | `"cGFnZToy"` |
| 3 | `"cGFnZToz"` |

Decoding:

```lua
-- internal/graphql_translators.lua

function graphql_page_to_cursor(page)
  return EncodeBase64("page:" .. tostring(page))
end

function graphql_cursor_to_page(cursor)
  if not cursor then return nil end
  local decoded = DecodeBase64(cursor)
  if not decoded then return nil end
  return tonumber(decoded:match("^page:(%d+)$"))
end
```

`graphql_cursor_to_page` returns `nil` for any cursor that does not match the `page:N`
format, including GitHub's real opaque cursors.  Resolvers treat a nil result the same as
a missing cursor (start from page 1).

### Why page-number cursors instead of offset cursors

Offset cursors (`offset:N`) would allow item-level precision but REST backends use page
numbers.  Converting an offset to a page number requires knowing `per_page`, and if the
client changes `first` between requests, the offset cursor becomes misaligned.
Page-number cursors are stable: a cursor obtained with `first: 10` is still valid when
reused with `first: 20` (it just shifts which page is fetched).

## Forward pagination (`first`/`after`)

### Argument semantics

| Arguments | Meaning | REST translation |
|-----------|---------|-----------------|
| `first: N` only | First N items from the start | `per_page=N, page=1` |
| `first: N, after: cursor` | Next N items after cursor | `per_page=N, page=cursor_page+1` |
| *(no args)* | Default page size (30 items) | `per_page=30, page=1` |

### URL construction helper

```lua
-- internal/graphql_translators.lua
--
-- Append GraphQL forward-pagination args to a REST URL.
-- param_names: { per_page = "upstream_name", page = "upstream_name" }
--              (same format as append_page_params mapping)
-- Returns the URL with per_page and page appended.
function graphql_cursor_url(url_base, args, param_names)
  local per_page = args.first or 30
  local page = 1
  if args.after then
    local p = graphql_cursor_to_page(args.after)
    if p then page = p + 1 end
  end

  local sep = url_base:find("?") and "&" or "?"
  local parts = {}
  if param_names.per_page then
    parts[#parts + 1] = param_names.per_page .. "=" .. tostring(per_page)
  end
  if param_names.page and page > 1 then
    parts[#parts + 1] = param_names.page .. "=" .. tostring(page)
  end
  if #parts == 0 then return url_base end
  return url_base .. sep .. table.concat(parts, "&")
end
```

Usage in a sub-resolver (Gitea family, `per_page = "limit"`, `page = "page"`):

```lua
graphql_resolvers["Repository.issues"] = function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  local url = graphql_cursor_url(
    base() .. "/repos/" .. owner .. "/" .. name .. "/issues",
    args,
    { per_page = "limit", page = "page" })
  -- add state filter etc.
  local data, headers, err = graphql_fetch_with_headers(fetch_json, url)
  ...
end
```

## Backward pagination (`last`/`before`)

### Phase 1 limitation

Backward pagination requires either:
- Backend support for reverse ordering, or
- Knowing the total page count to seek from the end.

Most REST backends support neither reliably.  Phase 1 returns an error for any request
that uses `last` or `before`:

```lua
if args.last or args.before then
  append_graphql_error(ctx,
    "backward pagination (last/before) is not supported in this version")
  return {
    __typename  = typename .. "Connection",
    total_count = 0,
    page_info   = {
      __typename         = "PageInfo",
      has_next_page      = false,
      has_previous_page  = false,
      start_cursor       = nil,
      end_cursor         = nil,
    },
    nodes = {},
    edges = {},
  }
end
```

The error is added to `ctx.errors` and the field returns an empty connection (not `null`),
so the rest of the query continues executing.  Clients that use only `first`/`after` are
unaffected.

Backward pagination implementation is tracked as a Phase 2 item in
[16-roadmap.md](16-roadmap.md).

## `totalCount`

`totalCount` on a Connection is `Int!` in GitHub's schema (non-null).  Confusio must
always emit a number.

### Sources (in priority order)

1. **Response body `total_count` field**: used by REST search endpoints (`/search/issues`,
   `/search/repositories`, etc.) and some provider-specific list endpoints.  Resolvers
   extract it explicitly from the decoded body.

2. **`X-Total` response header**: Gitea emits `X-Total: N` on paginated list responses.
   The `graphql_fetch_with_headers` helper (see below) returns headers so resolvers can
   read this value.

3. **`X-Total-Count` response header**: some other backends emit this.  Same approach.

4. **Fallback — count of returned items**: when no total is available, `totalCount` is set
   to `#nodes` for this page.  This is a lower bound (and misleads clients that use
   `totalCount` to decide whether to paginate).  It is the unavoidable cost of supporting
   backends without a total-count API.  Document it in
   [14-backend-feasibility.md](14-backend-feasibility.md) per backend.

### `graphql_fetch_with_headers`

A variant of `graphql_fetch` that also returns headers, for resolvers that need to inspect
`X-Total` or `X-Total-Count`:

```lua
-- Returns decoded_table, headers_table, nil         on success
-- Returns nil,           nil,           error_string on failure
function graphql_fetch_with_headers(fetch_json, path, method, body)
  local ok, status, headers, raw = fetch_json(path, method, body)
  if not ok then
    return nil, nil, "network error fetching " .. path
  end
  if status == 404 then
    return nil, nil, "not found: " .. path
  end
  if status < 200 or status >= 300 then
    return nil, nil, "upstream error " .. tostring(status)
  end
  local decoded = DecodeJson(raw)
  if decoded == nil then
    return nil, nil, "invalid JSON from upstream"
  end
  return decoded, headers or {}, nil
end
```

Resolver usage:

```lua
local data, hdrs, err = graphql_fetch_with_headers(fetch_json, url)
if not data then
  append_graphql_error(ctx, err)
  return nil
end
local total = (hdrs["X-Total"] and tonumber(hdrs["X-Total"]))
           or (hdrs["X-Total-Count"] and tonumber(hdrs["X-Total-Count"]))
           or #data
```

## `hasNextPage` and `hasPreviousPage`

### `hasNextPage`

Computed from `total` and `page` when total is known:

```lua
has_next_page = (page * per_page) < total
```

When `total` is unknown (fallback case), use the page-full heuristic:

```lua
has_next_page = (#nodes == per_page)
-- true if we got exactly as many items as requested; false on a partial page
```

This can produce a false positive on the last page when the total happens to be an exact
multiple of `per_page`.  The client will make one extra empty request and then stop.  This
is a well-known and accepted trade-off for page-number pagination exposed as cursors.

### `hasPreviousPage`

```lua
has_previous_page = (page > 1)
```

Always accurate because `page` is encoded in the cursor.

## Connection assembly helper

```lua
-- internal/graphql_translators.lua
--
-- Assemble a standard Relay Connection table from already-translated nodes.
--
-- typename:  base GraphQL type name, e.g. "Issue" (NOT "IssueConnection")
-- nodes:     array of translated item tables
-- args:      GraphQL connection args { first, after, last, before }
-- total:     integer totalCount, or nil (falls back to #nodes)
--
-- Returns a table matching the *Connection + PageInfo GraphQL shapes.
function graphql_make_connection(typename, nodes, args, total)
  local per_page = args.first or 30
  local page = 1
  if args.after then
    local p = graphql_cursor_to_page(args.after)
    if p then page = p + 1 end
  end

  local count = #nodes
  local has_next
  if total then
    has_next = (page * per_page) < total
  else
    has_next = (count == per_page)
  end

  local start_cursor = count > 0 and graphql_page_to_cursor(page) or nil
  local end_cursor   = start_cursor  -- same page; item-level cursors are a Phase 2 item

  local edges = {}
  for i, node in ipairs(nodes) do
    edges[i] = {
      __typename = typename .. "Edge",
      cursor     = graphql_page_to_cursor(page),
      node       = node,
    }
  end

  return {
    __typename  = typename .. "Connection",
    total_count = total or count,
    page_info   = {
      __typename         = "PageInfo",
      has_next_page      = has_next,
      has_previous_page  = page > 1,
      start_cursor       = start_cursor,
      end_cursor         = end_cursor,
    },
    nodes = nodes,
    edges = edges,
  }
end
```

The `edges[i].cursor` is the same for all edges on the same page because page-number
cursors encode the page, not the item offset.  Clients that iterate over `edges.cursor`
will see repeated values on the same page; clients that only use `pageInfo.endCursor` for
the next request are unaffected.  Item-level cursor precision is a Phase 2 item.

## Convenience wrappers

```lua
-- Convenience wrappers for common connection types
function graphql_issues_connection(nodes, args, total)
  return graphql_make_connection("Issue", nodes, args, total)
end

function graphql_prs_connection(nodes, args, total)
  return graphql_make_connection("PullRequest", nodes, args, total)
end

function graphql_repos_connection(nodes, args, total)
  return graphql_make_connection("Repository", nodes, args, total)
end

function graphql_users_connection(nodes, args, total)
  return graphql_make_connection("User", nodes, args, total)
end

function graphql_labels_connection(nodes, args, total)
  return graphql_make_connection("Label", nodes, args, total)
end

function graphql_refs_connection(nodes, args, total)
  return graphql_make_connection("Ref", nodes, args, total)
end
```

These are exported globals from `graphql_translators.lua`, available to all backends.

## Inline connection helper

For small lists already present in the parent REST response (issue labels, PR assignees,
etc.) where no pagination is needed and `hasPreviousPage`/`hasNextPage` are always false:

```lua
function graphql_inline_connection(typename, nodes)
  return {
    __typename  = typename .. "Connection",
    total_count = #nodes,
    page_info   = {
      __typename         = "PageInfo",
      has_next_page      = false,
      has_previous_page  = false,
      start_cursor       = nil,
      end_cursor         = nil,
    },
    nodes = nodes,
    edges = (function()
      local edges = {}
      for i, node in ipairs(nodes) do
        edges[i] = { __typename = typename .. "Edge", cursor = "", node = node }
      end
      return edges
    end)(),
  }
end
```

## Field name mapping for Connection fields

The executor plucks connection sub-fields from the returned table.  The Lua table keys
must match the GraphQL field names (camelCase):

| GraphQL field | Lua table key |
|---|---|
| `totalCount` | `total_count` |
| `pageInfo` | `page_info` |
| `pageInfo.hasNextPage` | `page_info.has_next_page` |
| `pageInfo.hasPreviousPage` | `page_info.has_previous_page` |
| `pageInfo.startCursor` | `page_info.start_cursor` |
| `pageInfo.endCursor` | `page_info.end_cursor` |
| `nodes` | `nodes` |
| `edges` | `edges` |
| `edges[i].cursor` | `edges[i].cursor` |
| `edges[i].node` | `edges[i].node` |

Wait — the executor's field pluck reads `parent[field_name]` where `field_name` is the
GraphQL field name from the query.  So the Lua keys **must** match the GraphQL names
exactly (camelCase).

The connection assembly functions above use snake_case keys (`total_count`,
`has_next_page`, etc.) which do not match the GraphQL camelCase names.  This must be
resolved by either:

**Option A (recommended)**: Use camelCase keys in connection tables, matching GraphQL
field names directly.  Change the assembly helpers to use `totalCount`, `pageInfo`,
`hasNextPage`, `hasPreviousPage`, `startCursor`, `endCursor`.

**Option B**: Register sub-resolvers for every Connection and PageInfo field that pluck
using the snake_case key.  Too many resolvers for a minor style concern.

**Decision: Option A.**  The connection tables use GraphQL camelCase keys throughout.
This is an exception to the usual pattern (REST translators use GitHub REST snake_case
keys) but is necessary because the executor plucks by GraphQL field name.

Revised assembly helper (corrected key names):

```lua
function graphql_make_connection(typename, nodes, args, total)
  -- ... (same logic as above, but camelCase keys) ...
  return {
    __typename = typename .. "Connection",
    totalCount = total or count,
    pageInfo   = {
      __typename        = "PageInfo",
      hasNextPage       = has_next,
      hasPreviousPage   = page > 1,
      startCursor       = start_cursor,
      endCursor         = end_cursor,
    },
    nodes = nodes,
    edges = edges,
  }
end
```

All connection-related table keys are camelCase.  All other translated object tables
(Repository, User, Issue, …) also use camelCase keys (see [05-translation.md](05-translation.md)).
This is the general rule: **all Lua tables produced for the GraphQL executor use GraphQL
field names (camelCase) as their keys**, not REST field names (snake_case).

## Testing

Unit tests in `test/graphql-pagination.lua`:

- `graphql_page_to_cursor(1)` → deterministic base64 string.
- `graphql_cursor_to_page(graphql_page_to_cursor(3))` → `3` (round-trip).
- `graphql_cursor_to_page("invalid")` → `nil`.
- `graphql_cursor_to_page(nil)` → `nil`.
- `graphql_cursor_url(base, {first=10}, params)` → URL with `limit=10`, no `page` param.
- `graphql_cursor_url(base, {first=10, after=cursor_for_page_2}, params)` → URL with
  `limit=10&page=3`.
- `graphql_make_connection("Issue", nodes, {first=2}, nil)` where `#nodes==2`:
  `hasNextPage = true`, `hasPreviousPage = false`, `totalCount = 2`.
- `graphql_make_connection("Issue", nodes, {first=5}, nil)` where `#nodes==3`:
  `hasNextPage = false` (partial page).
- `graphql_make_connection("Issue", nodes, {first=10, after=cursor_for_page_1}, 25)`:
  page=2, `hasNextPage = (2*10)<25 = true`, `hasPreviousPage = true`.
- `graphql_make_connection("Issue", nodes, {first=10, after=cursor_for_page_2}, 25)`:
  page=3, `hasNextPage = (3*10)<25 = false`.
- `graphql_inline_connection("Label", labels)`: `hasNextPage = false`,
  `hasPreviousPage = false`, `totalCount = #labels`.
- Backward pagination: `graphql_make_connection` with `{last=5}` returns empty connection
  and appends to `ctx.errors`.

Integration: an executor test that selects
`repository { issues(first: 2) { totalCount pageInfo { hasNextPage endCursor } nodes { title } } }`
with a stub resolver returning 2 issues verifies the full connection shape is assembled and
plucked correctly.
