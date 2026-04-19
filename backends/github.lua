-- GitHub backend: webhook-receive-only.
--
-- GitHub's webhook payloads are already in GitHub format, so normalizers are
-- pass-through: actions are used verbatim and data fields are forwarded as-is.
-- REST and GraphQL endpoints fall through to catalog defaults (stubs).

local b = make_backend_builder()

-- Action maps: GitHub action string → canonical GitHub action string (identity).
-- Any action not in the map is treated as "unknown" and surfaced via
-- X-Confusio-Raw-Action so operators can observe new variants without
-- breaking delivery.
local GH_ISSUES_ACTIONS = {
  assigned = "assigned",
  closed = "closed",
  deleted = "deleted",
  demilestoned = "demilestoned",
  edited = "edited",
  labeled = "labeled",
  locked = "locked",
  milestoned = "milestoned",
  opened = "opened",
  pinned = "pinned",
  reopened = "reopened",
  transferred = "transferred",
  unassigned = "unassigned",
  unlabeled = "unlabeled",
  unlocked = "unlocked",
  unpinned = "unpinned",
}
local GH_ISSUE_COMMENT_ACTIONS = {
  created = "created",
  deleted = "deleted",
  edited = "edited",
}
local GH_LABEL_ACTIONS = {
  created = "created",
  deleted = "deleted",
  edited = "edited",
}
local GH_MILESTONE_ACTIONS = {
  closed = "closed",
  created = "created",
  deleted = "deleted",
  edited = "edited",
  opened = "opened",
}
local GH_SUB_ISSUES_ACTIONS = {
  parent_issue_added = "parent_issue_added",
  parent_issue_removed = "parent_issue_removed",
  sub_issue_added = "sub_issue_added",
  sub_issue_removed = "sub_issue_removed",
}

b:webhook("issues", function(payload)
  local raw_action = payload.action or ""
  local action = GH_ISSUES_ACTIONS[raw_action]
  local data = {
    action = action or "unknown",
    issue = payload.issue or {},
    repository = payload.repository or {},
    sender = payload.sender or {},
  }
  if action == "labeled" or action == "unlabeled" then
    data.label = payload.label
  end
  if action == "assigned" or action == "unassigned" then
    data.assignee = payload.assignee
  end
  return make_internal_event({
    event = "issues",
    action = action or "unknown",
    raw_action = action and nil or raw_action,
    provider = "github",
    raw = payload,
    data = data,
    timestamp = (payload.issue or {}).updated_at or "",
  })
end)

b:webhook("issue_comment", function(payload)
  local raw_action = payload.action or ""
  local action = GH_ISSUE_COMMENT_ACTIONS[raw_action]
  return make_internal_event({
    event = "issue_comment",
    action = action or "unknown",
    raw_action = action and nil or raw_action,
    provider = "github",
    raw = payload,
    data = {
      action = action or "unknown",
      issue = payload.issue or {},
      comment = payload.comment or {},
      repository = payload.repository or {},
      sender = payload.sender or {},
    },
    timestamp = (payload.comment or {}).updated_at or "",
  })
end)

b:webhook("label", function(payload)
  local raw_action = payload.action or ""
  local action = GH_LABEL_ACTIONS[raw_action]
  return make_internal_event({
    event = "label",
    action = action or "unknown",
    raw_action = action and nil or raw_action,
    provider = "github",
    raw = payload,
    data = {
      action = action or "unknown",
      label = payload.label or {},
      changes = payload.changes or {},
      repository = payload.repository or {},
      sender = payload.sender or {},
    },
    timestamp = "",
  })
end)

b:webhook("milestone", function(payload)
  local raw_action = payload.action or ""
  local action = GH_MILESTONE_ACTIONS[raw_action]
  return make_internal_event({
    event = "milestone",
    action = action or "unknown",
    raw_action = action and nil or raw_action,
    provider = "github",
    raw = payload,
    data = {
      action = action or "unknown",
      milestone = payload.milestone or {},
      repository = payload.repository or {},
      sender = payload.sender or {},
    },
    timestamp = (payload.milestone or {}).updated_at or "",
  })
end)

b:webhook("sub_issues", function(payload)
  local raw_action = payload.action or ""
  local action = GH_SUB_ISSUES_ACTIONS[raw_action]
  return make_internal_event({
    event = "sub_issues",
    action = action or "unknown",
    raw_action = action and nil or raw_action,
    provider = "github",
    raw = payload,
    data = {
      action = action or "unknown",
      issue = payload.issue or {},
      parent_issue = payload.parent_issue or {},
      sub_issue = payload.sub_issue or {},
      repository = payload.repository or {},
      sender = payload.sender or {},
    },
    timestamp = (payload.issue or {}).updated_at or "",
  })
end)

b:build()
