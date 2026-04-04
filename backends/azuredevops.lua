-- Azure DevOps backend handler overrides.
-- Uses Azure DevOps Git REST API.
-- config.base_url = https://dev.azure.com/{org}  (or https://{org}.visualstudio.com)
-- GitHub {owner}/{repo} maps to: owner = ADO project, repo = ADO repository name.
-- API version is appended as ?api-version=7.0 on all requests.

local auth = function() return make_fetch_opts("basic-colon") end
local API_VER = "api-version=7.0"

local function repos_base(owner)
  return config.base_url .. "/" .. owner .. "/_apis/git/repositories"
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

local function ado_url(path)
  return path .. (path:find("?") and "&" or "?") .. API_VER
end

-- Map an Azure DevOps repository object to GitHub format.
-- ADO: { id, name, remoteUrl, defaultBranch, isDisabled, isPrivate, size, project }
local function translate_ado_repo(r)
  if not r then return {} end
  local proj = r.project or {}
  local branch = r.defaultBranch and r.defaultBranch:match("refs/heads/(.+)") or "main"
  return {
    id                = 0,
    node_id           = r.id or "",
    name              = r.name or "",
    full_name         = (proj.name or "") .. "/" .. (r.name or ""),
    private           = r.isPrivate or false,
    owner             = {
      login      = proj.name or "",
      id         = 0,
      node_id    = proj.id or "",
      avatar_url = "",
      url        = "",
      html_url   = "",
      type       = "Organization",
    },
    html_url          = r.remoteUrl or "",
    description       = r.project and r.project.description or nil,
    fork              = false,
    url               = "",
    clone_url         = r.remoteUrl or "",
    homepage          = "",
    size              = r.size or 0,
    stargazers_count  = 0,
    watchers_count    = 0,
    language          = nil,
    has_issues        = true,
    has_wiki          = false,
    forks_count       = 0,
    archived          = false,
    disabled          = r.isDisabled or false,
    open_issues_count = 0,
    default_branch    = branch,
    visibility        = (r.isPrivate or false) and "private" or "public",
    forks             = 0,
    open_issues       = 0,
    watchers          = 0,
    created_at        = nil,
    updated_at        = nil,
    pushed_at         = nil,
  }
end

-- ADO branch ref: { name, objectId, creator }
local function translate_ado_branch(b)
  if not b then return {} end
  local name = b.name and b.name:match("refs/heads/(.+)") or (b.name or "")
  return { name = name, commit = { sha = b.objectId or "", url = "" }, protected = false }
end

-- ADO commit: { commitId, comment, author, committer }
local function translate_ado_commit(c)
  if not c then return {} end
  local author = c.author or {}
  local committer = c.committer or {}
  return {
    sha    = c.commitId or "",
    commit = {
      message   = c.comment or "",
      author    = { name = author.name or "", email = author.email or "", date = author.date or "" },
      committer = { name = committer.name or "", email = committer.email or "", date = committer.date or "" },
    },
    author    = { login = author.name or "", id = 0, avatar_url = "" },
    committer = { login = committer.name or "", id = 0, avatar_url = "" },
  }
end

-- ADO tag ref: same shape as branch but name is refs/tags/...
local function translate_ado_tag(t)
  if not t then return {} end
  local name = t.name and t.name:match("refs/tags/(.+)") or (t.name or "")
  return { name = name, commit = { sha = t.objectId or "", url = "" } }
end

-- ADO webhook: { id, url, publisherInputs: { repository }, status, eventType }
local function translate_ado_hook(h)
  if not h then return {} end
  return {
    id         = h.id or 0,
    name       = "web",
    active     = h.status == "enabled",
    events     = { h.eventType or "" },
    config     = { url = (h.consumerInputs and h.consumerInputs.url) or "", content_type = "json" },
    created_at = h.createdDate,
    updated_at = h.modifiedDate,
  }
end

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch,
      ado_url(config.base_url .. "/_apis/connectionData"), auth())
    if ok and status == 200 then respond_json(200, "OK", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,
  get_emojis = function() respond_json(404, "Not Found", { message = "Not Found" }) end,

  get_repo = function(owner, repo_name)
    proxy_json(translate_ado_repo,
      fetch_json(ado_url(repos_base(owner) .. "/" .. repo_name)))
  end,

  patch_repo = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
    local a = {}
    if req.description ~= nil then a.project = { description = req.description } end
    if req.default_branch then a.defaultBranch = "refs/heads/" .. req.default_branch end
    proxy_json(translate_ado_repo,
      fetch_json(ado_url(repos_base(owner) .. "/" .. repo_name), "PATCH", EncodeJson(a)))
  end,

  delete_repo = function(owner, repo_name)
    -- Must resolve repo ID first
    local ok, status, _, body = fetch_json(ado_url(repos_base(owner) .. "/" .. repo_name))
    if not ok or status ~= 200 then
      respond_json(ok and status or 503, "Error", {}); return
    end
    local repo = DecodeJson(body) or {}
    local repo_id = repo.id or repo_name
    local dopts = auth() or {}; dopts.method = "DELETE"
    local dok, dstatus = pcall(Fetch, ado_url(repos_base(owner) .. "/" .. repo_id), dopts)
    if dok and (dstatus == 204 or dstatus == 200) then SetStatus(204, "No Content")
    elseif dok then respond_json(dstatus, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_user_repos = function()
    -- ADO: list repos across all projects
    local limit = tonumber(GetParam("per_page")) or 30
    local url = ado_url(config.base_url .. "/_apis/git/repositories")
    proxy_json(
      function(data)
        local repos = {}
        local all = data.value or {}
        for i = 1, math.min(limit, #all) do repos[#repos + 1] = translate_ado_repo(all[i]) end
        return repos
      end,
      fetch_json(url))
  end,

  post_user_repos = function()
    -- ADO requires a project; use a "default" project or from request
    local req = DecodeJson(GetBody() or "{}")
    local proj = req.organization or "default"
    local a = { name = req.name or "", project = { name = proj } }
    proxy_json_created(translate_ado_repo,
      fetch_json(ado_url(repos_base(proj)), "POST", EncodeJson(a)))
  end,

  get_org_repos = function(owner)
    local limit = tonumber(GetParam("per_page")) or 30
    local url = ado_url(repos_base(owner))
    proxy_json(
      function(data)
        local repos = {}
        local all = data.value or {}
        for i = 1, math.min(limit, #all) do repos[#repos + 1] = translate_ado_repo(all[i]) end
        return repos
      end,
      fetch_json(url))
  end,

  post_org_repos = function(owner)
    local req = DecodeJson(GetBody() or "{}")
    local a = { name = req.name or "", project = { name = owner } }
    proxy_json_created(translate_ado_repo,
      fetch_json(ado_url(repos_base(owner)), "POST", EncodeJson(a)))
  end,

  -- Branches ------------------------------------------------------------------
  -- ADO: GET /{owner}/_apis/git/repositories/{repo}/refs?filter=heads

  get_repo_branches = function(owner, repo_name)
    local limit = GetParam("per_page") or "30"
    local url = ado_url(repos_base(owner) .. "/" .. repo_name ..
      "/refs?filter=heads&$top=" .. limit)
    proxy_json(
      function(data)
        local result = {}
        for _, b in ipairs(data.value or {}) do result[#result + 1] = translate_ado_branch(b) end
        return result
      end,
      fetch_json(url))
  end,

  get_repo_branch = function(owner, repo_name, branch)
    local url = ado_url(repos_base(owner) .. "/" .. repo_name ..
      "/refs?filter=heads/" .. branch)
    proxy_json(
      function(data)
        local b = (data.value or {})[1]
        return b and translate_ado_branch(b) or {}
      end,
      fetch_json(url))
  end,

  -- Tags ----------------------------------------------------------------------
  -- ADO: GET /{owner}/_apis/git/repositories/{repo}/refs?filter=tags

  get_repo_tags = function(owner, repo_name)
    local url = ado_url(repos_base(owner) .. "/" .. repo_name .. "/refs?filter=tags")
    proxy_json(
      function(data)
        local result = {}
        for _, t in ipairs(data.value or {}) do result[#result + 1] = translate_ado_tag(t) end
        return result
      end,
      fetch_json(url))
  end,

  -- Commits -------------------------------------------------------------------
  -- ADO: GET /{owner}/_apis/git/repositories/{repo}/commits

  get_repo_commits = function(owner, repo_name)
    local limit = GetParam("per_page") or "30"
    local page  = tonumber(GetParam("page")) or 1
    local skip  = (page - 1) * (tonumber(limit) or 30)
    local ref = GetParam("sha") or ""
    local url = ado_url(repos_base(owner) .. "/" .. repo_name ..
      "/commits?$top=" .. limit .. "&$skip=" .. skip)
    if ref ~= "" then url = url .. "&searchCriteria.itemVersion.version=" .. ref end
    proxy_json(
      function(data)
        local result = {}
        for _, c in ipairs(data.value or {}) do result[#result + 1] = translate_ado_commit(c) end
        return result
      end,
      fetch_json(url))
  end,

  get_repo_commit = function(owner, repo_name, ref)
    proxy_json(translate_ado_commit,
      fetch_json(ado_url(repos_base(owner) .. "/" .. repo_name .. "/commits/" .. ref)))
  end,

  -- Contents ------------------------------------------------------------------
  -- ADO: GET /{owner}/_apis/git/repositories/{repo}/items?path={path}&version={ref}

  get_repo_readme = function(owner, repo_name)
    local ref = GetParam("ref") or ""
    local candidates = { "README.md", "README", "readme.md", "README.rst" }
    for _, fname in ipairs(candidates) do
      local url = ado_url(repos_base(owner) .. "/" .. repo_name ..
        "/items?path=/" .. fname .. (ref ~= "" and ("&version=" .. ref) or ""))
      local ok, status, _, body = fetch_json(url)
      if ok and status == 200 then
        respond_json(200, "OK", {
          type = "file", name = fname, path = fname, sha = "",
          size = #body, encoding = "base64", content = EncodeBase64(body),
        })
        return
      end
    end
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  get_repo_content = function(owner, repo_name, path)
    local ref = GetParam("ref") or ""
    local url = ado_url(repos_base(owner) .. "/" .. repo_name ..
      "/items?path=/" .. path .. (ref ~= "" and ("&version=" .. ref) or ""))
    local ok, status, _, body = fetch_json(url)
    if ok and status == 200 then
      respond_json(200, "OK", {
        type = "file", name = path:match("[^/]+$") or path, path = path,
        sha = "", size = #body, encoding = "base64", content = EncodeBase64(body),
      })
    elseif ok then respond_json(status, "Error", { message = "Error" })
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- Archive -------------------------------------------------------------------

  get_repo_tarball = function(owner, repo_name, ref)
    SetStatus(302, "Found")
    SetHeader("Location",
      ado_url(repos_base(owner) .. "/" .. repo_name ..
        "/items?path=/&$format=zip&versionDescriptor.version=" .. ref))
    Write("")
  end,

  get_repo_zipball = function(owner, repo_name, ref)
    SetStatus(302, "Found")
    SetHeader("Location",
      ado_url(repos_base(owner) .. "/" .. repo_name ..
        "/items?path=/&$format=zip&versionDescriptor.version=" .. ref))
    Write("")
  end,

  -- Forks ---------------------------------------------------------------------
  -- ADO: GET /{owner}/_apis/git/repositories/{repo}/forks/{project}

  get_repo_forks = function(owner, repo_name)
    proxy_json(
      function(data)
        local result = {}
        for _, r in ipairs(data.value or {}) do result[#result + 1] = translate_ado_repo(r) end
        return result
      end,
      fetch_json(ado_url(repos_base(owner) .. "/" .. repo_name .. "/forks/" .. owner)))
  end,

  post_repo_forks = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
    local target = req.organization or owner
    proxy_json_created(translate_ado_repo,
      fetch_json(ado_url(repos_base(owner) .. "/" .. repo_name .. "/forks"),
        "POST", EncodeJson({ targetProjectId = target })))
  end,

  -- Webhooks ------------------------------------------------------------------
  -- ADO: GET /_apis/hooks/subscriptions?publisherInputs.repository={repo_id}

  get_repo_hooks = function(owner, repo_name)
    -- First resolve repo ID
    local ok, status, _, body = fetch_json(ado_url(repos_base(owner) .. "/" .. repo_name))
    if not ok or status ~= 200 then respond_json(ok and status or 503, "Error", {}); return end
    local repo_id = (DecodeJson(body) or {}).id or repo_name
    proxy_json(
      function(data)
        local result = {}
        for _, h in ipairs(data.value or {}) do result[#result + 1] = translate_ado_hook(h) end
        return result
      end,
      fetch_json(ado_url(config.base_url ..
        "/_apis/hooks/subscriptions?publisherInputs.repository=" .. repo_id)))
  end,

  -- Users' repos --------------------------------------------------------------

  get_users_repos = function(username)
    -- Treat username as a project name in ADO
    local limit = tonumber(GetParam("per_page")) or 30
    proxy_json(
      function(data)
        local repos = {}
        local all = data.value or {}
        for i = 1, math.min(limit, #all) do repos[#repos + 1] = translate_ado_repo(all[i]) end
        return repos
      end,
      fetch_json(ado_url(repos_base(username))))
  end,

}
