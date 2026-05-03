-- SourceForge backend handler overrides.
if config.base_url == "" then
  config.base_url = "https://sourceforge.net"
end

local ZERO_SHA = "0000000000000000000000000000000000000000"

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

local function sourceforge_repo_parts(repo)
  repo = repo or {}
  local project, tool = tostring(repo.full_name or ""):match("^/p/([^/]+)/([^/]+)/?$")
  if project then
    return project, tool
  end
  project, tool = tostring(repo.url or repo.homepage or ""):match("/p/([^/]+)/([^/]+)/?$")
  if project then
    return project, tool
  end
  project, tool = tostring(repo.full_name or ""):match("^([^/]+)/(.+)$")
  return project or "", tool or repo.name or ""
end

local function translate_sourceforge_user(u)
  u = u or {}
  local login = u.username or u.login or u.name or ""
  return {
    login = login,
    id = 0,
    node_id = "",
    avatar_url = u.avatar_url or "",
    url = u.url or "",
    html_url = u.url or "",
    type = "User",
    site_admin = false,
    name = u.name or login,
    email = u.email or "",
  }
end

local function sourceforge_repo_url(owner, name, repo)
  if repo and repo.url and repo.url ~= "" then
    return repo.url
  end
  if repo and repo.homepage and repo.homepage ~= "" then
    return repo.homepage
  end
  if owner ~= "" and name ~= "" then
    return config.base_url .. "/p/" .. owner .. "/" .. name .. "/"
  end
  return ""
end

local function translate_sourceforge_repo(repo)
  repo = repo or {}
  local owner, name = sourceforge_repo_parts(repo)
  local url = sourceforge_repo_url(owner, name, repo)
  local full_name = owner ~= "" and name ~= "" and (owner .. "/" .. name)
    or (repo.full_name or name)
  return {
    id = 0,
    node_id = "",
    name = name,
    full_name = full_name,
    private = false,
    owner = {
      login = owner,
      id = 0,
      node_id = "",
      avatar_url = "",
      url = "",
      html_url = owner ~= "" and (config.base_url .. "/p/" .. owner .. "/") or "",
      type = "Organization",
    },
    html_url = url,
    description = repo.description,
    fork = false,
    url = "",
    git_url = repo.git_url or "",
    ssh_url = repo.ssh_url or "",
    clone_url = repo.clone_url or repo.url or "",
    homepage = repo.homepage or url,
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
    default_branch = repo.default_branch or "master",
    visibility = "public",
    forks = 0,
    open_issues = 0,
    watchers = 0,
    created_at = repo.created_at,
    updated_at = repo.updated_at,
    pushed_at = repo.pushed_at,
  }
end

local function translate_sourceforge_commit(c)
  c = c or {}
  local author = c.author or {}
  local committer = c.committer or author
  return {
    id = c.id or c.sha or "",
    message = c.message or "",
    timestamp = c.timestamp or c.date or "",
    url = c.url or "",
    author = {
      name = author.name or "",
      email = author.email or "",
      username = author.username or author.login or author.name or "",
    },
    committer = {
      name = committer.name or author.name or "",
      email = committer.email or author.email or "",
      username = committer.username or committer.login or committer.name or author.name or "",
    },
    added = c.added or {},
    removed = c.removed or {},
    modified = c.modified or {},
  }
end

local function sourceforge_commits(commits)
  local result = {}
  for _, commit in ipairs(commits or {}) do
    result[#result + 1] = translate_sourceforge_commit(commit)
  end
  return result
end

local function sourceforge_sender(payload)
  return translate_sourceforge_user(payload.sender or payload.pusher or payload.author)
end

local function sourceforge_pusher(payload)
  local pusher = payload.pusher or payload.sender or payload.author or {}
  return {
    name = pusher.name or pusher.username or pusher.login or "",
    email = pusher.email or "",
  }
end

local function sourceforge_ref_webhook(payload)
  payload = payload or {}
  local raw_ref = payload.ref or ""
  local before = payload.before or ""
  local after = payload.after or ""
  local repository = translate_sourceforge_repo(payload.repository)
  local sender = sourceforge_sender(payload)

  if before == ZERO_SHA then
    return make_internal_event({
      event = "create",
      action = "create",
      provider = "sourceforge",
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
      timestamp = payload.timestamp or "",
    })
  end

  if after == ZERO_SHA then
    return make_internal_event({
      event = "delete",
      action = "delete",
      provider = "sourceforge",
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
      timestamp = payload.timestamp or "",
    })
  end

  local commits = sourceforge_commits(payload.commits)
  local head_commit = #commits > 0 and commits[#commits] or nil
  return make_internal_event({
    event = "push",
    action = "push",
    provider = "sourceforge",
    raw = payload,
    data = {
      ref = raw_ref,
      before = before,
      after = after,
      created = false,
      deleted = false,
      forced = payload.forced or false,
      compare = payload.compare or payload.compare_url or "",
      commits = commits,
      head_commit = head_commit,
      pusher = sourceforge_pusher(payload),
      repository = repository,
      sender = sender,
    },
    timestamp = payload.timestamp or (head_commit and head_commit.timestamp) or "",
  })
end

local SOURCEFORGE_ACTIONLESS_NORMALIZED_EVENTS = {
  create = true,
  delete = true,
  push = true,
}

local function sourceforge_normalized_payload_without_envelope_fields(data)
  local payload = {}
  for k, v in pairs(data or {}) do
    if k ~= "sender" and k ~= "repository" then
      payload[k] = v
    end
  end
  return payload
end

local function translate_sourceforge_normalized_webhook(internal_event, fields)
  local data = internal_event.data or {}
  fields = fields or {}
  return make_normalized_webhook_envelope(internal_event, {
    id = fields.id,
    type = fields.type
      or (
        SOURCEFORGE_ACTIONLESS_NORMALIZED_EVENTS[internal_event.event]
          and normalized_webhook_event_type(internal_event.event, "")
        or normalized_webhook_event_type(internal_event.event, internal_event.action)
      ),
    occurred_at = fields.occurred_at,
    actor = fields.actor or data.sender,
    repository = fields.repository or data.repository,
    payload = fields.payload or sourceforge_normalized_payload_without_envelope_fields(data),
  })
end

local function translate_sourceforge_github_webhook(internal_event)
  return github_webhook_payload(internal_event)
end

local b = make_backend_builder()
b:rest("get_root", function()
  proxy_health_check(pcall(Fetch, config.base_url .. "/rest/p"))
end)

b:webhook("repo-push", sourceforge_ref_webhook)

for _, event in ipairs({ "push", "create", "delete" }) do
  b:webhook_translator(event, translate_sourceforge_normalized_webhook)
  b:webhook_github_translator(event, translate_sourceforge_github_webhook)
end

-- Issues -----------------------------------------------------------------------
-- SourceForge uses the Allura ticket tracker, whose REST API shape differs
-- significantly from GitHub Issues and is not currently mapped.
-- All issues, labels, milestones, and assignees endpoints fall back to the
-- default empty-list / 404 handlers defined in .init.lua.

b:build()
