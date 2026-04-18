-- Validate capability module registrations across all backends.
-- Reads dump-capabilities JSON from stdin.
--
-- Rules checked for each registered capability module:
--   - The module must have at least one operation.
--     (An empty capability table is a registration mistake — it means
--     b:capability("name", {}) was called with an uninitialised table.)
--
-- Backends with zero capability registrations pass without error — they
-- simply have not been migrated to the capability layer yet.
--
-- Usage:
--   ./redbean.com -i scripts/dump-capabilities.lua <backends...> 2>/dev/null \
--     | ./redbean.com -i scripts/validate-capabilities.lua
--
-- Exits non-zero if any violation is found.

local data = DecodeJson(io.read("*a"))
local backends = data.backends

local errors = {}
local total_backends = 0
local total_modules = 0

for backend_name, cap_map in pairs(backends) do
  total_backends = total_backends + 1
  for domain, ops in pairs(cap_map) do
    total_modules = total_modules + 1
    if #ops == 0 then
      errors[#errors + 1] = "ERROR: "
        .. backend_name
        .. " capability '"
        .. domain
        .. "' has no operations (registered with an empty table)"
    end
  end
end

if #errors > 0 then
  for _, e in ipairs(errors) do
    io.stderr:write(e .. "\n")
  end
  os.exit(1)
end

io.write(
  "validate-capabilities OK ("
    .. tostring(total_backends)
    .. " backends, "
    .. tostring(total_modules)
    .. " modules)\n"
)
