-- UUID v4 generation and ISO 8601 timestamp utilities.
--
-- These are used by the outbound webhook dispatcher for delivery IDs,
-- target IDs, attempt IDs, and timestamp fields.
--
-- make_uuid()     — returns a UUID v4 string (e.g. "a2fb4a9c-1234-4abc-8def-000000000001")
-- iso8601(t)      — formats Unix epoch t as ISO 8601 UTC string (e.g. "2026-04-24T21:00:00Z")
-- now_iso8601()   — returns the current time formatted as ISO 8601 UTC
--
-- make_uuid() uses GetRandomBytes(16) — a Redbean built-in that returns
-- cryptographically secure random bytes.  Unit tests stub GetRandomBytes to a
-- deterministic sequence.
--
-- Globals exported:
--   make_uuid, iso8601, now_iso8601

-- make_uuid() generates a UUID v4 (random) string.
-- Format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
-- where 4 is the version nibble and y is the variant nibble (8, 9, a, or b).
function make_uuid() -- luacheck: globals make_uuid
  local b = GetRandomBytes(16) -- luacheck: globals GetRandomBytes
  -- Set version 4: high nibble of byte 7 = 0x4
  local b7 = (b:byte(7) & 0x0f) | 0x40
  -- Set variant 1: high 2 bits of byte 9 = 10xxxxxx
  local b9 = (b:byte(9) & 0x3f) | 0x80
  return string.format(
    "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
    b:byte(1),
    b:byte(2),
    b:byte(3),
    b:byte(4),
    b:byte(5),
    b:byte(6),
    b7,
    b:byte(8),
    b9,
    b:byte(10),
    b:byte(11),
    b:byte(12),
    b:byte(13),
    b:byte(14),
    b:byte(15),
    b:byte(16)
  )
end

-- iso8601(t) formats a Unix epoch timestamp as an ISO 8601 UTC string.
-- Example: iso8601(0) → "1970-01-01T00:00:00Z"
function iso8601(t) -- luacheck: globals iso8601
  return os.date("!%Y-%m-%dT%H:%M:%SZ", t)
end

-- now_iso8601() returns the current time formatted as ISO 8601 UTC.
function now_iso8601() -- luacheck: globals now_iso8601
  return iso8601(os.time())
end
