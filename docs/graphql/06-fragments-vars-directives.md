# 06 — Fragment, Variable, Directive, and Introspection Handling

## What this document covers

The executor overview in [04-executor.md](04-executor.md) sketches `collect_fields` and
`coerce_argument_values` at a high level.  This document specifies the full behaviour of
each feature: how fragments are collected and type-checked, how variables are scoped and
substituted, how `@skip`/`@include` are evaluated, and how the three introspection
meta-fields (`__typename`, `__schema`, `__type`) are answered.

## Fragments

### Named fragment definitions

Fragment definitions appear as `FragmentDefinition` nodes in `ctx.doc.definitions`.  They
are not executed eagerly; the executor looks them up by name when a `FragmentSpread` is
encountered during `collect_fields`.

```lua
-- Helper: find a named fragment in the document
local function find_fragment(ctx, name)
  for _, def in ipairs(ctx.doc.definitions) do
    if def.kind == "FragmentDefinition" and def.name.value == name then
      return def
    end
  end
  return nil
end
```

Fragments are scoped to the document, not to an operation.  A document with two operations
can share fragments across both.

### Type condition evaluation

Every fragment (named or inline) carries a `type_condition` identifying the concrete type
or interface the fragment applies to.  Before merging a fragment's fields into the grouped
result, `collect_fields` calls `does_type_apply`:

```lua
-- Does the fragment's type condition apply to the currently-executing type?
local function does_type_apply(condition_name, current_type)
  if condition_name == current_type then
    return true
  end
  local t = graphql_schema_type(current_type)
  if not t then
    return false
  end
  -- Interface: current type implements the condition interface
  if t.kind == "OBJECT" or t.kind == "INTERFACE" then
    for _, iface in ipairs(t.interfaces or {}) do
      if iface == condition_name then return true end
    end
  end
  -- Union: condition is a union and current type is one of its possible types
  local cond = graphql_schema_type(condition_name)
  if cond and cond.kind == "UNION" then
    for _, pt in ipairs(cond.possible_types or {}) do
      if pt == current_type then return true end
    end
  end
  return false
end
```

An inline fragment with no `type_condition` (permitted by the spec) always applies.

### Cycle guard

`collect_fields` receives a `visited` set (a table used as a hash set) to prevent
infinite recursion if a fragment spreads itself:

```lua
-- collect_fields signature:
-- sel_set       SelectionSetNode
-- type_name     string (current GraphQL type)
-- ctx           context table
-- visited       table { [fragment_name] = true } (shared across the recursion)

local visited = visited or {}
-- ...
-- FragmentSpread case:
local fname = selection.name.value
if visited[fname] then
  -- already visited; skip to prevent cycle
else
  visited[fname] = true
  local frag = find_fragment(ctx, fname)
  if frag and does_type_apply(frag.type_condition.name.value, type_name) then
    collect_fields(frag.selection_set, type_name, ctx, visited)
  end
end
```

The spec requires a static cycle-detection validation pass; confusio's Phase 1 runtime
guard is equivalent for well-formed real-world documents.

### Fragment variable scoping

Fragment arguments (a 2023 draft feature) are **not supported** in Phase 1.  If a client
sends a fragment with argument declarations, the lexer and parser accept the syntax but the
executor ignores the argument declarations; variable values always come from the top-level
`ctx.variables` table.  This is consistent with how GitHub's own server behaves for the
clients confusio targets.

## Variables

### Variable definition scope

Variable definitions belong to an operation, not a fragment.  After selecting the operation
in `graphql_handler`, the executor builds a lookup table of definitions:

```lua
-- After select_operation, before execute_operation:
ctx.variable_defs = {}
for _, vd in ipairs(op.variable_definitions) do
  ctx.variable_defs[vd.variable.name.value] = vd
end
```

`ctx.variable_defs` maps variable name strings to `VariableDefinitionNode` tables (which
carry the type, the default value, and the source location).

### Variable resolution in `coerce_value`

Every argument value in the document is a `ValueNode` of one of the kinds defined in
[02-lexer-parser.md](02-lexer-parser.md).  The single function `coerce_value(node, ctx)`
converts any `ValueNode` to a plain Lua value:

```lua
local function coerce_value(node, ctx)
  local k = node.kind
  if k == "Variable" then
    local name = node.name.value
    local val  = ctx.variables[name]
    if val == nil then
      -- Fall back to the VariableDefinition's default value, if any
      local vd = ctx.variable_defs and ctx.variable_defs[name]
      if vd and vd.default_value then
        return coerce_value(vd.default_value, ctx)
      end
    end
    return val  -- nil if missing and no default (caller handles nil)

  elseif k == "IntValue"     then return tonumber(node.value)
  elseif k == "FloatValue"   then return tonumber(node.value)
  elseif k == "StringValue"  then return node.value
  elseif k == "BooleanValue" then return node.value
  elseif k == "NullValue"    then return nil
  elseif k == "EnumValue"    then return node.value

  elseif k == "ListValue" then
    local result = {}
    for i, item in ipairs(node.values) do
      result[i] = coerce_value(item, ctx)
    end
    return result

  elseif k == "ObjectValue" then
    local result = {}
    for _, f in ipairs(node.fields) do
      result[f.name.value] = coerce_value(f.value, ctx)
    end
    return result
  end
  return nil
end
```

`coerce_value` is the single authoritative place where `Variable` nodes are resolved.
It is called from `coerce_argument_values` (for field arguments), from directive
evaluation (for `@skip`/`@include` arguments), and from default-value evaluation in
`VariableDefinition`.

### `coerce_argument_values(field_node, ctx)`

Produces a table of argument values keyed by argument name:

```lua
local function coerce_argument_values(field_node, ctx)
  local result = {}
  for _, arg in ipairs(field_node.arguments or {}) do
    result[arg.name.value] = coerce_value(arg.value, ctx)
  end
  return result
end
```

Called by `execute_field` before invoking a resolver.  Resolvers receive the coerced table
and read arguments by name: `args.owner`, `args.first`, etc.

### Phase 1 variable coercion scope

Phase 1 does **not** validate that variable values match their declared types.  A variable
declared as `$owner: String!` that is passed as an integer produces no error; the resolver
receives the integer and will likely fail to build a valid URL, producing a resolver error
rather than a type error.  Full type coercion is deferred to Phase 2.

Phase 1 **does** apply default values.  A variable declared as `$state: IssueState =
OPEN` that is absent from the request body will be coerced to the string `"OPEN"` by
following the `default_value` through `coerce_value`.

Phase 1 does **not** enforce non-null variable constraints.  A variable declared as
`$owner: String!` that is omitted without a default produces `nil`; the resolver will
produce a null field value and add an error entry.  A dedicated validation pass would
catch this earlier and produce a clearer error; that pass is a Phase 2 item.

## Directives

### Supported directives

Phase 1 supports exactly two execution directives:

| Directive | Argument | Semantics |
|-----------|----------|-----------|
| `@skip(if: Boolean!)` | `if` | Skip the selection if `if` evaluates to `true` |
| `@include(if: Boolean!)` | `if` | Include the selection only if `if` evaluates to `true` |

Both apply to fields, fragment spreads, and inline fragments.  The spec permits both on
the same selection; they are evaluated independently (a selection is included only when
`@skip` does not suppress it **and** `@include` does not suppress it).

All other directives encountered in a query document — including schema-definition
directives like `@deprecated`, `@specifiedBy`, `@oneOf` — are silently ignored by the
executor.  They are not execution directives; they annotate schema elements and are never
present in operation documents.

### Directive evaluation in `collect_fields`

`should_include(selection, ctx)` evaluates all directives on a selection node and returns
`false` if the selection should be dropped:

```lua
local function eval_if_arg(directive, ctx)
  for _, arg in ipairs(directive.arguments or {}) do
    if arg.name.value == "if" then
      return coerce_value(arg.value, ctx)
    end
  end
  return false  -- missing 'if' arg → condition not met
end

local function should_include(selection, ctx)
  for _, dir in ipairs(selection.directives or {}) do
    local name = dir.name.value
    if name == "skip" and eval_if_arg(dir, ctx) then
      return false
    end
    if name == "include" and not eval_if_arg(dir, ctx) then
      return false
    end
  end
  return true
end
```

`collect_fields` calls `should_include` as the first check for every selection:

```lua
for _, selection in ipairs(sel_set.selections) do
  if not should_include(selection, ctx) then
    -- skip
  elseif selection.kind == "Field" then
    ...
```

Because `eval_if_arg` calls `coerce_value`, directives with variable arguments work
automatically: `@skip(if: $dry)` where `$dry` is `true` in `ctx.variables` skips the
field.

### Future directives

`@defer` and `@stream` are permanently out of scope (see
[01-api-surface.md](01-api-surface.md)).  If a client sends `@defer`, the directive is
silently ignored and the field is executed synchronously; the response contains no
`hasNext` or incremental delivery markers.  This is a spec deviation but is acceptable
because confusio documents it and real-world clients that use `@defer` already handle
servers that execute it eagerly.

## Introspection

### `__typename`

`__typename` is a synthetic field available on every object, interface, and union type.
It returns the current concrete type name as a `String!`.

The executor intercepts it in `execute_field` before any resolver lookup:

```lua
if field_name == "__typename" then
  return type_name   -- the string "Repository", "User", "Issue", etc.
end
```

`__typename` never touches a backend REST call.  It is handled identically on root types
and sub-types.  The `graphql_schema_field` function returns a synthetic definition for it
so schema validation does not reject it.

### `__schema`

Only available on the `Query` root type.  Returns the full `__Schema` object describing
every type in the vendored schema subset.

In `execute_field`:

```lua
if type_name == schema_data.query_type and field_name == "__schema" then
  return graphql_introspect_schema()
end
```

`graphql_introspect_schema()` is defined in `graphql_schema.lua` and builds the full
introspection object from `graphql_schema_data`.  The returned Lua table mirrors the
`__Schema` GraphQL type:

```lua
{
  __typename       = "__Schema",
  description      = "...",
  queryType        = { __typename = "__Type", kind = "OBJECT", name = "Query" },
  mutationType     = { __typename = "__Type", kind = "OBJECT", name = "Mutation" },
  subscriptionType = nil,
  types            = { ... },     -- array of __Type tables, one per named type
  directives       = { ... },     -- array of __Directive tables for built-ins
}
```

The executor plucks the client's selected sub-fields from this table using its normal
field-pluck mechanism.  Because the introspection types (`__Schema`, `__Type`, `__Field`,
`__InputValue`, `__EnumValue`, `__Directive`) are present in `graphql_schema_data`, the
schema validation and leaf-detection logic work on introspection selections without special
cases.

#### `__Schema.types` and `__Type` shape

Each entry in `types` is a fully-populated `__Type` table:

```lua
{
  __typename     = "__Type",
  kind           = "OBJECT",     -- or SCALAR, ENUM, INTERFACE, UNION, INPUT_OBJECT
  name           = "Repository",
  description    = "A repository ...",
  fields         = { ... },      -- array of __Field tables; nil for non-OBJECT/INTERFACE
  interfaces     = { ... },      -- array of __Type stubs; nil for non-OBJECT
  possibleTypes  = { ... },      -- array of __Type stubs; nil for non-INTERFACE/UNION
  enumValues     = { ... },      -- array of __EnumValue; nil for non-ENUM
  inputFields    = { ... },      -- array of __InputValue; nil for non-INPUT_OBJECT
  ofType         = nil,          -- used only for NON_NULL and LIST wrappers
}
```

NON_NULL and LIST wrappers appear only as the `type` field of `__Field` and
`__InputValue` nodes, not as named types in the `types` array.  They are constructed
on the fly by `graphql_schema_expand_type` (see [03-schema.md](03-schema.md)).

#### `__Field` and `includeDeprecated`

The `fields` and `enumValues` resolver functions accept an `includeDeprecated: Boolean`
argument.  In Phase 1, confusio always returns all fields regardless of the argument's
value.  Because most clients — including graphql-js's `IntrospectionQuery` — pass
`includeDeprecated: true`, this deviation is rarely observable.  Filtering based on
`isDeprecated` is a Phase 2 item.

#### Built-in directives in `__Schema.directives`

The `directives` array always contains exactly three entries:

```lua
{
  { __typename = "__Directive", name = "skip",
    description   = "Directs the executor to skip this field or fragment ...",
    locations     = { "FIELD", "FRAGMENT_SPREAD", "INLINE_FRAGMENT" },
    isRepeatable  = false,
    args          = { { __typename = "__InputValue", name = "if",
                        description = "Skipped when true.",
                        type        = { kind="NON_NULL", ofType={kind="SCALAR", name="Boolean"} },
                        defaultValue = nil } } },
  { __typename = "__Directive", name = "include",
    description   = "Directs the executor to include this field or fragment ...",
    locations     = { "FIELD", "FRAGMENT_SPREAD", "INLINE_FRAGMENT" },
    isRepeatable  = false,
    args          = { { __typename = "__InputValue", name = "if",
                        description = "Included when true.",
                        type        = { kind="NON_NULL", ofType={kind="SCALAR", name="Boolean"} },
                        defaultValue = nil } } },
  { __typename = "__Directive", name = "deprecated",
    description   = "Marks an element of a GraphQL schema as no longer supported.",
    locations     = { "FIELD_DEFINITION", "ARGUMENT_DEFINITION", "INPUT_FIELD_DEFINITION", "ENUM_VALUE" },
    isRepeatable  = false,
    args          = { { __typename = "__InputValue", name = "reason",
                        description = "Explains why this element was deprecated ...",
                        type        = { kind="SCALAR", name="String" },
                        defaultValue = '"No longer supported"' } } },
}
```

### `__type(name: String!)`

Only available on `Query`.  Returns a single `__Type` table or `nil` (JSON `null`) if the
named type is not in the schema.

In `execute_field`:

```lua
if type_name == schema_data.query_type and field_name == "__type" then
  local args = coerce_argument_values(field_node, ctx)
  return graphql_introspect_type(args.name)
end
```

`graphql_introspect_type(name)` is defined in `graphql_schema.lua`.  It returns the same
`__Type` table shape as entries in `__Schema.types`.

### The standard IntrospectionQuery

Code generators (graphql-js, graphql-inspector, Octokit type generation) send a standard
IntrospectionQuery that exercises fragments, `@include(if: false)`, and deeply-nested type
references:

```graphql
query IntrospectionQuery {
  __schema {
    queryType { name }
    mutationType { name }
    subscriptionType { name }
    types { ...FullType }
    directives {
      name description locations
      args { ...InputValue }
    }
  }
}
fragment FullType on __Type {
  kind name description
  fields(includeDeprecated: true) {
    name description
    args { ...InputValue }
    type { ...TypeRef }
    isDeprecated deprecationReason
  }
  inputFields { ...InputValue }
  interfaces { ...TypeRef }
  enumValues(includeDeprecated: true) { name description isDeprecated deprecationReason }
  possibleTypes { ...TypeRef }
}
fragment InputValue on __InputValue {
  name description type { ...TypeRef } defaultValue
}
fragment TypeRef on __Type {
  kind name
  ofType { kind name
    ofType { kind name
      ofType { kind name
        ofType { kind name
          ofType { kind name
            ofType { kind name
              ofType { kind name } } } } } } }
}
```

This query:
- Uses three named fragments (`FullType`, `InputValue`, `TypeRef`), each spread multiple
  times.
- Nests `TypeRef` within itself 7 levels deep (via field pluck, not recursive resolution,
  because `__Type.ofType` is a field whose value is itself a `__Type` table — the executor
  plucks it normally).
- Uses `includeDeprecated: true` as a literal argument.
- Selects `__typename` implicitly through the `kind` field.

This must work correctly when confusio ships Phase 1.  The executor's fragment-spread
handling and the `graphql_introspect_schema()` return value must jointly satisfy it.

### Introspection and field validation

The Phase 1 validator (see [03-schema.md](03-schema.md)) must not reject meta-field
selections.  `graphql_schema_field` returns synthetic definitions for `__typename`,
`__schema`, and `__type` on their respective allowed types, so the field-existence check
passes without a special case in the validator.

The introspection types (`__Schema`, `__Type`, `__Field`, `__InputValue`, `__EnumValue`,
`__Directive`) are included in `graphql_schema_data` as regular named types, so `TypeRef`
fragment spreads on `__Type` pass the type-condition check normally.

## Testing

Unit tests in `test/graphql-fragments-vars-directives.lua`:

### Fragment tests
- Named fragment spread: a query using a single fragment resolves its fields correctly.
- Inline fragment with matching type condition: fields included.
- Inline fragment with non-matching type condition: fields excluded.
- Inline fragment with no type condition: fields always included.
- Nested fragment (spread within spread): resolves correctly.
- Fragment cycle guard: a document where fragment A spreads B and B spreads A does not
  infinite-loop; the second encounter of A is skipped.
- Fragment on interface type condition: included when current type implements the
  interface.

### Variable tests
- Variable used in argument: `$owner: String!` with `variables = {owner = "octocat"}`
  produces the correct argument value.
- Missing variable with default: `$state: IssueState = OPEN` absent from request body
  produces the string `"OPEN"`.
- Missing variable without default: produces `nil` for the argument.
- Variable in `@skip` directive: `@skip(if: $dry)` with `{dry: true}` skips the field.
- Variable in nested ObjectValue: a variable within a list within an object argument is
  resolved from `ctx.variables`.

### Directive tests
- `@skip(if: true)`: field absent from response.
- `@skip(if: false)`: field present.
- `@include(if: true)`: field present.
- `@include(if: false)`: field absent.
- Both `@skip(if: false)` and `@include(if: true)` on same field: field present.
- Both `@skip(if: true)` and `@include(if: true)` on same field: field absent (`@skip`
  wins).
- Unknown directive: silently ignored, field present.
- Directive on fragment spread: entire fragment included or excluded.

### Introspection tests
- `__typename` on a root field: returns the type name string without calling any resolver.
- `__schema { queryType { name } }`: returns `"Query"`.
- `__schema { types { name } }` contains `"Repository"` and `"User"`.
- `__schema { directives { name } }` returns exactly `["skip", "include", "deprecated"]`.
- `__type(name: "Repository") { kind name }`: returns `kind = "OBJECT"`.
- `__type(name: "IssueState") { enumValues { name } }`: returns `["OPEN", "CLOSED"]`.
- `__type(name: "NonExistent")`: returns `null`.
- Full `IntrospectionQuery` document (the standard graphql-js query): executes without
  error and returns a response with all expected top-level keys.
