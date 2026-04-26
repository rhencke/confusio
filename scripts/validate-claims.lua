-- Validate that CSV support claims agree with actual backend REST handler presence.
--
-- Rules checked for each (backend, endpoint) cell in the CSV:
--   y  — app.backend.rest must contain a handler for this endpoint, UNLESS the handler is
--          confusio-native (a complete response synthesized by confusio itself, not the
--          backend API — e.g. GET /meta, GET /zen).  Confusio-native handlers return
--          real responses for every backend and are exempted from the handler-presence
--          requirement.
--   n  — app.backend.rest must NOT contain a handler for this endpoint
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
-- accurate even when app.backend.rest has no entry for them.
local CONFUSIO_NATIVE = {
  get_meta = true,
  get_octocat = true,
  get_teapot = true,
  get_versions = true,
  get_zen = true,
  -- graphql_handler is the fixed handler for POST /graphql across all backends;
  -- backends populate graphql_resolvers rather than app.backend.rest.graphql_request.
  graphql_request = true,
  -- The webhook receive pipeline in internal/webhooks.lua handles all backends uniformly;
  -- backends register event handlers via b:webhook(), not app.backend.rest entries.
  post_webhooks_backend = true,
}

local csv_path = (arg and arg[1]) or "site/compatibility.csv" -- luacheck: globals arg

-- Read dump-claims JSON from stdin.
local data = DecodeJson(io.read("*a"))
local endpoints = data.endpoints
local backends = data.backends -- backends[name] = { rest = [...], webhooks = [...] }

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

-- Build a lookup from "METHOD /path" → { handler, is_webhook_event, webhook_event }.
-- For webhook event rows, webhook_event is the event type extracted from the path
-- (e.g. "issues" from "issues/opened") — this is the key in app.backend.webhooks.
local ep_info = {}
for _, e in ipairs(endpoints) do
  local key = e.method .. " " .. e.path
  local webhook_event = nil
  if e.is_webhook_event then
    -- path is "event/action" (e.g. "issues/opened"); extract event type
    webhook_event = e.path:match("^([^/]+)/")
  end
  ep_info[key] =
    { handler = e.handler, is_webhook_event = e.is_webhook_event, webhook_event = webhook_event }
end

-- Build O(1) lookup sets per provider.
-- impl_set[name][handler]      true if app.backend.rest has this handler
-- wh_set[name][event]          true if app.backend.webhooks has this event handler
local impl_set = {}
local wh_set = {}
for name, info in pairs(backends) do
  local rs = {}
  for _, h in ipairs(info.rest or {}) do
    rs[h] = true
  end
  impl_set[name] = rs

  local ws = {}
  for _, ev in ipairs(info.webhooks or {}) do
    ws[ev] = true
  end
  wh_set[name] = ws
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
    local info = ep_info[ep]
    if info then
      for _, provider in ipairs(csv_providers) do
        if backends[provider] then
          local claim = row[provider] or "n"
          if info.is_webhook_event then
            -- Webhook event rows: validate against app.backend.webhooks[event_type].
            -- A 'y' claim requires the backend to have a webhook handler for this event type.
            -- A 'n' claim requires the backend NOT to have one.
            -- '~*' claims are not validated (partial/best-effort support).
            local event_type = info.webhook_event
            local has_wh = event_type ~= nil and wh_set[provider][event_type] == true
            if claim == "y" and not has_wh then
              errors[#errors + 1] = "ERROR: "
                .. provider
                .. " claims 'y' for "
                .. ep
                .. " but app.backend.webhooks has no handler for event '"
                .. (event_type or "?")
                .. "'"
            elseif claim == "n" and has_wh then
              errors[#errors + 1] = "ERROR: "
                .. provider
                .. " claims 'n' for "
                .. ep
                .. " but app.backend.webhooks defines a handler for event '"
                .. (event_type or "?")
                .. "'"
            end
          else
            -- REST endpoint rows: validate against app.backend.rest[handler].
            local handler = info.handler
            local has_handler = impl_set[provider][handler] == true
            if claim == "y" and not has_handler and not CONFUSIO_NATIVE[handler] then
              errors[#errors + 1] = "ERROR: "
                .. provider
                .. " claims 'y' for "
                .. ep
                .. " but app.backend.rest has no handler '"
                .. handler
                .. "'"
            elseif claim == "n" and has_handler then
              errors[#errors + 1] = "ERROR: "
                .. provider
                .. " claims 'n' for "
                .. ep
                .. " but app.backend.rest defines handler '"
                .. handler
                .. "'"
            end
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
