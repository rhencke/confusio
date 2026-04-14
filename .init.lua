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
dofile("/zip/internal/families.lua")

-- backend_impl is global: set by backends/<name>.lua at startup.
backend_impl = {}
-- backend_allow_anonymous is global: backends that require sign-in set this to false
-- at startup (after checking the provider's API settings). Default: allow.
backend_allow_anonymous = true
if config.backend ~= "" then
  assert(config.backend:match("^[%a][%w_]*$"), "invalid backend name: " .. config.backend)
  dofile("/zip/backends/" .. config.backend .. ".lua")
end

-- Handlers resolved once at startup; backend is fixed for the program's lifetime.
-- Registered routes not implemented by the backend return 404.
local handle = backend_impl

dofile("/zip/internal/defaults.lua")
dofile("/zip/internal/router.lua")
dofile("/zip/internal/catalog.lua")
function OnHttpRequest()
  if not backend_allow_anonymous and not GetHeader("Authorization") then
    respond_json(401, { message = "This instance requires authentication." })
    return
  end
  local ep, caps, default_fn = route_match(GetMethod(), GetPath())
  if ep then
    local fn = handle[ep] or default_fn
    if fn then
      fn(table.unpack(caps))
    else
      respond_json(404, { message = "Not Found" })
    end
  elseif path_known(GetPath()) then
    respond_json(405, { message = "Method Not Allowed" })
  else
    respond_json(404, { message = "Not Found" })
  end
end
