-- Export endpoint catalog + per-backend handler sets as JSON.
-- Used by validate-claims.lua to check CSV support claims against backend_impl.
--
-- Usage: ./redbean.com -i scripts/dump-claims.lua <backend1> [backend2 ...]
--
-- Output: a single JSON object:
--   { "endpoints": [...], "backends": { "<name>": ["handler",...], ... } }

-- Save CLI args before init.lua reads them.
local cli_backends = {}
for _, v in ipairs(arg or {}) do -- luacheck: globals arg
  cli_backends[#cli_backends + 1] = v
end
arg = {} -- luacheck: globals arg

-- Redirect /zip/internal/ and /zip/backends/ to the local filesystem so that
-- both the core modules and backend files can be loaded without a zip context.
local _real_dofile = dofile
function dofile(path) -- luacheck: globals dofile
  if path and path:match("^/zip/backends/") then
    return _real_dofile("backends/" .. path:match("^/zip/backends/(.+)$"))
  end
  if path and path:match("^/zip/internal/") then
    return _real_dofile(path:sub(6))
  end
  return _real_dofile(path)
end

-- Load .init.lua (no backend — config.backend is "").  This populates all
-- internal globals: set_preamble, proxy_*, translate_*, load_family_backend,
-- defaults, route_add, endpoints, ...
config = { backend = "", base_url = "" } -- luacheck: globals config
_real_dofile(".init.lua")

-- Serialize the endpoint catalog.
local ep_parts = {}
for i, e in ipairs(endpoints) do -- luacheck: globals endpoints
  local verb, path = e[1]:match("^(%S+)%s+(.+)$")
  ep_parts[i] = "{"
    .. '"method":'
    .. EncodeJson(verb)
    .. ',"path":'
    .. EncodeJson(path)
    .. ',"handler":'
    .. EncodeJson(e[2])
    .. ',"group":'
    .. EncodeJson(e.group)
    .. ',"has_default":'
    .. (e[3] ~= nil and "true" or "false")
    .. "}"
end

-- For each backend: reset state, load the backend file, capture handler keys.
-- Fetch is stubbed to a no-op so load-time probes (e.g. Gitea anon check) fail
-- immediately inside their pcall wrappers without making real network calls.
local _real_fetch = Fetch -- luacheck: globals Fetch
local function noop_fetch()
  error("network disabled in dump mode")
end

local backend_parts = {}
for _, name in ipairs(cli_backends) do
  config = { backend = name, base_url = "" } -- luacheck: globals config
  app.backend_impl = {} -- luacheck: globals app
  Fetch = noop_fetch -- luacheck: globals Fetch
  dofile("/zip/backends/" .. name .. ".lua")
  Fetch = _real_fetch -- luacheck: globals Fetch

  local handlers = {}
  for k in pairs(app.backend_impl) do -- luacheck: globals app
    handlers[#handlers + 1] = k
  end
  table.sort(handlers)

  local handler_parts = {}
  for i, h in ipairs(handlers) do
    handler_parts[i] = EncodeJson(h)
  end
  backend_parts[#backend_parts + 1] = EncodeJson(name)
    .. ":["
    .. table.concat(handler_parts, ",")
    .. "]"
end

io.write('{"endpoints":[\n')
io.write(table.concat(ep_parts, ",\n"))
io.write('\n],"backends":{\n')
io.write(table.concat(backend_parts, ",\n"))
io.write("\n}}\n")
