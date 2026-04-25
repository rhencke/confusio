-- Read-only delivery inspection API.
--
-- Handles HTTP requests to /webhooks/deliveries*.
-- All endpoints require an Authorization header; missing auth → 401.
--
-- Routes:
--   GET  /webhooks/deliveries                        — list all deliveries (newest first, max 100)
--   GET  /webhooks/deliveries/{delivery_id}          — get a single delivery record
--   GET  /webhooks/deliveries/{delivery_id}/attempts — attempt history for a delivery
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

    respond_json(404, { message = "Not Found" })
  end
end
