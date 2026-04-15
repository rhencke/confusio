-- Unit tests for estimate_query_cost, Query.rateLimit, and Query.viewer.
-- Run: sh redbean.com -i test/graphql-ratelimit-viewer.lua
-- ============================================================

-- Stub Redbean HTTP context APIs needed by http.lua and graphql_executor.lua.
-- luacheck: push
-- luacheck: globals SetStatus SetHeader Write GetBody
SetStatus = function(_code, _reason) end
SetHeader = function(_k, _v) end
Write = function(_s) end
GetBody = function()
  return nil
end
-- luacheck: pop

-- Redirect /zip/internal/ → internal/ so tests run without a Redbean zip context.
local _real_dofile = dofile
function dofile(path) -- luacheck: globals dofile
  if path and path:match("^/zip/internal/") then
    return _real_dofile(path:sub(6))
  end
  return _real_dofile(path)
end

dofile("internal/graphql_parser.lua")
dofile("internal/graphql_schema_data.lua")
dofile("internal/graphql_schema.lua")
dofile("internal/http.lua")
dofile("internal/graphql_translators.lua")
dofile("internal/graphql_executor.lua")

dofile = _real_dofile -- luacheck: globals dofile

-- ============================================================
-- Assertion helpers
-- ============================================================

local PASS, FAIL = 0, 0

local function ok(cond, msg)
  if cond then
    PASS = PASS + 1
    io.write("PASS  " .. msg .. "\n")
  else
    FAIL = FAIL + 1
    io.write("FAIL  " .. msg .. "\n")
  end
end

local function eq(a, b, msg)
  ok(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end

-- Build a minimal execution context.
local function make_ctx()
  return { errors = {}, path = {} }
end

-- Parse a query string and return the first OperationDefinition.
local function parse_op(src)
  local doc, err = graphql_parse(src)
  if not doc then
    error("parse failed: " .. tostring(err))
  end
  return doc.definitions[1]
end

-- ============================================================
-- estimate_query_cost
-- ============================================================

do -- no connection fields → minimum cost of 1
  local op = parse_op("{ viewer { login } }")
  local cost = estimate_query_cost(op, {})
  eq(cost, 1, "cost: no first/last args → minimum cost 1")
end

do -- single connection with first:10 → cost 10
  local op = parse_op("{ repositories(first: 10) { nodes { name } } }")
  local cost = estimate_query_cost(op, {})
  eq(cost, 10, "cost: single first:10 → cost 10")
end

do -- single connection with last:5 → cost 5
  local op = parse_op("{ repositories(last: 5) { nodes { name } } }")
  local cost = estimate_query_cost(op, {})
  eq(cost, 5, "cost: single last:5 → cost 5")
end

do -- two sibling connections → additive cost
  local op = parse_op(
    "{ a: repositories(first: 10) { nodes { name } } b: repositories(first: 5) { nodes { name } } }"
  )
  local cost = estimate_query_cost(op, {})
  eq(cost, 15, "cost: two sibling connections first:10+first:5 → cost 15")
end

do -- nested connection → multiplicative cost
  -- outer first:5, inner first:10 per outer item → 5 + 5*10 = 55
  local op =
    parse_op("{ repositories(first: 5) { nodes { issues(first: 10) { nodes { title } } } } }")
  local cost = estimate_query_cost(op, {})
  eq(cost, 55, "cost: nested first:5 * first:10 → cost 55")
end

do -- variable-backed first argument resolved from variables table
  local op = parse_op("query GetRepos($n: Int!) { repositories(first: $n) { nodes { name } } }")
  local cost = estimate_query_cost(op, { n = 20 })
  eq(cost, 20, "cost: variable first=$n (n=20) → cost 20")
end

do -- variable with default: unresolved variable (not in variables) → page_size stays 0
  -- When the variable has no value in the variables table, page_size stays 0
  -- and cost_ctx.variables is empty, so the cost falls through to minimum 1.
  local op = parse_op("query GetRepos($n: Int!) { repositories(first: $n) { nodes { name } } }")
  local cost = estimate_query_cost(op, {})
  eq(cost, 1, "cost: missing variable → minimum cost 1")
end

do -- InlineFragment is walked transparently
  local op = parse_op("{ ... on Query { repositories(first: 8) { nodes { name } } } }")
  local cost = estimate_query_cost(op, {})
  eq(cost, 8, "cost: inline fragment walked → cost 8")
end

do -- FragmentSpread is NOT walked (Phase 1 limitation) → minimum 1
  -- The operation is definitions[2] (after the fragment definition).
  local src = "fragment F on Query { repositories(first: 99) { nodes { name } } } { ...F }"
  local doc = graphql_parse(src)
  -- definitions[1] = FragmentDefinition, definitions[2] = OperationDefinition
  local op = doc.definitions[2]
  local cost = estimate_query_cost(op, {})
  eq(cost, 1, "cost: fragment spread not walked → minimum cost 1")
end

-- ============================================================
-- Query.rateLimit resolver
-- ============================================================

do -- returns expected fields with cost from ctx
  local ctx = make_ctx()
  ctx.rate_cost = 7
  local result = graphql_resolvers["Query.rateLimit"](nil, {}, ctx) -- luacheck: globals graphql_resolvers
  ok(result ~= nil, "rateLimit: returns a table")
  eq(result.cost, 7, "rateLimit: cost matches ctx.rate_cost")
  eq(result.used, 0, "rateLimit: used is 0")
  eq(result.nodeCount, 0, "rateLimit: nodeCount is 0")
  ok(type(result.limit) == "number" and result.limit > 0, "rateLimit: limit is a positive number")
  ok(result.limit == result.remaining, "rateLimit: remaining equals limit")
  ok(
    type(result.resetAt) == "string"
      and result.resetAt:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$") ~= nil,
    "rateLimit: resetAt is an ISO-8601 UTC string"
  )
end

do -- cost defaults to 1 when ctx.rate_cost is absent
  local ctx = make_ctx()
  local result = graphql_resolvers["Query.rateLimit"](nil, {}, ctx)
  eq(result.cost, 1, "rateLimit: cost defaults to 1 when ctx.rate_cost is nil")
end

do -- cost propagates through the graphql_handler via estimate_query_cost
  -- Issue a rateLimit query through the handler; cost should be 1 (no connection fields).
  local _last_body = ""
  local _saved_write = Write -- luacheck: globals Write
  Write = function(s) -- luacheck: globals Write
    _last_body = _last_body .. tostring(s)
  end
  local _saved_get_body = GetBody -- luacheck: globals GetBody
  GetBody = function() -- luacheck: globals GetBody
    return EncodeJson({ query = "{ rateLimit { cost remaining limit used nodeCount resetAt } }" })
  end
  graphql_handler() -- luacheck: globals graphql_handler
  Write = _saved_write -- luacheck: globals Write
  GetBody = _saved_get_body -- luacheck: globals GetBody
  local r = DecodeJson(_last_body)
  ok(r ~= nil, "rateLimit via handler: response is valid JSON")
  ok(r.errors == nil or #r.errors == 0, "rateLimit via handler: no errors")
  ok(r.data ~= nil, "rateLimit via handler: data present")
  ok(r.data.rateLimit ~= nil, "rateLimit via handler: rateLimit field present")
  eq(r.data.rateLimit.cost, 1, "rateLimit via handler: cost is 1 for no connection fields")
  eq(r.data.rateLimit.used, 0, "rateLimit via handler: used is 0")
end

-- ============================================================
-- Query.viewer resolver (via mock fetch_json)
-- ============================================================

-- make_fetch_stub: returns a fetch_json stub returning (ok, status, {}, json_body).
local function make_fetch_stub(status, json_body)
  return function(_path, _method, _body)
    if status == nil then
      return false, nil, nil, nil
    end
    return true, status, {}, json_body or "{}"
  end
end

-- The viewer resolver in backends/gitea.lua calls graphql_fetch_or_error against
-- the backend's fetch_json.  We test the resolver contract directly by constructing
-- a closure that mirrors the backend implementation, using a stubbed fetch_json.

local function make_viewer_resolver(fetch_stub)
  return function(_parent, _args, ctx)
    local data = graphql_fetch_or_error(fetch_stub, "http://host/user", ctx, nil) -- luacheck: globals graphql_fetch_or_error
    if not data then
      return nil
    end
    local u = graphql_translate_user(data) -- luacheck: globals graphql_translate_user
    u.isViewer = true
    return u
  end
end

do -- success: returns a User object with isViewer=true
  local fetch = make_fetch_stub(
    200,
    '{"login":"fido","avatar_url":"http://host/avatar","html_url":"http://host/fido","site_admin":false}'
  )
  local ctx = make_ctx()
  local resolver = make_viewer_resolver(fetch)
  local result = resolver(nil, {}, ctx)
  ok(result ~= nil, "viewer: 200 → result is non-nil")
  eq(result.__typename, "User", "viewer: __typename is User")
  eq(result.login, "fido", "viewer: login field matches upstream")
  ok(result.isViewer == true, "viewer: isViewer is true")
  eq(#ctx.errors, 0, "viewer: no errors on success")
end

do -- 401 → nil returned, FORBIDDEN error in ctx
  local fetch = make_fetch_stub(401, "")
  local ctx = make_ctx()
  local resolver = make_viewer_resolver(fetch)
  local result = resolver(nil, {}, ctx)
  ok(result == nil, "viewer: 401 → nil returned")
  eq(#ctx.errors, 1, "viewer: 401 → one error added")
  eq(ctx.errors[1].extensions.code, "FORBIDDEN", "viewer: 401 → FORBIDDEN error code")
end

do -- network failure → nil returned, INTERNAL_ERROR in ctx
  local fetch = make_fetch_stub(nil)
  local ctx = make_ctx()
  local resolver = make_viewer_resolver(fetch)
  local result = resolver(nil, {}, ctx)
  ok(result == nil, "viewer: network failure → nil returned")
  eq(#ctx.errors, 1, "viewer: network failure → one error added")
  eq(
    ctx.errors[1].extensions.code,
    "INTERNAL_ERROR",
    "viewer: network failure → INTERNAL_ERROR code"
  )
end

do -- isViewer is false on a regular graphql_translate_user call (not viewer resolver)
  local u = graphql_translate_user({ login = "bob", avatar_url = "", html_url = "" })
  ok(u ~= nil, "translate_user: returns a table")
  ok(u.isViewer == false, "translate_user: isViewer defaults to false")
end

-- ============================================================
-- Summary
-- ============================================================

io.write(string.format("\n%d passed, %d failed\n", PASS, FAIL))
if FAIL > 0 then
  os.exit(1)
end
