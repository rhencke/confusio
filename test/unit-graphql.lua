-- Unit tests for the GraphQL lexer, parser, and schema loader.
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

-- Load modules under test.
dofile("internal/graphql_parser.lua")
dofile("internal/graphql_schema_data.lua")
dofile("internal/graphql_schema.lua")

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
-- Test helpers
-- ============================================================

-- Parse src and assert success; return doc for further assertions.
local function must_parse(src, label)
  local doc, err = graphql_parse(src)
  ok(doc ~= nil, label .. ": parse succeeds")
  ok(err == nil, label .. ": no error returned")
  return doc or { definitions = {} }
end

-- Parse src and assert failure with a line:col error string.
local function must_fail(src, label)
  local doc, err = graphql_parse(src)
  ok(doc == nil, label .. ": parse returns nil")
  ok(err ~= nil and err:match("^%d+:%d+:") ~= nil, label .. ": error has line:col prefix")
  return err or ""
end

-- ============================================================
-- Sanity check: assertion helpers
-- ============================================================

ok(true, "test harness: ok(true) passes")
eq(1, 1, "test harness: eq(1, 1) passes")

-- ============================================================
-- graphql_tokenize: lexer smoke tests
-- ============================================================

-- Data-driven token sequence tests: each entry is { input, label, expected }
-- where expected is a flat list of { kind, value } pairs. EOF is checked
-- automatically after the last expected token.
local token_cases = {
  {
    "{ viewer }",
    "simple query tokens",
    { "PUNCT", "{", "NAME", "viewer", "PUNCT", "}" },
  },
  {
    "a , b",
    "commas ignored",
    { "NAME", "a", "NAME", "b" },
  },
  {
    "# this is a comment\n{ id }",
    "comments discarded",
    { "PUNCT", "{", "NAME", "id", "PUNCT", "}" },
  },
  {
    "...",
    "spread operator",
    { "PUNCT", "..." },
  },
  {
    "42 -7 3.14 1e10 -2.5E-3",
    "numbers",
    {
      "INT_VALUE",
      "42",
      "INT_VALUE",
      "-7",
      "FLOAT_VALUE",
      "3.14",
      "FLOAT_VALUE",
      "1e10",
      "FLOAT_VALUE",
      "-2.5E-3",
    },
  },
  {
    '"hello\\nworld"',
    "string escape",
    { "STRING_VALUE", "hello\nworld" },
  },
  {
    '"\\u0041"',
    "unicode escape \\u0041 → A",
    { "STRING_VALUE", "A" },
  },
}
for _, case in ipairs(token_cases) do
  local input, label, expected = case[1], case[2], case[3]
  local toks = graphql_tokenize(input)
  local n_expected = #expected / 2
  eq(#toks, n_expected + 1, "tokenize " .. label .. ": token count (including EOF)")
  for i = 1, n_expected do
    local kind, value = expected[i * 2 - 1], expected[i * 2]
    eq(toks[i].kind, kind, "tokenize " .. label .. ": toks[" .. i .. "] kind")
    eq(toks[i].value, value, "tokenize " .. label .. ": toks[" .. i .. "] value")
  end
  eq(toks[#toks].kind, "EOF", "tokenize " .. label .. ": last token is EOF")
end

do -- line/col tracking (not just kind/value, so tested separately)
  local toks = graphql_tokenize("{\n  login\n}")
  eq(toks[2].line, 2, "tokenize: 'login' is on line 2")
  eq(toks[2].col, 3, "tokenize: 'login' starts at col 3")
end

-- Data-driven tokenizer error tests: each entry is { input, label }.
local tokenize_error_cases = {
  { "{ viewer { ..UserFields } }", "two dots instead of three" },
  { "42abc", "int immediately followed by name char" },
}
for _, case in ipairs(tokenize_error_cases) do
  local input, label = case[1], case[2]
  local ok2, err = pcall(graphql_tokenize, input)
  ok(not ok2, "tokenize error: " .. label .. " raises error")
  ok(err ~= nil and err:match("%d+:%d+:") ~= nil, "tokenize error: " .. label .. " has line:col")
end

-- ============================================================
-- 1. Shorthand query
-- ============================================================

do
  local doc = must_parse("{ viewer { login } }", "shorthand query")
  local def = doc.definitions[1]
  eq(doc.kind, "Document", "shorthand: doc.kind")
  eq(#doc.definitions, 1, "shorthand: one definition")
  eq(def.kind, "OperationDefinition", "shorthand: def.kind")
  eq(def.operation, "query", "shorthand: operation is 'query'")
  ok(def.name == nil, "shorthand: name is nil (anonymous)")
  eq(#def.variable_definitions, 0, "shorthand: no variable definitions")
  eq(#def.directives, 0, "shorthand: no directives")
  eq(def.selection_set.kind, "SelectionSet", "shorthand: selection_set.kind")
  eq(#def.selection_set.selections, 1, "shorthand: one top-level selection")
  local viewer = def.selection_set.selections[1]
  eq(viewer.kind, "Field", "shorthand: selection is Field")
  eq(viewer.name.value, "viewer", "shorthand: field name 'viewer'")
  ok(viewer.alias == nil, "shorthand: viewer has no alias")
  eq(#viewer.arguments, 0, "shorthand: viewer has no arguments")
  ok(viewer.selection_set ~= nil, "shorthand: viewer has a sub-selection-set")
  local login = viewer.selection_set.selections[1]
  eq(login.kind, "Field", "shorthand: nested field is Field")
  eq(login.name.value, "login", "shorthand: nested field name 'login'")
  ok(login.selection_set == nil, "shorthand: login has no sub-selection-set (leaf)")
end

-- ============================================================
-- 2. Named query with variables
-- ============================================================

do
  local src = [[
    query GetRepo($owner: String!, $name: String!) {
      repository(owner: $owner, name: $name) {
        id
        description
      }
    }
  ]]
  local doc = must_parse(src, "named query with variables")
  local def = doc.definitions[1]
  eq(def.kind, "OperationDefinition", "named query: def.kind")
  eq(def.operation, "query", "named query: operation")
  eq(def.name.value, "GetRepo", "named query: name 'GetRepo'")
  eq(#def.variable_definitions, 2, "named query: two variable definitions")

  local v1 = def.variable_definitions[1]
  eq(v1.kind, "VariableDefinition", "named query: vardef kind")
  eq(v1.variable.kind, "Variable", "named query: variable.kind")
  eq(v1.variable.name.value, "owner", "named query: var name 'owner'")
  eq(v1.type.kind, "NonNullType", "named query: $owner type is NonNull")
  eq(v1.type.type.kind, "NamedType", "named query: $owner inner type is Named")
  eq(v1.type.type.name.value, "String", "named query: $owner inner type name 'String'")
  ok(v1.default_value == nil, "named query: $owner has no default")

  local v2 = def.variable_definitions[2]
  eq(v2.variable.name.value, "name", "named query: second var is 'name'")
  eq(v2.type.kind, "NonNullType", "named query: $name is NonNull")

  local repo = def.selection_set.selections[1]
  eq(repo.name.value, "repository", "named query: field 'repository'")
  eq(#repo.arguments, 2, "named query: repository has 2 arguments")
  eq(repo.arguments[1].name.value, "owner", "named query: arg[1] name 'owner'")
  eq(repo.arguments[1].value.kind, "Variable", "named query: arg[1] value is Variable")
  eq(repo.arguments[1].value.name.value, "owner", "named query: arg[1] variable 'owner'")
  eq(repo.arguments[2].name.value, "name", "named query: arg[2] name 'name'")
  eq(#repo.selection_set.selections, 2, "named query: repository has 2 sub-fields")
  eq(repo.selection_set.selections[1].name.value, "id", "named query: first sub-field 'id'")
end

-- ============================================================
-- 3. Mutation and subscription operation types
-- ============================================================

do
  local doc = must_parse(
    "mutation CreateIssue($title: String!) { createIssue(title: $title) { id } }",
    "mutation"
  )
  eq(doc.definitions[1].operation, "mutation", "mutation: operation type")
  eq(doc.definitions[1].name.value, "CreateIssue", "mutation: name 'CreateIssue'")
end

do
  local doc = must_parse(
    "subscription OnPush($repo: String!) { pushEvent(repo: $repo) { sha } }",
    "subscription"
  )
  eq(doc.definitions[1].operation, "subscription", "subscription: operation type")
  eq(doc.definitions[1].name.value, "OnPush", "subscription: name 'OnPush'")
end

-- ============================================================
-- 4. Fragment spread and inline fragment
-- ============================================================

do
  local src = [[
    {
      user(id: "1") {
        ...UserFields
        ... on Admin {
          permissions
        }
      }
    }

    fragment UserFields on User {
      name
      email
    }
  ]]
  local doc = must_parse(src, "fragments")
  eq(#doc.definitions, 2, "fragments: two definitions")

  local query = doc.definitions[1]
  eq(query.kind, "OperationDefinition", "fragments: first def is operation")
  local user = query.selection_set.selections[1]
  eq(user.name.value, "user", "fragments: field 'user'")
  eq(#user.selection_set.selections, 2, "fragments: user has 2 selections")

  local spread = user.selection_set.selections[1]
  eq(spread.kind, "FragmentSpread", "fragments: first is FragmentSpread")
  eq(spread.name.value, "UserFields", "fragments: spread name 'UserFields'")
  eq(#spread.directives, 0, "fragments: spread has no directives")

  local inline = user.selection_set.selections[2]
  eq(inline.kind, "InlineFragment", "fragments: second is InlineFragment")
  ok(inline.type_condition ~= nil, "fragments: inline has type condition")
  eq(inline.type_condition.kind, "NamedType", "fragments: type_condition is NamedType")
  eq(inline.type_condition.name.value, "Admin", "fragments: type condition 'Admin'")
  eq(#inline.selection_set.selections, 1, "fragments: inline has one field")
  eq(
    inline.selection_set.selections[1].name.value,
    "permissions",
    "fragments: inline field 'permissions'"
  )

  local frag = doc.definitions[2]
  eq(frag.kind, "FragmentDefinition", "fragments: second def is FragmentDefinition")
  eq(frag.name.value, "UserFields", "fragments: fragment name 'UserFields'")
  eq(frag.type_condition.kind, "NamedType", "fragments: fragment type_condition kind")
  eq(frag.type_condition.name.value, "User", "fragments: fragment type 'User'")
  eq(#frag.selection_set.selections, 2, "fragments: UserFields has 2 fields")
  eq(frag.selection_set.selections[1].name.value, "name", "fragments: UserFields field 'name'")
  eq(frag.selection_set.selections[2].name.value, "email", "fragments: UserFields field 'email'")
end

do -- inline fragment without type condition
  local src = "{ viewer { ... { login } } }"
  local doc = must_parse(src, "inline fragment without type condition")
  local inline = doc.definitions[1].selection_set.selections[1].selection_set.selections[1]
  eq(inline.kind, "InlineFragment", "no-type-cond inline: kind")
  ok(inline.type_condition == nil, "no-type-cond inline: type_condition is nil")
end

-- ============================================================
-- 5. All value kinds
-- ============================================================

do
  local src = [[
    {
      search(
        int_arg: 42
        neg_int: -5
        float_arg: 3.14
        neg_float: -2.5
        exp_float: 1e10
        str_arg: "hello world"
        bool_true: true
        bool_false: false
        null_arg: null
        enum_arg: ACTIVE
        list_arg: [1, 2, 3]
        obj_arg: {key: "value", num: 7}
      ) {
        id
      }
    }
  ]]
  local doc = must_parse(src, "all value kinds")
  local args = doc.definitions[1].selection_set.selections[1].arguments
  local by_name = {}
  for _, a in ipairs(args) do
    by_name[a.name.value] = a.value
  end

  eq(by_name.int_arg.kind, "IntValue", "value kinds: int_arg is IntValue")
  eq(by_name.int_arg.value, "42", "value kinds: int_arg value '42'")
  eq(by_name.neg_int.kind, "IntValue", "value kinds: neg_int is IntValue")
  eq(by_name.neg_int.value, "-5", "value kinds: neg_int value '-5'")
  eq(by_name.float_arg.kind, "FloatValue", "value kinds: float_arg is FloatValue")
  eq(by_name.float_arg.value, "3.14", "value kinds: float_arg value '3.14'")
  eq(by_name.neg_float.kind, "FloatValue", "value kinds: neg_float is FloatValue")
  eq(by_name.exp_float.kind, "FloatValue", "value kinds: exp_float is FloatValue")
  eq(by_name.str_arg.kind, "StringValue", "value kinds: str_arg is StringValue")
  eq(by_name.str_arg.value, "hello world", "value kinds: str_arg value")
  eq(by_name.bool_true.kind, "BooleanValue", "value kinds: bool_true is BooleanValue")
  eq(by_name.bool_true.value, true, "value kinds: bool_true value is Lua true")
  eq(by_name.bool_false.kind, "BooleanValue", "value kinds: bool_false is BooleanValue")
  eq(by_name.bool_false.value, false, "value kinds: bool_false value is Lua false")
  eq(by_name.null_arg.kind, "NullValue", "value kinds: null_arg is NullValue")
  eq(by_name.enum_arg.kind, "EnumValue", "value kinds: enum_arg is EnumValue")
  eq(by_name.enum_arg.value, "ACTIVE", "value kinds: enum_arg value 'ACTIVE'")
  eq(by_name.list_arg.kind, "ListValue", "value kinds: list_arg is ListValue")
  eq(#by_name.list_arg.values, 3, "value kinds: list has 3 elements")
  eq(by_name.list_arg.values[1].kind, "IntValue", "value kinds: list[1] is IntValue")
  eq(by_name.list_arg.values[2].value, "2", "value kinds: list[2] value '2'")
  eq(by_name.obj_arg.kind, "ObjectValue", "value kinds: obj_arg is ObjectValue")
  eq(#by_name.obj_arg.fields, 2, "value kinds: object has 2 fields")
  eq(by_name.obj_arg.fields[1].kind, "ObjectField", "value kinds: obj field kind")
  eq(by_name.obj_arg.fields[1].name.value, "key", "value kinds: obj field[1] name 'key'")
  eq(
    by_name.obj_arg.fields[1].value.kind,
    "StringValue",
    "value kinds: obj field[1] value is StringValue"
  )
  eq(by_name.obj_arg.fields[2].name.value, "num", "value kinds: obj field[2] name 'num'")
end

do -- variable as argument value
  local src = "query Q($x: Int) { field(arg: $x) { id } }"
  local doc = must_parse(src, "variable as argument value")
  local arg = doc.definitions[1].selection_set.selections[1].arguments[1]
  eq(arg.value.kind, "Variable", "variable arg: kind")
  eq(arg.value.name.value, "x", "variable arg: name 'x'")
end

do -- variable definition with default value
  local src = "query Q($limit: Int = 10) { items(limit: $limit) { id } }"
  local doc = must_parse(src, "variable default value")
  local vardef = doc.definitions[1].variable_definitions[1]
  ok(vardef.default_value ~= nil, "var default: default_value present")
  eq(vardef.default_value.kind, "IntValue", "var default: default_value is IntValue")
  eq(vardef.default_value.value, "10", "var default: default is '10'")
end

-- ============================================================
-- 6. Block string
-- ============================================================

do
  -- The block string below has 2-space indent on content lines.
  local src = '{ field(desc: """\n  hello\n  world\n""") { id } }'
  local doc = must_parse(src, "block string")
  local arg = doc.definitions[1].selection_set.selections[1].arguments[1]
  eq(arg.value.kind, "StringValue", "block string: value kind")
  eq(arg.value.value, "hello\nworld", "block string: common indent stripped, joined with \\n")
end

do -- block string with escaped triple-quote
  local src = '{ field(x: """before \\""" after""") { id } }'
  local doc = must_parse(src, "block string escaped triple-quote")
  local val = doc.definitions[1].selection_set.selections[1].arguments[1].value
  eq(val.value, 'before """ after', 'block string: escaped \\""" decoded to """')
end

do -- block string preserves blank lines inside content
  local src = '{ field(x: """\n  line1\n\n  line3\n""") { id } }'
  local doc = must_parse(src, "block string with interior blank line")
  local val = doc.definitions[1].selection_set.selections[1].arguments[1].value
  eq(val.value, "line1\n\nline3", "block string: interior blank line preserved")
end

-- ============================================================
-- 7. Aliases
-- ============================================================

do
  local src = [[
    {
      myRepo: repository(owner: "me", name: "stuff") {
        id
      }
      otherRepo: repository(owner: "you", name: "thing") {
        id
      }
    }
  ]]
  local doc = must_parse(src, "aliases")
  local sels = doc.definitions[1].selection_set.selections
  eq(#sels, 2, "aliases: two aliased fields")

  local f1 = sels[1]
  eq(f1.kind, "Field", "aliases: f1 kind")
  ok(f1.alias ~= nil, "aliases: f1 has an alias")
  eq(f1.alias.value, "myRepo", "aliases: f1 alias 'myRepo'")
  eq(f1.name.value, "repository", "aliases: f1 field name 'repository'")

  local f2 = sels[2]
  eq(f2.alias.value, "otherRepo", "aliases: f2 alias 'otherRepo'")
  eq(
    f2.name.value,
    "repository",
    "aliases: f2 field name 'repository' (same field, different alias)"
  )
end

-- ============================================================
-- 8. Directives (@skip, @include, custom)
-- ============================================================

do
  local src = [[
    query Dirs($withDetails: Boolean!) {
      viewer {
        login
        name @include(if: $withDetails)
        email @skip(if: false)
        bio @deprecated
      }
    }
  ]]
  local doc = must_parse(src, "directives")
  local fields = doc.definitions[1].selection_set.selections[1].selection_set.selections
  eq(#fields, 4, "directives: 4 fields under viewer")

  local login = fields[1]
  eq(#login.directives, 0, "directives: login has no directives")

  local name_field = fields[2]
  eq(#name_field.directives, 1, "directives: name has 1 directive")
  eq(name_field.directives[1].kind, "Directive", "directives: directive kind")
  eq(name_field.directives[1].name.value, "include", "directives: @include")
  eq(#name_field.directives[1].arguments, 1, "directives: @include has 1 arg")
  eq(name_field.directives[1].arguments[1].name.value, "if", "directives: @include arg name 'if'")
  eq(
    name_field.directives[1].arguments[1].value.kind,
    "Variable",
    "directives: @include arg is Variable"
  )

  local email = fields[3]
  eq(email.directives[1].name.value, "skip", "directives: @skip")
  eq(
    email.directives[1].arguments[1].value.kind,
    "BooleanValue",
    "directives: @skip arg is BooleanValue"
  )
  eq(email.directives[1].arguments[1].value.value, false, "directives: @skip(if: false)")

  local bio = fields[4]
  eq(bio.directives[1].name.value, "deprecated", "directives: @deprecated (no args)")
  eq(#bio.directives[1].arguments, 0, "directives: @deprecated has no arguments")
end

do -- directive on operation
  local src = "query Q @cached { viewer { login } }"
  local doc = must_parse(src, "directive on operation")
  eq(#doc.definitions[1].directives, 1, "op directive: one directive")
  eq(doc.definitions[1].directives[1].name.value, "cached", "op directive: @cached")
end

do -- directive on variable definition
  local src = "query Q($x: String @deprecated) { field(a: $x) { id } }"
  local doc = must_parse(src, "directive on variable definition")
  local vardef = doc.definitions[1].variable_definitions[1]
  eq(#vardef.directives, 1, "var directive: one directive")
  eq(vardef.directives[1].name.value, "deprecated", "var directive: @deprecated")
end

-- ============================================================
-- 9. Multiple operations in one document
-- ============================================================

do
  local src = [[
    query GetUser { viewer { login } }
    mutation UpdateUser($name: String!) { updateUser(name: $name) { id } }
    query GetRepo { repository(owner: "x", name: "y") { id } }
  ]]
  local doc = must_parse(src, "multiple operations")
  eq(#doc.definitions, 3, "multiple ops: three definitions")
  eq(doc.definitions[1].operation, "query", "multiple ops: first is query")
  eq(doc.definitions[1].name.value, "GetUser", "multiple ops: first name 'GetUser'")
  eq(doc.definitions[2].operation, "mutation", "multiple ops: second is mutation")
  eq(doc.definitions[2].name.value, "UpdateUser", "multiple ops: second name 'UpdateUser'")
  eq(doc.definitions[3].operation, "query", "multiple ops: third is query")
  eq(doc.definitions[3].name.value, "GetRepo", "multiple ops: third name 'GetRepo'")
end

-- ============================================================
-- 10. Type forms (Named, List, NonNull, nested)
-- ============================================================

do
  local src = "query Q($a: String, $b: [Int]!, $c: [[Boolean!]!]) { f { id } }"
  local doc = must_parse(src, "type forms")
  local vars = doc.definitions[1].variable_definitions
  -- $a: String  → NamedType
  eq(vars[1].type.kind, "NamedType", "types: $a is NamedType")
  eq(vars[1].type.name.value, "String", "types: $a name 'String'")
  -- $b: [Int]!  → NonNull(List(Named))
  eq(vars[2].type.kind, "NonNullType", "types: $b is NonNull")
  eq(vars[2].type.type.kind, "ListType", "types: $b inner is List")
  eq(vars[2].type.type.type.kind, "NamedType", "types: $b inner-inner is Named")
  -- $c: [[Boolean!]!]  → List(NonNull(List(NonNull(Named))))
  eq(vars[3].type.kind, "ListType", "types: $c is List")
  eq(vars[3].type.type.kind, "NonNullType", "types: $c[0] is NonNull")
  eq(vars[3].type.type.type.kind, "ListType", "types: $c[0][0] is List")
end

-- ============================================================
-- 11. String escape sequences
-- ============================================================

do
  local src = '{ f(x: "quote:\\" backslash:\\\\ tab:\\t newline:\\n") { id } }'
  local doc = must_parse(src, "string escapes")
  local val = doc.definitions[1].selection_set.selections[1].arguments[1].value.value
  ok(val:find('quote:"') ~= nil, 'string escapes: \\" decoded')
  ok(val:find("backslash:\\") ~= nil, "string escapes: \\\\ decoded")
  ok(val:find("\t") ~= nil, "string escapes: \\t decoded")
  ok(val:find("\n") ~= nil, "string escapes: \\n decoded")
end

-- ============================================================
-- Error cases
-- ============================================================

do -- unclosed brace
  local err = must_fail("{ viewer {", "unclosed brace")
  ok(err:match("%d+:%d+:") ~= nil, "unclosed brace: error has line:col")
end

do -- bad escape sequence in string
  must_fail('{ field(x: "bad \\z escape") { id } }', "bad escape")
end

do -- two dots (not three)
  must_fail("{ viewer { ..UserFields } }", "two dots")
end

do -- integer immediately followed by identifier char
  must_fail("{ field(x: 42abc) { id } }", "int+ident")
end

do -- 'fragment on' with no fragment name
  must_fail("fragment on User { id }", "fragment missing name")
end

do -- empty document
  must_fail("", "empty document")
end

do -- empty document (only whitespace)
  must_fail("   \n  \t  ", "whitespace-only document")
end

do -- empty selection set is a parse error
  must_fail("{ }", "empty selection set")
end

do -- unterminated string
  must_fail('{ field(x: "unterminated) { id } }', "unterminated string")
end

do -- minus not followed by digit
  must_fail("{ field(x: -) { id } }", "minus alone")
end

do -- float with no digits after decimal point
  must_fail("{ field(x: 1.) { id } }", "float no digits after dot")
end

do -- bad unicode escape (not 4 hex digits)
  must_fail('{ field(x: "\\u00GG") { id } }', "bad unicode escape")
end

-- luacheck: globals graphql_schema_type graphql_schema_field graphql_schema_base_type
-- luacheck: globals graphql_schema_is_leaf graphql_schema_is_nonnull graphql_schema_expand_type
-- luacheck: globals graphql_introspect_schema graphql_introspect_type

-- ============================================================
-- graphql_schema_type
-- ============================================================

do
  local t = graphql_schema_type("Repository")
  ok(t ~= nil, "schema_type: Repository is found")
  eq(t and t.kind, "OBJECT", "schema_type: Repository.kind is OBJECT")
end

do
  local t = graphql_schema_type("IssueState")
  ok(t ~= nil, "schema_type: IssueState is found")
  eq(t and t.kind, "ENUM", "schema_type: IssueState.kind is ENUM")
end

do
  local t = graphql_schema_type("NonExistent")
  ok(t == nil, "schema_type: NonExistent returns nil")
end

-- ============================================================
-- graphql_schema_field
-- ============================================================

do
  local f = graphql_schema_field("Repository", "issues")
  ok(f ~= nil, "schema_field: Repository.issues is found")
  eq(f and f.type, "IssueConnection!", "schema_field: Repository.issues type is IssueConnection!")
end

do -- meta-field __schema on Query
  local f = graphql_schema_field("Query", "__schema")
  ok(f ~= nil, "schema_field: Query.__schema returns synthetic meta-field")
  eq(f and f.name, "__schema", "schema_field: Query.__schema name")
  eq(f and f.type, "__Schema!", "schema_field: Query.__schema type is __Schema!")
end

do -- meta-field __type on Query
  local f = graphql_schema_field("Query", "__type")
  ok(f ~= nil, "schema_field: Query.__type returns synthetic meta-field")
  eq(f and f.name, "__type", "schema_field: Query.__type name")
  eq(f and f.type, "__Type", "schema_field: Query.__type type is __Type")
end

do -- meta-field __typename on any object
  local f = graphql_schema_field("Repository", "__typename")
  ok(f ~= nil, "schema_field: Repository.__typename returns synthetic meta-field")
  eq(f and f.name, "__typename", "schema_field: Repository.__typename name")
  eq(f and f.type, "String!", "schema_field: Repository.__typename type is String!")
end

do -- __schema not available on non-Query types
  local f = graphql_schema_field("Repository", "__schema")
  ok(f == nil, "schema_field: __schema is nil on non-Query type")
end

do -- unknown field returns nil
  local f = graphql_schema_field("Repository", "doesNotExist")
  ok(f == nil, "schema_field: unknown field returns nil")
end

do -- unknown type returns nil
  local f = graphql_schema_field("NoSuchType", "field")
  ok(f == nil, "schema_field: unknown type returns nil")
end

-- ============================================================
-- graphql_schema_base_type
-- ============================================================

do
  eq(graphql_schema_base_type("[Issue!]!"), "Issue", "base_type: [Issue!]! → Issue")
  eq(graphql_schema_base_type("String!"), "String", "base_type: String! → String")
  eq(
    graphql_schema_base_type("[IssueState]!"),
    "IssueState",
    "base_type: [IssueState]! → IssueState"
  )
  eq(graphql_schema_base_type("Repository"), "Repository", "base_type: Repository → Repository")
end

-- ============================================================
-- graphql_schema_is_nonnull
-- ============================================================

do
  ok(graphql_schema_is_nonnull("String!") == true, "is_nonnull: String! is non-null")
  ok(graphql_schema_is_nonnull("String") == false, "is_nonnull: String is nullable")
  ok(graphql_schema_is_nonnull("[Issue!]!") == true, "is_nonnull: [Issue!]! is non-null")
  ok(graphql_schema_is_nonnull("[Issue!]") == false, "is_nonnull: [Issue!] is nullable")
end

-- ============================================================
-- graphql_schema_is_leaf
-- ============================================================

do
  ok(graphql_schema_is_leaf("String!") == true, "is_leaf: String! is a leaf (scalar)")
  ok(graphql_schema_is_leaf("Repository!") == false, "is_leaf: Repository! is not a leaf (object)")
  ok(graphql_schema_is_leaf("IssueState") == true, "is_leaf: IssueState is a leaf (enum)")
  ok(
    graphql_schema_is_leaf("IssueConnection!") == false,
    "is_leaf: IssueConnection! is not a leaf (object)"
  )
  ok(graphql_schema_is_leaf("UnknownType") == false, "is_leaf: unknown type is not a leaf")
end

-- ============================================================
-- graphql_schema_expand_type
-- ============================================================

do -- "String!" → NON_NULL → SCALAR
  local e = graphql_schema_expand_type("String!")
  eq(e.kind, "NON_NULL", "expand_type String!: outer kind is NON_NULL")
  ok(e.name == nil, "expand_type String!: outer name is nil")
  ok(e.ofType ~= nil, "expand_type String!: ofType present")
  eq(e.ofType.kind, "SCALAR", "expand_type String!: inner kind is SCALAR")
  eq(e.ofType.name, "String", "expand_type String!: inner name is String")
  ok(e.ofType.ofType == nil, "expand_type String!: inner ofType is nil")
end

do -- "[Issue!]!" → NON_NULL → LIST → NON_NULL → OBJECT
  local e = graphql_schema_expand_type("[Issue!]!")
  eq(e.kind, "NON_NULL", "expand_type [Issue!]!: level 1 NON_NULL")
  eq(e.ofType.kind, "LIST", "expand_type [Issue!]!: level 2 LIST")
  eq(e.ofType.ofType.kind, "NON_NULL", "expand_type [Issue!]!: level 3 NON_NULL")
  eq(e.ofType.ofType.ofType.kind, "OBJECT", "expand_type [Issue!]!: level 4 OBJECT")
  eq(e.ofType.ofType.ofType.name, "Issue", "expand_type [Issue!]!: leaf name Issue")
end

-- ============================================================
-- graphql_introspect_type
-- ============================================================

do -- ENUM type
  local t = graphql_introspect_type("IssueState")
  ok(t ~= nil, "introspect_type: IssueState returns a table")
  eq(t and t.kind, "ENUM", "introspect_type: IssueState.kind is ENUM")
  eq(t and t.name, "IssueState", "introspect_type: IssueState.name")
  ok(t and t.enumValues ~= nil, "introspect_type: IssueState.enumValues present")
  local found_open = false
  for _, ev in ipairs(t and t.enumValues or {}) do
    if ev.name == "OPEN" then
      found_open = true
    end
  end
  ok(found_open, "introspect_type: IssueState.enumValues contains OPEN")
  local found_closed = false
  for _, ev in ipairs(t and t.enumValues or {}) do
    if ev.name == "CLOSED" then
      found_closed = true
    end
  end
  ok(found_closed, "introspect_type: IssueState.enumValues contains CLOSED")
end

do -- OBJECT type
  local t = graphql_introspect_type("Repository")
  ok(t ~= nil, "introspect_type: Repository returns a table")
  eq(t and t.kind, "OBJECT", "introspect_type: Repository.kind is OBJECT")
  eq(t and t.name, "Repository", "introspect_type: Repository.name")
  ok(t and t.fields ~= nil, "introspect_type: Repository.fields present")
  ok(t and t.interfaces ~= nil, "introspect_type: Repository.interfaces present")
  -- fields should be __Field introspection tables (have .type as expanded table)
  local found_name_field = false
  for _, f in ipairs(t and t.fields or {}) do
    if f.name == "name" then
      found_name_field = true
      ok(type(f.type) == "table", "introspect_type: Repository.name field.type is a table")
    end
  end
  ok(found_name_field, "introspect_type: Repository.fields contains 'name'")
end

do -- SCALAR type
  local t = graphql_introspect_type("String")
  ok(t ~= nil, "introspect_type: String returns a table")
  eq(t and t.kind, "SCALAR", "introspect_type: String.kind is SCALAR")
  eq(t and t.name, "String", "introspect_type: String.name")
  ok(t and t.fields == nil, "introspect_type: String.fields is nil (not an object)")
end

do -- INPUT_OBJECT type
  local t = graphql_introspect_type("CreateIssueInput")
  ok(t ~= nil, "introspect_type: CreateIssueInput returns a table")
  eq(t and t.kind, "INPUT_OBJECT", "introspect_type: CreateIssueInput.kind is INPUT_OBJECT")
  ok(t and t.inputFields ~= nil, "introspect_type: CreateIssueInput.inputFields present")
end

do -- unknown type returns nil
  local t = graphql_introspect_type("NoSuchType")
  ok(t == nil, "introspect_type: unknown type returns nil")
end

-- ============================================================
-- graphql_introspect_schema
-- ============================================================

do
  local s = graphql_introspect_schema()
  ok(s ~= nil, "introspect_schema: returns a table")
  ok(s.queryType ~= nil, "introspect_schema: queryType present")
  eq(s.queryType and s.queryType.name, "Query", "introspect_schema: queryType.name is Query")
  ok(s.mutationType ~= nil, "introspect_schema: mutationType present")
  eq(
    s.mutationType and s.mutationType.name,
    "Mutation",
    "introspect_schema: mutationType.name is Mutation"
  )
  ok(s.subscriptionType == nil, "introspect_schema: subscriptionType is nil")
  ok(s.types ~= nil, "introspect_schema: types present")
  ok(type(s.types) == "table", "introspect_schema: types is a table")
  ok(#s.types > 0, "introspect_schema: types is non-empty")
  ok(s.directives ~= nil, "introspect_schema: directives present")
  ok(type(s.directives) == "table", "introspect_schema: directives is a table")
end

do -- types array contains introspect_type-shaped entries
  local s = graphql_introspect_schema()
  -- Find Repository in the types list
  local repo_type = nil
  for _, t in ipairs(s.types or {}) do
    if t.name == "Repository" then
      repo_type = t
      break
    end
  end
  ok(repo_type ~= nil, "introspect_schema: types contains Repository")
  eq(
    repo_type and repo_type.kind,
    "OBJECT",
    "introspect_schema: Repository in types has kind OBJECT"
  )
end

do -- types array is sorted by name (stable)
  local s = graphql_introspect_schema()
  local prev = ""
  local sorted = true
  for _, t in ipairs(s.types or {}) do
    if t.name < prev then
      sorted = false
      break
    end
    prev = t.name
  end
  ok(sorted, "introspect_schema: types array is sorted by name")
end

do -- directives array entries have required __Directive fields
  local s = graphql_introspect_schema()
  local found_skip = false
  for _, d in ipairs(s.directives or {}) do
    if d.name == "skip" then
      found_skip = true
      ok(d.locations ~= nil, "introspect_schema: skip directive has locations")
      ok(d.args ~= nil, "introspect_schema: skip directive has args")
      ok(
        type(d.isRepeatable) == "boolean",
        "introspect_schema: skip directive.isRepeatable is boolean"
      )
    end
  end
  ok(found_skip, "introspect_schema: directives contains @skip")
end

-- ============================================================
-- Summary
-- ============================================================

io.write(string.format("\n%d passed, %d failed\n", PASS, FAIL))
if FAIL > 0 then
  os.exit(1)
end
