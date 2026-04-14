# 05 — GraphQL-to-REST Translation and Resolver Binding Model

## What this document covers

The executor (see [04-executor.md](04-executor.md)) dispatches each GraphQL field to a
resolver.  This document specifies how resolvers are written, how they connect to the
existing transport layer, and how REST API responses are translated into the GraphQL field
shapes the executor expects.

## Translation pipeline

Every backend already translates its native API responses to GitHub REST field shapes.
GitLab's `translate_gl_repo`, Gitea's `translate_repo`, Bitbucket's `translate_bb_repo`,
and so on, all produce a table with the same keys: `full_name`, `stargazers_count`,
`html_url`, `created_at`, etc.

The new GraphQL layer adds one more stage that converts those **GitHub REST shapes** to
**GitHub GraphQL shapes** (camelCase field names, nested objects, enum values):

```
Native backend response
  → existing backend translator   (backend-specific: translate_gl_repo, translate_repo, …)
  → GitHub REST shape             (snake_case; same across all backends)
  → graphql_translate_*           (shared; defined in internal/graphql_translators.lua)
  → GraphQL shape                 (camelCase; returned by resolvers to the executor)
```

Because the second stage reads only GitHub REST field names, it is **backend-agnostic**.
Every backend that already produces correct REST translations gets GraphQL translations for
free.

## New module: `internal/graphql_translators.lua`

Exports globals used by resolvers in every backend:

```
graphql_translate_repo(r)     — Repository object
graphql_translate_user(u)     — User object
graphql_translate_org(o)      — Organization object
graphql_translate_owner(o)    — User or Organization (discriminated by o.type)
graphql_translate_issue(i)    — Issue object
graphql_translate_pr(p)       — PullRequest object
graphql_translate_label(l)    — Label object
graphql_translate_milestone(m)— Milestone object
graphql_translate_comment(c)  — IssueComment object
graphql_translate_commit(c)   — Commit object
graphql_translate_ref(r, repo)— Ref object (requires repo for context)
graphql_translate_release(r)  — Release object
encode_node_id(type, id)      — base64-encode a Node ID ("Type:id")
decode_node_id(encoded)       — returns type, id strings; nil if malformed
graphql_fetch(fetch_json, path[, method[, body]])
                              — shared fetch + decode helper for resolvers
```

Load order: after `translators.lua` (which defines the REST-stage functions), before
backends:

```lua
dofile("/zip/internal/translators.lua")
dofile("/zip/internal/graphql_parser.lua")
dofile("/zip/internal/graphql_schema_data.lua")
dofile("/zip/internal/graphql_schema.lua")
dofile("/zip/internal/graphql_executor.lua")
dofile("/zip/internal/graphql_translators.lua")   -- new
dofile("/zip/internal/families.lua")
```

## Field mapping reference

### Repository

| GitHub REST field | GraphQL field | Notes |
|------|------|------|
| `id` | `id` | via `encode_node_id("Repository", tostring(id))` |
| `name` | `name` | — |
| `full_name` | `nameWithOwner` | `"owner/name"` string |
| `description` | `description` | `nil` if absent |
| `private` | `isPrivate` | boolean |
| `fork` | `isFork` | boolean |
| `archived` | `isArchived` | boolean |
| `disabled` | `isDisabled` | boolean |
| `html_url` | `url` | — |
| `ssh_url` | `sshUrl` | — |
| `clone_url` | `cloneUrl` | — |
| `homepage` | `homepageUrl` | `nil` if absent or `""` |
| `stargazers_count` | `stargazerCount` | — |
| `forks_count` | `forkCount` | — |
| `size` | `diskUsage` | in KiB |
| `language` | `primaryLanguage` | `nil` or `{ __typename="Language", name=value }` |
| `visibility` | `visibility` | `"PUBLIC"` / `"PRIVATE"` / `"INTERNAL"` (uppercased) |
| `has_issues` | `hasIssuesEnabled` | boolean |
| `has_wiki` | `hasWikiEnabled` | boolean |
| `has_projects` | `hasProjectsEnabled` | boolean |
| `created_at` | `createdAt` | ISO 8601 string passthrough |
| `updated_at` | `updatedAt` | — |
| `pushed_at` | `pushedAt` | — |
| `default_branch` | `defaultBranchRef` | `nil` or `{ __typename="Ref", name=value }` |
| `owner` | `owner` | via `graphql_translate_owner(owner)` |

Sub-resolver fields (`issues`, `pullRequests`, `labels`, `refs`, `releases`, `stargazers`,
`watchers`, `collaborators`) are left `nil` by `graphql_translate_repo`.  The executor
retrieves them via registered sub-resolvers (extra REST calls) when the client selects them.

### User

| GitHub REST field | GraphQL field | Notes |
|------|------|------|
| `id` | `id` | via `encode_node_id("User", tostring(id))` |
| `login` | `login` | — |
| `name` | `name` | `nil` if absent |
| `email` | `email` | `""` if absent (some backends omit it) |
| `bio` | `bio` | `nil` if absent |
| `company` | `company` | `nil` if absent |
| `location` | `location` | `nil` if absent |
| `blog` | `websiteUrl` | `nil` if `""` |
| `avatar_url` | `avatarUrl` | — |
| `html_url` | `url` | — |
| `site_admin` | `isSiteAdmin` | boolean |
| `created_at` | `createdAt` | — |
| `updated_at` | `updatedAt` | — |

`isViewer` is `false` from `graphql_translate_user`; the `Query.viewer` resolver sets it
to `true` after calling `graphql_translate_user`.

### Organization

Produced by `graphql_translate_org`, which reads the same REST fields as `graphql_translate_user`
plus:

| REST field | GraphQL field |
|------|------|
| `login` | `login` |
| `name` | `name` |
| `description` | `description` |
| `avatar_url` | `avatarUrl` |
| `html_url` | `url` |
| `blog` | `websiteUrl` |
| `email` | `email` |
| `location` | `location` |
| `created_at` | `createdAt` |
| `updated_at` | `updatedAt` |

`__typename` is `"Organization"`.

### Owner discriminator

`graphql_translate_owner(o)` branches on `o.type`:
- `"Organization"` → calls `graphql_translate_org(o)`, sets `__typename = "Organization"`
- anything else → calls `graphql_translate_user(o)`, sets `__typename = "User"`

### Issue

| REST field | GraphQL field | Notes |
|------|------|------|
| `id` | `id` | via `encode_node_id("Issue", tostring(id))` |
| `number` | `number` | integer |
| `title` | `title` | — |
| `body` | `body` | `nil` if absent |
| `state` | `state` | `"open"` → `"OPEN"`, `"closed"` → `"CLOSED"` |
| `html_url` | `url` | — |
| `user` | `author` | via `graphql_translate_user(user)` |
| `assignees` | `assignees.nodes` | wrapped in Connection shape |
| `labels` | `labels.nodes` | wrapped in Connection shape |
| `milestone` | `milestone` | via `graphql_translate_milestone(milestone)` or `nil` |
| `comments` | `comments.totalCount` | integer; full list via sub-resolver |
| `created_at` | `createdAt` | — |
| `updated_at` | `updatedAt` | — |
| `closed_at` | `closedAt` | `nil` if open |
| `pull_request` | (used to detect if item is a PR; should not appear as Issue) | |

`pull_request` non-nil means the issue is actually a pull request.  Resolvers must filter
these out when populating the `issues` connection.

### PullRequest

| REST field | GraphQL field | Notes |
|------|------|------|
| `id` | `id` | via `encode_node_id("PullRequest", tostring(id))` |
| `number` | `number` | — |
| `title` | `title` | — |
| `body` | `body` | — |
| `state` | `state` | `"open"` → `"OPEN"`, `"closed"` → `"CLOSED"`, `"merged"` (REST has no merged state; derive from `merged_at ~= nil`) |
| `merged` | `merged` | boolean |
| `merged_at` | `mergedAt` | `nil` if unmerged |
| `html_url` | `url` | — |
| `user` | `author` | — |
| `head.ref` | `headRefName` | branch name string |
| `head.sha` | `headRefOid` | commit SHA |
| `base.ref` | `baseRefName` | — |
| `base.sha` | `baseRefOid` | — |
| `mergeable` | `mergeable` | `"MERGEABLE"` / `"CONFLICTING"` / `"UNKNOWN"` enum |
| `assignees` | `assignees.nodes` | Connection shape |
| `labels` | `labels.nodes` | Connection shape |
| `created_at` | `createdAt` | — |
| `updated_at` | `updatedAt` | — |
| `closed_at` | `closedAt` | — |

### Small types

| Function | Input | GraphQL type |
|----------|-------|------|
| `graphql_translate_label(l)` | REST label | `Label` |
| `graphql_translate_milestone(m)` | REST milestone | `Milestone` |
| `graphql_translate_comment(c)` | REST comment | `IssueComment` |
| `graphql_translate_commit(c)` | REST commit | `Commit` |
| `graphql_translate_ref(r, repo)` | REST ref + repo table | `Ref` |
| `graphql_translate_release(r)` | REST release | `Release` |

All set `__typename` to the appropriate GraphQL type name.

### Connection wrapping helper

Many GraphQL fields return a Connection type (Relay spec).  The translator emits a
pre-populated Connection table for small inline lists (e.g. `labels`, `assignees` on an
issue) where all items are already present in the REST response:

```lua
-- internal/graphql_translators.lua
local function make_inline_connection(typename, items)
  return {
    __typename  = typename,
    total_count = #items,
    nodes       = items,
    page_info   = {
      __typename        = "PageInfo",
      has_next_page     = false,
      has_previous_page = false,
      start_cursor      = nil,
      end_cursor        = nil,
    },
  }
end
```

Used by translators for fields like `issue.labels`, `issue.assignees`.  For fields that
require a separate paginated REST call (`repository.issues`, `repository.pullRequests`),
the Connection is built by the sub-resolver instead.

## `graphql_fetch` helper

Resolvers should not call `Fetch` directly.  `graphql_fetch` is a thin adapter that:
1. Calls the backend's local `fetch_json` (closed over from `make_backend_transport`)
2. Decodes the JSON body
3. Returns `decoded_table, nil` on success or `nil, "error message"` on failure
4. Appends an error to `ctx.errors` on failure

```lua
-- internal/graphql_translators.lua
function graphql_fetch(fetch_json, path, method, body)
  local ok, status, _, raw = fetch_json(path, method, body)
  if not ok then
    return nil, "network error fetching " .. path
  end
  if status == 404 then
    return nil, "not found: " .. path
  end
  if status < 200 or status >= 300 then
    return nil, "upstream error " .. tostring(status) .. " fetching " .. path
  end
  local decoded = DecodeJson(raw)
  if decoded == nil then
    return nil, "invalid JSON from upstream for " .. path
  end
  return decoded, nil
end
```

Resolvers use it:

```lua
local data, err = graphql_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. name)
if not data then
  append_graphql_error(ctx, err, field_node)
  return nil
end
```

`append_graphql_error(ctx, message, field_node)` is defined in `graphql_executor.lua` and
appends a formatted error table to `ctx.errors`.  Backends call it whenever a resolver
cannot produce a value.

## Resolver binding: backend file layout

Backends register GraphQL resolvers at the bottom of their existing `.lua` file, after
all REST handlers.  The pattern mirrors how `backend_impl` is built:

```lua
-- backends/gitea.lua (additions at the bottom)

-- ============================================================
-- GraphQL resolvers
-- ============================================================

local function gql_translate_repo(r)
  return graphql_translate_repo(translate_repo(r))
end

local function gql_translate_user(u)
  return graphql_translate_user(translate_user(u))
end

graphql_resolvers["Query.viewer"] = function(parent, args, ctx)
  local data, err = graphql_fetch(fetch_json, base() .. "/user")
  if not data then
    append_graphql_error(ctx, err)
    return nil
  end
  local u = graphql_translate_user(translate_user(data))
  u.isViewer = true
  return u
end

graphql_resolvers["Query.user"] = function(parent, args, ctx)
  if not args.login then
    append_graphql_error(ctx, "user requires login argument")
    return nil
  end
  local data, err = graphql_fetch(fetch_json, base() .. "/users/" .. args.login)
  if not data then
    append_graphql_error(ctx, err)
    return nil
  end
  return graphql_translate_user(translate_user(data))
end

graphql_resolvers["Query.repository"] = function(parent, args, ctx)
  if not args.owner or not args.name then
    append_graphql_error(ctx, "repository requires owner and name")
    return nil
  end
  local data, err = graphql_fetch(
    fetch_json, base() .. "/repos/" .. args.owner .. "/" .. args.name)
  if not data then
    append_graphql_error(ctx, err)
    return nil
  end
  return gql_translate_repo(data)
end

graphql_resolvers["Repository.issues"] = function(parent, args, ctx)
  -- parent is a translated Repository table; owner/name come from nameWithOwner
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  local url = base() .. "/repos/" .. owner .. "/" .. name .. "/issues"
  url = url .. "?type=issues"  -- exclude pull requests
  if args.states and args.states[1] then
    url = url .. "&state=" .. args.states[1]:lower()
  end
  if args.first then url = url .. "&limit=" .. tostring(args.first) end
  if args.after then url = url .. "&page=" .. graphql_cursor_to_page(args.after) end
  local data, err = graphql_fetch(fetch_json, url)
  if not data then
    append_graphql_error(ctx, err)
    return nil
  end
  return graphql_issues_connection(data, args)
end
```

### Two-stage translation call pattern

The double-call `graphql_translate_repo(translate_repo(raw))` is the standard pattern for
Gitea-family backends.  Backends that write their own first-stage translator (GitLab,
Bitbucket, etc.) follow the same pattern with their own translator:

```lua
-- backends/gitlab.lua
graphql_resolvers["Query.repository"] = function(parent, args, ctx)
  local data, err = graphql_fetch(fetch_json, base() .. "/projects/" .. ...)
  if not data then ... end
  return graphql_translate_repo(translate_gl_repo(data))  -- GL first stage, then GQL stage
end
```

GitBucket, which mirrors the GitHub v3 REST API directly, skips the first stage:

```lua
-- backends/gitbucket.lua
graphql_resolvers["Query.repository"] = function(parent, args, ctx)
  local data, err = graphql_fetch(fetch_json, base() .. "/api/v3/repos/" .. ...)
  if not data then ... end
  return graphql_translate_repo(data)  -- data is already GitHub REST shape
end
```

## Enum value mapping

GraphQL enums use SCREAMING_SNAKE_CASE; REST APIs use lowercase strings.  The mapping is
centralised in `graphql_translators.lua`:

```lua
local ISSUE_STATE = { open = "OPEN", closed = "CLOSED" }
local PR_STATE    = { open = "OPEN", closed = "CLOSED", merged = "MERGED" }
local VISIBILITY  = { public = "PUBLIC", private = "PRIVATE", internal = "INTERNAL" }
local MERGEABLE   = { clean = "MERGEABLE", dirty = "CONFLICTING", unknown = "UNKNOWN" }
```

Translators call e.g. `ISSUE_STATE[rest.state] or "OPEN"` — the fallback prevents a nil
`state` field from crashing the response.

## Sub-resolver patterns

### Pattern 1 — Paginated connection (most common)

Used for `Repository.issues`, `Repository.pullRequests`, `User.repositories`, etc.:

```lua
graphql_resolvers["Repository.issues"] = function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  local url = build_url(base() .. "/repos/" .. owner .. "/" .. name .. "/issues", args)
  local data, err = graphql_fetch(fetch_json, url)
  if not data then
    append_graphql_error(ctx, err)
    return nil
  end
  local nodes = translate_list(
    function(i) return graphql_translate_issue(translate_issue(i)) end, data)
  return graphql_issues_connection(nodes, args, #data)
end
```

`graphql_issues_connection(nodes, args, count)` is a helper in `graphql_translators.lua`
that wraps a node array in the Relay Connection shape (see [07-pagination.md](07-pagination.md)).

### Pattern 2 — Inline list (already present in parent response)

Used for `Issue.labels`, `Issue.assignees`, `PullRequest.labels`:

No sub-resolver needed.  `graphql_translate_issue` directly populates these as
`make_inline_connection("LabelConnection", nodes)`.  The executor plucks them from the
parent table.

### Pattern 3 — Single sub-object (already present in parent response)

Used for `Repository.owner`, `Repository.primaryLanguage`, `Issue.author`:

No sub-resolver needed.  The first-stage translator populates the sub-object inline.  The
executor plucks it from the parent table and recurses into the selection set.

### Pattern 4 — Derived sub-object (requires second REST call)

Used for `Repository.defaultBranchRef` when the client selects fields beyond `.name`:

```lua
graphql_resolvers["Repository.defaultBranchRef"] = function(parent, args, ctx)
  -- parent.defaultBranchRef is already a {__typename="Ref", name="main"} stub
  -- if the client only selects .name, field pluck suffices.
  -- This resolver is only needed if the client selects .target (the commit),
  -- which requires a separate API call.
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  local branch = parent.defaultBranchRef and parent.defaultBranchRef.name
  if not branch then return nil end
  local data, err = graphql_fetch(
    fetch_json, base() .. "/repos/" .. owner .. "/" .. name .. "/branches/" .. branch)
  if not data then
    append_graphql_error(ctx, err)
    return nil
  end
  return graphql_translate_ref(data, parent)
end
```

Register this resolver only if the basic stub (already in the translated repo) is
insufficient for the expected query patterns.

## Resolver coverage per root field

The minimum set of resolvers a backend must implement for Phase 1:

| Resolver key | REST call |
|---|---|
| `Query.viewer` | `GET /user` |
| `Query.user` | `GET /users/{login}` |
| `Query.organization` | `GET /orgs/{login}` |
| `Query.repository` | `GET /repos/{owner}/{name}` |
| `Query.search` | `GET /search/repositories`, `/search/users`, `/search/issues` |
| `Query.rateLimit` | `GET /rate_limit` or synthesised |
| `Repository.issues` | `GET /repos/{o}/{r}/issues` |
| `Repository.pullRequests` | `GET /repos/{o}/{r}/pulls` |
| `Repository.labels` | `GET /repos/{o}/{r}/labels` |
| `Repository.releases` | `GET /repos/{o}/{r}/releases` |
| `Repository.refs` | `GET /repos/{o}/{r}/branches` + `/tags` |
| `Repository.collaborators` | `GET /repos/{o}/{r}/collaborators` |
| `User.repositories` | `GET /users/{login}/repos` |
| `Organization.repositories` | `GET /orgs/{org}/repos` |
| `Organization.members` | `GET /orgs/{org}/members` |

Each resolver key corresponds to an existing REST endpoint in confusio's catalog.  A
backend that does not implement a given REST endpoint simply omits the corresponding
GraphQL resolver; the executor returns `null` for that field and adds an error entry.

## Node ID encoding

`encode_node_id` and `decode_node_id` are defined in `graphql_translators.lua`:

```lua
function encode_node_id(type_name, id)
  return EncodeBase64(type_name .. ":" .. id)
end

function decode_node_id(encoded)
  local decoded = DecodeBase64(encoded)
  if not decoded then return nil, nil end
  local t, id = decoded:match("^([^:]+):(.+)$")
  return t, id
end
```

`DecodeBase64` is available in Redbean's Lua runtime.  The `node()` root resolver
(see [08-node-id.md](08-node-id.md)) uses `decode_node_id` to dispatch lookups.

## `graphql_translators.lua` exports summary

```
-- Translators (all take GitHub REST-shaped input)
graphql_translate_repo(r)
graphql_translate_user(u)
graphql_translate_org(o)
graphql_translate_owner(o)       -- discriminates User vs Organization
graphql_translate_issue(i)
graphql_translate_pr(p)
graphql_translate_label(l)
graphql_translate_milestone(m)
graphql_translate_comment(c)
graphql_translate_commit(c)
graphql_translate_ref(r, repo)
graphql_translate_release(r)

-- Connection builders
make_inline_connection(typename, nodes)
graphql_issues_connection(nodes, args, count)
graphql_prs_connection(nodes, args, count)
graphql_repos_connection(nodes, args, count)
graphql_users_connection(nodes, args, count)

-- Node ID
encode_node_id(type_name, id)
decode_node_id(encoded)

-- Fetch helper
graphql_fetch(fetch_json, path[, method[, body]])
```

## Testing

Unit tests in `test/graphql-translators.lua`:

- `graphql_translate_repo` maps all fields correctly, including enum uppercasing for
  `visibility` and nested `owner`, `primaryLanguage`, `defaultBranchRef` stubs.
- `graphql_translate_user` sets `isViewer = false`; the viewer resolver overrides it.
- `graphql_translate_issue` maps `state`, `author`, and inline Connection fields for
  `labels` and `assignees`.
- `graphql_translate_pr` maps `merged` / `mergedAt` and `state = "MERGED"` when
  `merged_at` is non-nil.
- `encode_node_id` / `decode_node_id` round-trips correctly; `decode_node_id` returns nil
  for a malformed input.
- `graphql_fetch` returns `nil, "not found"` for a 404, `nil, "network error"` for a
  connection failure, and the decoded table for a 200.
- `make_inline_connection` produces the correct Relay Connection shape with `total_count`
  and `page_info.has_next_page = false`.
