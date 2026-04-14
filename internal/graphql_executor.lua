-- GraphQL executor: resolver dispatch, selection walking, and response helpers.
--
-- Requires: set_preamble (internal/http.lua), EncodeJson/Write (Redbean built-ins),
--           graphql_parse (internal/graphql_parser.lua),
--           graphql_schema_* (internal/graphql_schema.lua).
--
-- Globals exported:
--   graphql_resolvers            — table; backends populate at load time alongside backend_impl
--   graphql_handler()            — HTTP handler for POST /graphql; registered in catalog
--   respond_graphql(data, errs)  — null-safe GraphQL response writer
--   graphql_error(ctx, ...)      — error-recording helper called by resolvers

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
-- graphql_handler (placeholder — full implementation in subsequent commits)
-- ---------------------------------------------------------------------------

-- graphql_handler is registered in the catalog as the fixed handler for
-- POST /graphql.  Backends do NOT override this via backend_impl; they only
-- populate graphql_resolvers.
function graphql_handler() -- luacheck: globals graphql_handler
  respond_graphql(nil, { { message = "GraphQL executor not yet implemented." } })
end
