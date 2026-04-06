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

local function fetch_json(url, method, body)
  local opts = auth()
  if method ~= nil and method ~= "GET" then
    opts = opts or {}
    opts.method = method
    if body then
      opts.body = body
      opts.headers = opts.headers or {}
      opts.headers["Content-Type"] = "application/json"
    end
  end
  return pcall(Fetch, url, opts)
end

-- Translate a Tuleap git repository object to GitHub format.
local function translate_tuleap_repo(r)
  if not r then
    return {}
  end
  local project = r.project or {}
  local shortname = project.shortname or ""
  return {
    id = r.id or 0,
    node_id = "",
    name = r.name or "",
    full_name = shortname .. "/" .. (r.name or ""),
    private = false,
    owner = {
      login = shortname,
      id = project.id or 0,
      node_id = "",
      avatar_url = "",
      url = "",
      html_url = config.base_url .. "/projects/" .. shortname,
      type = "Organization",
    },
    html_url = r.http_url or "",
    description = r.description,
    fork = false,
    url = "",
    clone_url = r.clone_http_url or "",
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
    default_branch = r.default_branch or "main",
    visibility = "public",
    forks = 0,
    open_issues = 0,
    watchers = 0,
    created_at = nil,
    updated_at = nil,
    pushed_at = nil,
  }
end

-- Translate a Tuleap user object to GitHub format.
local function translate_tuleap_user(u)
  if not u then
    return {}
  end
  return {
    login = u.username or "",
    id = u.id or 0,
    node_id = "",
    avatar_url = u.avatar_url or "",
    html_url = config.base_url .. "/users/" .. (u.username or ""),
    type = "User",
    site_admin = false,
    name = u.real_name or u.display_name or u.username or "",
    email = "",
    blog = "",
  }
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

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, base() .. "/projects?limit=1", auth())
    if ok and status == 200 then
      respond_json(200, "OK", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- GET /repos/{owner}/{repo}: owner = project shortname, repo = git repo name.
  -- Two-step: find project by shortname, then list git repos and filter by name.
  get_repo = function(owner, repo_name)
    local project = find_project(owner)
    if not project then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    local ok, status, _, body = fetch_json(project_git_url(project.id))
    if not ok then
      respond_json(503, "Service Unavailable", {})
      return
    end
    if status ~= 200 then
      respond_json(status, "Error", {})
      return
    end
    local repos = DecodeJson(body) or {}
    for _, r in ipairs(repos) do
      if r.name == repo_name then
        respond_json(200, "OK", translate_tuleap_repo(r))
        return
      end
    end
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  -- GET /orgs/{org}/repos: org = project shortname; lists git repos in that project.
  get_org_repos = function(org)
    local project = find_project(org)
    if not project then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    proxy_json(function(repos)
      local result = {}
      for _, r in ipairs(repos or {}) do
        result[#result + 1] = translate_tuleap_repo(r)
      end
      return result
    end, fetch_json(project_git_url(project.id)))
  end,

  -- GET /users/{username}: find Tuleap user by username.
  get_users_username = function(username)
    local url = base() .. '/users?query={"username":"' .. username .. '"}&limit=1'
    local ok, status, _, body = fetch_json(url)
    if not ok then
      respond_json(503, "Service Unavailable", {})
      return
    end
    if status ~= 200 then
      respond_json(status, "Error", {})
      return
    end
    local users = DecodeJson(body) or {}
    for _, u in ipairs(users) do
      if u.username == username then
        respond_json(200, "OK", translate_tuleap_user(u))
        return
      end
    end
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  -- GET /users: list Tuleap users (search by ?q= if given).
  get_users = function()
    local q = GetParam("q") or ""
    proxy_json(function(users)
      local result = {}
      for _, u in ipairs(users or {}) do
        result[#result + 1] = translate_tuleap_user(u)
      end
      return result
    end, fetch_json(users_url(q)))
  end,

  -- GET /search/repositories: search Tuleap projects by name.
  search_repositories = function()
    local q = GetParam("q") or ""
    local url = base() .. "/projects" .. pagination_suffix()
    if q ~= "" then
      url = url .. '&query={"name":"' .. q .. '"}'
    end
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
    end, fetch_json(url))
  end,

  -- GET /search/users: search Tuleap users by username.
  search_users = function()
    local q = GetParam("q") or ""
    proxy_json(function(users)
      local items = {}
      for _, u in ipairs(users or {}) do
        items[#items + 1] = translate_tuleap_user(u)
      end
      return { total_count = #items, incomplete_results = false, items = items }
    end, fetch_json(users_url(q)))
  end,
}
