-- Gitblit backend handler overrides.
-- Uses Gitblit HTTP/JSON RPC at /rpc with ?req= dispatch.
-- Repository names follow the pattern "owner/repo.git".
if config.base_url == "" then
  config.base_url = "https://try.gitblit.com"
end

local rpc = function()
  return config.base_url .. "/rpc"
end

local auth = function()
  return make_fetch_opts("basic")
end

local function fetch_rpc(req, extra)
  local url = rpc() .. "?req=" .. req .. (extra or "")
  return pcall(Fetch, url, auth())
end

-- Split a Gitblit repo name like "owner/repo.git" into (owner, repo).
local function split_name(name)
  local owner, repo = (name or ""):match("^([^/]+)/(.+)%.git$")
  if not owner then
    owner, repo = (name or ""):match("^([^/]+)/(.+)$")
  end
  return owner or "", repo or (name or ""):gsub("%.git$", "")
end

local function gitblit_repo_owner(r)
  local owner = split_name(r.name or "")
  return owner
end

local function gitblit_repo_name(r)
  local _, repo_name = split_name(r.name or "")
  return repo_name
end

local function gitblit_repo_default_branch(r)
  local branch = r.HEAD and r.HEAD:match("^refs/heads/(.+)") or r.defaultBranch or "main"
  return branch
end

local translate_repo_owner = make_translator({
  login = computed(gitblit_repo_owner),
  id = const(0),
  node_id = const(""),
  avatar_url = const(""),
  url = const(""),
  html_url = computed(function(r)
    return config.base_url .. "/summary/" .. gitblit_repo_owner(r)
  end),
  type = const("User"),
})

-- Translate a Gitblit repository object to GitHub format.
local translate_repo = make_translator({
  id = const(0),
  node_id = const(""),
  name = computed(gitblit_repo_name),
  full_name = computed(function(r)
    return gitblit_repo_owner(r) .. "/" .. gitblit_repo_name(r)
  end),
  private = const(false),
  owner = computed(function(r)
    return translate_repo_owner(r)
  end),
  html_url = computed(function(r)
    return config.base_url .. "/summary/" .. (r.name or "")
  end),
  description = "description",
  fork = const(false),
  url = const(""),
  clone_url = computed(function(r)
    return config.base_url .. "/r/" .. (r.name or "")
  end),
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
  default_branch = computed(gitblit_repo_default_branch),
  visibility = const("public"),
  forks = const(0),
  open_issues = const(0),
  watchers = const(0),
  created_at = "lastChange",
  updated_at = "lastChange",
  pushed_at = "lastChange",
})

-- Translate a Gitblit user object to GitHub format.
local translate_user = make_translator({
  login = field("name", { default = "" }),
  id = const(0),
  node_id = const(""),
  avatar_url = const(""),
  html_url = computed(function(u)
    return config.base_url .. "/user/" .. (u.name or "")
  end),
  type = const("User"),
  site_admin = const(false),
  name = computed(function(u)
    return u.displayName or u.name or ""
  end),
  email = field("emailAddress", { default = "" }),
  blog = const(""),
})

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

local function gitblit_commit_author(c)
  return c.author or {}
end

local translate_push_commit_author = make_translator({
  name = field("name", { default = "" }),
  email = field("email", { default = "" }),
  username = const(""),
})

local translate_push_commit = make_translator({
  id = field("id", { default = "" }),
  message = field("message", { default = "" }),
  timestamp = field("timestamp", { default = "" }),
  url = field("url", { default = "" }),
  author = computed(function(c)
    return translate_push_commit_author(gitblit_commit_author(c))
  end),
  committer = computed(function(c)
    return translate_push_commit_author(gitblit_commit_author(c))
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

-- Return all repos from LIST_REPOSITORIES whose name starts with prefix.
local function list_repos_by_prefix(prefix)
  local ok, status, _, body = fetch_rpc("LIST_REPOSITORIES")
  if not ok then
    return nil, 503
  end
  if status ~= 200 then
    return nil, status
  end
  local all = DecodeJson(body) or {}
  local result = {}
  for name, r in pairs(all) do
    if prefix == "" or name:sub(1, #prefix) == prefix then
      r.name = r.name or name
      result[#result + 1] = translate_repo(r)
    end
  end
  return result, 200
end

local b = make_backend_builder()
b:rest("get_root", function()
  proxy_health_check(pcall(Fetch, rpc() .. "?req=LIST_REPOSITORIES", auth()))
end)

b:rest("get_repo", function(owner, repo_name)
  local gitblit_name = owner .. "/" .. repo_name .. ".git"
  local ok, status, _, body = fetch_rpc("GET_REPOSITORY", "&name=" .. gitblit_name)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local r = DecodeJson(body) or {}
  if not r.name then
    respond_json(404, { message = "Not Found" })
    return
  end
  respond_json(200, translate_repo(r))
end)

b:rest("get_org_repos", function(org)
  local repos, status = list_repos_by_prefix(org .. "/")
  if not repos then
    respond_json(status, {})
    return
  end
  respond_json(200, repos)
end)

b:rest("get_users_repos", function(username)
  local repos, status = list_repos_by_prefix(username .. "/")
  if not repos then
    respond_json(status, {})
    return
  end
  respond_json(200, repos)
end)

b:rest("get_repositories", function()
  local repos, status = list_repos_by_prefix("")
  if not repos then
    respond_json(status, {})
    return
  end
  respond_json(200, repos)
end)

b:rest("get_users_username", function(username)
  local ok, status, _, body = fetch_rpc("GET_USER", "&name=" .. username)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local u = DecodeJson(body) or {}
  if not u.name then
    respond_json(404, { message = "Not Found" })
    return
  end
  respond_json(200, translate_user(u))
end)

b:rest("get_users", function()
  local ok, status, _, body = fetch_rpc("LIST_USERS")
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local users = DecodeJson(body) or {}
  local result = {}
  for _, u in ipairs(users) do
    result[#result + 1] = translate_user(u)
  end
  respond_json(200, result)
end)

b:rest("search_repositories", function()
  local q = (GetParam("q") or ""):lower()
  local repos, status = list_repos_by_prefix("")
  if not repos then
    respond_json(status, {})
    return
  end
  local items = repos
  if q ~= "" then
    items = {}
    for _, r in ipairs(repos) do
      if
        (r.name or ""):lower():find(q, 1, true) or (r.full_name or ""):lower():find(q, 1, true)
      then
        items[#items + 1] = r
      end
    end
  end
  respond_json(200, { total_count = #items, incomplete_results = false, items = items })
end)

b:rest("search_users", function()
  local q = (GetParam("q") or ""):lower()
  local ok, status, _, body = fetch_rpc("LIST_USERS")
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local users = DecodeJson(body) or {}
  local items = {}
  for _, u in ipairs(users) do
    if q == "" or (u.name or ""):lower():find(q, 1, true) then
      items[#items + 1] = translate_user(u)
    end
  end
  respond_json(200, { total_count = #items, incomplete_results = false, items = items })
end)

-- Gitblit post-receive webhooks carry one or more ref update commands in the
-- body.  Confusio normalizes the first successful command into the matching
-- GitHub ref event family: create, delete, or push.
b:webhook("post-receive", function(payload)
  local command = nil
  for _, c in ipairs(payload.commands or {}) do
    if not command and (c.result == nil or c.result == "OK") then
      command = c
    end
  end
  if not command then
    return nil, "No successful Gitblit ref command"
  end

  local repo = translate_repo(payload.repository or {})
  local sender = translate_user(payload.user or {})
  local before = command.oldId or ""
  local after = command.newId or ""
  local raw_ref = command.refName or ""
  local kind = ref_type(raw_ref)
  local name = ref_name(raw_ref)
  local command_type = command.type or ""

  if command_type == "CREATE" or before == ZERO_SHA then
    return make_internal_event({
      event = "create",
      action = "create",
      provider = "gitblit",
      raw = payload,
      data = {
        ref = name,
        ref_type = kind,
        master_branch = (payload.repository or {}).defaultBranch or "",
        description = (payload.repository or {}).description,
        pusher_type = "user",
        repository = repo,
        sender = sender,
      },
      timestamp = (payload.repository or {}).lastChange or "",
    })
  end

  if command_type == "DELETE" or after == ZERO_SHA then
    return make_internal_event({
      event = "delete",
      action = "delete",
      provider = "gitblit",
      raw = payload,
      data = {
        ref = name,
        ref_type = kind,
        master_branch = (payload.repository or {}).defaultBranch or "",
        description = (payload.repository or {}).description,
        pusher_type = "user",
        repository = repo,
        sender = sender,
      },
      timestamp = (payload.repository or {}).lastChange or "",
    })
  end

  local commits = {}
  for _, c in ipairs(command.commits or {}) do
    commits[#commits + 1] = translate_push_commit(c)
  end
  local head_commit = #commits > 0 and commits[#commits] or nil
  local user = payload.user or {}
  return make_internal_event({
    event = "push",
    action = "push",
    provider = "gitblit",
    raw = payload,
    data = {
      ref = raw_ref,
      before = before,
      after = after,
      created = false,
      deleted = false,
      forced = false,
      compare = "",
      commits = commits,
      head_commit = head_commit,
      pusher = {
        name = user.displayName or user.name or "",
        email = user.emailAddress or "",
      },
      repository = repo,
      sender = sender,
    },
    timestamp = head_commit and head_commit.timestamp
      or (payload.repository or {}).lastChange
      or "",
  })
end)

local function normalized_payload_without_envelope_fields(data)
  local payload = {}
  for k, v in pairs(data or {}) do
    if k ~= "sender" and k ~= "repository" then
      payload[k] = v
    end
  end
  return payload
end

local function translate_gitblit_normalized_webhook(internal_event, fields)
  local data = internal_event.data or {}
  fields = fields or {}
  return make_normalized_webhook_envelope(internal_event, {
    id = fields.id,
    type = fields.type or normalized_webhook_event_type(internal_event.event, ""),
    occurred_at = fields.occurred_at,
    actor = fields.actor or data.sender,
    repository = fields.repository or data.repository,
    payload = fields.payload or normalized_payload_without_envelope_fields(data),
  })
end

local function translate_gitblit_github_webhook(internal_event, fields)
  return github_webhook_payload(internal_event, fields)
end

for _, event in ipairs({ "push", "create", "delete" }) do
  b:webhook_translator(event, translate_gitblit_normalized_webhook)
  b:webhook_github_translator(event, translate_gitblit_github_webhook)
end

b:build()
