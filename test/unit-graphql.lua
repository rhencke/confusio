-- GraphQL unit test driver (interim stub).
-- All GraphQL tests have been extracted to test/graphql-*.lua standalone files.
-- This file retains the shared setup and will become the driver in the next task.
-- Run from project root: sh redbean.com -i test/unit-graphql.lua
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
dofile("internal/graphql_translators.lua") -- graphql_fetch, graphql_fetch_or_error, etc.

dofile = _real_dofile -- luacheck: globals dofile

-- ============================================================
-- Minimal assertion helpers
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

-- ============================================================
-- Sanity check: assertion helpers
-- ============================================================

ok(true, "test harness: ok(true) passes")
eq(1, 1, "test harness: eq(1, 1) passes")

-- ============================================================
-- Summary
-- ============================================================

io.write(string.format("\n%d passed, %d failed\n", PASS, FAIL))
if FAIL > 0 then
  os.exit(1)
end
