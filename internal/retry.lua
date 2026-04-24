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
-- Globals exported:
--   next_retry_at(attempt_number) → Unix timestamp (os.time() + delay)
--   maybe_retry_pending()         → call on each request; retries when interval has elapsed

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

-- maybe_retry_pending() polls outbox_pending_retries and drives one attempt
-- per eligible delivery, but runs at most once per _RETRY_INTERVAL_SECS.
function maybe_retry_pending() -- luacheck: globals maybe_retry_pending
  local now = os.time()
  if now - _last_retry_at >= _RETRY_INTERVAL_SECS then
    _last_retry_at = now
    local pending = outbox_pending_retries()
    for _, delivery in ipairs(pending) do
      deliver_attempt(delivery.delivery_id)
    end
  end
end
