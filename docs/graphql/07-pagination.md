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

Confusio uses **item-level cursors**: a cursor encodes a 1-based page index and a 1-based
item index within that page.

```
cursor = EncodeBase64("page:" .. tostring(page_number) .. ":" .. tostring(item_index))
```

Examples (page 1, items 1–3):

| Page | Item | Cursor (base64 of `page:N:M`) |
|------|------|-------------------------------|
| 1 | 1 | `"cGFnZToxOjE="` |
| 1 | 2 | `"cGFnZToxOjI="` |
| 1 | 3 | `"cGFnZToxOjM="` |
| 2 | 1 | `"cGFnZTI6MQ=="` |

Encoding and decoding:

```lua
-- internal/graphql_translators.lua

-- index is optional; omitting it produces a legacy "page:N" cursor (still valid).
function graphql_page_to_cursor(page, index)
  if index then
    return EncodeBase64("page:" .. tostring(page) .. ":" .. tostring(index))
  end
  return EncodeBase64("page:" .. tostring(page))
end

-- Accepts both "page:N" (legacy) and "page:N:M" (item-level).
-- Returns the 1-based page number; the item index is ignored for REST URL building.
function graphql_cursor_to_page(cursor)
  if not cursor then return nil end
  local decoded = DecodeBase64(cursor)
  if not decoded then return nil end
  local n = decoded:match("^page:(%d+)")
  return n and tonumber(n)
end
```

`graphql_cursor_to_page` returns `nil` for any cursor that does not start with the
`page:` prefix, including GitHub's real opaque cursors.  Resolvers treat a nil result the
same as a missing cursor (start from page 1).

### Why page-number + item-index, not pure offsets

Offset cursors (`offset:N`) are misaligned when the client changes `first` between
requests.  By encoding only the page number for REST URL construction, item-level cursors
remain stable across page-size changes: a cursor obtained with `first: 10` is still valid
when reused with `first: 20` (it shifts which page is fetched, but the cursor itself does
not become invalid).

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

### Argument semantics

| Arguments | Meaning | REST translation |
|-----------|---------|-----------------|
| `last: N` only | Last N items overall | two-pass: prefetch total → `per_page=N, page=ceil(total/N)` |
| `last: N, before: cursor` | N items before cursor | `per_page=N, page=cursor_page-1` |
| `before: cursor` only | Default page before cursor | `per_page=30, page=cursor_page-1` |

### Two-pass total-prefetch strategy

Seeking the last page requires knowing the total item count *before* building the REST URL.
For `last: N` without a `before` cursor, resolvers use a two-pass approach:

1. **Prefetch pass**: call `graphql_prefetch_total_from_headers` with `first: 1` to fetch
   a single-item page and read the total-count header (`X-Total` / `X-Total-Count`).
   This avoids downloading a full page of data we will discard.

2. **Real pass**: call `graphql_cursor_url(url_base, args, param_names, total)` with the
   fetched total so it computes `page = ceil(total / per_page)` and fetches the correct
   last page.

```lua
-- internal/graphql_translators.lua
--
-- Lightweight prefetch that returns the total item count from headers.
-- Only call when args.last is set and args.before is absent.
function graphql_prefetch_total_from_headers(fetch_json, url_base, param_names, header_names)
  local count_url = graphql_cursor_url(url_base, { first = 1 }, param_names)
  local _, headers, _ = graphql_fetch_with_headers(fetch_json, count_url)
  if not headers then return nil end
  for _, name in ipairs(header_names) do
    local v = headers[name] and tonumber(headers[name])
    if v then return v end
  end
  return nil
end
```

Helper usage in a backend connection resolver:

```lua
local function gitea_repo_connection(owner, repo, suffix, args, ctx, translate_fn, make_conn)
  local url_base = base() .. "/repos/" .. owner .. "/" .. repo .. suffix
  local total
  if args.last and not args.before then
    total = graphql_prefetch_total_from_headers(
      fetch_json, url_base, GITEA_PAGES, { "X-Total", "X-Total-Count" }
    )
  end
  local url = graphql_cursor_url(url_base, args, GITEA_PAGES, total)
  local data, headers, err = graphql_fetch_with_headers(fetch_json, url)
  if not data then
    graphql_error(ctx, err)
    return nil
  end
  total = gitea_total(headers) or total
  -- translate + return make_conn(nodes, args, total, ctx)
end
```

### URL construction for backward pagination

`graphql_cursor_url` accepts an optional fourth argument `total`.  When `args.last` (or
`args.before`) is detected, the backward-pagination branch runs:

| Case | REST page |
|------|-----------|
| `last: N, before: cursor(P)` where P ≥ 2 | `page=P-1, per_page=N` |
| `last: N, before: cursor(1)` or malformed cursor | `page=1, per_page=N` (edge: `make_connection` returns empty) |
| `last: N` with `total` provided | `page=ceil(total/N), per_page=N` |
| `last: N` without `total` | `page=1, per_page=N` (fallback; resolver uses two-pass) |

### Connection assembly for backward pagination

`graphql_make_connection` detects `args.last` or `args.before` and enters the backward
branch:

**`before: cursor(P)` where P ≥ 2 — one page before the cursor:**

```lua
local page = before_page - 1
return {
  pageInfo = {
    hasNextPage     = true,  -- cursor page P proves items exist there
    hasPreviousPage = page > 1,
    startCursor     = count > 0 and edges[1].cursor or nil,
    endCursor       = count > 0 and edges[count].cursor or nil,
  },
  totalCount = total or count,
  nodes = nodes,
  edges = edges,
}
```

**`before: cursor(1)` or malformed cursor — nothing before the first page:**

```lua
return {
  pageInfo = {
    hasNextPage     = (before_page ~= nil and before_page >= 1),
    hasPreviousPage = false,
    startCursor     = nil,
    endCursor       = nil,
  },
  totalCount = total or 0,
  nodes = {},
  edges = {},
}
```

**`last: N` without `before` — last page overall:**

```lua
local page = total and math.max(1, math.ceil(total / per_page)) or 1
local has_next = total ~= nil and (page * per_page) < total
              or total == nil and count == per_page  -- heuristic fallback
return {
  pageInfo = {
    hasNextPage     = has_next,
    hasPreviousPage = page > 1,
    ...
  },
  ...
}
```

### Backends without total-count headers

Backends that do not return `X-Total` / `X-Total-Count` (Bitbucket Cloud, Pagure,
Sourcehut) cannot determine the total page count.  For `last: N` without `before`:

- The two-pass prefetch returns `nil` (no header).
- `graphql_cursor_url` falls back to `page=1`.
- `graphql_make_connection` uses the page-full heuristic for `hasNextPage`.
- `hasPreviousPage` is always `false` (page 1).

Clients receive the first page of results when they ask for the last, which is incorrect
but does not error.  This is documented in [14-backend-feasibility.md](14-backend-feasibility.md).

`last: N, before: cursor` always works correctly (no total needed).

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

  -- Each edge carries a unique item-level cursor: graphql_page_to_cursor(page, i).
  local edges = {}
  for i, node in ipairs(nodes) do
    edges[i] = {
      __typename = typename .. "Edge",
      cursor     = graphql_page_to_cursor(page, i),
      node       = node,
    }
  end

  return {
    __typename = typename .. "Connection",
    totalCount = total or count,
    pageInfo   = {
      __typename      = "PageInfo",
      hasNextPage     = has_next,
      hasPreviousPage = page > 1,
      startCursor     = count > 0 and edges[1].cursor or nil,
      endCursor       = count > 0 and edges[count].cursor or nil,
    },
    nodes = nodes,
    edges = edges,
  }
end
```

Each `edges[i].cursor` uniquely identifies that item by page and position within the page.
`startCursor` and `endCursor` are the first and last edge cursors respectively; they are
distinct for multi-item pages and equal only when the page contains a single item.

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

### Unit tests — `test/graphql-pagination.lua`

Cursor encoding (item-level):

- `graphql_page_to_cursor(1, 1)` → non-nil; `graphql_cursor_to_page` returns `1`.
- `graphql_page_to_cursor(3, 5)` → decodes to page `3`.
- `graphql_page_to_cursor(1, 1) ~= graphql_page_to_cursor(1, 2)` (same page, different items).
- `graphql_page_to_cursor(1, 1) ~= graphql_page_to_cursor(2, 1)` (different pages, same position).
- `graphql_page_to_cursor(1) ~= graphql_page_to_cursor(1, 1)` (page-only vs item-level).
- Legacy `page:N` cursors still decode correctly alongside item-level cursors.

Forward pagination:

- `graphql_page_to_cursor(1)` → deterministic base64 string.
- `graphql_cursor_to_page(graphql_page_to_cursor(3))` → `3` (round-trip, page-only form).
- `graphql_cursor_to_page("invalid")` → `nil`.
- `graphql_cursor_url(base, {first=10}, params)` → URL with `limit=10`, no `page` param.
- `graphql_cursor_url(base, {first=10, after=cursor_for_page_2}, params)` → URL with
  `limit=10&page=3`.
- `graphql_cursor_url(base, {first=10, after=graphql_page_to_cursor(2, 5)}, params)` →
  URL with `limit=10&page=3` (item index ignored for URL building).
- `graphql_make_connection("Issue", nodes, {first=2}, nil)` where `#nodes==2`:
  `hasNextPage = true`, `hasPreviousPage = false`, `totalCount = 2`,
  `startCursor ~= endCursor` (two distinct item-level cursors).
- `graphql_make_connection("Issue", [single_node], {first=10}, 1)`:
  `startCursor == endCursor` (only one edge).
- `graphql_make_connection("Issue", nodes, {first=10, after=cursor_for_page_1}, 25)`:
  page=2, `hasNextPage = true`, `hasPreviousPage = true`.

Backward pagination:

- `graphql_cursor_url(base, {last=10}, params, 25)` → URL with `limit=10&page=3`
  (`ceil(25/10)=3`).
- `graphql_cursor_url(base, {last=10}, params)` (no total) → URL with `limit=10`, page 1
  fallback.
- `graphql_cursor_url(base, {last=10, before=cursor(3)}, params)` → URL with
  `limit=10&page=2`.
- `graphql_cursor_url(base, {last=10, before=graphql_page_to_cursor(3, 5)}, params)` →
  URL with `limit=10&page=2` (item index ignored; before page 3 → fetch page 2).
- `graphql_cursor_url(base, {last=5, before=cursor(1)}, params)` → URL with `limit=5`
  (clamped to page 1; `make_connection` returns empty).
- `graphql_make_connection("Issue", nodes, {last=10}, 25)`: page=3, `hasNextPage=false`,
  `hasPreviousPage=true`, `startCursor ~= endCursor` (10 distinct item-level cursors).
- `graphql_make_connection("Issue", nodes, {last=10}, 10)`: page=1, `hasNextPage=false`,
  `hasPreviousPage=false`.
- `graphql_make_connection("Issue", nodes, {last=3, before=cursor(3)}, 10)`: page=2,
  `hasNextPage=true`, `hasPreviousPage=true`, `startCursor ~= endCursor` (3 items).
- `graphql_make_connection("Issue", nodes, {last=3, before=cursor(1)}, 10)`: empty nodes,
  `hasNextPage=true` (cursor(1) is valid), `hasPreviousPage=false`.
- `graphql_make_connection("Issue", nodes, {before="notacursor"}, 10)`: empty nodes,
  `hasNextPage=false` (malformed cursor), `hasPreviousPage=false`.
- `graphql_inline_connection("Label", labels)`: `hasNextPage = false`,
  `hasPreviousPage = false`, `totalCount = #labels`.

### Unit tests — `test/gitea-graphql.hurl` (against mock)

- `issues(last: 1)`: mock returns X-Total: 1 → two-pass resolves to page 1; 1 node,
  `hasPreviousPage=false`, `hasNextPage=false`.
- `issues(first: 1)` to capture `endCursor` (cursor for page 1), then
  `issues(last: 1, before: endCursor)`: empty nodes (nothing before page 1),
  `hasNextPage=true`, `hasPreviousPage=false`.

### Integration tests — `test/integration-graphql-mutations.hurl` (live gitea.com)

Run when `GITEA_TOKEN` is set.  Three issues are created inside `confusio-mutation-test`
so the repo has enough data to exercise the two-pass path:

- `issues(last: 1)` with total=3: prefetch returns 3, `last_page=3`; resolver fetches
  page 3; `hasPreviousPage=true`, `hasNextPage=false`, `totalCount=3`.
- `issues(first: 1)` to capture `endCursor` for page 1, then
  `issues(last: 1, before: endCursor)`: empty nodes, `hasNextPage=true`,
  `hasPreviousPage=false`, `totalCount=3`.
