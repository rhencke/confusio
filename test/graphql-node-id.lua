-- Unit tests for GQL-06: node ID encoding/decoding and graphql_fetch helpers.
-- Covers encode_node_id, decode_node_id, graphql_fetch, and graphql_fetch_with_headers.
-- Run: sh redbean.com -i test/graphql-node-id.lua
-- ============================================================

-- Redirect /zip/internal/ → internal/ so tests run without a Redbean zip context.
local _real_dofile = dofile
function dofile(path) -- luacheck: globals dofile
  if path and path:match("^/zip/internal/") then
    return _real_dofile(path:sub(6))
  end
  return _real_dofile(path)
end

dofile("internal/graphql_translators.lua")

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
-- encode_node_id / decode_node_id
-- ============================================================

do -- encode produces deterministic base64
  local id = encode_node_id("Repository", "octocat/hello-world")
  eq(id, EncodeBase64("Repository:octocat/hello-world"), "encode_node_id: deterministic base64")
end

do -- decode round-trips a Repository ID
  local encoded = encode_node_id("Repository", "octocat/hello-world")
  local t, local_id = decode_node_id(encoded)
  eq(t, "Repository", "decode_node_id: Repository type")
  eq(local_id, "octocat/hello-world", "decode_node_id: Repository local_id")
end

do -- decode round-trips an Issue ID (local_id contains slashes)
  local encoded = encode_node_id("Issue", "octocat/hello-world/42")
  local t, local_id = decode_node_id(encoded)
  eq(t, "Issue", "decode_node_id: Issue type")
  eq(local_id, "octocat/hello-world/42", "decode_node_id: Issue local_id with slashes")
end

do -- decode round-trips a User ID
  local encoded = encode_node_id("User", "octocat")
  local t, local_id = decode_node_id(encoded)
  eq(t, "User", "decode_node_id: User type")
  eq(local_id, "octocat", "decode_node_id: User local_id")
end

do -- decode nil → nil, nil
  local t, local_id = decode_node_id(nil)
  ok(t == nil, "decode_node_id(nil): type is nil")
  ok(local_id == nil, "decode_node_id(nil): local_id is nil")
end

do -- decode malformed base64 → nil, nil
  local t, local_id = decode_node_id("not valid base64!!")
  ok(t == nil, "decode_node_id(malformed): type is nil")
  ok(local_id == nil, "decode_node_id(malformed): local_id is nil")
end

do -- decode valid base64 but no colon separator → nil, nil
  local t, local_id = decode_node_id(EncodeBase64("NoColon"))
  ok(t == nil, "decode_node_id(no-colon): type is nil")
  ok(local_id == nil, "decode_node_id(no-colon): local_id is nil")
end

-- ============================================================
-- graphql_fetch
-- ============================================================

do -- success: returns decoded table and nil error
  local function mock_fetch(_path, _method, _body)
    return true, 200, {}, '{"name":"hello"}'
  end
  local data, err = graphql_fetch(mock_fetch, "http://example.com/repos/o/r")
  ok(data ~= nil, "graphql_fetch: success returns non-nil data")
  ok(err == nil, "graphql_fetch: success returns nil error")
  eq(data.name, "hello", "graphql_fetch: decoded field is correct")
end

do -- 404: returns nil and error string mentioning "not found"
  local function mock_fetch(_path, _method, _body)
    return true, 404, {}, '{"message":"not found"}'
  end
  local data, err = graphql_fetch(mock_fetch, "http://example.com/repos/o/r")
  ok(data == nil, "graphql_fetch: 404 returns nil data")
  ok(err ~= nil, "graphql_fetch: 404 returns error string")
  ok(err:find("not found") ~= nil, "graphql_fetch: 404 error mentions 'not found'")
end

do -- network error (pcall failed): returns nil and error string mentioning "network error"
  local function mock_fetch(_path, _method, _body)
    return false, "connection refused"
  end
  local data, err = graphql_fetch(mock_fetch, "http://example.com/repos/o/r")
  ok(data == nil, "graphql_fetch: network error returns nil data")
  ok(err ~= nil, "graphql_fetch: network error returns error string")
  ok(err:find("network error") ~= nil, "graphql_fetch: network error mentions 'network error'")
end

do -- non-2xx status (500): returns nil and error string mentioning the status code
  local function mock_fetch(_path, _method, _body)
    return true, 500, {}, '{"message":"server error"}'
  end
  local data, err = graphql_fetch(mock_fetch, "http://example.com/repos/o/r")
  ok(data == nil, "graphql_fetch: 500 returns nil data")
  ok(err ~= nil, "graphql_fetch: 500 returns error string")
  ok(err:find("500") ~= nil, "graphql_fetch: 500 error mentions status code")
end

do -- invalid JSON body: returns nil and error string
  local function mock_fetch(_path, _method, _body)
    return true, 200, {}, "not-json"
  end
  local data, err = graphql_fetch(mock_fetch, "http://example.com/repos/o/r")
  ok(data == nil, "graphql_fetch: invalid JSON returns nil data")
  ok(err ~= nil, "graphql_fetch: invalid JSON returns error string")
end

-- ============================================================
-- graphql_fetch_with_headers
-- ============================================================

do -- success: returns decoded table, headers, and nil error
  local function mock_fetch(_path, _method, _body)
    return true, 200, { ["X-Total"] = "42" }, '{"items":[]}'
  end
  local data, hdrs, err = graphql_fetch_with_headers(mock_fetch, "http://example.com/list")
  ok(data ~= nil, "graphql_fetch_with_headers: success returns non-nil data")
  ok(hdrs ~= nil, "graphql_fetch_with_headers: success returns non-nil headers")
  eq(hdrs["X-Total"], "42", "graphql_fetch_with_headers: X-Total header preserved")
  ok(err == nil, "graphql_fetch_with_headers: success returns nil error")
end

do -- 404: returns nil, nil, error string
  local function mock_fetch(_path, _method, _body)
    return true, 404, {}, '{"message":"not found"}'
  end
  local data, hdrs, err = graphql_fetch_with_headers(mock_fetch, "http://example.com/list")
  ok(data == nil, "graphql_fetch_with_headers: 404 returns nil data")
  ok(hdrs == nil, "graphql_fetch_with_headers: 404 returns nil headers")
  ok(err ~= nil, "graphql_fetch_with_headers: 404 returns error string")
end

do -- network error: returns nil, nil, error string
  local function mock_fetch(_path, _method, _body)
    return false, "connection refused"
  end
  local data, hdrs, err = graphql_fetch_with_headers(mock_fetch, "http://example.com/list")
  ok(data == nil, "graphql_fetch_with_headers: network error returns nil data")
  ok(hdrs == nil, "graphql_fetch_with_headers: network error returns nil headers")
  ok(err ~= nil, "graphql_fetch_with_headers: network error returns error string")
end

do -- nil headers from upstream: returns empty table instead of nil
  local function mock_fetch(_path, _method, _body)
    return true, 200, nil, '{"ok":true}'
  end
  local data, hdrs, err = graphql_fetch_with_headers(mock_fetch, "http://example.com/list")
  ok(data ~= nil, "graphql_fetch_with_headers: nil headers → data non-nil")
  ok(type(hdrs) == "table", "graphql_fetch_with_headers: nil headers → empty table returned")
  ok(err == nil, "graphql_fetch_with_headers: nil headers → no error")
end

-- ============================================================
-- Summary
-- ============================================================

io.write(string.format("\n%d passed, %d failed\n", PASS, FAIL))
if FAIL > 0 then
  os.exit(1)
end
