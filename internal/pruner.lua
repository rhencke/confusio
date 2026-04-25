-- Periodic outbox pruning for the 72-hour retention policy.
--
-- maybe_prune_outbox() is called on every HTTP request but does real work at
-- most once per PRUNE_INTERVAL_SECS (one hour) to keep per-request overhead
-- negligible.  On the first request after startup, _last_prune_at == 0 so
-- pruning always runs immediately, clearing any stale events from a previous
-- server run (if the outbox were persisted).
--
-- Globals exported:
--   OUTBOX_MAX_AGE_SECS  — 72 hours in seconds; events older than this are pruned
--   maybe_prune_outbox() — call on each request; prunes when interval has elapsed

-- 72 hours in seconds: the maximum age of an event before it is eligible for pruning.
OUTBOX_MAX_AGE_SECS = 72 * 3600 -- luacheck: globals OUTBOX_MAX_AGE_SECS

-- How often (in seconds) the prune pass actually runs.  One hour is fine for a
-- 72-hour retention window — events are never more than ~1 h past their deadline.
local _PRUNE_INTERVAL_SECS = 3600

-- os.time() of the last completed prune pass.  Zero means "never pruned";
-- the first request will always trigger a pass.
local _last_prune_at = 0

-- maybe_prune_outbox() runs outbox_prune(OUTBOX_MAX_AGE_SECS) if at least
-- _PRUNE_INTERVAL_SECS seconds have elapsed since the last pass.
function maybe_prune_outbox() -- luacheck: globals maybe_prune_outbox
  local now = os.time()
  if now - _last_prune_at >= _PRUNE_INTERVAL_SECS then
    outbox_prune(OUTBOX_MAX_AGE_SECS)
    _last_prune_at = now
  end
end
