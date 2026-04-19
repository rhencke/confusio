-- Export capability registrations for all backends as JSON.
-- Used by validate-capabilities to check capability module structure.
--
-- Usage: ./redbean.com -i scripts/dump-capabilities.lua <backend1> [backend2 ...]
--
-- Output: a single JSON object:
--   { "backends": { "<name>": { "<domain>": ["op1","op2",...], ... }, ... } }
--
-- Errors go to stderr; exits non-zero if any capability module is not a
-- table or contains non-function values.

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
-- internal globals: make_app, make_backend_builder, cap_fetch, etc.
config = { backend = "", base_url = "" } -- luacheck: globals config
_real_dofile(".init.lua")

-- Stub Fetch so load-time network probes (e.g. Gitea anon check) fail
-- immediately inside their pcall wrappers without making real network calls.
local _real_fetch = Fetch -- luacheck: globals Fetch
local function noop_fetch()
  error("network disabled in dump mode")
end

local errors = {}
local backend_parts = {}

for _, name in ipairs(cli_backends) do
  config = { backend = name, base_url = "" } -- luacheck: globals config
  app.backend = { rest = {}, graphql = {}, capabilities = {}, webhooks = {} } -- luacheck: globals app
  graphql_resolvers = app.backend.graphql -- luacheck: globals graphql_resolvers
  Fetch = noop_fetch -- luacheck: globals Fetch
  dofile("/zip/backends/" .. name .. ".lua")
  Fetch = _real_fetch -- luacheck: globals Fetch

  local domain_parts = {}
  for domain, module in pairs(app.backend.capabilities) do
    if type(module) ~= "table" then
      errors[#errors + 1] = name .. ": capability '" .. domain .. "' is not a table"
    else
      local ops = {}
      for op_name, op_val in pairs(module) do
        if type(op_val) ~= "function" then
          errors[#errors + 1] = name
            .. ": capability "
            .. domain
            .. "."
            .. op_name
            .. " is not a function"
        else
          ops[#ops + 1] = op_name
        end
      end
      table.sort(ops)
      local op_parts = {}
      for i, op in ipairs(ops) do
        op_parts[i] = EncodeJson(op)
      end
      domain_parts[#domain_parts + 1] = EncodeJson(domain)
        .. ":["
        .. table.concat(op_parts, ",")
        .. "]"
    end
  end
  backend_parts[#backend_parts + 1] = EncodeJson(name)
    .. ":{"
    .. table.concat(domain_parts, ",")
    .. "}"
end

if #errors > 0 then
  for _, e in ipairs(errors) do
    io.stderr:write(e .. "\n")
  end
  os.exit(1)
end

io.write('{"backends":{\n')
io.write(table.concat(backend_parts, ",\n"))
io.write("\n}}\n")
