-- Application context constructor.
--
-- make_app(cfg) returns the single app context table for the process lifetime.
-- Fields are populated by .init.lua after the backend loads.
--
-- Fields:
--   config          — backend config table (same object as the global `config`)
--   backend_impl    — handler registry set by the backend at startup
--   capabilities    — provider capability modules; keyed by domain name (e.g.
--                     "repos", "users", "issues"); each value is a table of
--                     named operations (e.g. { get = fn, list = fn, ... }).
--                     Both REST handlers and GraphQL resolvers call into these
--                     to avoid duplicating fetch + translate + error logic.
--   allow_anonymous — auth-gate flag; true means unauthenticated requests are allowed

function make_app(cfg) -- luacheck: globals make_app
  return {
    config = cfg,
    backend_impl = {},
    capabilities = {},
    allow_anonymous = true,
  }
end
