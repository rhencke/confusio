-- SQLite-backed outbox for the outbound webhook dispatcher.
--
-- The outbox stores two kinds of records in a local SQLite database:
--
--   Event records    — one per inbound webhook event received.
--   Delivery records — one per (event, target) pair, tracking dispatch state.
--   Attempt records  — one per HTTP POST attempt, stored in a separate table.
--
-- The database path is read from config.outbox_db at module load time.
-- It defaults to ":memory:" (transient, cleared on restart).  Set
-- CONFUSIO_OUTBOX_DB to a file path in .init.lua for persistence.
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
--   outbox_record_attempt(delivery_id, fields)
--   outbox_get_attempts(delivery_id)
--   outbox_pending_retries()
--   outbox_list_all_deliveries()
--   outbox_prune(max_age_seconds)

local _sq = require("lsqlite3")
local _db

-- _open_db(path) opens (or creates) the SQLite database and initialises the schema.
-- ":memory:" creates a transient in-memory database.
local function _open_db(path)
  path = path or ":memory:"
  _db = _sq.open(path)
  if not _db then
    error("outbox: cannot open database: " .. tostring(path))
  end
  _db:exec("PRAGMA journal_mode=WAL")
  _db:exec([[
    CREATE TABLE IF NOT EXISTS events (
      event_id    TEXT PRIMARY KEY,
      received_at TEXT NOT NULL,
      backend     TEXT NOT NULL,
      event_type  TEXT NOT NULL,
      payload     TEXT NOT NULL
    )
  ]])
  _db:exec([[
    CREATE TABLE IF NOT EXISTS deliveries (
      delivery_id      TEXT PRIMARY KEY,
      event_id         TEXT NOT NULL,
      target_id        TEXT NOT NULL,
      status           TEXT NOT NULL,
      attempt_count    INTEGER NOT NULL DEFAULT 0,
      next_attempt_at  TEXT,
      last_http_status INTEGER,
      last_error       TEXT,
      created_at       TEXT NOT NULL,
      updated_at       TEXT NOT NULL
    )
  ]])
  _db:exec("CREATE INDEX IF NOT EXISTS idx_del_event  ON deliveries(event_id)")
  _db:exec("CREATE INDEX IF NOT EXISTS idx_del_target ON deliveries(target_id)")
  _db:exec("CREATE INDEX IF NOT EXISTS idx_del_retry  ON deliveries(status, next_attempt_at)")
  _db:exec([[
    CREATE TABLE IF NOT EXISTS attempts (
      id             INTEGER PRIMARY KEY AUTOINCREMENT,
      delivery_id    TEXT NOT NULL,
      attempt_number INTEGER NOT NULL,
      attempted_at   TEXT NOT NULL,
      http_status    INTEGER,
      error          TEXT,
      outcome        TEXT NOT NULL
    )
  ]])
  _db:exec("CREATE INDEX IF NOT EXISTS idx_att_delivery ON attempts(delivery_id)")
end

-- _exec(sql, ...) executes a SQL statement, binding ? parameters to the given values.
local function _exec(sql, ...)
  local stmt = _db:prepare(sql)
  stmt:bind_values(...)
  stmt:step()
  stmt:finalize()
end

-- _one(sql, ...) returns the first result row as a named-key table, or nil.
local function _one(sql, ...)
  local stmt = _db:prepare(sql)
  stmt:bind_values(...)
  local row
  if stmt:step() == _sq.ROW then
    row = stmt:get_named_values()
  end
  stmt:finalize()
  return row
end

-- _all(sql, ...) returns all result rows as an array of named-key tables.
local function _all(sql, ...)
  local stmt = _db:prepare(sql)
  stmt:bind_values(...)
  local rows = {}
  while stmt:step() == _sq.ROW do
    rows[#rows + 1] = stmt:get_named_values()
  end
  stmt:finalize()
  return rows
end

-- _to_event(row) builds an event record from a SQLite row.
-- Payload is decoded from JSON back to a Lua value.
local function _to_event(row)
  return {
    event_id = row.event_id,
    received_at = row.received_at,
    backend = row.backend,
    event_type = row.event_type,
    payload = DecodeJson(row.payload), -- luacheck: globals DecodeJson
  }
end

-- _to_delivery(row) builds a delivery record from a SQLite row.
-- SQLite NULLs map to nil automatically via get_named_values.
local function _to_delivery(row)
  return {
    delivery_id = row.delivery_id,
    event_id = row.event_id,
    target_id = row.target_id,
    status = row.status,
    attempt_count = row.attempt_count,
    next_attempt_at = row.next_attempt_at,
    last_http_status = row.last_http_status,
    last_error = row.last_error,
    created_at = row.created_at,
    updated_at = row.updated_at,
  }
end

-- _to_attempt(row) builds an attempt record from a SQLite row.
local function _to_attempt(row)
  return {
    attempt_number = row.attempt_number,
    attempted_at = row.attempted_at,
    http_status = row.http_status,
    error = row.error,
    outcome = row.outcome,
  }
end

-- Open the database.  config.outbox_db is set in .init.lua from CONFUSIO_OUTBOX_DB;
-- if absent, fall back to ":memory:" (transient, cleared on restart).
_open_db(config and config.outbox_db or ":memory:") -- luacheck: globals config

-- outbox_store_event(backend, event_type, payload) stores a new inbound event.
-- payload may be any JSON-serialisable Lua value (table, string, etc.).
-- Uses INSERT OR REPLACE so that deterministic test UUIDs do not cause
-- primary-key errors; associated deliveries and their attempts are pruned first.
-- Returns the event record.
function outbox_store_event(backend, event_type, payload) -- luacheck: globals outbox_store_event
  local id = make_uuid() -- luacheck: globals make_uuid
  local now = now_iso8601() -- luacheck: globals now_iso8601
  -- Cascade-clean any deliveries (and their attempts) for the old event with
  -- this id before replacing it, so no stale attempt rows accumulate.
  _exec(
    "DELETE FROM attempts WHERE delivery_id IN (SELECT delivery_id FROM deliveries WHERE event_id = ?)",
    id
  )
  _exec("DELETE FROM deliveries WHERE event_id = ?", id)
  _exec(
    "INSERT OR REPLACE INTO events (event_id, received_at, backend, event_type, payload) VALUES (?,?,?,?,?)",
    id,
    now,
    backend,
    event_type,
    EncodeJson(payload) -- luacheck: globals EncodeJson
  )
  return {
    event_id = id,
    received_at = now,
    backend = backend,
    event_type = event_type,
    payload = payload,
  }
end

-- outbox_get_event(event_id) returns the event record, or nil.
function outbox_get_event(event_id) -- luacheck: globals outbox_get_event
  local row = _one("SELECT * FROM events WHERE event_id = ?", event_id)
  return row and _to_event(row)
end

-- outbox_create_delivery(event_id, target_id) creates a new delivery record.
-- Initial status is "pending".
-- Uses INSERT OR REPLACE; any existing attempts for this delivery_id are deleted
-- first so callers always receive a delivery with a clean attempt history.
-- Returns the delivery record.
function outbox_create_delivery(event_id, target_id) -- luacheck: globals outbox_create_delivery
  local id = make_uuid()
  local now = now_iso8601()
  -- Delete any stale attempts before replacing the delivery row.
  _exec("DELETE FROM attempts WHERE delivery_id = ?", id)
  _exec(
    [[INSERT OR REPLACE INTO deliveries
        (delivery_id, event_id, target_id, status, attempt_count,
         next_attempt_at, last_http_status, last_error, created_at, updated_at)
      VALUES (?,?,?,'pending',0, NULL,NULL,NULL, ?,?)]],
    id,
    event_id,
    target_id,
    now,
    now
  )
  return {
    delivery_id = id,
    event_id = event_id,
    target_id = target_id,
    status = "pending",
    attempt_count = 0,
    next_attempt_at = nil,
    last_http_status = nil,
    last_error = nil,
    created_at = now,
    updated_at = now,
  }
end

-- outbox_get_delivery(delivery_id) returns the delivery record, or nil.
function outbox_get_delivery(delivery_id) -- luacheck: globals outbox_get_delivery
  local row = _one("SELECT * FROM deliveries WHERE delivery_id = ?", delivery_id)
  return row and _to_delivery(row)
end

-- outbox_list_deliveries_for_event(event_id) returns all delivery records
-- for the given event, in creation order.
function outbox_list_deliveries_for_event(event_id) -- luacheck: globals outbox_list_deliveries_for_event
  local rows = _all("SELECT * FROM deliveries WHERE event_id = ? ORDER BY created_at ASC", event_id)
  local result = {}
  for _, row in ipairs(rows) do
    result[#result + 1] = _to_delivery(row)
  end
  return result
end

-- outbox_list_deliveries_for_target(target_id) returns all delivery records
-- for the given target, newest first.
function outbox_list_deliveries_for_target(target_id) -- luacheck: globals outbox_list_deliveries_for_target
  local rows =
    _all("SELECT * FROM deliveries WHERE target_id = ? ORDER BY created_at DESC", target_id)
  local result = {}
  for _, row in ipairs(rows) do
    result[#result + 1] = _to_delivery(row)
  end
  return result
end

-- outbox_update_delivery(delivery_id, fields) applies a partial update.
-- Allowed fields: status, attempt_count, next_attempt_at, last_http_status, last_error.
-- Always bumps updated_at.  Returns the updated record, or nil if not found.
function outbox_update_delivery(delivery_id, fields) -- luacheck: globals outbox_update_delivery
  local parts = {}
  local vals = {}
  if fields.status ~= nil then
    parts[#parts + 1] = "status = ?"
    vals[#vals + 1] = fields.status
  end
  if fields.attempt_count ~= nil then
    parts[#parts + 1] = "attempt_count = ?"
    vals[#vals + 1] = fields.attempt_count
  end
  if fields.next_attempt_at ~= nil then
    parts[#parts + 1] = "next_attempt_at = ?"
    vals[#vals + 1] = fields.next_attempt_at
  end
  if fields.last_http_status ~= nil then
    parts[#parts + 1] = "last_http_status = ?"
    vals[#vals + 1] = fields.last_http_status
  end
  if fields.last_error ~= nil then
    parts[#parts + 1] = "last_error = ?"
    vals[#vals + 1] = fields.last_error
  end
  parts[#parts + 1] = "updated_at = ?"
  vals[#vals + 1] = now_iso8601()
  vals[#vals + 1] = delivery_id
  local sql = "UPDATE deliveries SET " .. table.concat(parts, ", ") .. " WHERE delivery_id = ?"
  _exec(sql, table.unpack(vals))
  return outbox_get_delivery(delivery_id)
end

-- outbox_abandon_deliveries_for_target(target_id) moves all "pending" or
-- "retrying" deliveries for the given target to status="failed".
function outbox_abandon_deliveries_for_target(target_id) -- luacheck: globals outbox_abandon_deliveries_for_target
  _exec(
    [[UPDATE deliveries
        SET status = 'failed', last_error = 'target deleted', updated_at = ?
      WHERE target_id = ? AND status IN ('pending','retrying')]],
    now_iso8601(),
    target_id
  )
end

-- outbox_record_attempt(delivery_id, fields) appends one attempt record.
-- fields: { http_status?, error?, outcome }.
-- outcome is one of "delivered", "retrying", "failed".
-- Returns the new attempt record, or nil if the delivery is not found.
function outbox_record_attempt(delivery_id, fields) -- luacheck: globals outbox_record_attempt
  -- Verify the delivery exists before inserting.
  local drow = _one("SELECT delivery_id FROM deliveries WHERE delivery_id = ?", delivery_id)
  if not drow then
    return nil
  end
  local cnt_row = _one("SELECT COUNT(*) AS cnt FROM attempts WHERE delivery_id = ?", delivery_id)
  local attempt_number = (cnt_row and cnt_row.cnt or 0) + 1
  local now = now_iso8601()
  _exec(
    [[INSERT INTO attempts
        (delivery_id, attempt_number, attempted_at, http_status, error, outcome)
      VALUES (?,?,?,?,?,?)]],
    delivery_id,
    attempt_number,
    now,
    fields.http_status,
    fields.error,
    fields.outcome
  )
  return {
    attempt_number = attempt_number,
    attempted_at = now,
    http_status = fields.http_status,
    error = fields.error,
    outcome = fields.outcome,
  }
end

-- outbox_get_attempts(delivery_id) returns the attempts array for the given
-- delivery (ordered by insertion), or nil if the delivery is not found.
function outbox_get_attempts(delivery_id) -- luacheck: globals outbox_get_attempts
  local drow = _one("SELECT delivery_id FROM deliveries WHERE delivery_id = ?", delivery_id)
  if not drow then
    return nil
  end
  local rows = _all("SELECT * FROM attempts WHERE delivery_id = ? ORDER BY id ASC", delivery_id)
  local result = {}
  for _, row in ipairs(rows) do
    result[#result + 1] = _to_attempt(row)
  end
  return result
end

-- outbox_pending_retries() returns all delivery records with status="retrying"
-- and next_attempt_at <= now (ISO 8601 string comparison).
function outbox_pending_retries() -- luacheck: globals outbox_pending_retries
  local now = now_iso8601()
  local rows = _all(
    [[SELECT * FROM deliveries
       WHERE status = 'retrying'
         AND next_attempt_at IS NOT NULL
         AND next_attempt_at <= ?]],
    now
  )
  local result = {}
  for _, row in ipairs(rows) do
    result[#result + 1] = _to_delivery(row)
  end
  return result
end

-- outbox_list_all_deliveries() returns all delivery records, newest first,
-- limited to 100 records.
function outbox_list_all_deliveries() -- luacheck: globals outbox_list_all_deliveries
  local rows = _all("SELECT * FROM deliveries ORDER BY created_at DESC LIMIT 100")
  local result = {}
  for _, row in ipairs(rows) do
    result[#result + 1] = _to_delivery(row)
  end
  return result
end

-- outbox_prune(max_age_seconds) removes events (and associated deliveries and
-- attempts) whose received_at is older than max_age_seconds ago.
function outbox_prune(max_age_seconds) -- luacheck: globals outbox_prune
  local cutoff = iso8601(os.time() - max_age_seconds) -- luacheck: globals iso8601
  _db:exec("BEGIN")
  _exec(
    [[DELETE FROM attempts
       WHERE delivery_id IN (
         SELECT delivery_id FROM deliveries
          WHERE event_id IN (SELECT event_id FROM events WHERE received_at < ?)
       )]],
    cutoff
  )
  _exec(
    "DELETE FROM deliveries WHERE event_id IN (SELECT event_id FROM events WHERE received_at < ?)",
    cutoff
  )
  _exec("DELETE FROM events WHERE received_at < ?", cutoff)
  _db:exec("COMMIT")
end
