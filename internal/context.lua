-- Application context constructor.
--
-- make_app(cfg) returns the single app context table for the process lifetime.
-- Fields are populated by .init.lua after the backend loads.
--
-- Fields:
--   config          — backend config table (same object as the global `config`)
--   backend_impl    — handler registry set by the backend at startup
--   allow_anonymous — auth-gate flag; true means unauthenticated requests are allowed

function make_app(cfg) -- luacheck: globals make_app
  return {
    config = cfg,
    backend_impl = {},
    allow_anonymous = true,
  }
end
