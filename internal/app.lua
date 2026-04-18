-- App context builder (global).
--
-- make_app_context(cfg) collects the backend runtime globals that were
-- populated at startup into a single owned object.  Called by .init.lua
-- after all modules and the backend file are loaded.
--
-- Exported globals:
--   make_app_context(cfg)  — builds and returns an app context table
--
-- App context shape:
--   app.config                    — parsed SCRIPTARGS: { backend, base_url }
--   app.backend.name              — backend identifier string (e.g. "gitea")
--   app.backend.handlers          — REST handler table (same ref as backend_impl)
--   app.backend.resolvers         — GraphQL resolver table (same ref as graphql_resolvers)
--   app.backend.allow_anonymous   — whether this backend allows unauthenticated requests
--   app.allow_anonymous           — effective anonymous-access policy for this instance
--
-- NOTE: The globals backend_impl, graphql_resolvers, and backend_allow_anonymous
-- remain as compatibility shims until internal/dispatch.lua is migrated to read
-- from the app context (see next task: #203).  At that point the shims are removed.

function make_app_context(cfg) -- luacheck: globals make_app_context
  return {
    config = cfg,
    backend = {
      name = cfg.backend,
      handlers = backend_impl,
      resolvers = graphql_resolvers,
      allow_anonymous = backend_allow_anonymous,
    },
    allow_anonymous = backend_allow_anonymous,
  }
end
