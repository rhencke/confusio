-- Unit tests for the GraphQL lexer and recursive-descent parser
-- (internal/graphql_parser.lua).
-- Run from project root: sh redbean.com -i test/unit-graphql.lua
-- ============================================================

-- Redirect /zip/internal/ to the internal/ directory so tests can load
-- internal modules without a Redbean zip context.
local _real_dofile = dofile
function dofile(path) -- luacheck: globals dofile
  if path and path:match("^/zip/internal/") then
    return _real_dofile(path:sub(6))
  end
  return _real_dofile(path)
end

-- Load module under test.
dofile("internal/graphql_parser.lua")

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
-- (graphql_parser tests will be added here)
-- ============================================================

-- ============================================================
-- Summary
-- ============================================================

io.write(string.format("\n%d passed, %d failed\n", PASS, FAIL))
if FAIL > 0 then
  os.exit(1)
end
