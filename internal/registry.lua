-- Backend builder: the required API for registering REST handlers, GraphQL
-- resolvers, provider capability modules, inbound webhook event handlers,
-- normalized outbound webhook translators, and GitHub-shape outbound webhook
-- translators.
--
-- make_backend_builder() returns a builder.  A backend file calls b:rest(name, fn),
-- b:graphql(key, fn), b:capability(name, module), b:webhook(event, fn),
-- b:webhook_translator(event, fn), b:webhook_github_translator(event, fn), and
-- b:set_allow_anonymous(v) to declare its handlers, resolvers, capabilities,
-- webhook handlers, and metadata, then calls b:build() to commit them to the
-- app context or b:spec() to return a reusable backend spec table.
--
-- Capability modules are the shared domain layer consumed by both REST handlers and
-- GraphQL resolvers.  Each module is a table of named operations (e.g.
-- { get = fn, list = fn, update = fn, delete = fn }).  They live in app.backend.capabilities
-- keyed by domain name (e.g. "repos", "users", "issues").  Strip patterns do NOT
-- apply to capabilities — they are domain-level, not REST surface-level.
--
-- Webhook event handlers live in app.backend.webhooks keyed by the canonical event
-- name (e.g. "push", "issues", "pull_request").  The receiver pipeline calls
-- backend.webhooks[event](raw_payload) to normalise a forge event into confusio's
-- internal event model.  Strip patterns do NOT apply to webhook handlers.
--
-- Normalized outbound webhook translators live in app.backend.webhook_translators
-- keyed by the internal event name (e.g. "push", "issues", "pull_request").  The
-- confusio-shape delivery path calls translator(internal_event, fields) to build
-- the normalized delivery envelope.  When no translator exists, the shared
-- make_normalized_webhook_envelope fallback is used.
--
-- GitHub-shape outbound webhook translators live in
-- app.backend.webhook_github_translators keyed by the internal event name.  The
-- github-shape delivery path calls translator(internal_event, fields) to build a
-- GitHub-compatible payload body.  When no translator exists, the raw provider
-- payload is forwarded unchanged.
--
-- Direct assignment to app.backend.rest or graphql_resolvers is forbidden;
-- make validate-builders enforces this at CI time.
--
-- Backend specs are plain tables with rest/graphql/capabilities/webhooks fields.
-- Alias backends can inherit a root backend spec with setmetatable(alias,
-- { __index = root }) and can inherit individual handler tables the same way.
-- register_backend_spec() walks those __index chains and commits the resolved
-- spec to the app context.
--
-- Globals exported:
--   make_backend_builder   — builder factory; backends call this at load time
--   backend_strip_patterns — returns REST strip patterns for a family alias
--   register_backend_spec  — commits a returned backend spec table

local function iter_index_chain(tbl, visit)
  local chain = {}
  local cur = tbl
  while type(cur) == "table" do
    chain[#chain + 1] = cur
    local mt = getmetatable(cur)
    local index = mt and mt.__index
    cur = type(index) == "table" and index or nil
  end
  for i = #chain, 1, -1 do
    for key, value in pairs(chain[i]) do
      visit(key, value)
    end
  end
end

local function should_strip(name, strip)
  if strip then
    for _, pat in ipairs(strip) do
      if name:find(pat) then
        return true
      end
    end
  end
  return false
end

function backend_strip_patterns(name) -- luacheck: globals backend_strip_patterns
  for _, family in pairs(provider_families) do
    local alias = family.aliases and family.aliases[name]
    if alias then
      return alias.strip
    end
  end
  return nil
end

local function iter_spec_field(spec, field, visit)
  local chain = {}
  local cur = spec
  while type(cur) == "table" do
    chain[#chain + 1] = cur
    local mt = getmetatable(cur)
    local index = mt and mt.__index
    cur = type(index) == "table" and index or nil
  end
  for i = #chain, 1, -1 do
    local value = rawget(chain[i], field)
    if type(value) == "table" then
      iter_index_chain(value, visit)
    end
  end
end

function register_backend_spec(spec, strip) -- luacheck: globals register_backend_spec
  assert(type(spec) == "table", "backend spec must be a table")

  iter_spec_field(spec, "rest", function(name, fn)
    if not should_strip(name, strip) then
      app.backend.rest[name] = fn
    end
  end)
  iter_spec_field(spec, "graphql", function(key, fn)
    graphql_resolvers[key] = fn
  end)
  iter_spec_field(spec, "capabilities", function(name, module)
    app.backend.capabilities[name] = module
  end)
  iter_spec_field(spec, "webhooks", function(event, fn)
    app.backend.webhooks[event] = fn
  end)
  iter_spec_field(spec, "webhook_translators", function(event, fn)
    app.backend.webhook_translators[event] = fn
  end)
  iter_spec_field(spec, "webhook_github_translators", function(event, fn)
    app.backend.webhook_github_translators[event] = fn
  end)
  if spec.allow_anonymous ~= nil then
    app.allow_anonymous = spec.allow_anonymous
  end
end

function make_backend_builder() -- luacheck: globals make_backend_builder
  local b = {
    _rest = {},
    _graphql = {},
    _capabilities = {},
    _webhooks = {},
    _webhook_translators = {},
    _webhook_github_translators = {},
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

  -- Register an inbound webhook event handler.
  -- event: canonical event name (e.g. "push", "issues", "pull_request")
  -- fn:    normaliser function called with (raw_payload) — the decoded JSON body
  --        from the forge webhook POST.  Returns the confusio internal event model
  --        on success, or nil + error message on failure.
  -- Strip patterns do NOT apply to webhook handlers.
  -- Returns self for method chaining.
  function b:webhook(event, fn)
    self._webhooks[event] = fn
    return self
  end

  -- Register a normalized outbound webhook translator.
  -- event: internal event name (e.g. "push", "issues", "pull_request")
  -- fn:    translator function called with (internal_event, fields).  Returns the
  --        normalized delivery envelope for confusio-shape outbound delivery.
  -- Strip patterns do NOT apply to webhook translators.
  -- Returns self for method chaining.
  function b:webhook_translator(event, fn)
    self._webhook_translators[event] = fn
    return self
  end

  -- Register a GitHub-shape outbound webhook translator.
  -- event: internal event name (e.g. "push", "issues", "pull_request")
  -- fn:    translator function called with (internal_event, fields).  Returns the
  --        GitHub-compatible delivery payload for github-shape outbound delivery.
  -- Strip patterns do NOT apply to webhook translators.
  -- Returns self for method chaining.
  function b:webhook_github_translator(event, fn)
    self._webhook_github_translators[event] = fn
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

  -- Return a reusable backend spec without committing it to the app context.
  function b:spec()
    local spec = {
      rest = self._rest,
      graphql = self._graphql,
      capabilities = self._capabilities,
      webhooks = self._webhooks,
      webhook_translators = self._webhook_translators,
      webhook_github_translators = self._webhook_github_translators,
    }
    if self._anonymous ~= nil then
      spec.allow_anonymous = self._anonymous
    end
    return spec
  end

  -- Commit all registered handlers, resolvers, capabilities, and webhook handlers
  -- to the app context.
  --
  -- strip: optional array of Lua patterns; REST keys whose names match any pattern
  --        are silently omitted from the commit.  Alias backends pass the strip list
  --        from provider_families so that feature gaps are applied declaratively
  --        rather than by post-hoc mutation.  Strip patterns do NOT affect
  --        capabilities or webhook handlers.
  --
  -- After build() returns:
  --   app.backend.rest[name]         = fn     for each registered REST handler (unless stripped)
  --   graphql_resolvers[key]         = fn     for each registered GraphQL resolver
  --   app.backend.capabilities[name] = module for each registered capability module
  --   app.backend.webhooks[event]    = fn     for each registered webhook event handler
  --   app.backend.webhook_translators[event] = fn for each normalized webhook translator
  --   app.backend.webhook_github_translators[event] = fn for each GitHub-shape webhook translator
  --   app.allow_anonymous            = v      only when set_allow_anonymous was called
  function b:build(strip)
    register_backend_spec(self:spec(), strip)
  end

  return b
end
