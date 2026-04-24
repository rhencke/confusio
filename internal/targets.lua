-- In-memory target registry for the outbound webhook dispatcher.
--
-- A "target" is an HTTP(S) endpoint that receives delivered webhook events.
-- Each target has a stable UUID, URL, signing secret, event filter, shape,
-- status, and timestamps.
--
-- Globals exported:
--   target_create(fields)          — create and store a new target; returns public record
--   target_get(target_id)          — return public record, or nil if not found/deleted
--   target_list(filter)            — return array of public records (excludes deleted by default)
--   target_update(target_id, fields) — partial update; returns public record or nil
--   target_delete(target_id)       — soft-delete; returns true or nil
--   target_pause(target_id)        — pause a target; returns public record or nil
--   target_resume(target_id)       — resume a paused target; returns public record or nil
--   target_get_secret(target_id)   — return raw secret string (or nil); internal use only

-- Module-local storage.  Keyed by target_id; each entry stores all fields
-- including secret.  An ordered insertion list tracks creation order.
local _targets = {} -- target_id → full record
local _order = {} -- insertion-order list of target_ids

-- _public(record) returns a copy of record with the secret field omitted.
local function _public(r)
  return {
    target_id = r.target_id,
    url = r.url,
    status = r.status,
    events = r.events,
    shape = r.shape,
    created_at = r.created_at,
    updated_at = r.updated_at,
  }
end

-- target_create(fields) creates and stores a new target.
-- fields: { url, events?, shape?, secret? }
--   url     — required, absolute HTTP(S) URL
--   events  — optional array of event family names; defaults to {"*"}
--   shape   — optional "github" or "confusio"; defaults to "github"
--   secret  — optional HMAC signing secret string
-- Returns the public target record (without secret).
function target_create(fields) -- luacheck: globals target_create
  local now = now_iso8601()
  local id = make_uuid()
  local record = {
    target_id = id,
    url = fields.url,
    status = "active",
    events = fields.events or { "*" },
    shape = fields.shape or "github",
    secret = fields.secret or nil,
    created_at = now,
    updated_at = now,
  }
  _targets[id] = record
  _order[#_order + 1] = id
  return _public(record)
end

-- target_get(target_id) returns the public record for the given id,
-- or nil if the target does not exist or has been soft-deleted.
function target_get(target_id) -- luacheck: globals target_get
  local r = _targets[target_id]
  if r == nil or r.status == "deleted" then
    return nil
  end
  return _public(r)
end

-- target_list(filter) returns an array of public target records in creation order.
-- filter is an optional table with an optional "status" key.
-- Deleted targets are excluded unless filter.status == "deleted".
function target_list(filter) -- luacheck: globals target_list
  local want_status = filter and filter.status
  local result = {}
  for _, id in ipairs(_order) do
    local r = _targets[id]
    if r ~= nil then
      if want_status ~= nil then
        -- Explicit status filter: include only matching records.
        if r.status == want_status then
          result[#result + 1] = _public(r)
        end
      else
        -- Default: exclude deleted targets.
        if r.status ~= "deleted" then
          result[#result + 1] = _public(r)
        end
      end
    end
  end
  return result
end

-- target_update(target_id, fields) applies a partial update to an existing target.
-- fields: { url?, events?, shape?, status?, secret? }
--   secret may be set to false to remove the signing secret.
--   status "deleted" is not accepted here; use target_delete instead.
-- Returns the updated public record, or nil if not found or already deleted.
function target_update(target_id, fields) -- luacheck: globals target_update
  local r = _targets[target_id]
  if r == nil or r.status == "deleted" then
    return nil
  end
  if fields.url ~= nil then
    r.url = fields.url
  end
  if fields.events ~= nil then
    r.events = fields.events
  end
  if fields.shape ~= nil then
    r.shape = fields.shape
  end
  if fields.status ~= nil and fields.status ~= "deleted" then
    r.status = fields.status
  end
  -- secret = false removes the secret; any other non-nil value sets it.
  if fields.secret == false then
    r.secret = nil
  elseif fields.secret ~= nil then
    r.secret = fields.secret
  end
  r.updated_at = now_iso8601()
  return _public(r)
end

-- target_delete(target_id) soft-deletes a target by setting its status to "deleted".
-- Also abandons any pending or retrying deliveries for the target.
-- Returns true on success, or nil if the target is not found or already deleted.
function target_delete(target_id) -- luacheck: globals target_delete
  local r = _targets[target_id]
  if r == nil or r.status == "deleted" then
    return nil
  end
  r.status = "deleted"
  r.updated_at = now_iso8601()
  outbox_abandon_deliveries_for_target(target_id)
  return true
end

-- target_pause(target_id) sets a target's status to "paused".
-- Returns the updated public record, or nil if not found or already deleted.
function target_pause(target_id) -- luacheck: globals target_pause
  local r = _targets[target_id]
  if r == nil or r.status == "deleted" then
    return nil
  end
  r.status = "paused"
  r.updated_at = now_iso8601()
  return _public(r)
end

-- target_resume(target_id) sets a target's status back to "active".
-- Returns the updated public record, or nil if not found or already deleted.
function target_resume(target_id) -- luacheck: globals target_resume
  local r = _targets[target_id]
  if r == nil or r.status == "deleted" then
    return nil
  end
  r.status = "active"
  r.updated_at = now_iso8601()
  return _public(r)
end

-- target_get_secret(target_id) returns the raw secret string for the given target,
-- or nil if the target does not exist or has no secret configured.
-- This is for internal dispatcher use only — never include secrets in API responses.
function target_get_secret(target_id) -- luacheck: globals target_get_secret
  local r = _targets[target_id]
  if r == nil then
    return nil
  end
  return r.secret
end
