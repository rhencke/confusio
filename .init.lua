-- Config defaults
local config = {
  backend  = "",
  base_url = "https://gitea.com",
}

-- Config keys that can be set via .confusio.lua or SCRIPTARGS (after --).
-- Parity is structural: every key works the same way in both mechanisms.
-- CLI:         sh ./confusio.com -- backend=gitea base_url=https://gitea.com
-- Config file: confusio = { backend="gitea", base_url="https://gitea.com" }
local CONFIG_KEYS = { "backend", "base_url" }

-- Load .confusio.lua if present. Runs with full Lua global access so it
-- can call functions (e.g. secrets backends) during init.
if pcall(dofile, ".confusio.lua") then
  if type(confusio) == "table" then
    for k, v in pairs(confusio) do
      if config[k] ~= nil then config[k] = v end
    end
  end
  confusio = nil  -- clean up global
end

-- SCRIPTARGS (key=value after --) override config file (highest precedence).
for _, a in ipairs(arg or {}) do
  local k, v = a:match("^([%w_]+)=(.+)$")
  if k and config[k] ~= nil then config[k] = v end
end

-- Strip trailing slash for uniform concatenation.
config.base_url = config.base_url:gsub("/$", "")

local function respond_json(status, reason, body)
  SetStatus(status, reason)
  SetHeader("Content-Type", "application/json; charset=utf-8")
  Write(EncodeJson(body))
end

-- Backend-specific handler overrides. Only define what differs from the default.
-- To add a new backend: add a new key with its endpoint overrides.
-- To add a new endpoint: add it to defaults; only add to a backend if it differs.
local backend_impls = {
  gitea = {
    root = function()
      local ok, status = pcall(Fetch, config.base_url .. "/api/v1/version")
      if ok and status == 200 then respond_json(200, "OK", {})
      else respond_json(503, "Service Unavailable", {}) end
    end,
  },
}

-- Default handlers used when the active backend has no override.
local defaults = {
  root = function() respond_json(200, "OK", {}) end,
}

-- Resolve once at startup: handle.X uses the backend override if present,
-- otherwise falls through to defaults.X. The backend is fixed for the
-- program's lifetime so this table never changes after init.
local handle = setmetatable(backend_impls[config.backend] or {}, { __index = defaults })

-- Route table maps path → handler name.
-- O(1) lookup; adding an endpoint is one table entry.
local routes = {
  ["/"]       = "root",
  ["/emojis"] = "emojis",
}

function OnHttpRequest()
  local method = GetMethod()
  local path   = GetPath()
  if method ~= "GET" and method ~= "HEAD" then Route(); return end
  local ep = routes[path]
  if ep then handle[ep]() else Route() end
end
