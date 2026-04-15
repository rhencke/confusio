-- Unit tests for the GraphQL error model.
-- Covers respond_graphql (null-safe response envelope) and graphql_error
-- (error recorder: message, location, path snapshot, extensions.code).
-- Run: sh redbean.com -i test/graphql-errors.lua
-- ============================================================

-- Stub Redbean HTTP context APIs needed by http.lua and graphql_executor.lua.
-- luacheck: push
-- luacheck: globals SetStatus SetHeader Write GetBody
local _last_status, _last_body, _req_body
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
-- luacheck: pop

local function reset_response()
  _last_status = nil
  _last_body = ""
  _req_body = nil
end

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

-- ============================================================
-- respond_graphql: null-safe GraphQL response envelope
-- ============================================================

do -- data=nil, no errors → {"data":null}
  reset_response()
  respond_graphql(nil, nil)
  eq(_last_status, 200, "respond_graphql(nil,nil): status 200")
  eq(_last_body, '{"data":null}', "respond_graphql(nil,nil): body is {data:null}")
end

do -- data=nil, empty errors → {"data":null}
  reset_response()
  respond_graphql(nil, {})
  eq(_last_body, '{"data":null}', "respond_graphql(nil,{}): body is {data:null}")
end

do -- data=nil, non-empty errors → {"data":null,"errors":[...]}
  reset_response()
  respond_graphql(nil, { { message = "oops" } })
  ok(
    _last_body:match('^{"data":null,"errors":'),
    "respond_graphql(nil,errors): starts with {data:null,errors:"
  )
  ok(
    _last_body:find('"oops"', 1, true) ~= nil,
    "respond_graphql(nil,errors): contains error message"
  )
end

do -- data={}, no errors → {"data":{}} (not {"data":null})
  reset_response()
  respond_graphql({}, nil)
  eq(_last_status, 200, "respond_graphql({},nil): status 200")
  ok(_last_body:match('^{"data":'), "respond_graphql({},nil): starts with {data:")
  ok(not _last_body:find('"errors"', 1, true), "respond_graphql({},nil): no errors key")
end

do -- data=table with content, with errors → {"data":{...},"errors":[...]}
  reset_response()
  respond_graphql({ viewer = { login = "fido" } }, { { message = "partial" } })
  ok(_last_body:match('^{"data":'), "respond_graphql(data,errors): starts with {data:")
  ok(_last_body:find('"errors"', 1, true) ~= nil, "respond_graphql(data,errors): has errors key")
  ok(_last_body:find('"fido"', 1, true) ~= nil, "respond_graphql(data,errors): data is present")
end

do -- always HTTP 200, even when errors present (GraphQL spec)
  reset_response()
  respond_graphql(nil, { { message = "fatal" } })
  eq(_last_status, 200, "respond_graphql with errors: still HTTP 200")
end

-- ============================================================
-- graphql_error: error recorder
-- ============================================================

do -- basic error: message only, no location, no path, no code
  local ctx = { errors = {} }
  local ret = graphql_error(ctx, "something went wrong", nil, nil)
  ok(ret == nil, "graphql_error: returns nil")
  eq(#ctx.errors, 1, "graphql_error: one error recorded")
  eq(ctx.errors[1].message, "something went wrong", "graphql_error: message stored")
  ok(ctx.errors[1].locations == nil, "graphql_error: no locations when field_node is nil")
  ok(ctx.errors[1].path == nil, "graphql_error: no path when ctx.path absent")
  ok(ctx.errors[1].extensions == nil, "graphql_error: no extensions when code is nil")
end

do -- error with code → extensions.code
  local ctx = { errors = {} }
  graphql_error(ctx, "not found", nil, "NOT_FOUND")
  eq(ctx.errors[1].extensions.code, "NOT_FOUND", "graphql_error: extensions.code set")
end

do -- error with field_node location
  local ctx = { errors = {} }
  local node = { name = { line = 3, col = 7 } }
  graphql_error(ctx, "bad field", node, nil)
  ok(ctx.errors[1].locations ~= nil, "graphql_error: locations present when field_node has line")
  eq(ctx.errors[1].locations[1].line, 3, "graphql_error: location line")
  eq(ctx.errors[1].locations[1].column, 7, "graphql_error: location column")
end

do -- error with path snapshot
  local ctx = { errors = {}, path = { "repository", "issues", 0 } }
  graphql_error(ctx, "leaf error", nil, nil)
  ok(ctx.errors[1].path ~= nil, "graphql_error: path recorded")
  eq(ctx.errors[1].path[1], "repository", "graphql_error: path[1]")
  eq(ctx.errors[1].path[2], "issues", "graphql_error: path[2]")
  eq(ctx.errors[1].path[3], 0, "graphql_error: path[3]")
end

do -- path snapshot is a copy: mutating ctx.path does not change recorded path
  local ctx = { errors = {}, path = { "a", "b" } }
  graphql_error(ctx, "snap", nil, nil)
  ctx.path[1] = "mutated"
  eq(ctx.errors[1].path[1], "a", "graphql_error: path is a snapshot, not a reference")
end

do -- multiple errors accumulate
  local ctx = { errors = {} }
  graphql_error(ctx, "first", nil, nil)
  graphql_error(ctx, "second", nil, nil)
  eq(#ctx.errors, 2, "graphql_error: second error appended")
  eq(ctx.errors[2].message, "second", "graphql_error: second error message")
end

-- ============================================================
-- Summary
-- ============================================================

io.write(string.format("\n%d passed, %d failed\n", PASS, FAIL))
if FAIL > 0 then
  os.exit(1)
end
