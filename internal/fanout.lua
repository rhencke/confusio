-- Fan-out dispatcher for the outbound webhook system.
--
-- Receives a normalized inbound event and fans it out to all active targets
-- whose event subscription covers the event type.  Each matching target gets
-- one outbox delivery record created with status="pending".
--
-- "Shape" controls how the request body is serialised for each target:
--   "github"   — re-encodes the raw inbound payload unchanged (GitHub-emulation)
--   "confusio" — wraps the payload in a metadata envelope {source, event, payload}
--
-- The actual HTTP dispatch and signing live in the outbound delivery module.
-- This module is responsible only for routing decisions (which targets receive
-- the event) and body serialisation (what each target receives).
--
-- Globals exported:
--   fanout_body(backend, event_type, payload, shape) → body string
--   fanout_dispatch(backend, event_type, payload)    → event_record, deliveries

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
-- pending delivery record for each active target whose event subscription
-- covers the event type.
-- Returns (event_record, deliveries) where deliveries is an array of delivery
-- records (one per matched target, in target_list order).  Returns an empty
-- array when no targets match.
function fanout_dispatch(backend, event_type, payload) -- luacheck: globals fanout_dispatch
  local ev = outbox_store_event(backend, event_type, payload)
  local targets = target_list()
  local deliveries = {}
  for _, target in ipairs(targets) do
    if fanout_event_matches(event_type, target.events) then
      local delivery = outbox_create_delivery(ev.event_id, target.target_id)
      deliveries[#deliveries + 1] = delivery
    end
  end
  return ev, deliveries
end
