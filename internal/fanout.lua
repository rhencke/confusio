-- Single-target dispatcher for the outbound webhook system.
--
-- Receives a normalized inbound event and dispatches it to the single active
-- target (if any) whose event subscription covers the event type.  A delivery
-- record is created with status="pending" when the target matches.
--
-- "Shape" controls how the request body is serialised for the target:
--   "github"   — re-encodes the raw inbound payload unchanged (GitHub-emulation)
--   "confusio" — wraps the payload in a metadata envelope {source, event, payload}
--
-- The actual HTTP dispatch lives in the outbound delivery module.
-- This module is responsible only for routing decisions (does the target receive
-- the event) and body serialisation (what the target receives).
--
-- Globals exported:
--   fanout_body(backend, event_type, payload, shape) → body string
--   fanout_dispatch(backend, event_type, payload)    → event_record, delivery_or_nil

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

-- fanout_body: serialises the event for the given delivery shape.
--   "github"   — re-encodes the raw inbound payload (fields forwarded as-is)
--   "confusio" — wraps in {source, event, payload} envelope
-- Any unknown shape value falls back to "github" behaviour.
function fanout_body(backend, event_type, payload, shape) -- luacheck: globals fanout_body
  if shape == "confusio" then
    return EncodeJson({
      source = backend,
      event = event_type,
      payload = payload,
    })
  end
  -- "github" (default): forward the raw inbound payload unchanged.
  return EncodeJson(payload)
end

-- fanout_dispatch: stores an inbound event in the outbox and creates one
-- pending delivery record if the single active target subscribes to this
-- event type.
-- Returns (event_record, delivery) where delivery is the new record, or
-- (event_record, nil) when there is no active target or the event is filtered.
function fanout_dispatch(backend, event_type, payload) -- luacheck: globals fanout_dispatch
  local ev = outbox_store_event(backend, event_type, payload)
  local targets = target_list({ status = "active" })
  local target = targets[1]
  if target and fanout_event_matches(event_type, target.events) then
    local delivery = outbox_create_delivery(ev.event_id, target.target_id)
    return ev, delivery
  end
  return ev, nil
end
