-- Retry scheduler for outbound webhook deliveries.
--
-- next_retry_at(attempt_number) returns the Unix timestamp at which the next
-- delivery attempt should be made, using exponential backoff with jitter:
--   delay = min(base * 2^(attempt-1), max) + random_jitter
--
-- maybe_retry_pending() is called on every HTTP request (like maybe_prune_outbox)
-- but does real work at most once per RETRY_INTERVAL_SECS to keep per-request
-- overhead negligible.  It fetches all deliveries eligible for retry and calls
-- deliver_attempt for each.
--
-- retry_budget_ok(target_id) returns true when the target has not exhausted its
-- per-hour or per-day retry attempt budget.  Counts attempts with outcome="retry"
-- recorded within the rolling window using ISO 8601 lexicographic comparison.
--
-- Globals exported:
--   RETRY_BUDGET_HOURLY           → max retry attempts per target per hour (10)
--   RETRY_BUDGET_DAILY            → max retry attempts per target per 24 hours (50)
--   next_retry_at(attempt_number) → Unix timestamp (os.time() + delay)
--   retry_budget_ok(target_id)   → true if target has remaining retry budget
--   maybe_retry_pending()         → call on each request; retries when interval has elapsed

-- Max retry attempts per target per rolling hour.
RETRY_BUDGET_HOURLY = 10 -- luacheck: globals RETRY_BUDGET_HOURLY

-- Max retry attempts per target per rolling 24-hour window.
RETRY_BUDGET_DAILY = 50 -- luacheck: globals RETRY_BUDGET_DAILY

-- Base delay in seconds for the first retry (attempt 1 → base seconds).
local _BASE_DELAY_SECS = 60

-- Maximum delay cap so retries never wait longer than one hour.
local _MAX_DELAY_SECS = 3600

-- Maximum random jitter added to each delay (uniform [0, _JITTER_SECS]).
local _JITTER_SECS = 30

-- How often (in seconds) the retry polling pass actually runs.
local _RETRY_INTERVAL_SECS = 30

-- os.time() of the last completed retry pass.  Zero means "never ran";
-- the first request will always trigger a pass.
local _last_retry_at = 0

-- Seed the random number generator once at module load for production jitter.
math.randomseed(os.time())

-- next_retry_at(attempt_number) computes the next-attempt timestamp.
-- attempt_number is the attempt count AFTER recording the current attempt
-- (i.e. 1 for the first retry, 2 for the second, etc.).
function next_retry_at(attempt_number) -- luacheck: globals next_retry_at
  local exp = attempt_number - 1
  local delay = _BASE_DELAY_SECS * (2 ^ exp)
  if delay > _MAX_DELAY_SECS then
    delay = _MAX_DELAY_SECS
  end
  delay = delay + math.random(0, _JITTER_SECS)
  return os.time() + delay
end

-- retry_budget_ok(target_id) returns true when the target has not exhausted its
-- hourly (RETRY_BUDGET_HOURLY) or daily (RETRY_BUDGET_DAILY) retry attempt budget.
-- Counts attempts with outcome="retrying" within the rolling window using ISO 8601
-- lexicographic comparison (UTC zero-padded strings sort correctly).
function retry_budget_ok(target_id) -- luacheck: globals retry_budget_ok
  local now = os.time()
  local hour_cutoff = iso8601(now - 3600)
  local day_cutoff = iso8601(now - 86400)
  local hour_count = 0
  local day_count = 0
  local seen = {}
  local deliveries = outbox_list_deliveries_for_target(target_id)
  for _, delivery in ipairs(deliveries) do
    local did = delivery.delivery_id
    if not seen[did] then
      seen[did] = true
      local attempts = outbox_get_attempts(did)
      if attempts ~= nil then
        for _, attempt in ipairs(attempts) do
          if attempt.outcome == "retrying" and attempt.attempted_at > day_cutoff then
            day_count = day_count + 1
            if attempt.attempted_at > hour_cutoff then
              hour_count = hour_count + 1
            end
          end
        end
      end
    end
  end
  return hour_count < RETRY_BUDGET_HOURLY and day_count < RETRY_BUDGET_DAILY
end

-- maybe_retry_pending() polls outbox_pending_retries and drives one attempt
-- per eligible delivery, but runs at most once per _RETRY_INTERVAL_SECS.
-- Deliveries whose target has exhausted its retry budget are skipped.
function maybe_retry_pending() -- luacheck: globals maybe_retry_pending
  local now = os.time()
  if now - _last_retry_at >= _RETRY_INTERVAL_SECS then
    _last_retry_at = now
    local pending = outbox_pending_retries()
    for _, delivery in ipairs(pending) do
      local d = outbox_get_delivery(delivery.delivery_id)
      if d ~= nil and retry_budget_ok(d.target_id) then
        deliver_attempt(delivery.delivery_id)
      end
    end
  end
end
