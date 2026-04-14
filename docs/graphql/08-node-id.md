# 08 — Node/ID Global Identifier Scheme and `node()` Resolution

## What this document covers

GitHub's GraphQL API exposes a `Node` interface that every major object type implements.
Clients use opaque `id` fields to store references and later look objects up with
`Query.node(id)` or `Query.nodes(ids)`.  This document specifies confusio's node ID
format, how IDs are encoded into translated objects, how `node()` and `nodes()` dispatch
to REST lookups, and the Phase 1 type coverage.

## The Node interface

```graphql
interface Node {
  id: ID!
}
```

`Repository`, `User`, `Organization`, `Issue`, `PullRequest`, `IssueComment`, `Label`,
`Milestone`, `Release`, `Commit`, `Ref`, and dozens of other types implement `Node`.
Clients treat `id` as an opaque handle — they store it and send it back to the server
later, expecting to retrieve the same object.

## Node ID encoding

Confusio's node IDs are base64-encoded strings in the format:

```
base64("TypeName:local_id")
```

where `local_id` is the **canonical REST path segment** needed to look the object up.

### Why path segments, not integer IDs

Integer IDs are backend-specific and frequently not exposed as a standalone lookup key.
Most REST backends support `GET /repos/{owner}/{repo}` but not `GET /repositories/{integer_id}`.
Path-segment encoding means the `node()` resolver constructs the same REST URL that any
other resolver already uses — no special integer-ID endpoint required.

Path-segment IDs are also stable across confusio restarts and backend schema changes,
whereas a backend's internal integer sequence can be reset.

### Local ID formats by type

| Type | Local ID | Example |
|------|---------|---------|
| `Repository` | `owner/repo` | `octocat/hello-world` |
| `User` | `login` | `octocat` |
| `Organization` | `login` | `github` |
| `Issue` | `owner/repo/number` | `octocat/hello-world/42` |
| `PullRequest` | `owner/repo/number` | `octocat/hello-world/7` |
| `IssueComment` | `owner/repo/comment_id` | `octocat/hello-world/1234567` |
| `PullRequestReviewComment` | `owner/repo/comment_id` | `octocat/hello-world/9876` |
| `Release` | `owner/repo/release_id` | `octocat/hello-world/55` |
| `Label` | `owner/repo/label_id` | `octocat/hello-world/8` |
| `Milestone` | `owner/repo/milestone_number` | `octocat/hello-world/3` |
| `Commit` | `owner/repo/sha` | `octocat/hello-world/abc123` |
| `Ref` | `owner/repo/ref_name` | `octocat/hello-world/refs/heads/main` |

Types with integer IDs in the local part (comment ID, release ID, label ID) use the
backend's native integer because no human-readable alternative exists — there is no
`GET /repos/{o}/{r}/releases/by-name` endpoint.

### `encode_node_id` and `decode_node_id`

Already defined in `internal/graphql_translators.lua`
(see [05-translation.md](05-translation.md)):

```lua
function encode_node_id(type_name, local_id)
  return EncodeBase64(type_name .. ":" .. local_id)
end

function decode_node_id(encoded)
  if not encoded then return nil, nil end
  local decoded = DecodeBase64(encoded)
  if not decoded then return nil, nil end
  local t, id = decoded:match("^([^:]+):(.+)$")
  return t, id  -- both nil if pattern doesn't match
end
```

## Translator context requirements

### Top-level types: context-free

`Repository`, `User`, and `Organization` translators have all the information they need
to produce the node ID:

```lua
-- graphql_translate_repo reads r.full_name ("owner/repo")
id = encode_node_id("Repository", r.full_name)

-- graphql_translate_user reads u.login
id = encode_node_id("User", u.login)

-- graphql_translate_org reads o.login
id = encode_node_id("Organization", o.login)
```

### Context-dependent types: extra arguments

`Issue`, `PullRequest`, and other types that require owner/repo context receive it as
additional arguments to their translator functions.  The sub-resolver has the context
and passes it through:

```lua
-- graphql_translate_issue(i, owner, repo)
id = encode_node_id("Issue", owner .. "/" .. repo .. "/" .. tostring(i.number))

-- graphql_translate_pr(p, owner, repo)
id = encode_node_id("PullRequest", owner .. "/" .. repo .. "/" .. tostring(p.number))

-- graphql_translate_comment(c, owner, repo)
id = encode_node_id("IssueComment", owner .. "/" .. repo .. "/" .. tostring(c.id))

-- graphql_translate_release(r, owner, repo)
id = encode_node_id("Release", owner .. "/" .. repo .. "/" .. tostring(r.id))

-- graphql_translate_label(l, owner, repo)
id = encode_node_id("Label", owner .. "/" .. repo .. "/" .. tostring(l.id))
```

Sub-resolvers already know owner/repo from the parent `Repository` object
(`parent.nameWithOwner:match("^([^/]+)/(.+)$")`), so passing it to the translator adds
no new fetch.  When a translator is called without context (e.g. from a path where
owner/repo is unavailable), it falls back to the integer ID alone and the `node()` resolver
for that type will return `null` if asked to look it up.

## `Query.node` implementation

`Query.node` is registered in `graphql_executor.lua`, not by individual backends:

```lua
graphql_resolvers["Query.node"] = function(parent, args, ctx)
  local node_id = args.id
  if not node_id then
    append_graphql_error(ctx, "node requires an id argument")
    return nil
  end
  local type_name, local_id = decode_node_id(node_id)
  if not type_name then
    append_graphql_error(ctx,
      "invalid node id: " .. tostring(node_id),
      nil)  -- no field_node location available here
    return nil
  end
  local resolver_key = "node." .. type_name
  local resolver = graphql_resolvers[resolver_key]
  if not resolver then
    -- Type not supported; return null (no error — the ID may be valid on a different server)
    return nil
  end
  local ok, result = pcall(resolver, local_id, ctx)
  if not ok then
    append_graphql_error(ctx, "internal error resolving node: " .. type_name)
    return nil
  end
  return result
end
```

### Not-found vs. invalid

| Situation | Response | Error? |
|-----------|----------|--------|
| Valid ID format, object not found on backend | `null` | No |
| Valid ID format, type not supported | `null` | No |
| Malformed ID (not valid base64 or wrong format) | `null` | Yes |
| Missing `id` argument | `null` | Yes |

The GraphQL spec permits `null` for an unknown node without requiring an error entry.
Clients use this to detect stale IDs (the object was deleted) and handle it gracefully.

## `Query.nodes` implementation

Also registered in `graphql_executor.lua`:

```lua
graphql_resolvers["Query.nodes"] = function(parent, args, ctx)
  local ids = args.ids
  if not ids or type(ids) ~= "table" then
    append_graphql_error(ctx, "nodes requires an ids argument")
    return {}
  end
  local results = {}
  for i, id in ipairs(ids) do
    local type_name, local_id = decode_node_id(id)
    if not type_name then
      results[i] = nil  -- null in JSON for malformed IDs
    else
      local resolver = graphql_resolvers["node." .. type_name]
      if resolver then
        local ok, result = pcall(resolver, local_id, ctx)
        results[i] = ok and result or nil
      else
        results[i] = nil
      end
    end
  end
  return results
end
```

Each ID is resolved independently.  A failure on one ID does not affect others.  The
returned array is parallel to `args.ids`: `results[i]` corresponds to `ids[i]`.  Null
entries are not errors (they represent not-found or unsupported types).

## Node resolver convention

Backend files register node resolvers with the key `"node.TypeName"`.  The signature
differs from field resolvers:

```lua
-- field resolver:  function(parent, args, ctx) → value
-- node resolver:   function(local_id, ctx) → value
```

The `local_id` is the string after `TypeName:` in the decoded node ID (e.g. `"octocat/hello-world"`
for a Repository node).

### Repository

```lua
graphql_resolvers["node.Repository"] = function(local_id, ctx)
  -- local_id = "owner/repo"
  local data, err = graphql_fetch(fetch_json, base() .. "/repos/" .. local_id)
  if not data then return nil end
  return graphql_translate_repo(translate_repo(data))
end
```

### User

```lua
graphql_resolvers["node.User"] = function(local_id, ctx)
  -- local_id = "login"
  local data, err = graphql_fetch(fetch_json, base() .. "/users/" .. local_id)
  if not data then return nil end
  return graphql_translate_user(translate_user(data))
end
```

### Organization

```lua
graphql_resolvers["node.Organization"] = function(local_id, ctx)
  local data, err = graphql_fetch(fetch_json, base() .. "/orgs/" .. local_id)
  if not data then return nil end
  return graphql_translate_org(data)
end
```

### Issue

```lua
graphql_resolvers["node.Issue"] = function(local_id, ctx)
  -- local_id = "owner/repo/number"
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then return nil end
  local data, err = graphql_fetch(
    fetch_json, base() .. "/repos/" .. owner .. "/" .. repo .. "/issues/" .. number)
  if not data then return nil end
  return graphql_translate_issue(translate_gitea_issue(data), owner, repo)
end
```

### PullRequest

```lua
graphql_resolvers["node.PullRequest"] = function(local_id, ctx)
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then return nil end
  local data, err = graphql_fetch(
    fetch_json, base() .. "/repos/" .. owner .. "/" .. repo .. "/pulls/" .. number)
  if not data then return nil end
  return graphql_translate_pr(translate_gitea_pull(data), owner, repo)
end
```

### IssueComment

```lua
graphql_resolvers["node.IssueComment"] = function(local_id, ctx)
  -- local_id = "owner/repo/comment_id"
  local owner, repo, cid = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then return nil end
  local data, err = graphql_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo .. "/issues/comments/" .. cid)
  if not data then return nil end
  return graphql_translate_comment(translate_gitea_issue_comment(data), owner, repo)
end
```

## `Query.repositoryOwner`

`repositoryOwner(login: String!)` is closely related to node resolution: it looks up a
User or Organization by login and returns a `RepositoryOwner` (an interface).  It does
not use node IDs but does require `__typename` discrimination:

```lua
graphql_resolvers["Query.repositoryOwner"] = function(parent, args, ctx)
  if not args.login then
    append_graphql_error(ctx, "repositoryOwner requires login")
    return nil
  end
  -- Try user first; fall back to org
  local data, err = graphql_fetch(fetch_json, base() .. "/users/" .. args.login)
  if data then
    return graphql_translate_user(translate_user(data))
  end
  local org_data, org_err = graphql_fetch(fetch_json, base() .. "/orgs/" .. args.login)
  if org_data then
    return graphql_translate_org(org_data)
  end
  return nil  -- neither found; no error (null is valid for not-found)
end
```

`graphql_translate_user` sets `__typename = "User"` and `graphql_translate_org` sets
`__typename = "Organization"`, so the executor resolves the `RepositoryOwner` interface
correctly when the client uses inline fragments.

## Phase 1 type coverage

Node resolvers registered in Phase 1:

| Resolver key | REST call | Notes |
|---|---|---|
| `node.Repository` | `GET /repos/{owner}/{repo}` | Local ID: `owner/repo` |
| `node.User` | `GET /users/{login}` | Local ID: `login` |
| `node.Organization` | `GET /orgs/{login}` | Local ID: `login` |
| `node.Issue` | `GET /repos/{o}/{r}/issues/{n}` | Local ID: `owner/repo/number` |
| `node.PullRequest` | `GET /repos/{o}/{r}/pulls/{n}` | Local ID: `owner/repo/number` |
| `node.IssueComment` | `GET /repos/{o}/{r}/issues/comments/{id}` | Local ID: `owner/repo/id` |
| `node.Release` | `GET /repos/{o}/{r}/releases/{id}` | Local ID: `owner/repo/id` |
| `node.Label` | `GET /repos/{o}/{r}/labels/{id}` | Local ID: `owner/repo/id` |

Types not supported in Phase 1 (node() returns null):

| Type | Reason |
|------|--------|
| `Commit` | SHA lookup requires branch context on some backends |
| `Ref` | Ref name lookup works but rarely requested via `node()` |
| `Milestone` | Low usage; Phase 2 |
| `Team` | Requires org context; Phase 2 |
| `ProjectV2` | Complex type; Phase 2 |
| All other types | Out of scope per [01-api-surface.md](01-api-surface.md) |

## Backend-specific considerations

### GitLab

GitLab uses URL-encoded `owner%2Frepo` paths for project lookup, which is what
`owner_repo_id(owner, repo)` produces.  The `node.Repository` resolver for GitLab uses the
owner/repo local ID directly:

```lua
-- backends/gitlab.lua
graphql_resolvers["node.Repository"] = function(local_id, ctx)
  local owner, repo = local_id:match("^([^/]+)/(.+)$")
  if not owner then return nil end
  local data, err = graphql_fetch(fetch_json,
    base() .. "/projects/" .. owner_repo_id(owner, repo))
  if not data then return nil end
  return graphql_translate_repo(translate_gl_repo(data))
end
```

### GitBucket

GitBucket mirrors the GitHub v3 REST API, so its node resolvers use the same paths as
Gitea but prefix with `/api/v3`:

```lua
graphql_resolvers["node.Repository"] = function(local_id, ctx)
  local data, err = graphql_fetch(fetch_json, base() .. "/api/v3/repos/" .. local_id)
  if not data then return nil end
  return graphql_translate_repo(data)  -- GitBucket response is already GitHub REST shape
end
```

### Backends without sub-resource ID lookup

Some backends (Pagure, Sourcehut, Radicle) do not expose issue or comment lookup by
integer ID.  Their `node.Issue` resolvers return `nil` immediately.  This is acceptable —
`node()` returns `null` for those IDs, and clients that cache node IDs from confusio's
responses on those backends will receive `null` when they try to look them up.

## Testing

Unit tests in `test/graphql-node-id.lua`:

- `encode_node_id("Repository", "octocat/hello-world")` → deterministic base64 string.
- `decode_node_id(encode_node_id("Issue", "octocat/hello-world/42"))` → `"Issue"`,
  `"octocat/hello-world/42"`.
- `decode_node_id("not-base64!!")` → `nil, nil`.
- `decode_node_id(EncodeBase64("NoColon"))` → `nil, nil` (no `:` separator).
- `Query.node` with a Repository ID: mock `node.Repository` resolver returns a fixed
  table; assert the result is correct.
- `Query.node` with a malformed ID: assert `data = null` and `errors` non-empty.
- `Query.node` with a valid-format but unsupported type: assert `data = null`, no error.
- `Query.nodes` with three IDs (one valid, one unsupported, one malformed): assert
  results array has correct values and only the malformed ID produces an error.
- `Query.repositoryOwner` with a user login: mock returns user; assert `__typename =
  "User"`.
- `Query.repositoryOwner` with an org login (user lookup fails, org succeeds): assert
  `__typename = "Organization"`.
- `Query.repositoryOwner` with an unknown login (both fail): assert `data = null`, no
  error.
- Issue node ID round-trip: `graphql_translate_issue(i, "octocat", "hello-world")` sets
  `id = encode_node_id("Issue", "octocat/hello-world/42")`; `decode_node_id` recovers the
  local ID; `node.Issue` resolver parses it and constructs the correct REST URL.
