-- Config defaults (global: backends/<name>.lua can read at startup)
-- base_url defaults to "" here; each backend sets its own default at load time
-- (after SCRIPTARGS are applied) if the user hasn't provided an explicit value.
config = {
  backend = "",
  base_url = "",
}

-- SCRIPTARGS (positional after --): first arg = backend, second = base_url.
local positional_keys = { "backend", "base_url" }
local pos_idx = 1
for _, a in ipairs(arg or {}) do
  if positional_keys[pos_idx] then
    config[positional_keys[pos_idx]] = a
    pos_idx = pos_idx + 1
  end
end

config.base_url = config.base_url:gsub("/$", "")

dofile("/zip/internal/http.lua")
dofile("/zip/internal/proxy.lua")
dofile("/zip/internal/transport.lua")
dofile("/zip/internal/translators.lua")
dofile("/zip/internal/graphql_parser.lua")
dofile("/zip/internal/graphql_schema_data.lua")
dofile("/zip/internal/graphql_schema.lua")
dofile("/zip/internal/graphql_executor.lua")
dofile("/zip/internal/graphql_translators.lua")
dofile("/zip/internal/families.lua")
dofile("/zip/internal/context.lua")

-- Build the initial app context.  backend_impl and backend_allow_anonymous are
-- global shims that backend and families code still write to directly; they are
-- synced into app after the backend loads so that subsequent tasks can migrate
-- each read site from the bare globals to app incrementally.
app = make_app(config)

-- backend_impl is global: set by backends/<name>.lua at startup.
backend_impl = {}
-- backend_allow_anonymous is global: backends that require sign-in set this to false
-- at startup (after checking the provider's API settings). Default: allow.
backend_allow_anonymous = true
if config.backend ~= "" then
  assert(config.backend:match("^[%a][%w_]*$"), "invalid backend name: " .. config.backend)
  dofile("/zip/backends/" .. config.backend .. ".lua")
end

-- Sync backend startup state into the app context.
app.backend_impl = backend_impl
app.allow_anonymous = backend_allow_anonymous

dofile("/zip/internal/defaults.lua")
dofile("/zip/internal/router.lua")
dofile("/zip/internal/catalog.lua")
dofile("/zip/internal/dispatch.lua")
