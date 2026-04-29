-- Config defaults (global: backends/<name>.lua can read at startup)
-- base_url defaults to "" here; each backend sets its own default at load time
-- (after SCRIPTARGS are applied) if the user hasn't provided an explicit value.
config = {
  backend = "",
  base_url = "",
  webhook_delivery_log_path = "webhook-deliveries.log",
  -- webhook_secrets: table mapping backend name → inbound signing secret.
  -- Populated by webhook_secret_file_BACKEND=/path SCRIPTARGS.
  -- Absent entry (or empty string) → trust-the-network for that backend.
  webhook_secrets = {},
}

-- read_secret_file: reads a signing secret from a file after verifying that
-- the file is owned by the current process's effective uid and has permissions
-- exactly 0600 (owner read+write only — no group or other access).
-- Trims trailing whitespace so `echo secret > file` works without surprises.
-- Calls error() on any violation; startup fails loudly rather than silently
-- falling through to trust-the-network mode with a bad or missing path.
local function read_secret_file(path)
  local st, stat_err = unix.stat(path) -- luacheck: globals unix
  if not st then
    error("webhook secret file not found: " .. path .. " (" .. tostring(stat_err) .. ")")
  end
  if st:uid() ~= unix.geteuid() then
    error(
      string.format(
        "webhook secret file %s must be owned by uid %d (got %d)",
        path,
        unix.geteuid(),
        st:uid()
      )
    )
  end
  local perm = st:mode() & 0x1FF -- lower 9 bits: rwxrwxrwx
  if perm ~= 0x180 then -- 0x180 = 0600 octal: owner rw, no group/other
    error(string.format("webhook secret file %s must have permissions 0600 (got %04o)", path, perm))
  end
  local f = assert(io.open(path, "r"))
  local secret = f:read("*a")
  f:close()
  return (secret:gsub("%s+$", ""))
end

-- SCRIPTARGS (positional after --):
--   First positional  = backend
--   Second positional = base_url
--
-- Key=value pairs (any arg containing "=") configure webhook options:
--   webhook_secret_file_BACKEND=/path — path to 0600 file with inbound signing secret
--   webhook_target=URL                — outbound delivery target URL
--   webhook_target_name=NAME          — logical outbound target name (default: default)
--   webhook_target_events=A,B,C      — comma-separated event filter (default: *)
--   webhook_target_shape=SHAPE       — delivery shape: "github" (default) or "confusio"
--   webhook_target_secret_file=/path — path to 0600 file with outbound HMAC signing secret
--   webhook_delivery_log_path=PATH   — structured delivery-attempt log path
local positional_keys = { "backend", "base_url" }
local pos_idx = 1
for _, a in ipairs(arg or {}) do
  local kv_key, kv_val = a:match("^([^=]+)=(.*)$")
  if kv_key then
    -- Key=value pair: webhook config.
    local wh_backend = kv_key:match("^webhook_secret_file_(.+)$")
    if wh_backend then
      config.webhook_secrets[wh_backend] = read_secret_file(kv_val)
    elseif kv_key == "webhook_target" then
      config.webhook_target = config.webhook_target or {}
      config.webhook_target.url = kv_val
    elseif kv_key == "webhook_target_name" then
      config.webhook_target = config.webhook_target or {}
      config.webhook_target.name = kv_val
    elseif kv_key == "webhook_target_events" then
      config.webhook_target = config.webhook_target or {}
      local events = {}
      for e in kv_val:gmatch("[^,]+") do
        events[#events + 1] = e
      end
      config.webhook_target.events = events
    elseif kv_key == "webhook_target_shape" then
      config.webhook_target = config.webhook_target or {}
      config.webhook_target.shape = kv_val
    elseif kv_key == "webhook_target_secret_file" then
      config.webhook_target = config.webhook_target or {}
      config.webhook_target.secret = read_secret_file(kv_val)
    elseif kv_key == "webhook_delivery_log_path" then
      config.webhook_delivery_log_path = kv_val
    end
  elseif positional_keys[pos_idx] then
    config[positional_keys[pos_idx]] = a
    pos_idx = pos_idx + 1
  end
end

config.base_url = config.base_url:gsub("/$", "")

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
dofile("/zip/internal/webhook_event.lua")

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
dofile("/zip/internal/util.lua")
dofile("/zip/internal/signing.lua")
dofile("/zip/internal/fanout.lua")
dofile("/zip/internal/deliver.lua")
dofile("/zip/internal/webhooks.lua")
dofile("/zip/internal/startup.lua")

app.route_match = route_match
app.path_known = path_known
app.webhook_receiver = make_webhook_receiver(app)

-- Register the single outbound target declared via webhook_target=URL at startup.
-- Silently ignored if missing or malformed (missing url, wrong type).
if config.webhook_target then
  config.webhook_target.delivery_log_path = config.webhook_delivery_log_path
  fanout_register_target(config.webhook_target)
end

-- Synthesize installation lifecycle events for GitHub-App-aware consumers.
-- Fires installation.created and installation_repositories.added to all registered
-- targets when a backend is configured.  When no targets are registered,
-- fanout_dispatch returns 0 immediately without attempting delivery.
synthesize_startup_events(config.backend, config.base_url)

OnHttpRequest = make_dispatcher(app)
