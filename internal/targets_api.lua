-- Target registration API (confusio-specific).
--
-- Handles HTTP requests to /webhooks/targets*.
-- All endpoints require an Authorization header; missing auth → 401.
--
-- Routes:
--   GET    /webhooks/targets                         — list all non-deleted targets (200)
--   POST   /webhooks/targets                         — create a new target (201)
--   GET    /webhooks/targets/{target_id}             — get a single target (200)
--   PATCH  /webhooks/targets/{target_id}             — partial update (200)
--   DELETE /webhooks/targets/{target_id}             — soft-delete (204)
--   POST   /webhooks/targets/{target_id}/pause       — pause a target (200)
--   POST   /webhooks/targets/{target_id}/resume      — resume a paused target (200)
--
-- Globals exported:
--   make_targets_api(a) — factory; returns the closure installed as a.targets_api

-- _terr(status, code, msg) writes a JSON error response.
local function _terr(status, code, msg)
  respond_json(status, { error = code, message = msg })
end

-- make_targets_api(a) returns the closure that handles target registration requests.
function make_targets_api(_a) -- luacheck: globals make_targets_api
  return function()
    local method = GetMethod()
    local path = GetPath()

    -- All target API endpoints require an Authorization header.
    if not GetHeader("Authorization") then
      _terr(401, "unauthorized", "Admin credentials required.")
      return
    end

    -- POST /webhooks/targets/{target_id}/pause
    local pause_id = path:match("^/webhooks/targets/([^/]+)/pause$")
    if pause_id then
      if method == "POST" then
        local t = target_pause(pause_id)
        if t == nil then
          _terr(404, "target_not_found", "Target " .. pause_id .. " not found.")
          return
        end
        respond_json(200, t)
      else
        respond_json(405, { message = "Method Not Allowed" })
      end
      return
    end

    -- POST /webhooks/targets/{target_id}/resume
    local resume_id = path:match("^/webhooks/targets/([^/]+)/resume$")
    if resume_id then
      if method == "POST" then
        local t = target_resume(resume_id)
        if t == nil then
          _terr(404, "target_not_found", "Target " .. resume_id .. " not found.")
          return
        end
        respond_json(200, t)
      else
        respond_json(405, { message = "Method Not Allowed" })
      end
      return
    end

    -- /webhooks/targets/{target_id}
    local target_id = path:match("^/webhooks/targets/([^/]+)$")
    if target_id then
      if method == "GET" then
        local t = target_get(target_id)
        if t == nil then
          _terr(404, "target_not_found", "Target " .. target_id .. " not found.")
          return
        end
        respond_json(200, t)
      elseif method == "PATCH" then
        local ok_j, body = pcall(DecodeJson, GetBody() or "{}")
        if not ok_j or type(body) ~= "table" then
          _terr(400, "bad_request", "Invalid JSON body.")
          return
        end
        -- Only forward recognised fields; ignore unknown keys.
        local fields = {}
        if body.url ~= nil then
          fields.url = body.url
        end
        if body.events ~= nil then
          fields.events = body.events
        end
        if body.shape ~= nil then
          fields.shape = body.shape
        end
        if body.status ~= nil then
          fields.status = body.status
        end
        local t = target_update(target_id, fields)
        if t == nil then
          _terr(404, "target_not_found", "Target " .. target_id .. " not found.")
          return
        end
        respond_json(200, t)
      elseif method == "DELETE" then
        local ok_del = target_delete(target_id)
        if ok_del == nil then
          _terr(404, "target_not_found", "Target " .. target_id .. " not found.")
          return
        end
        set_preamble(204)
      else
        respond_json(405, { message = "Method Not Allowed" })
      end
      return
    end

    -- /webhooks/targets
    if path == "/webhooks/targets" then
      if method == "GET" then
        respond_json(200, target_list())
      elseif method == "POST" then
        local ok_j, body = pcall(DecodeJson, GetBody() or "{}")
        if not ok_j or type(body) ~= "table" then
          _terr(400, "bad_request", "Invalid JSON body.")
          return
        end
        if type(body.url) ~= "string" or body.url == "" then
          _terr(422, "validation_error", "Field 'url' is required and must be a non-empty string.")
          return
        end
        local t = target_create({
          url = body.url,
          events = body.events,
          shape = body.shape,
        })
        respond_json(201, t)
      else
        respond_json(405, { message = "Method Not Allowed" })
      end
      return
    end

    respond_json(404, { message = "Not Found" })
  end
end
