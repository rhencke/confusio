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

local function sourceforge_user_login(u)
  return u.username or u.login or u.name or ""
end

local translate_sourceforge_user = make_translator({
  login = computed(sourceforge_user_login),
  id = const(0),
  node_id = const(""),
  avatar_url = field("avatar_url", { default = "" }),
  url = field("url", { default = "" }),
  html_url = field("url", { default = "" }),
  type = const("User"),
  site_admin = const(false),
  name = computed(function(u)
    return u.name or sourceforge_user_login(u)
  end),
  email = field("email", { default = "" }),
})

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

local function sourceforge_repo_name(repo)
  local _, name = sourceforge_repo_parts(repo)
  return name
end

local function sourceforge_repo_owner(repo)
  local owner, name = sourceforge_repo_parts(repo)
  return owner, name
end

local function sourceforge_repo_full_name(repo)
  local owner, name = sourceforge_repo_parts(repo)
  local full_name = owner ~= "" and name ~= "" and (owner .. "/" .. name)
    or (repo.full_name or name)
  return full_name
end

local translate_sourceforge_repo_owner = make_translator({
  login = computed(sourceforge_repo_owner),
  id = const(0),
  node_id = const(""),
  avatar_url = const(""),
  url = const(""),
  html_url = computed(function(repo)
    local owner = sourceforge_repo_owner(repo)
    return owner ~= "" and (config.base_url .. "/p/" .. owner .. "/") or ""
  end),
  type = const("Organization"),
})

local translate_sourceforge_repo = make_translator({
  id = const(0),
  node_id = const(""),
  name = computed(sourceforge_repo_name),
  full_name = computed(sourceforge_repo_full_name),
  private = const(false),
  owner = computed(function(repo)
    return translate_sourceforge_repo_owner(repo)
  end),
  html_url = computed(function(repo)
    local owner, name = sourceforge_repo_parts(repo)
    return sourceforge_repo_url(owner, name, repo)
  end),
  description = "description",
  fork = const(false),
  url = const(""),
  git_url = field("git_url", { default = "" }),
  ssh_url = field("ssh_url", { default = "" }),
  clone_url = computed(function(repo)
    return repo.clone_url or repo.url or ""
  end),
  homepage = computed(function(repo)
    local owner, name = sourceforge_repo_parts(repo)
    local url = sourceforge_repo_url(owner, name, repo)
    return repo.homepage or url
  end),
  size = const(0),
  stargazers_count = const(0),
  watchers_count = const(0),
  language = const(nil),
  has_issues = const(false),
  has_wiki = const(false),
  forks_count = const(0),
  archived = const(false),
  disabled = const(false),
  open_issues_count = const(0),
  default_branch = field("default_branch", { default = "master" }),
  visibility = const("public"),
  forks = const(0),
  open_issues = const(0),
  watchers = const(0),
  created_at = "created_at",
  updated_at = "updated_at",
  pushed_at = "pushed_at",
})

local function sourceforge_commit_author(c)
  return c.author or {}
end

local function sourceforge_commit_committer(c)
  return c.committer or sourceforge_commit_author(c)
end

local translate_sourceforge_commit_author = make_translator({
  name = field("name", { default = "" }),
  email = field("email", { default = "" }),
  username = computed(function(author)
    return author.username or author.login or author.name or ""
  end),
})

local translate_sourceforge_commit_committer = make_translator({
  name = computed(function(c)
    local committer = sourceforge_commit_committer(c)
    local author = sourceforge_commit_author(c)
    return committer.name or author.name or ""
  end),
  email = computed(function(c)
    local committer = sourceforge_commit_committer(c)
    local author = sourceforge_commit_author(c)
    return committer.email or author.email or ""
  end),
  username = computed(function(c)
    local committer = sourceforge_commit_committer(c)
    local author = sourceforge_commit_author(c)
    return committer.username or committer.login or committer.name or author.name or ""
  end),
})

local translate_sourceforge_commit = make_translator({
  id = computed(function(c)
    return c.id or c.sha or ""
  end),
  message = field("message", { default = "" }),
  timestamp = computed(function(c)
    return c.timestamp or c.date or ""
  end),
  url = field("url", { default = "" }),
  author = computed(function(c)
    return translate_sourceforge_commit_author(sourceforge_commit_author(c))
  end),
  committer = computed(function(c)
    return translate_sourceforge_commit_committer(c)
  end),
  added = computed(function(c)
    return c.added or {}
  end),
  removed = computed(function(c)
    return c.removed or {}
  end),
  modified = computed(function(c)
    return c.modified or {}
  end),
})

local function sourceforge_commits(commits)
  return translate_list(translate_sourceforge_commit, commits)
end

local function sourceforge_sender(payload)
  return translate_sourceforge_user(payload.sender or payload.pusher or payload.author or {})
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
  local repository = translate_sourceforge_repo(payload.repository or {})
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

local function translate_sourceforge_github_webhook(internal_event, fields)
  return github_webhook_payload(internal_event, fields)
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
