-- Bitbucket Datacenter (Server) backend handler overrides.
-- Uses Bitbucket Server REST API v1 at /rest/api/1.0/.
-- Repos are addressed as /projects/{projectKey}/repos/{slug}.
-- Personal project keys use the ~username convention (e.g. ~octocat).

local base = function() return config.base_url .. "/rest/api/1.0" end
local auth = function() return make_fetch_opts("basic") end

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

-- Bitbucket DC pagination: { values, isLastPage, start, limit }
-- Upstream query params: start (offset) and limit (page size).
local function bbs_page_url(url)
  local sep = url:find("?") and "&" or "?"
  local pp = GetParam("per_page")
  local pg = GetParam("page")
  if pp and pp ~= "" then
    local limit = tonumber(pp) or 25
    local page  = tonumber(pg) or 1
    url = url .. sep .. "limit=" .. limit .. "&start=" .. ((page - 1) * limit)
  end
  return url
end

-- Map a Bitbucket DC project key + repo object to GitHub format.
local function translate_bbs_repo(r, proj_key)
  if not r then return {} end
  local proj = r.project or {}
  local key = proj_key or proj.key or ""
  -- Strip leading ~ for the display login; keep ~ if it's a personal project
  local login = key:match("^~(.+)$") or key
  local links = r.links or {}
  local self_links = links.self or {}
  local html_url = (self_links[1] and self_links[1].href) or ""
  return {
    id                = r.id or 0,
    node_id           = "",
    name              = r.slug or r.name or "",
    full_name         = login .. "/" .. (r.slug or r.name or ""),
    private           = not (r.public or false),
    owner             = {
      login      = login,
      id         = proj.id or 0,
      node_id    = "",
      avatar_url = "",
      url        = "",
      html_url   = "",
      type       = proj.type == "PERSONAL" and "User" or "Organization",
    },
    html_url          = html_url,
    description       = r.description,
    fork              = r.origin ~= nil,
    url               = html_url,
    clone_url         = "",
    homepage          = "",
    size              = 0,
    stargazers_count  = 0,
    watchers_count    = 0,
    language          = nil,
    has_issues        = false,
    has_wiki          = false,
    forks_count       = 0,
    archived          = r.archived or false,
    disabled          = false,
    open_issues_count = 0,
    default_branch    = r.default_branch or "main",
    visibility        = (r.public or false) and "public" or "private",
    forks             = 0,
    open_issues       = 0,
    watchers          = 0,
    created_at        = nil,
    updated_at        = nil,
    pushed_at         = nil,
  }
end

-- Map a Bitbucket DC user object to GitHub format.
local function translate_bbs_user(u)
  if not u then return {} end
  return {
    login      = u.name or u.slug or "",
    id         = u.id or 0,
    node_id    = "",
    avatar_url = "",
    html_url   = "",
    type       = "User",
    site_admin = false,
    name       = u.displayName or "",
    email      = u.emailAddress or "",
  }
end

local function translate_bbs_repos(data, proj_key)
  local repos = (data and data.values) or {}
  for i, r in ipairs(repos) do repos[i] = translate_bbs_repo(r, proj_key) end
  return repos
end

-- Translate GitHub create/update request body to Bitbucket DC format.
local function translate_bbs_req(body_str)
  local req = DecodeJson(body_str or "{}")
  local bbs = {}
  if req.name        then bbs.name        = req.name end
  if req.description then bbs.description = req.description end
  if req.private ~= nil then bbs.public   = not req.private end
  return EncodeJson(bbs)
end

-- Translate a DC branch object to GitHub format.
-- DC: { id: "refs/heads/main", displayId: "main", latestCommit: "abc123..." }
local function translate_bbs_branch(b)
  if not b then return {} end
  return {
    name      = b.displayId or b.id and b.id:match("refs/heads/(.+)") or "",
    commit    = { sha = b.latestCommit or b.latestChangeset or "", url = "" },
    protected = false,
  }
end

-- Translate a DC commit object to GitHub format.
-- DC: { id, displayId, author: { name, emailAddress }, authorTimestamp, message }
local function translate_bbs_commit(c)
  if not c then return {} end
  local author = c.author or {}
  local ts = c.authorTimestamp
  local date = ts and os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(ts / 1000)) or ""
  return {
    sha    = c.id or "",
    commit = {
      message   = c.message or "",
      author    = { name = author.name or "", email = author.emailAddress or "", date = date },
      committer = { name = author.name or "", email = author.emailAddress or "", date = date },
    },
    author    = { login = author.name or "", id = 0, avatar_url = "" },
    committer = { login = author.name or "", id = 0, avatar_url = "" },
  }
end

-- Translate a DC deploy key to GitHub format.
-- DC: { id, key: { id, label, text, createdDate } }
local function translate_bbs_key(k)
  if not k then return {} end
  local key = k.key or {}
  return {
    id         = k.id or 0,
    key        = key.text or "",
    title      = key.label or "",
    read_only  = true,
    verified   = true,
    created_at = nil,
  }
end

-- Translate a DC webhook to GitHub format.
-- DC: { id, name, url, events: [...], active, configuration: {...} }
local function translate_bbs_hook(h)
  if not h then return {} end
  return {
    id         = h.id or 0,
    name       = h.name or "web",
    active     = h.active ~= false,
    events     = h.events or {},
    config     = { url = h.url or "", content_type = "json" },
    created_at = nil,
    updated_at = nil,
  }
end

local function translate_bbs_hook_req(body_str)
  local req = DecodeJson(body_str or "{}")
  local cfg = req.config or {}
  return EncodeJson({
    name    = req.name or "web",
    url     = cfg.url or "",
    active  = req.active ~= false,
    events  = req.events or { "repo:refs_changed" },
  })
end

local function proxy_handler(xform, url_fn)
  return function(...)
    local args = {...}
    proxy_json(
      type(xform) == "function" and function(r) return xform(r, table.unpack(args)) end or xform,
      fetch_json(url_fn(...)))
  end
end

-- Repo path helper: /projects/{owner}/repos/{repo}
local function repo_path(owner, repo_name)
  return base() .. "/projects/" .. owner .. "/repos/" .. repo_name
end

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, base() .. "/repos", auth())
    if ok and status == 200 then respond_json(200, "OK", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_repo = proxy_handler(translate_bbs_repo,
    function(owner, repo_name) return repo_path(owner, repo_name) end),

  patch_repo = function(owner, repo_name)
    proxy_json(
      function(r) return translate_bbs_repo(r, owner) end,
      fetch_json(repo_path(owner, repo_name), "PUT", translate_bbs_req(GetBody())))
  end,

  delete_repo = function(owner, repo_name)
    local dopts = auth() or {}; dopts.method = "DELETE"
    local ok, status = pcall(Fetch, repo_path(owner, repo_name), dopts)
    if ok and (status == 202 or status == 204) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- GET /user/repos — DC: GET /repos (all repos visible to the auth'd user)
  get_user_repos = proxy_handler(translate_bbs_repos, function()
    return bbs_page_url(base().."/repos")
  end),

  post_user_repos = function()
    -- DC requires a project key; no generic "my repos" create endpoint.
    respond_json(501, "Not Implemented",
      { message = "POST /user/repos requires a project key; use POST /orgs/{project}/repos" })
  end,

  get_org_repos = proxy_handler(translate_bbs_repos,
    function(project_key)
      return bbs_page_url(base() .. "/projects/" .. project_key .. "/repos")
    end),

  post_org_repos = function(project_key)
    proxy_json_created(
      function(r) return translate_bbs_repo(r, project_key) end,
      fetch_json(base() .. "/projects/" .. project_key .. "/repos",
        "POST", translate_bbs_req(GetBody())))
  end,

  -- GET /users/{username}/repos — via personal project ~username
  get_users_repos = proxy_handler(
    function(data, username) return translate_bbs_repos(data, "~" .. username) end,
    function(username) return bbs_page_url(base() .. "/projects/~" .. username .. "/repos") end),

  -- GET /repositories — all repos visible to the authenticated user
  get_repositories = proxy_handler(translate_bbs_repos, function()
    return bbs_page_url(base().."/repos")
  end),

  -- Tags -----------------------------------------------------------------------
  -- DC: GET /projects/{proj}/repos/{slug}/tags → { values: [{id, displayId, latestCommit}] }

  get_repo_tags = proxy_handler(
    function(data)
      local tags = data.values or {}
      local result = {}
      for _, t in ipairs(tags) do
        result[#result + 1] = {
          name   = t.displayId or t.id or "",
          commit = { sha = t.latestCommit or t.latestChangeset or "", url = "" },
        }
      end
      return result
    end,
    function(owner, repo_name) return bbs_page_url(repo_path(owner, repo_name).."/tags") end),

  -- Branches -------------------------------------------------------------------

  get_repo_branches = proxy_handler(
    function(data)
      local branches = data.values or {}
      for i, b in ipairs(branches) do branches[i] = translate_bbs_branch(b) end
      return branches
    end,
    function(owner, repo_name) return bbs_page_url(repo_path(owner, repo_name).."/branches") end),

  get_repo_branch = proxy_handler(
    function(data)
      local b = (data.values or {})[1]
      return b and translate_bbs_branch(b) or {}
    end,
    function(owner, repo_name, branch)
      return repo_path(owner, repo_name).."/branches?filterText="..branch.."&limit=1"
    end),

  -- Commits --------------------------------------------------------------------

  get_repo_commits = function(owner, repo_name)
    local ref = GetParam("sha") or ""
    local url = bbs_page_url(repo_path(owner, repo_name) .. "/commits")
    if ref ~= "" then
      local sep = url:find("?") and "&" or "?"
      url = url .. sep .. "until=" .. ref
    end
    proxy_json(
      function(data)
        local commits = data.values or {}
        for i, c in ipairs(commits) do commits[i] = translate_bbs_commit(c) end
        return commits
      end,
      fetch_json(url))
  end,

  get_repo_commit = proxy_handler(translate_bbs_commit, function(owner, repo_name, sha)
    return repo_path(owner, repo_name).."/commits/"..sha
  end),

  -- Contents -------------------------------------------------------------------
  -- DC: GET /projects/{proj}/repos/{slug}/raw/{path}?at={ref}

  get_repo_readme = function(owner, repo_name)
    local ref = GetParam("ref") or ""
    local candidates = { "README.md", "README", "readme.md", "README.rst" }
    for _, fname in ipairs(candidates) do
      local url = repo_path(owner, repo_name) .. "/raw/" .. fname
      if ref ~= "" then url = url .. "?at=" .. ref end
      local ok, status, _, body = fetch_json(url)
      if ok and status == 200 then
        respond_json(200, "OK", {
          type     = "file",
          name     = fname,
          path     = fname,
          sha      = "",
          size     = #body,
          encoding = "base64",
          content  = EncodeBase64(body),
        })
        return
      end
    end
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  get_repo_content = function(owner, repo_name, path)
    local ref = GetParam("ref") or ""
    local url = repo_path(owner, repo_name) .. "/raw/" .. path
    if ref ~= "" then url = url .. "?at=" .. ref end
    local ok, status, _, body = fetch_json(url)
    if ok and status == 200 then
      respond_json(200, "OK", {
        type     = "file",
        name     = path:match("[^/]+$") or path,
        path     = path,
        sha      = "",
        size     = #body,
        encoding = "base64",
        content  = EncodeBase64(body),
      })
    elseif ok then respond_json(status, "Error", { message = "Error" })
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- Forks ----------------------------------------------------------------------

  get_repo_forks = proxy_handler(translate_bbs_repos,
    function(owner, repo_name) return bbs_page_url(repo_path(owner, repo_name) .. "/forks") end),

  post_repo_forks = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
    local bb = {}
    if req.organization then
      bb.project = { key = req.organization }
    end
    proxy_json_created(
      function(r) return translate_bbs_repo(r, owner) end,
      fetch_json(repo_path(owner, repo_name) .. "/forks",
        "POST", EncodeJson(bb)))
  end,

  -- Deploy keys ----------------------------------------------------------------
  -- DC: /ssh endpoint (not /deploy-keys)

  get_repo_keys = proxy_handler(
    function(data)
      local keys = data.values or {}
      for i, k in ipairs(keys) do keys[i] = translate_bbs_key(k) end
      return keys
    end,
    function(owner, repo_name) return bbs_page_url(repo_path(owner, repo_name).."/ssh") end),

  post_repo_keys = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
    local bb = {
      key  = { text = req.key or "", label = req.title or "" },
      permission = "REPO_READ",
    }
    proxy_json_created(translate_bbs_key,
      fetch_json(repo_path(owner, repo_name) .. "/ssh",
        "POST", EncodeJson(bb)))
  end,

  get_repo_key = proxy_handler(translate_bbs_key, function(owner, repo_name, key_id)
    return repo_path(owner, repo_name).."/ssh/"..key_id
  end),

  delete_repo_key = function(owner, repo_name, key_id)
    local dopts = auth() or {}; dopts.method = "DELETE"
    local ok, status = pcall(Fetch, repo_path(owner, repo_name) .. "/ssh/" .. key_id, dopts)
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- Webhooks -------------------------------------------------------------------

  get_repo_hooks = proxy_handler(
    function(data)
      local hooks = data.values or {}
      for i, h in ipairs(hooks) do hooks[i] = translate_bbs_hook(h) end
      return hooks
    end,
    function(owner, repo_name) return bbs_page_url(repo_path(owner, repo_name).."/webhooks") end),

  post_repo_hooks = function(owner, repo_name)
    proxy_json_created(translate_bbs_hook,
      fetch_json(repo_path(owner, repo_name) .. "/webhooks",
        "POST", translate_bbs_hook_req(GetBody())))
  end,

  get_repo_hook = proxy_handler(translate_bbs_hook, function(owner, repo_name, hook_id)
    return repo_path(owner, repo_name).."/webhooks/"..hook_id
  end),

  patch_repo_hook = function(owner, repo_name, hook_id)
    proxy_json(translate_bbs_hook,
      fetch_json(repo_path(owner, repo_name) .. "/webhooks/" .. hook_id,
        "PUT", translate_bbs_hook_req(GetBody())))
  end,

  delete_repo_hook = function(owner, repo_name, hook_id)
    local dopts = auth() or {}; dopts.method = "DELETE"
    local ok, status = pcall(Fetch, repo_path(owner, repo_name) .. "/webhooks/" .. hook_id, dopts)
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_repo_hook_config = proxy_handler(
    function(h) return (translate_bbs_hook(h)).config or {} end,
    function(owner, repo_name, hook_id) return repo_path(owner, repo_name).."/webhooks/"..hook_id end),

  -- Users ---------------------------------------------------------------------

  -- GET /users/{username}
  get_users_username = proxy_handler(translate_bbs_user, function(username)
    return base().."/users/"..username
  end),

  -- GET /users
  get_users = proxy_handler(
    function(data)
      local users = (data and data.values) or {}
      for i, u in ipairs(users) do users[i] = translate_bbs_user(u) end
      return users
    end,
    function() return bbs_page_url(base().."/users") end),
}
