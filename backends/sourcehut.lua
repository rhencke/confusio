-- Sourcehut backend handler overrides.
-- Uses git.sr.ht REST API at /api/~{username}/repos/{name}.

local base = function() return config.base_url .. "/api" end
local auth = function() return make_fetch_opts("token") end

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

-- Map a Sourcehut repository object to GitHub format.
local function translate_srht_repo(r)
  if not r then return {} end
  local owner = r.owner or {}
  local canonical = owner.canonical_name or ""
  -- canonical_name is like "~username", strip the tilde for login
  local login = canonical:sub(1, 1) == "~" and canonical:sub(2) or canonical
  local vis = r.visibility or "public"
  return {
    id                = r.id or 0,
    node_id           = "",
    name              = r.name,
    full_name         = login .. "/" .. (r.name or ""),
    private           = vis == "private",
    owner             = {
      login      = login,
      id         = 0,
      node_id    = "",
      avatar_url = "",
      url        = "",
      html_url   = config.base_url .. "/" .. canonical,
      type       = "User",
    },
    html_url          = config.base_url .. "/" .. canonical .. "/" .. (r.name or ""),
    description       = r.description,
    fork              = false,
    url               = "",
    clone_url         = "",
    homepage          = "",
    size              = 0,
    stargazers_count  = 0,
    watchers_count    = 0,
    language          = nil,
    has_issues        = false,
    has_wiki          = false,
    forks_count       = 0,
    archived          = false,
    disabled          = false,
    open_issues_count = 0,
    default_branch    = r.HEAD and r.HEAD.name or "main",
    visibility        = vis == "private" and "private" or "public",
    forks             = 0,
    open_issues       = 0,
    watchers          = 0,
    created_at        = r.created,
    updated_at        = r.updated,
    pushed_at         = r.updated,
  }
end

-- Translate GitHub create/update request body to Sourcehut format.
local function translate_srht_req(body_str)
  local req = DecodeJson(body_str or "{}")
  local sr = {}
  if req.name        then sr.name        = req.name end
  if req.description then sr.description = req.description end
  if req.private ~= nil then
    sr.visibility = req.private and "private" or "public"
  end
  return EncodeJson(sr)
end

-- Translate a Sourcehut ref to a GitHub branch object.
-- Only call for refs with names like "refs/heads/main".
local function translate_srht_branch(ref)
  if not ref then return {} end
  local name = ref.name and ref.name:match("^refs/heads/(.+)") or (ref.name or "")
  return {
    name      = name,
    commit    = { sha = ref.target or "", url = "" },
    protected = false,
  }
end

-- Translate a Sourcehut log entry to GitHub commit format.
-- Sourcehut: { id, message, timestamp, author: { name, email } }
local function translate_srht_commit(c)
  if not c then return {} end
  local author = c.author or {}
  return {
    sha    = c.id or "",
    commit = {
      message   = c.message or "",
      author    = { name = author.name or "", email = author.email or "", date = c.timestamp or "" },
      committer = { name = author.name or "", email = author.email or "", date = c.timestamp or "" },
    },
    author    = { login = author.name or "", id = 0, avatar_url = "" },
    committer = { login = author.name or "", id = 0, avatar_url = "" },
  }
end

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, config.base_url .. "/api/version", auth())
    if ok and status == 200 then respond_json(200, "OK", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_repo = function(owner, repo_name)
    proxy_json(translate_srht_repo,
      fetch_json(base() .. "/~" .. owner .. "/repos/" .. repo_name))
  end,

  patch_repo = function(owner, repo_name)
    -- Sourcehut uses PUT for updates
    proxy_json(translate_srht_repo,
      fetch_json(base() .. "/~" .. owner .. "/repos/" .. repo_name,
        "PUT", translate_srht_req(GetBody())))
  end,

  delete_repo = function(owner, repo_name)
    local url = base() .. "/~" .. owner .. "/repos/" .. repo_name
    local dopts = auth() or {}; dopts.method = "DELETE"
    local ok, status = pcall(Fetch, url, dopts)
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_user_repos = function()
    -- Sourcehut: need to know the authenticated user. Use /api/user first.
    local ok, status, _, ubody = fetch_json(config.base_url .. "/api/user")
    if not ok or status ~= 200 then respond_json(503, "Service Unavailable", {}); return end
    local user = DecodeJson(ubody)
    local canonical = user.canonical_name or ("~" .. (user.name or ""))
    proxy_json(
      function(data)
        local repos = data.results or {}
        for i, r in ipairs(repos) do repos[i] = translate_srht_repo(r) end
        return repos
      end,
      -- Sourcehut uses cursor-based pagination; only limit is supported for page size
      fetch_json(append_page_params(base() .. "/" .. canonical .. "/repos",
        { per_page = "limit" })))
  end,

  post_user_repos = function()
    -- Sourcehut: create via POST /api/~{user}/repos — need user context
    local ok, status, _, ubody = fetch_json(config.base_url .. "/api/user")
    if not ok or status ~= 200 then respond_json(503, "Service Unavailable", {}); return end
    local user = DecodeJson(ubody)
    local canonical = user.canonical_name or ("~" .. (user.name or ""))
    proxy_json_created(translate_srht_repo,
      fetch_json(base() .. "/" .. canonical .. "/repos", "POST", translate_srht_req(GetBody())))
  end,

  -- Branches ------------------------------------------------------------------
  -- Sourcehut: filter /refs for refs starting with "refs/heads/"

  get_repo_branches = function(owner, repo_name)
    proxy_json(
      function(data)
        local branches = {}
        for _, ref in ipairs(data.results or {}) do
          if ref.name and ref.name:match("^refs/heads/") then
            branches[#branches + 1] = translate_srht_branch(ref)
          end
        end
        return branches
      end,
      fetch_json(base() .. "/~" .. owner .. "/repos/" .. repo_name .. "/refs"))
  end,

  get_repo_branch = function(owner, repo_name, branch)
    -- Fetch the specific ref: refs/heads/{branch}
    proxy_json(
      function(data)
        for _, ref in ipairs(data.results or {}) do
          if ref.name == "refs/heads/" .. branch then
            return translate_srht_branch(ref)
          end
        end
        return {}
      end,
      fetch_json(base() .. "/~" .. owner .. "/repos/" .. repo_name .. "/refs"))
  end,

  -- Tags ----------------------------------------------------------------------
  -- Sourcehut /refs returns { results: [...] } with name and target fields
  -- Filter to tags only (refs starting with "refs/tags/")

  get_repo_tags = function(owner, repo_name)
    proxy_json(
      function(data)
        local tags = {}
        for _, ref in ipairs(data.results or {}) do
          local tag_name = ref.name and ref.name:match("^refs/tags/(.+)")
          if tag_name then
            tags[#tags + 1] = { name = tag_name, commit = { sha = ref.target or "", url = "" } }
          end
        end
        return tags
      end,
      fetch_json(base() .. "/~" .. owner .. "/repos/" .. repo_name .. "/refs"))
  end,

  -- Commits -------------------------------------------------------------------
  -- Sourcehut: GET /api/~{owner}/repos/{name}/log or /log/{ref}

  get_repo_commits = function(owner, repo_name)
    local ref = GetParam("sha") or ""
    local url = base() .. "/~" .. owner .. "/repos/" .. repo_name .. "/log"
    if ref ~= "" then url = url .. "/" .. ref end
    url = append_page_params(url, { per_page = "limit" })
    proxy_json(
      function(data)
        local commits = data.results or {}
        for i, c in ipairs(commits) do commits[i] = translate_srht_commit(c) end
        return commits
      end,
      fetch_json(url))
  end,

  get_repo_commit = function(owner, repo_name, ref)
    -- Fetch the log at the specific ref and return first entry.
    proxy_json(
      function(data)
        local c = (data.results or {})[1]
        return translate_srht_commit(c)
      end,
      fetch_json(base() .. "/~" .. owner .. "/repos/" .. repo_name .. "/log/" .. ref .. "?limit=1"))
  end,

  -- Contents ------------------------------------------------------------------
  -- Sourcehut: GET /api/~{owner}/repos/{name}/blob/{ref}/{path} — raw bytes.

  get_repo_readme = function(owner, repo_name)
    local ref = GetParam("ref") or "HEAD"
    local candidates = { "README.md", "README", "readme.md", "README.rst" }
    for _, fname in ipairs(candidates) do
      local url = base() .. "/~" .. owner .. "/repos/" .. repo_name ..
        "/blob/" .. ref .. "/" .. fname
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
    local ref = GetParam("ref") or "HEAD"
    local url = base() .. "/~" .. owner .. "/repos/" .. repo_name ..
      "/blob/" .. ref .. "/" .. path
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

  -- Users' repos --------------------------------------------------------------

  get_users_repos = function(username)
    proxy_json(
      function(data)
        local repos = data.results or {}
        for i, r in ipairs(repos) do repos[i] = translate_srht_repo(r) end
        return repos
      end,
      fetch_json(append_page_params(base() .. "/~" .. username .. "/repos",
        { per_page = "limit" })))
  end,

}
