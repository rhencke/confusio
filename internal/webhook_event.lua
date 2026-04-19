-- Shared webhook event mapping infrastructure.
--
-- Provides the canonical internal event representation used by all backend
-- normalizer functions registered via b:webhook(event, fn).
--
-- Convention for normalizer return values:
--
--   Known action:
--     return make_internal_event {
--       event    = "issues",
--       action   = "opened",
--       provider = "gitea",
--       raw      = payload,
--       data     = { ... },
--     }
--
--   Unrecognized action:
--     return make_internal_event {
--       event      = "issues",
--       action     = "unknown",
--       raw_action = payload.action,   -- the original unrecognized string
--       provider   = "gitea",
--       raw        = payload,
--       data       = { ... },
--     }
--     The receiver sets X-Confusio-Raw-Action: <raw_action> on the 200 response
--     so operators can identify unrecognized actions without breaking delivery.
--
-- Globals exported:
--   make_internal_event   — internal event factory

-- make_internal_event(fields) constructs the canonical internal event table.
--
-- Required fields (normalizer must supply):
--   event    (string) — GitHub event family name, e.g. "issues", "issue_comment"
--   action   (string) — canonical GitHub action name, or "unknown" for unrecognized actions
--   provider (string) — originating backend name, e.g. "gitea", "gitlab"
--   raw      (table)  — original decoded forge payload, unmodified
--   data     (table)  — normalized, provider-agnostic field bag
--
-- Optional fields:
--   raw_action (string) — original, unrecognized action string; set only when
--                         action == "unknown".  The receiver surfaces this value in the
--                         X-Confusio-Raw-Action response header so operators can
--                         inspect unrecognized event variants.
--   timestamp  (string) — ISO 8601 event timestamp from the forge; defaults to ""
--                         when the forge payload does not include one.
function make_internal_event(fields) -- luacheck: globals make_internal_event
  return {
    event = fields.event or "",
    action = fields.action or "",
    raw_action = fields.raw_action,
    provider = fields.provider or "",
    timestamp = fields.timestamp or "",
    raw = fields.raw or {},
    data = fields.data or {},
  }
end
