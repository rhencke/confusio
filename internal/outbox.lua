-- In-memory outbox for the outbound webhook dispatcher.
--
-- The outbox stores two kinds of records:
--
--   Event records   — one per inbound webhook event received.
--   Delivery records — one per (event, target) pair, tracking dispatch state.
--
-- All records are stored in module-local tables; there is no persistence across
-- process restarts.  Returned records are the actual internal tables (mutable).
-- Callers must not modify returned records directly; use outbox_update_delivery
-- for delivery state changes.
--
-- Globals exported:
--   outbox_store_event(backend, event_type, payload)
--   outbox_get_event(event_id)
--   outbox_create_delivery(event_id, target_id)
--   outbox_get_delivery(delivery_id)
--   outbox_list_deliveries_for_event(event_id)
--   outbox_list_deliveries_for_target(target_id)
--   outbox_update_delivery(delivery_id, fields)
--   outbox_abandon_deliveries_for_target(target_id)
--   outbox_pending_retries()
--   outbox_prune(max_age_seconds)

-- Module-local storage.
local _events = {} -- event_id → event record
local _deliveries = {} -- delivery_id → delivery record
local _event_order = {} -- insertion-order list of event_ids
local _delivery_order = {} -- insertion-order list of delivery_ids

-- outbox_store_event(backend, event_type, payload) stores a new inbound event.
-- Returns the event record.
function outbox_store_event(backend, event_type, payload) -- luacheck: globals outbox_store_event
  local id = make_uuid()
  local record = {
    event_id = id,
    received_at = now_iso8601(),
    backend = backend,
    event_type = event_type,
    payload = payload,
  }
  _events[id] = record
  _event_order[#_event_order + 1] = id
  return record
end

-- outbox_get_event(event_id) returns the event record for the given id,
-- or nil if not found.
function outbox_get_event(event_id) -- luacheck: globals outbox_get_event
  return _events[event_id]
end

-- outbox_create_delivery(event_id, target_id) creates a new delivery record
-- for the given (event, target) pair.  Initial status is "pending".
-- Returns the delivery record.
function outbox_create_delivery(event_id, target_id) -- luacheck: globals outbox_create_delivery
  local now = now_iso8601()
  local id = make_uuid()
  local record = {
    delivery_id = id,
    event_id = event_id,
    target_id = target_id,
    status = "pending",
    created_at = now,
    updated_at = now,
    attempt_count = 0,
    next_attempt_at = nil,
    last_http_status = nil,
    last_error = nil,
  }
  _deliveries[id] = record
  _delivery_order[#_delivery_order + 1] = id
  return record
end

-- outbox_get_delivery(delivery_id) returns the delivery record for the given id,
-- or nil if not found.
function outbox_get_delivery(delivery_id) -- luacheck: globals outbox_get_delivery
  return _deliveries[delivery_id]
end

-- outbox_list_deliveries_for_event(event_id) returns all delivery records
-- for the given event, in insertion order.
function outbox_list_deliveries_for_event(event_id) -- luacheck: globals outbox_list_deliveries_for_event
  local result = {}
  for _, id in ipairs(_delivery_order) do
    local d = _deliveries[id]
    if d ~= nil and d.event_id == event_id then
      result[#result + 1] = d
    end
  end
  return result
end

-- outbox_list_deliveries_for_target(target_id) returns all delivery records
-- for the given target, newest first (reverse insertion order).
function outbox_list_deliveries_for_target(target_id) -- luacheck: globals outbox_list_deliveries_for_target
  local result = {}
  for i = #_delivery_order, 1, -1 do
    local d = _deliveries[_delivery_order[i]]
    if d ~= nil and d.target_id == target_id then
      result[#result + 1] = d
    end
  end
  return result
end

-- outbox_update_delivery(delivery_id, fields) applies a partial update to a
-- delivery record.  Allowed fields: status, attempt_count, next_attempt_at,
-- last_http_status, last_error.  Always updates updated_at automatically.
-- Returns the updated delivery record, or nil if not found.
function outbox_update_delivery(delivery_id, fields) -- luacheck: globals outbox_update_delivery
  local d = _deliveries[delivery_id]
  if d == nil then
    return nil
  end
  if fields.status ~= nil then
    d.status = fields.status
  end
  if fields.attempt_count ~= nil then
    d.attempt_count = fields.attempt_count
  end
  if fields.next_attempt_at ~= nil then
    d.next_attempt_at = fields.next_attempt_at
  end
  if fields.last_http_status ~= nil then
    d.last_http_status = fields.last_http_status
  end
  if fields.last_error ~= nil then
    d.last_error = fields.last_error
  end
  d.updated_at = now_iso8601()
  return d
end

-- outbox_abandon_deliveries_for_target(target_id) moves all "pending" or "retrying"
-- deliveries for the given target to status="failed" with last_error="target deleted".
function outbox_abandon_deliveries_for_target(target_id) -- luacheck: globals outbox_abandon_deliveries_for_target
  local now = now_iso8601()
  for _, id in ipairs(_delivery_order) do
    local d = _deliveries[id]
    if d ~= nil and d.target_id == target_id then
      if d.status == "pending" or d.status == "retrying" then
        d.status = "failed"
        d.last_error = "target deleted"
        d.updated_at = now
      end
    end
  end
end

-- outbox_pending_retries() returns all delivery records with status="retrying"
-- and next_attempt_at <= now (ISO 8601 string comparison).
function outbox_pending_retries() -- luacheck: globals outbox_pending_retries
  local now = now_iso8601()
  local result = {}
  for _, id in ipairs(_delivery_order) do
    local d = _deliveries[id]
    if
      d ~= nil
      and d.status == "retrying"
      and d.next_attempt_at ~= nil
      and d.next_attempt_at <= now
    then
      result[#result + 1] = d
    end
  end
  return result
end

-- outbox_list_all_deliveries() returns all delivery records, newest first,
-- limited to 100 records.
function outbox_list_all_deliveries() -- luacheck: globals outbox_list_all_deliveries
  local result = {}
  local limit = 100
  for i = #_delivery_order, 1, -1 do
    local d = _deliveries[_delivery_order[i]]
    if d ~= nil then
      result[#result + 1] = d
      if #result >= limit then
        break
      end
    end
  end
  return result
end

-- outbox_prune(max_age_seconds) removes events (and their associated deliveries)
-- whose received_at timestamp is older than max_age_seconds ago.
function outbox_prune(max_age_seconds) -- luacheck: globals outbox_prune
  local cutoff = iso8601(os.time() - max_age_seconds)
  -- Collect event_ids to remove.
  local to_remove = {}
  local new_event_order = {}
  for _, id in ipairs(_event_order) do
    local ev = _events[id]
    if ev ~= nil and ev.received_at < cutoff then
      to_remove[id] = true
    else
      new_event_order[#new_event_order + 1] = id
    end
  end
  -- Remove events.
  for id in pairs(to_remove) do
    _events[id] = nil
  end
  _event_order = new_event_order
  -- Remove associated deliveries.
  local new_delivery_order = {}
  for _, id in ipairs(_delivery_order) do
    local d = _deliveries[id]
    if d ~= nil and to_remove[d.event_id] then
      _deliveries[id] = nil
    else
      new_delivery_order[#new_delivery_order + 1] = id
    end
  end
  _delivery_order = new_delivery_order
end
