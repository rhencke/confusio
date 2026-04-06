-- Azure DevOps backend handler overrides.
-- Uses Azure DevOps Git REST API.
-- config.base_url = https://dev.azure.com/{org}  (or https://{org}.visualstudio.com)
-- GitHub {owner}/{repo} maps to: owner = ADO project, repo = ADO repository name.
-- API version is appended as ?api-version=7.0 on all requests.

local auth = function()
  return make_fetch_opts("basic-colon")
end
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
  if not r then
    return {}
  end
  local proj = r.project or {}
  local branch = r.defaultBranch and r.defaultBranch:match("refs/heads/(.+)") or "main"
  return {
    id = 0,
    node_id = r.id or "",
    name = r.name or "",
    full_name = (proj.name or "") .. "/" .. (r.name or ""),
    private = r.isPrivate or false,
    owner = {
      login = proj.name or "",
      id = 0,
      node_id = proj.id or "",
      avatar_url = "",
      url = "",
      html_url = "",
      type = "Organization",
    },
    html_url = r.remoteUrl or "",
    description = r.project and r.project.description or nil,
    fork = false,
    url = "",
    clone_url = r.remoteUrl or "",
    homepage = "",
    size = r.size or 0,
    stargazers_count = 0,
    watchers_count = 0,
    language = nil,
    has_issues = true,
    has_wiki = false,
    forks_count = 0,
    archived = false,
    disabled = r.isDisabled or false,
    open_issues_count = 0,
    default_branch = branch,
    visibility = (r.isPrivate or false) and "private" or "public",
    forks = 0,
    open_issues = 0,
    watchers = 0,
    created_at = nil,
    updated_at = nil,
    pushed_at = nil,
  }
end

-- ADO branch ref: { name, objectId, creator }
local function translate_ado_branch(b)
  if not b then
    return {}
  end
  local name = b.name and b.name:match("refs/heads/(.+)") or (b.name or "")
  return { name = name, commit = { sha = b.objectId or "", url = "" }, protected = false }
end

-- ADO commit: { commitId, comment, author, committer }
local function translate_ado_commit(c)
  if not c then
    return {}
  end
  local author = c.author or {}
  local committer = c.committer or {}
  return {
    sha = c.commitId or "",
    commit = {
      message = c.comment or "",
      author = { name = author.name or "", email = author.email or "", date = author.date or "" },
      committer = {
        name = committer.name or "",
        email = committer.email or "",
        date = committer.date or "",
      },
    },
    author = { login = author.name or "", id = 0, avatar_url = "" },
    committer = { login = committer.name or "", id = 0, avatar_url = "" },
  }
end

-- ADO tag ref: same shape as branch but name is refs/tags/...
local function translate_ado_tag(t)
  if not t then
    return {}
  end
  local name = t.name and t.name:match("refs/tags/(.+)") or (t.name or "")
  return { name = name, commit = { sha = t.objectId or "", url = "" } }
end

-- Work items (issues) ---------------------------------------------------------
-- ADO Boards: work items are project-scoped.
-- GitHub {owner}/{repo}/issues → ADO project {owner} work items (repo not used).
-- List:   POST /{owner}/_apis/wit/wiql        → { workItems: [{id,url}] }
-- Fetch:  GET  /{owner}/_apis/wit/workitems?ids=...&$expand=all
-- Single: GET  /{owner}/_apis/wit/workitems/{id}?$expand=all
-- Create: POST /{owner}/_apis/wit/workitems/$Issue  (json-patch+json)
-- Comments: GET/POST /{owner}/_apis/wit/workitems/{id}/comments

local function ado_state_to_github(state)
  local s = (state or ""):lower()
  if s == "closed" or s == "resolved" or s == "done" or s == "inactive" then
    return "closed"
  end
  return "open"
end

local function translate_ado_workitem(w)
  if not w then
    return {}
  end
  local fields = w.fields or {}
  local created_by = fields["System.CreatedBy"] or {}
  local id = w.id or 0
  return {
    id = id,
    node_id = "",
    number = id,
    title = fields["System.Title"] or "",
    body = fields["System.Description"] or "",
    state = ado_state_to_github(fields["System.State"]),
    user = {
      login = created_by.uniqueName or created_by.displayName or "",
      id = 0,
      node_id = "",
      avatar_url = "",
      type = "User",
    },
    assignees = {},
    labels = {},
    milestone = nil,
    created_at = fields["System.CreatedDate"] or "",
    updated_at = fields["System.ChangedDate"] or "",
    closed_at = nil,
    html_url = "",
  }
end

local function translate_ado_workitem_comment(c)
  if not c then
    return {}
  end
  local revised_by = c.revisedBy or {}
  return {
    id = c.id or 0,
    node_id = "",
    url = "",
    body = c.text or "",
    user = {
      login = revised_by.uniqueName or revised_by.displayName or "",
      id = 0,
      node_id = "",
      avatar_url = "",
      type = "User",
    },
    created_at = c.revisedDate or "",
    updated_at = c.revisedDate or "",
    html_url = "",
  }
end

-- Teams -----------------------------------------------------------------------
-- ADO: GET /_apis/projects/{project}/teams (project = GitHub org)

local function ado_team_slug(name)
  return (name or ""):lower():gsub("[^%w%-]", "-")
end

local function translate_ado_team(t)
  if not t then
    return {}
  end
  return {
    id = 0,
    node_id = t.id or "",
    name = t.name or "",
    slug = ado_team_slug(t.name),
    description = t.description or "",
    privacy = "closed",
    notification_setting = "notifications_enabled",
    permission = "pull",
    members_url = "",
    repositories_url = "",
    parent = nil,
  }
end

local function ado_find_team(org, slug)
  local ok, status, _, body =
    fetch_json(ado_url(config.base_url .. "/_apis/projects/" .. org .. "/teams"))
  if not ok or status ~= 200 then
    return nil
  end
  for _, t in ipairs((DecodeJson(body) or {}).value or {}) do
    if ado_team_slug(t.name) == slug then
      return t
    end
  end
  return nil
end

-- Fetch a team directly by its ADO GUID (uses /_apis/teams/{id}).
-- Returns the team object (which includes projectName) or nil on failure.
local function ado_get_team_by_id(team_id)
  local ok, status, _, body = fetch_json(ado_url(config.base_url .. "/_apis/teams/" .. team_id))
  if not ok or status ~= 200 then
    return nil
  end
  return DecodeJson(body) or nil
end

-- Fetch members for a team given its GUID and project name.
-- Returns the parsed response body or nil on failure.
local function ado_fetch_team_members(proj, team_id)
  local ok, status, _, body = fetch_json(
    ado_url(config.base_url .. "/_apis/projects/" .. proj .. "/teams/" .. team_id .. "/members")
  )
  if not ok or status ~= 200 then
    return nil
  end
  return DecodeJson(body) or nil
end

-- ADO webhook: { id, url, publisherInputs: { repository }, status, eventType }
local function translate_ado_hook(h)
  if not h then
    return {}
  end
  return {
    id = h.id or 0,
    name = "web",
    active = h.status == "enabled",
    events = { h.eventType or "" },
    config = { url = (h.consumerInputs and h.consumerInputs.url) or "", content_type = "json" },
    created_at = h.createdDate,
    updated_at = h.modifiedDate,
  }
end

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, ado_url(config.base_url .. "/_apis/connectionData"), auth())
    if ok and status == 200 then
      respond_json(200, "OK", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,
  get_repo = function(owner, repo_name)
    proxy_json(translate_ado_repo, fetch_json(ado_url(repos_base(owner) .. "/" .. repo_name)))
  end,

  patch_repo = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
    local a = {}
    if req.description ~= nil then
      a.project = { description = req.description }
    end
    if req.default_branch then
      a.defaultBranch = "refs/heads/" .. req.default_branch
    end
    proxy_json(
      translate_ado_repo,
      fetch_json(ado_url(repos_base(owner) .. "/" .. repo_name), "PATCH", EncodeJson(a))
    )
  end,

  delete_repo = function(owner, repo_name)
    -- Must resolve repo ID first
    local ok, status, _, body = fetch_json(ado_url(repos_base(owner) .. "/" .. repo_name))
    if not ok or status ~= 200 then
      respond_json(ok and status or 503, "Error", {})
      return
    end
    local repo = DecodeJson(body) or {}
    local repo_id = repo.id or repo_name
    local dopts = auth() or {}
    dopts.method = "DELETE"
    local dok, dstatus = pcall(Fetch, ado_url(repos_base(owner) .. "/" .. repo_id), dopts)
    if dok and (dstatus == 204 or dstatus == 200) then
      SetStatus(204, "No Content")
    elseif dok then
      respond_json(dstatus, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  get_user_repos = function()
    -- ADO: list repos across all projects
    local limit = tonumber(GetParam("per_page")) or 30
    local url = ado_url(config.base_url .. "/_apis/git/repositories")
    proxy_json(function(data)
      local repos = {}
      local all = data.value or {}
      for i = 1, math.min(limit, #all) do
        repos[#repos + 1] = translate_ado_repo(all[i])
      end
      return repos
    end, fetch_json(url))
  end,

  post_user_repos = function()
    -- ADO requires a project; use a "default" project or from request
    local req = DecodeJson(GetBody() or "{}")
    local proj = req.organization or "default"
    local a = { name = req.name or "", project = { name = proj } }
    proxy_json_created(
      translate_ado_repo,
      fetch_json(ado_url(repos_base(proj)), "POST", EncodeJson(a))
    )
  end,

  get_org_repos = function(owner)
    local limit = tonumber(GetParam("per_page")) or 30
    local url = ado_url(repos_base(owner))
    proxy_json(function(data)
      local repos = {}
      local all = data.value or {}
      for i = 1, math.min(limit, #all) do
        repos[#repos + 1] = translate_ado_repo(all[i])
      end
      return repos
    end, fetch_json(url))
  end,

  post_org_repos = function(owner)
    local req = DecodeJson(GetBody() or "{}")
    local a = { name = req.name or "", project = { name = owner } }
    proxy_json_created(
      translate_ado_repo,
      fetch_json(ado_url(repos_base(owner)), "POST", EncodeJson(a))
    )
  end,

  -- Branches ------------------------------------------------------------------
  -- ADO: GET /{owner}/_apis/git/repositories/{repo}/refs?filter=heads

  get_repo_branches = function(owner, repo_name)
    local limit = GetParam("per_page") or "30"
    local url =
      ado_url(repos_base(owner) .. "/" .. repo_name .. "/refs?filter=heads&$top=" .. limit)
    proxy_json(function(data)
      local result = {}
      for _, b in ipairs(data.value or {}) do
        result[#result + 1] = translate_ado_branch(b)
      end
      return result
    end, fetch_json(url))
  end,

  get_repo_branch = function(owner, repo_name, branch)
    local url = ado_url(repos_base(owner) .. "/" .. repo_name .. "/refs?filter=heads/" .. branch)
    proxy_json(function(data)
      local b = (data.value or {})[1]
      return b and translate_ado_branch(b) or {}
    end, fetch_json(url))
  end,

  -- Tags ----------------------------------------------------------------------
  -- ADO: GET /{owner}/_apis/git/repositories/{repo}/refs?filter=tags

  get_repo_tags = function(owner, repo_name)
    local url = ado_url(repos_base(owner) .. "/" .. repo_name .. "/refs?filter=tags")
    proxy_json(function(data)
      local result = {}
      for _, t in ipairs(data.value or {}) do
        result[#result + 1] = translate_ado_tag(t)
      end
      return result
    end, fetch_json(url))
  end,

  -- Commits -------------------------------------------------------------------
  -- ADO: GET /{owner}/_apis/git/repositories/{repo}/commits

  get_repo_commits = function(owner, repo_name)
    local limit = GetParam("per_page") or "30"
    local page = tonumber(GetParam("page")) or 1
    local skip = (page - 1) * (tonumber(limit) or 30)
    local ref = GetParam("sha") or ""
    local url = ado_url(
      repos_base(owner) .. "/" .. repo_name .. "/commits?$top=" .. limit .. "&$skip=" .. skip
    )
    if ref ~= "" then
      url = url .. "&searchCriteria.itemVersion.version=" .. ref
    end
    proxy_json(function(data)
      local result = {}
      for _, c in ipairs(data.value or {}) do
        result[#result + 1] = translate_ado_commit(c)
      end
      return result
    end, fetch_json(url))
  end,

  get_repo_commit = function(owner, repo_name, ref)
    proxy_json(
      translate_ado_commit,
      fetch_json(ado_url(repos_base(owner) .. "/" .. repo_name .. "/commits/" .. ref))
    )
  end,

  -- Contents ------------------------------------------------------------------
  -- ADO: GET /{owner}/_apis/git/repositories/{repo}/items?path={path}&version={ref}

  get_repo_readme = function(owner, repo_name)
    local ref = GetParam("ref") or ""
    local candidates = { "README.md", "README", "readme.md", "README.rst" }
    for _, fname in ipairs(candidates) do
      local url = ado_url(
        repos_base(owner)
          .. "/"
          .. repo_name
          .. "/items?path=/"
          .. fname
          .. (ref ~= "" and ("&version=" .. ref) or "")
      )
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
    local url = ado_url(
      repos_base(owner)
        .. "/"
        .. repo_name
        .. "/items?path=/"
        .. path
        .. (ref ~= "" and ("&version=" .. ref) or "")
    )
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

  -- Archive -------------------------------------------------------------------

  get_repo_tarball = function(owner, repo_name, ref)
    SetStatus(302, "Found")
    SetHeader(
      "Location",
      ado_url(
        repos_base(owner)
          .. "/"
          .. repo_name
          .. "/items?path=/&$format=zip&versionDescriptor.version="
          .. ref
      )
    )
    Write("")
  end,

  get_repo_zipball = function(owner, repo_name, ref)
    SetStatus(302, "Found")
    SetHeader(
      "Location",
      ado_url(
        repos_base(owner)
          .. "/"
          .. repo_name
          .. "/items?path=/&$format=zip&versionDescriptor.version="
          .. ref
      )
    )
    Write("")
  end,

  -- Forks ---------------------------------------------------------------------
  -- ADO: GET /{owner}/_apis/git/repositories/{repo}/forks/{project}

  get_repo_forks = function(owner, repo_name)
    proxy_json(function(data)
      local result = {}
      for _, r in ipairs(data.value or {}) do
        result[#result + 1] = translate_ado_repo(r)
      end
      return result
    end, fetch_json(ado_url(repos_base(owner) .. "/" .. repo_name .. "/forks/" .. owner)))
  end,

  post_repo_forks = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
    local target = req.organization or owner
    proxy_json_created(
      translate_ado_repo,
      fetch_json(
        ado_url(repos_base(owner) .. "/" .. repo_name .. "/forks"),
        "POST",
        EncodeJson({ targetProjectId = target })
      )
    )
  end,

  -- Webhooks ------------------------------------------------------------------
  -- ADO: GET /_apis/hooks/subscriptions?publisherInputs.repository={repo_id}

  get_repo_hooks = function(owner, repo_name)
    -- First resolve repo ID
    local ok, status, _, body = fetch_json(ado_url(repos_base(owner) .. "/" .. repo_name))
    if not ok or status ~= 200 then
      respond_json(ok and status or 503, "Error", {})
      return
    end
    local repo_id = (DecodeJson(body) or {}).id or repo_name
    proxy_json(
      function(data)
        local result = {}
        for _, h in ipairs(data.value or {}) do
          result[#result + 1] = translate_ado_hook(h)
        end
        return result
      end,
      fetch_json(
        ado_url(
          config.base_url .. "/_apis/hooks/subscriptions?publisherInputs.repository=" .. repo_id
        )
      )
    )
  end,

  -- Users' repos --------------------------------------------------------------

  get_users_repos = function(username)
    -- Treat username as a project name in ADO
    local limit = tonumber(GetParam("per_page")) or 30
    proxy_json(function(data)
      local repos = {}
      local all = data.value or {}
      for i = 1, math.min(limit, #all) do
        repos[#repos + 1] = translate_ado_repo(all[i])
      end
      return repos
    end, fetch_json(ado_url(repos_base(username))))
  end,

  -- Teams ---------------------------------------------------------------------

  get_org_teams = function(org)
    proxy_json(function(data)
      local result = {}
      for _, t in ipairs(data.value or {}) do
        result[#result + 1] = translate_ado_team(t)
      end
      return result
    end, fetch_json(ado_url(config.base_url .. "/_apis/projects/" .. org .. "/teams")))
  end,

  post_org_teams = function(org)
    local req = DecodeJson(GetBody() or "{}")
    local a = { name = req.name or "", description = req.description or "" }
    proxy_json_created(
      translate_ado_team,
      fetch_json(
        ado_url(config.base_url .. "/_apis/projects/" .. org .. "/teams"),
        "POST",
        EncodeJson(a)
      )
    )
  end,

  get_org_team = function(org, slug)
    local t = ado_find_team(org, slug)
    if not t then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    respond_json(200, "OK", translate_ado_team(t))
  end,

  patch_org_team = function(org, slug)
    local t = ado_find_team(org, slug)
    if not t then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    local req = DecodeJson(GetBody() or "{}")
    local a = {}
    if req.name then
      a.name = req.name
    end
    if req.description then
      a.description = req.description
    end
    proxy_json(
      translate_ado_team,
      fetch_json(
        ado_url(config.base_url .. "/_apis/projects/" .. org .. "/teams/" .. t.id),
        "PATCH",
        EncodeJson(a)
      )
    )
  end,

  delete_org_team = function(org, slug)
    local t = ado_find_team(org, slug)
    if not t then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    local dopts = auth() or {}
    dopts.method = "DELETE"
    local ok, status = pcall(
      Fetch,
      ado_url(config.base_url .. "/_apis/projects/" .. org .. "/teams/" .. t.id),
      dopts
    )
    if ok and (status == 204 or status == 200) then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  get_org_team_invitations = function()
    Write("[]")
  end,

  get_org_team_members = function(org, slug)
    local t = ado_find_team(org, slug)
    if not t then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    proxy_json(
      function(data)
        local result = {}
        for _, m in ipairs(data.value or {}) do
          local ident = m.identity or {}
          result[#result + 1] = {
            login = ident.uniqueName or ident.displayName or "",
            id = 0,
            node_id = ident.id or "",
            avatar_url = ident.imageUrl or "",
            type = "User",
          }
        end
        return result
      end,
      fetch_json(
        ado_url(config.base_url .. "/_apis/projects/" .. org .. "/teams/" .. t.id .. "/members")
      )
    )
  end,

  get_org_team_membership = function(org, slug, username)
    local t = ado_find_team(org, slug)
    if not t then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    local ok, status, _, body = fetch_json(
      ado_url(config.base_url .. "/_apis/projects/" .. org .. "/teams/" .. t.id .. "/members")
    )
    if not ok or status ~= 200 then
      respond_json(ok and status or 503, "Error", {})
      return
    end
    for _, m in ipairs((DecodeJson(body) or {}).value or {}) do
      local ident = m.identity or {}
      local name = ident.uniqueName or ident.displayName or ""
      local short = name:match("^([^@]+)") or name
      if name == username or short == username then
        respond_json(200, "OK", {
          url = "",
          role = m.isTeamAdmin and "maintainer" or "member",
          state = "active",
        })
        return
      end
    end
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  -- ADO team membership is managed through security groups (no simple add/remove
  -- in the Teams REST API). Forward as best-effort and pass through the response.
  put_org_team_membership = function(org, slug, username)
    local t = ado_find_team(org, slug)
    if not t then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    local req = DecodeJson(GetBody() or "{}")
    local role = req.role or "member"
    local ok, status = fetch_json(
      ado_url(config.base_url .. "/_apis/projects/" .. org .. "/teams/" .. t.id .. "/members"),
      "POST",
      EncodeJson({ id = username })
    )
    -- ADO may return 400/404 here if the username isn't an AAD object ID; surface gracefully.
    if ok and status == 200 then
      respond_json(200, "OK", { url = "", role = role, state = "active" })
    elseif ok and (status == 204 or status == 201) then
      respond_json(200, "OK", { url = "", role = role, state = "active" })
    else
      respond_json(200, "OK", { url = "", role = role, state = "pending" })
    end
  end,

  delete_org_team_membership = function(org, slug, username)
    local t = ado_find_team(org, slug)
    if not t then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    local dopts = auth() or {}
    dopts.method = "DELETE"
    pcall(
      Fetch,
      ado_url(
        config.base_url .. "/_apis/projects/" .. org .. "/teams/" .. t.id .. "/members/" .. username
      ),
      dopts
    )
    SetStatus(204, "No Content")
  end,

  -- ADO does not model team-repo associations at this level; return empty list.
  get_org_team_repos = function()
    Write("[]")
  end,
  -- PUT/DELETE team repo not supported in ADO model.
  put_org_team_repo = function()
    respond_json(
      422,
      "Unprocessable Entity",
      { message = "Team repository associations are not supported by Azure DevOps" }
    )
  end,
  delete_org_team_repo = function()
    SetStatus(204, "No Content")
  end,

  get_org_team_children = function()
    Write("[]")
  end,

  -- Legacy team-by-id API (/teams/{team_id}) ----------------------------------
  -- team_id is the ADO team GUID (e.g. "team-abc123").

  get_user_teams = function()
    proxy_json(function(data)
      local result = {}
      for _, t in ipairs(data.value or {}) do
        result[#result + 1] = translate_ado_team(t)
      end
      return result
    end, fetch_json(ado_url(config.base_url .. "/_apis/teams")))
  end,

  get_team = function(team_id)
    local t = ado_get_team_by_id(team_id)
    if not t then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    respond_json(200, "OK", translate_ado_team(t))
  end,

  patch_team = function(team_id)
    local t = ado_get_team_by_id(team_id)
    if not t then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    local req = DecodeJson(GetBody() or "{}")
    local a = {}
    if req.name then
      a.name = req.name
    end
    if req.description then
      a.description = req.description
    end
    proxy_json(
      translate_ado_team,
      fetch_json(
        ado_url(
          config.base_url .. "/_apis/projects/" .. (t.projectName or "") .. "/teams/" .. team_id
        ),
        "PATCH",
        EncodeJson(a)
      )
    )
  end,

  delete_team = function(team_id)
    local t = ado_get_team_by_id(team_id)
    if not t then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    local dopts = auth() or {}
    dopts.method = "DELETE"
    local ok, status = pcall(
      Fetch,
      ado_url(
        config.base_url .. "/_apis/projects/" .. (t.projectName or "") .. "/teams/" .. team_id
      ),
      dopts
    )
    if ok and (status == 204 or status == 200) then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  get_team_invitations = function()
    Write("[]")
  end,

  get_team_members = function(team_id)
    local t = ado_get_team_by_id(team_id)
    if not t then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    local data = ado_fetch_team_members(t.projectName or "", team_id)
    if not data then
      respond_json(503, "Service Unavailable", {})
      return
    end
    local result = {}
    for _, m in ipairs(data.value or {}) do
      local ident = m.identity or {}
      result[#result + 1] = {
        login = ident.uniqueName or ident.displayName or "",
        id = 0,
        node_id = ident.id or "",
        avatar_url = ident.imageUrl or "",
        type = "User",
      }
    end
    respond_json(200, "OK", result)
  end,

  get_team_member = function(team_id, username)
    local t = ado_get_team_by_id(team_id)
    if not t then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    local data = ado_fetch_team_members(t.projectName or "", team_id)
    if not data then
      respond_json(503, "Service Unavailable", {})
      return
    end
    for _, m in ipairs(data.value or {}) do
      local ident = m.identity or {}
      local name = ident.uniqueName or ident.displayName or ""
      local short = name:match("^([^@]+)") or name
      if name == username or short == username then
        SetStatus(204, "No Content")
        return
      end
    end
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  put_team_member = function(team_id, username)
    local t = ado_get_team_by_id(team_id)
    if not t then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    fetch_json(
      ado_url(
        config.base_url
          .. "/_apis/projects/"
          .. (t.projectName or "")
          .. "/teams/"
          .. team_id
          .. "/members"
      ),
      "POST",
      EncodeJson({ id = username })
    )
    SetStatus(204, "No Content")
  end,

  delete_team_member = function(team_id, username)
    local t = ado_get_team_by_id(team_id)
    if not t then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    local dopts = auth() or {}
    dopts.method = "DELETE"
    pcall(
      Fetch,
      ado_url(
        config.base_url
          .. "/_apis/projects/"
          .. (t.projectName or "")
          .. "/teams/"
          .. team_id
          .. "/members/"
          .. username
      ),
      dopts
    )
    SetStatus(204, "No Content")
  end,

  get_team_membership = function(team_id, username)
    local t = ado_get_team_by_id(team_id)
    if not t then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    local data = ado_fetch_team_members(t.projectName or "", team_id)
    if not data then
      respond_json(503, "Service Unavailable", {})
      return
    end
    for _, m in ipairs(data.value or {}) do
      local ident = m.identity or {}
      local name = ident.uniqueName or ident.displayName or ""
      local short = name:match("^([^@]+)") or name
      if name == username or short == username then
        respond_json(200, "OK", {
          url = "",
          role = m.isTeamAdmin and "maintainer" or "member",
          state = "active",
        })
        return
      end
    end
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  put_team_membership = function(team_id, username)
    local t = ado_get_team_by_id(team_id)
    if not t then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    local req = DecodeJson(GetBody() or "{}")
    local role = req.role or "member"
    local ok, status = fetch_json(
      ado_url(
        config.base_url
          .. "/_apis/projects/"
          .. (t.projectName or "")
          .. "/teams/"
          .. team_id
          .. "/members"
      ),
      "POST",
      EncodeJson({ id = username })
    )
    if ok and (status == 200 or status == 201 or status == 204) then
      respond_json(200, "OK", { url = "", role = role, state = "active" })
    else
      respond_json(200, "OK", { url = "", role = role, state = "pending" })
    end
  end,

  delete_team_membership = function(team_id, username)
    local t = ado_get_team_by_id(team_id)
    if not t then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    local dopts = auth() or {}
    dopts.method = "DELETE"
    pcall(
      Fetch,
      ado_url(
        config.base_url
          .. "/_apis/projects/"
          .. (t.projectName or "")
          .. "/teams/"
          .. team_id
          .. "/members/"
          .. username
      ),
      dopts
    )
    SetStatus(204, "No Content")
  end,

  get_team_repos = function()
    Write("[]")
  end,
  get_team_repo = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,
  put_team_repo = function()
    respond_json(
      422,
      "Unprocessable Entity",
      { message = "Team repository associations are not supported by Azure DevOps" }
    )
  end,
  delete_team_repo = function()
    SetStatus(204, "No Content")
  end,
  get_team_children = function()
    Write("[]")
  end,

  -- Issues (Azure Boards work items) -----------------------------------------

  get_repo_issues = function(owner, _repo_name)
    local state = GetParam("state") or "open"
    local limit = tonumber(GetParam("per_page")) or 30
    local where = "[System.TeamProject] = '" .. owner .. "'"
    if state == "closed" then
      where = where .. " AND [System.State] IN ('Closed','Resolved','Done')"
    elseif state ~= "all" then
      where = where .. " AND [System.State] NOT IN ('Closed','Resolved','Done')"
    end
    local wiql_body = EncodeJson({
      query = "SELECT [System.Id] FROM WorkItems WHERE "
        .. where
        .. " ORDER BY [System.ChangedDate] DESC",
    })
    local ok, status, _, body = fetch_json(
      ado_url(config.base_url .. "/" .. owner .. "/_apis/wit/wiql?$top=" .. limit),
      "POST",
      wiql_body
    )
    if not ok then
      respond_json(503, "Service Unavailable", {})
      return
    end
    if status ~= 200 then
      respond_json(status, "Error", {})
      return
    end
    local refs = (DecodeJson(body) or {}).workItems or {}
    if #refs == 0 then
      Write("[]")
      return
    end
    local ids = {}
    for i = 1, math.min(limit, #refs) do
      ids[#ids + 1] = tostring(refs[i].id or "")
    end
    proxy_json(
      function(data)
        local result = {}
        for _, w in ipairs(data.value or {}) do
          result[#result + 1] = translate_ado_workitem(w)
        end
        return result
      end,
      fetch_json(
        ado_url(
          config.base_url
            .. "/"
            .. owner
            .. "/_apis/wit/workitems?ids="
            .. table.concat(ids, ",")
            .. "&$expand=all"
        )
      )
    )
  end,

  get_repo_issue = function(owner, _repo_name, issue_number)
    proxy_json(
      translate_ado_workitem,
      fetch_json(
        ado_url(
          config.base_url
            .. "/"
            .. owner
            .. "/_apis/wit/workitems/"
            .. issue_number
            .. "?$expand=all"
        )
      )
    )
  end,

  post_repo_issues = function(owner, _repo_name)
    local req = DecodeJson(GetBody() or "{}")
    local patch = {
      { op = "add", path = "/fields/System.Title", value = req.title or "" },
    }
    if req.body then
      patch[#patch + 1] = { op = "add", path = "/fields/System.Description", value = req.body }
    end
    local opts = auth() or {}
    opts.method = "POST"
    opts.body = EncodeJson(patch)
    opts.headers = opts.headers or {}
    opts.headers["Content-Type"] = "application/json-patch+json"
    local cok, cstatus, _, cbody =
      pcall(Fetch, ado_url(config.base_url .. "/" .. owner .. "/_apis/wit/workitems/$Issue"), opts)
    if cok and (cstatus == 200 or cstatus == 201) then
      respond_json(201, "Created", translate_ado_workitem(DecodeJson(cbody) or {}))
    elseif cok then
      respond_json(cstatus, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  patch_repo_issue = function(owner, _repo_name, issue_number)
    local req = DecodeJson(GetBody() or "{}")
    local patch = {}
    if req.title ~= nil then
      patch[#patch + 1] = { op = "replace", path = "/fields/System.Title", value = req.title }
    end
    if req.body ~= nil then
      patch[#patch + 1] = { op = "replace", path = "/fields/System.Description", value = req.body }
    end
    if req.state == "closed" then
      patch[#patch + 1] = { op = "replace", path = "/fields/System.State", value = "Closed" }
    elseif req.state == "open" then
      patch[#patch + 1] = { op = "replace", path = "/fields/System.State", value = "Active" }
    end
    if #patch == 0 then
      proxy_json(
        translate_ado_workitem,
        fetch_json(
          ado_url(
            config.base_url
              .. "/"
              .. owner
              .. "/_apis/wit/workitems/"
              .. issue_number
              .. "?$expand=all"
          )
        )
      )
      return
    end
    local opts = auth() or {}
    opts.method = "PATCH"
    opts.body = EncodeJson(patch)
    opts.headers = opts.headers or {}
    opts.headers["Content-Type"] = "application/json-patch+json"
    local pok, pstatus, _, pbody = pcall(
      Fetch,
      ado_url(config.base_url .. "/" .. owner .. "/_apis/wit/workitems/" .. issue_number),
      opts
    )
    if pok and pstatus == 200 then
      respond_json(200, "OK", translate_ado_workitem(DecodeJson(pbody) or {}))
    elseif pok then
      respond_json(pstatus, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  get_issue_comments = function(owner, _repo_name, issue_number)
    proxy_json(
      function(data)
        local result = {}
        for _, c in ipairs(data.value or {}) do
          result[#result + 1] = translate_ado_workitem_comment(c)
        end
        return result
      end,
      fetch_json(
        ado_url(
          config.base_url .. "/" .. owner .. "/_apis/wit/workitems/" .. issue_number .. "/comments"
        )
      )
    )
  end,

  post_issue_comment = function(owner, _repo_name, issue_number)
    local req = DecodeJson(GetBody() or "{}")
    proxy_json_created(
      translate_ado_workitem_comment,
      fetch_json(
        ado_url(
          config.base_url .. "/" .. owner .. "/_apis/wit/workitems/" .. issue_number .. "/comments"
        ),
        "POST",
        EncodeJson({ text = req.body or "" })
      )
    )
  end,
}
