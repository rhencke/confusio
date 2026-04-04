-- Pagure backend handler overrides.
-- Uses Pagure REST API at /api/0/.
-- Repos are addressed as /api/0/{namespace}/{repo} (owner = namespace/username).

local base = function() return config.base_url .. "/api/0" end
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

-- Map a Pagure project object to GitHub repo format.
local function translate_pagure_repo(r)
  if not r then return {} end
  local user = r.user or {}
  local ns = r.namespace or ""
  local owner_login = ns ~= "" and ns or user.name or ""
  return {
    id                = r.id or 0,
    node_id           = "",
    name              = r.name,
    full_name         = r.fullname or (owner_login .. "/" .. (r.name or "")),
    private           = r.private or false,
    owner             = {
      login      = owner_login,
      id         = 0,
      node_id    = "",
      avatar_url = "",
      url        = "",
      html_url   = config.base_url .. "/" .. (user.url_path or user.name or ""),
      type       = ns ~= "" and "Organization" or "User",
    },
    html_url          = config.base_url .. "/" .. (r.url_path or ""),
    description       = r.description,
    fork              = r.parent ~= nil,
    url               = "",
    clone_url         = r.full_url or "",
    homepage          = r.url or "",
    size              = 0,
    stargazers_count  = r.stars or 0,
    watchers_count    = 0,
    language          = nil,
    has_issues        = true,
    has_wiki          = r.settings and r.settings.wiki_enabled or false,
    forks_count       = r.forks_count or 0,
    archived          = r.close_status ~= nil and r.close_status ~= "",
    disabled          = false,
    open_issues_count = 0,
    default_branch    = r.default_branch or "main",
    visibility        = (r.private or false) and "private" or "public",
    forks             = r.forks_count or 0,
    open_issues       = 0,
    watchers          = 0,
    created_at        = r.date_created,
    updated_at        = r.date_modified,
    pushed_at         = r.date_modified,
  }
end

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, base() .. "/version", auth())
    if ok and status == 200 then respond_json(200, "OK", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_repo = function(owner, repo_name)
    proxy_json(translate_pagure_repo,
      fetch_json(base() .. "/" .. owner .. "/" .. repo_name))
  end,

  patch_repo = function(owner, repo_name)
    -- Pagure: update project description via POST /api/0/{owner}/{repo}/modify
    local url = base() .. "/" .. owner .. "/" .. repo_name .. "/modify"
    local req = DecodeJson(GetBody() or "{}")
    local pg = {}
    if req.description then pg.description = req.description end
    if req.private ~= nil then pg.private = req.private end
    -- Pagure /modify returns { "repo": {...} }
    proxy_json(
      function(resp) return translate_pagure_repo(resp.repo or resp) end,
      fetch_json(url, "POST", EncodeJson(pg)))
  end,

  delete_repo = function(owner, repo_name)
    -- Pagure: delete project via POST /api/0/{owner}/{repo}/delete
    local url = base() .. "/" .. owner .. "/" .. repo_name .. "/delete"
    local ok, status = fetch_json(url, "POST", "{}")
    if ok and (status == 200 or status == 204) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_user_repos = function()
    -- Pagure: /api/0/projects?author={user} — need to know the authenticated user first
    local ok, status, _, ubody = fetch_json(base() .. "/-/whoami")
    if not ok or status ~= 200 then respond_json(503, "Service Unavailable", {}); return end
    local me = DecodeJson(ubody)
    local username = me.username or me.name or ""
    proxy_json(
      function(data)
        local projects = data.projects or {}
        for i, p in ipairs(projects) do projects[i] = translate_pagure_repo(p) end
        return projects
      end,
      fetch_json(append_page_params(base() .. "/user/" .. username .. "/projects",
        { per_page = "per_page", page = "page" })))
  end,

  post_user_repos = function()
    -- Pagure: create project via POST /api/0/new
    local req = DecodeJson(GetBody() or "{}")
    local pg = {
      name        = req.name,
      description = req.description or "",
      private     = req.private or false,
    }
    proxy_json_created(
      function(resp) return translate_pagure_repo(resp.project or resp) end,
      fetch_json(base() .. "/new", "POST", EncodeJson(pg)))
  end,

  get_org_repos = function(namespace)
    -- Pagure: list projects in a namespace/group
    proxy_json(
      function(data)
        local projects = data.projects or {}
        for i, p in ipairs(projects) do projects[i] = translate_pagure_repo(p) end
        return projects
      end,
      fetch_json(append_page_params(base() .. "/projects?namespace=" .. namespace,
        { per_page = "per_page", page = "page" })))
  end,

  post_org_repos = function(namespace)
    -- Pagure: create project with namespace
    local req = DecodeJson(GetBody() or "{}")
    local pg = {
      name        = req.name,
      description = req.description or "",
      private     = req.private or false,
      namespace   = namespace,
    }
    proxy_json_created(
      function(resp) return translate_pagure_repo(resp.project or resp) end,
      fetch_json(base() .. "/new", "POST", EncodeJson(pg)))
  end,

  get_repo_topics = function(owner, repo_name)
    -- Pagure uses "tags" not topics — return them as names
    proxy_json(
      function(r) return { names = r.tags or {} } end,
      fetch_json(base() .. "/" .. owner .. "/" .. repo_name))
  end,

  put_repo_topics = function(owner, repo_name)
    -- Pagure: set tags via POST /api/0/{owner}/{repo}/modify with tags field
    local url = base() .. "/" .. owner .. "/" .. repo_name .. "/modify"
    local req = DecodeJson(GetBody() or "{}")
    proxy_json(
      function(resp)
        local r = resp.repo or resp
        return { names = r.tags or {} }
      end,
      fetch_json(url, "POST", EncodeJson({ tags = req.names or {} })))
  end,

  get_repo_tags = function(owner, repo_name)
    -- Pagure returns { "tags": ["v1.0", ...] } — just tag names, no commit info
    proxy_json(
      function(data)
        local tags = {}
        for _, name in ipairs(data.tags or {}) do
          tags[#tags + 1] = { name = name, commit = { sha = "", url = "" } }
        end
        return tags
      end,
      fetch_json(base() .. "/" .. owner .. "/" .. repo_name .. "/git/tags"))
  end,

}
