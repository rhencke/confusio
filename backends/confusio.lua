-- Confusio-to-confusio inbound webhook source.
--
-- Accepts the normalized confusio event envelope as a provider-bound inbound
-- shape, then routes it through the same internal event and fanout machinery as
-- native forge webhooks.
local b = make_backend_builder()

local function shallow_copy(src)
  local dst = {}
  for k, v in pairs(src or {}) do
    dst[k] = v
  end
  return dst
end

local ACTIONLESS_EVENTS = {
  create = true,
  delete = true,
  fork = true,
  push = true,
  status = true,
  ping = true,
  meta = true,
  public = true,
  gollum = true,
}

local function action_known(event_name, action)
  local def = webhook_catalog_event(event_name) -- luacheck: globals webhook_catalog_event
  if not def then
    return false
  end
  for _, candidate in ipairs(def.actions or {}) do
    if candidate == action then
      return true
    end
  end
  return false
end

local function normalized_data(payload, action)
  local data = shallow_copy(payload.payload or {})
  if data.repository == nil and payload.repository ~= nil then
    data.repository = payload.repository
  end
  if data.actor == nil and payload.actor ~= nil then
    data.actor = payload.actor
  end
  if data.sender == nil and payload.actor ~= nil then
    data.sender = payload.actor
  end
  if data.action == nil and action ~= "" then
    data.action = action
  end
  return data
end

local function confusio_webhook(payload)
  if type(payload) ~= "table" then
    return nil, "Invalid confusio normalized webhook payload"
  end

  local event_name, action = webhook_catalog_event_for_normalized_type(payload.type) -- luacheck: globals webhook_catalog_event_for_normalized_type
  if not event_name then
    return nil, "Unsupported confusio normalized event type"
  end

  local header_event = GetHeader("X-Confusio-Event") -- luacheck: globals GetHeader
  if header_event and header_event ~= "" and header_event ~= event_name then
    return nil, "Confusio event header/body mismatch"
  end

  action = action or ""
  local raw_action = nil
  if ACTIONLESS_EVENTS[event_name] then
    action = ""
  elseif not action_known(event_name, action) then
    raw_action = action
    action = "unknown"
  end

  return make_internal_event({ -- luacheck: globals make_internal_event
    event = event_name,
    action = action,
    raw_action = raw_action,
    provider = "confusio",
    raw = payload,
    data = normalized_data(payload, action),
    timestamp = payload.occurred_at or "",
  })
end

local function translate_confusio_normalized_webhook(internal_event, fields)
  local raw = internal_event.raw or {}
  fields = fields or {}
  return make_normalized_webhook_envelope( -- luacheck: globals make_normalized_webhook_envelope
    internal_event,
    {
      id = fields.id or raw.id,
      type = raw.type,
      occurred_at = raw.occurred_at,
      actor = raw.actor,
      repository = raw.repository,
      payload = raw.payload,
    }
  )
end

local function translate_confusio_github_webhook(internal_event, fields)
  return github_webhook_payload(internal_event, fields) -- luacheck: globals github_webhook_payload
end

for _, def in ipairs(webhook_catalog_events()) do -- luacheck: globals webhook_catalog_events
  b:webhook(def.name, confusio_webhook)
  b:webhook_translator(def.name, translate_confusio_normalized_webhook)
  b:webhook_github_translator(def.name, translate_confusio_github_webhook)
end

b:build()
