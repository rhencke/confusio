# 11 — Mutation Handling and Write-Side Translation

## What this document covers

GraphQL mutations are write operations: they change server state and return the modified
object.  This document specifies how confusio executes mutation operations, how mutation
input types are translated into REST request bodies, how results are translated back to
GraphQL shapes, and which mutations are in scope for Phase 2.

## Phase placement

Per [01-api-surface.md](01-api-surface.md):

- **Phase 1** — queries and introspection only.  The executor rejects `mutation` operations
  with a request error.
- **Phase 2** — mutations for the categories listed below.

All design in this document is implemented in Phase 2.  Phase 1 executor code includes
only the rejection path.

## Phase 1 rejection

In `graphql_handler`, after `select_operation` identifies the operation kind:

```lua
if op.operation == "mutation" then
  respond_graphql(nil, {{
    message    = "mutations are not supported in this version",
    extensions = { code = "BAD_USER_INPUT" },
  }})
  return
end
```

Subscriptions are rejected the same way:

```lua
if op.operation == "subscription" then
  respond_graphql(nil, {{
    message    = "subscriptions are not supported",
    extensions = { code = "BAD_USER_INPUT" },
  }})
  return
end
```

## Mutation execution model

### Serial field execution

The GraphQL October 2021 spec requires that mutation root fields execute **serially**, in
document order.  (Query root fields execute in parallel in spec-compliant servers; confusio
executes both sequentially because Redbean is single-threaded — this is already compliant
for mutations.)

`execute_selection_set` already processes fields sequentially in order.  No change is
needed for the serial guarantee; the single-threaded model provides it for free.

### Result shape

Mutations return a result type just like queries.  The selection set on each mutation
field is walked by the same `execute_selection_set` / `complete_value` machinery used for
queries.  No new walking logic is needed.

### `clientMutationId` (Relay mutation pattern)

GitHub's mutations follow the Relay mutation specification: every mutation input type
includes an optional `clientMutationId: String` field, and the corresponding payload type
echoes it back:

```graphql
input CreateIssueInput {
  repositoryId: ID!
  title:        String!
  body:         String
  clientMutationId: String
}
type CreateIssuePayload {
  issue: Issue
  clientMutationId: String
}
```

Confusio must:

1. Extract `clientMutationId` from the input argument.
2. Pass it through to the payload result unchanged.
3. Never forward it to the upstream REST API.

Helper (defined in `graphql_executor.lua`, available to all mutation resolvers):

```lua
-- Extract clientMutationId from a mutation args.input table.
-- Returns the string value, or nil if absent.
local function get_client_mutation_id(args)
  return args and args.input and args.input.clientMutationId or nil
end
```

Mutation resolvers store it and include it in the returned payload:

```lua
graphql_resolvers["Mutation.createIssue"] = function(parent, args, ctx)
  local input = args and args.input
  if not input then
    return graphql_error(ctx, "createIssue requires an input argument", nil, "BAD_USER_INPUT")
  end
  local cmid = get_client_mutation_id(args)
  -- ... REST call ...
  return { issue = translated_issue, clientMutationId = cmid }
end
```

## Input type translation

### General pattern

Mutation input is always in `args.input` (GitHub's mutations all use a single `input`
argument of an Input Object type).  The resolver maps input fields to a REST request body:

```lua
local body = EncodeJson({
  title = input.title,
  body  = input.body,
  -- only include fields that are present (non-nil)
})
```

Lua's `EncodeJson` silently drops nil-valued keys, so fields the client did not supply
are naturally omitted from the REST body.  No explicit nil-guard is needed for optional
fields.

### ID decoding

Input fields typed `ID!` in the schema are node IDs (base64-encoded path segments, per
[08-node-id.md](08-node-id.md)).  Resolvers must decode them before constructing REST URLs:

```lua
local type_name, local_id = decode_node_id(input.repositoryId)
if type_name ~= "Repository" then
  return graphql_error(ctx, "invalid repositoryId", nil, "BAD_USER_INPUT")
end
local owner, repo = local_id:match("^([^/]+)/(.+)$")
```

A missing or mismatched type is a `BAD_USER_INPUT` error — the client sent a node ID that
does not decode to the expected type.

### Enum coercion

GraphQL enum values in input arrive as Lua strings (e.g. `"OPEN"`, `"CLOSED"`).  Most
Gitea-family REST APIs accept lowercase equivalents (`"open"`, `"closed"`).  Resolvers
apply a case-fold when needed:

```lua
local state = input.state and input.state:lower() or nil
```

For backends that use different enum vocabularies (GitLab uses `"opened"` instead of
`"open"`), per-backend mutation resolvers apply the mapping at the point of body
construction.

## Phase 2 mutation coverage

### Repository mutations

| GraphQL mutation | REST call | Input → body fields |
|---|---|---|
| `createRepository` | `POST /user/repos` or `POST /orgs/{org}/repos` | `name`, `description`, `private`, `auto_init` |
| `updateRepository` | `PATCH /repos/{owner}/{repo}` | `name`, `description`, `private`, `has_issues`, `has_wiki` |
| `deleteRepository` | `DELETE /repos/{owner}/{repo}` | (no body) |

`createRepository` input includes `ownerId: ID` (optional; if present and decodes to
`Organization`, uses the org route; otherwise uses the user route).

```lua
graphql_resolvers["Mutation.createRepository"] = function(parent, args, ctx)
  local input = args and args.input
  if not input or not input.name then
    return graphql_error(ctx, "createRepository requires input.name", nil, "BAD_USER_INPUT")
  end
  local cmid = get_client_mutation_id(args)
  local path
  if input.ownerId then
    local t, lid = decode_node_id(input.ownerId)
    if t == "Organization" then
      path = base() .. "/orgs/" .. lid .. "/repos"
    end
  end
  path = path or (base() .. "/user/repos")
  local body = EncodeJson({
    name        = input.name,
    description = input.description,
    private     = input.visibility == "PRIVATE",
    auto_init   = input.initializeWithReadme,
  })
  local data = graphql_fetch_or_error(fetch_json, path, ctx, nil, "POST", body)
  if not data then return nil end
  return {
    repository       = graphql_translate_repo(translate_repo(data)),
    clientMutationId = cmid,
  }
end
```

### Issue mutations

| GraphQL mutation | REST call | Key input fields |
|---|---|---|
| `createIssue` | `POST /repos/{o}/{r}/issues` | `repositoryId`, `title`, `body`, `labelIds`, `assigneeIds`, `milestoneId` |
| `updateIssue` | `PATCH /repos/{o}/{r}/issues/{n}` | `id` (issue node ID), `title`, `body`, `state` |
| `closeIssue` | `PATCH /repos/{o}/{r}/issues/{n}` with `state=closed` | `issueId` |
| `reopenIssue` | `PATCH /repos/{o}/{r}/issues/{n}` with `state=open` | `issueId` |

`labelIds` and `assigneeIds` are arrays of node IDs.  Resolvers decode each and extract
the label name or login respectively:

```lua
local labels = {}
for _, lid_encoded in ipairs(input.labelIds or {}) do
  local t, lid = decode_node_id(lid_encoded)
  if t == "Label" then
    -- Label local_id = "owner/repo/label_id"; name is not in the local_id
    -- Fall back: send the integer label id in the REST body (Gitea accepts it)
    local _, _, label_id = lid:match("^([^/]+)/([^/]+)/(.+)$")
    if label_id then labels[#labels + 1] = tonumber(label_id) end
  end
end
```

### Pull request mutations

| GraphQL mutation | REST call | Key input fields |
|---|---|---|
| `createPullRequest` | `POST /repos/{o}/{r}/pulls` | `repositoryId`, `title`, `body`, `headRefName`, `baseRefName` |
| `updatePullRequest` | `PATCH /repos/{o}/{r}/pulls/{n}` | `pullRequestId`, `title`, `body`, `baseRefName` |
| `closePullRequest` | `PATCH /repos/{o}/{r}/pulls/{n}` with `state=closed` | `pullRequestId` |
| `reopenPullRequest` | `PATCH /repos/{o}/{r}/pulls/{n}` with `state=open` | `pullRequestId` |
| `mergePullRequest` | `PUT /repos/{o}/{r}/pulls/{n}/merge` | `pullRequestId`, `mergeMethod`, `commitHeadline`, `commitBody` |

`mergeMethod` enum: `MERGE` → `"merge"`, `SQUASH` → `"squash"`, `REBASE` → `"rebase"`.

### Comment mutations

| GraphQL mutation | REST call | Key input fields |
|---|---|---|
| `addComment` | `POST /repos/{o}/{r}/issues/{n}/comments` | `subjectId` (issue or PR node ID), `body` |
| `updateIssueComment` | `PATCH /repos/{o}/{r}/issues/comments/{id}` | `id` (comment node ID), `body` |
| `deleteIssueComment` | `DELETE /repos/{o}/{r}/issues/comments/{id}` | `id` |
| `minimizeComment` | not supported in Phase 2 (no REST analog) | — |

`addComment.subjectId` may decode to `Issue` or `PullRequest`.  Both use the same REST
path (`/issues/{n}/comments`):

```lua
local t, lid = decode_node_id(input.subjectId)
local owner, repo, number
if t == "Issue" or t == "PullRequest" then
  owner, repo, number = lid:match("^([^/]+)/([^/]+)/(%d+)$")
end
if not owner then
  return graphql_error(ctx, "addComment requires a valid issue or PR id", nil, "BAD_USER_INPUT")
end
```

### Label mutations

| GraphQL mutation | REST call | Key input fields |
|---|---|---|
| `createLabel` | `POST /repos/{o}/{r}/labels` | `repositoryId`, `name`, `color`, `description` |
| `updateLabel` | `PATCH /repos/{o}/{r}/labels/{name}` | `id` (label node ID), `name`, `color`, `description` |
| `deleteLabel` | `DELETE /repos/{o}/{r}/labels/{name}` | `id` |
| `addLabelsToLabelable` | `PATCH /repos/{o}/{r}/issues/{n}` or `/pulls/{n}` | `labelableId`, `labelIds` |
| `removeLabelsFromLabelable` | `PATCH /repos/{o}/{r}/issues/{n}` or `/pulls/{n}` | `labelableId`, `labelIds` |

### Star mutations

| GraphQL mutation | REST call | Key input fields |
|---|---|---|
| `addStar` | `PUT /user/starred/{owner}/{repo}` | `starrableId` (repository node ID) |
| `removeStar` | `DELETE /user/starred/{owner}/{repo}` | `starrableId` |

### Watch mutations

| GraphQL mutation | REST call | Key input fields |
|---|---|---|
| `updateSubscription` | `PUT /repos/{o}/{r}/subscription` | `subscribableId`, `state` |

`state` enum: `SUBSCRIBED` → `{ subscribed = true, ignored = false }`,
`UNSUBSCRIBED` → `{ subscribed = false }`, `IGNORED` → `{ ignored = true }`.

## Mutation result translation

Mutation payload types are new GraphQL types (e.g. `CreateIssuePayload`) but their
content fields are the same object types already used in queries (`Issue`, `Repository`,
etc.).  The same `graphql_translate_*` functions used in query resolvers produce the
result objects.

No new translator functions are needed for mutations.  The resolver assembles the payload
table directly:

```lua
return {
  issue            = graphql_translate_issue(translate_gitea_issue(data), owner, repo),
  clientMutationId = cmid,
}
```

The executor's `complete_value` walks the payload selection set and plucks fields by name,
exactly as it does for any other object type.

## Error handling

Mutation errors follow the same model as query field errors (see [09-errors.md](09-errors.md)):

- Input validation failures (missing required field, bad node ID) → `BAD_USER_INPUT` +
  return `nil` from the resolver.
- Backend 4xx → `NOT_FOUND` / `FORBIDDEN` via `graphql_fetch_or_error`.
- Backend 5xx / network failure → `INTERNAL_ERROR`.
- Failed mutations return `null` for that mutation's payload field; other mutation fields
  in the same document continue executing (serial guarantee).

## Backend-specific mutation support

Not all backends implement all write endpoints.  When a mutation resolver calls
`graphql_fetch_or_error` and the backend returns 404 or 501, the field returns `null`
with a `NOT_FOUND` or `INTERNAL_ERROR` code.  Backends that completely lack a write
endpoint register a resolver that immediately records an error:

```lua
-- For backends that don't support repository deletion:
graphql_resolvers["Mutation.deleteRepository"] = function(parent, args, ctx)
  return graphql_error(ctx, "deleteRepository is not supported on this backend",
    nil, "BAD_USER_INPUT")
end
```

The per-backend feasibility matrix in [14-backend-feasibility.md](14-backend-feasibility.md)
documents which mutations each backend supports.

## Executor changes for Phase 2

Only one guard needs to be removed in `graphql_handler` when Phase 2 begins:

```lua
-- REMOVE this block in Phase 2:
if op.operation == "mutation" then
  respond_graphql(nil, {{
    message    = "mutations are not supported in this version",
    extensions = { code = "BAD_USER_INPUT" },
  }})
  return
end
```

Everything else (field execution, `complete_value`, `graphql_error`, `respond_graphql`)
already handles mutations without modification.

## Testing

Unit tests in `test/graphql-mutations.lua`:

- Phase 1 rejection: `graphql_handler` with `mutation { createIssue(...) { issue { id } } }`
  returns `{"data":null,"errors":[{"message":"mutations are not supported..."}]}`.
- `get_client_mutation_id({input={clientMutationId="abc"}})` → `"abc"`.
- `get_client_mutation_id({input={}})` → `nil`.
- `createRepository` resolver: mock `POST /user/repos` returning a repo object; assert
  payload has `repository.nameWithOwner` and `clientMutationId` echoed back.
- `createRepository` with `ownerId` decoding to `Organization`: assert path is
  `POST /orgs/{org}/repos`.
- `createIssue` with invalid `repositoryId`: assert `BAD_USER_INPUT` error, `nil` payload.
- `updateIssue` resolver: mock `PATCH /repos/{o}/{r}/issues/{n}` returning updated issue;
  assert translated `Issue` in payload.
- `closeIssue` resolver: assert body sent to REST is `{state="closed"}`.
- `addComment` with an Issue node ID: assert path is `/repos/{o}/{r}/issues/{n}/comments`.
- `addComment` with a PullRequest node ID: same path (issues endpoint handles PRs).
- `addComment` with an invalid `subjectId`: assert `BAD_USER_INPUT`.
- `mergePullRequest` with `mergeMethod = "SQUASH"`: assert body contains `merge_method = "squash"`.
- `addStar` resolver: assert `PUT /user/starred/{owner}/{repo}` called; payload has
  `starrable.nameWithOwner` and `viewerHasStarred = true`.
- Serial execution: two mutations in one document execute in order; second mutation
  proceeds even if first returns an error (no early exit).
- `clientMutationId` round-trip: send a random string in `input.clientMutationId`; assert
  the same string appears in the payload.
