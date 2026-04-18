-- Backend builder: structured alternative to directly mutating global registries.
--
-- make_backend_builder() returns a builder.  A backend file calls b:rest(name, fn),
-- b:graphql(key, fn), and b:set_allow_anonymous(v) to declare its handlers and
-- metadata, then calls b:build() to commit them to the app context.
--
-- This is the new registration path.  The old path (directly assigning
-- app.backend_impl = {...} and graphql_resolvers["k"] = fn) remains supported
-- during migration and coexists without conflict since only one backend loads
-- per process.
--
-- Globals exported:
--   make_backend_builder   — builder factory; backends call this at load time

function make_backend_builder() -- luacheck: globals make_backend_builder
  local b = {
    _rest = {},
    _graphql = {},
    _anonymous = nil,
  }

  -- Register a REST handler.
  -- name: catalog handler name (e.g. "get_repo")
  -- fn:   handler function, called with route captures as positional args
  -- Returns self for method chaining.
  function b:rest(name, fn)
    self._rest[name] = fn
    return self
  end

  -- Register a GraphQL resolver.
  -- key: resolver key in graphql_resolvers (e.g. "Query.viewer", "node.Repository")
  -- fn:  resolver function (parent, args, ctx) or (local_id, ctx) for node resolvers
  -- Returns self for method chaining.
  function b:graphql(key, fn)
    self._graphql[key] = fn
    return self
  end

  -- Declare the anonymous-access policy for this backend.
  -- v: true = allow unauthenticated requests; false = require Authorization header
  -- When not called, app.allow_anonymous is left at its current value.
  -- Returns self for method chaining.
  function b:set_allow_anonymous(v)
    self._anonymous = v
    return self
  end

  -- Commit all registered handlers to the app context.
  --
  -- strip: optional array of Lua patterns; REST keys whose names match any pattern
  --        are silently omitted from the commit.  When omitted, b:build() falls back
  --        to app._family_strip, which load_family_backend sets before loading the
  --        root backend file so alias feature gaps are applied declaratively rather
  --        than by post-hoc mutation.
  --
  -- After build() returns:
  --   app.backend_impl[name] = fn  for each registered REST handler (unless stripped)
  --   graphql_resolvers[key]  = fn  for each registered GraphQL resolver
  --   app.allow_anonymous     = v   only when set_allow_anonymous was called
  function b:build(strip)
    -- Explicit strip arg takes precedence; fall back to the family-level strip
    -- declared by load_family_backend before the root backend file was loaded.
    local effective_strip = strip or app._family_strip
    for name, fn in pairs(self._rest) do
      local skip = false
      if effective_strip then
        for _, pat in ipairs(effective_strip) do
          if name:find(pat) then
            skip = true
            break
          end
        end
      end
      if not skip then
        app.backend_impl[name] = fn
      end
    end
    for key, fn in pairs(self._graphql) do
      graphql_resolvers[key] = fn
    end
    if self._anonymous ~= nil then
      app.allow_anonymous = self._anonymous
    end
  end

  return b
end
