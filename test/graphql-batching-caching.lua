-- Unit tests for batch/APQ rejection, cost-limit enforcement, and request-scoped cache.
-- Run: sh redbean.com -i test/graphql-batching-caching.lua
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

-- run_handler: invoke graphql_handler() with a given request body, capturing
-- the HTTP status code and response body.  Returns (status, decoded_body).
local function run_handler(body_str)
  local captured_status = nil
  local captured_body = ""
  local saved_set_status = SetStatus -- luacheck: globals SetStatus
  local saved_write = Write -- luacheck: globals Write
  local saved_get_body = GetBody -- luacheck: globals GetBody
  SetStatus = function(code, _reason)
    captured_status = code
  end -- luacheck: globals SetStatus
  Write = function(s)
    captured_body = captured_body .. tostring(s)
  end -- luacheck: globals Write
  GetBody = function()
    return body_str
  end -- luacheck: globals GetBody
  graphql_handler() -- luacheck: globals graphql_handler
  SetStatus = saved_set_status -- luacheck: globals SetStatus
  Write = saved_write -- luacheck: globals Write
  GetBody = saved_get_body -- luacheck: globals GetBody
  return captured_status, DecodeJson(captured_body)
end

-- ============================================================
-- Batch rejection
-- ============================================================

do -- array body → HTTP 400, batching-not-supported message
  local body = '[{"query":"{ viewer { login } }"},{"query":"{ rateLimit { cost } }"}]'
  local status, r = run_handler(body)
  eq(status, 400, "batch: array body → HTTP 400")
  ok(r ~= nil, "batch: response is valid JSON")
  ok(r.errors ~= nil and #r.errors == 1, "batch: exactly one error in response")
  ok(
    type(r.errors[1].message) == "string" and r.errors[1].message:find("batching") ~= nil,
    "batch: error message mentions batching"
  )
end

do -- single-element array body also rejected (still a batch)
  local body = '[{"query":"{ viewer { login } }"}]'
  local status, r = run_handler(body)
  eq(status, 400, "batch: single-element array → HTTP 400")
  ok(r.errors ~= nil and #r.errors == 1, "batch: single-element array → one error")
end

-- ============================================================
-- APQ rejection
-- ============================================================

do -- APQ body (no query, has extensions.persistedQuery) → PERSISTED_QUERY_NOT_SUPPORTED
  local body = EncodeJson({
    extensions = {
      persistedQuery = { version = 1, sha256Hash = "abc123deadbeef" },
    },
  })
  local status, r = run_handler(body)
  eq(status, 200, "APQ: HTTP 200 (GraphQL-layer error)")
  ok(r ~= nil, "APQ: response is valid JSON")
  ok(r.errors ~= nil and #r.errors == 1, "APQ: exactly one error in response")
  eq(
    r.errors[1].extensions.code,
    "PERSISTED_QUERY_NOT_SUPPORTED",
    "APQ: error code is PERSISTED_QUERY_NOT_SUPPORTED"
  )
  ok(
    type(r.errors[1].message) == "string" and r.errors[1].message:find("Persisted") ~= nil,
    "APQ: message mentions persisted queries"
  )
end

do -- APQ body that also includes a query field is still rejected
  local body = EncodeJson({
    query = "{ viewer { login } }",
    extensions = {
      persistedQuery = { version = 1, sha256Hash = "abc123deadbeef" },
    },
  })
  local status, r = run_handler(body)
  eq(status, 200, "APQ+query: HTTP 200 (GraphQL-layer error)")
  eq(
    r.errors[1].extensions.code,
    "PERSISTED_QUERY_NOT_SUPPORTED",
    "APQ+query: still rejected with PERSISTED_QUERY_NOT_SUPPORTED"
  )
end

-- ============================================================
-- Cost-limit enforcement
-- ============================================================

-- Helper: parse source and return the first OperationDefinition.
local function parse_op(src)
  local doc, err = graphql_parse(src) -- luacheck: globals graphql_parse
  if not doc then
    error("parse failed: " .. tostring(err))
  end
  return doc.definitions[1]
end

do -- 100×100 nested connection → cost 10100 (100 outer + 100*100 inner)
  -- outer first:100 → 100; inner first:100 per outer item → 100*100 = 10000; total = 10100
  local op =
    parse_op("{ repositories(first: 100) { nodes { issues(first: 100) { nodes { title } } } } }")
  local cost = estimate_query_cost(op, {}) -- luacheck: globals estimate_query_cost
  ok(
    cost > 10000,
    "cost: 100×100 nested connection exceeds GRAPHQL_MAX_COST (got " .. tostring(cost) .. ")"
  )
end

do -- cost enforcement gate: query over ceiling → data:null, BAD_USER_INPUT, estimatedCost
  -- Stub estimate_query_cost to return 10001 so validation (run first) can pass on a
  -- simple schema-valid query, while the cost gate still fires as intended.
  local _saved = estimate_query_cost -- luacheck: globals estimate_query_cost
  estimate_query_cost = function(_op, _vars)
    return 10001
  end -- luacheck: globals estimate_query_cost
  local status, r = run_handler(EncodeJson({ query = "{ rateLimit { cost } }" }))
  estimate_query_cost = _saved -- luacheck: globals estimate_query_cost
  eq(status, 200, "cost-limit: HTTP 200 (GraphQL-layer rejection)")
  ok(r ~= nil, "cost-limit: response is valid JSON")
  ok(r.errors ~= nil and #r.errors == 1, "cost-limit: exactly one error")
  eq(r.errors[1].extensions.code, "BAD_USER_INPUT", "cost-limit: error code BAD_USER_INPUT")
  eq(r.errors[1].extensions.estimatedCost, 10001, "cost-limit: estimatedCost is 10001")
  eq(r.errors[1].extensions.maxAllowedCost, 10000, "cost-limit: maxAllowedCost is 10000")
  ok(
    type(r.errors[1].message) == "string" and r.errors[1].message:find("exceeds") ~= nil,
    "cost-limit: message mentions exceeds"
  )
end

do -- cost enforcement gate: cost exactly at ceiling (==10000) is allowed through
  local _saved = estimate_query_cost -- luacheck: globals estimate_query_cost
  estimate_query_cost = function(_op, _vars)
    return 10000
  end -- luacheck: globals estimate_query_cost
  local status, r = run_handler(EncodeJson({ query = "{ rateLimit { cost } }" }))
  estimate_query_cost = _saved -- luacheck: globals estimate_query_cost
  eq(status, 200, "cost-limit: cost==10000 → HTTP 200")
  ok(
    r.errors == nil or #r.errors == 0 or r.errors[1].extensions.code ~= "BAD_USER_INPUT",
    "cost-limit: cost==10000 allowed through (not rejected as cost-limit error)"
  )
end

do -- introspection query has cost 1, well below ceiling → allowed
  local body = EncodeJson({ query = "{ __schema { types { name } } }" })
  local status, r = run_handler(body)
  eq(status, 200, "cost-limit: introspection → HTTP 200")
  ok(
    r.errors == nil or #r.errors == 0 or r.errors[1].extensions.code ~= "BAD_USER_INPUT",
    "cost-limit: introspection not rejected by cost enforcement"
  )
  ok(r.data ~= nil, "cost-limit: introspection returns data")
end

-- ============================================================
-- graphql_cached
-- ============================================================
-- luacheck: globals graphql_cached

-- Build a minimal ctx with an empty cache (mirrors graphql_handler's ctx init).
local function make_cache_ctx()
  return { errors = {}, path = {}, cache = {} }
end

do -- first call invokes fetch_fn and returns its result
  local calls = 0
  local ctx = make_cache_ctx()
  local result = graphql_cached(ctx, "User:fido", function()
    calls = calls + 1
    return { login = "fido" }
  end)
  eq(calls, 1, "graphql_cached: first call invokes fetch_fn once")
  ok(result ~= nil and result.login == "fido", "graphql_cached: first call returns fetch result")
end

do -- second call with same key returns cached value without re-invoking fetch_fn
  local calls = 0
  local ctx = make_cache_ctx()
  local function fetch()
    calls = calls + 1
    return { login = "fido" }
  end
  graphql_cached(ctx, "User:fido", fetch)
  local result2 = graphql_cached(ctx, "User:fido", fetch)
  eq(calls, 1, "graphql_cached: second call does not invoke fetch_fn again")
  ok(result2 ~= nil and result2.login == "fido", "graphql_cached: second call returns cached value")
end

do -- nil result is cached via CACHE_MISS sentinel; second call returns nil without fetch
  local calls = 0
  local ctx = make_cache_ctx()
  local function fetch()
    calls = calls + 1
    return nil
  end
  local r1 = graphql_cached(ctx, "User:ghost", fetch)
  local r2 = graphql_cached(ctx, "User:ghost", fetch)
  eq(calls, 1, "graphql_cached: nil result cached; fetch_fn not called again")
  ok(r1 == nil, "graphql_cached: first call returns nil when fetch_fn returns nil")
  ok(r2 == nil, "graphql_cached: second call returns nil (from cache, not re-fetch)")
end

do -- different keys are independent; each invokes its own fetch_fn
  local calls_a, calls_b = 0, 0
  local ctx = make_cache_ctx()
  graphql_cached(ctx, "User:alice", function()
    calls_a = calls_a + 1
    return { login = "alice" }
  end)
  graphql_cached(ctx, "User:bob", function()
    calls_b = calls_b + 1
    return { login = "bob" }
  end)
  eq(calls_a, 1, "graphql_cached: key alice fetched once")
  eq(calls_b, 1, "graphql_cached: key bob fetched once (independent)")
end

do -- request-scoped isolation: two separate ctx tables share no cache state
  local calls = 0
  local function fetch()
    calls = calls + 1
    return { login = "fido" }
  end
  local ctx1 = make_cache_ctx()
  local ctx2 = make_cache_ctx()
  graphql_cached(ctx1, "User:fido", fetch)
  graphql_cached(ctx2, "User:fido", fetch)
  eq(calls, 2, "graphql_cached: separate ctx tables each invoke fetch_fn (no cross-request bleed)")
end

do -- ctx.cache is initialised by graphql_handler (verified via a handler round-trip)
  -- The handler sets ctx.cache = {}; resolvers that call graphql_cached must not panic.
  -- Use the rateLimit query (no backend needed) to exercise the full handler path.
  local status, r = run_handler(EncodeJson({ query = "{ rateLimit { cost } }" }))
  eq(status, 200, "graphql_cached: handler initialises ctx.cache (rateLimit round-trip → 200)")
  ok(r ~= nil and r.data ~= nil, "graphql_cached: handler response has data")
end

-- ============================================================
-- Summary
-- ============================================================

io.write(string.format("\n%d passed, %d failed\n", PASS, FAIL))
if FAIL > 0 then
  os.exit(1)
end
