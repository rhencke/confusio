-- Unit tests for Query.node, Query.nodes, and Query.repositoryOwner resolver dispatch.
-- Covers the dispatcher logic in graphql_executor.lua and the resolver contract.
-- Loaded by test/unit-graphql.lua; relies on shared state from the driver.
-- ============================================================

-- Globals provided by the driver (test/unit-graphql.lua):
-- luacheck: globals ok eq PASS FAIL graphql_resolvers encode_node_id decode_node_id

-- Build a minimal execution context (errors array, no path).
local function make_ctx()
  return { errors = {}, path = {} }
end

-- ============================================================
-- Query.node
-- ============================================================

do -- node: valid ID dispatches to node.TypeName resolver and returns its result
  local FIXED = { __typename = "Repository", id = "abc", nameWithOwner = "octocat/hello-world" }
  graphql_resolvers["node.Repository"] = function(_local_id, _ctx) -- luacheck: globals graphql_resolvers
    return FIXED
  end
  local repo_id = encode_node_id("Repository", "octocat/hello-world")
  local ctx = make_ctx()
  local result = graphql_resolvers["Query.node"](nil, { id = repo_id }, ctx)
  ok(result == FIXED, "Query.node: dispatches to node.Repository and returns its result")
  eq(#ctx.errors, 0, "Query.node: no errors for valid ID")
  graphql_resolvers["node.Repository"] = nil
end

do -- node: malformed ID returns nil and records an error
  local ctx = make_ctx()
  local result = graphql_resolvers["Query.node"](nil, { id = "not-valid-base64!!" }, ctx)
  ok(result == nil, "Query.node: malformed ID returns nil")
  ok(#ctx.errors > 0, "Query.node: malformed ID records an error")
  ok(
    ctx.errors[1].message:find("invalid node id") ~= nil,
    "Query.node: error message mentions 'invalid node id'"
  )
end

do -- node: missing id argument returns nil and records an error
  local ctx = make_ctx()
  local result = graphql_resolvers["Query.node"](nil, {}, ctx)
  ok(result == nil, "Query.node: missing id returns nil")
  ok(#ctx.errors > 0, "Query.node: missing id records an error")
end

do -- node: valid-format ID with unsupported type returns nil, no error
  local ctx = make_ctx()
  local unsupported_id = encode_node_id("Gist", "some-gist-id")
  -- Ensure there is no resolver for this type.
  graphql_resolvers["node.Gist"] = nil
  local result = graphql_resolvers["Query.node"](nil, { id = unsupported_id }, ctx)
  ok(result == nil, "Query.node: unsupported type returns nil")
  eq(#ctx.errors, 0, "Query.node: unsupported type produces no error")
end

do -- node: resolver that raises an error returns nil and records an internal error
  graphql_resolvers["node.Broken"] = function(_lid, _ctx)
    error("kaboom")
  end
  local broken_id = encode_node_id("Broken", "x")
  local ctx = make_ctx()
  local result = graphql_resolvers["Query.node"](nil, { id = broken_id }, ctx)
  ok(result == nil, "Query.node: resolver error returns nil")
  ok(#ctx.errors > 0, "Query.node: resolver error records an error")
  graphql_resolvers["node.Broken"] = nil
end

-- ============================================================
-- Query.nodes
-- ============================================================

do -- nodes: parallel array — one valid, one unsupported, one malformed
  local FIXED = { __typename = "User", id = "xyz", login = "octocat" }
  graphql_resolvers["node.User"] = function(_lid, _ctx)
    return FIXED
  end
  local user_id = encode_node_id("User", "octocat")
  local unsupported_id = encode_node_id("Gist", "g1")
  local malformed_id = "!!not-base64!!"
  local ctx = make_ctx()
  local results =
    graphql_resolvers["Query.nodes"](nil, { ids = { user_id, unsupported_id, malformed_id } }, ctx)
  ok(type(results) == "table", "Query.nodes: returns a table")
  -- results.n carries the explicit count; # would stop at the first nil slot.
  eq(results.n, 3, "Query.nodes: result length matches ids length")
  ok(results[1] == FIXED, "Query.nodes: valid ID resolves to the resolver result")
  ok(results[2] == nil, "Query.nodes: unsupported type resolves to nil")
  ok(results[3] == nil, "Query.nodes: malformed ID resolves to nil")
  eq(#ctx.errors, 0, "Query.nodes: no errors (null entries are not errors)")
  graphql_resolvers["node.User"] = nil
end

do -- nodes: missing ids argument returns empty array and records an error
  local ctx = make_ctx()
  local results = graphql_resolvers["Query.nodes"](nil, {}, ctx)
  ok(type(results) == "table", "Query.nodes: missing ids returns a table")
  eq(#results, 0, "Query.nodes: missing ids returns empty array")
  ok(#ctx.errors > 0, "Query.nodes: missing ids records an error")
end

do -- nodes: empty ids list returns empty array, no errors
  local ctx = make_ctx()
  local results = graphql_resolvers["Query.nodes"](nil, { ids = {} }, ctx)
  ok(type(results) == "table", "Query.nodes: empty ids returns a table")
  eq(#results, 0, "Query.nodes: empty ids returns empty array")
  eq(#ctx.errors, 0, "Query.nodes: empty ids no errors")
end

-- ============================================================
-- Query.repositoryOwner (mock resolver)
-- ============================================================
-- This tests the resolver contract as implemented by backends.  The mock
-- resolver below mimics what backends/gitea.lua registers, using a mocked
-- fetch_json to avoid real network calls.

do -- repositoryOwner: user login → __typename "User"
  local function mock_fetch_user(path, _method, _body)
    if path:find("/users/octocat") then
      return true, 200, {}, '{"login":"octocat","type":"User","avatar_url":"","html_url":""}'
    end
    return true, 404, {}, '{"message":"not found"}'
  end
  -- Wire up a standalone resolver closure (mirrors what backends/gitea.lua does).
  local function repo_owner_resolver(_parent, args, ctx)
    if not args.login then
      graphql_error(ctx, "repositoryOwner requires a login argument")
      return nil
    end
    local udata, _ = graphql_fetch(mock_fetch_user, "http://host/users/" .. args.login)
    if udata then
      return graphql_translate_user(udata)
    end
    local odata, _ = graphql_fetch(mock_fetch_user, "http://host/orgs/" .. args.login)
    if odata then
      return graphql_translate_org(odata)
    end
    return nil
  end
  local ctx = make_ctx()
  local result = repo_owner_resolver(nil, { login = "octocat" }, ctx)
  ok(result ~= nil, "repositoryOwner(user): result is non-nil")
  eq(result.__typename, "User", "repositoryOwner(user): __typename is User")
  eq(result.login, "octocat", "repositoryOwner(user): login is preserved")
  eq(#ctx.errors, 0, "repositoryOwner(user): no errors")
end

do -- repositoryOwner: org login (user lookup fails, org succeeds) → __typename "Organization"
  local function mock_fetch_org(path, _method, _body)
    if path:find("/users/myorg") then
      return true, 404, {}, '{"message":"not found"}'
    end
    if path:find("/orgs/myorg") then
      return true, 200, {}, '{"login":"myorg","type":"Organization","avatar_url":"","html_url":""}'
    end
    return true, 404, {}, '{"message":"not found"}'
  end
  local function repo_owner_resolver(_parent, args, ctx)
    if not args.login then
      graphql_error(ctx, "repositoryOwner requires a login argument")
      return nil
    end
    local udata, _ = graphql_fetch(mock_fetch_org, "http://host/users/" .. args.login)
    if udata then
      return graphql_translate_user(udata)
    end
    local odata, _ = graphql_fetch(mock_fetch_org, "http://host/orgs/" .. args.login)
    if odata then
      return graphql_translate_org(odata)
    end
    return nil
  end
  local ctx = make_ctx()
  local result = repo_owner_resolver(nil, { login = "myorg" }, ctx)
  ok(result ~= nil, "repositoryOwner(org): result is non-nil")
  eq(result.__typename, "Organization", "repositoryOwner(org): __typename is Organization")
  eq(result.login, "myorg", "repositoryOwner(org): login is preserved")
  eq(#ctx.errors, 0, "repositoryOwner(org): no errors")
end

do -- repositoryOwner: unknown login → nil, no error
  local function mock_fetch_none(_path, _method, _body)
    return true, 404, {}, '{"message":"not found"}'
  end
  local function repo_owner_resolver(_parent, args, ctx)
    if not args.login then
      graphql_error(ctx, "repositoryOwner requires a login argument")
      return nil
    end
    local udata, _ = graphql_fetch(mock_fetch_none, "http://host/users/" .. args.login)
    if udata then
      return graphql_translate_user(udata)
    end
    local odata, _ = graphql_fetch(mock_fetch_none, "http://host/orgs/" .. args.login)
    if odata then
      return graphql_translate_org(odata)
    end
    return nil
  end
  local ctx = make_ctx()
  local result = repo_owner_resolver(nil, { login = "nobody" }, ctx)
  ok(result == nil, "repositoryOwner(unknown): returns nil")
  eq(#ctx.errors, 0, "repositoryOwner(unknown): no error recorded")
end

-- ============================================================
-- node ID round-trip for Issue (verifies encode → decode → REST URL construction)
-- ============================================================

do -- Issue node ID round-trip: translate_issue sets id; decode recovers owner/repo/number
  -- Use graphql_translate_issue to get the ID as it's set in practice.
  local raw_issue = {
    id = 999,
    number = 42,
    title = "A bug",
    state = "open",
    labels = {},
    assignees = {},
    created_at = "2024-01-01T00:00:00Z",
    updated_at = "2024-01-01T00:00:00Z",
  }
  local translated = graphql_translate_issue(raw_issue, "octocat", "hello-world")
  ok(translated ~= nil, "Issue round-trip: translate_issue returned non-nil")

  local type_name, local_id = decode_node_id(translated.id)
  eq(type_name, "Issue", "Issue round-trip: decoded type is Issue")
  eq(local_id, "octocat/hello-world/42", "Issue round-trip: decoded local_id is owner/repo/number")

  -- Confirm the local_id is parse-able for a node resolver.
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  eq(owner, "octocat", "Issue round-trip: owner parsed from local_id")
  eq(repo, "hello-world", "Issue round-trip: repo parsed from local_id")
  eq(number, "42", "Issue round-trip: number parsed from local_id")
end
