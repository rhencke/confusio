-- Config defaults (global: backends/<name>.lua can read at startup)
config = {
  backend  = "",
  base_url = "https://gitea.com",
}

-- Config keys accepted by both .confusio.lua and SCRIPTARGS.
local CONFIG_KEYS = { "backend", "base_url" }

-- Load .confusio.lua if present.
if pcall(dofile, ".confusio.lua") then
  if type(confusio) == "table" then
    for k, v in pairs(confusio) do
      if config[k] ~= nil then config[k] = v end
    end
  end
  confusio = nil
end

-- SCRIPTARGS (key=value after --) override config file.
for _, a in ipairs(arg or {}) do
  local k, v = a:match("^([%w_]+)=(.+)$")
  if k and config[k] ~= nil then config[k] = v end
end

config.base_url = config.base_url:gsub("/$", "")

-- respond_json is global: backends/<name>.lua uses it.
function respond_json(status, reason, body)
  SetStatus(status, reason)
  SetHeader("Content-Type", "application/json; charset=utf-8")
  Write(EncodeJson(body))
end

-- backend_impl is global: set by backends/<name>.lua at startup.
backend_impl = {}
if config.backend ~= "" then
  assert(config.backend:match("^[%a][%w_]*$"),
    "invalid backend name: " .. config.backend)
  dofile("/zip/backends/" .. config.backend .. ".lua")
end

-- Default handlers. Add an entry here for every endpoint confusio exposes.
-- Override in backends/<name>.lua only when the backend behaves differently.
local defaults = {
  root = function() respond_json(200, "OK", {}) end,
}

-- Resolve handlers once at startup: backend overrides shadow defaults via __index.
-- The backend is fixed for the program's lifetime — no per-request dispatch needed.
local handle = setmetatable(backend_impl, { __index = defaults })

-- ---------------------------------------------------------------------------
-- Segment-based radix trie router
--
-- Each node: { static = {[segment]→node}, param = node|nil, handler = name|nil }
--
-- route_add builds the trie at startup. {param} segments become param edges;
-- all other segments become static edges. Static edges are preferred over param
-- edges during matching, so /repos/search beats /repos/{owner} for that path.
-- ---------------------------------------------------------------------------

local function new_node() return { static = {}, param = nil, handler = nil } end
local trie = new_node()

local function route_add(path, handler_name)
  local node = trie
  for seg in path:gmatch("[^/]+") do
    if seg:sub(1, 1) == "{" then
      node.param = node.param or new_node()
      node = node.param
    else
      node.static[seg] = node.static[seg] or new_node()
      node = node.static[seg]
    end
  end
  node.handler = handler_name
end

local function route_match(path)
  local node = trie
  local caps = {}
  for seg in path:gmatch("[^/]+") do
    if node.static[seg] then
      node = node.static[seg]
    elseif node.param then
      caps[#caps + 1] = seg
      node = node.param
    else
      return nil, nil
    end
  end
  return node.handler, caps
end

-- ---------------------------------------------------------------------------
-- Route registry
--
-- Exact:      route_add("/emojis",               "emojis")
-- Parametric: route_add("/repos/{owner}/{repo}",  "repo")
--
-- Each handler_name must have an entry in defaults above (and optionally an
-- override in backends/<name>.lua). Parametric captures are passed positionally:
--   repo = function(owner, repo) ... end
-- ---------------------------------------------------------------------------

route_add("/", "root")

function OnHttpRequest()
  local method = GetMethod()
  local path   = GetPath()
  if method ~= "GET" and method ~= "HEAD" then Route(); return end
  local ep, caps = route_match(path)
  if ep then handle[ep](table.unpack(caps)) else Route() end
end
