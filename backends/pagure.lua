-- Pagure backend handler overrides.
-- Uses Pagure REST API at /api/0/.
-- Repos are addressed as /api/0/{namespace}/{repo} (owner = namespace/username).
if config.base_url == "" then
  config.base_url = "https://pagure.io"
end

local base = function()
  return config.base_url .. "/api/0"
end
local auth = function()
  return make_fetch_opts("token")
end
local PAGES = { per_page = "per_page", page = "page" }

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

-- Map a Pagure project object to GitHub repo format.
local function translate_pagure_repo(r)
  if not r then
    return {}
  end
  local user = r.user or {}
  local ns = r.namespace or ""
  local owner_login = ns ~= "" and ns or user.name or ""
  return {
    id = r.id or 0,
    node_id = "",
    name = r.name,
    full_name = r.fullname or (owner_login .. "/" .. (r.name or "")),
    private = r.private or false,
    owner = {
      login = owner_login,
      id = 0,
      node_id = "",
      avatar_url = "",
      url = "",
      html_url = config.base_url .. "/" .. (user.url_path or user.name or ""),
      type = ns ~= "" and "Organization" or "User",
    },
    html_url = config.base_url .. "/" .. (r.url_path or ""),
    description = r.description,
    fork = r.parent ~= nil,
    url = "",
    clone_url = r.full_url or "",
    homepage = r.url or "",
    size = 0,
    stargazers_count = r.stars or 0,
    watchers_count = 0,
    language = nil,
    has_issues = true,
    has_wiki = r.settings and r.settings.wiki_enabled or false,
    forks_count = r.forks_count or 0,
    archived = r.close_status ~= nil and r.close_status ~= "",
    disabled = false,
    open_issues_count = 0,
    default_branch = r.default_branch or "main",
    visibility = (r.private or false) and "private" or "public",
    forks = r.forks_count or 0,
    open_issues = 0,
    watchers = 0,
    created_at = r.date_created,
    updated_at = r.date_modified,
    pushed_at = r.date_modified,
  }
end

-- Translate a Pagure branch name to GitHub format.
-- Pagure branch list returns only names, no commit SHAs.
local function translate_pagure_branch(name)
  return { name = name, commit = { sha = "", url = "" }, protected = false }
end

-- Translate a Pagure commit object to GitHub format.
-- Pagure: { id, message, date, date_utc, author: { name, email } }
local proxy_handler         = make_proxy_handler(fetch_json)
local proxy_handler_created = make_proxy_handler(fetch_json, proxy_json_created)

-- Translate a Pagure user to GitHub format.
local function translate_pagure_user(u)
  if not u then return {} end
  return {
    login      = u.name or u.username or "",
    id         = 0,
    node_id    = "",
    avatar_url = u.avatar_url or "",
    html_url   = config.base_url .. "/" .. (u.url_path or u.name or ""),
    type       = "User",
    site_admin = false,
    name       = u.fullname or u.name or "",
  }
end

-- Translate a Pagure issue tag (string) to a GitHub label object.
local function translate_pagure_tag(tag)
  return { id = 0, node_id = "", url = "", name = tag or "", color = "", description = "", default = false }
end

-- Translate a Pagure issue to GitHub format.
-- Pagure states: "Open", "Closed"
-- Pagure dates: Unix timestamps as strings
local function translate_pagure_issue(i)
  if not i then return {} end
  local state = (i.status == "Open") and "open" or "closed"
  local labels = {}
  for _, tag in ipairs(i.tags or {}) do
    labels[#labels + 1] = translate_pagure_tag(tag)
  end
  local assignees = {}
  if i.assignee then assignees[1] = translate_pagure_user(i.assignee) end
  local user = translate_pagure_user(i.user)
  -- Pagure date_created is a Unix timestamp string; convert to ISO 8601
  local function ts(v)
    if not v then return "" end
    -- Try to return as-is if it looks like a timestamp (digits only)
    return tostring(v)
  end
  return {
    id         = i.id or 0,
    number     = i.id or 0,
    title      = i.title or "",
    body       = i.content or "",
    state      = state,
    user       = user,
    assignees  = assignees,
    labels     = labels,
    milestone  = nil,
    created_at = ts(i.date_created),
    updated_at = ts(i.last_updated),
    closed_at  = nil,
    html_url   = config.base_url .. "/" .. (i.full_url or ""),
  }
end

-- Translate a Pagure comment to GitHub format.
local function translate_pagure_comment(c)
  if not c then return {} end
  return {
    id         = c.id or 0,
    body       = c.comment or "",
    user       = translate_pagure_user(c.user),
    created_at = tostring(c.date_created or ""),
    updated_at = tostring(c.date_created or ""),
    html_url   = "",
  }
end

local function translate_pagure_commit(c)
  if not c then
    return {}
  end
  local author = c.author or {}
  return {
    sha = c.id or "",
    commit = {
      message = c.message or "",
      author = { name = author.name or "", email = author.email or "", date = c.date_utc or "" },
      committer = { name = author.name or "", email = author.email or "", date = c.date_utc or "" },
    },
    author = { login = author.name or "", id = 0, avatar_url = "" },
    committer = { login = author.name or "", id = 0, avatar_url = "" },
  }
end

local function translate_pagure_issues(data)
  local issues = data.issues or {}
  for i, iss in ipairs(issues) do issues[i] = translate_pagure_issue(iss) end
  return issues
end

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, base() .. "/version", auth())
    if ok and status == 200 then
      respond_json(200, "OK", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  get_repo = proxy_handler(translate_pagure_repo, function(owner, repo_name)
    return base() .. "/" .. owner .. "/" .. repo_name
  end),

  patch_repo = function(owner, repo_name)
    -- Pagure: update project description via POST /api/0/{owner}/{repo}/modify
    local url = base() .. "/" .. owner .. "/" .. repo_name .. "/modify"
    local req = DecodeJson(GetBody() or "{}")
    local pg = {}
    if req.description then
      pg.description = req.description
    end
    if req.private ~= nil then
      pg.private = req.private
    end
    -- Pagure /modify returns { "repo": {...} }
    proxy_json(function(resp)
      return translate_pagure_repo(resp.repo or resp)
    end, fetch_json(url, "POST", EncodeJson(pg)))
  end,

  delete_repo = function(owner, repo_name)
    -- Pagure: delete project via POST /api/0/{owner}/{repo}/delete
    local url = base() .. "/" .. owner .. "/" .. repo_name .. "/delete"
    local ok, status = fetch_json(url, "POST", "{}")
    if ok and (status == 200 or status == 204) then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  get_user_repos = function()
    -- Pagure: /api/0/projects?author={user} — need to know the authenticated user first
    local ok, status, _, ubody = fetch_json(base() .. "/-/whoami")
    if not ok or status ~= 200 then
      respond_json(503, "Service Unavailable", {})
      return
    end
    local me = DecodeJson(ubody)
    local username = me.username or me.name or ""
    proxy_json(function(data)
      local projects = data.projects or {}
      for i, p in ipairs(projects) do
        projects[i] = translate_pagure_repo(p)
      end
      return projects
    end, fetch_json(append_page_params(base() .. "/user/" .. username .. "/projects", PAGES)))
  end,

  post_user_repos = function()
    -- Pagure: create project via POST /api/0/new
    local req = DecodeJson(GetBody() or "{}")
    local pg = {
      name = req.name,
      description = req.description or "",
      private = req.private or false,
    }
    proxy_json_created(function(resp)
      return translate_pagure_repo(resp.project or resp)
    end, fetch_json(base() .. "/new", "POST", EncodeJson(pg)))
  end,

  get_org_repos = proxy_handler(function(data)
    local projects = data.projects or {}
    for i, p in ipairs(projects) do
      projects[i] = translate_pagure_repo(p)
    end
    return projects
  end, function(namespace)
    return append_page_params(base() .. "/projects?namespace=" .. namespace, PAGES)
  end),

  post_org_repos = function(namespace)
    -- Pagure: create project with namespace
    local req = DecodeJson(GetBody() or "{}")
    local pg = {
      name = req.name,
      description = req.description or "",
      private = req.private or false,
      namespace = namespace,
    }
    proxy_json_created(function(resp)
      return translate_pagure_repo(resp.project or resp)
    end, fetch_json(base() .. "/new", "POST", EncodeJson(pg)))
  end,

  get_repo_topics = proxy_handler(function(r)
    return { names = r.tags or {} }
  end, function(owner, repo_name)
    return base() .. "/" .. owner .. "/" .. repo_name
  end),

  put_repo_topics = function(owner, repo_name)
    -- Pagure: set tags via POST /api/0/{owner}/{repo}/modify with tags field
    local url = base() .. "/" .. owner .. "/" .. repo_name .. "/modify"
    local req = DecodeJson(GetBody() or "{}")
    proxy_json(function(resp)
      local r = resp.repo or resp
      return { names = r.tags or {} }
    end, fetch_json(url, "POST", EncodeJson({ tags = req.names or {} })))
  end,

  -- Branches ------------------------------------------------------------------
  -- Pagure: GET /api/0/{owner}/{repo}/git/branches → { branches: ["main", ...] }
  -- No commit SHAs in branch list response.

  get_repo_branches = proxy_handler(function(data)
    local branches = {}
    for _, name in ipairs(data.branches or {}) do
      branches[#branches + 1] = translate_pagure_branch(name)
    end
    return branches
  end, function(owner, repo_name)
    return base() .. "/" .. owner .. "/" .. repo_name .. "/git/branches"
  end),

  -- Commits -------------------------------------------------------------------
  -- Pagure: GET /api/0/{owner}/{repo}/commits?branch={branch}&limit={n}&start={offset}

  get_repo_commits = function(owner, repo_name)
    local branch = GetParam("sha") or GetParam("branch") or ""
    local limit = GetParam("per_page") or "30"
    local page = tonumber(GetParam("page")) or 1
    local limit_n = tonumber(limit) or 30
    local start = (page - 1) * limit_n
    local url = base()
      .. "/"
      .. owner
      .. "/"
      .. repo_name
      .. "/commits?limit="
      .. limit
      .. "&start="
      .. start
    if branch ~= "" then
      url = url .. "&branch=" .. branch
    end
    proxy_json(function(data)
      local commits = data.commits or {}
      for i, c in ipairs(commits) do
        commits[i] = translate_pagure_commit(c)
      end
      return commits
    end, fetch_json(url))
  end,

  -- Tags ----------------------------------------------------------------------
  -- Pagure returns { "tags": ["v1.0", ...] } — just tag names, no commit info

  get_repo_tags = proxy_handler(function(data)
    local tags = {}
    for _, name in ipairs(data.tags or {}) do
      tags[#tags + 1] = { name = name, commit = { sha = "", url = "" } }
    end
    return tags
  end, function(owner, repo_name)
    return base() .. "/" .. owner .. "/" .. repo_name .. "/git/tags"
  end),

  -- Contents ------------------------------------------------------------------
  -- Pagure: GET /api/0/{owner}/{repo}/raw/{path}?ref={ref} — returns raw bytes.
  -- We base64-encode and return a GitHub-shaped content object.

  get_repo_readme = function(owner, repo_name)
    local ref = GetParam("ref") or ""
    -- Try common README filenames in order.
    local candidates = { "README.md", "README", "readme.md", "README.rst" }
    for _, fname in ipairs(candidates) do
      local url = base() .. "/" .. owner .. "/" .. repo_name .. "/raw/" .. fname
      if ref ~= "" then
        url = url .. "?ref=" .. ref
      end
      local ok, status, _, body = fetch_json(url)
      if ok and status == 200 then
        respond_json(200, "OK", {
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
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  get_repo_content = function(owner, repo_name, path)
    local ref = GetParam("ref") or ""
    local url = base() .. "/" .. owner .. "/" .. repo_name .. "/raw/" .. path
    if ref ~= "" then
      url = url .. "?ref=" .. ref
    end
    local ok, status, _, body = fetch_json(url)
    if ok and status == 200 then
      respond_json(200, "OK", {
        type = "file",
        name = path:match("[^/]+$") or path,
        path = path,
        sha = "",
        size = #body,
        encoding = "base64",
        content = EncodeBase64(body),
      })
    elseif ok then
      respond_json(status, "Error", { message = "Error" })
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- Forks ---------------------------------------------------------------------
  -- Pagure: POST /api/0/fork with form body

  get_repo_forks = proxy_handler(function(data)
    local forks = {}
    for _, f in ipairs(data.forks or {}) do
      forks[#forks + 1] = translate_pagure_repo(f)
    end
    return forks
  end, function(owner, repo_name)
    return base() .. "/" .. owner .. "/" .. repo_name
  end),

  post_repo_forks = function(owner, repo_name)
    -- Pagure fork endpoint expects form-encoded body
    local req = DecodeJson(GetBody() or "{}")
    local fopts = auth() or {}
    fopts.method = "POST"
    fopts.body = "repo=" .. repo_name .. "&namespace=" .. owner
    if req.organization then
      fopts.body = fopts.body .. "&username=" .. req.organization
    end
    fopts.headers = fopts.headers or {}
    fopts.headers["Content-Type"] = "application/x-www-form-urlencoded"
    proxy_json_created(function(resp)
      return translate_pagure_repo(resp.project or resp)
    end, pcall(Fetch, base() .. "/fork", fopts))
  end,

  -- Users ---------------------------------------------------------------------

  -- GET /user — two-step: whoami then full profile
  get_user = function()
    local ok, status, _, ubody = fetch_json(base() .. "/-/whoami")
    if not ok or status ~= 200 then
      respond_json(503, "Service Unavailable", {})
      return
    end
    local me = DecodeJson(ubody) or {}
    local username = me.username or ""
    if username == "" then
      respond_json(503, "Service Unavailable", {})
      return
    end
    proxy_json(function(data)
      local u = data.user or data
      return {
        login = u.username or "",
        id = 0,
        node_id = "",
        avatar_url = u.avatar_url or "",
        html_url = config.base_url .. "/" .. (u.username or ""),
        type = "User",
        site_admin = false,
        name = u.fullname or "",
        email = (u.emails and u.emails[1]) or "",
      }
    end, fetch_json(base() .. "/user/" .. username))
  end,

  -- GET /users/{username}
  get_users_username = proxy_handler(function(data)
    local u = data.user or data
    return {
      login = u.username or "",
      id = 0,
      node_id = "",
      avatar_url = u.avatar_url or "",
      html_url = config.base_url .. "/" .. (u.username or ""),
      type = "User",
      site_admin = false,
      name = u.fullname or "",
    }
  end, function(username)
    return base() .. "/user/" .. username
  end),

  -- GET /users
  get_users = proxy_handler(function(data)
    local users = {}
    for _, name in ipairs(data.users or {}) do
      users[#users + 1] = {
        login = name,
        id = 0,
        node_id = "",
        avatar_url = "",
        html_url = config.base_url .. "/" .. name,
        type = "User",
        site_admin = false,
      }
    end
    return users
  end, function()
    return base() .. "/users"
  end),

  -- Users' repos --------------------------------------------------------------

  get_users_repos = proxy_handler(function(data)
    local projects = data.repos or data.projects or {}
    for i, p in ipairs(projects) do
      projects[i] = translate_pagure_repo(p)
    end
    return projects
  end, function(username)
    return append_page_params(base() .. "/user/" .. username .. "/projects", PAGES)
  end),

  -- Public repos list ---------------------------------------------------------

  get_repositories = function()
    proxy_json(function(data)
      local projects = data.projects or {}
      for i, p in ipairs(projects) do
        projects[i] = translate_pagure_repo(p)
      end
      return projects
    end, fetch_json(append_page_params(base() .. "/repos", PAGES)))
  end,

  -- Issues --------------------------------------------------------------------

  get_repo_issues = proxy_handler(translate_pagure_issues, function(o, r)
    return append_page_params(base().."/"..o.."/"..r.."/issues", PAGES)
  end),

  -- Pagure uses /issue/{id} (singular) for individual issues
  get_repo_issue = proxy_handler(translate_pagure_issue, function(o, r, n)
    return base().."/"..o.."/"..r.."/issue/"..n
  end),

  get_issue_comments = function(owner, repo_name, issue_number)
    -- Pagure returns comments embedded in the issue object
    local ok, status, _, body = fetch_json(
      base().."/"..owner.."/"..repo_name.."/issue/"..issue_number)
    if not ok then respond_json(503, "Service Unavailable", {}); return end
    if status ~= 200 then respond_json(status, "Error", {}); return end
    local issue = DecodeJson(body or "{}") or {}
    local comments = {}
    for _, c in ipairs(issue.comments or {}) do
      comments[#comments + 1] = translate_pagure_comment(c)
    end
    respond_json(200, "OK", comments)
  end,

  get_repo_labels = function(owner, repo_name)
    -- Pagure has no repo-level label list endpoint; return empty list
    respond_json(200, "OK", {})
  end,

}
