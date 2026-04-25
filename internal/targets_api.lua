-- Admin API for outbound webhook target management.
--
-- Handles HTTP requests to /webhooks/targets and /webhooks/targets/{target_id}.
-- All endpoints require an Authorization header; missing auth → 401.
--
-- Routes:
--   POST   /webhooks/targets              — create a target (201)
--   GET    /webhooks/targets              — list targets   (200)
--   GET    /webhooks/targets/{id}         — get a target   (200)
--   PATCH  /webhooks/targets/{id}         — update a target (200)
--   DELETE /webhooks/targets/{id}         — soft-delete    (204)
--   POST   /webhooks/targets/{id}/pause   — pause a target  (200)
--   POST   /webhooks/targets/{id}/resume  — resume a target (200)
--
-- Circuit breaker fields (circuit, circuit_open_until, consecutive_failures) appear
-- in single-target GET responses.  The circuit breaker is not yet implemented;
-- all targets report a healthy closed circuit until that task ships.
--
-- Globals exported:
--   make_targets_api(a) — factory; returns the closure installed as a.targets_api

-- _validate_url(url) returns true if url is an absolute http:// or https:// URL.
local function _validate_url(url)
  if type(url) ~= "string" or url == "" then
    return false
  end
  return url:match("^https?://%S") ~= nil
end

-- _validate_events(events) returns nil on success or an error string on failure.
-- Rules: must be a non-empty array; if "*" is present it must be the only element;
-- all values must be strings.
local function _validate_events(events)
  if type(events) ~= "table" or #events == 0 then
    return "events must be a non-empty array"
  end
  for _, e in ipairs(events) do
    if type(e) ~= "string" then
      return "event names must be strings"
    end
  end
  for _, e in ipairs(events) do
    if e == "*" then
      if #events ~= 1 then
        return 'wildcard "*" must be the sole element of the events array'
      end
      return nil
    end
  end
  return nil
end

-- _err(status, code, msg) writes a JSON error response and returns.
local function _err(status, code, msg)
  respond_json(status, { error = code, message = msg })
end

-- _with_circuit(t) decorates a public target record with stub circuit breaker fields.
-- These fields are included in single-target GET responses only.
-- Real circuit state will come from the circuit breaker module (future task).
local function _with_circuit(t)
  return {
    target_id = t.target_id,
    url = t.url,
    status = t.status,
    events = t.events,
    shape = t.shape,
    created_at = t.created_at,
    updated_at = t.updated_at,
    circuit = "closed",
    circuit_open_until = nil,
    consecutive_failures = 0,
  }
end

-- make_targets_api(a) returns the closure that handles all /webhooks/targets* requests.
function make_targets_api(_a) -- luacheck: globals make_targets_api
  return function()
    local method = GetMethod()
    local path = GetPath()

    -- All admin API endpoints require an Authorization header.
    if not GetHeader("Authorization") then
      _err(401, "unauthorized", "Admin credentials required.")
      return
    end

    -- Dispatch by path shape.
    local target_id = path:match("^/webhooks/targets/([^/]+)$")
    local pause_id = path:match("^/webhooks/targets/([^/]+)/pause$")
    local resume_id = path:match("^/webhooks/targets/([^/]+)/resume$")

    if path == "/webhooks/targets" then
      -- ── Collection endpoints ─────────────────────────────────────

      if method == "GET" then
        -- List targets.  Optional ?status= query param filters by status.
        -- Deleted targets are excluded by default.
        local status_param = GetParam("status")
        local filter = status_param ~= nil and status_param ~= "" and { status = status_param }
          or nil
        local targets = target_list(filter)
        respond_json(200, { targets = targets, next_cursor = nil })
      elseif method == "POST" then
        -- Create a target.
        local body_str = GetBody()
        local ok_parse, body = pcall(DecodeJson, body_str or "")
        if not ok_parse or type(body) ~= "table" then
          _err(400, "invalid_request", "Request body must be valid JSON.")
          return
        end
        -- Required: url.
        if body.url == nil then
          _err(400, "invalid_request", 'Field "url" is required.')
          return
        end
        if not _validate_url(body.url) then
          _err(400, "invalid_url", "url must be an absolute http:// or https:// URL.")
          return
        end
        -- Optional: events.
        if body.events ~= nil then
          local events_err = _validate_events(body.events)
          if events_err then
            _err(400, "invalid_filter", events_err)
            return
          end
        end
        -- Optional: shape.
        if body.shape ~= nil and body.shape ~= "github" and body.shape ~= "confusio" then
          _err(400, "invalid_request", 'shape must be "github" or "confusio".')
          return
        end
        local rec = target_create({
          url = body.url,
          events = body.events,
          shape = body.shape,
        })
        set_preamble(201)
        Write(EncodeJson(rec))
      else
        respond_json(405, { message = "Method Not Allowed" })
      end
    elseif target_id then
      -- ── Single-target endpoints ──────────────────────────────────

      if method == "GET" then
        local t = target_get(target_id)
        if t == nil then
          _err(404, "target_not_found", "Target " .. target_id .. " not found.")
          return
        end
        respond_json(200, _with_circuit(t))
      elseif method == "PATCH" then
        -- Verify the target exists before parsing the body.
        if target_get(target_id) == nil then
          _err(404, "target_not_found", "Target " .. target_id .. " not found.")
          return
        end
        local body_str = GetBody()
        local ok_parse, body = pcall(DecodeJson, body_str or "")
        if not ok_parse or type(body) ~= "table" then
          _err(400, "invalid_request", "Request body must be valid JSON.")
          return
        end
        if body.url ~= nil and not _validate_url(body.url) then
          _err(400, "invalid_url", "url must be an absolute http:// or https:// URL.")
          return
        end
        if body.events ~= nil then
          local events_err = _validate_events(body.events)
          if events_err then
            _err(400, "invalid_filter", events_err)
            return
          end
        end
        if body.shape ~= nil and body.shape ~= "github" and body.shape ~= "confusio" then
          _err(400, "invalid_request", 'shape must be "github" or "confusio".')
          return
        end
        if body.status ~= nil and body.status ~= "active" and body.status ~= "paused" then
          _err(400, "invalid_status", 'status must be "active" or "paused".')
          return
        end
        local updated = target_update(target_id, {
          url = body.url,
          events = body.events,
          shape = body.shape,
          status = body.status,
        })
        respond_json(200, _with_circuit(updated))
      elseif method == "DELETE" then
        local ok_del = target_delete(target_id)
        if not ok_del then
          _err(404, "target_not_found", "Target " .. target_id .. " not found.")
          return
        end
        set_preamble(204)
        Write("")
      else
        respond_json(405, { message = "Method Not Allowed" })
      end
    elseif pause_id then
      -- ── Pause endpoint ───────────────────────────────────────────

      if method == "POST" then
        local t = target_pause(pause_id)
        if t == nil then
          _err(404, "target_not_found", "Target " .. pause_id .. " not found.")
          return
        end
        respond_json(200, _with_circuit(t))
      else
        respond_json(405, { message = "Method Not Allowed" })
      end
    elseif resume_id then
      -- ── Resume endpoint ──────────────────────────────────────────

      if method == "POST" then
        local t = target_resume(resume_id)
        if t == nil then
          _err(404, "target_not_found", "Target " .. resume_id .. " not found.")
          return
        end
        respond_json(200, _with_circuit(t))
      else
        respond_json(405, { message = "Method Not Allowed" })
      end
    else
      respond_json(404, { message = "Not Found" })
    end
  end
end
