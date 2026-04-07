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

-- Translate a Gitblit repository object to GitHub format.
local function translate_repo(r)
  if not r then
    return {}
  end
  local owner, repo_name = split_name(r.name or "")
  local branch = r.HEAD and r.HEAD:match("^refs/heads/(.+)") or r.defaultBranch or "main"
  return {
    id = 0,
    node_id = "",
    name = repo_name,
    full_name = owner .. "/" .. repo_name,
    private = false,
    owner = {
      login = owner,
      id = 0,
      node_id = "",
      avatar_url = "",
      url = "",
      html_url = config.base_url .. "/summary/" .. owner,
      type = "User",
    },
    html_url = config.base_url .. "/summary/" .. (r.name or ""),
    description = r.description,
    fork = false,
    url = "",
    clone_url = config.base_url .. "/r/" .. (r.name or ""),
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
    default_branch = branch,
    visibility = "public",
    forks = 0,
    open_issues = 0,
    watchers = 0,
    created_at = r.lastChange,
    updated_at = r.lastChange,
    pushed_at = r.lastChange,
  }
end

-- Translate a Gitblit user object to GitHub format.
local function translate_user(u)
  if not u then
    return {}
  end
  return {
    login = u.name or "",
    id = 0,
    node_id = "",
    avatar_url = "",
    html_url = config.base_url .. "/user/" .. (u.name or ""),
    type = "User",
    site_admin = false,
    name = u.displayName or u.name or "",
    email = u.emailAddress or "",
    blog = "",
  }
end

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

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, rpc() .. "?req=LIST_REPOSITORIES", auth())
    if ok and status == 200 then
      respond_json(200, {})
    else
      respond_json(503, {})
    end
  end,

  get_repo = function(owner, repo_name)
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
  end,

  get_org_repos = function(org)
    local repos, status = list_repos_by_prefix(org .. "/")
    if not repos then
      respond_json(status, {})
      return
    end
    respond_json(200, repos)
  end,

  get_users_repos = function(username)
    local repos, status = list_repos_by_prefix(username .. "/")
    if not repos then
      respond_json(status, {})
      return
    end
    respond_json(200, repos)
  end,

  get_repositories = function()
    local repos, status = list_repos_by_prefix("")
    if not repos then
      respond_json(status, {})
      return
    end
    respond_json(200, repos)
  end,

  get_users_username = function(username)
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
  end,

  get_users = function()
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
  end,

  search_repositories = function()
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
  end,

  search_users = function()
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
  end,

  -- Checks — Gitblit has no native CI build system; all check endpoints are stubs.

  -- POST /repos/{owner}/{repo}/check-runs
  post_check_runs = function(_owner, _repo_name)
    local req = DecodeJson(GetBody() or "{}")
    respond_json(201, {
      id = 0,
      node_id = "",
      head_sha = req.head_sha or "",
      name = req.name or "",
      status = req.status or "queued",
      conclusion = req.conclusion,
      started_at = nil,
      completed_at = nil,
      output = {
        title = (req.output and req.output.title) or "",
        summary = (req.output and req.output.summary) or "",
        text = "",
        annotations_count = 0,
        annotations_url = "",
      },
      url = "",
      html_url = "",
      details_url = req.details_url or "",
    })
  end,

  -- GET /repos/{owner}/{repo}/check-runs/{check_run_id}
  get_check_run = function(_owner, _repo_name, check_run_id)
    respond_json(200, {
      id = tonumber(check_run_id) or 0,
      node_id = "",
      head_sha = "",
      name = "",
      status = "completed",
      conclusion = "success",
      started_at = nil,
      completed_at = nil,
      output = { title = "", summary = "", text = "", annotations_count = 0, annotations_url = "" },
      url = "",
      html_url = "",
      details_url = "",
    })
  end,

  -- PATCH /repos/{owner}/{repo}/check-runs/{check_run_id}
  patch_check_run = function(_owner, _repo_name, check_run_id)
    respond_json(200, {
      id = tonumber(check_run_id) or 0,
      node_id = "",
      head_sha = "",
      name = "",
      status = "completed",
      conclusion = "success",
      started_at = nil,
      completed_at = nil,
      output = { title = "", summary = "", text = "", annotations_count = 0, annotations_url = "" },
      url = "",
      html_url = "",
      details_url = "",
    })
  end,

  -- GET /repos/{owner}/{repo}/check-runs/{check_run_id}/annotations
  get_check_run_annotations = function(_owner, _repo_name, _check_run_id)
    set_preamble()
    Write("[]")
  end,

  -- POST /repos/{owner}/{repo}/check-runs/{check_run_id}/rerequest
  post_check_run_rerequest = function(_owner, _repo_name, _check_run_id)
    respond_json(201, {})
  end,

  -- GET /repos/{owner}/{repo}/commits/{ref}/check-runs — no CI system; always empty
  get_commit_check_runs = function(_owner, _repo_name, _ref)
    respond_json(200, { total_count = 0, check_runs = {} })
  end,

  -- Check Suites — no Gitblit equivalent; all are stubs -------------------------

  -- POST /repos/{owner}/{repo}/check-suites
  post_check_suites = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
    respond_json(201, {
      id = 0,
      node_id = "",
      head_sha = req.head_sha or "",
      status = "completed",
      conclusion = "success",
      app = { id = 0, slug = "", name = "" },
      repository = { full_name = owner .. "/" .. repo_name },
    })
  end,

  -- PATCH /repos/{owner}/{repo}/check-suites/preferences
  patch_check_suites_preferences = function(_owner, _repo_name) -- luacheck: ignore 212
    local req = DecodeJson(GetBody() or "{}") or {}
    respond_json(200, {
      preferences = req.auto_trigger_checks or {},
    })
  end,

  -- GET /repos/{owner}/{repo}/check-suites/{check_suite_id}
  get_check_suite = function(owner, repo_name, check_suite_id)
    respond_json(200, {
      id = tonumber(check_suite_id) or 0,
      node_id = "",
      head_sha = "",
      status = "completed",
      conclusion = "success",
      app = { id = 0, slug = "", name = "" },
      repository = { full_name = owner .. "/" .. repo_name },
    })
  end,

  -- GET /repos/{owner}/{repo}/check-suites/{check_suite_id}/check-runs
  get_check_suite_check_runs = function(_owner, _repo_name, _check_suite_id)
    respond_json(200, { total_count = 0, check_runs = {} })
  end,

  -- POST /repos/{owner}/{repo}/check-suites/{check_suite_id}/rerequest
  post_check_suite_rerequest = function(_owner, _repo_name, _check_suite_id)
    respond_json(201, {})
  end,

  -- GET /repos/{owner}/{repo}/commits/{ref}/check-suites
  get_commit_check_suites = function(_owner, _repo_name, _ref)
    respond_json(200, { total_count = 0, check_suites = {} })
  end,
}

-- Code scanning: Gitblit has no native code scanning API.
-- List endpoints return empty collections; per-resource endpoints return 501.
local _b = backend_impl

_b.list_org_code_scanning_alerts = function(_org)
  respond_json(200, {})
end

_b.list_repo_code_scanning_alerts = function(_owner, _repo)
  respond_json(200, {})
end

_b.list_code_scanning_alert_instances = function(_owner, _repo, _alert_number)
  respond_json(200, {})
end

_b.list_code_scanning_analyses = function(_owner, _repo)
  respond_json(200, {})
end
