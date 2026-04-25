-- Export the endpoint catalog as a JSON array to stdout.
-- Run from the project root: ./redbean.com -i scripts/dump-endpoints.lua

-- Block backend files so only the core catalog is loaded.
-- Redirect /zip/internal/ to the internal/ directory on the filesystem so the
-- script can load internal modules without a Redbean zip.
local _real_dofile = dofile
function dofile(path) -- luacheck: globals dofile
  if path and path:match("^/zip/backends/") then
    return
  end
  if path and path:match("^/zip/internal/") then
    return _real_dofile(path:sub(6))
  end
  return _real_dofile(path)
end

-- Load .init.lua, which populates the global `endpoints` table.
_real_dofile(".init.lua")
dofile = _real_dofile -- luacheck: globals dofile

-- Serialize the catalog.
local parts = {}
for i, e in ipairs(endpoints) do -- luacheck: globals endpoints
  local verb, path = e[1]:match("^(%S+)%s+(.+)$")
  parts[i] = "  {"
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
    .. ',"is_webhook_event":'
    .. (e.is_webhook_event and "true" or "false")
    .. "}"
end
io.write("[\n" .. table.concat(parts, ",\n") .. "\n]\n")
