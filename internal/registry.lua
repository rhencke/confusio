-- Backend builder: the required API for registering REST handlers, GraphQL
-- resolvers, and provider capability modules.
--
-- make_backend_builder() returns a builder.  A backend file calls b:rest(name, fn),
-- b:graphql(key, fn), b:capability(name, module), and b:set_allow_anonymous(v) to
-- declare its handlers, resolvers, capabilities, and metadata, then calls b:build()
-- to commit them to the app context.
--
-- Capability modules are the shared domain layer consumed by both REST handlers and
-- GraphQL resolvers.  Each module is a table of named operations (e.g.
-- { get = fn, list = fn, update = fn, delete = fn }).  They live in app.capabilities
-- keyed by domain name (e.g. "repos", "users", "issues").  Strip patterns do NOT
-- apply to capabilities — they are domain-level, not REST surface-level.
--
-- Direct assignment to app.backend_impl or graphql_resolvers is forbidden;
-- make validate-builders enforces this at CI time.
--
-- Globals exported:
--   make_backend_builder   — builder factory; backends call this at load time

function make_backend_builder() -- luacheck: globals make_backend_builder
  local b = {
    _rest = {},
    _graphql = {},
    _capabilities = {},
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

  -- Register a provider capability module.
  -- name:   domain name for this capability (e.g. "repos", "users", "issues")
  -- module: table of named operations consumed by both REST handlers and GraphQL
  --         resolvers (e.g. { get = fn, list = fn, update = fn, delete = fn })
  -- Strip patterns do NOT affect capabilities — they are domain-level only.
  -- Returns self for method chaining.
  function b:capability(name, module)
    self._capabilities[name] = module
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

  -- Commit all registered handlers, resolvers, and capabilities to the app context.
  --
  -- strip: optional array of Lua patterns; REST keys whose names match any pattern
  --        are silently omitted from the commit.  Alias backends pass the strip list
  --        from provider_families so that feature gaps are applied declaratively
  --        rather than by post-hoc mutation.  Strip patterns do NOT affect
  --        capabilities.
  --
  -- After build() returns:
  --   app.backend_impl[name]   = fn     for each registered REST handler (unless stripped)
  --   graphql_resolvers[key]   = fn     for each registered GraphQL resolver
  --   app.capabilities[name]   = module for each registered capability module
  --   app.allow_anonymous      = v      only when set_allow_anonymous was called
  function b:build(strip)
    for name, fn in pairs(self._rest) do
      local skip = false
      if strip then
        for _, pat in ipairs(strip) do
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
    for name, module in pairs(self._capabilities) do
      app.capabilities[name] = module
    end
    if self._anonymous ~= nil then
      app.allow_anonymous = self._anonymous
    end
  end

  return b
end
