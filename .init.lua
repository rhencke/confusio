-- Config defaults (global: backends/<name>.lua can read at startup)
-- base_url defaults to "" here; each backend sets its own default at load time
-- (after SCRIPTARGS are applied) if the user hasn't provided an explicit value.
config = {
  backend = "",
  base_url = "",
  -- webhook_secrets: table mapping backend name → inbound signing secret.
  -- Populated by webhook_secret_file_BACKEND=/path SCRIPTARGS.
  -- Absent entry (or empty string) → trust-the-network for that backend.
  webhook_secrets = {},
}

dofile("/zip/internal/webhook_catalog.lua")
local webhook_event_names = webhook_catalog_event_names()

local supported_providers = {
  azuredevops = true,
  bitbucket = true,
  bitbucket_datacenter = true,
  codeberg = true,
  codecommit = true,
  confusio = true,
  forgejo = true,
  gerrit = true,
  gitblit = true,
  gitbucket = true,
  gitea = true,
  gitlab = true,
  gogs = true,
  harness = true,
  kallithea = true,
  launchpad = true,
  notabug = true,
  onedev = true,
  pagure = true,
  phabricator = true,
  radicle = true,
  rhodecode = true,
  sourceforge = true,
  sourcehut = true,
  tuleap = true,
}

local function set_config_once(field, value, source)
  local current = config[field]
  if current ~= nil and current ~= "" then
    error(
      string.format(
        "conflicting %s configuration: %s conflicts with existing value %s",
        source,
        value,
        current
      )
    )
  end
  config[field] = value
end

local function valid_url(url)
  return type(url) == "string"
    and url:match("^https?://[^%s/][^%s]*$") ~= nil
    and url:match("^https?://[^%s]*%.%.") == nil
end

local read_secret_file

local function split_event_filter(raw)
  if raw == "" then
    error("webhook target events must not be empty")
  end
  local events = {}
  for event in raw:gmatch("[^,+]+") do
    if event ~= "*" and not webhook_event_names[event] then
      error("unsupported webhook target event: " .. event)
    end
    events[#events + 1] = event
  end
  if #events == 0 then
    error("webhook target events must not be empty")
  end
  return events
end

local function parse_webhook_target_spec(spec)
  local target = {}
  local seen = {}
  for part in spec:gmatch("[^,]+") do
    local key, value = part:match("^([%w_]+)=(.*)$")
    if not key then
      error("malformed --webhook-target field: " .. part)
    end
    if seen[key] then
      error("duplicate --webhook-target field: " .. key)
    end
    seen[key] = true
    if value == "" then
      error("missing --webhook-target field value: " .. key)
    end
    if key == "name" then
      target.name = value
    elseif key == "url" then
      target.url = value
    elseif key == "shape" then
      target.shape = value
    elseif key == "events" then
      target.events = split_event_filter(value)
    elseif key == "secret" then
      target.secret = value
    elseif key == "secret_file" then
      target.secret = read_secret_file(value)
    else
      error("unsupported --webhook-target field: " .. key)
    end
  end
  if not target.name then
    error("--webhook-target requires name")
  end
  if not target.url then
    error("--webhook-target requires url")
  end
  if not valid_url(target.url) then
    error("invalid webhook target URL: " .. target.url)
  end
  target.shape = target.shape or "github"
  if target.shape ~= "github" and target.shape ~= "confusio" then
    error("unsupported webhook target shape: " .. target.shape)
  end
  target.events = target.events or { "*" }
  target.secret = target.secret or ""
  return target
end

-- read_secret_file: reads a signing secret from a file after verifying that
-- the file is owned by the current process's effective uid and has permissions
-- exactly 0600 (owner read+write only — no group or other access).
-- Trims trailing whitespace so `echo secret > file` works without surprises.
-- Calls error() on any violation; startup fails loudly rather than silently
-- falling through to trust-the-network mode with a bad or missing path.
read_secret_file = function(path)
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
-- Startup provider flags:
--   --provider=BACKEND / --provider BACKEND — backend provider name
--   --upstream=URL     / --upstream URL     — upstream base URL
--
-- Key=value pairs (any arg containing "=") configure webhook options:
--   webhook_secret_file_BACKEND=/path — path to 0600 file with inbound signing secret
--   --webhook-target=name=NAME,url=URL,shape=SHAPE,events=A+B,secret_file=/path
--   webhook_target=URL                — legacy single outbound delivery target URL
--   webhook_target_name=NAME          — legacy target logical name (default: default)
--   webhook_target_events=A,B,C      — legacy comma-separated event filter (default: *)
--   webhook_target_shape=SHAPE       — legacy delivery shape: "github" (default) or "confusio"
--   webhook_target_secret_file=/path — legacy path to 0600 file with outbound HMAC signing secret
local positional_keys = { "backend", "base_url" }
local pos_idx = 1
local saw_provider_flag = false
local saw_upstream_flag = false
local function webhook_target_config()
  config.webhook_target = config.webhook_target or {}
  return config.webhook_target
end
local argv = arg or {}
local i = 1
while i <= #argv do
  local a = argv[i]
  local consumed_next = false
  local flag_key, flag_val = a:match("^%-%-([^=]+)=(.*)$")
  if not flag_key and (a == "--provider" or a == "--upstream" or a == "--webhook-target") then
    flag_key = a:sub(3)
    flag_val = argv[i + 1]
    if flag_val == nil or flag_val:match("^%-%-") then
      error("missing value for --" .. flag_key)
    end
    consumed_next = true
  end
  if flag_key and flag_val == "" then
    error("missing value for --" .. flag_key)
  end
  local kv_key, kv_val = a:match("^([^=]+)=(.*)$")
  if flag_key == "provider" then
    saw_provider_flag = true
    set_config_once("backend", flag_val, "--provider")
  elseif flag_key == "upstream" then
    saw_upstream_flag = true
    set_config_once("base_url", flag_val, "--upstream")
  elseif flag_key == "webhook-target" then
    local target = parse_webhook_target_spec(flag_val)
    config.webhook_targets = config.webhook_targets or {}
    for _, existing in ipairs(config.webhook_targets) do
      if existing.name == target.name then
        error("duplicate webhook target name: " .. target.name)
      end
    end
    config.webhook_targets[#config.webhook_targets + 1] = target
  elseif flag_key then
    error("unknown startup flag: --" .. flag_key)
  elseif kv_key then
    -- Key=value pair: webhook config.
    local wh_backend = kv_key:match("^webhook_secret_file_(.+)$")
    if wh_backend then
      config.webhook_secrets[wh_backend] = read_secret_file(kv_val)
    elseif kv_key == "webhook_target" then
      if not valid_url(kv_val) then
        error("invalid webhook target URL: " .. kv_val)
      end
      webhook_target_config().url = kv_val
    elseif kv_key == "webhook_target_name" then
      webhook_target_config().name = kv_val
    elseif kv_key == "webhook_target_events" then
      webhook_target_config().events = split_event_filter(kv_val)
    elseif kv_key == "webhook_target_shape" then
      if kv_val ~= "github" and kv_val ~= "confusio" then
        error("unsupported webhook target shape: " .. kv_val)
      end
      webhook_target_config().shape = kv_val
    elseif kv_key == "webhook_target_secret_file" then
      webhook_target_config().secret = read_secret_file(kv_val)
    end
  elseif positional_keys[pos_idx] then
    set_config_once(positional_keys[pos_idx], a, "positional " .. positional_keys[pos_idx])
    pos_idx = pos_idx + 1
  end
  if consumed_next then
    i = i + 1
  end
  i = i + 1
end

config.base_url = config.base_url:gsub("/$", "")

if config.backend ~= "" and not supported_providers[config.backend] then
  error("unsupported provider: " .. config.backend)
end
if saw_provider_flag and not saw_upstream_flag then
  error("--upstream is required when --provider is used")
end
if config.base_url ~= "" and not valid_url(config.base_url) then
  error("invalid upstream URL: " .. config.base_url)
end
if config.webhook_target and config.webhook_targets then
  local legacy_name = config.webhook_target.name or "default"
  for _, target in ipairs(config.webhook_targets) do
    if target.name == legacy_name then
      error("duplicate webhook target name: " .. legacy_name)
    end
  end
end

dofile("/zip/internal/http.lua")
dofile("/zip/internal/proxy.lua")
dofile("/zip/internal/transport.lua")
dofile("/zip/internal/capabilities.lua")
dofile("/zip/internal/backend_helpers.lua")
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
dofile("/zip/internal/webhook_github.lua")

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

-- Register outbound targets declared at startup.
if config.webhook_targets then
  for _, target in ipairs(config.webhook_targets) do
    fanout_register_target(target)
  end
end

-- Register the legacy single outbound target declared via webhook_target=URL.
if config.webhook_target then
  fanout_register_target(config.webhook_target)
end

-- Synthesize installation lifecycle events for GitHub-App-aware consumers.
-- Fires installation.created and installation_repositories.added to all registered
-- targets when a backend is configured.  When no targets are registered,
-- fanout_dispatch returns 0 immediately without attempting delivery.
synthesize_startup_events(config.backend, config.base_url)

OnHttpRequest = make_dispatcher(app)
