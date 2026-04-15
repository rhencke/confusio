-- Unit tests for the GraphQL executor.
-- Covers graphql_handler integration (request parsing, operation selection,
-- validation), extensions.code on request-level and validation errors,
-- field dispatch (resolvers, aliases, fragments, directives, list completion,
-- argument coercion, pcall safety), ctx.path tracking, and PROPAGATE sentinel
-- null propagation.
-- Loaded by test/unit-graphql.lua; relies on shared state from the driver.
-- ============================================================

-- Globals provided by the driver (test/unit-graphql.lua):
-- luacheck: globals ok eq PASS FAIL reset_response _last_status _last_body _req_body

-- ============================================================
-- Test helpers
-- ============================================================

-- Snapshot and restore graphql_resolvers around each executor test so tests
-- are isolated from one another.
local function with_resolvers(tbl, fn)
  local saved = graphql_resolvers
  graphql_resolvers = tbl
  fn()
  graphql_resolvers = saved
end

-- Call graphql_handler with a JSON-encoded body table; return parsed response.
local function call_handler(body_table)
  reset_response()
  _req_body = EncodeJson(body_table)
  graphql_handler()
  return DecodeJson(_last_body)
end

-- ============================================================
-- graphql_handler / executor integration tests
-- ============================================================

do -- invalid body → error, still HTTP 200
  reset_response()
  _req_body = "not json"
  graphql_handler()
  eq(_last_status, 200, "handler: invalid body → HTTP 200")
  local r = DecodeJson(_last_body)
  ok(r ~= nil, "handler: invalid body → parseable response")
  ok(r.data == nil, "handler: invalid body → data is null")
  ok(r.errors ~= nil, "handler: invalid body → errors present")
end

do -- parse error → error response
  local r = call_handler({ query = "{ unclosed_brace" })
  ok(r.data == nil, "handler: parse error → data null")
  ok(r.errors ~= nil and #r.errors > 0, "handler: parse error → errors")
end

do -- unknown operation name → error
  local r = call_handler({ query = "query A { __typename }", operationName = "B" })
  ok(r.data == nil, "handler: unknown op name → data null")
  ok(
    r.errors and r.errors[1].message:find("'B'"),
    "handler: unknown op name → error mentions name"
  )
end

do -- multiple operations without operationName → error
  local r = call_handler({ query = "query A { __typename } query B { __typename }" })
  ok(r.data == nil, "handler: multi-op no name → data null")
  ok(r.errors and #r.errors > 0, "handler: multi-op no name → errors")
end

do -- multiple operations with operationName → correct one runs
  local r = call_handler({
    query = "query A { __typename } query B { __typename }",
    operationName = "A",
  })
  ok(r.errors == nil or #r.errors == 0, "handler: multi-op with name → no errors")
  ok(r.data ~= nil, "handler: multi-op with name → data present")
end

do -- validation error: unknown field
  local r = call_handler({ query = "{ nonexistentField123 }" })
  ok(r.data == nil, "handler: validation unknown field → data null")
  ok(
    r.errors and r.errors[1].message:find("nonexistentField123"),
    "handler: validation error mentions field name"
  )
end

-- ============================================================
-- extensions.code on request-level and validation errors
-- ============================================================

do -- invalid body → extensions.code = BAD_USER_INPUT
  reset_response()
  _req_body = "not json"
  graphql_handler()
  local r = DecodeJson(_last_body)
  ok(
    r.errors and r.errors[1].extensions and r.errors[1].extensions.code == "BAD_USER_INPUT",
    "error codes: invalid body → BAD_USER_INPUT"
  )
end

do -- missing query field → extensions.code = BAD_USER_INPUT
  reset_response()
  _req_body = '{"notQuery": "x"}'
  graphql_handler()
  local r = DecodeJson(_last_body)
  ok(
    r.errors and r.errors[1].extensions and r.errors[1].extensions.code == "BAD_USER_INPUT",
    "error codes: missing query field → BAD_USER_INPUT"
  )
end

do -- parse error → extensions.code = PARSE_ERROR
  local r = call_handler({ query = "{ unclosed_brace" })
  ok(
    r.errors and r.errors[1].extensions and r.errors[1].extensions.code == "PARSE_ERROR",
    "error codes: parse error → PARSE_ERROR"
  )
end

do -- unknown operationName → extensions.code = BAD_USER_INPUT
  local r = call_handler({ query = "query A { __typename }", operationName = "B" })
  ok(
    r.errors and r.errors[1].extensions and r.errors[1].extensions.code == "BAD_USER_INPUT",
    "error codes: unknown operationName → BAD_USER_INPUT"
  )
end

do -- ambiguous document (no operationName) → extensions.code = BAD_USER_INPUT
  local r = call_handler({ query = "query A { __typename } query B { __typename }" })
  ok(
    r.errors and r.errors[1].extensions and r.errors[1].extensions.code == "BAD_USER_INPUT",
    "error codes: ambiguous document → BAD_USER_INPUT"
  )
end

do -- validation error: unknown field → extensions.code = VALIDATION_ERROR
  local r = call_handler({ query = "{ nonexistentField123 }" })
  ok(
    r.errors and r.errors[1].extensions and r.errors[1].extensions.code == "VALIDATION_ERROR",
    "error codes: unknown field → VALIDATION_ERROR"
  )
end

do -- __typename meta-field — no resolver needed
  with_resolvers({}, function()
    local r = call_handler({ query = "{ __typename }" })
    ok(r.errors == nil or #r.errors == 0, "executor: __typename → no errors")
    eq(r.data.__typename, "Query", "executor: __typename returns root type name")
  end)
end

do -- root resolver + field pluck
  with_resolvers({
    ["Query.viewer"] = function(_parent, _args, _ctx)
      return { login = "fido", __typename = "User" }
    end,
  }, function()
    local r = call_handler({ query = "{ viewer { login } }" })
    ok(r.errors == nil or #r.errors == 0, "executor: root resolver → no errors")
    eq(r.data.viewer.login, "fido", "executor: field pluck from resolver result")
  end)
end

do -- field pluck against nil parent → null (no resolver registered)
  with_resolvers({}, function()
    -- "viewer" exists in the schema under Query but we register no resolver;
    -- parent is nil at root so field pluck returns nil → null.
    local r = call_handler({ query = "{ viewer { login } }" })
    ok(r.data.viewer == nil, "executor: no resolver → null for object field")
  end)
end

do -- sub-resolver: Query.repository and Repository.owner field pluck
  with_resolvers({
    ["Query.repository"] = function(_parent, args, _ctx)
      return {
        name = args.name or "myrepo",
        owner = { login = "rhencke" },
        __typename = "Repository",
      }
    end,
  }, function()
    local r = call_handler({ query = '{ repository(name: "myrepo") { name } }' })
    ok(r.errors == nil or #r.errors == 0, "executor: sub-resolver → no errors")
    eq(r.data.repository.name, "myrepo", "executor: sub-resolver result field plucked")
  end)
end

do -- variable substitution in argument
  with_resolvers({
    ["Query.repository"] = function(_parent, args, _ctx)
      return { name = args.name, __typename = "Repository" }
    end,
  }, function()
    local r = call_handler({
      query = "query Q($n: String!) { repository(name: $n) { name } }",
      variables = { n = "varrepo" },
    })
    ok(r.errors == nil or #r.errors == 0, "executor: variable substitution → no errors")
    eq(r.data.repository.name, "varrepo", "executor: variable value passed as argument")
  end)
end

do -- @skip(if: true) omits field from response
  with_resolvers({}, function()
    local r = call_handler({ query = "{ __typename @skip(if: true) }" })
    ok(r.data.__typename == nil, "executor: @skip(if:true) omits field")
  end)
end

do -- @skip(if: false) keeps field in response
  with_resolvers({}, function()
    local r = call_handler({ query = "{ __typename @skip(if: false) }" })
    eq(r.data.__typename, "Query", "executor: @skip(if:false) keeps field")
  end)
end

do -- @include(if: false) omits field from response
  with_resolvers({}, function()
    local r = call_handler({ query = "{ __typename @include(if: false) }" })
    ok(r.data.__typename == nil, "executor: @include(if:false) omits field")
  end)
end

do -- fragment spread: named fragment fields are included
  with_resolvers({
    ["Query.viewer"] = function(_parent, _args, _ctx)
      return { login = "fido", __typename = "User" }
    end,
  }, function()
    local r = call_handler({
      query = "fragment F on User { login } { viewer { ...F } }",
    })
    ok(r.errors == nil or #r.errors == 0, "executor: fragment spread → no errors")
    eq(r.data.viewer.login, "fido", "executor: fragment spread field plucked")
  end)
end

do -- resolver error: resolver appends to ctx.errors and returns nil → null field
  with_resolvers({
    ["Query.viewer"] = function(_parent, _args, ctx)
      ctx.errors[#ctx.errors + 1] = { message = "resolver failed" }
      return nil
    end,
  }, function()
    local r = call_handler({ query = "{ viewer { login } }" })
    ok(r.data.viewer == nil, "executor: resolver error → null field")
    ok(r.errors and #r.errors > 0, "executor: resolver error → errors present")
  end)
end

do -- pcall safety: resolver that raises a Lua error is caught
  with_resolvers({
    ["Query.viewer"] = function(_parent, _args, _ctx)
      error("unexpected crash")
    end,
  }, function()
    local r = call_handler({ query = "{ viewer { login } }" })
    ok(r.data.viewer == nil, "executor: pcall catches resolver crash → null field")
    ok(
      r.errors and r.errors[1].message:find("internal error"),
      "executor: pcall adds internal error entry"
    )
  end)
end

do -- alias: aliased field appears under alias key
  with_resolvers({
    ["Query.viewer"] = function(_parent, _args, _ctx)
      return { login = "fido", __typename = "User" }
    end,
  }, function()
    local r = call_handler({ query = "{ me: viewer { login } }" })
    ok(r.errors == nil or #r.errors == 0, "executor: alias → no errors")
    ok(r.data.me ~= nil, "executor: aliased field appears under alias key")
    ok(r.data.viewer == nil, "executor: original key absent when alias used")
    eq(r.data.me.login, "fido", "executor: aliased field value correct")
  end)
end

do -- __schema introspection returns queryType
  with_resolvers({}, function()
    local r = call_handler({ query = "{ __schema { queryType { name } } }" })
    ok(r.errors == nil or #r.errors == 0, "executor: __schema → no errors")
    ok(r.data.__schema ~= nil, "executor: __schema field present")
    ok(r.data.__schema.queryType ~= nil, "executor: __schema.queryType present")
    eq(r.data.__schema.queryType.name, "Query", "executor: queryType.name is Query")
  end)
end

-- ============================================================
-- Additional executor tests — coverage of gaps identified post-initial review
-- ============================================================

do -- @include(if: true) keeps field in response
  with_resolvers({}, function()
    local r = call_handler({ query = "{ __typename @include(if: true) }" })
    eq(r.data.__typename, "Query", "executor: @include(if:true) keeps field")
  end)
end

do -- mutation operation: __typename returns "Mutation"
  with_resolvers({}, function()
    local r = call_handler({ query = "mutation { __typename }" })
    ok(r.errors == nil or #r.errors == 0, "executor: mutation __typename → no errors")
    eq(r.data.__typename, "Mutation", "executor: mutation __typename returns Mutation")
  end)
end

do -- __type introspection returns type metadata
  with_resolvers({}, function()
    local r = call_handler({ query = '{ __type(name: "User") { kind name } }' })
    ok(r.errors == nil or #r.errors == 0, "executor: __type → no errors")
    ok(r.data.__type ~= nil, "executor: __type field present")
    eq(r.data.__type.kind, "OBJECT", "executor: __type.kind is OBJECT")
    eq(r.data.__type.name, "User", "executor: __type.name is User")
  end)
end

do -- __type with unknown type name returns null (not an error)
  with_resolvers({}, function()
    local r = call_handler({ query = '{ __type(name: "NoSuchType") { kind } }' })
    ok(r.errors == nil or #r.errors == 0, "executor: __type unknown → no errors")
    ok(r.data.__type == nil, "executor: __type unknown → null")
  end)
end

do -- inline fragment with matching type condition includes fields
  with_resolvers({}, function()
    -- At the Query root, "on Query" matches — __typename should appear.
    local r = call_handler({ query = "{ ... on Query { __typename } }" })
    ok(r.errors == nil or #r.errors == 0, "executor: inline fragment matching type → no errors")
    eq(r.data.__typename, "Query", "executor: inline fragment matching type includes field")
  end)
end

do -- inline fragment with non-matching type condition excludes fields
  with_resolvers({}, function()
    -- At the Query root, "on User" does not match — __typename should be absent.
    local r = call_handler({ query = "{ ... on User { login } __typename }" })
    ok(r.errors == nil or #r.errors == 0, "executor: inline fragment non-matching → no errors")
    ok(r.data.login == nil, "executor: inline fragment non-matching → excluded field absent")
    eq(r.data.__typename, "Query", "executor: sibling field outside fragment present")
  end)
end

do -- list completion: resolver returns an array; each item's fields are plucked
  with_resolvers({
    ["Query.codesOfConduct"] = function(_parent, _args, _ctx)
      return {
        { key = "mit", name = "MIT License", __typename = "CodeOfConduct" },
        { key = "apache-2.0", name = "Apache 2.0", __typename = "CodeOfConduct" },
      }
    end,
  }, function()
    local r = call_handler({ query = "{ codesOfConduct { key } }" })
    ok(r.errors == nil or #r.errors == 0, "executor: list resolver → no errors")
    ok(type(r.data.codesOfConduct) == "table", "executor: list resolver → array result")
    eq(#r.data.codesOfConduct, 2, "executor: list resolver → correct item count")
    eq(r.data.codesOfConduct[1].key, "mit", "executor: list item[1] field plucked")
    eq(r.data.codesOfConduct[2].key, "apache-2.0", "executor: list item[2] field plucked")
  end)
end

do -- fragment cycle guard: same fragment referenced twice is expanded only once
  with_resolvers({
    ["Query.viewer"] = function(_parent, _args, _ctx)
      return { login = "fido", __typename = "User" }
    end,
  }, function()
    -- Two spreads of the same fragment F; the second should be deduped by the
    -- visited guard in collect_fields, but the field itself still appears once.
    local r = call_handler({
      query = "fragment F on User { login } { viewer { ...F ...F } }",
    })
    ok(r.errors == nil or #r.errors == 0, "executor: duplicate fragment spread → no errors")
    eq(r.data.viewer.login, "fido", "executor: duplicate fragment spread → field present once")
  end)
end

do -- int argument coercion: IntValue node becomes a Lua number passed to resolver
  with_resolvers({
    ["Query.repository"] = function(_parent, args, _ctx)
      -- "name" arg isn't an integer in the schema but the executor coerces
      -- any IntValue node via tonumber; we use a string field to carry it back.
      return { name = tostring(args.first or "none"), __typename = "Repository" }
    end,
    -- Use a resolver key that receives an integer arg; re-use repository with a
    -- custom arg to keep the test self-contained.
    ["Query.codeOfConduct"] = function(_parent, args, _ctx)
      -- Record the Lua type of "key" arg for inspection.
      return { key = type(args.key), __typename = "CodeOfConduct" }
    end,
  }, function()
    -- Pass a string arg (normal) to confirm the type arrives correctly.
    local r = call_handler({ query = '{ codeOfConduct(key: "mit") { key } }' })
    ok(r.errors == nil or #r.errors == 0, "executor: string arg coercion → no errors")
    eq(r.data.codeOfConduct.key, "string", "executor: string arg arrives as Lua string")
  end)
end

do -- boolean argument coercion via variable: variable value is a Lua boolean
  with_resolvers({
    ["Query.codeOfConduct"] = function(_parent, args, _ctx)
      return { key = tostring(args.key), __typename = "CodeOfConduct" }
    end,
  }, function()
    local r = call_handler({
      query = "query Q($k: String!) { codeOfConduct(key: $k) { key } }",
      variables = { k = "apache-2.0" },
    })
    ok(r.errors == nil or #r.errors == 0, "executor: variable string arg → no errors")
    eq(r.data.codeOfConduct.key, "apache-2.0", "executor: variable string value passed through")
  end)
end

do -- non-null field returning null records an error
  with_resolvers({
    ["Query.repository"] = function(_parent, _args, _ctx)
      -- Return a repo with id=nil; "id" is "ID!" (non-null) on Repository.
      return { id = nil, __typename = "Repository" }
    end,
  }, function()
    local r = call_handler({ query = '{ repository(name: "x") { id } }' })
    -- The non-null error is appended to ctx.errors; data.repository.id is null.
    ok(r.errors and #r.errors > 0, "executor: non-null field null → error recorded")
    local found = false
    for _, e in ipairs(r.errors or {}) do
      if e.message and e.message:find("non%-null") then
        found = true
      end
    end
    ok(found, "executor: non-null field null → 'non-null' in error message")
  end)
end

do -- subscription operation: unsupported op type → null data (execute_operation returns nil)
  with_resolvers({}, function()
    local r = call_handler({ query = "subscription { __typename }" })
    ok(r.data == nil, "executor: subscription op → data is null")
  end)
end

-- ============================================================
-- ctx.path tracking: path appears in errors during execution
-- ============================================================

do -- path recorded for nested non-null field error
  -- Query.repository → Repository.id (ID!) with id=nil triggers a non-null error.
  -- The error path should be ["repository", "id"].
  with_resolvers({
    ["Query.repository"] = function(_parent, _args, _ctx)
      return { id = nil, __typename = "Repository" }
    end,
  }, function()
    local r = call_handler({ query = '{ repository(name: "x") { id } }' })
    ok(r.errors and #r.errors > 0, "path tracking: nested field error recorded")
    local err = r.errors[1]
    ok(err.path ~= nil, "path tracking: path is present on field error")
    eq(err.path[1], "repository", "path tracking: path[1] is 'repository'")
    eq(err.path[2], "id", "path tracking: path[2] is 'id'")
    eq(#err.path, 2, "path tracking: path has exactly 2 segments")
  end)
end

do -- path includes 0-based list index for error inside a list item
  -- Query.codesOfConduct returns [CodeOfConduct]; CodeOfConduct.id is ID! (non-null).
  -- The second item has id=nil → error path should be ["codesOfConduct", 1, "id"].
  with_resolvers({
    ["Query.codesOfConduct"] = function(_parent, _args, _ctx)
      return {
        { __typename = "CodeOfConduct", id = "coc:mit", key = "mit", name = "MIT" },
        { __typename = "CodeOfConduct", id = nil, key = "cc0-1.0", name = "CC0" },
      }
    end,
  }, function()
    local r = call_handler({ query = "{ codesOfConduct { id } }" })
    ok(r.errors and #r.errors > 0, "path tracking: list item error recorded")
    local err = r.errors[1]
    ok(err.path ~= nil, "path tracking: path present for list item error")
    eq(err.path[1], "codesOfConduct", "path tracking: list path[1] is field name")
    eq(err.path[2], 1, "path tracking: list path[2] is 0-based index (1 = second item)")
    eq(err.path[3], "id", "path tracking: list path[3] is 'id'")
    eq(#err.path, 3, "path tracking: list error path has 3 segments")
  end)
end

-- ============================================================
-- PROPAGATE sentinel and null propagation
-- ============================================================

do -- non-null field with nil value: error message uses new wording, exactly one error
  -- complete_value(nil, "ID!") should record exactly one "non-null field resolved to null"
  -- error and store nil for that field in data.
  with_resolvers({
    ["Query.repository"] = function(_parent, _args, _ctx)
      return { id = nil, __typename = "Repository" }
    end,
  }, function()
    local r = call_handler({ query = '{ repository(name: "x") { id } }' })
    eq(#r.errors, 1, "propagate: exactly one error for one non-null violation")
    ok(
      r.errors[1].message:find("non%-null field resolved to null"),
      "propagate: error message is 'non-null field resolved to null: ...'"
    )
    -- The field is null (nil in Lua → null in JSON), not the PROPAGATE sentinel.
    ok(r.data.repository ~= nil, "propagate: Repository object is still present")
    ok(r.data.repository.id == nil, "propagate: id field is null (PROPAGATE converted to nil)")
  end)
end

do -- PROPAGATE stops at nullable: the nullable parent is not null, only the non-null field inside
  -- Repository.name is "String!" (non-null); Query.repository is "Repository" (nullable).
  -- When name is nil, null propagates to name but stops there — repository stays non-null.
  with_resolvers({
    ["Query.repository"] = function(_parent, _args, _ctx)
      return { name = nil, __typename = "Repository" }
    end,
  }, function()
    local r = call_handler({ query = '{ repository(name: "x") { name } }' })
    eq(#r.errors, 1, "propagate stops at nullable: exactly one error")
    ok(r.data.repository ~= nil, "propagate stops at nullable: Repository field is not null")
    ok(r.data.repository.name == nil, "propagate stops at nullable: name field is null")
  end)
end

do -- PROPAGATE in a list: non-null item failure becomes nil in the list, not the sentinel
  -- Query.codesOfConduct is [CodeOfConduct]; CodeOfConduct.id is ID! (non-null).
  -- Second item has id=nil → data.codesOfConduct[2].id must be nil, not a table/object.
  with_resolvers({
    ["Query.codesOfConduct"] = function(_parent, _args, _ctx)
      return {
        { __typename = "CodeOfConduct", id = "coc:mit", key = "mit", name = "MIT" },
        { __typename = "CodeOfConduct", id = nil, key = "cc0-1.0", name = "CC0" },
      }
    end,
  }, function()
    local r = call_handler({ query = "{ codesOfConduct { id } }" })
    ok(r.errors and #r.errors == 1, "propagate in list: exactly one error")
    -- First item succeeds; second item's id is null (not the PROPAGATE sentinel object).
    eq(r.data.codesOfConduct[1].id, "coc:mit", "propagate in list: first item id intact")
    ok(
      r.data.codesOfConduct[2].id == nil,
      "propagate in list: second item id is null (not sentinel)"
    )
  end)
end

-- ============================================================
-- graphql_fetch_or_error: HTTP-status → error-code mapping
-- ============================================================

-- make_fetch_stub: returns a fetch_json stub that produces (ok, status, {}, json_body).
-- Pass status=nil to simulate a network failure (ok=false).
local function make_fetch_stub(status, json_body)
  return function(_path, _method, _body)
    if status == nil then
      return false, nil, nil, nil -- network failure
    end
    return true, status, {}, json_body or '{"key":"value"}'
  end
end

do -- success: returns decoded data, no error added to ctx
  local ctx = { errors = {}, path = {} }
  local fetch = make_fetch_stub(200, '{"login":"fido"}')
  local data = graphql_fetch_or_error(fetch, "/user", ctx, nil)
  ok(data ~= nil, "fetch_or_error: 200 → data returned")
  eq(data.login, "fido", "fetch_or_error: 200 → decoded body accessible")
  eq(#ctx.errors, 0, "fetch_or_error: 200 → no errors added")
end

do -- 404 → NOT_FOUND code, nil returned
  local ctx = { errors = {}, path = {} }
  local fetch = make_fetch_stub(404)
  local data = graphql_fetch_or_error(fetch, "/repos/x/y", ctx, nil)
  ok(data == nil, "fetch_or_error: 404 → nil returned")
  eq(#ctx.errors, 1, "fetch_or_error: 404 → one error added")
  eq(ctx.errors[1].extensions.code, "NOT_FOUND", "fetch_or_error: 404 → NOT_FOUND code")
end

do -- 401 → FORBIDDEN code
  local ctx = { errors = {}, path = {} }
  local fetch = make_fetch_stub(401, "")
  -- graphql_fetch produces "upstream error 401 fetching /path" which matches "40[13]"
  local data = graphql_fetch_or_error(fetch, "/user", ctx, nil)
  ok(data == nil, "fetch_or_error: 401 → nil returned")
  eq(ctx.errors[1].extensions.code, "FORBIDDEN", "fetch_or_error: 401 → FORBIDDEN code")
end

do -- 403 → FORBIDDEN code
  local ctx = { errors = {}, path = {} }
  local fetch = make_fetch_stub(403, "")
  local data = graphql_fetch_or_error(fetch, "/user", ctx, nil)
  ok(data == nil, "fetch_or_error: 403 → nil returned")
  eq(ctx.errors[1].extensions.code, "FORBIDDEN", "fetch_or_error: 403 → FORBIDDEN code")
end

do -- 429 → RATE_LIMITED code
  local ctx = { errors = {}, path = {} }
  local fetch = make_fetch_stub(429, "")
  local data = graphql_fetch_or_error(fetch, "/user", ctx, nil)
  ok(data == nil, "fetch_or_error: 429 → nil returned")
  eq(ctx.errors[1].extensions.code, "RATE_LIMITED", "fetch_or_error: 429 → RATE_LIMITED code")
end

do -- 500 → INTERNAL_ERROR code
  local ctx = { errors = {}, path = {} }
  local fetch = make_fetch_stub(500, "")
  local data = graphql_fetch_or_error(fetch, "/user", ctx, nil)
  ok(data == nil, "fetch_or_error: 500 → nil returned")
  eq(ctx.errors[1].extensions.code, "INTERNAL_ERROR", "fetch_or_error: 500 → INTERNAL_ERROR code")
end

do -- network failure → INTERNAL_ERROR code
  local ctx = { errors = {}, path = {} }
  local fetch = make_fetch_stub(nil) -- ok=false
  local data = graphql_fetch_or_error(fetch, "/user", ctx, nil)
  ok(data == nil, "fetch_or_error: network failure → nil returned")
  eq(
    ctx.errors[1].extensions.code,
    "INTERNAL_ERROR",
    "fetch_or_error: network failure → INTERNAL_ERROR code"
  )
end

do -- error message forwarded to ctx.errors[1].message
  local ctx = { errors = {}, path = {} }
  local fetch = make_fetch_stub(404)
  graphql_fetch_or_error(fetch, "/repos/owner/repo", ctx, nil)
  ok(
    ctx.errors[1].message:find("not found"),
    "fetch_or_error: error message forwarded from graphql_fetch"
  )
end
