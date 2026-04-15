-- Unit tests for the GraphQL schema loader.
-- Covers graphql_schema_type, graphql_schema_field, graphql_schema_base_type,
-- graphql_schema_is_nonnull, graphql_schema_is_leaf, graphql_schema_expand_type,
-- graphql_introspect_type, and graphql_introspect_schema.
-- Loaded by test/unit-graphql.lua; relies on shared state from the driver.
-- ============================================================

-- Globals provided by the driver (test/unit-graphql.lua):
-- luacheck: globals ok eq PASS FAIL

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
