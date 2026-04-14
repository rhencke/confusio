-- Validate that CSV support claims agree with actual backend_impl handler presence.
--
-- Rules checked for each (backend, endpoint) cell in the CSV:
--   y  — backend_impl must contain a handler for this endpoint, UNLESS the handler is
--          confusio-native (a complete response synthesized by confusio itself, not the
--          backend API — e.g. GET /meta, GET /zen).  Confusio-native handlers return
--          real responses for every backend and are exempted from the handler-presence
--          requirement.
--   n  — backend_impl must NOT contain a handler for this endpoint
--          (backend silently implements something the CSV calls unsupported → error)
--   ~* — not checked (partial support may or may not have a dedicated handler)
--
-- The confusio-native handler set is small and explicit — update it here if catalog
-- defaults ever change.
--
-- Usage:
--   ./redbean.com -i scripts/dump-claims.lua <backends...> 2>/dev/null \
--     | ./redbean.com -i scripts/validate-claims.lua [csv]
--
--   csv  path to compatibility CSV (default: site/compatibility.csv)
--
-- Exits non-zero if any mismatch is found.

-- Handlers whose catalog defaults are complete confusio-synthesised responses.
-- These work for every backend without a per-backend handler, so a y claim is
-- accurate even when backend_impl has no entry for them.
local CONFUSIO_NATIVE = {
  get_meta = true,
  get_octocat = true,
  get_teapot = true,
  get_versions = true,
  get_zen = true,
}

local csv_path = (arg and arg[1]) or "site/compatibility.csv" -- luacheck: globals arg

-- Read dump-claims JSON from stdin.
local data = DecodeJson(io.read("*a"))
local endpoints = data.endpoints
local backends = data.backends

-- Parse a single CSV line into fields, handling RFC 4180 quoting.
local function parse_csv_line(line)
  local fields = {}
  local pos = 1
  while pos <= #line do
    if line:sub(pos, pos) == '"' then
      pos = pos + 1
      local field = {}
      while pos <= #line do
        local c = line:sub(pos, pos)
        if c == '"' then
          if line:sub(pos + 1, pos + 1) == '"' then
            field[#field + 1] = '"'
            pos = pos + 2
          else
            pos = pos + 1
            break
          end
        else
          field[#field + 1] = c
          pos = pos + 1
        end
      end
      fields[#fields + 1] = table.concat(field)
      if line:sub(pos, pos) == "," then
        pos = pos + 1
      end
    else
      local j = line:find(",", pos, true)
      if j then
        fields[#fields + 1] = line:sub(pos, j - 1)
        pos = j + 1
      else
        fields[#fields + 1] = line:sub(pos)
        break
      end
    end
  end
  return fields
end

-- Read and parse the CSV file.
local f = assert(io.open(csv_path, "r"))
local lines = {}
for line in f:lines() do
  lines[#lines + 1] = line
end
f:close()

local headers = parse_csv_line(lines[1])
local csv_providers = {}
for _, h in ipairs(headers) do
  if h ~= "endpoint" then
    csv_providers[#csv_providers + 1] = h
  end
end

-- Build a lookup from "METHOD /path" → handler name.
local handler_for = {}
for _, e in ipairs(endpoints) do
  handler_for[e.method .. " " .. e.path] = e.handler
end

-- Build a set of handlers per provider for O(1) lookup.
local impl_set = {}
for name, handlers in pairs(backends) do
  local s = {}
  for _, h in ipairs(handlers) do
    s[h] = true
  end
  impl_set[name] = s
end

local errors = {}
for li = 2, #lines do
  if lines[li] ~= "" then
    local fields = parse_csv_line(lines[li])
    local row = {}
    for fi, h in ipairs(headers) do
      row[h] = fields[fi] or ""
    end
    local ep = row.endpoint
    local handler = handler_for[ep]
    if handler then
      for _, provider in ipairs(csv_providers) do
        if backends[provider] then
          local claim = row[provider] or "n"
          local has_handler = impl_set[provider][handler] == true
          if claim == "y" and not has_handler and not CONFUSIO_NATIVE[handler] then
            errors[#errors + 1] = "ERROR: "
              .. provider
              .. " claims 'y' for "
              .. ep
              .. " but backend_impl has no handler '"
              .. handler
              .. "'"
          elseif claim == "n" and has_handler then
            errors[#errors + 1] = "ERROR: "
              .. provider
              .. " claims 'n' for "
              .. ep
              .. " but backend_impl defines handler '"
              .. handler
              .. "'"
          end
        end
      end
    end
  end
end

if #errors > 0 then
  for _, e in ipairs(errors) do
    io.stderr:write(e .. "\n")
  end
  os.exit(1)
end
