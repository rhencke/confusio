-- Sourcehut backend handler overrides.
-- Uses git.sr.ht REST API at /api/~{username}/repos/{name}.
-- Issues use todo.sr.ht REST API at /api/~{username}/trackers/{name}/tickets.
-- Checks use builds.sr.ht REST API at /api/jobs (filtered by tag).
if config.base_url == "" then
  config.base_url = "https://git.sr.ht"
end

local base = function()
  return config.base_url .. "/api"
end

-- Derive the todo.sr.ht base URL from the git.sr.ht base URL.
-- In production: https://git.sr.ht → https://todo.sr.ht
-- In tests (IP:PORT): unchanged, same mock server handles both API path prefixes.
local todo_base = function()
  return config.base_url:gsub("git%.sr%.ht", "todo.sr.ht") .. "/api"
end

-- Derive the builds.sr.ht base URL from the git.sr.ht base URL.
-- In production: https://git.sr.ht → https://builds.sr.ht
-- In tests (IP:PORT): unchanged, same mock server handles both API path prefixes.
local builds_base = function()
  return config.base_url:gsub("git%.sr%.ht", "builds.sr.ht") .. "/api"
end
local auth = function()
  return make_fetch_opts("token")
end
local PAGES = { per_page = "limit" }
local _t = make_backend_transport("token", PAGES)
local fetch_json = _t.fetch_json
local proxy_handler = _t.proxy_handler

local ZERO_SHA = "0000000000000000000000000000000000000000"

local function strip_tilde(value)
  value = value or ""
  return value:sub(1, 1) == "~" and value:sub(2) or value
end

local function sourcehut_canonical(entity)
  entity = entity or {}
  return entity.canonical_name or entity.canonicalName or entity.username or entity.name or ""
end

local function sourcehut_login(entity)
  local canonical = sourcehut_canonical(entity)
  if canonical ~= "" then
    return strip_tilde(canonical)
  end
  return (entity or {}).login or ""
end

local function ref_name(ref)
  return (ref or ""):match("^refs/heads/(.+)$")
    or (ref or ""):match("^refs/tags/(.+)$")
    or (ref or "")
end

local function ref_type(ref)
  if (ref or ""):match("^refs/tags/") then
    return "tag"
  end
  return "branch"
end

-- Map a Sourcehut repository object to GitHub format.
local function translate_srht_repo(r)
  if not r then
    return {}
  end
  local owner = r.owner or {}
  local canonical = sourcehut_canonical(owner)
  local login = sourcehut_login(owner)
  local vis = r.visibility or "public"
  local private = vis == "private" or vis == "PRIVATE"
  local head = r.HEAD or r.head or {}
  local default_branch
  if type(head) == "table" then
    default_branch = (head.name or ""):match("^refs/heads/(.+)") or head.name or ""
  else
    default_branch = tostring(head or ""):match("^refs/heads/(.+)") or tostring(head or "")
  end
  if default_branch == "" then
    default_branch = "main"
  end
  return {
    id = r.id or 0,
    node_id = r.rid or "",
    name = r.name,
    full_name = login .. "/" .. (r.name or ""),
    private = private,
    owner = {
      login = login,
      id = owner.id or 0,
      node_id = "",
      avatar_url = "",
      url = "",
      html_url = config.base_url .. "/" .. canonical,
      type = "User",
    },
    html_url = config.base_url .. "/" .. canonical .. "/" .. (r.name or ""),
    description = r.description,
    fork = false,
    url = "",
    clone_url = "",
    homepage = "",
    size = 0,
    stargazers_count = 0,
    watchers_count = 0,
    language = nil,
    has_issues = false,
    has_wiki = false,
    forks_count = 0,
    archived = false,
    disabled = false,
    open_issues_count = 0,
    default_branch = default_branch,
    visibility = private and "private" or "public",
    forks = 0,
    open_issues = 0,
    watchers = 0,
    created_at = r.created,
    updated_at = r.updated,
    pushed_at = r.updated,
  }
end

local function translate_srht_user(u)
  u = u or {}
  local canonical = sourcehut_canonical(u)
  local login = sourcehut_login(u)
  return {
    login = login,
    id = u.id or 0,
    node_id = "",
    avatar_url = "",
    url = u.url or "",
    html_url = canonical ~= "" and (config.base_url .. "/" .. canonical) or "",
    type = "User",
    site_admin = false,
    name = u.name or u.username or login,
    email = u.email or "",
  }
end

local function translate_srht_label(label)
  label = label or {}
  return {
    id = label.id or 0,
    node_id = label.rid or "",
    url = "",
    name = label.name or "",
    color = (label.backgroundColor or label.background_color or ""):gsub("^#", ""),
    description = label.description or "",
    default = false,
  }
end

local function translate_srht_labels(labels)
  local result = {}
  for _, label in ipairs(labels or {}) do
    result[#result + 1] = translate_srht_label(label)
  end
  return result
end

local function translate_srht_tracker_repo(tracker)
  tracker = tracker or {}
  local owner = tracker.owner or {}
  local canonical = sourcehut_canonical(owner)
  local login = sourcehut_login(owner)
  local vis = tracker.visibility or "PUBLIC"
  local private = vis == "private" or vis == "PRIVATE"
  return {
    id = tracker.id or 0,
    node_id = tracker.rid or "",
    name = tracker.name or "",
    full_name = login ~= "" and (login .. "/" .. (tracker.name or "")) or (tracker.name or ""),
    private = private,
    owner = translate_srht_user(owner),
    html_url = canonical ~= "" and (todo_base():gsub("/api$", "") .. "/" .. canonical) or "",
    description = tracker.description,
    fork = false,
    url = "",
    clone_url = "",
    homepage = "",
    size = 0,
    stargazers_count = 0,
    watchers_count = 0,
    language = nil,
    has_issues = true,
    has_wiki = false,
    forks_count = 0,
    archived = false,
    disabled = false,
    open_issues_count = 0,
    default_branch = "",
    visibility = private and "private" or "public",
    forks = 0,
    open_issues = 0,
    watchers = 0,
    created_at = tracker.created,
    updated_at = tracker.updated,
    pushed_at = tracker.updated,
  }
end

-- Translate GitHub create/update request body to Sourcehut format.
local function translate_srht_req(body_str)
  local req = DecodeJson(body_str or "{}")
  local sr = {}
  if req.name then
    sr.name = req.name
  end
  if req.description then
    sr.description = req.description
  end
  if req.private ~= nil then
    sr.visibility = req.private and "private" or "public"
  end
  return EncodeJson(sr)
end

-- Translate a Sourcehut ref to a GitHub branch object.
-- Only call for refs with names like "refs/heads/main".
local function translate_srht_branch(ref)
  if not ref then
    return {}
  end
  local name = ref.name and ref.name:match("^refs/heads/(.+)") or (ref.name or "")
  return {
    name = name,
    commit = { sha = ref.target or "", url = "" },
    protected = false,
  }
end

-- Translate a todo.sr.ht ticket to GitHub issue format.
-- Sourcehut: { id, created, updated, title, body, status, submitter: { canonical_name, name } }
local function translate_srht_ticket(t)
  if not t then
    return {}
  end
  local submitter = t.submitter or {}
  local status = t.status or "reported"
  local state = (
    status == "resolved"
    or status == "closed"
    or status == "RESOLVED"
    or status == "CLOSED"
  )
      and "closed"
    or "open"
  return {
    id = t.id or 0,
    node_id = t.rid or "",
    number = t.id or 0,
    title = t.subject or t.title or "",
    body = t.body or "",
    state = state,
    user = translate_srht_user(submitter),
    assignees = translate_list(translate_srht_user, t.assignees),
    labels = translate_srht_labels(t.labels),
    milestone = nil,
    created_at = t.created or "",
    updated_at = t.updated or t.created or "",
    closed_at = nil,
    html_url = "",
  }
end

-- Translate a todo.sr.ht event to GitHub issue comment format.
-- Events with no comment field (status changes, etc.) are skipped by the caller.
-- event: { id, created, event_type, comment: { id, created, text, author } }
local function translate_srht_event_comment(e)
  if not e or not e.comment then
    return nil
  end
  local comment = e.comment
  local author = comment.author or {}
  local canonical = author.canonical_name or ""
  local login = canonical:sub(1, 1) == "~" and canonical:sub(2) or (author.name or canonical)
  return {
    id = comment.id or e.id or 0,
    node_id = "",
    url = "",
    body = comment.text or "",
    user = { login = login, id = 0, node_id = "", avatar_url = "", url = "", type = "User" },
    created_at = comment.created or e.created or "",
    updated_at = comment.created or e.created or "",
    html_url = "",
  }
end

-- Translate a Sourcehut log entry to GitHub commit format.
-- Sourcehut: { id, message, timestamp, author: { name, email } }

-- Checks (via builds.sr.ht jobs) -----------------------------------------------
--
-- GitHub Check Runs map onto builds.sr.ht jobs.  Each job is tagged with the
-- git repository and commit SHA it was triggered by, so:
--   • GET commits/{ref}/check-runs → GET /api/jobs?filter[tags]=git.sr.ht/~owner/repo=sha
--   • All other check and check-suite endpoints fall back to defaults.
--   • Annotations are always empty.
--
-- Status mapping (builds.sr.ht → GitHub):
--   pending/queued/running → status=in_progress, conclusion=null
--   success                → status=completed,   conclusion=success
--   failed/timeout         → status=completed,   conclusion=failure
--   cancelled              → status=completed,   conclusion=cancelled

local function translate_srht_job_to_check_run(j)
  if not j then
    return {}
  end
  local srht_status = j.status or "pending"
  local srht_to_gh = {
    success = { status = "completed", conclusion = "success" },
    failed = { status = "completed", conclusion = "failure" },
    timeout = { status = "completed", conclusion = "failure" },
    cancelled = { status = "completed", conclusion = "cancelled" },
  }
  local mapped = srht_to_gh[srht_status] or { status = "in_progress", conclusion = nil }
  local gh_status, gh_conclusion = mapped.status, mapped.conclusion
  -- Job name: use note field or fall back to id
  local name = j.note or (tostring(j.id or 0))
  return {
    id = j.id or 0,
    node_id = "",
    head_sha = "",
    name = name,
    status = gh_status,
    conclusion = gh_conclusion,
    started_at = j.created,
    completed_at = gh_status == "completed" and (j.updated or j.created) or nil,
    output = {
      title = name,
      summary = name,
      text = "",
      annotations_count = 0,
      annotations_url = "",
    },
    url = "",
    html_url = "",
    details_url = "",
  }
end

local function translate_srht_commit(c)
  if not c then
    return {}
  end
  local author = c.author or {}
  local committer = c.committer or author
  local author_date = author.time or c.timestamp or ""
  local committer_date = committer.time or author_date
  return {
    sha = c.id or "",
    commit = {
      message = c.message or "",
      author = { name = author.name or "", email = author.email or "", date = author_date },
      committer = {
        name = committer.name or "",
        email = committer.email or "",
        date = committer_date,
      },
    },
    author = { login = author.name or "", id = 0, avatar_url = "" },
    committer = { login = committer.name or "", id = 0, avatar_url = "" },
  }
end

local function sourcehut_payload(payload)
  if type(payload) == "table" and type(payload.data) == "table" then
    return payload.data
  end
  return payload or {}
end

local function sourcehut_webhook(payload)
  payload = sourcehut_payload(payload)
  return payload.webhook or payload
end

local function sourcehut_event_name(payload)
  local webhook = sourcehut_webhook(payload)
  return webhook.event or webhook.event_type or webhook.eventType or ""
end

local function sourcehut_sender(payload)
  payload = sourcehut_payload(payload)
  return translate_srht_user(
    payload.pusher
      or payload.sender
      or payload.actor
      or payload.repository and payload.repository.owner
  )
end

local function sourcehut_repository(payload)
  payload = sourcehut_payload(payload)
  return translate_srht_repo(payload.repository or {})
end

local function sourcehut_ticket_payload(payload)
  payload = sourcehut_payload(payload)
  return payload.ticket or payload.newTicket or payload.ticketEvent and payload.ticketEvent.ticket
end

local function sourcehut_label_payload(payload)
  payload = sourcehut_payload(payload)
  return payload.label or payload.newLabel
end

local function sourcehut_event_payload(payload)
  payload = sourcehut_payload(payload)
  return payload.newEvent or payload.eventRecord or payload.ticketEvent or payload.event_detail
end

local function sourcehut_issue_repository(payload, ticket, label)
  payload = sourcehut_payload(payload)
  ticket = ticket or sourcehut_ticket_payload(payload) or {}
  label = label or sourcehut_label_payload(payload) or {}
  return translate_srht_tracker_repo(
    payload.tracker or ticket.tracker or label.tracker or (payload.repository or {}).tracker
  )
end

local function sourcehut_ticket_sender(ticket)
  ticket = ticket or {}
  return translate_srht_user(ticket.submitter or ticket.author)
end

local function sourcehut_ticket_event(payload, action)
  payload = payload or {}
  local ticket = sourcehut_ticket_payload(payload) or {}
  local sender = sourcehut_sender(payload)
  return make_internal_event({
    event = "issues",
    action = action,
    provider = "sourcehut",
    raw = payload,
    data = {
      action = action,
      issue = translate_srht_ticket(ticket),
      repository = sourcehut_issue_repository(payload, ticket),
      sender = sender.login ~= "" and sender or sourcehut_ticket_sender(ticket),
    },
    timestamp = (sourcehut_webhook(payload) or {}).date or ticket.updated or ticket.created or "",
  })
end

local function sourcehut_deleted_ticket_event(payload)
  payload = payload or {}
  local data = sourcehut_payload(payload)
  local ticket_id = data.ticketId or data.ticket_id or 0
  return make_internal_event({
    event = "issues",
    action = "deleted",
    provider = "sourcehut",
    raw = payload,
    data = {
      action = "deleted",
      issue = { id = ticket_id, number = ticket_id, state = "closed", labels = {} },
      repository = sourcehut_issue_repository(payload),
      sender = sourcehut_sender(payload),
    },
    timestamp = (sourcehut_webhook(payload) or {}).date or "",
  })
end

local function sourcehut_label_event(payload, action)
  payload = payload or {}
  local label = sourcehut_label_payload(payload) or {}
  local sender = sourcehut_sender(payload)
  return make_internal_event({
    event = "label",
    action = action,
    provider = "sourcehut",
    raw = payload,
    data = {
      action = action,
      label = translate_srht_label(label),
      changes = {},
      repository = sourcehut_issue_repository(payload, nil, label),
      sender = sender.login ~= "" and sender or translate_srht_user((label.tracker or {}).owner),
    },
    timestamp = (sourcehut_webhook(payload) or {}).date or label.updated or label.created or "",
  })
end

local function sourcehut_comment_from_event(event, change)
  event = event or {}
  change = change or {}
  return {
    id = change.id or event.id or 0,
    node_id = "",
    url = "",
    body = change.text or "",
    user = translate_srht_user(change.author),
    created_at = event.created or "",
    updated_at = event.created or "",
    html_url = "",
  }
end

local function sourcehut_ticket_activity_sender(change, ticket)
  change = change or {}
  return translate_srht_user(
    change.author or change.editor or change.labeler or change.user or ticket and ticket.submitter
  )
end

local function sourcehut_status_action(change)
  change = change or {}
  local new_status = change.newStatus or change.new_status or ""
  local old_status = change.oldStatus or change.old_status or ""
  if new_status == "RESOLVED" or new_status == "CLOSED" or new_status == "resolved" then
    return "closed"
  end
  if old_status == "RESOLVED" or old_status == "CLOSED" or old_status == "resolved" then
    return "reopened"
  end
  return "edited"
end

local function sourcehut_event_created(payload)
  payload = payload or {}
  local event = sourcehut_event_payload(payload) or {}
  local ticket = event.ticket or {}
  local change = (event.changes or {})[1] or {}
  local event_type = change.eventType or change.event_type or ""

  if event_type == "CREATED" then
    return make_internal_event({
      event = "issues",
      action = "opened",
      provider = "sourcehut",
      raw = payload,
      data = {
        action = "opened",
        issue = translate_srht_ticket(ticket),
        repository = sourcehut_issue_repository(payload, ticket),
        sender = sourcehut_ticket_activity_sender(change, ticket),
      },
      timestamp = (sourcehut_webhook(payload) or {}).date or event.created or "",
    })
  end

  if event_type == "COMMENT" then
    return make_internal_event({
      event = "issue_comment",
      action = "created",
      provider = "sourcehut",
      raw = payload,
      data = {
        action = "created",
        issue = translate_srht_ticket(ticket),
        comment = sourcehut_comment_from_event(event, change),
        repository = sourcehut_issue_repository(payload, ticket),
        sender = sourcehut_ticket_activity_sender(change, ticket),
      },
      timestamp = (sourcehut_webhook(payload) or {}).date or event.created or "",
    })
  end

  if event_type == "LABEL_ADDED" or event_type == "LABEL_REMOVED" then
    local action = event_type == "LABEL_ADDED" and "labeled" or "unlabeled"
    return make_internal_event({
      event = "issues",
      action = action,
      provider = "sourcehut",
      raw = payload,
      data = {
        action = action,
        issue = translate_srht_ticket(ticket),
        label = translate_srht_label(change.label),
        repository = sourcehut_issue_repository(payload, ticket, change.label),
        sender = sourcehut_ticket_activity_sender(change, ticket),
      },
      timestamp = (sourcehut_webhook(payload) or {}).date or event.created or "",
    })
  end

  if event_type == "STATUS_CHANGE" then
    local action = sourcehut_status_action(change)
    return make_internal_event({
      event = "issues",
      action = action,
      provider = "sourcehut",
      raw = payload,
      data = {
        action = action,
        issue = translate_srht_ticket(ticket),
        repository = sourcehut_issue_repository(payload, ticket),
        sender = sourcehut_ticket_activity_sender(change, ticket),
      },
      timestamp = (sourcehut_webhook(payload) or {}).date or event.created or "",
    })
  end

  if event_type == "ASSIGNED_USER" or event_type == "UNASSIGNED_USER" then
    local action = event_type == "ASSIGNED_USER" and "assigned" or "unassigned"
    return make_internal_event({
      event = "issues",
      action = action,
      provider = "sourcehut",
      raw = payload,
      data = {
        action = action,
        issue = translate_srht_ticket(ticket),
        assignee = translate_srht_user(change.user or change.assignee),
        repository = sourcehut_issue_repository(payload, ticket),
        sender = sourcehut_ticket_activity_sender(change, ticket),
      },
      timestamp = (sourcehut_webhook(payload) or {}).date or event.created or "",
    })
  end

  return make_internal_event({
    event = "issues",
    action = "edited",
    provider = "sourcehut",
    raw = payload,
    data = {
      action = "edited",
      issue = translate_srht_ticket(ticket),
      repository = sourcehut_issue_repository(payload, ticket),
      sender = sourcehut_ticket_activity_sender(change, ticket),
    },
    timestamp = (sourcehut_webhook(payload) or {}).date or event.created or "",
  })
end

local function sourcehut_update_ref(update)
  update = update or {}
  local ref = update.ref or update.reference or {}
  if type(ref) == "table" then
    return ref.name or update.name or update.refName or ""
  end
  return ref or update.name or update.refName or ""
end

local function sourcehut_object_id(value)
  if type(value) == "table" then
    return value.id or value.target or value.sha or value.oid or ""
  end
  return value or ""
end

local function sourcehut_first_nonempty(...)
  for i = 1, select("#", ...) do
    local value = select(i, ...)
    if value ~= nil and value ~= "" then
      return value
    end
  end
  return ""
end

local function sourcehut_update_before(update)
  update = update or {}
  return sourcehut_object_id(update.old or update.oldTarget or update.from or update.before)
end

local function sourcehut_update_after(update)
  update = update or {}
  local ref = update.ref or update.reference or {}
  return sourcehut_first_nonempty(
    sourcehut_object_id(update.new or update.newTarget or update.to or update.after),
    type(ref) == "table" and (ref.target or "") or ""
  )
end

local function sourcehut_first_update(payload)
  payload = sourcehut_payload(payload)
  for _, update in ipairs(payload.updates or {}) do
    if type(update) == "table" then
      return update
    end
  end
  return payload.update
end

local function sourcehut_commit_identity(sig)
  sig = sig or {}
  local login = sourcehut_login(sig)
  return {
    name = sig.name or sig.username or login,
    email = sig.email or "",
    username = sig.username or login,
  }
end

local function translate_srht_push_commit(c)
  c = c or {}
  local author = c.author or {}
  local committer = c.committer or author
  local author_time = author.time or c.timestamp or ""
  local committer_time = committer.time or author_time
  return {
    id = c.id or c.sha or "",
    tree_id = type(c.tree) == "table" and (c.tree.id or "") or c.tree or "",
    distinct = c.distinct ~= false,
    message = c.message or "",
    timestamp = committer_time,
    url = c.url or "",
    author = {
      name = author.name or "",
      email = author.email or "",
      username = author.name or "",
    },
    committer = {
      name = committer.name or "",
      email = committer.email or "",
      username = committer.name or "",
    },
    added = c.added or {},
    removed = c.removed or {},
    modified = c.modified or {},
  }
end

local function sourcehut_update_commits(update)
  local commits = {}
  update = update or {}
  local raw_commits = update.commits or update.log and update.log.results or update.results or {}
  for _, commit in ipairs(raw_commits) do
    commits[#commits + 1] = translate_srht_push_commit(commit)
  end
  return commits
end

local function sourcehut_repo_event(payload, action)
  payload = payload or {}
  local data = sourcehut_payload(payload)
  local repository = translate_srht_repo(data.repository or {})
  return make_internal_event({
    event = "repository",
    action = action,
    provider = "sourcehut",
    raw = payload,
    data = {
      action = action,
      repository = repository,
      sender = sourcehut_sender(payload),
    },
    timestamp = (sourcehut_webhook(payload) or {}).date or data.date or repository.updated_at or "",
  })
end

local function sourcehut_git_event(payload)
  payload = payload or {}
  local update = sourcehut_first_update(payload)
  if not update then
    return nil, "No Sourcehut ref update"
  end

  local raw_ref = sourcehut_update_ref(update)
  local before = sourcehut_update_before(update)
  local after = sourcehut_update_after(update)
  local repository = sourcehut_repository(payload)
  local sender = sourcehut_sender(payload)

  if before == "" then
    before = ZERO_SHA
  end
  if after == "" then
    after = ZERO_SHA
  end

  if before == ZERO_SHA then
    return make_internal_event({
      event = "create",
      action = "create",
      provider = "sourcehut",
      raw = payload,
      data = {
        ref = ref_name(raw_ref),
        ref_type = ref_type(raw_ref),
        master_branch = repository.default_branch or "",
        description = repository.description,
        pusher_type = "user",
        repository = repository,
        sender = sender,
      },
      timestamp = (sourcehut_webhook(payload) or {}).date or "",
    })
  end

  if after == ZERO_SHA then
    return make_internal_event({
      event = "delete",
      action = "delete",
      provider = "sourcehut",
      raw = payload,
      data = {
        ref = ref_name(raw_ref),
        ref_type = ref_type(raw_ref),
        master_branch = repository.default_branch or "",
        description = repository.description,
        pusher_type = "user",
        repository = repository,
        sender = sender,
      },
      timestamp = (sourcehut_webhook(payload) or {}).date or "",
    })
  end

  local commits = sourcehut_update_commits(update)
  local head_commit = #commits > 0 and commits[#commits] or nil
  return make_internal_event({
    event = "push",
    action = "",
    provider = "sourcehut",
    raw = payload,
    data = {
      ref = raw_ref,
      before = before,
      after = after,
      created = false,
      deleted = false,
      forced = update.forced or false,
      compare = update.compare or update.compareUrl or "",
      commits = commits,
      head_commit = head_commit,
      pusher = sourcehut_commit_identity((sourcehut_payload(payload).pusher or {})),
      repository = repository,
      sender = sender,
      sourcehut_event = sourcehut_event_name(payload),
    },
    timestamp = (sourcehut_webhook(payload) or {}).date
      or (head_commit and head_commit.timestamp)
      or "",
  })
end

local function sourcehut_job_payload(payload)
  payload = sourcehut_payload(payload)
  return payload.job or payload.newJob or payload.build
end

local function sourcehut_job_state(job, forced_action)
  job = job or {}
  local status_key = tostring(job.status or job.state or ""):lower()
  local states = {
    success = { "completed", "completed", "success" },
    failed = { "completed", "completed", "failure" },
    timeout = { "completed", "completed", "failure" },
    cancelled = { "completed", "completed", "cancelled" },
    canceled = { "completed", "completed", "cancelled" },
    running = { "in_progress", "in_progress", nil },
    queued = { "requested", "queued", nil },
    pending = { "requested", "queued", nil },
  }
  local mapped = states[status_key] or { "in_progress", "in_progress", nil }
  local action = forced_action or mapped[1]
  return action, mapped[2], mapped[3]
end

local function sourcehut_job_name(job)
  job = job or {}
  return job.note or job.name or job.manifest or ("Sourcehut job " .. tostring(job.id or 0))
end

local function sourcehut_job_ref(job)
  job = job or {}
  return sourcehut_first_nonempty(job.ref, job.branch, job.head_branch)
end

local function sourcehut_job_sha(job)
  job = job or {}
  return sourcehut_first_nonempty(job.commit, job.commitId, job.commit_id, job.sha, job.head_sha)
end

local function translate_srht_workflow(job)
  job = job or {}
  local name = sourcehut_job_name(job)
  return {
    id = job.id or 0,
    name = name,
    path = job.url or job.webUrl or job.web_url or "",
    state = "active",
    url = "",
    html_url = job.url or job.webUrl or job.web_url or "",
    badge_url = "",
    created_at = job.created,
    updated_at = job.updated or job.created,
  }
end

local function translate_srht_workflow_run(job, payload, action)
  job = job or {}
  local _, status, conclusion = sourcehut_job_state(job, action)
  local sender = sourcehut_sender(payload)
  local name = sourcehut_job_name(job)
  return {
    id = job.id or 0,
    name = name,
    head_branch = ref_name(sourcehut_job_ref(job)),
    head_sha = sourcehut_job_sha(job),
    run_number = job.id or 0,
    event = "push",
    display_title = name,
    status = status,
    conclusion = conclusion,
    workflow_id = job.id or 0,
    url = "",
    html_url = job.url or job.webUrl or job.web_url or "",
    pull_requests = {},
    created_at = job.created,
    updated_at = job.updated or job.created,
    run_attempt = 1,
    referenced_workflows = {},
    actor = sender,
    triggering_actor = sender,
  }
end

local function sourcehut_job_event(payload, forced_action)
  payload = payload or {}
  local job = sourcehut_job_payload(payload) or {}
  local action = sourcehut_job_state(job, forced_action)
  local repository = sourcehut_repository(payload)
  local workflow_run = translate_srht_workflow_run(job, payload, action)
  return make_internal_event({
    event = "workflow_run",
    action = action,
    provider = "sourcehut",
    raw = payload,
    data = {
      action = action,
      workflow = translate_srht_workflow(job),
      workflow_run = workflow_run,
      repository = repository,
      sender = sourcehut_sender(payload),
    },
    timestamp = (sourcehut_webhook(payload) or {}).date
      or workflow_run.updated_at
      or workflow_run.created_at
      or "",
  })
end

local function sourcehut_patchset_payload(payload)
  payload = sourcehut_payload(payload)
  return payload.patchset or payload.newPatchset
end

local function sourcehut_patchset_sender(patchset)
  patchset = patchset or {}
  return translate_srht_user(patchset.submitter or patchset.owner or patchset.author)
end

local function translate_srht_patchset(patchset, payload)
  patchset = patchset or {}
  local repository = sourcehut_repository(payload)
  local sender = sourcehut_patchset_sender(patchset)
  local number = patchset.id or patchset.number or 0
  local base_ref = sourcehut_first_nonempty(
    patchset.targetBranch,
    patchset.target_branch,
    patchset.base,
    repository.default_branch
  )
  return {
    id = patchset.id or 0,
    node_id = patchset.rid or "",
    number = number,
    state = "open",
    locked = false,
    title = patchset.subject or patchset.title or "",
    user = sender,
    body = patchset.coverLetter or patchset.cover_letter or patchset.body or "",
    created_at = patchset.created,
    updated_at = patchset.updated or patchset.created,
    closed_at = nil,
    merged_at = nil,
    merge_commit_sha = nil,
    assignee = nil,
    assignees = {},
    requested_reviewers = {},
    requested_teams = {},
    labels = {},
    milestone = nil,
    draft = false,
    commits_url = "",
    review_comments_url = "",
    review_comment_url = "",
    comments_url = "",
    statuses_url = "",
    head = {
      label = sourcehut_first_nonempty(patchset.ref, patchset.branch, "patchset/" .. number),
      ref = sourcehut_first_nonempty(patchset.ref, patchset.branch, "patchset/" .. number),
      sha = sourcehut_first_nonempty(patchset.commit, patchset.commitId, patchset.sha),
      user = sender,
      repo = repository,
    },
    base = {
      label = base_ref,
      ref = base_ref,
      sha = sourcehut_first_nonempty(patchset.baseCommit, patchset.base_commit, patchset.baseSha),
      user = repository.owner or {},
      repo = repository,
    },
    html_url = patchset.url or patchset.webUrl or patchset.web_url or "",
    url = "",
    diff_url = "",
    patch_url = "",
    merged = false,
    mergeable = nil,
    rebaseable = nil,
    mergeable_state = "unknown",
    merged_by = nil,
    comments = 0,
    review_comments = 0,
    commits = 0,
    additions = 0,
    deletions = 0,
    changed_files = 0,
  }
end

local function sourcehut_patchset_event(payload)
  payload = payload or {}
  local patchset = sourcehut_patchset_payload(payload) or {}
  local pull_request = translate_srht_patchset(patchset, payload)
  local sender = sourcehut_sender(payload)
  return make_internal_event({
    event = "pull_request",
    action = "opened",
    provider = "sourcehut",
    raw = payload,
    data = {
      action = "opened",
      number = pull_request.number,
      pull_request = pull_request,
      repository = sourcehut_repository(payload),
      sender = sender.login ~= "" and sender or sourcehut_patchset_sender(patchset),
    },
    timestamp = (sourcehut_webhook(payload) or {}).date
      or pull_request.updated_at
      or pull_request.created_at
      or "",
  })
end

local SOURCEHUT_ACTIONLESS_NORMALIZED_EVENTS = {
  create = true,
  delete = true,
  push = true,
}

local function sourcehut_normalized_payload_without_envelope_fields(data)
  local payload = {}
  for k, v in pairs(data or {}) do
    if k ~= "sender" and k ~= "repository" then
      payload[k] = v
    end
  end
  return payload
end

local function translate_sourcehut_normalized_webhook(internal_event, fields)
  local data = internal_event.data or {}
  fields = fields or {}
  return make_normalized_webhook_envelope(internal_event, {
    id = fields.id,
    type = fields.type
      or (
        SOURCEHUT_ACTIONLESS_NORMALIZED_EVENTS[internal_event.event]
          and normalized_webhook_event_type(internal_event.event, "")
        or normalized_webhook_event_type(internal_event.event, internal_event.action)
      ),
    occurred_at = fields.occurred_at,
    actor = fields.actor or data.sender,
    repository = fields.repository or data.repository,
    payload = fields.payload or sourcehut_normalized_payload_without_envelope_fields(data),
  })
end

local function translate_sourcehut_github_webhook(internal_event, _fields)
  local data = internal_event.data or {}
  local payload = {
    action = data.action or internal_event.action,
    repository = data.repository or {},
    sender = data.sender or {},
  }
  if internal_event.event == "push" then
    payload.action = nil
    payload.ref = data.ref or ""
    payload.before = data.before or ""
    payload.after = data.after or ""
    payload.created = data.created or false
    payload.deleted = data.deleted or false
    payload.forced = data.forced or false
    payload.compare = data.compare or ""
    payload.commits = data.commits or {}
    payload.head_commit = data.head_commit
    payload.pusher = data.pusher or {}
  elseif internal_event.event == "create" or internal_event.event == "delete" then
    payload.ref = data.ref or ""
    payload.ref_type = data.ref_type or ""
    payload.master_branch = data.master_branch or ""
    payload.description = data.description
    payload.pusher_type = data.pusher_type or "user"
  elseif internal_event.event == "issues" then
    payload.issue = data.issue or {}
    if data.label then
      payload.label = data.label
    end
    if data.assignee then
      payload.assignee = data.assignee
    end
  elseif internal_event.event == "issue_comment" then
    payload.issue = data.issue or {}
    payload.comment = data.comment or {}
  elseif internal_event.event == "label" then
    payload.label = data.label or {}
    payload.changes = data.changes or {}
  elseif internal_event.event == "workflow_run" then
    payload.workflow_run = data.workflow_run or {}
    payload.workflow = data.workflow or {}
  elseif internal_event.event == "pull_request" then
    payload.number = data.number
    payload.pull_request = data.pull_request or {}
  end
  return payload
end

local b = make_backend_builder()
b:rest("get_root", function()
  proxy_health_check(pcall(Fetch, config.base_url .. "/api/version", auth()))
end)

b:rest(
  "get_repo",
  proxy_handler(translate_srht_repo, function(owner, repo_name)
    return base() .. "/~" .. owner .. "/repos/" .. repo_name
  end)
)

b:rest("patch_repo", function(owner, repo_name)
  -- Sourcehut uses PUT for updates
  proxy_json(
    translate_srht_repo,
    fetch_json(
      base() .. "/~" .. owner .. "/repos/" .. repo_name,
      "PUT",
      translate_srht_req(GetBody())
    )
  )
end)

b:rest("delete_repo", function(owner, repo_name)
  local url = base() .. "/~" .. owner .. "/repos/" .. repo_name
  local dopts = auth() or {}
  dopts.method = "DELETE"
  proxy_204({ 200 }, pcall(Fetch, url, dopts))
end)

b:rest("get_user_repos", function()
  -- Sourcehut: need to know the authenticated user. Use /api/user first.
  local ok, status, _, ubody = fetch_json(config.base_url .. "/api/user")
  if not ok or status ~= 200 then
    respond_json(503, {})
    return
  end
  local user = DecodeJson(ubody)
  local canonical = user.canonical_name or ("~" .. (user.name or ""))
  proxy_json(
    function(data)
      return translate_list(translate_srht_repo, data.results)
    end,
    -- Sourcehut uses cursor-based pagination; only limit is supported for page size
    fetch_json(append_page_params(base() .. "/" .. canonical .. "/repos", PAGES))
  )
end)

b:rest("post_user_repos", function()
  -- Sourcehut: create via POST /api/~{user}/repos — need user context
  local ok, status, _, ubody = fetch_json(config.base_url .. "/api/user")
  if not ok or status ~= 200 then
    respond_json(503, {})
    return
  end
  local user = DecodeJson(ubody)
  local canonical = user.canonical_name or ("~" .. (user.name or ""))
  proxy_json_created(
    translate_srht_repo,
    fetch_json(base() .. "/" .. canonical .. "/repos", "POST", translate_srht_req(GetBody()))
  )
end)

-- Branches ------------------------------------------------------------------
-- Sourcehut: filter /refs for refs starting with "refs/heads/"

b:rest(
  "get_repo_branches",
  proxy_handler(function(data)
    local branches = {}
    for _, ref in ipairs(data.results or {}) do
      if ref.name and ref.name:match("^refs/heads/") then
        branches[#branches + 1] = translate_srht_branch(ref)
      end
    end
    return branches
  end, function(owner, repo_name)
    return base() .. "/~" .. owner .. "/repos/" .. repo_name .. "/refs"
  end)
)

b:rest(
  "get_repo_branch",
  proxy_handler(function(data, _owner, _repo_name, branch)
    for _, ref in ipairs(data.results or {}) do
      if ref.name == "refs/heads/" .. branch then
        return translate_srht_branch(ref)
      end
    end
    return {}
  end, function(owner, repo_name)
    return base() .. "/~" .. owner .. "/repos/" .. repo_name .. "/refs"
  end)
)

-- Tags ----------------------------------------------------------------------
-- Sourcehut /refs returns { results: [...] } with name and target fields
-- Filter to tags only (refs starting with "refs/tags/")

b:rest("get_repo_tags", function(owner, repo_name)
  proxy_json(function(data)
    local tags = {}
    for _, ref in ipairs(data.results or {}) do
      local tag_name = ref.name and ref.name:match("^refs/tags/(.+)")
      if tag_name then
        tags[#tags + 1] = { name = tag_name, commit = { sha = ref.target or "", url = "" } }
      end
    end
    return tags
  end, fetch_json(base() .. "/~" .. owner .. "/repos/" .. repo_name .. "/refs"))
end)

-- Commits -------------------------------------------------------------------
-- Sourcehut: GET /api/~{owner}/repos/{name}/log or /log/{ref}

b:rest("get_repo_commits", function(owner, repo_name)
  local ref = GetParam("sha") or ""
  local url = base() .. "/~" .. owner .. "/repos/" .. repo_name .. "/log"
  if ref ~= "" then
    url = url .. "/" .. ref
  end
  url = append_page_params(url, PAGES)
  proxy_json(function(data)
    return translate_list(translate_srht_commit, data.results)
  end, fetch_json(url))
end)

b:rest("get_repo_commit", function(owner, repo_name, ref)
  -- Fetch the log at the specific ref and return first entry.
  proxy_json(
    function(data)
      local c = (data.results or {})[1]
      return translate_srht_commit(c)
    end,
    fetch_json(base() .. "/~" .. owner .. "/repos/" .. repo_name .. "/log/" .. ref .. "?limit=1")
  )
end)

-- Contents ------------------------------------------------------------------
-- Sourcehut: GET /api/~{owner}/repos/{name}/blob/{ref}/{path} — raw bytes.

b:rest("get_repo_readme", function(owner, repo_name)
  local ref = GetParam("ref") or "HEAD"
  local candidates = { "README.md", "README", "readme.md", "README.rst" }
  for _, fname in ipairs(candidates) do
    local url = base() .. "/~" .. owner .. "/repos/" .. repo_name .. "/blob/" .. ref .. "/" .. fname
    local ok, status, _, body = fetch_json(url)
    if ok and status == 200 then
      respond_json(200, {
        type = "file",
        name = fname,
        path = fname,
        sha = "",
        size = #body,
        encoding = "base64",
        content = EncodeBase64(body),
      })
      return
    end
  end
  respond_json(404, { message = "Not Found" })
end)

b:rest("get_repo_content", function(owner, repo_name, path)
  local ref = GetParam("ref") or "HEAD"
  local url = base() .. "/~" .. owner .. "/repos/" .. repo_name .. "/blob/" .. ref .. "/" .. path
  local ok, status, _, body = fetch_json(url)
  if ok and status == 200 then
    respond_json(200, {
      type = "file",
      name = path:match("[^/]+$") or path,
      path = path,
      sha = "",
      size = #body,
      encoding = "base64",
      content = EncodeBase64(body),
    })
  elseif ok then
    respond_json(status, { message = "Error" })
  else
    respond_json(503, {})
  end
end)

-- Users' repos --------------------------------------------------------------

b:rest("get_users_repos", function(username)
  proxy_json(function(data)
    return translate_list(translate_srht_repo, data.results)
  end, fetch_json(append_page_params(base() .. "/~" .. username .. "/repos", PAGES)))
end)

-- Users ---------------------------------------------------------------------

-- GET /user
b:rest("get_user", function()
  proxy_json(function(u)
    if not u then
      return {}
    end
    local canonical = u.canonical_name or ""
    local login = canonical:sub(1, 1) == "~" and canonical:sub(2) or canonical
    return {
      login = login,
      id = 0,
      node_id = "",
      avatar_url = "",
      html_url = config.base_url .. "/" .. canonical,
      type = "User",
      site_admin = false,
      name = u.name or canonical,
      email = u.email or "",
      blog = u.url or "",
    }
  end, fetch_json(base() .. "/user"))
end)

-- Issues --------------------------------------------------------------------
-- todo.sr.ht: GET /api/~{owner}/trackers/{repo}/tickets

b:rest("get_repo_issues", function(owner, repo_name)
  local url = todo_base() .. "/~" .. owner .. "/trackers/" .. repo_name .. "/tickets"
  url = append_page_params(url, PAGES)
  proxy_json(function(data)
    return translate_list(translate_srht_ticket, data.results)
  end, fetch_json(url))
end)

-- GET /repos/{owner}/{repo}/issues/{issue_number}
-- Cannot use proxy_json: todo.sr.ht returns a 404 body with tracker-specific
-- error text; we emit a clean GitHub-shaped { message = "Not Found" } instead.
b:rest("get_repo_issue", function(owner, repo_name, issue_number)
  local url = todo_base()
    .. "/~"
    .. owner
    .. "/trackers/"
    .. repo_name
    .. "/tickets/"
    .. issue_number
  local ok, status, _, body = fetch_json(url)
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
  local ticket = DecodeJson(body)
  respond_json(200, translate_srht_ticket(ticket))
end)

-- POST /repos/{owner}/{repo}/issues
b:rest("post_repo_issues", function(owner, repo_name)
  local req = DecodeJson(GetBody() or "{}")
  local payload = EncodeJson({ title = req.title or "", description = req.body or "" })
  proxy_json_created(
    translate_srht_ticket,
    fetch_json(
      todo_base() .. "/~" .. owner .. "/trackers/" .. repo_name .. "/tickets",
      "POST",
      payload
    )
  )
end)

-- GET /repos/{owner}/{repo}/issues/{issue_number}/comments
-- todo.sr.ht: GET /api/~{owner}/trackers/{repo}/tickets/{id}/events
-- Filter events to only those with a comment field.
b:rest("get_issue_comments", function(owner, repo_name, issue_number)
  local url = todo_base()
    .. "/~"
    .. owner
    .. "/trackers/"
    .. repo_name
    .. "/tickets/"
    .. issue_number
    .. "/events"
  url = append_page_params(url, PAGES)
  proxy_json(function(data)
    local events = data.results or {}
    local comments = {}
    for _, e in ipairs(events) do
      local c = translate_srht_event_comment(e)
      if c then
        comments[#comments + 1] = c
      end
    end
    return comments
  end, fetch_json(url))
end)

-- POST /repos/{owner}/{repo}/issues/{issue_number}/comments
b:rest("post_issue_comment", function(owner, repo_name, issue_number)
  local req = DecodeJson(GetBody() or "{}")
  local payload = EncodeJson({ comment = req.body or "" })
  local url = todo_base()
    .. "/~"
    .. owner
    .. "/trackers/"
    .. repo_name
    .. "/tickets/"
    .. issue_number
    .. "/events"
  proxy_json_created(function(e)
    return translate_srht_event_comment(e) or {}
  end, fetch_json(url, "POST", payload))
end)

-- Checks (via builds.sr.ht jobs) --------------------------------------------

-- GET /repos/{owner}/{repo}/commits/{ref}/check-runs
-- Maps to builds.sr.ht GET /api/jobs filtered by the git repo tag and commit SHA.
-- builds.sr.ht jobs are tagged with "git.sr.ht/~owner/repo=sha" when triggered
-- from a git push.
b:rest("get_commit_check_runs", function(owner, repo_name, ref)
  -- Derive the git.sr.ht hostname from the config base URL for the tag filter.
  local git_host = config.base_url:match("^https?://([^/]+)") or "git.sr.ht"
  local tag = git_host .. "/~" .. owner .. "/" .. repo_name .. "=" .. ref
  local url = builds_base() .. "/jobs?filter[tags]=" .. tag
  local ok, status, _, body = fetch_json(url)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local data = DecodeJson(body) or {}
  local runs = translate_list(translate_srht_job_to_check_run, data.results)
  respond_json(200, { total_count = #runs, check_runs = runs })
end)

-- Code scanning: Sourcehut has no native code scanning API.
-- All code scanning endpoints fall back to the default handlers in .init.lua:
-- list endpoints return 200 empty, per-resource endpoints return 501.

-- GraphQL resolvers --------------------------------------------------------
-- Sourcehut scope: Query.repository, Query.viewer, Repository.issues.
-- No Query.user (no endpoint to fetch an arbitrary user by login).
-- No Repository.pullRequests (Sourcehut has no PR model).

-- Translate a Sourcehut user (canonical_name/name) into a GitHub REST-shaped
-- user table suitable for graphql_translate_user.
local function translate_srht_user_for_graphql(u)
  if not u then
    return {}
  end
  local canonical = u.canonical_name or ""
  local login = canonical:sub(1, 1) == "~" and canonical:sub(2) or canonical
  return {
    login = login,
    id = 0,
    node_id = "",
    avatar_url = "",
    html_url = config.base_url .. "/" .. canonical,
    type = "User",
    site_admin = false,
    name = u.name or canonical,
    email = u.email or "",
    blog = u.url or "",
  }
end

b:graphql("Query.repository", function(_parent, args, ctx)
  if not args.owner or not args.name then
    graphql_error(ctx, "repository requires owner and name arguments")
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, base() .. "/~" .. args.owner .. "/repos/" .. args.name)
  if not data then
    return nil
  end
  return graphql_translate_repo(translate_srht_repo(data))
end)

b:graphql("node.Repository", function(local_id, _ctx)
  local owner, name = local_id:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, base() .. "/~" .. owner .. "/repos/" .. name)
  if not data then
    return nil
  end
  return graphql_translate_repo(translate_srht_repo(data))
end)

b:graphql("Query.viewer", function(_parent, _args, ctx)
  local data = graphql_fetch_or_error(fetch_json, base() .. "/user", ctx, nil)
  if not data then
    return nil
  end
  local u = graphql_translate_user(translate_srht_user_for_graphql(data))
  u.isViewer = true
  return u
end)

-- Repository.issues: paginated list of issues via todo.sr.ht trackers.
-- Sourcehut pagination uses cursor-based results with a `limit` param;
-- graphql_cursor_url cannot be used (no page-number param), so we build
-- the URL manually like bbs_repo_connection does.
-- Backward pagination (last/before): Sourcehut exposes no total count and no
-- page-number addressing, so last: N returns the first N items (known limitation).
local function srht_issue_connection(owner, repo_name, args, ctx)
  local per_page = args.last or args.first or 30
  local url = todo_base()
    .. "/~"
    .. owner
    .. "/trackers/"
    .. repo_name
    .. "/tickets?limit="
    .. tostring(per_page)
  local data, _, err = graphql_fetch_with_headers(fetch_json, url)
  if not data then
    graphql_error(ctx, err)
    return nil
  end
  local nodes = {}
  for _, t in ipairs(data.results or {}) do
    nodes[#nodes + 1] = graphql_translate_issue(translate_srht_ticket(t), owner, repo_name)
  end
  return graphql_issues_connection(nodes, args, nil, ctx)
end

b:graphql("Repository.issues", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return srht_issue_connection(owner, name, args, ctx)
end)

b:graphql("node.Issue", function(local_id, _ctx)
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local url = todo_base() .. "/~" .. owner .. "/trackers/" .. repo .. "/tickets/" .. number
  local data, _ = graphql_fetch(fetch_json, url)
  if not data then
    return nil
  end
  return graphql_translate_issue(translate_srht_ticket(data), owner, repo)
end)

b:webhook("REPO_CREATED", function(payload)
  return sourcehut_repo_event(payload, "created")
end)

b:webhook("REPO_UPDATE", function(payload)
  return sourcehut_repo_event(payload, "edited")
end)

b:webhook("REPO_DELETED", function(payload)
  return sourcehut_repo_event(payload, "deleted")
end)

b:webhook("GIT_PRE_RECEIVE", sourcehut_git_event)
b:webhook("GIT_POST_RECEIVE", sourcehut_git_event)

b:webhook("TICKET_CREATED", function(payload)
  return sourcehut_ticket_event(payload, "opened")
end)

b:webhook("TICKET_UPDATE", function(payload)
  return sourcehut_ticket_event(payload, "edited")
end)

b:webhook("TICKET_DELETED", sourcehut_deleted_ticket_event)

b:webhook("LABEL_CREATED", function(payload)
  return sourcehut_label_event(payload, "created")
end)

b:webhook("LABEL_UPDATE", function(payload)
  return sourcehut_label_event(payload, "edited")
end)

b:webhook("LABEL_DELETED", function(payload)
  return sourcehut_label_event(payload, "deleted")
end)

b:webhook("EVENT_CREATED", sourcehut_event_created)

b:webhook("JOB_CREATED", function(payload)
  return sourcehut_job_event(payload, "requested")
end)

b:webhook("JOB_UPDATED", sourcehut_job_event)

b:webhook("PATCHSET_RECEIVED", sourcehut_patchset_event)

for _, event in ipairs({
  "push",
  "create",
  "delete",
  "repository",
  "issues",
  "issue_comment",
  "label",
  "workflow_run",
  "pull_request",
}) do
  b:webhook_translator(event, translate_sourcehut_normalized_webhook)
  b:webhook_github_translator(event, translate_sourcehut_github_webhook)
end

b:build()
