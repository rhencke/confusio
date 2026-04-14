# 04 — Query Executor, Resolver Dispatch, and Selection Walking

## What this document covers

The executor is the heart of GraphQL support: it receives a parsed, validated document,
walks the selection set, calls resolvers, and assembles the `{"data": ..., "errors": [...]}`
response.  This document specifies the executor's structure, the resolver dispatch model,
the selection-walking algorithm, and the interface backends use to register resolvers.

## Module

```
internal/graphql_executor.lua
```

Globals exported:

```lua
graphql_resolvers  -- table: populated at load time by backend files
graphql_handler()  -- HTTP handler function: called by dispatch for POST /graphql
```

`graphql_resolvers` is initialised to `{}` by `graphql_executor.lua`.  Backend files
populate it at load time alongside `backend_impl`.  The executor reads it on every request.

## Catalog registration

A single catalog entry registers the route:

```lua
-- internal/catalog.lua, inside endpoint_sections
{
  "graphql",
  {
    { "POST /graphql", "graphql_request", defaults.graphql_stub },
  },
},
```

`defaults.graphql_stub` is a fallback used when no backend is loaded (returns
`{"data":null,"errors":[{"message":"No backend configured."}]}`).  Once a backend
populates `graphql_resolvers`, the catalog's default is bypassed by the normal
`backend_impl.graphql_request` lookup — except that there is no `backend_impl.graphql_request`
at all.  Instead, `graphql_handler` is registered as the permanent fixed handler in the
catalog's default slot and is always used:

```lua
{ "POST /graphql", "graphql_request", graphql_handler },
```

`graphql_handler` is defined in `graphql_executor.lua` and referenced here after
`graphql_executor.lua` is loaded.  Backends do **not** override `graphql_request` in
`backend_impl`; they only populate `graphql_resolvers`.

## Request lifecycle

```
POST /graphql
  → OnHttpRequest (dispatch.lua)
    → graphql_handler()
        1. Read and JSON-decode request body
        2. Parse document string with graphql_parse()
        3. Select operation by operationName
        4. Validate (field existence, leaf/composite checks)
        5. Execute: walk selection set, call resolvers
        6. Write {"data": ..., "errors": [...]} response
```

### Step 1 — decode request body

```lua
local raw = GetBody() or ""
local req = DecodeJson(raw)
if not req or type(req.query) ~= "string" then
  respond_json(200, { data = nil,
    errors = {{ message = "POST /graphql requires a JSON body with a 'query' field" }} })
  return
end
local source       = req.query
local variables    = type(req.variables) == "table" and req.variables or {}
local op_name      = type(req.operationName) == "string" and req.operationName or nil
```

Note: GraphQL always responds with HTTP 200, even for errors, as long as the request was
well-formed at the HTTP level.  A completely unparseable request body may return 400, but
all GraphQL-level errors use 200 with an `errors` field.

### Step 2 — parse

```lua
local doc, parse_err = graphql_parse(source)
if not doc then
  respond_json(200, { data = nil,
    errors = {{ message = parse_err }} })
  return
end
```

### Step 3 — select operation

```lua
local op, sel_err = select_operation(doc, op_name)
if not op then
  respond_json(200, { data = nil, errors = {{ message = sel_err }} })
  return
end
```

Rules:
- If `op_name` is non-nil: find the operation whose `name.value == op_name`; error if not
  found.
- If `op_name` is nil and the document has exactly one operation: use it.
- If `op_name` is nil and the document has more than one operation: error (the spec
  requires `operationName` when multiple operations are present).

### Step 4 — validate

```lua
local verrs = graphql_validate(doc, op)
if #verrs > 0 then
  respond_json(200, { data = nil, errors = verrs })
  return
end
```

`graphql_validate` performs the Phase 1 checks from [03-schema.md](03-schema.md) and
returns an array of error tables (empty on success).  Validation errors short-circuit
execution entirely.

### Step 5 — execute

```lua
local ctx = {
  doc       = doc,
  variables = variables,
  errors    = {},
}
local data = execute_operation(op, ctx)
```

### Step 6 — write response

```lua
local resp = { data = data }
if #ctx.errors > 0 then
  resp.errors = ctx.errors
end
respond_json(200, resp)
```

## Execution model

### Two-tier resolver model

Not every field requires a REST call.  Most fields are simply extracted from a table
returned by a higher-level resolver.  The executor operates in two tiers:

**Tier 1 — registered resolvers** make REST calls and return Lua tables:

```lua
graphql_resolvers["Query.repository"] = function(parent, args, ctx)
  -- calls GET /repos/{owner}/{name}
  -- returns translated repo table or nil+error
end

graphql_resolvers["Repository.issues"] = function(parent, args, ctx)
  -- parent is the repo table; parent.owner.login and parent.name are available
  -- calls GET /repos/{owner}/{name}/issues?...
  -- returns { nodes = {...}, total_count = N, page_info = {...} }
end
```

**Tier 2 — field pluck** reads a key from the parent table directly:

```lua
-- For repository.name, repository.description, issue.title, etc.
-- No resolver registration needed; the executor does: parent_value[field_name]
```

The executor always tries the registered resolver first; if none exists, it falls back to
field pluck.

### Context object

```lua
ctx = {
  doc       = doc,        -- full DocumentNode (for fragment lookup in collect_fields)
  variables = variables,  -- raw JSON-decoded table from request body
  errors    = {},         -- array; resolvers append error tables here on failure
}
```

Resolvers must not raise Lua errors; they must return `nil` and append to `ctx.errors`.
The executor wraps each resolver call in `pcall` as a safety net and converts uncaught
errors to `ctx.errors` entries with `"internal error"` messages.

## Selection-walking algorithm

### `execute_operation(op, ctx)`

```
root_type = op.operation == "query"    and schema_data.query_type
         or op.operation == "mutation" and schema_data.mutation_type

data = execute_selection_set(op.selection_set, root_type, nil, ctx)
return data
```

### `execute_selection_set(sel_set, type_name, parent, ctx)`

```
fields = collect_fields(sel_set, type_name, ctx)
result = {}
for response_key, field_nodes in ordered(fields) do
  value = execute_field(field_nodes[1], type_name, parent, ctx)
  field_def = graphql_schema_field(type_name, field_nodes[1].name.value)
  result[response_key] = complete_value(value, field_def and field_def.type or "String",
                                        field_nodes[1], type_name, ctx)
end
return result
```

### `collect_fields(sel_set, type_name, ctx, visited?)`

Produces an **ordered** map from response key to list of `FieldNode`s, processing
selections left to right.  Ordering matters: the response object must preserve the
field order from the query.

Lua tables are unordered by default; use a parallel array of keys:

```lua
local field_map  = {}   -- response_key → { FieldNode, ... }
local field_order = {}  -- insertion-order list of response keys

local function add_field(response_key, field_node)
  if not field_map[response_key] then
    field_order[#field_order + 1] = response_key
    field_map[response_key] = {}
  end
  field_map[response_key][#field_map[response_key] + 1] = field_node
end
```

For each selection:

1. **Check `@skip` / `@include`** (see [06-fragments-vars-directives.md](06-fragments-vars-directives.md)):
   - If `@skip(if: true)` or `@include(if: false)`: skip entirely.
2. **`Field`**: `response_key = alias?.value or name.value`; call `add_field`.
3. **`InlineFragment`**:
   - If there is a `type_condition` and it does not apply to `type_name`: skip.
   - Otherwise recurse: `collect_fields(inline.selection_set, type_name, ctx, visited)`.
4. **`FragmentSpread`**:
   - If the fragment name is in `visited`: skip (cycle guard).
   - Look up the fragment in `ctx.doc.definitions` by name.
   - If the fragment's `type_condition` does not apply: skip.
   - Recurse into the fragment's `selection_set`, adding the fragment name to `visited`.

**Type condition applicability** (`does_type_apply(condition_type, current_type)`):
- If `condition_type == current_type`: yes.
- If the schema type at `current_type` implements the interface `condition_type`: yes.
- If `condition_type` is a union and `current_type` is one of its `possible_types`: yes.
- Otherwise: no.

### `execute_field(field_node, type_name, parent, ctx)`

```
field_name = field_node.name.value

-- Meta-fields handled directly
if field_name == "__typename" then
  return type_name
end
if type_name == schema_data.query_type and field_name == "__schema" then
  return graphql_introspect_schema()
end
if type_name == schema_data.query_type and field_name == "__type" then
  local name_arg = coerce_arg(field_node, "name", ctx)
  return graphql_introspect_type(name_arg)
end

args = coerce_argument_values(field_node.arguments, ctx)

resolver_key = type_name .. "." .. field_name
if graphql_resolvers[resolver_key] then
  ok, result = pcall(graphql_resolvers[resolver_key], parent, args, ctx)
  if not ok then
    append_error(ctx, "internal error in resolver " .. resolver_key, field_node)
    return nil
  end
  return result
end

-- Field pluck fallback
if parent ~= nil then
  return parent[field_name]
end

return nil
```

### `complete_value(value, type_ref, field_node, type_name, ctx)`

Handles the recursive completion of a resolved value, including null propagation:

```
if is_nonnull(type_ref) then
  inner = complete_value(value, unwrap_nonnull(type_ref), field_node, type_name, ctx)
  if inner == nil then
    -- non-null violation: append error and return nil (caller must propagate)
    append_error(ctx, "non-null field returned null: " .. response_key_of(field_node), field_node)
  end
  return inner
end

if value == nil then return nil end

if is_list(type_ref) then
  if type(value) ~= "table" then
    append_error(ctx, "expected list, got scalar", field_node)
    return nil
  end
  local result = {}
  for i, item in ipairs(value) do
    result[i] = complete_value(item, unwrap_list(type_ref), field_node, type_name, ctx)
  end
  return result
end

if graphql_schema_is_leaf(type_ref) then
  return value  -- scalar or enum; use as-is
end

-- Object / interface / union
local concrete_type = resolve_concrete_type(type_ref, value)
if not concrete_type then
  append_error(ctx, "cannot determine concrete type for " .. type_ref, field_node)
  return nil
end
if field_node.selection_set == nil then
  append_error(ctx, "composite field requires sub-selection", field_node)
  return nil
end
return execute_selection_set(field_node.selection_set, concrete_type, value, ctx)
```

### `resolve_concrete_type(type_ref, value)`

Determines the Lua type name to use for recursion when the schema type is an interface or
union:

1. If `value.__typename` is a non-nil string: return it.
2. If the schema type at `base_type(type_ref)` has `kind == "OBJECT"`: return
   `base_type(type_ref)` directly (no ambiguity).
3. Otherwise: return `nil` (error path in `complete_value`).

Resolvers are responsible for setting `__typename` on values returned for interface and
union fields.  For object fields there is no ambiguity and `__typename` is optional.

## Resolver interface

### Registration key

Resolvers are registered with string keys of the form `"TypeName.fieldName"`:

```lua
graphql_resolvers["Query.viewer"]           = fn  -- root query field
graphql_resolvers["Query.repository"]       = fn  -- root query field
graphql_resolvers["Repository.issues"]      = fn  -- sub-resolver (needs extra REST call)
graphql_resolvers["Repository.pullRequests"]= fn  -- sub-resolver
graphql_resolvers["User.repositories"]      = fn  -- sub-resolver
```

### Resolver signature

```lua
-- parent  : the parent object table (nil for root Query/Mutation fields)
-- args    : table of coerced argument values, keyed by argument name
-- ctx     : context table { doc, variables, errors }
-- returns : resolved value (table, string, number, boolean) or nil
function resolver(parent, args, ctx)
  ...
end
```

Resolvers must:
- Return `nil` and append to `ctx.errors` on failure (never raise a Lua error).
- Set `__typename` on returned tables when the field's schema type is abstract
  (interface or union).
- Return Connection-shaped tables for paginated fields (see
  [07-pagination.md](07-pagination.md)).

### Standard Connection return shape

For any field that maps to a Relay Connection:

```lua
return {
  __typename  = "IssueConnection",   -- required: concrete type name
  total_count = N,
  page_info   = {
    __typename       = "PageInfo",
    has_next_page    = true | false,
    has_previous_page= false,
    start_cursor     = "...",
    end_cursor       = "...",
  },
  nodes = { item1, item2, ... },     -- translated objects
  edges = {                           -- optional; same objects wrapped in Edge nodes
    { __typename = "IssueEdge", cursor = "...", node = item1 },
    ...
  },
}
```

The executor plucks `nodes`, `edges`, `page_info`, and `total_count` via field pluck
(Tier 2) — no sub-resolver is needed for these structural Connection fields.

## Variable handling in Phase 1

Full variable coercion (validating variable types against their `VariableDefinition` types)
is deferred to Phase 2.  In Phase 1, variables are used as follows:

- `ctx.variables` holds the raw JSON-decoded table from the request.
- `coerce_argument_values` substitutes `Variable` nodes with the corresponding value from
  `ctx.variables`.  If a variable is missing, the argument is `nil`.
- Argument values of all other kinds (`IntValue`, `StringValue`, `BooleanValue`, etc.) are
  converted to their Lua equivalents:

| Value node kind | Lua value |
|-----------------|-----------|
| `IntValue`      | `tonumber(node.value)` |
| `FloatValue`    | `tonumber(node.value)` |
| `StringValue`   | `node.value` (already decoded by the lexer) |
| `BooleanValue`  | `node.value` (already a Lua boolean) |
| `NullValue`     | `nil` |
| `EnumValue`     | `node.value` (string) |
| `ListValue`     | recursively coerce each element → Lua table (ipairs) |
| `ObjectValue`   | recursively coerce each field → Lua table (string keys) |
| `Variable`      | `ctx.variables[node.name.value]` |

## Load order

```lua
-- .init.lua (addition)
dofile("/zip/internal/graphql_parser.lua")
dofile("/zip/internal/graphql_schema_data.lua")
dofile("/zip/internal/graphql_schema.lua")
dofile("/zip/internal/graphql_executor.lua")   -- initialises graphql_resolvers = {}
dofile("/zip/internal/families.lua")
-- backend loaded here (appends to graphql_resolvers and backend_impl)
dofile("/zip/internal/defaults.lua")           -- references graphql_handler for catalog
dofile("/zip/internal/router.lua")
dofile("/zip/internal/catalog.lua")            -- registers POST /graphql
dofile("/zip/internal/dispatch.lua")
```

## Error table format

Each entry in `ctx.errors` and the top-level `errors` array:

```lua
{
  message   = "human-readable description",
  locations = { { line = N, column = N }, ... },  -- from field_node position; omit if unavailable
  path      = { "fieldName", "subField", 0, ... }, -- nil if not yet walking a field
}
```

`locations` and `path` are optional per spec; confusio populates them when the position
is available from the AST node.  The parser stores `line`/`col` on every token (and thus
on every AST node's `name` token); the executor passes the relevant `field_node` to
`append_error` so the location can be extracted.

See [09-errors.md](09-errors.md) for the full error model including HTTP-level error cases.

## Testing

Unit tests in `test/graphql-executor.lua`:

- **Empty resolvers**: a query with no registered resolvers for its fields returns
  `{"data": {"viewer": null}, "errors": [...]}` (null from field pluck against nil parent).
- **Root resolver + field pluck**: register `Query.viewer` returning a fixed table; assert
  the selection set is plucked correctly.
- **Sub-resolver**: register `Query.repository` and `Repository.issues`; assert both are
  called in order and the connection shape is correctly assembled.
- **`__typename`**: assert the executor returns the type name string without calling any
  resolver.
- **`__schema`**: assert the executor calls `graphql_introspect_schema()` and returns its
  result.
- **Fragment spread**: a query using a named fragment is collected and executed correctly.
- **`@skip(if: true)`**: a skipped field does not appear in the response.
- **Variable substitution**: a variable in an argument position is resolved from
  `ctx.variables`.
- **Resolver error**: a resolver that appends to `ctx.errors` and returns `nil` produces
  `null` for that field and a non-empty `errors` array.
- **Non-null propagation**: a `NON_NULL` field returning `nil` propagates null upward to
  its nearest nullable ancestor.
- **Multiple operations + operationName**: correct operation is selected.
- **Ambiguous document (no operationName, two operations)**: error returned.
