-- Per-target circuit breaker for the outbound webhook dispatcher.
--
-- Prevents hammering failing targets by tracking consecutive failures and
-- temporarily blocking delivery attempts when a target is misbehaving.
--
-- States (stored in module-local _cb_state table, NOT persisted):
--   "closed"    — normal operation; all attempts allowed
--   "open"      — target is failing; attempts blocked for CB_OPEN_SECS seconds
--   "half_open" — probe window; one attempt allowed; success → closed, failure → open
--
-- Globals exported:
--   CB_FAILURE_THRESHOLD   → consecutive failures required to trip the breaker (5)
--   CB_OPEN_SECS           → seconds the breaker stays open before entering half_open (300)
--   CB_HALF_OPEN_MAX       → max probe attempts allowed in half_open state (1)
--   cb_state(target_id)    → current state string for target
--   cb_record_success(target_id) → reset to closed
--   cb_record_failure(target_id) → increment failures; trip to open at threshold
--   cb_ok(target_id)       → true when an attempt is permitted (closed or half_open)

-- Number of consecutive failures that trip the breaker to "open".
CB_FAILURE_THRESHOLD = 5 -- luacheck: globals CB_FAILURE_THRESHOLD

-- Seconds the breaker stays "open" before transitioning to "half_open".
CB_OPEN_SECS = 300 -- luacheck: globals CB_OPEN_SECS

-- Maximum probe attempts allowed while in "half_open" state.
CB_HALF_OPEN_MAX = 1 -- luacheck: globals CB_HALF_OPEN_MAX

-- Module-local state table.  Not exported; tests exercise behaviour through the API.
-- _cb_state[target_id] = { state, opened_at, consecutive_failures }
local _cb_state = {}

-- cb_state(target_id) returns the current circuit-breaker state string for the target.
-- Unknown targets default to "closed".  Automatically transitions "open" → "half_open"
-- when CB_OPEN_SECS have elapsed since the breaker was tripped.
function cb_state(target_id) -- luacheck: globals cb_state
  local entry = _cb_state[target_id]
  if entry == nil then
    return "closed"
  end
  if entry.state == "open" and os.time() - entry.opened_at >= CB_OPEN_SECS then
    entry.state = "half_open"
  end
  return entry.state
end

-- cb_record_success(target_id) resets the breaker to "closed" and clears the
-- consecutive-failure counter.
function cb_record_success(target_id) -- luacheck: globals cb_record_success
  local entry = _cb_state[target_id]
  if entry == nil then
    return
  end
  entry.state = "closed"
  entry.consecutive_failures = 0
  entry.opened_at = nil
end

-- cb_record_failure(target_id) increments the consecutive-failure counter.
-- When the counter reaches CB_FAILURE_THRESHOLD, or when the current state is
-- "half_open", the breaker trips to "open" and opened_at is recorded.
function cb_record_failure(target_id) -- luacheck: globals cb_record_failure
  local entry = _cb_state[target_id]
  if entry == nil then
    entry = { state = "closed", opened_at = nil, consecutive_failures = 0 }
    _cb_state[target_id] = entry
  end
  if entry.state == "half_open" then
    -- Probe failed: go back to open immediately.
    entry.state = "open"
    entry.opened_at = os.time()
    return
  end
  entry.consecutive_failures = entry.consecutive_failures + 1
  if entry.consecutive_failures >= CB_FAILURE_THRESHOLD then
    entry.state = "open"
    entry.opened_at = os.time()
  end
end

-- cb_ok(target_id) returns true when the breaker permits an attempt.
-- "closed" and "half_open" both return true; "open" returns false.
function cb_ok(target_id) -- luacheck: globals cb_ok
  local s = cb_state(target_id)
  return s == "closed" or s == "half_open"
end
