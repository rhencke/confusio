-- Delivery inspection and replay API.
--
-- Handles HTTP requests to /webhooks/deliveries*, /webhooks/events/{id}/deliveries,
-- and /webhooks/targets/{id}/deliveries.
-- All endpoints require an Authorization header; missing auth → 401.
--
-- Routes:
--   GET  /webhooks/deliveries                           — list all deliveries (newest first, max 100)
--   GET  /webhooks/deliveries/{delivery_id}             — get a single delivery record
--   POST /webhooks/deliveries/{delivery_id}/redeliver   — redeliver: new delivery for same (event, target)
--   GET  /webhooks/deliveries/{delivery_id}/attempts    — attempt history for a delivery
--   GET  /webhooks/events/{event_id}/deliveries         — list deliveries for an event
--   GET  /webhooks/targets/{target_id}/deliveries       — list deliveries for a target
--
-- Globals exported:
--   make_deliveries_api(a) — factory; returns the closure installed as a.deliveries_api

-- _derr(status, code, msg) writes a JSON error response.
local function _derr(status, code, msg)
  respond_json(status, { error = code, message = msg })
end

-- make_deliveries_api(a) returns the closure that handles delivery inspection requests.
function make_deliveries_api(_a) -- luacheck: globals make_deliveries_api
  return function()
    local method = GetMethod()
    local path = GetPath()

    -- All admin API endpoints require an Authorization header.
    if not GetHeader("Authorization") then
      _derr(401, "unauthorized", "Admin credentials required.")
      return
    end

    -- GET /webhooks/deliveries
    if path == "/webhooks/deliveries" then
      if method == "GET" then
        respond_json(200, outbox_list_all_deliveries())
      else
        respond_json(405, { message = "Method Not Allowed" })
      end
      return
    end

    -- GET /webhooks/deliveries/{delivery_id}
    local delivery_id = path:match("^/webhooks/deliveries/([^/]+)$")
    if delivery_id then
      if method == "GET" then
        local d = outbox_get_delivery(delivery_id)
        if d == nil then
          _derr(404, "delivery_not_found", "Delivery " .. delivery_id .. " not found.")
          return
        end
        respond_json(200, d)
      else
        respond_json(405, { message = "Method Not Allowed" })
      end
      return
    end

    -- POST /webhooks/deliveries/{delivery_id}/redeliver
    -- Creates a new delivery for the same (event, target) pair and attempts it immediately.
    local redeliver_id = path:match("^/webhooks/deliveries/([^/]+)/redeliver$")
    if redeliver_id then
      if method == "POST" then
        local orig = outbox_get_delivery(redeliver_id)
        if orig == nil then
          _derr(404, "delivery_not_found", "Delivery " .. redeliver_id .. " not found.")
          return
        end
        -- Verify the event still exists (it may have been pruned).
        if outbox_get_event(orig.event_id) == nil then
          _derr(410, "event_expired", "The originating event has been pruned; cannot redeliver.")
          return
        end
        -- Create a fresh delivery for the same (event, target) pair.
        local new_d = outbox_create_delivery(orig.event_id, orig.target_id)
        -- Attempt delivery immediately (synchronous; retry scheduler handles backoff later).
        deliver_attempt(new_d.delivery_id)
        -- Return the updated delivery record (attempt may have changed its status).
        set_preamble(201)
        Write(EncodeJson(outbox_get_delivery(new_d.delivery_id)))
      else
        respond_json(405, { message = "Method Not Allowed" })
      end
      return
    end

    -- GET /webhooks/deliveries/{delivery_id}/attempts
    local attempts_id = path:match("^/webhooks/deliveries/([^/]+)/attempts$")
    if attempts_id then
      if method == "GET" then
        local attempts = outbox_get_attempts(attempts_id)
        if attempts == nil then
          _derr(404, "delivery_not_found", "Delivery " .. attempts_id .. " not found.")
          return
        end
        respond_json(200, attempts)
      else
        respond_json(405, { message = "Method Not Allowed" })
      end
      return
    end

    -- GET /webhooks/events/{event_id}/deliveries
    local event_id = path:match("^/webhooks/events/([^/]+)/deliveries$")
    if event_id then
      if method == "GET" then
        local ev = outbox_get_event(event_id)
        if ev == nil then
          _derr(404, "event_not_found", "Event " .. event_id .. " not found.")
          return
        end
        respond_json(200, outbox_list_deliveries_for_event(event_id))
      else
        respond_json(405, { message = "Method Not Allowed" })
      end
      return
    end

    -- GET /webhooks/targets/{target_id}/deliveries
    local target_id = path:match("^/webhooks/targets/([^/]+)/deliveries$")
    if target_id then
      if method == "GET" then
        local t = target_get(target_id)
        if t == nil then
          _derr(404, "target_not_found", "Target " .. target_id .. " not found.")
          return
        end
        respond_json(200, outbox_list_deliveries_for_target(target_id))
      else
        respond_json(405, { message = "Method Not Allowed" })
      end
      return
    end

    respond_json(404, { message = "Not Found" })
  end
end
