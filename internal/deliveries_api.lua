-- Read-only API for delivery inspection.
--
-- Handles HTTP requests to /webhooks/deliveries*, /webhooks/events/{id}/deliveries,
-- and /webhooks/targets/{id}/deliveries.
-- All endpoints require an Authorization header; missing auth → 401.
--
-- Routes:
--   GET /webhooks/deliveries                        — list all deliveries (newest first, max 100)
--   GET /webhooks/deliveries/{delivery_id}          — get a single delivery record
--   GET /webhooks/events/{event_id}/deliveries      — list deliveries for an event
--   GET /webhooks/targets/{target_id}/deliveries    — list deliveries for a target
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

    if method ~= "GET" then
      respond_json(405, { message = "Method Not Allowed" })
      return
    end

    -- GET /webhooks/deliveries
    if path == "/webhooks/deliveries" then
      respond_json(200, outbox_list_all_deliveries())
      return
    end

    -- GET /webhooks/deliveries/{delivery_id}
    local delivery_id = path:match("^/webhooks/deliveries/([^/]+)$")
    if delivery_id then
      local d = outbox_get_delivery(delivery_id)
      if d == nil then
        _derr(404, "delivery_not_found", "Delivery " .. delivery_id .. " not found.")
        return
      end
      respond_json(200, d)
      return
    end

    -- GET /webhooks/events/{event_id}/deliveries
    local event_id = path:match("^/webhooks/events/([^/]+)/deliveries$")
    if event_id then
      local ev = outbox_get_event(event_id)
      if ev == nil then
        _derr(404, "event_not_found", "Event " .. event_id .. " not found.")
        return
      end
      respond_json(200, outbox_list_deliveries_for_event(event_id))
      return
    end

    -- GET /webhooks/targets/{target_id}/deliveries
    local target_id = path:match("^/webhooks/targets/([^/]+)/deliveries$")
    if target_id then
      local t = target_get(target_id)
      if t == nil then
        _derr(404, "target_not_found", "Target " .. target_id .. " not found.")
        return
      end
      respond_json(200, outbox_list_deliveries_for_target(target_id))
      return
    end

    respond_json(404, { message = "Not Found" })
  end
end
