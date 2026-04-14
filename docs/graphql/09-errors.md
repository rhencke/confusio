# 09 — Error Model, Partial Results, and GraphQL Error Envelope

## What this document covers

GraphQL error handling is more nuanced than REST: the HTTP status is almost always 200,
errors coexist with partial data in the same response, and where a null appears in the
result tree is determined by the schema's nullability constraints.  This document specifies
the response envelope format, error table structure, null propagation rules, path tracking,
the `graphql_error` helper, and `respond_graphql` — the single function that writes every
`POST /graphql` response.

## Response envelope

Every `POST /graphql` response is a JSON object with two fields:

```json
{
  "data":   { ... },
  "errors": [ { ... }, ... ]
}
```

The rules (from the [GraphQL October 2021 spec](https://spec.graphql.org/October2021/#sec-Errors)):

| Situation | `data` | `errors` |
|-----------|--------|----------|
| Execution completes with no errors | present (result object) | **omitted** |
| Field errors during execution | present (partial result) | present (one+ entries) |
| Request error before execution | `null` | present (one+ entries) |
| Validation error | `null` | present (one+ entries) |

`data` is **never omitted** — it is either a result object, `null`, or `false`.  `errors`
is omitted on success, never `null`.

### The `data: null` problem in Lua

`EncodeJson({data = nil})` silently drops the `data` key:

```lua
EncodeJson({data = nil, errors = {...}})  -- → {"errors":[...]}  ← WRONG
```

The `respond_graphql` function handles this by manual JSON construction when `data` is
absent:

```lua
-- internal/graphql_executor.lua
local function respond_graphql(data, errors)
  set_preamble(200)
  -- EncodeJson(nil) → "null"; use it explicitly when data is nil
  local data_json = (data ~= nil) and EncodeJson(data) or "null"
  if errors and #errors > 0 then
    Write('{"data":' .. data_json .. ',"errors":' .. EncodeJson(errors) .. '}')
  else
    Write('{"data":' .. data_json .. '}')
  end
end
```

All response paths in `graphql_handler` call `respond_graphql`.  No other code in the
GraphQL stack calls `respond_json` or `Write` directly.

## Error table format

Each entry in the `errors` array:

```lua
{
  message    = "Human-readable description.",           -- required
  locations  = { { line = N, column = N }, ... },       -- optional: query source position
  path       = { "fieldName", "subField", 0, ... },     -- optional: result path to failure
  extensions = { code = "MACHINE_CODE", ... },          -- optional: machine-readable extras
}
```

### `message`

A free-form string.  Confusio's conventions:

| Situation | Message prefix |
|-----------|---------------|
| Network failure | `"network error fetching /path"` |
| Upstream 404 | `"not found: /path"` |
| Upstream non-200 | `"upstream error 503 fetching /path"` |
| Missing required arg | `"fieldName requires an argumentName argument"` |
| Invalid argument value | `"invalid value for argument: argumentName"` |
| Parse failure | forwarded from `graphql_parse` (includes `"line:col: ..."`) |
| Validation failure | `"field 'name' does not exist on type 'TypeName'"` etc. |
| Resolver panic | `"internal error in resolver TypeName.fieldName"` |

### `locations`

The position in the query document of the field that failed.  The parser stores `line` and
`col` on every `NameNode` (see [02-lexer-parser.md](02-lexer-parser.md)); the executor
extracts them from `field_node.name.line` / `field_node.name.col` when building the error.

`locations` is omitted when:
- No `field_node` is available (e.g. parse errors reference the whole document).
- The error is a request-level error detected before any field is executed.

For parse errors the `message` itself contains `"line:col: ..."`, which gives source
location in the absence of a structured `locations` array.

### `path`

A JSON array tracing the path from the query root to the failing field, mirroring the
structure of the `data` response object.  String elements are field names; integer
elements (0-based) are list indices.

Example: `["repository", "issues", "nodes", 0, "author"]` means
`data.repository.issues.nodes[0].author` failed.

`path` is omitted when the error is not attached to a specific result field (e.g. parse
errors, missing `operationName`).

### `extensions`

Machine-readable metadata for programmatic clients.  Confusio Phase 1 populates only
`extensions.code`:

| Code | When emitted |
|------|-------------|
| `"PARSE_ERROR"` | Document has a syntax error |
| `"VALIDATION_ERROR"` | Schema validation check failed |
| `"NOT_FOUND"` | Resolver received a 404 from the backend |
| `"FORBIDDEN"` | Resolver received a 401 or 403 from the backend |
| `"RATE_LIMITED"` | Resolver received a 429 from the backend |
| `"BAD_USER_INPUT"` | Required argument missing; invalid argument value |
| `"INTERNAL_ERROR"` | Uncaught Lua error inside a resolver (`pcall` boundary) |

`extensions` is omitted when there is no applicable code (e.g. simple "not found" cases
that are expressed as null rather than as an error).

## Error categories and their `data` behaviour

### Request errors (data = null)

Errors detected before execution begins.  `data` is `null`.

| Situation | Triggered by |
|-----------|-------------|
| Malformed JSON body | `DecodeJson` returns nil |
| Missing `query` field in body | `req.query` is not a string |
| Parse failure | `graphql_parse` returns `nil, errmsg` |
| Invalid `operationName` (not found in document) | `select_operation` fails |
| Ambiguous document (multiple operations, no `operationName`) | `select_operation` fails |
| Backward pagination requested (`last`/`before`) | counted as request error in Phase 1 |

```lua
-- Example: parse failure
local doc, parse_err = graphql_parse(source)
if not doc then
  respond_graphql(nil, {{
    message    = parse_err,
    extensions = { code = "PARSE_ERROR" },
  }})
  return
end
```

### Validation errors (data = null)

Detected after parsing, before any resolver runs.  `data` is `null`.

```lua
local verrs = graphql_validate(doc, op)
if #verrs > 0 then
  respond_graphql(nil, verrs)
  return
end
```

`graphql_validate` returns error tables already in the correct format (with `message`,
`locations`, and `extensions.code = "VALIDATION_ERROR"`).

### Field errors (data = partial result)

Detected during execution.  `data` is present with the fields that succeeded; failing
fields are `null`.  Errors are accumulated in `ctx.errors`.

At the end of `graphql_handler`:

```lua
respond_graphql(data, ctx.errors)
-- If #ctx.errors == 0, respond_graphql omits "errors" key.
-- If #ctx.errors > 0, both "data" and "errors" are present.
```

### HTTP status codes

| HTTP status | When |
|-------------|------|
| `200 OK` | All well-formed requests — success, field errors, validation errors, parse errors |
| `400 Bad Request` | Only when the request body is not valid JSON at all (not a GraphQL-level error) |

Confusio never returns 401, 403, 404, or 500 from the `/graphql` endpoint itself.
Authentication failures and backend 4xx/5xx responses are expressed as errors in the
`errors` array with `extensions.code` set to `"FORBIDDEN"`, `"NOT_FOUND"`, etc.

## `graphql_error` helper

The single function for recording errors during execution.  Returns `nil` so callers
can write `return graphql_error(ctx, ...)`:

```lua
-- internal/graphql_executor.lua
function graphql_error(ctx, message, field_node, code)
  local err = { message = message }

  -- Location: from the field node's name token
  if field_node and field_node.name and field_node.name.line then
    err.locations = { { line = field_node.name.line, column = field_node.name.col } }
  end

  -- Path: snapshot of the current execution path
  if ctx.path and #ctx.path > 0 then
    err.path = {}
    for i, segment in ipairs(ctx.path) do
      err.path[i] = segment
    end
  end

  -- Extensions
  if code then
    err.extensions = { code = code }
  end

  ctx.errors[#ctx.errors + 1] = err
  return nil
end
```

Usage:

```lua
-- In a resolver:
local data, err = graphql_fetch(fetch_json, url)
if not data then
  return graphql_error(ctx, err, field_node, "NOT_FOUND")
end
```

The `field_node` parameter is the `FieldNode` currently being executed; it is available
in `execute_field` as the first argument.  Resolvers do not have it directly; they receive
it via the execution context or omit it (accepting a nil `locations`).

For convenience, a version without `field_node` is also valid:

```lua
return graphql_error(ctx, "operation not supported", nil, "BAD_USER_INPUT")
```

## Path tracking

The executor maintains `ctx.path` as a mutable array, pushing segments on descent and
popping on return.

### In `execute_selection_set`

```lua
for response_key, field_nodes in ordered_fields(fields) do
  ctx.path[#ctx.path + 1] = response_key          -- push field name

  local value = execute_field(field_nodes[1], type_name, parent, ctx)
  local field_def = graphql_schema_field(type_name, field_nodes[1].name.value)
  result[response_key] = complete_value(
    value, field_def and field_def.type or "String",
    field_nodes[1], type_name, ctx)

  ctx.path[#ctx.path] = nil                        -- pop
end
```

### In `complete_value` for lists

```lua
if is_list(type_ref) then
  local result = {}
  for i, item in ipairs(value) do
    ctx.path[#ctx.path + 1] = i - 1               -- 0-based index per spec
    result[i] = complete_value(item, unwrap_list(type_ref), field_node, type_name, ctx)
    ctx.path[#ctx.path] = nil
  end
  return result
end
```

`graphql_error` snapshots `ctx.path` at the moment of the call, so each error records
the precise field path independently.

## Null propagation

When `complete_value` encounters a `NON_NULL` type whose value is `nil`, it must propagate
the null upward to the nearest nullable ancestor.  This is implemented by having
`complete_value` return a special sentinel, `GRAPHQL_NULL_PROPAGATION`, that the parent
`complete_value` or `execute_selection_set` recognises:

```lua
-- internal/graphql_executor.lua
local PROPAGATE = {}   -- unique sentinel table; identity comparison only

local function complete_value(value, type_ref, field_node, type_name, ctx)
  if graphql_schema_is_nonnull(type_ref) then
    local inner = complete_value(value, unwrap_nonnull(type_ref), field_node, type_name, ctx)
    if inner == nil or inner == PROPAGATE then
      -- Non-null contract violated; propagate upward
      graphql_error(ctx,
        "non-null field resolved to null: " .. (field_node and field_node.name.value or "?"),
        field_node)
      return PROPAGATE
    end
    return inner
  end

  -- Nullable: stop propagation here
  if value == PROPAGATE then return nil end
  if value == nil       then return nil end
  -- ... rest of complete_value ...
end
```

And in `execute_selection_set`:

```lua
local raw = complete_value(value, field_type, field_node, type_name, ctx)
result[response_key] = (raw == PROPAGATE) and nil or raw
```

If propagation reaches the root (the outermost `execute_selection_set`), `data` contains
`null` entries where the propagation stopped at nullable ancestors.  If every root field
is non-null and they all propagate, `data` becomes an empty object `{}` — not `null`.
(A fully-null root is unusual; the GraphQL spec does allow `data: null` for root-level
non-null violations, but confusio emits `{}` for simplicity in Phase 1.)

## Upstream error mapping

`graphql_fetch` (defined in `graphql_translators.lua`) maps HTTP status codes to error
messages.  Resolvers use the returned error string and a code derived from the status:

```lua
-- graphql_fetch returns: decoded, nil  OR  nil, "error message"
-- Callers map the message to a code:

local data, fetch_err = graphql_fetch(fetch_json, url)
if not data then
  local code = "INTERNAL_ERROR"
  if fetch_err:find("not found") then   code = "NOT_FOUND"
  elseif fetch_err:find("403")    then  code = "FORBIDDEN"
  elseif fetch_err:find("401")    then  code = "FORBIDDEN"
  elseif fetch_err:find("429")    then  code = "RATE_LIMITED"
  end
  return graphql_error(ctx, fetch_err, field_node, code)
end
```

This is repetitive if written in every resolver.  A helper `graphql_fetch_or_error`
can encapsulate it:

```lua
-- internal/graphql_translators.lua
-- Like graphql_fetch but appends to ctx.errors on failure and returns nil.
-- field_node is the current FieldNode (for location tracking), or nil.
function graphql_fetch_or_error(fetch_json, path, ctx, field_node, method, body)
  local data, err = graphql_fetch(fetch_json, path, method, body)
  if not data then
    local code = "INTERNAL_ERROR"
    if err:find("not found")       then code = "NOT_FOUND"
    elseif err:find("40[13]")      then code = "FORBIDDEN"
    elseif err:find("429")         then code = "RATE_LIMITED"
    elseif err:find("network")     then code = "INTERNAL_ERROR"
    end
    graphql_error(ctx, err, field_node, code)
    return nil
  end
  return data
end
```

Resolver usage collapses to:

```lua
local data = graphql_fetch_or_error(fetch_json, url, ctx, field_node)
if not data then return nil end
```

## Validation error format

`graphql_validate` returns an array of error tables directly, pre-formatted for the
response.  Each entry has `message`, optional `locations`, and
`extensions.code = "VALIDATION_ERROR"`:

```lua
-- Example validation error
{
  message    = "field 'foobar' does not exist on type 'Repository'",
  locations  = { { line = 3, column = 5 } },
  extensions = { code = "VALIDATION_ERROR" },
}
```

The validator uses `graphql_validate_error(message, name_node)` — a simpler variant of
`graphql_error` that does not need a `ctx` (since validation runs before `ctx` exists):

```lua
local function graphql_validate_error(message, name_node)
  local err = {
    message    = message,
    extensions = { code = "VALIDATION_ERROR" },
  }
  if name_node and name_node.line then
    err.locations = { { line = name_node.line, column = name_node.col } }
  end
  return err
end
```

## Testing

Unit tests in `test/graphql-errors.lua`:

- `respond_graphql(nil, errors)` writes `{"data":null,"errors":[...]}` — verifies
  manual null construction.
- `respond_graphql({viewer={login="x"}}, {})` writes `{"data":{"viewer":{"login":"x"}}}`
  — no `"errors"` key.
- `respond_graphql({viewer=nil}, errors)` writes `{"data":{"viewer":null},"errors":[...]}`.
- `graphql_error(ctx, "msg", nil, "NOT_FOUND")` appends one entry with `code="NOT_FOUND"`,
  no `locations`, no `path`.
- `graphql_error(ctx, "msg", field_node_with_line)` includes `locations`.
- Path tracking: after pushing `"repository"` and `"name"` onto `ctx.path`,
  `graphql_error` records `path = ["repository", "name"]`.
- Path tracking for list index: after pushing `"nodes"` and `0`,
  `graphql_error` records `path = ["nodes", 0]`.
- Non-null propagation: `complete_value(nil, "String!", ...)` returns `PROPAGATE` and
  appends one error.
- Non-null propagation stops at nullable: a `String!` inside a nullable `Repository`
  propagates to `null` at the `Repository` level.
- Full request error flow: `graphql_handler` with a malformed query body returns
  `{"data":null,"errors":[{"message":"...","extensions":{"code":"PARSE_ERROR"}}]}`.
- Validation error flow: a query for a non-existent field returns `{"data":null,
  "errors":[{"message":"field 'foo' does not exist...","extensions":{"code":
  "VALIDATION_ERROR"}}]}`.
- `graphql_fetch_or_error` on a 404 path appends `code="NOT_FOUND"` to ctx.errors and
  returns nil.
