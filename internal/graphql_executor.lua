-- GraphQL executor: resolver dispatch, selection walking, and response helpers.
--
-- Requires: set_preamble (internal/http.lua), EncodeJson/Write/GetBody/DecodeJson (Redbean),
--           graphql_parse (internal/graphql_parser.lua),
--           graphql_schema_* (internal/graphql_schema.lua).
--
-- Globals exported:
--   graphql_resolvers            — table; backends populate at load time alongside backend_impl
--   graphql_handler()            — HTTP handler for POST /graphql; registered in catalog
--   respond_graphql(data, errs)  — null-safe GraphQL response writer
--   graphql_error(ctx, ...)      — error-recording helper called by resolvers
--   graphql_cached(ctx, key, fn) — request-scoped cache helper for resolvers
--   estimate_query_cost(op, vars) — query cost estimator; exposed for unit tests

-- ---------------------------------------------------------------------------
-- Resolver registry
-- ---------------------------------------------------------------------------

-- Backends populate graphql_resolvers at load time alongside backend_impl.
-- Keys are "TypeName.fieldName" strings (e.g. "Query.repository", "Repository.issues").
graphql_resolvers = {} -- luacheck: globals graphql_resolvers

-- ---------------------------------------------------------------------------
-- respond_graphql
-- ---------------------------------------------------------------------------

-- Write the canonical GraphQL response envelope: always HTTP 200, always a JSON
-- object with a "data" key.
--
-- WHY MANUAL CONSTRUCTION: EncodeJson({data = nil}) silently drops the key,
-- producing {"errors":[...]} instead of the spec-required {"data":null,...}.
-- We work around this by building the string by hand when data is nil.
--
-- Signature:
--   data   — Lua table (result object or partial result) or nil (request/validation error)
--   errors — array of error tables; omitted from the response when nil or empty
function respond_graphql(data, errors) -- luacheck: globals respond_graphql
  set_preamble(200)
  local data_json = (data ~= nil) and EncodeJson(data) or "null"
  if errors and #errors > 0 then
    Write('{"data":' .. data_json .. ',"errors":' .. EncodeJson(errors) .. "}")
  else
    Write('{"data":' .. data_json .. "}")
  end
end

-- ---------------------------------------------------------------------------
-- graphql_error
-- ---------------------------------------------------------------------------

-- Record a GraphQL field error in ctx.errors and return nil.
--
-- Designed so callers can write:  return graphql_error(ctx, "msg", field_node, "CODE")
--
-- Parameters:
--   ctx        — execution context table with an `errors` array and optional `path` array
--   message    — human-readable error description
--   field_node — FieldNode currently being executed (for location tracking), or nil
--   code       — optional machine-readable extensions.code string (e.g. "NOT_FOUND")
function graphql_error(ctx, message, field_node, code) -- luacheck: globals graphql_error
  local err = { message = message }

  -- Location: extracted from the field node's name token (line/col set by the parser).
  if field_node and field_node.name and field_node.name.line then
    err.locations = { { line = field_node.name.line, column = field_node.name.col } }
  end

  -- Path: snapshot of the current execution path so each error records its own position.
  if ctx.path and #ctx.path > 0 then
    err.path = {}
    for i, segment in ipairs(ctx.path) do
      err.path[i] = segment
    end
  end

  -- Extensions: machine-readable code when provided.
  if code then
    err.extensions = { code = code }
  end

  ctx.errors[#ctx.errors + 1] = err
  return nil
end

-- ---------------------------------------------------------------------------
-- graphql_cached
-- ---------------------------------------------------------------------------

-- Unique sentinel: distinguishes "key not yet fetched" (nil table entry) from
-- "key was fetched and result was nil" (CACHE_MISS entry).
local CACHE_MISS = {}

-- Call fetch_fn() and cache the result under cache_key for this request.
-- Returns the cached result on subsequent calls with the same key.
--
-- fetch_fn may return nil (e.g. resource not found); nil is cached via the
-- CACHE_MISS sentinel so a second call does not re-invoke fetch_fn.
--
-- Cache key convention: "TypeName:local_id"  (e.g. "User:octocat",
-- "Repository:octocat/hello-world").  Connection results (paginated lists)
-- are not cached — their content varies by pagination args.
--
-- ctx.cache is created fresh per graphql_handler invocation; there is no
-- cross-request cache.
function graphql_cached(ctx, cache_key, fetch_fn) -- luacheck: globals graphql_cached
  local hit = ctx.cache[cache_key]
  if hit == nil then
    -- Not yet fetched.
    local result = fetch_fn()
    ctx.cache[cache_key] = (result == nil) and CACHE_MISS or result
    return result
  elseif hit == CACHE_MISS then
    return nil -- previously fetched, was nil
  else
    return hit
  end
end

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

-- append_error: convenience wrapper used internally (no code, pcall-safe).
local function append_error(ctx, message, field_node)
  graphql_error(ctx, message, field_node, nil)
end

-- coerce_value: converts a parsed Value node to a Lua value.
local function coerce_value(node, ctx)
  if node.kind == "Variable" then
    local name = node.name.value
    local val = ctx.variables[name]
    if val == nil then
      -- Fall back to the VariableDefinition's default value, if any.
      local vd = ctx.variable_defs and ctx.variable_defs[name]
      if vd and vd.default_value then
        return coerce_value(vd.default_value, ctx)
      end
    end
    return val
  elseif node.kind == "IntValue" or node.kind == "FloatValue" then
    return tonumber(node.value)
  elseif node.kind == "StringValue" or node.kind == "EnumValue" then
    return node.value
  elseif node.kind == "BooleanValue" then
    return node.value -- already a Lua boolean from the parser
  elseif node.kind == "NullValue" then
    return nil
  elseif node.kind == "ListValue" then
    local result = {}
    for i, item in ipairs(node.values) do
      result[i] = coerce_value(item, ctx)
    end
    return result
  elseif node.kind == "ObjectValue" then
    local result = {}
    for _, field in ipairs(node.fields) do
      result[field.name.value] = coerce_value(field.value, ctx)
    end
    return result
  end
  return nil
end

-- coerce_argument_values: converts a list of Argument nodes to a key/value table.
local function coerce_argument_values(arguments, ctx)
  local args = {}
  if arguments then
    for _, arg in ipairs(arguments) do
      args[arg.name.value] = coerce_value(arg.value, ctx)
    end
  end
  return args
end

-- coerce_arg: helper to pluck a single named argument (used for __type).
local function coerce_arg(field_node, arg_name, ctx)
  if field_node.arguments then
    for _, arg in ipairs(field_node.arguments) do
      if arg.name.value == arg_name then
        return coerce_value(arg.value, ctx)
      end
    end
  end
  return nil
end

-- eval_directive: returns true if the field should be included given @skip/@include.
local function eval_directive(directives, ctx)
  if not directives then
    return true
  end
  for _, dir in ipairs(directives) do
    local name = dir.name.value
    if name == "skip" or name == "include" then
      -- Find the "if" argument.
      local cond = nil
      if dir.arguments then
        for _, arg in ipairs(dir.arguments) do
          if arg.name.value == "if" then
            cond = coerce_value(arg.value, ctx)
            break
          end
        end
      end
      if name == "skip" and cond == true then
        return false
      end
      if name == "include" and cond == false then
        return false
      end
    end
  end
  return true
end

-- does_type_apply: checks whether a fragment type_condition applies to current_type.
local function does_type_apply(condition_type, current_type)
  if condition_type == current_type then
    return true
  end
  -- Check if current_type implements condition_type as an interface.
  local ct = graphql_schema_type(current_type)
  if ct and ct.interfaces then
    for _, iface in ipairs(ct.interfaces) do
      if iface == condition_type then
        return true
      end
    end
  end
  -- Check if condition_type is a union containing current_type.
  local ut = graphql_schema_type(condition_type)
  if ut and ut.kind == "UNION" and ut.possible_types then
    for _, pt in ipairs(ut.possible_types) do
      if pt == current_type then
        return true
      end
    end
  end
  return false
end

-- collect_fields: produces an ordered map from response_key → {FieldNode,...}.
-- sel_set  — SelectionSetNode
-- type_name — string: current object type
-- ctx       — execution context
-- visited   — table of fragment names already expanded (cycle guard); may be nil
local function collect_fields(sel_set, type_name, ctx, visited)
  visited = visited or {}
  local field_map = {}
  local field_order = {}

  local function add_field(response_key, field_node)
    if not field_map[response_key] then
      field_order[#field_order + 1] = response_key
      field_map[response_key] = {}
    end
    field_map[response_key][#field_map[response_key] + 1] = field_node
  end

  for _, sel in ipairs(sel_set.selections) do
    if eval_directive(sel.directives, ctx) then
      if sel.kind == "Field" then
        local response_key = (sel.alias and sel.alias.value) or sel.name.value
        add_field(response_key, sel)
      elseif sel.kind == "InlineFragment" then
        local ok_to_include = true
        if sel.type_condition then
          ok_to_include = does_type_apply(sel.type_condition.name.value, type_name)
        end
        if ok_to_include then
          local sub_map, sub_order = collect_fields(sel.selection_set, type_name, ctx, visited)
          for _, key in ipairs(sub_order) do
            for _, fn in ipairs(sub_map[key]) do
              add_field(key, fn)
            end
          end
        end
      elseif sel.kind == "FragmentSpread" then
        local frag_name = sel.name.value
        if not visited[frag_name] then
          visited[frag_name] = true
          -- Look up the fragment definition in the document.
          local frag_def = nil
          for _, def in ipairs(ctx.doc.definitions) do
            if def.kind == "FragmentDefinition" and def.name and def.name.value == frag_name then
              frag_def = def
              break
            end
          end
          if frag_def then
            local cond_applies = true
            if frag_def.type_condition then
              cond_applies = does_type_apply(frag_def.type_condition.name.value, type_name)
            end
            if cond_applies then
              local sub_map, sub_order =
                collect_fields(frag_def.selection_set, type_name, ctx, visited)
              for _, key in ipairs(sub_order) do
                for _, fn in ipairs(sub_map[key]) do
                  add_field(key, fn)
                end
              end
            end
          end
        end
      end
    end
  end

  return field_map, field_order
end

-- resolve_concrete_type: returns the Lua type name for an object/interface/union value.
local function resolve_concrete_type(type_ref, value)
  -- Use __typename if the resolver set it (required for interfaces and unions).
  if type(value.__typename) == "string" then
    return value.__typename
  end
  -- For plain OBJECT types there is no ambiguity.
  local base = graphql_schema_base_type(type_ref)
  local t = graphql_schema_type(base)
  if t and t.kind == "OBJECT" then
    return base
  end
  return nil
end

-- Forward declarations for mutual recursion.
local execute_selection_set
local complete_value

-- PROPAGATE is a unique sentinel returned by complete_value when a Non-Null field
-- resolves to null.  The parent complete_value propagates it upward until a nullable
-- type stops it (returning nil) or execute_selection_set converts it to nil in the
-- result table.  Identity comparison only — never serialised or exposed to resolvers.
local PROPAGATE = {}

-- execute_field: resolves one field and returns the raw (uncompleted) value.
local function execute_field(field_node, type_name, parent, ctx)
  local field_name = field_node.name.value

  -- Meta-fields handled directly (no resolver, no schema lookup).
  if field_name == "__typename" then
    return type_name
  end
  if type_name == graphql_schema_data.query_type then
    if field_name == "__schema" then
      return graphql_introspect_schema()
    end
    if field_name == "__type" then
      return graphql_introspect_type(coerce_arg(field_node, "name", ctx))
    end
  end

  local args = coerce_argument_values(field_node.arguments, ctx)
  local resolver_key = type_name .. "." .. field_name

  if graphql_resolvers[resolver_key] then
    local ok, result = pcall(graphql_resolvers[resolver_key], parent, args, ctx)
    if not ok then
      append_error(ctx, "internal error in resolver " .. resolver_key, field_node)
      return nil
    end
    return result
  end

  -- Tier 2: field pluck from parent table.
  if parent ~= nil then
    return parent[field_name]
  end
  return nil
end

-- complete_value: recursively completes a resolved value according to its type.
complete_value = function(value, type_ref, field_node, type_name, ctx)
  -- Non-null unwrapping.
  if graphql_schema_is_nonnull(type_ref) then
    local inner_ref = type_ref:sub(1, -2) -- strip trailing "!"
    local inner = complete_value(value, inner_ref, field_node, type_name, ctx)
    if inner == nil or inner == PROPAGATE then
      -- Non-null contract violated; bubble upward so the nearest nullable ancestor
      -- becomes null (execute_selection_set converts PROPAGATE → nil in the result).
      graphql_error(
        ctx,
        "non-null field resolved to null: " .. (field_node and field_node.name.value or "?"),
        field_node
      )
      return PROPAGATE
    end
    return inner
  end

  -- Nullable: absorb any upward-propagating null here.
  if value == PROPAGATE then
    return nil
  end
  if value == nil then
    return nil
  end

  -- List unwrapping.
  if type_ref:sub(1, 1) == "[" then
    if type(value) ~= "table" then
      append_error(ctx, "expected list, got scalar", field_node)
      return nil
    end
    local inner_ref = type_ref:match("%[(.+)%]$") or type_ref:sub(2, -2)
    local result = {}
    -- Use value.n when present (set by resolvers that return sparse arrays, e.g.
    -- Query.nodes where some entries are nil/null) to preserve the correct length.
    local len = rawget(value, "n") or #value
    for i = 1, len do
      ctx.path[#ctx.path + 1] = i - 1 -- push 0-based index per spec
      local item = complete_value(value[i], inner_ref, field_node, type_name, ctx)
      -- Do not use `item and nil or item` — the ternary idiom breaks when nil is
      -- the "truthy" branch.  An explicit if keeps PROPAGATE out of the result.
      if item ~= PROPAGATE then
        result[i] = item
      end
      ctx.path[#ctx.path] = nil -- pop
    end
    return result
  end

  -- Leaf scalar/enum: return as-is.
  if graphql_schema_is_leaf(type_ref) then
    return value
  end

  -- Object / interface / union: recurse into selection set.
  if type(value) ~= "table" then
    append_error(ctx, "expected object, got scalar for " .. type_ref, field_node)
    return nil
  end
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
end

-- execute_selection_set: walks all fields in the selection set and returns a result table.
execute_selection_set = function(sel_set, type_name, parent, ctx)
  local field_map, field_order = collect_fields(sel_set, type_name, ctx)
  local result = {}
  for _, response_key in ipairs(field_order) do
    local field_nodes = field_map[response_key]
    local field_node = field_nodes[1]
    local field_name = field_node.name.value
    ctx.path[#ctx.path + 1] = response_key -- push
    local raw = execute_field(field_node, type_name, parent, ctx)
    local field_def = graphql_schema_field(type_name, field_name)
    local type_ref = (field_def and field_def.type) or "String"
    local completed = complete_value(raw, type_ref, field_node, type_name, ctx)
    -- PROPAGATE means a non-null field resolved to null; the field becomes null
    -- (nil in Lua) in the result.  Do not use the `a and b or c` ternary here —
    -- it breaks when b is nil (falsy), causing PROPAGATE to leak into the result.
    if completed ~= PROPAGATE then
      result[response_key] = completed
    end
    ctx.path[#ctx.path] = nil -- pop
  end
  return result
end

-- execute_operation: top-level entry point for running one operation.
local function execute_operation(op, ctx)
  local root_type
  if op.operation == "query" then
    root_type = graphql_schema_data.query_type
  elseif op.operation == "mutation" then
    root_type = graphql_schema_data.mutation_type
  else
    return nil
  end
  return execute_selection_set(op.selection_set, root_type, nil, ctx)
end

-- ---------------------------------------------------------------------------
-- select_operation
-- ---------------------------------------------------------------------------

local function select_operation(doc, op_name)
  local ops = {}
  for _, def in ipairs(doc.definitions) do
    if def.kind == "OperationDefinition" then
      ops[#ops + 1] = def
    end
  end

  if op_name then
    for _, op in ipairs(ops) do
      if op.name and op.name.value == op_name then
        return op, nil
      end
    end
    return nil, "Unknown operation named '" .. op_name .. "'"
  end

  if #ops == 1 then
    return ops[1], nil
  end
  if #ops == 0 then
    return nil, "Document contains no operations"
  end
  return nil, "Must provide operation name when document contains multiple operations"
end

-- ---------------------------------------------------------------------------
-- graphql_validate: Phase 1 field-existence and leaf/composite checks
-- ---------------------------------------------------------------------------

-- graphql_validate_error: builds a validation error table (VALIDATION_ERROR code).
-- Simpler than graphql_error — no ctx needed since validation runs before execution.
-- name_node is a NameNode with optional line/col from the parser, or nil.
local function graphql_validate_error(message, name_node)
  local err = {
    message = message,
    extensions = { code = "VALIDATION_ERROR" },
  }
  if name_node and name_node.line then
    err.locations = { { line = name_node.line, column = name_node.col } }
  end
  return err
end

-- validate_selection_set: recursively validate field existence and structure.
-- Returns an array of error objects (empty means valid).
local function validate_selection_set(sel_set, type_name, doc, seen_frags, errors)
  for _, sel in ipairs(sel_set.selections) do
    if sel.kind == "Field" then
      local field_name = sel.name.value
      -- Meta-fields are always valid.
      if field_name ~= "__typename" and field_name ~= "__schema" and field_name ~= "__type" then
        local field_def = graphql_schema_field(type_name, field_name)
        if not field_def then
          errors[#errors + 1] = graphql_validate_error(
            "Field '" .. field_name .. "' does not exist on type '" .. type_name .. "'",
            sel.name
          )
        else
          local is_leaf = graphql_schema_is_leaf(field_def.type)
          if is_leaf and sel.selection_set then
            errors[#errors + 1] = graphql_validate_error(
              "Field '" .. field_name .. "' is a leaf type and must not have sub-selections",
              sel.name
            )
          elseif not is_leaf and not sel.selection_set then
            errors[#errors + 1] = graphql_validate_error(
              "Field '" .. field_name .. "' is a composite type and must have sub-selections",
              sel.name
            )
          elseif sel.selection_set then
            local base = graphql_schema_base_type(field_def.type)
            validate_selection_set(sel.selection_set, base, doc, seen_frags, errors)
          end
        end
      end
    elseif sel.kind == "InlineFragment" then
      local cond_type = type_name
      if sel.type_condition then
        cond_type = sel.type_condition.name.value
      end
      validate_selection_set(sel.selection_set, cond_type, doc, seen_frags, errors)
    elseif sel.kind == "FragmentSpread" then
      local frag_name = sel.name.value
      if not seen_frags[frag_name] then
        seen_frags[frag_name] = true
        for _, def in ipairs(doc.definitions) do
          if def.kind == "FragmentDefinition" and def.name and def.name.value == frag_name then
            local cond_type = type_name
            if def.type_condition then
              cond_type = def.type_condition.name.value
            end
            validate_selection_set(def.selection_set, cond_type, doc, seen_frags, errors)
            break
          end
        end
      end
    end
  end
end

local function graphql_validate(doc, op)
  local root_type
  if op.operation == "query" then
    root_type = graphql_schema_data.query_type
  elseif op.operation == "mutation" then
    root_type = graphql_schema_data.mutation_type
  else
    return {
      graphql_validate_error("Unsupported operation type: " .. tostring(op.operation), nil),
    }
  end
  local errors = {}
  validate_selection_set(op.selection_set, root_type, doc, {}, errors)
  return errors
end

-- ---------------------------------------------------------------------------
-- graphql_handler
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Query.node and Query.nodes — backend-independent dispatchers
-- ---------------------------------------------------------------------------
-- These resolvers live in the executor, not in backends, because they only
-- decode the node ID and dispatch to a "node.TypeName" sub-resolver.  The
-- sub-resolvers are backend-specific and registered by each backend file.

graphql_resolvers["Query.node"] = function(_parent, args, ctx) -- luacheck: globals graphql_resolvers
  local node_id = args.id
  if not node_id then
    append_error(ctx, "node requires an id argument")
    return nil
  end
  local type_name, local_id = decode_node_id(node_id)
  if not type_name then
    append_error(ctx, "invalid node id: " .. tostring(node_id))
    return nil
  end
  local resolver = graphql_resolvers["node." .. type_name]
  if not resolver then
    -- Unknown type: return null with no error (valid on a different server).
    return nil
  end
  local ok, result = pcall(resolver, local_id, ctx)
  if not ok then
    append_error(ctx, "internal error resolving node: " .. type_name)
    return nil
  end
  return result
end

graphql_resolvers["Query.nodes"] = function(_parent, args, ctx)
  local ids = args.ids
  if not ids or type(ids) ~= "table" then
    append_error(ctx, "nodes requires an ids argument")
    return {}
  end
  -- Null slots (unsupported type, malformed ID, or not-found) must be preserved as
  -- nil in the parallel output array.  Lua's # operator stops at the first nil hole,
  -- so we attach a __len metamethod that returns the explicit .n count instead.
  -- The list completer in complete_value() already reads rawget(value, "n") for the
  -- same reason; __len keeps external callers (tests, JSON encoders) consistent.
  local n = #ids
  local results = setmetatable({ n = n }, {
    __len = function(t)
      return rawget(t, "n") or 0
    end,
  })
  for i, id in ipairs(ids) do
    local type_name, local_id = decode_node_id(id)
    if type_name then
      local resolver = graphql_resolvers["node." .. type_name]
      if resolver then
        local ok, result = pcall(resolver, local_id, ctx)
        if ok and result ~= nil then
          results[i] = result
        end
        -- else: results[i] stays nil (null for not-found or resolver error)
      end
      -- else: results[i] stays nil (null for unsupported type)
    end
    -- else: results[i] stays nil (null for malformed ID — no per-item error per spec)
  end
  return results
end

-- ---------------------------------------------------------------------------
-- estimate_query_cost / GRAPHQL_MAX_COST
-- ---------------------------------------------------------------------------

-- Maximum allowed estimated query cost.  Queries whose estimated cost exceeds
-- this value are rejected before execution.  The default (10000) is enough for
-- practical GitHub CLI and Octokit queries; override in Phase 2 via SCRIPTARGS.
local GRAPHQL_MAX_COST = 10000

-- Lightweight pre-execution cost estimator.  Walks the operation's selection
-- set counting connection argument values (first/last), multiplying for nested
-- connections.  The result is stored in ctx.rate_cost before execution so that
-- the Query.rateLimit resolver can report a non-zero cost value, and so that
-- the cost-limit gate can reject runaway queries before execution begins.
--
-- Cost rules (mirrors GitHub's documented model):
--   - Each field with a first/last argument contributes (multiplier × value).
--   - Nested connection fields multiply their parent's page size.
--   - Scalar leaf fields contribute 0.
--   - Minimum returned value is 1 (math.max(1, total)).
--
-- This is best-effort: fragment spreads are not walked in Phase 1, and
-- @skip/@include directives are not applied.
function estimate_query_cost(op, variables) -- luacheck: globals estimate_query_cost
  local cost = 0
  -- We need a minimal ctx for coerce_value (Variable nodes require variables +
  -- variable_defs).  Build one from the operation's variable definitions.
  local vdefs = {}
  for _, vd in ipairs(op.variable_definitions or {}) do
    vdefs[vd.variable.name.value] = vd
  end
  local cost_ctx = { variables = variables or {}, variable_defs = vdefs }

  local function walk(selection_set, multiplier)
    if not selection_set then
      return
    end
    for _, sel in ipairs(selection_set.selections) do
      if sel.kind == "Field" then
        local page_size = 0
        if sel.arguments then
          for _, arg in ipairs(sel.arguments) do
            if arg.name.value == "first" or arg.name.value == "last" then
              local v = coerce_value(arg.value, cost_ctx)
              if type(v) == "number" then
                page_size = v
              end
            end
          end
        end
        if page_size > 0 then
          cost = cost + multiplier * page_size
          walk(sel.selection_set, multiplier * page_size)
        else
          walk(sel.selection_set, multiplier)
        end
      elseif sel.kind == "InlineFragment" then
        walk(sel.selection_set, multiplier)
      end
      -- FragmentSpread: not walked in Phase 1.
    end
  end

  walk(op.selection_set, 1)
  return math.max(1, cost)
end

-- ---------------------------------------------------------------------------
-- Query.rateLimit — backend-independent synthetic rate limit response
-- ---------------------------------------------------------------------------

-- Confusio does not bill by node cost.  Synthesise a plausible rateLimit
-- response so that clients polling rateLimit { cost remaining resetAt } work
-- without errors.  ctx.rate_cost is populated by estimate_query_cost before
-- execution runs.
graphql_resolvers["Query.rateLimit"] = function(_parent, _args, ctx)
  local limit = 999999
  local reset = os.time() + 3600
  return {
    limit = limit,
    cost = ctx.rate_cost or 1,
    remaining = limit,
    used = 0,
    nodeCount = 0,
    resetAt = os.date("!%Y-%m-%dT%H:%M:%SZ", reset),
  }
end

-- ---------------------------------------------------------------------------
-- graphql_handler
-- ---------------------------------------------------------------------------

-- graphql_handler is registered in the catalog as the fixed handler for
-- POST /graphql.  Backends do NOT override this via backend_impl; they only
-- populate graphql_resolvers.
function graphql_handler() -- luacheck: globals graphql_handler
  -- Step 1: decode request body.
  local raw = GetBody() or ""
  local req = DecodeJson(raw)
  -- Step 1a: array body → batch request (rejected in Phase 1).
  if type(req) == "table" and req[1] ~= nil then
    respond_json(400, {
      errors = {
        { message = "GraphQL request batching is not supported; send one operation per request." },
      },
    })
    return
  end
  -- Step 1b: APQ body → persisted queries not supported.
  if type(req) == "table" and type(req.extensions) == "table" and req.extensions.persistedQuery then
    respond_graphql(nil, {
      {
        message = "Persisted queries are not supported; send the full query string.",
        extensions = { code = "PERSISTED_QUERY_NOT_SUPPORTED" },
      },
    })
    return
  end
  -- Step 1c: missing or non-string query field.
  if not req or type(req.query) ~= "string" then
    respond_graphql(nil, {
      {
        message = "POST /graphql requires a JSON body with a 'query' field",
        extensions = { code = "BAD_USER_INPUT" },
      },
    })
    return
  end
  local source = req.query
  local variables = type(req.variables) == "table" and req.variables or {}
  local op_name = type(req.operationName) == "string" and req.operationName or nil

  -- Step 2: parse.
  local doc, parse_err = graphql_parse(source)
  if not doc then
    respond_graphql(nil, {
      {
        message = parse_err,
        extensions = { code = "PARSE_ERROR" },
      },
    })
    return
  end

  -- Step 3: select operation.
  local op, sel_err = select_operation(doc, op_name)
  if not op then
    respond_graphql(nil, {
      {
        message = sel_err,
        extensions = { code = "BAD_USER_INPUT" },
      },
    })
    return
  end

  -- Step 4: validate.
  local verrs = graphql_validate(doc, op)
  if #verrs > 0 then
    respond_graphql(nil, verrs)
    return
  end

  -- Step 5: execute.
  local ctx = {
    doc = doc,
    variables = variables,
    errors = {},
    path = {},
    cache = {}, -- request-scoped cache; see graphql_cached
  }
  -- Build variable_defs lookup: name → VariableDefinitionNode (for default values).
  ctx.variable_defs = {}
  for _, vd in ipairs(op.variable_definitions or {}) do
    ctx.variable_defs[vd.variable.name.value] = vd
  end
  -- Estimate query cost before execution so rateLimit.cost reflects this query.
  ctx.rate_cost = estimate_query_cost(op, variables)
  -- Step 5a: reject queries that exceed the cost ceiling.
  if ctx.rate_cost > GRAPHQL_MAX_COST then
    respond_graphql(nil, {
      {
        message = "query cost "
          .. tostring(ctx.rate_cost)
          .. " exceeds maximum allowed cost of "
          .. tostring(GRAPHQL_MAX_COST),
        extensions = {
          code = "BAD_USER_INPUT",
          estimatedCost = ctx.rate_cost,
          maxAllowedCost = GRAPHQL_MAX_COST,
        },
      },
    })
    return
  end
  local data = execute_operation(op, ctx)

  -- Step 6: write response.
  respond_graphql(data, ctx.errors)
end
