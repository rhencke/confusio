-- Gerrit backend handler overrides.
-- Uses Gerrit REST API at /a/ (authenticated) endpoints.
-- Projects in Gerrit use "/" as separator (e.g. "owner/repo"), URL-encoded as "owner%2Frepo".

local base = function()
  return config.base_url .. "/a"
end
local auth = function()
  return make_fetch_opts("basic")
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

-- Gerrit project names use "/" as path separator; URL-encode it.
local function project_id(owner, repo_name)
  return owner .. "%2F" .. repo_name
end

-- Map a Gerrit project object to GitHub format.
local function translate_gerrit_repo(r, owner, repo_name)
  if not r then
    return {}
  end
  local full = r.name or (owner and (owner .. "/" .. (repo_name or "")) or "")
  local o, n = full:match("^(.+)/([^/]+)$")
  if not o then
    o = ""
    n = full
  end
  return {
    id = 0,
    node_id = "",
    name = n,
    full_name = full,
    private = false,
    owner = {
      login = o,
      id = 0,
      node_id = "",
      avatar_url = "",
      url = "",
      html_url = "",
      type = "User",
    },
    html_url = config.base_url .. "/admin/repos/" .. full,
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
    archived = r.state == "READ_ONLY",
    disabled = r.state == "HIDDEN",
    open_issues_count = 0,
    default_branch = "main",
    visibility = "public",
    forks = 0,
    open_issues = 0,
    watchers = 0,
    created_at = nil,
    updated_at = nil,
    pushed_at = nil,
  }
end

-- Gerrit prepends ")]}'\n" (5 chars) to all JSON responses as XSSI protection.
local function gerrit_decode(body)
  if body and body:sub(1, 4) == ")]}'" then
    return DecodeJson(body:sub(6)) or {}
  end
  return DecodeJson(body) or {}
end

-- Map a Gerrit account object to GitHub user format.
local function translate_gerrit_user(u)
  if not u then
    return {}
  end
  return {
    login = u.username or "",
    id = u._account_id or 0,
    node_id = "",
    avatar_url = "",
    html_url = "",
    type = "User",
    site_admin = false,
    name = u.name or "",
    email = u.email or "",
  }
end

-- Gerrit branch: { ref, revision }
local function translate_gerrit_branch(b)
  if not b then
    return {}
  end
  local name = b.ref and b.ref:match("^refs/heads/(.+)") or (b.ref or "")
  return { name = name, commit = { sha = b.revision or "", url = "" }, protected = false }
end

local proxy_handler = make_proxy_handler(fetch_json)

-- Gerrit tag: { ref, revision, object }
local function translate_gerrit_tag(t)
  if not t then
    return {}
  end
  local name = t.ref and t.ref:match("^refs/tags/(.+)") or (t.ref or "")
  return { name = name, commit = { sha = t.revision or t.object or "", url = "" } }
end

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, config.base_url .. "/config/server/version", auth())
    if ok and status == 200 then
      respond_json(200, "OK", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,
  get_repo = proxy_handler(translate_gerrit_repo, function(owner, repo_name)
    return base() .. "/projects/" .. project_id(owner, repo_name)
  end),

  patch_repo = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
    local g = {}
    if req.description then
      g.description = req.description
    end
    proxy_json(
      function(r)
        return translate_gerrit_repo(r, owner, repo_name)
      end,
      fetch_json(
        base() .. "/projects/" .. project_id(owner, repo_name) .. "/config",
        "PUT",
        EncodeJson(g)
      )
    )
  end,

  -- Gerrit: GET /a/projects/ → dict of project_name → project_info
  get_user_repos = function()
    local limit = GetParam("per_page") or "30"
    local skip = ((tonumber(GetParam("page")) or 1) - 1) * (tonumber(limit) or 30)
    local url = base() .. "/projects/?n=" .. limit .. (skip > 0 and ("&S=" .. skip) or "")
    proxy_json(function(data)
      local repos = {}
      for name, r in pairs(data or {}) do
        r.name = name
        repos[#repos + 1] = translate_gerrit_repo(r)
      end
      return repos
    end, fetch_json(url))
  end,

  get_users_repos = function(username)
    local limit = GetParam("per_page") or "30"
    local skip = ((tonumber(GetParam("page")) or 1) - 1) * (tonumber(limit) or 30)
    local url = base()
      .. "/projects/?p="
      .. username
      .. "%2F&n="
      .. limit
      .. (skip > 0 and ("&S=" .. skip) or "")
    proxy_json(function(data)
      local repos = {}
      for name, r in pairs(data or {}) do
        r.name = name
        repos[#repos + 1] = translate_gerrit_repo(r)
      end
      return repos
    end, fetch_json(url))
  end,

  get_repositories = function()
    local limit = GetParam("per_page") or "30"
    local skip = ((tonumber(GetParam("page")) or 1) - 1) * (tonumber(limit) or 30)
    local url = base() .. "/projects/?n=" .. limit .. (skip > 0 and ("&S=" .. skip) or "")
    proxy_json(function(data)
      local repos = {}
      for name, r in pairs(data or {}) do
        r.name = name
        repos[#repos + 1] = translate_gerrit_repo(r)
      end
      return repos
    end, fetch_json(url))
  end,

  -- Branches ------------------------------------------------------------------
  -- GET /a/projects/{id}/branches/ → [{ ref, revision }]

  get_repo_branches = proxy_handler(function(branches)
    local result = {}
    for _, b in ipairs(branches or {}) do
      if b.ref and b.ref:match("^refs/heads/") then
        result[#result + 1] = translate_gerrit_branch(b)
      end
    end
    return result
  end, function(owner, repo_name)
    return base() .. "/projects/" .. project_id(owner, repo_name) .. "/branches/"
  end),

  get_repo_branch = proxy_handler(translate_gerrit_branch, function(owner, repo_name, branch)
    return base()
      .. "/projects/"
      .. project_id(owner, repo_name)
      .. "/branches/refs%2Fheads%2F"
      .. branch
  end),

  -- Tags ----------------------------------------------------------------------
  -- GET /a/projects/{id}/tags/ → [{ ref, revision, object }]

  get_repo_tags = proxy_handler(function(tags)
    local result = {}
    for _, t in ipairs(tags or {}) do
      result[#result + 1] = translate_gerrit_tag(t)
    end
    return result
  end, function(owner, repo_name)
    return base() .. "/projects/" .. project_id(owner, repo_name) .. "/tags/"
  end),

  -- Commits -------------------------------------------------------------------
  -- Gerrit: GET /a/projects/{id}/commits/{sha}

  get_repo_commit = proxy_handler(function(c)
    if not c then
      return {}
    end
    local author = c.author or {}
    local committer = c.committer or {}
    return {
      sha = c.commit or "",
      commit = {
        message = c.message or "",
        author = { name = author.name or "", email = author.email or "", date = author.date or "" },
        committer = {
          name = committer.name or "",
          email = committer.email or "",
          date = committer.date or "",
        },
      },
    }
  end, function(owner, repo_name, ref)
    return base() .. "/projects/" .. project_id(owner, repo_name) .. "/commits/" .. ref
  end),

  -- Users ---------------------------------------------------------------------

  -- GET /user — authenticated user
  get_user = function()
    local ok, status, _, body = fetch_json(base() .. "/accounts/self?o=DETAILS")
    if ok and status == 200 then
      respond_json(200, "OK", translate_gerrit_user(gerrit_decode(body)))
    elseif ok then
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- GET /users/{username}
  get_users_username = function(username)
    local ok, status, _, body = fetch_json(base() .. "/accounts/" .. username .. "?o=DETAILS")
    if ok and status == 200 then
      respond_json(200, "OK", translate_gerrit_user(gerrit_decode(body)))
    elseif ok then
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- GET /users — search active accounts
  get_users = function()
    local limit = GetParam("per_page") or "30"
    local page = tonumber(GetParam("page")) or 1
    local skip = (page - 1) * (tonumber(limit) or 30)
    local url = base()
      .. "/accounts/?q=is:active&o=DETAILS&n="
      .. limit
      .. (skip > 0 and ("&S=" .. skip) or "")
    local ok, status, _, body = fetch_json(url)
    if ok and status == 200 then
      local accounts = gerrit_decode(body)
      local users = {}
      for _, a in ipairs(accounts) do
        users[#users + 1] = translate_gerrit_user(a)
      end
      respond_json(200, "OK", users)
    elseif ok then
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- Contents ------------------------------------------------------------------
  -- Gerrit returns raw base64-encoded content at /branches/{branch}/files/{path}/content

  get_repo_content = function(owner, repo_name, path)
    local ref = GetParam("ref") or "HEAD"
    local url = base()
      .. "/projects/"
      .. project_id(owner, repo_name)
      .. "/branches/"
      .. ref
      .. "/files/"
      .. path
      .. "/content"
    local ok, status, _, body = fetch_json(url)
    if ok and status == 200 then
      -- Gerrit returns already-base64-encoded content
      respond_json(200, "OK", {
        type = "file",
        name = path:match("[^/]+$") or path,
        path = path,
        sha = "",
        size = 0,
        encoding = "base64",
        content = body,
      })
    elseif ok then
      respond_json(status, "Error", { message = "Error" })
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,
}
