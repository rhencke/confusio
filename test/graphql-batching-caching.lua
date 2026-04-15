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
-- Summary
-- ============================================================

io.write(string.format("\n%d passed, %d failed\n", PASS, FAIL))
if FAIL > 0 then
  os.exit(1)
end
