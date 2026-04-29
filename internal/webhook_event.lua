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
--   make_internal_event              — internal event factory
--   normalized_webhook_event_type    — normalized event namespace helper
--   make_normalized_webhook_envelope — normalized event envelope factory

local NORMALIZED_EVENT_BASES = {
  branch_protection_configuration = "branch_protection_configuration",
  branch_protection_rule = "branch_protection_rule",
  check_run = "check_run",
  check_suite = "check_suite",
  code_scanning_alert = "code_scanning_alert",
  create = "create",
  custom_property = "custom_property",
  custom_property_values = "custom_property_values",
  delete = "delete",
  dependabot_alert = "dependabot_alert",
  deploy_key = "deploy_key",
  deployment = "deployment",
  deployment_protection_rule = "deployment.protection_rule",
  deployment_review = "deployment.review",
  deployment_status = "deployment.status",
  discussion = "discussion",
  discussion_comment = "discussion.comment",
  fork = "fork",
  github_app_authorization = "github_app_authorization",
  gollum = "gollum",
  installation = "installation",
  installation_repositories = "installation.repositories",
  installation_target = "installation.target",
  issue_comment = "issue.comment",
  issues = "issue",
  label = "label",
  marketplace_purchase = "marketplace_purchase",
  member = "member",
  membership = "membership",
  merge_group = "merge_group",
  meta = "meta",
  milestone = "milestone",
  org_block = "org_block",
  organization = "organization",
  package = "package",
  page_build = "page_build",
  personal_access_token_request = "personal_access_token_request",
  ping = "ping",
  project = "project",
  project_card = "project.card",
  project_column = "project.column",
  projects_v2 = "projects_v2",
  projects_v2_item = "projects_v2.item",
  projects_v2_status_update = "projects_v2.status_update",
  public = "public",
  pull_request = "pull_request",
  pull_request_review = "pull_request.review",
  pull_request_review_comment = "pull_request.review_comment",
  pull_request_review_thread = "pull_request.review_thread",
  push = "push",
  registry_package = "registry_package",
  release = "release",
  repository = "repository",
  repository_advisory = "repository.advisory",
  repository_dispatch = "repository.dispatch",
  repository_import = "repository.import",
  repository_ruleset = "repository.ruleset",
  repository_vulnerability_alert = "repository.vulnerability_alert",
  secret_scanning_alert = "secret_scanning_alert",
  secret_scanning_alert_location = "secret_scanning_alert.location",
  security_advisory = "security_advisory",
  security_and_analysis = "security_and_analysis",
  sponsorship = "sponsorship",
  star = "star",
  status = "status",
  sub_issues = "sub_issues",
  team = "team",
  team_add = "team.add",
  watch = "watch",
  workflow_dispatch = "workflow.dispatch",
  workflow_job = "workflow.job",
  workflow_run = "workflow.run",
}

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

-- normalized_webhook_event_type(event, action) returns the stable dotted
-- confusio event namespace used by normalized webhook deliveries.
--
-- Examples:
--   issues/opened                  -> issue.opened
--   issue_comment/created          -> issue.comment.created
--   pull_request_review/submitted  -> pull_request.review.submitted
--
-- Action-less events return only their event-family name.
function normalized_webhook_event_type(event, action) -- luacheck: globals normalized_webhook_event_type
  local base = NORMALIZED_EVENT_BASES[event] or event or ""
  if action and action ~= "" then
    return base .. "." .. action
  end
  return base
end

local function fallback_time()
  if type(now_iso8601) == "function" then -- luacheck: globals now_iso8601
    return now_iso8601()
  end
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function fallback_id()
  if type(make_uuid) == "function" then -- luacheck: globals make_uuid
    return make_uuid()
  end
  return ""
end

local function nonempty(value, fallback)
  if value ~= nil and value ~= "" then
    return value
  end
  return fallback
end

-- make_normalized_webhook_envelope(internal_event[, fields]) constructs the
-- normalized delivery envelope shared by all backend-specific translators.
--
-- Envelope fields:
--   id          (string) — delivery/event identifier
--   type        (string) — dotted normalized event type
--   occurred_at (string) — ISO 8601 event time
--   actor       (table)  — normalized actor object
--   repository  (table)  — normalized repository object
--   payload     (table)  — event-family-specific normalized payload
function make_normalized_webhook_envelope(internal_event, fields) -- luacheck: globals make_normalized_webhook_envelope
  internal_event = internal_event or {}
  fields = fields or {}
  local data = internal_event.data or {}
  local raw = internal_event.raw or {}
  return {
    id = fields.id or fallback_id(),
    type = fields.type
      or normalized_webhook_event_type(internal_event.event, internal_event.action),
    occurred_at = nonempty(fields.occurred_at, nonempty(internal_event.timestamp, fallback_time())),
    actor = fields.actor or data.actor or data.sender or raw.sender or {},
    repository = fields.repository or data.repository or raw.repository or {},
    payload = fields.payload or data.payload or data,
  }
end
