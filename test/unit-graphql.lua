-- GraphQL unit test driver.
-- Sets up shared state once, then loads each sub-file.
-- Run from project root: sh redbean.com -i test/unit-graphql.lua
-- ============================================================

-- Globals set here and shared with sub-files loaded via dofile:
-- luacheck: globals SetStatus SetHeader Write GetBody reset_response
-- luacheck: globals _last_status _last_body _req_body
-- luacheck: globals PASS FAIL ok eq

-- Stub Redbean HTTP context APIs needed by http.lua and graphql_executor.lua.
-- These are globals so sub-files can reference them.
_last_status = nil
_last_body = nil
_req_body = nil
SetStatus = function(code, _reason)
  _last_status = code
end
SetHeader = function(_k, _v) end
Write = function(s)
  _last_body = (_last_body or "") .. tostring(s)
end
GetBody = function()
  return _req_body
end

function reset_response()
  _last_status = nil
  _last_body = ""
  _req_body = nil
end

-- Redirect /zip/internal/ to the internal/ directory so tests can load
-- internal modules without a Redbean zip context.
local _real_dofile = dofile
function dofile(path) -- luacheck: globals dofile
  if path and path:match("^/zip/internal/") then
    return _real_dofile(path:sub(6))
  end
  return _real_dofile(path)
end

-- Load modules under test.
dofile("internal/graphql_parser.lua")
dofile("internal/graphql_schema_data.lua")
dofile("internal/graphql_schema.lua")
dofile("internal/http.lua")
dofile("internal/graphql_executor.lua")
dofile("internal/graphql_translators.lua")

dofile = _real_dofile -- luacheck: globals dofile

-- ============================================================
-- Assertion helpers (globals so sub-files share state)
-- ============================================================

PASS, FAIL = 0, 0

function ok(cond, msg)
  if cond then
    PASS = PASS + 1
    io.write("PASS  " .. msg .. "\n")
  else
    FAIL = FAIL + 1
    io.write("FAIL  " .. msg .. "\n")
  end
end

function eq(a, b, msg)
  ok(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end

-- ============================================================
-- Sanity check: assertion helpers
-- ============================================================

ok(true, "test harness: ok(true) passes")
eq(1, 1, "test harness: eq(1, 1) passes")

-- ============================================================
-- Sub-files (each adds to the shared PASS/FAIL counters)
-- ============================================================

dofile("test/graphql-errors.lua")
dofile("test/graphql-executor.lua")

-- ============================================================
-- Summary
-- ============================================================

io.write(string.format("\n%d passed, %d failed\n", PASS, FAIL))
if FAIL > 0 then
  os.exit(1)
end
