-- Launchpad backend handler overrides.
-- Uses Launchpad REST API (Malone) at /devel/.
-- Bug tracker: /devel/~{owner}/{repo}?ws.op=searchTasks for issue lists.
-- Individual bugs: /devel/bugs/{id} (global bug numbers).
if config.base_url == "" then
  config.base_url = "https://api.launchpad.net"
end

local function fetch_json(url)
  return pcall(Fetch, url, nil)
end

local CLOSED_STATUSES = {
  ["Fix Released"] = true,
  ["Invalid"] = true,
  ["Won't Fix"] = true,
  ["Fix Committed"] = true,
}

local LAUNCHPAD_WEBHOOK_EVENT_TYPES = {
  "git:push:0.1",
  "merge-proposal:0.1",
  "ping",
  "bug:0.1",
  "bug:comment:0.1",
  "ci:build:0.1",
  "livefs:build:0.1",
  "snap:build:0.1",
  "ocirecipe:build:0.1",
  "archive:source-package-upload:0.1",
  "archive:binary-package-upload:0.1",
  "archive:binary-build:0.1",
}

local LAUNCHPAD_NATIVE_TO_GITHUB_EVENT = {
  ["git:push:0.1"] = "push",
  ["merge-proposal:0.1"] = "pull_request",
  ping = "ping",
  ["bug:0.1"] = "issues",
  ["bug:comment:0.1"] = "issue_comment",
  ["ci:build:0.1"] = "workflow_run",
  ["livefs:build:0.1"] = "workflow_run",
  ["snap:build:0.1"] = "workflow_run",
  ["ocirecipe:build:0.1"] = "workflow_run",
  ["archive:source-package-upload:0.1"] = "package",
  ["archive:binary-package-upload:0.1"] = "package",
  ["archive:binary-build:0.1"] = "workflow_run",
}

local LAUNCHPAD_ACTIONLESS_NORMALIZED_EVENTS = {
  ping = true,
  push = true,
}

local LAUNCHPAD_NORMALIZED_WEBHOOK_EVENTS = {
  "push",
  "ping",
  "issues",
  "issue_comment",
  "pull_request",
  "workflow_run",
  "package",
}

local ZERO_SHA = string.rep("0", 40)

local LAUNCHPAD_BUG_ACTIONS = {
  created = "opened",
}

local LAUNCHPAD_BUG_COMMENT_ACTIONS = {
  created = "created",
}

local LAUNCHPAD_CLOSED_MERGE_PROPOSAL_STATUSES = {
  Merged = true,
  Rejected = true,
  Superseded = true,
}

local LAUNCHPAD_COMPLETED_BUILD_STATUSES = {
  ["Build for superseded Source"] = "skipped",
  ["Cancelled build"] = "cancelled",
  Cancelled = "cancelled",
  ["Failed to build"] = "failure",
  ["Failed to upload"] = "failure",
  ["Fully built"] = "success",
  ["Successfully built"] = "success",
  Superseded = "skipped",
}

local LAUNCHPAD_IN_PROGRESS_BUILD_STATUSES = {
  ["Cancelling build"] = true,
  ["Currently building"] = true,
  ["Uploading build"] = true,
}

-- Extract Launchpad username from an owner/assignee link like ".../~username".
local function lp_login(link)
  return (link or ""):match("/~([^/]+)$") or ""
end

local translate_lp_user = make_translator({
  login = computed(function(u)
    return lp_login(u.owner_link)
  end),
  id = const(0),
  node_id = const(""),
  avatar_url = const(""),
  url = const(""),
  type = const("User"),
})

local function lp_webhook_owner_login(path)
  return (path or ""):match("^~([^/]+)/") or ""
end

local function lp_webhook_repo_name(path)
  return (path or ""):match("/%+git/(.+)$") or (path or ""):match("/([^/]+)$") or ""
end

local function lp_webhook_target_name(path)
  return (path or ""):match("/%+source/([^/]+)$") or (path or ""):match("/([^/]+)$") or ""
end

local function lp_webhook_user(login)
  login = login or ""
  return {
    login = login,
    id = 0,
    node_id = "",
    avatar_url = "",
    url = "",
    html_url = login ~= "" and ("https://launchpad.net/~" .. login) or "",
    type = "User",
  }
end

local function lp_webhook_user_from_path(path)
  return lp_webhook_user(lp_login(path))
end

local function lp_webhook_repository(payload)
  payload = payload or {}
  local path = payload.git_repository_path or ""
  local owner = lp_webhook_owner_login(path)
  local name = lp_webhook_repo_name(path)
  local full_name = owner ~= "" and name ~= "" and (owner .. "/" .. name) or name
  local html_url = path ~= "" and ("https://code.launchpad.net/" .. path) or ""
  return {
    id = 0,
    node_id = "",
    name = name,
    full_name = full_name,
    private = false,
    owner = lp_webhook_user(owner),
    html_url = html_url,
    url = payload.git_repository or "",
    git_url = path ~= "" and ("git://git.launchpad.net/" .. path) or "",
    ssh_url = path ~= "" and ("git+ssh://git.launchpad.net/" .. path) or "",
    clone_url = path ~= "" and ("https://git.launchpad.net/" .. path) or "",
    default_branch = "",
  }
end

local function lp_webhook_target_repository(payload)
  payload = payload or {}
  local path = payload.target or ""
  local name = lp_webhook_target_name(path)
  local owner = lp_webhook_owner_login(path)
  if owner == "" then
    owner = "launchpad"
  end
  local full_name = owner ~= "" and name ~= "" and (owner .. "/" .. name) or name
  local html_url = path ~= "" and ("https://launchpad.net" .. path) or ""
  return {
    id = 0,
    node_id = "",
    name = name,
    full_name = full_name,
    private = false,
    owner = lp_webhook_user(owner),
    html_url = html_url,
    url = path,
    git_url = "",
    ssh_url = "",
    clone_url = "",
    default_branch = "",
  }
end

local function lp_webhook_ref_sha(ref_desc)
  if type(ref_desc) ~= "table" then
    return nil
  end
  return ref_desc.commit_sha1 or ref_desc.sha or ref_desc.id
end

local function lp_webhook_primary_ref_change(ref_changes)
  if type(ref_changes) ~= "table" then
    return "", {}
  end
  local refs = {}
  for ref, _ in pairs(ref_changes) do
    refs[#refs + 1] = ref
  end
  table.sort(refs)
  local ref = refs[1] or ""
  return ref, ref_changes[ref] or {}
end

local function lp_webhook_sender(payload)
  payload = payload or {}
  local login = lp_login(payload.person)
  if login == "" then
    login = lp_login(payload.person_link)
  end
  if login == "" then
    login = lp_login(payload.owner_link)
  end
  if login == "" then
    login = lp_webhook_owner_login(payload.git_repository_path)
  end
  if login == "" then
    local attrs = payload.new or payload.old or {}
    login = lp_login(attrs.registrant)
  end
  return lp_webhook_user(login)
end

local function lp_webhook_bug_id(path)
  return tonumber((path or ""):match("/bugs/(%d+)")) or 0
end

local function lp_webhook_bug(payload)
  payload = payload or {}
  local bug_path = payload.bug or ""
  local bug_id = lp_webhook_bug_id(bug_path)
  local title = payload.title or (bug_id ~= 0 and ("Bug #" .. bug_id) or "")
  return {
    id = bug_id,
    node_id = "",
    number = bug_id,
    title = title,
    body = "",
    state = "open",
    user = lp_webhook_user_from_path(payload.owner or payload.owner_link),
    assignees = {},
    labels = {},
    milestone = nil,
    created_at = "",
    updated_at = "",
    closed_at = nil,
    html_url = bug_path ~= "" and ("https://bugs.launchpad.net" .. bug_path) or "",
  }
end

local function lp_webhook_bug_comment(payload)
  payload = payload or {}
  local comment_path = payload.bug_comment or ""
  local new = payload.new or {}
  local commenter = new.commenter or payload.commenter or ""
  return {
    id = tonumber((comment_path or ""):match("/comments/(%d+)$")) or 0,
    node_id = "",
    url = comment_path,
    body = new.content or payload.content or "",
    user = lp_webhook_user_from_path(commenter),
    created_at = "",
    updated_at = "",
    html_url = comment_path ~= "" and ("https://bugs.launchpad.net" .. comment_path) or "",
  }
end

local function lp_webhook_bug_action(raw_action)
  if LAUNCHPAD_BUG_ACTIONS[raw_action] then
    return LAUNCHPAD_BUG_ACTIONS[raw_action]
  end
  if (raw_action or ""):match("%-changed$") then
    return "edited"
  end
  return nil
end

local function lp_webhook_bug_comment_action(raw_action)
  if LAUNCHPAD_BUG_COMMENT_ACTIONS[raw_action] then
    return LAUNCHPAD_BUG_COMMENT_ACTIONS[raw_action]
  end
  if (raw_action or ""):match("%-changed$") then
    return "edited"
  end
  return nil
end

local function lp_webhook_merge_proposal_id(path)
  return tonumber((path or ""):match("/%+merge/(%d+)")) or 0
end

local function lp_webhook_merge_proposal_attrs(payload)
  payload = payload or {}
  return payload.new or payload.old or {}
end

local function lp_webhook_merge_proposal_branch(path, api_path)
  local repo = lp_webhook_repository({
    git_repository = api_path or "",
    git_repository_path = path or "",
  })
  return {
    label = repo.full_name or "",
    ref = repo.name or path or "",
    sha = "",
    repo = repo,
  }
end

local function lp_webhook_merge_proposal(payload)
  payload = payload or {}
  local attrs = lp_webhook_merge_proposal_attrs(payload)
  local mp_path = payload.merge_proposal or ""
  local number = lp_webhook_merge_proposal_id(mp_path)
  local queue_status = attrs.queue_status or attrs.status or ""
  local state = LAUNCHPAD_CLOSED_MERGE_PROPOSAL_STATUSES[queue_status] and "closed" or "open"
  return {
    id = number,
    node_id = "",
    number = number,
    state = state,
    locked = false,
    title = attrs.commit_message or ("Merge proposal #" .. number),
    body = attrs.description or "",
    user = lp_webhook_user_from_path(attrs.registrant),
    head = lp_webhook_merge_proposal_branch(
      attrs.source_git_path or attrs.source_branch,
      attrs.source_git_repository
    ),
    base = lp_webhook_merge_proposal_branch(
      attrs.target_git_path or attrs.target_branch,
      attrs.target_git_repository
    ),
    draft = queue_status == "Work in progress",
    created_at = "",
    updated_at = "",
    closed_at = state == "closed" and "" or nil,
    merged_at = queue_status == "Merged" and "" or nil,
    merge_commit_sha = "",
    merged_by = nil,
    diff_url = "",
    patch_url = "",
    html_url = mp_path ~= "" and ("https://code.launchpad.net" .. mp_path) or "",
    url = mp_path,
    mergeable = nil,
    comments = nil,
    review_comments = nil,
    additions = nil,
    deletions = nil,
    changed_files = nil,
    labels = {},
    assignees = {},
    requested_reviewers = {},
  }
end

local function lp_webhook_merge_proposal_action(payload)
  payload = payload or {}
  local raw_action = payload.action or ""
  if raw_action == "created" then
    return "opened"
  end
  if raw_action == "deleted" then
    return "closed"
  end
  if raw_action ~= "modified" then
    return nil
  end
  local old = payload.old or {}
  local new = payload.new or {}
  local old_status = old.queue_status or old.status or ""
  local new_status = new.queue_status or new.status or ""
  if
    LAUNCHPAD_CLOSED_MERGE_PROPOSAL_STATUSES[new_status]
    and not LAUNCHPAD_CLOSED_MERGE_PROPOSAL_STATUSES[old_status]
  then
    return "closed"
  end
  if
    LAUNCHPAD_CLOSED_MERGE_PROPOSAL_STATUSES[old_status]
    and not LAUNCHPAD_CLOSED_MERGE_PROPOSAL_STATUSES[new_status]
  then
    return "reopened"
  end
  if
    (old.source_git_commit_sha and old.source_git_commit_sha ~= new.source_git_commit_sha)
    or (old.source_revision_id and old.source_revision_id ~= new.source_revision_id)
  then
    return "synchronize"
  end
  return "edited"
end

local function lp_webhook_build_id(path)
  return tonumber((path or ""):match("/%+build/(%d+)"))
    or tonumber((path or ""):match("/build/(%d+)"))
    or tonumber((path or ""):match("/(%d+)$"))
end

local function lp_webhook_build_subject_path(payload)
  payload = payload or {}
  return payload.git_repository
    or payload.livefs
    or payload.snap
    or payload.ocirecipe
    or payload.archive
    or payload.build
    or ""
end

local function lp_webhook_build_path(payload)
  payload = payload or {}
  return payload.build
    or payload.livefs_build
    or payload.snap_build
    or payload.ocirecipe_build
    or ""
end

local function lp_webhook_workflow_name(payload)
  payload = payload or {}
  if payload.git_repository then
    return "Launchpad CI build"
  end
  if payload.livefs then
    return "Launchpad live filesystem build"
  end
  if payload.snap then
    return "Launchpad snap build"
  end
  if payload.ocirecipe then
    return "Launchpad OCI recipe build"
  end
  if payload.archive then
    return "Launchpad binary build"
  end
  return "Launchpad build"
end

local function lp_webhook_workflow_run_status(status)
  local conclusion = LAUNCHPAD_COMPLETED_BUILD_STATUSES[status or ""]
  if conclusion then
    return "completed", conclusion
  end
  if LAUNCHPAD_IN_PROGRESS_BUILD_STATUSES[status or ""] then
    return "in_progress", nil
  end
  return "queued", nil
end

local function lp_webhook_workflow_action(payload)
  payload = payload or {}
  if payload.action == "created" then
    return "requested"
  end
  local status, _ = lp_webhook_workflow_run_status(payload.status)
  if status == "completed" then
    return "completed"
  end
  if status == "in_progress" then
    return "in_progress"
  end
  return "requested"
end

local function lp_webhook_build_repository(payload)
  payload = payload or {}
  if payload.git_repository then
    return lp_webhook_repository({
      git_repository = payload.git_repository,
      git_repository_path = payload.git_repository_path or payload.git_repository,
    })
  end
  return lp_webhook_target_repository({ target = lp_webhook_build_subject_path(payload) })
end

local function lp_webhook_workflow_run(payload)
  payload = payload or {}
  local build_path = lp_webhook_build_path(payload)
  local status, conclusion = lp_webhook_workflow_run_status(payload.status)
  local workflow_name = lp_webhook_workflow_name(payload)
  local id = lp_webhook_build_id(build_path)
  return {
    id = id,
    name = workflow_name,
    head_branch = "",
    head_sha = payload.commit_sha1 or "",
    run_number = id,
    event = "launchpad",
    display_title = workflow_name,
    status = status,
    conclusion = conclusion,
    workflow_id = nil,
    url = build_path,
    html_url = build_path ~= "" and ("https://launchpad.net" .. build_path) or "",
    pull_requests = {},
    created_at = "",
    updated_at = "",
    run_attempt = 1,
    referenced_workflows = {},
    actor = lp_webhook_sender(payload),
    triggering_actor = lp_webhook_sender(payload),
  }
end

local function lp_webhook_workflow(payload)
  payload = payload or {}
  local name = lp_webhook_workflow_name(payload)
  local subject_path = lp_webhook_build_subject_path(payload)
  return {
    id = nil,
    name = name,
    path = subject_path,
    state = "active",
    url = subject_path,
    html_url = subject_path ~= "" and ("https://launchpad.net" .. subject_path) or "",
    badge_url = "",
    created_at = "",
    updated_at = "",
  }
end

local function lp_webhook_package_name(payload)
  payload = payload or {}
  return payload.package_name or payload.source_package_name or ""
end

local function lp_webhook_package_action(payload)
  payload = payload or {}
  if payload.status == "Accepted" then
    return "published"
  end
  if payload.action == "status-changed" then
    return "updated"
  end
  return nil
end

local function lp_webhook_package(payload, package_type)
  payload = payload or {}
  local name = lp_webhook_package_name(payload)
  local archive = payload.archive or ""
  local upload_path = payload.package_upload or ""
  return {
    id = lp_webhook_build_id(upload_path),
    name = name,
    namespace = archive,
    ecosystem = "deb",
    package_type = package_type,
    html_url = upload_path ~= "" and ("https://launchpad.net" .. upload_path) or "",
    created_at = "",
    updated_at = "",
    owner = lp_webhook_user("launchpad"),
    description = nil,
    package_version = {
      id = nil,
      name = payload.package_version or "",
      html_url = "",
      created_at = "",
      metadata = {
        status = payload.status or "",
        archive = archive,
      },
      package_files = {},
      installation_command = "",
    },
    registry = nil,
  }
end

local function launchpad_normalized_payload_without_envelope_fields(data)
  data = data or {}
  local payload = {}
  for k, v in pairs(data) do
    if k ~= "repository" and k ~= "sender" and k ~= "actor" then
      payload[k] = v
    end
  end
  return payload
end

local function translate_launchpad_normalized_webhook(internal_event, fields)
  local data = internal_event.data or {}
  fields = fields or {}
  return make_normalized_webhook_envelope(internal_event, {
    id = fields.id,
    type = fields.type
      or (
        LAUNCHPAD_ACTIONLESS_NORMALIZED_EVENTS[internal_event.event]
          and normalized_webhook_event_type(internal_event.event, "")
        or normalized_webhook_event_type(internal_event.event, internal_event.action)
      ),
    occurred_at = fields.occurred_at,
    actor = fields.actor or data.sender,
    repository = fields.repository or data.repository,
    payload = fields.payload or launchpad_normalized_payload_without_envelope_fields(data),
  })
end

local function translate_launchpad_github_webhook(internal_event, fields)
  return github_webhook_payload(internal_event, fields)
end

local function lp_webhook_unimplemented(event_type)
  local github_event = LAUNCHPAD_NATIVE_TO_GITHUB_EVENT[event_type] or event_type
  return function(_payload)
    return nil, "Launchpad webhook event not implemented: " .. github_event
  end
end

local function lp_task_bug_id(t)
  return tonumber((t.bug_link or ""):match("/bugs/(%d+)$")) or 0
end

local function lp_task_state(t)
  return CLOSED_STATUSES[t.status or ""] and "closed" or "open"
end

local function lp_bug_state(_bug, task)
  if task then
    return CLOSED_STATUSES[task.status or ""] and "closed" or "open"
  end
  return "open"
end

local function lp_task_updated_at(t)
  return t.date_last_updated or t.date_created or ""
end

local function lp_bug_updated_at(bug)
  return bug.date_last_updated or bug.date_created or ""
end

-- Translate a Launchpad bug task (IBugTask) to GitHub issue format.
-- Bug tasks come from searchTasks; they have status but not description.
local translate_lp_task = make_translator({
  id = computed(lp_task_bug_id),
  node_id = const(""),
  number = computed(lp_task_bug_id),
  title = field("title", { default = "" }),
  body = const(""),
  state = computed(lp_task_state),
  user = computed(function(t)
    return translate_lp_user(t)
  end),
  assignees = computed(function()
    return {}
  end),
  labels = computed(function()
    return {}
  end),
  milestone = const(nil),
  created_at = field("date_created", { default = "" }),
  updated_at = computed(lp_task_updated_at),
  closed_at = "date_closed",
  html_url = const(""),
})

-- Translate a Launchpad IBug + optional IBugTask to GitHub issue format.
-- Bug has title/description/reporter; task has per-project status.
local translate_lp_bug = make_translator({
  id = field("id", { default = 0 }),
  node_id = const(""),
  number = field("id", { default = 0 }),
  title = field("title", { default = "" }),
  body = field("description", { default = "" }),
  state = computed(lp_bug_state),
  user = computed(function(bug)
    return translate_lp_user(bug)
  end),
  assignees = computed(function()
    return {}
  end),
  labels = computed(function()
    return {}
  end),
  milestone = const(nil),
  created_at = field("date_created", { default = "" }),
  updated_at = computed(lp_bug_updated_at),
  closed_at = const(nil),
  html_url = const(""),
})

local b = make_backend_builder()
b:rest("get_root", function()
  proxy_health_check(pcall(Fetch, config.base_url .. "/devel/"))
end)

-- Inbound webhook event headers ------------------------------------------------
-- Launchpad sends the native event type in X-Launchpad-Event-Type.  Register the
-- native keys up front so unsupported events fail as known-but-unimplemented
-- until the event-family translators replace these handlers.

for _, event_type in ipairs(LAUNCHPAD_WEBHOOK_EVENT_TYPES) do
  b:webhook(event_type, lp_webhook_unimplemented(event_type))
end

for _, event_type in ipairs(LAUNCHPAD_NORMALIZED_WEBHOOK_EVENTS) do
  b:webhook_translator(event_type, translate_launchpad_normalized_webhook)
  b:webhook_github_translator(event_type, translate_launchpad_github_webhook)
end

b:webhook("git:push:0.1", function(payload)
  payload = payload or {}
  local ref, change = lp_webhook_primary_ref_change(payload.ref_changes)
  local before = lp_webhook_ref_sha(change.old) or ZERO_SHA
  local after = lp_webhook_ref_sha(change.new) or ZERO_SHA
  local repository = lp_webhook_repository(payload)
  local sender = lp_webhook_sender(payload)
  return make_internal_event({
    event = "push",
    action = "push",
    provider = "launchpad",
    raw = payload,
    data = {
      ref = ref,
      before = before,
      after = after,
      created = change.old == nil and change.new ~= nil,
      deleted = change.old ~= nil and change.new == nil,
      forced = false,
      compare = "",
      commits = {},
      head_commit = nil,
      pusher = {
        name = sender.login,
        email = "",
      },
      repository = repository,
      sender = sender,
      ref_changes = payload.ref_changes or {},
    },
    timestamp = "",
  })
end)

b:webhook("ping", function(payload)
  payload = payload or {}
  return make_internal_event({
    event = "ping",
    action = "ping",
    provider = "launchpad",
    raw = payload,
    data = {
      zen = payload.zen or "Launchpad",
      hook_id = payload.hook_id,
      hook = payload.hook or {},
      repository = lp_webhook_repository(payload),
      sender = lp_webhook_sender(payload),
    },
    timestamp = "",
  })
end)

b:webhook("bug:0.1", function(payload)
  payload = payload or {}
  local raw_action = payload.action or ""
  local action = lp_webhook_bug_action(raw_action)
  return make_internal_event({
    event = "issues",
    action = action or "unknown",
    raw_action = action and nil or raw_action,
    provider = "launchpad",
    raw = payload,
    data = {
      action = action or "unknown",
      issue = lp_webhook_bug(payload),
      repository = lp_webhook_target_repository(payload),
      sender = lp_webhook_sender(payload),
      target = payload.target or "",
    },
    timestamp = "",
  })
end)

b:webhook("bug:comment:0.1", function(payload)
  payload = payload or {}
  local raw_action = payload.action or ""
  local action = lp_webhook_bug_comment_action(raw_action)
  return make_internal_event({
    event = "issue_comment",
    action = action or "unknown",
    raw_action = action and nil or raw_action,
    provider = "launchpad",
    raw = payload,
    data = {
      action = action or "unknown",
      issue = lp_webhook_bug(payload),
      comment = lp_webhook_bug_comment(payload),
      repository = lp_webhook_target_repository(payload),
      sender = lp_webhook_sender(payload),
      target = payload.target or "",
    },
    timestamp = "",
  })
end)

b:webhook("merge-proposal:0.1", function(payload)
  payload = payload or {}
  local raw_action = payload.action or ""
  local action = lp_webhook_merge_proposal_action(payload)
  local pull_request = lp_webhook_merge_proposal(payload)
  return make_internal_event({
    event = "pull_request",
    action = action or "unknown",
    raw_action = action and nil or raw_action,
    provider = "launchpad",
    raw = payload,
    data = {
      action = action or "unknown",
      number = pull_request.number,
      pull_request = pull_request,
      repository = pull_request.base.repo or {},
      sender = lp_webhook_sender(payload),
    },
    timestamp = "",
  })
end)

local function lp_webhook_workflow_run_handler(payload)
  payload = payload or {}
  local raw_action = payload.action or ""
  local action = lp_webhook_workflow_action(payload)
  return make_internal_event({
    event = "workflow_run",
    action = action or "unknown",
    raw_action = action and nil or raw_action,
    provider = "launchpad",
    raw = payload,
    data = {
      action = action or "unknown",
      workflow_run = lp_webhook_workflow_run(payload),
      workflow = lp_webhook_workflow(payload),
      repository = lp_webhook_build_repository(payload),
      sender = lp_webhook_sender(payload),
    },
    timestamp = "",
  })
end

b:webhook("ci:build:0.1", lp_webhook_workflow_run_handler)
b:webhook("livefs:build:0.1", lp_webhook_workflow_run_handler)
b:webhook("snap:build:0.1", lp_webhook_workflow_run_handler)
b:webhook("ocirecipe:build:0.1", lp_webhook_workflow_run_handler)
b:webhook("archive:binary-build:0.1", lp_webhook_workflow_run_handler)

local function lp_webhook_package_handler(package_type)
  return function(payload)
    payload = payload or {}
    local raw_action = payload.action or ""
    local action = lp_webhook_package_action(payload)
    local pkg = lp_webhook_package(payload, package_type)
    return make_internal_event({
      event = "package",
      action = action or "unknown",
      raw_action = action and nil or raw_action,
      provider = "launchpad",
      raw = payload,
      data = {
        action = action or "unknown",
        package = pkg,
        repository = lp_webhook_target_repository({ target = payload.archive or "" }),
        sender = lp_webhook_sender(payload),
      },
      timestamp = "",
    })
  end
end

b:webhook("archive:source-package-upload:0.1", lp_webhook_package_handler("deb-source"))
b:webhook("archive:binary-package-upload:0.1", lp_webhook_package_handler("deb-binary"))

-- Issues --------------------------------------------------------------------
-- Launchpad: GET /devel/~{owner}/{repo}?ws.op=searchTasks

b:rest("get_repo_issues", function(owner, repo_name)
  local state = GetParam("state") or "open"
  local count = tonumber(GetParam("per_page")) or 30
  local page = tonumber(GetParam("page")) or 1
  local url = config.base_url
    .. "/devel/~"
    .. owner
    .. "/"
    .. repo_name
    .. "?ws.op=searchTasks"
    .. "&start="
    .. ((page - 1) * count)
    .. "&limit="
    .. count
  if state == "closed" then
    url = url .. "&status=Fix+Released&status=Invalid&status=Won%27t+Fix&status=Fix+Committed"
  elseif state ~= "all" then
    url = url .. "&status=New&status=Incomplete&status=Confirmed&status=Triaged&status=In+Progress"
  end
  proxy_json(function(data)
    return translate_list(translate_lp_task, data.entries)
  end, fetch_json(url))
end)

-- GET /repos/{owner}/{repo}/issues/{issue_number}
-- Fetch the bug object (title/description) and its project task (status).
b:rest("get_repo_issue", function(owner, repo_name, issue_number)
  local ok, status, _, body = fetch_json(config.base_url .. "/devel/bugs/" .. issue_number)
  if not ok then
    respond_json(503, {})
    return
  end
  if status == 404 then
    respond_json(404, { message = "Not Found" })
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local bug = DecodeJson(body)
  local task_url = config.base_url
    .. "/devel/~"
    .. owner
    .. "/"
    .. repo_name
    .. "/+bug/"
    .. issue_number
  local ok2, status2, _, body2 = fetch_json(task_url)
  local task = (ok2 and status2 == 200) and DecodeJson(body2) or nil
  respond_json(200, translate_lp_bug(bug, task))
end)

-- GET /repos/{owner}/{repo}/issues/{issue_number}/comments
-- Launchpad: GET /devel/bugs/{id}/messages
-- The first message (index 0) is the bug description, so skip it.
b:rest("get_issue_comments", function(_owner, _repo_name, issue_number)
  local count = tonumber(GetParam("per_page")) or 30
  local page = tonumber(GetParam("page")) or 1
  -- Offset by 1 to skip the description message (always first in the collection).
  local start = (page - 1) * count + 1
  local url = config.base_url
    .. "/devel/bugs/"
    .. issue_number
    .. "/messages?start="
    .. start
    .. "&limit="
    .. count
  proxy_json(function(data)
    local entries = data.entries or {}
    local result = {}
    for _, m in ipairs(entries) do
      result[#result + 1] = {
        id = m.index or 0,
        node_id = "",
        url = "",
        body = m.content or "",
        user = {
          login = lp_login(m.owner_link),
          id = 0,
          node_id = "",
          avatar_url = "",
          url = "",
          type = "User",
        },
        created_at = m.date_created or "",
        updated_at = m.date_created or "",
        html_url = "",
      }
    end
    return result
  end, fetch_json(url))
end)

b:build()
