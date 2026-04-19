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

-- CONFUSIO_WEBHOOK_SECRETS: optional JSON object mapping backend names to
-- webhook secrets.  Used by the test harness to configure signature
-- verification without recompiling; also useful for single-backend deployments
-- that prefer environment-variable configuration.
-- Example: CONFUSIO_WEBHOOK_SECRETS='{"gitea":"mysecret","gitlab":"othersecret"}'
local ws_env = os.getenv("CONFUSIO_WEBHOOK_SECRETS")
if ws_env and ws_env ~= "" then
  local ok_ws, ws_parsed = pcall(DecodeJson, ws_env)
  if ok_ws and type(ws_parsed) == "table" then
    config.webhook_secrets = ws_parsed
  end
end

dofile("/zip/internal/http.lua")
dofile("/zip/internal/proxy.lua")
dofile("/zip/internal/transport.lua")
dofile("/zip/internal/capabilities.lua")
dofile("/zip/internal/translators.lua")
dofile("/zip/internal/graphql_parser.lua")
dofile("/zip/internal/graphql_schema_data.lua")
dofile("/zip/internal/graphql_schema.lua")
dofile("/zip/internal/graphql_executor.lua")
dofile("/zip/internal/graphql_translators.lua")
dofile("/zip/internal/families.lua")
dofile("/zip/internal/context.lua")
dofile("/zip/internal/registry.lua")

-- Build the app context.  Backends register handlers via make_backend_builder():b:build().
app = make_app(config)

-- Wire graphql_resolvers into app.backend.graphql so both paths reference the same
-- registry.  Backends writing to graphql_resolvers via b:build() and the executor
-- reading graphql_resolvers both see the same table as app.backend.graphql.
app.backend.graphql = graphql_resolvers

-- Register the backend-independent built-in resolvers (Query.node, Query.nodes,
-- Query.rateLimit) through the explicit composition point rather than as side effects
-- of loading graphql_executor.lua.
graphql_register_builtin_resolvers()

if config.backend ~= "" then
  assert(config.backend:match("^[%a][%w_]*$"), "invalid backend name: " .. config.backend)
  dofile("/zip/backends/" .. config.backend .. ".lua")
end

dofile("/zip/internal/defaults.lua")
dofile("/zip/internal/router.lua")
dofile("/zip/internal/catalog.lua")
dofile("/zip/internal/dispatch.lua")
dofile("/zip/internal/signing.lua")
dofile("/zip/internal/webhooks.lua")

app.route_match = route_match
app.path_known = path_known
app.webhook_receiver = make_webhook_receiver(app)
OnHttpRequest = make_dispatcher(app)
