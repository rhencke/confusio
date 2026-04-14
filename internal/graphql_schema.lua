-- internal/graphql_schema.lua
-- Runtime API for the GraphQL type registry.
-- Depends on graphql_schema_data (loaded first).
-- Exports eight globals: graphql_schema_type, graphql_schema_field,
-- graphql_schema_base_type, graphql_schema_is_leaf, graphql_schema_is_nonnull,
-- graphql_schema_expand_type, graphql_introspect_schema, graphql_introspect_type.
-- luacheck: globals graphql_schema_type graphql_schema_field graphql_schema_base_type
-- luacheck: globals graphql_schema_is_leaf graphql_schema_is_nonnull graphql_schema_expand_type
-- luacheck: globals graphql_introspect_schema graphql_introspect_type

-- ---------------------------------------------------------------------------
-- graphql_schema_type(name)
-- Returns the type definition table for the named type, or nil if unknown.
-- ---------------------------------------------------------------------------
function graphql_schema_type(name) -- luacheck: globals graphql_schema_type
  return graphql_schema_data.types[name]
end

-- ---------------------------------------------------------------------------
-- graphql_schema_base_type(type_ref)
-- Extracts the innermost named type from a type-reference string.
--   "String!"       → "String"
--   "[Issue!]!"     → "Issue"
-- ---------------------------------------------------------------------------
function graphql_schema_base_type(type_ref) -- luacheck: globals graphql_schema_base_type
  return type_ref:match("[_%a][_%w]*")
end

-- ---------------------------------------------------------------------------
-- graphql_schema_is_nonnull(type_ref)
-- True if the outermost wrapper is non-null (trailing "!").
-- ---------------------------------------------------------------------------
function graphql_schema_is_nonnull(type_ref) -- luacheck: globals graphql_schema_is_nonnull
  return type_ref:sub(-1) == "!"
end

-- ---------------------------------------------------------------------------
-- graphql_schema_is_leaf(type_ref)
-- True if the resolved base type is a scalar or enum (leaf node).
-- ---------------------------------------------------------------------------
function graphql_schema_is_leaf(type_ref) -- luacheck: globals graphql_schema_is_leaf
  local base = graphql_schema_base_type(type_ref)
  local t = graphql_schema_type(base)
  if t == nil then
    return false
  end
  return t.kind == "SCALAR" or t.kind == "ENUM"
end

-- ---------------------------------------------------------------------------
-- graphql_schema_expand_type(type_ref)
-- Expands a type-reference string to the nested table form used by introspection.
--   "String!"    → { kind="NON_NULL", name=nil, ofType={ kind="SCALAR", name="String", ofType=nil } }
--   "[Issue!]!"  → NON_NULL → LIST → NON_NULL → OBJECT{name="Issue"}
-- ---------------------------------------------------------------------------
function graphql_schema_expand_type(type_ref) -- luacheck: globals graphql_schema_expand_type
  if type_ref:sub(-1) == "!" then
    return {
      kind = "NON_NULL",
      name = nil,
      ofType = graphql_schema_expand_type(type_ref:sub(1, -2)),
    }
  elseif type_ref:sub(1, 1) == "[" then
    return {
      kind = "LIST",
      name = nil,
      ofType = graphql_schema_expand_type(type_ref:sub(2, -2)),
    }
  else
    local t = graphql_schema_type(type_ref)
    return { kind = (t and t.kind or "SCALAR"), name = type_ref, ofType = nil }
  end
end

-- ---------------------------------------------------------------------------
-- Synthetic meta-field definitions (injected by graphql_schema_field).
-- ---------------------------------------------------------------------------

local META_TYPENAME = {
  name = "__typename",
  type = "String!",
  description = "The name of the current type.",
  args = {},
}
local META_SCHEMA = {
  name = "__schema",
  type = "__Schema!",
  description = "Access the current type schema of this server.",
  args = {},
}
local META_TYPE = {
  name = "__type",
  type = "__Type",
  description = "Request the type information of a single type.",
  args = {
    { name = "name", type = "String!", description = "The name of the type.", default_value = nil },
  },
}

-- ---------------------------------------------------------------------------
-- graphql_schema_field(type_name, field_name)
-- Returns the field definition for field_name on the named type, or nil.
-- Injects synthetic meta-fields (__typename, __schema, __type) automatically.
-- ---------------------------------------------------------------------------
function graphql_schema_field(type_name, field_name) -- luacheck: globals graphql_schema_field
  -- __typename is available on every object and interface type.
  if field_name == "__typename" then
    local t = graphql_schema_type(type_name)
    if t and (t.kind == "OBJECT" or t.kind == "INTERFACE") then
      return META_TYPENAME
    end
    return nil
  end

  -- __schema and __type are available only on the root Query type.
  if field_name == "__schema" and type_name == graphql_schema_data.query_type then
    return META_SCHEMA
  end
  if field_name == "__type" and type_name == graphql_schema_data.query_type then
    return META_TYPE
  end

  local t = graphql_schema_type(type_name)
  if t == nil then
    return nil
  end

  -- Search the fields array (OBJECT, INTERFACE) or input_fields (INPUT_OBJECT).
  local fields = t.fields or t.input_fields
  if fields == nil then
    return nil
  end
  for _, f in ipairs(fields) do
    if f.name == field_name then
      return f
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Introspection helpers (internal).
-- ---------------------------------------------------------------------------

-- Convert a stored arg/input-field definition to an __InputValue introspection table.
local function introspect_input_value(iv)
  return {
    name = iv.name,
    description = iv.description,
    type = graphql_schema_expand_type(iv.type),
    defaultValue = iv.default_value,
  }
end

-- Convert a stored field definition to a __Field introspection table.
local function introspect_field(f)
  local args = {}
  for i, a in ipairs(f.args or {}) do
    args[i] = introspect_input_value(a)
  end
  return {
    name = f.name,
    description = f.description,
    args = args,
    type = graphql_schema_expand_type(f.type),
    isDeprecated = f.is_deprecated or false,
    deprecationReason = f.deprecation_reason,
  }
end

-- Convert a stored type definition to a __Type introspection table.
local function introspect_type_def(t)
  if t == nil then
    return nil
  end
  local result = {
    kind = t.kind,
    name = t.name,
    description = t.description,
  }

  -- fields: OBJECT and INTERFACE only
  if t.kind == "OBJECT" or t.kind == "INTERFACE" then
    local fields = {}
    for i, f in ipairs(t.fields or {}) do
      fields[i] = introspect_field(f)
    end
    result.fields = fields
  end

  -- interfaces: OBJECT only
  if t.kind == "OBJECT" then
    local ifaces = {}
    for i, iname in ipairs(t.interfaces or {}) do
      ifaces[i] = { kind = "INTERFACE", name = iname, ofType = nil }
    end
    result.interfaces = ifaces
  end

  -- possibleTypes: INTERFACE and UNION
  if t.kind == "INTERFACE" or t.kind == "UNION" then
    local pts = {}
    for i, ptname in ipairs(t.possible_types or {}) do
      pts[i] = { kind = "OBJECT", name = ptname, ofType = nil }
    end
    result.possibleTypes = pts
  end

  -- enumValues: ENUM only
  if t.kind == "ENUM" then
    local evs = {}
    for i, ev in ipairs(t.values or {}) do
      evs[i] = {
        name = ev.name,
        description = ev.description,
        isDeprecated = ev.is_deprecated or false,
        deprecationReason = ev.deprecation_reason,
      }
    end
    result.enumValues = evs
  end

  -- inputFields: INPUT_OBJECT only
  if t.kind == "INPUT_OBJECT" then
    local ifields = {}
    for i, f in ipairs(t.input_fields or {}) do
      ifields[i] = introspect_input_value(f)
    end
    result.inputFields = ifields
  end

  return result
end

-- ---------------------------------------------------------------------------
-- graphql_introspect_type(name)
-- Returns the __Type introspection table for the named type, or nil if unknown.
-- ---------------------------------------------------------------------------
function graphql_introspect_type(name) -- luacheck: globals graphql_introspect_type
  return introspect_type_def(graphql_schema_type(name))
end

-- ---------------------------------------------------------------------------
-- graphql_introspect_schema()
-- Returns the full __schema introspection response table.
-- ---------------------------------------------------------------------------
function graphql_introspect_schema() -- luacheck: globals graphql_introspect_schema
  -- Collect all types as __Type objects, sorted by name for stability.
  local type_names = {}
  for name in pairs(graphql_schema_data.types) do
    type_names[#type_names + 1] = name
  end
  table.sort(type_names)

  local types = {}
  for i, name in ipairs(type_names) do
    types[i] = introspect_type_def(graphql_schema_data.types[name])
  end

  -- Convert stored directive definitions to __Directive introspection tables.
  local directives = {}
  for i, d in ipairs(graphql_schema_data.directives or {}) do
    local args = {}
    for j, a in ipairs(d.args or {}) do
      args[j] = introspect_input_value(a)
    end
    directives[i] = {
      name = d.name,
      description = d.description,
      isRepeatable = d.is_repeatable or false,
      locations = d.locations,
      args = args,
    }
  end

  local qt = graphql_schema_data.query_type
  local mt = graphql_schema_data.mutation_type
  local st = graphql_schema_data.subscription_type

  return {
    types = types,
    queryType = qt and { name = qt } or nil,
    mutationType = mt and { name = mt } or nil,
    subscriptionType = st and { name = st } or nil,
    directives = directives,
  }
end
