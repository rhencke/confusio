-- Tuleap backend handler overrides.
-- Uses Tuleap REST API v1 at /api/v1/.
-- owner = project shortname, repo = git repository name within that project.
if config.base_url == "" then
  config.base_url = "https://tuleap.net"
end

local base = function()
  return config.base_url .. "/api/v1"
end

local auth = function()
  return make_fetch_opts("bearer")
end
local fetch_json = make_backend_transport("bearer").fetch_json
local ZERO_SHA = "0000000000000000000000000000000000000000"

local function short_ref(ref)
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

local function tuleap_repo_project(r)
  return r.project or {}
end

local function tuleap_repo_name(r)
  return r.name or ""
end

local function tuleap_repo_full_name(r)
  local project = tuleap_repo_project(r)
  local name = tuleap_repo_name(r)
  local full_name = r.full_name or ""
  local shortname = project.shortname
    or project.path
    or project.name
    or full_name:match("^([^/]+)/")
    or ""
  if full_name == "" then
    full_name = shortname ~= "" and (shortname .. "/" .. name) or name
  end
  return full_name
end

local function tuleap_repo_shortname(r)
  local project = tuleap_repo_project(r)
  local full_name = r.full_name or ""
  return project.shortname or project.path or project.name or full_name:match("^([^/]+)/") or ""
end

local translate_tuleap_repo_owner = make_translator({
  login = computed(tuleap_repo_shortname),
  id = computed(function(r)
    return tuleap_repo_project(r).id or 0
  end),
  node_id = const(""),
  avatar_url = const(""),
  url = const(""),
  html_url = computed(function(r)
    return config.base_url .. "/projects/" .. tuleap_repo_shortname(r)
  end),
  type = const("Organization"),
})

-- Translate a Tuleap git repository object to GitHub format.
local translate_tuleap_repo = make_translator({
  id = field("id", { default = 0 }),
  node_id = const(""),
  name = computed(tuleap_repo_name),
  full_name = computed(tuleap_repo_full_name),
  private = const(false),
  owner = computed(function(r)
    return translate_tuleap_repo_owner(r)
  end),
  html_url = field("http_url", { default = "" }),
  description = "description",
  fork = const(false),
  url = const(""),
  clone_url = field("clone_http_url", { default = "" }),
  homepage = const(""),
  size = const(0),
  stargazers_count = const(0),
  watchers_count = const(0),
  language = const(nil),
  has_issues = const(true),
  has_wiki = const(false),
  forks_count = const(0),
  archived = const(false),
  disabled = const(false),
  open_issues_count = const(0),
  default_branch = field("default_branch", { default = "main" }),
  visibility = const("public"),
  forks = const(0),
  open_issues = const(0),
  watchers = const(0),
  created_at = const(nil),
  updated_at = const(nil),
  pushed_at = const(nil),
})

local function tuleap_user_login(u)
  return u.username or u.login or u.name or u.real_name or ""
end

local function tuleap_user_html_url(u)
  local login = tuleap_user_login(u)
  local html_url = u.user_url or ""
  if html_url == "" then
    html_url = config.base_url .. "/users/" .. login
  elseif html_url:match("^/") then
    html_url = config.base_url .. html_url
  end
  return html_url
end

-- Translate a Tuleap user object to GitHub format.
local translate_tuleap_user = make_translator({
  login = computed(tuleap_user_login),
  id = field("id", { default = 0 }),
  node_id = const(""),
  avatar_url = field("avatar_url", { default = "" }),
  html_url = computed(tuleap_user_html_url),
  type = const("User"),
  site_admin = const(false),
  name = computed(function(u)
    return u.real_name or u.display_name or tuleap_user_login(u)
  end),
  email = field("email", { default = "" }),
  blog = const(""),
})

local function tuleap_project_url(path)
  if path and path ~= "" then
    return config.base_url .. "/projects/" .. path
  end
  return ""
end

local function tuleap_project_webhook_sender(payload)
  return translate_tuleap_user({
    id = payload.owner_id,
    username = payload.owner_username or payload.owner_name,
    real_name = payload.owner_name,
    email = payload.owner_email,
  })
end

local translate_tuleap_project_webhook = make_translator({
  id = computed(function(payload)
    return payload.project_id or payload.id or 0
  end),
  node_id = const(""),
  name = computed(function(payload)
    return payload.name or payload.path or ""
  end),
  body = field("description", { default = "" }),
  url = const(""),
  html_url = computed(function(payload)
    return tuleap_project_url(payload.path)
  end),
  owner_url = computed(function(payload)
    return tuleap_project_webhook_sender(payload).html_url or ""
  end),
  creator = computed(tuleap_project_webhook_sender),
  created_at = field("created_at", { default = "" }),
  updated_at = computed(function(payload)
    return payload.updated_at or payload.created_at or ""
  end),
  path = field("path", { default = "" }),
  path_with_namespace = computed(function(payload)
    return payload.path_with_namespace or payload.path or ""
  end),
  visibility = computed(function(payload)
    return payload.project_visibility or payload.visibility or ""
  end),
})

local function tuleap_commit_author(c)
  return c.author or {}
end

local function tuleap_commit_committer(c)
  return c.committer or tuleap_commit_author(c)
end

local translate_tuleap_commit_author = make_translator({
  name = field("name", { default = "" }),
  email = field("email", { default = "" }),
  username = computed(function(author)
    return author.username or author.login or author.name or ""
  end),
})

local translate_tuleap_commit_committer = make_translator({
  name = computed(function(c)
    local committer = tuleap_commit_committer(c)
    local author = tuleap_commit_author(c)
    return committer.name or author.name or ""
  end),
  email = computed(function(c)
    local committer = tuleap_commit_committer(c)
    local author = tuleap_commit_author(c)
    return committer.email or author.email or ""
  end),
  username = computed(function(c)
    local committer = tuleap_commit_committer(c)
    local author = tuleap_commit_author(c)
    return committer.username or committer.login or committer.name or author.name or ""
  end),
})

local translate_tuleap_commit = make_translator({
  id = computed(function(c)
    return c.id or c.sha or ""
  end),
  message = field("message", { default = "" }),
  timestamp = computed(function(c)
    return c.timestamp or c.date or ""
  end),
  url = field("url", { default = "" }),
  author = computed(function(c)
    return translate_tuleap_commit_author(tuleap_commit_author(c))
  end),
  committer = computed(function(c)
    return translate_tuleap_commit_committer(c)
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

local function translate_tuleap_commits(commits)
  return translate_list(translate_tuleap_commit, commits)
end

local function tuleap_sender(payload)
  return translate_tuleap_user(payload.sender or payload.user or payload.pusher)
end

local function tuleap_pusher(payload)
  local pusher = payload.pusher or payload.sender or payload.user or {}
  return {
    name = pusher.name or pusher.username or pusher.login or pusher.real_name or "",
    email = pusher.email or "",
  }
end

local function tuleap_project_created_event(payload)
  payload = payload or {}
  local project = translate_tuleap_project_webhook(payload)
  local sender = project.creator or {}
  return make_internal_event({
    event = "project",
    action = "created",
    provider = "tuleap",
    raw = payload,
    data = {
      action = "created",
      project = project,
      sender = sender,
    },
    timestamp = payload.created_at or payload.updated_at or "",
  })
end

local function tuleap_artifact_field(artifact, label)
  for _, field in ipairs((artifact or {}).values or {}) do
    if field.label == label then
      return field
    end
  end
  return nil
end

local function tuleap_artifact_field_value(artifact, label)
  local field = tuleap_artifact_field(artifact, label)
  if not field then
    return nil
  end
  if field.value ~= nil then
    return field.value
  end
  if field.values and field.values[1] then
    return field.values[1].label
  end
  return nil
end

local function tuleap_artifact_id(artifact)
  return tuleap_artifact_field_value(artifact, "Artifact ID") or (artifact or {}).id or 0
end

local function tuleap_artifact_state(artifact)
  local status = tostring(tuleap_artifact_field_value(artifact, "Status") or ""):lower()
  if status == "closed" or status == "done" or status == "resolved" then
    return "closed"
  end
  return "open"
end

local translate_tuleap_artifact = make_translator({
  id = computed(tuleap_artifact_id),
  node_id = const(""),
  number = computed(tuleap_artifact_id),
  title = computed(function(artifact)
    return tuleap_artifact_field_value(artifact, "Title") or ""
  end),
  body = computed(function(artifact)
    return tuleap_artifact_field_value(artifact, "Description") or ""
  end),
  state = computed(tuleap_artifact_state),
  user = computed(function(artifact)
    return translate_tuleap_user(artifact.submitted_by_details or {})
  end),
  assignees = computed(function()
    return {}
  end),
  labels = computed(function()
    return {}
  end),
  milestone = const(nil),
  created_at = field("submitted_on", { default = "" }),
  updated_at = computed(function(artifact)
    return tuleap_artifact_field_value(artifact, "Last Update On") or artifact.submitted_on or ""
  end),
  closed_at = const(nil),
  html_url = const(""),
})

local function tuleap_artifact_event(action)
  return function(payload)
    payload = payload or {}
    local artifact = payload.current or {}
    local sender = translate_tuleap_user(
      payload.user or artifact.last_modified_by or artifact.submitted_by_details
    )
    return make_internal_event({
      event = "issues",
      action = action,
      provider = "tuleap",
      raw = payload,
      data = {
        action = action,
        issue = translate_tuleap_artifact(artifact),
        repository = {},
        sender = sender,
      },
      timestamp = tuleap_artifact_field_value(artifact, "Last Update On")
        or artifact.submitted_on
        or "",
    })
  end
end

local TULEAP_ACTIONLESS_NORMALIZED_EVENTS = {
  create = true,
  delete = true,
  push = true,
}

local function tuleap_normalized_payload_without_envelope_fields(data)
  local payload = {}
  for k, v in pairs(data or {}) do
    if k ~= "sender" and k ~= "repository" then
      payload[k] = v
    end
  end
  return payload
end

local function translate_tuleap_normalized_webhook(internal_event, fields)
  local data = internal_event.data or {}
  fields = fields or {}
  return make_normalized_webhook_envelope(internal_event, {
    id = fields.id,
    type = fields.type
      or (
        TULEAP_ACTIONLESS_NORMALIZED_EVENTS[internal_event.event]
          and normalized_webhook_event_type(internal_event.event, "")
        or normalized_webhook_event_type(internal_event.event, internal_event.action)
      ),
    occurred_at = fields.occurred_at,
    actor = fields.actor or data.sender,
    repository = fields.repository or data.repository,
    payload = fields.payload or tuleap_normalized_payload_without_envelope_fields(data),
  })
end

local function translate_tuleap_github_webhook(internal_event, fields)
  return github_webhook_payload(internal_event, fields)
end

local function tuleap_git_event(payload)
  payload = payload or {}
  local raw_ref = payload.ref or ""
  local before = payload.before or ""
  local after = payload.after or ""
  local repository = translate_tuleap_repo(payload.repository)
  local sender = tuleap_sender(payload)

  if before == ZERO_SHA then
    return make_internal_event({
      event = "create",
      action = "create",
      provider = "tuleap",
      raw = payload,
      data = {
        ref = short_ref(raw_ref),
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
      provider = "tuleap",
      raw = payload,
      data = {
        ref = short_ref(raw_ref),
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

  local commits = translate_tuleap_commits(payload.commits)
  local head_commit = #commits > 0 and commits[#commits] or nil
  return make_internal_event({
    event = "push",
    action = "push",
    provider = "tuleap",
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
      pusher = tuleap_pusher(payload),
      repository = repository,
      sender = sender,
    },
    timestamp = payload.timestamp or (head_commit and head_commit.timestamp) or "",
  })
end

-- Returns limit and offset query params for Tuleap pagination.
local function pagination_params()
  local limit = GetParam("per_page") or "30"
  local offset = ((tonumber(GetParam("page")) or 1) - 1) * (tonumber(limit) or 30)
  return limit, offset
end

-- Returns the ?limit=...&offset=... query suffix for Tuleap pagination.
local function pagination_suffix()
  local limit, offset = pagination_params()
  return "?limit=" .. limit .. "&offset=" .. offset
end

-- Returns the Tuleap project git repos URL with pagination.
local function project_git_url(project_id)
  return base() .. "/projects/" .. project_id .. "/git" .. pagination_suffix()
end

-- Returns the Tuleap users URL with pagination and optional username query filter.
local function users_url(q)
  local url = base() .. "/users" .. pagination_suffix()
  if q and q ~= "" then
    url = url .. '&query={"username":"' .. q .. '"}'
  end
  return url
end

-- Returns the Tuleap projects URL with pagination and optional name query filter.
local function projects_url(q)
  local url = base() .. "/projects" .. pagination_suffix()
  if q and q ~= "" then
    url = url .. '&query={"name":"' .. q .. '"}'
  end
  return url
end

-- Look up a Tuleap project by shortname.
-- Returns the project table { id, shortname, ... } or nil on failure.
local function find_project(shortname)
  local url = base() .. '/projects?query={"shortname":"' .. shortname .. '"}&limit=1'
  local ok, status, _, body = fetch_json(url)
  if not ok or status ~= 200 then
    return nil
  end
  local projects = DecodeJson(body) or {}
  for _, p in ipairs(projects) do
    if p.shortname == shortname then
      return p
    end
  end
  return nil
end

local b = make_backend_builder()
b:rest("get_root", function()
  proxy_health_check(pcall(Fetch, base() .. "/projects?limit=1", auth()))
end)

-- GET /repos/{owner}/{repo}: owner = project shortname, repo = git repo name.
-- Two-step: find project by shortname, then list git repos and filter by name.
b:rest("get_repo", function(owner, repo_name)
  local project = find_project(owner)
  if not project then
    respond_json(404, { message = "Not Found" })
    return
  end
  local ok, status, _, body = fetch_json(project_git_url(project.id))
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local repos = DecodeJson(body) or {}
  for _, r in ipairs(repos) do
    if r.name == repo_name then
      respond_json(200, translate_tuleap_repo(r))
      return
    end
  end
  respond_json(404, { message = "Not Found" })
end)

-- GET /orgs/{org}/repos: org = project shortname; lists git repos in that project.
b:rest("get_org_repos", function(org)
  local project = find_project(org)
  if not project then
    respond_json(404, { message = "Not Found" })
    return
  end
  proxy_json(function(repos)
    local result = {}
    for _, r in ipairs(repos or {}) do
      result[#result + 1] = translate_tuleap_repo(r)
    end
    return result
  end, fetch_json(project_git_url(project.id)))
end)

-- GET /users/{username}: find Tuleap user by username.
b:rest("get_users_username", function(username)
  local url = base() .. '/users?query={"username":"' .. username .. '"}&limit=1'
  local ok, status, _, body = fetch_json(url)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local users = DecodeJson(body) or {}
  for _, u in ipairs(users) do
    if u.username == username then
      respond_json(200, translate_tuleap_user(u))
      return
    end
  end
  respond_json(404, { message = "Not Found" })
end)

-- GET /users: list Tuleap users (search by ?q= if given).
b:rest("get_users", function()
  local q = GetParam("q") or ""
  proxy_json(function(users)
    local result = {}
    for _, u in ipairs(users or {}) do
      result[#result + 1] = translate_tuleap_user(u)
    end
    return result
  end, fetch_json(users_url(q)))
end)

-- GET /search/repositories: search Tuleap projects by name.
b:rest("search_repositories", function()
  local q = GetParam("q") or ""
  proxy_json(function(projects)
    local items = {}
    for _, p in ipairs(projects or {}) do
      items[#items + 1] = {
        id = p.id or 0,
        name = p.shortname or "",
        full_name = p.shortname or "",
        description = p.description,
        private = p.access ~= "public",
        owner = {
          login = p.shortname or "",
          id = p.id or 0,
          type = "Organization",
        },
        html_url = config.base_url .. "/projects/" .. (p.shortname or ""),
      }
    end
    return { total_count = #items, incomplete_results = false, items = items }
  end, fetch_json(projects_url(q)))
end)

-- GET /search/users: search Tuleap users by username.
b:rest("search_users", function()
  local q = GetParam("q") or ""
  proxy_json(function(users)
    local items = {}
    for _, u in ipairs(users or {}) do
      items[#items + 1] = translate_tuleap_user(u)
    end
    return { total_count = #items, incomplete_results = false, items = items }
  end, fetch_json(users_url(q)))
end)

b:webhook("project_create", tuleap_project_created_event)
b:webhook("git_push", tuleap_git_event)
b:webhook("artifact_create", tuleap_artifact_event("opened"))
b:webhook("artifact_update", tuleap_artifact_event("edited"))

for _, event in ipairs({ "project", "push", "create", "delete", "issues" }) do
  b:webhook_translator(event, translate_tuleap_normalized_webhook)
  b:webhook_github_translator(event, translate_tuleap_github_webhook)
end

b:build()
