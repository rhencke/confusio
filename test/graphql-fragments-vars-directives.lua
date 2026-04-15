-- Unit tests for GQL-05: fragment, variable, directive, and introspection handling.
-- Covers named/inline fragments, cycle guard, interface type conditions,
-- variable coercion and defaults, @skip/@include evaluation, and the three
-- introspection meta-fields including the standard IntrospectionQuery.
-- Run: sh redbean.com -i test/graphql-fragments-vars-directives.lua
-- ============================================================

-- Stub Redbean HTTP context APIs.
-- luacheck: push
-- luacheck: globals SetStatus SetHeader Write GetBody EncodeJson DecodeJson
local _last_body, _req_body
SetStatus = function(_code, _reason) end
SetHeader = function(_k, _v) end
Write = function(s)
  _last_body = (_last_body or "") .. tostring(s)
end
GetBody = function()
  return _req_body
end
-- luacheck: pop

local function reset_response()
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
-- Test helpers
-- ============================================================

-- Snapshot and restore graphql_resolvers around each test for isolation.
local function with_resolvers(tbl, fn)
  local saved = graphql_resolvers
  graphql_resolvers = tbl
  fn()
  graphql_resolvers = saved
end

-- Invoke graphql_handler with a JSON-encoded body; return the parsed response.
local function call_handler(body_table)
  reset_response()
  _req_body = EncodeJson(body_table)
  graphql_handler()
  return DecodeJson(_last_body)
end

-- Return true if the array `tbl` contains a value where pred(v) is true.
local function any(tbl, pred)
  for _, v in ipairs(tbl or {}) do
    if pred(v) then
      return true
    end
  end
  return false
end

-- ============================================================
-- Fragment tests
-- ============================================================

do -- named fragment spread: fields are resolved from the fragment
  with_resolvers({
    ["Query.viewer"] = function(_p, _a, _c)
      return { login = "fido", __typename = "User" }
    end,
  }, function()
    local r = call_handler({
      query = "fragment F on User { login } { viewer { ...F } }",
    })
    ok(r.errors == nil or #r.errors == 0, "fragment: named spread → no errors")
    eq(r.data.viewer.login, "fido", "fragment: named spread field resolved")
  end)
end

do -- inline fragment with matching type condition: fields are included
  with_resolvers({}, function()
    local r = call_handler({
      query = "{ ... on Query { __typename } }",
    })
    ok(r.errors == nil or #r.errors == 0, "fragment: inline matching type → no errors")
    eq(r.data.__typename, "Query", "fragment: inline matching type includes field")
  end)
end

do -- inline fragment with non-matching type condition: fields are excluded
  with_resolvers({}, function()
    -- At Query root, "on User" does not match — login should be absent.
    local r = call_handler({
      query = "{ ... on User { login } __typename }",
    })
    ok(r.errors == nil or #r.errors == 0, "fragment: inline non-matching type → no errors")
    ok(r.data.login == nil, "fragment: inline non-matching type excludes field")
    eq(r.data.__typename, "Query", "fragment: sibling outside non-matching fragment present")
  end)
end

do -- inline fragment with no type condition: fields always included
  with_resolvers({}, function()
    local r = call_handler({
      query = "{ ... { __typename } }",
    })
    ok(r.errors == nil or #r.errors == 0, "fragment: inline no type condition → no errors")
    eq(r.data.__typename, "Query", "fragment: inline no type condition includes field")
  end)
end

do -- nested fragment: fragment A spreads fragment B
  with_resolvers({
    ["Query.viewer"] = function(_p, _a, _c)
      return { login = "fido", __typename = "User" }
    end,
  }, function()
    local r = call_handler({
      query = "fragment B on User { login } fragment A on User { ...B } { viewer { ...A } }",
    })
    ok(r.errors == nil or #r.errors == 0, "fragment: nested spread → no errors")
    eq(r.data.viewer.login, "fido", "fragment: nested spread resolves inner field")
  end)
end

do -- fragment cycle guard: mutual recursion does not loop
  with_resolvers({
    ["Query.viewer"] = function(_p, _a, _c)
      return { login = "fido", __typename = "User" }
    end,
  }, function()
    -- A spreads B; B spreads A — second encounter of A is skipped by visited guard.
    -- This must complete without hanging and must not error.
    local r = call_handler({
      query = "fragment A on User { login ...B } fragment B on User { ...A } { viewer { ...A } }",
    })
    -- Cycle is silently guarded; login should still appear from A's own field.
    ok(r.errors == nil or #r.errors == 0, "fragment: cycle guard → no errors")
    eq(r.data.viewer.login, "fido", "fragment: cycle guard allows non-recursive field")
  end)
end

do -- fragment on interface type condition: included when type implements it
  with_resolvers({
    ["Query.viewer"] = function(_p, _a, _c)
      -- User implements Node, Actor, and others.
      return { id = "U_123", login = "fido", __typename = "User" }
    end,
  }, function()
    -- Fragment on Node (interface): included because User implements Node.
    local r = call_handler({
      query = "fragment N on Node { id } { viewer { ...N login } }",
    })
    ok(r.errors == nil or #r.errors == 0, "fragment: interface type condition → no errors")
    eq(r.data.viewer.id, "U_123", "fragment: interface condition includes fragment field")
    eq(r.data.viewer.login, "fido", "fragment: sibling field outside fragment present")
  end)
end

-- ============================================================
-- Variable tests
-- ============================================================

do -- variable used in argument: value comes from ctx.variables
  with_resolvers({
    ["Query.viewer"] = function(_p, _a, _c)
      return { login = "octocat", __typename = "User" }
    end,
    ["Query.repository"] = function(_p, args, _c)
      return { name = args.owner, __typename = "Repository" }
    end,
  }, function()
    local r = call_handler({
      query = 'query Q($owner: String!) { repository(owner: $owner, name: "x") { name } }',
      variables = { owner = "octocat" },
    })
    ok(r.errors == nil or #r.errors == 0, "variable: arg from variable → no errors")
    eq(r.data.repository.name, "octocat", "variable: arg value resolved from variables")
  end)
end

do -- missing variable with default: default value is applied
  with_resolvers({
    ["Query.repository"] = function(_p, args, _c)
      return { name = args.name, __typename = "Repository" }
    end,
  }, function()
    local r = call_handler({
      -- $n has default "defaultname"; variables is empty so default kicks in.
      query = 'query Q($n: String = "defaultname") { repository(name: $n) { name } }',
      variables = {},
    })
    ok(r.errors == nil or #r.errors == 0, "variable: missing with default → no errors")
    eq(r.data.repository.name, "defaultname", "variable: missing variable uses default")
  end)
end

do -- missing variable without default: resolver receives nil
  with_resolvers({
    ["Query.repository"] = function(_p, args, _c)
      -- name will be nil; return it stringified so we can assert.
      return { name = tostring(args.name), __typename = "Repository" }
    end,
  }, function()
    local r = call_handler({
      -- $n has no default; variables is empty → args.name is nil.
      query = "query Q($n: String) { repository(name: $n) { name } }",
      variables = {},
    })
    ok(r.errors == nil or #r.errors == 0, "variable: missing without default → no errors")
    eq(r.data.repository.name, "nil", "variable: missing without default → nil arg")
  end)
end

do -- variable in @skip directive argument
  with_resolvers({}, function()
    local r = call_handler({
      query = "query Q($dry: Boolean!) { __typename @skip(if: $dry) }",
      variables = { dry = true },
    })
    ok(r.errors == nil or #r.errors == 0, "variable: @skip(if: $dry=true) → no errors")
    ok(r.data.__typename == nil, "variable: @skip(if: $dry=true) skips field")
  end)
end

do -- variable in nested ObjectValue: resolved recursively from ctx.variables
  with_resolvers({
    ["Query.repository"] = function(_p, args, _c)
      local key = type(args.meta) == "table" and args.meta.owner or "missing"
      return { name = key, __typename = "Repository" }
    end,
  }, function()
    local r = call_handler({
      -- args.meta is an ObjectValue containing a Variable reference.
      query = 'query Q($v: String!) { repository(name: "x", meta: {owner: $v}) { name } }',
      variables = { v = "rhencke" },
    })
    ok(r.errors == nil or #r.errors == 0, "variable: nested ObjectValue → no errors")
    eq(r.data.repository.name, "rhencke", "variable: nested ObjectValue resolves variable")
  end)
end

-- ============================================================
-- Directive tests
-- ============================================================

do -- @skip(if: true): field is absent from response
  with_resolvers({}, function()
    local r = call_handler({ query = "{ __typename @skip(if: true) }" })
    ok(r.errors == nil or #r.errors == 0, "@skip: if:true → no errors")
    ok(r.data.__typename == nil, "@skip: if:true → field absent")
  end)
end

do -- @skip(if: false): field is present
  with_resolvers({}, function()
    local r = call_handler({ query = "{ __typename @skip(if: false) }" })
    ok(r.errors == nil or #r.errors == 0, "@skip: if:false → no errors")
    eq(r.data.__typename, "Query", "@skip: if:false → field present")
  end)
end

do -- @include(if: true): field is present
  with_resolvers({}, function()
    local r = call_handler({ query = "{ __typename @include(if: true) }" })
    ok(r.errors == nil or #r.errors == 0, "@include: if:true → no errors")
    eq(r.data.__typename, "Query", "@include: if:true → field present")
  end)
end

do -- @include(if: false): field is absent
  with_resolvers({}, function()
    local r = call_handler({ query = "{ __typename @include(if: false) }" })
    ok(r.errors == nil or #r.errors == 0, "@include: if:false → no errors")
    ok(r.data.__typename == nil, "@include: if:false → field absent")
  end)
end

do -- @skip(if:false) + @include(if:true) on same field: field is present
  with_resolvers({}, function()
    local r = call_handler({ query = "{ __typename @skip(if: false) @include(if: true) }" })
    ok(r.errors == nil or #r.errors == 0, "directive combo: skip:false+include:true → no errors")
    eq(r.data.__typename, "Query", "directive combo: skip:false+include:true → present")
  end)
end

do -- @skip(if:true) + @include(if:true) on same field: @skip wins, field absent
  with_resolvers({}, function()
    local r = call_handler({ query = "{ __typename @skip(if: true) @include(if: true) }" })
    ok(r.errors == nil or #r.errors == 0, "directive combo: skip:true+include:true → no errors")
    ok(r.data.__typename == nil, "directive combo: skip:true wins → field absent")
  end)
end

do -- unknown directive: silently ignored, field is present
  with_resolvers({}, function()
    local r = call_handler({ query = "{ __typename @unknownDirective }" })
    ok(r.errors == nil or #r.errors == 0, "directive: unknown → no errors")
    eq(r.data.__typename, "Query", "directive: unknown → field present")
  end)
end

do -- @skip on fragment spread: entire fragment excluded when if:true
  with_resolvers({
    ["Query.viewer"] = function(_p, _a, _c)
      return { login = "fido", __typename = "User" }
    end,
  }, function()
    local r = call_handler({
      query = "fragment F on User { login } { viewer { ...F @skip(if: true) } }",
    })
    ok(r.errors == nil or #r.errors == 0, "directive: @skip on spread → no errors")
    ok(
      r.data.viewer == nil or r.data.viewer.login == nil,
      "directive: @skip(if:true) on spread excludes fragment fields"
    )
  end)
end

do -- @include on fragment spread: fragment included when if:true
  with_resolvers({
    ["Query.viewer"] = function(_p, _a, _c)
      return { login = "fido", __typename = "User" }
    end,
  }, function()
    local r = call_handler({
      query = "fragment F on User { login } { viewer { ...F @include(if: true) } }",
    })
    ok(r.errors == nil or #r.errors == 0, "directive: @include on spread → no errors")
    eq(r.data.viewer.login, "fido", "directive: @include(if:true) on spread includes fields")
  end)
end

-- ============================================================
-- Introspection tests
-- ============================================================

do -- __typename on root: returns type name without any resolver call
  local resolver_called = false
  with_resolvers({
    ["Query.__typename"] = function(_p, _a, _c)
      resolver_called = true
      return "should not be called"
    end,
  }, function()
    local r = call_handler({ query = "{ __typename }" })
    ok(r.errors == nil or #r.errors == 0, "introspection: __typename → no errors")
    eq(r.data.__typename, "Query", "introspection: __typename returns root type name")
    ok(not resolver_called, "introspection: __typename does not invoke resolver")
  end)
end

do -- __schema { queryType { name } } returns "Query"
  with_resolvers({}, function()
    local r = call_handler({ query = "{ __schema { queryType { name } } }" })
    ok(r.errors == nil or #r.errors == 0, "introspection: __schema queryType → no errors")
    ok(r.data.__schema ~= nil, "introspection: __schema field present")
    ok(r.data.__schema.queryType ~= nil, "introspection: queryType present")
    eq(r.data.__schema.queryType.name, "Query", "introspection: queryType.name is Query")
  end)
end

do -- __schema { types { name } } contains "Repository" and "User"
  with_resolvers({}, function()
    local r = call_handler({ query = "{ __schema { types { name } } }" })
    ok(r.errors == nil or #r.errors == 0, "introspection: __schema types → no errors")
    ok(type(r.data.__schema.types) == "table", "introspection: types is an array")
    local has_repo = any(r.data.__schema.types, function(t)
      return t.name == "Repository"
    end)
    local has_user = any(r.data.__schema.types, function(t)
      return t.name == "User"
    end)
    ok(has_repo, "introspection: types contains Repository")
    ok(has_user, "introspection: types contains User")
  end)
end

do -- __schema { directives { name } } contains skip, include, deprecated
  with_resolvers({}, function()
    local r = call_handler({ query = "{ __schema { directives { name } } }" })
    ok(r.errors == nil or #r.errors == 0, "introspection: __schema directives → no errors")
    ok(type(r.data.__schema.directives) == "table", "introspection: directives is an array")
    local has_skip = any(r.data.__schema.directives, function(d)
      return d.name == "skip"
    end)
    local has_include = any(r.data.__schema.directives, function(d)
      return d.name == "include"
    end)
    local has_deprecated = any(r.data.__schema.directives, function(d)
      return d.name == "deprecated"
    end)
    ok(has_skip, "introspection: directives contains skip")
    ok(has_include, "introspection: directives contains include")
    ok(has_deprecated, "introspection: directives contains deprecated")
  end)
end

do -- __type(name: "Repository") returns kind = "OBJECT"
  with_resolvers({}, function()
    local r = call_handler({ query = '{ __type(name: "Repository") { kind name } }' })
    ok(r.errors == nil or #r.errors == 0, "introspection: __type Repository → no errors")
    ok(r.data.__type ~= nil, "introspection: __type field present")
    eq(r.data.__type.kind, "OBJECT", "introspection: __type(Repository).kind is OBJECT")
    eq(r.data.__type.name, "Repository", "introspection: __type(Repository).name is Repository")
  end)
end

do -- __type(name: "IssueState") { enumValues { name } } returns OPEN and CLOSED
  with_resolvers({}, function()
    local r = call_handler({ query = '{ __type(name: "IssueState") { enumValues { name } } }' })
    ok(r.errors == nil or #r.errors == 0, "introspection: __type IssueState → no errors")
    ok(r.data.__type ~= nil, "introspection: __type(IssueState) present")
    ok(type(r.data.__type.enumValues) == "table", "introspection: enumValues is an array")
    local has_open = any(r.data.__type.enumValues, function(ev)
      return ev.name == "OPEN"
    end)
    local has_closed = any(r.data.__type.enumValues, function(ev)
      return ev.name == "CLOSED"
    end)
    ok(has_open, "introspection: IssueState enumValues contains OPEN")
    ok(has_closed, "introspection: IssueState enumValues contains CLOSED")
  end)
end

do -- __type with unknown type name returns null
  with_resolvers({}, function()
    local r = call_handler({ query = '{ __type(name: "NonExistent") { kind } }' })
    ok(r.errors == nil or #r.errors == 0, "introspection: __type unknown → no errors")
    ok(r.data.__type == nil, "introspection: __type unknown → null")
  end)
end

do -- standard graphql-js IntrospectionQuery executes without error
  local introspection_query = [[
    query IntrospectionQuery {
      __schema {
        queryType { name }
        mutationType { name }
        subscriptionType { name }
        types { ...FullType }
        directives {
          name description locations
          args { ...InputValue }
        }
      }
    }
    fragment FullType on __Type {
      kind name description
      fields(includeDeprecated: true) {
        name description
        args { ...InputValue }
        type { ...TypeRef }
        isDeprecated deprecationReason
      }
      inputFields { ...InputValue }
      interfaces { ...TypeRef }
      enumValues(includeDeprecated: true) { name description isDeprecated deprecationReason }
      possibleTypes { ...TypeRef }
    }
    fragment InputValue on __InputValue {
      name description type { ...TypeRef } defaultValue
    }
    fragment TypeRef on __Type {
      kind name
      ofType { kind name
        ofType { kind name
          ofType { kind name
            ofType { kind name
              ofType { kind name
                ofType { kind name
                  ofType { kind name } } } } } } }
    }
  ]]

  with_resolvers({}, function()
    local r = call_handler({ query = introspection_query })
    ok(r.errors == nil or #r.errors == 0, "introspection: IntrospectionQuery → no errors")
    ok(r.data ~= nil, "introspection: IntrospectionQuery → data present")
    ok(r.data.__schema ~= nil, "introspection: IntrospectionQuery → __schema present")
    ok(r.data.__schema.queryType ~= nil, "introspection: IntrospectionQuery → queryType present")
    eq(
      r.data.__schema.queryType.name,
      "Query",
      "introspection: IntrospectionQuery → queryType.name is Query"
    )
    ok(
      type(r.data.__schema.types) == "table" and #r.data.__schema.types > 0,
      "introspection: IntrospectionQuery → types array non-empty"
    )
    ok(
      type(r.data.__schema.directives) == "table",
      "introspection: IntrospectionQuery → directives array present"
    )
  end)
end

-- ============================================================
-- Summary
-- ============================================================

io.write(string.format("\n%d passed, %d failed\n", PASS, FAIL))
if FAIL > 0 then
  os.exit(1)
end
