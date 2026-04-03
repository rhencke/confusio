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

local function handle_root_gitea()
  local ok, status = pcall(Fetch, config.base_url .. "/api/v1/version")
  if ok and status == 200 then
    respond_json(200, "OK", {})
  else
    respond_json(503, "Service Unavailable", {})
  end
end

function OnHttpRequest()
  local method = GetMethod()
  local path   = GetPath()

  if (method == "GET" or method == "HEAD") and path == "/" then
    if config.backend == "gitea" then
      handle_root_gitea()
    else
      respond_json(200, "OK", {})
    end
  else
    Route()
  end
end
