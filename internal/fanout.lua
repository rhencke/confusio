-- Single-target dispatcher for the outbound webhook system.
--
-- Receives a normalized inbound event and dispatches it to all registered
-- targets whose event subscription covers the event type.  Delivery is
-- fire-and-record: the HTTP POST is attempted immediately, the outcome is
-- logged, and confusio moves on.  No retry, no persistence.
--
-- "Shape" controls how the request body is serialised for the target:
--   "github"   — re-encodes the raw inbound payload unchanged (GitHub-emulation)
--   "confusio" — emits the normalized event envelope
--
-- Globals exported:
--   fanout_body(backend, event_type, payload, shape[, internal_event, translators, fields]) → body string
--   fanout_register_target(target)                   — register a static outbound target
--   fanout_dispatch(backend, event_type, payload[, internal_event, translators]) — fire to all matching targets

-- _fanout_targets: in-memory list of registered outbound targets.
-- Each entry is a table: { name, url, events, shape, secret, delivery_log_path }
local _fanout_targets = {}

-- fanout_event_matches: returns true when event_type is covered by the target's
-- events subscription list.  The wildcard "*" matches any event type.
local function fanout_event_matches(event_type, events)
  for _, e in ipairs(events) do
    if e == "*" or e == event_type then
      return true
    end
  end
  return false
end

local function fallback_internal_event(backend, event_type, payload)
  return make_internal_event({ -- luacheck: globals make_internal_event
    event = event_type,
    action = "",
    provider = backend,
    raw = payload,
    data = {
      payload = payload,
    },
  })
end

local function normalized_body(backend, event_type, payload, internal_event, translators, fields)
  internal_event = internal_event or fallback_internal_event(backend, event_type, payload)
  fields = fields or {}
  local translator = nil
  if type(translators) == "table" then
    translator = translators[event_type] or translators["*"]
  end
  local envelope = nil
  if type(translator) == "function" then
    envelope = translator(internal_event, fields)
  end
  if type(envelope) ~= "table" then
    envelope = make_normalized_webhook_envelope(internal_event, fields) -- luacheck: globals make_normalized_webhook_envelope
  end
  return EncodeJson(envelope) -- luacheck: globals EncodeJson
end

-- fanout_body: serialises the event for the given delivery shape.
--   "github"   — re-encodes the raw inbound payload (fields forwarded as-is)
--   "confusio" — emits the normalized event envelope
-- Any unknown shape value falls back to "github" behaviour.
function fanout_body(backend, event_type, payload, shape, internal_event, translators, fields) -- luacheck: globals fanout_body
  if shape == "confusio" then
    return normalized_body(backend, event_type, payload, internal_event, translators, fields)
  end
  -- "github" (default): forward the raw inbound payload unchanged.
  return EncodeJson(payload) -- luacheck: globals EncodeJson
end

-- fanout_register_target: adds a static outbound target to the registry.
-- target must be a table with at least a non-empty url field.
-- Optional fields: name (string; default "default"), events (array; default {"*"}),
-- shape (string; default "github"), secret (string; used for HMAC signing),
-- delivery_log_path (string; structured delivery-attempt log path).
function fanout_register_target(target) -- luacheck: globals fanout_register_target
  if type(target) ~= "table" or type(target.url) ~= "string" or target.url == "" then
    return
  end
  local entry = {
    name = target.name or "default",
    url = target.url,
    events = target.events or { "*" },
    shape = target.shape or "github",
    secret = target.secret or "",
    delivery_log_path = target.delivery_log_path or "",
  }
  _fanout_targets[#_fanout_targets + 1] = entry
end

-- fanout_dispatch: fires the inbound event to all matching registered targets.
-- Delivery is fire-and-record: deliver_fire() is called for each matching target.
-- Returns the number of targets that matched (regardless of delivery success).
function fanout_dispatch(backend, event_type, payload, internal_event, translators) -- luacheck: globals fanout_dispatch deliver_fire
  local count = 0
  for _, target in ipairs(_fanout_targets) do
    if fanout_event_matches(event_type, target.events) then
      deliver_fire(target, backend, event_type, payload, internal_event, translators)
      count = count + 1
    end
  end
  return count
end
