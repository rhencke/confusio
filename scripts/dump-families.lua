-- Export provider-family metadata as a JSON array to stdout.
-- Run from the project root: ./redbean.com -i scripts/dump-families.lua

-- Block backend files so only the core metadata is loaded.
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

-- Load .init.lua, which populates the global `provider_families` table.
_real_dofile(".init.lua")
dofile = _real_dofile -- luacheck: globals dofile

-- Collect and sort families for stable output.
local families = {}
for root, family in pairs(provider_families) do -- luacheck: globals provider_families
  local aliases = {}
  for alias in pairs(family.aliases) do
    aliases[#aliases + 1] = alias
  end
  table.sort(aliases)
  families[#families + 1] = { root = root, aliases = aliases }
end
table.sort(families, function(a, b)
  return a.root < b.root
end)

local parts = {}
for i, f in ipairs(families) do
  local alias_parts = {}
  for j, a in ipairs(f.aliases) do
    alias_parts[j] = EncodeJson(a)
  end
  parts[i] = '  {"root":'
    .. EncodeJson(f.root)
    .. ',"aliases":['
    .. table.concat(alias_parts, ",")
    .. "]}"
end
io.write("[\n" .. table.concat(parts, ",\n") .. "\n]\n")
