-- Azure DevOps backend handler overrides.
-- Uses Azure DevOps Git REST API.
-- config.base_url = https://dev.azure.com/{org}  (or https://{org}.visualstudio.com)
-- GitHub {owner}/{repo} maps to: owner = ADO project, repo = ADO repository name.
-- API version is appended as ?api-version=7.0 on all requests.

local auth = function()
  return make_fetch_opts("basic-colon")
end
local API_VER = "api-version=7.0"
local fetch_json = make_backend_transport("basic-colon").fetch_json

local function repos_base(owner)
  return config.base_url .. "/" .. owner .. "/_apis/git/repositories"
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

-- ADO git ref (used by git database endpoints): { name, objectId }
local function translate_ado_ref(r)
  if not r then
    return {}
  end
  return {
    ref = r.name or "",
    node_id = "",
    url = "",
    object = { type = "commit", sha = r.objectId or "", url = "" },
  }
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
  if s == "closed" or s == "resolved" or s == "done" or s == "inactive" or s == "removed" then
    return "closed"
  end
  return "open"
end

local function ado_identity_login(u)
  if type(u) == "string" then
    return u
  end
  u = u or {}
  return u.uniqueName or u.displayName or ""
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
      login = ado_identity_login(created_by),
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

-- Checks (via ADO git commit statuses) ---------------------------------------
--
-- GitHub Check Runs map onto ADO git commit statuses.  ADO does not have a
-- concept of a check run independent of a commit SHA, so:
--   • POST check-runs and GET commits/{ref}/check-runs work natively.
--   • GET/PATCH by check_run_id cannot be reversed without the SHA;
--     those endpoints return a minimal stub.
--   • Check Suites have no ADO equivalent; all suite endpoints are stubs.
--   • Annotations are always empty.
--
-- Status mapping (GitHub → ADO):
--   queued/in_progress       → pending
--   completed/success        → succeeded
--   completed/failure        → failed
--   completed/neutral/skipped → succeeded
--   completed/(other)        → error
--
-- Status mapping (ADO → GitHub):
--   pending        → status=in_progress, conclusion=null
--   succeeded      → status=completed,   conclusion=success
--   failed         → status=completed,   conclusion=failure
--   error          → status=completed,   conclusion=failure
--   notApplicable  → status=completed,   conclusion=neutral

local function translate_ado_status_to_check_run(s)
  if not s then
    return {}
  end
  local state = s.state or "pending"
  local ado_to_gh = {
    pending = { status = "in_progress", conclusion = nil },
    succeeded = { status = "completed", conclusion = "success" },
    failed = { status = "completed", conclusion = "failure" },
    notApplicable = { status = "completed", conclusion = "neutral" },
  }
  local mapped = ado_to_gh[state] or { status = "completed", conclusion = "failure" }
  local gh_status, gh_conclusion = mapped.status, mapped.conclusion
  local ctx = s.context or {}
  return {
    id = s.id or 0,
    node_id = "",
    head_sha = "",
    name = ctx.name or "",
    status = gh_status,
    conclusion = gh_conclusion,
    started_at = s.creationDate,
    completed_at = gh_status == "completed" and (s.updatedDate or s.creationDate) or nil,
    output = {
      title = s.description or "",
      summary = s.description or "",
      text = "",
      annotations_count = 0,
      annotations_url = "",
    },
    url = s.targetUrl or "",
    html_url = s.targetUrl or "",
    details_url = s.targetUrl or "",
  }
end

local function gh_check_run_to_ado_status(req)
  local status = req.status or "queued"
  local conclusion = req.conclusion
  local gh_conclusion_to_ado = {
    success = "succeeded",
    neutral = "succeeded",
    skipped = "succeeded",
    failure = "failed",
  }
  local ado_state = status == "completed" and (gh_conclusion_to_ado[conclusion] or "error")
    or "pending"
  return EncodeJson({
    state = ado_state,
    description = (req.output and req.output.summary) or req.name or "",
    targetUrl = req.details_url or "",
    context = { name = req.name or "", genre = "continuous-integration" },
  })
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

local function ado_find_team_member(proj, team_id, username)
  local data = ado_fetch_team_members(proj, team_id)
  if not data then
    return nil, nil
  end
  for _, m in ipairs(data.value or {}) do
    local ident = m.identity or {}
    for _, name in ipairs({ ident.uniqueName or "", ident.displayName or "" }) do
      local short = name:match("^([^@]+)") or name
      if name == username or short == username then
        return true, m
      end
    end
  end
  return true, nil
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

local b = make_backend_builder()
b:rest("get_root", function()
  proxy_health_check(pcall(Fetch, ado_url(config.base_url .. "/_apis/connectionData"), auth()))
end)
b:rest("get_repo", function(owner, repo_name)
  proxy_json(translate_ado_repo, fetch_json(ado_url(repos_base(owner) .. "/" .. repo_name)))
end)

b:rest("patch_repo", function(owner, repo_name)
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
end)

b:rest("delete_repo", function(owner, repo_name)
  -- Must resolve repo ID first
  local ok, status, _, body = fetch_json(ado_url(repos_base(owner) .. "/" .. repo_name))
  if not ok or status ~= 200 then
    respond_json(ok and status or 503, {})
    return
  end
  local repo = DecodeJson(body) or {}
  local repo_id = repo.id or repo_name
  local dopts = auth() or {}
  dopts.method = "DELETE"
  proxy_204({ 200 }, pcall(Fetch, ado_url(repos_base(owner) .. "/" .. repo_id), dopts))
end)

b:rest("get_user_repos", function()
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
end)

b:rest("post_user_repos", function()
  -- ADO requires a project; use a "default" project or from request
  local req = DecodeJson(GetBody() or "{}")
  local proj = req.organization or "default"
  local a = { name = req.name or "", project = { name = proj } }
  proxy_json_created(
    translate_ado_repo,
    fetch_json(ado_url(repos_base(proj)), "POST", EncodeJson(a))
  )
end)

b:rest("get_org_repos", function(owner)
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
end)

b:rest("post_org_repos", function(owner)
  local req = DecodeJson(GetBody() or "{}")
  local a = { name = req.name or "", project = { name = owner } }
  proxy_json_created(
    translate_ado_repo,
    fetch_json(ado_url(repos_base(owner)), "POST", EncodeJson(a))
  )
end)

-- Branches ------------------------------------------------------------------
-- ADO: GET /{owner}/_apis/git/repositories/{repo}/refs?filter=heads

b:rest("get_repo_branches", function(owner, repo_name)
  local limit = GetParam("per_page") or "30"
  local url = ado_url(repos_base(owner) .. "/" .. repo_name .. "/refs?filter=heads&$top=" .. limit)
  proxy_json(function(data)
    return translate_list(translate_ado_branch, data.value)
  end, fetch_json(url))
end)

b:rest("get_repo_branch", function(owner, repo_name, branch)
  local url = ado_url(repos_base(owner) .. "/" .. repo_name .. "/refs?filter=heads/" .. branch)
  proxy_json(function(data)
    local br = (data.value or {})[1]
    return br and translate_ado_branch(br) or {}
  end, fetch_json(url))
end)

-- Tags ----------------------------------------------------------------------
-- ADO: GET /{owner}/_apis/git/repositories/{repo}/refs?filter=tags

b:rest("get_repo_tags", function(owner, repo_name)
  local url = ado_url(repos_base(owner) .. "/" .. repo_name .. "/refs?filter=tags")
  proxy_json(function(data)
    return translate_list(translate_ado_tag, data.value)
  end, fetch_json(url))
end)

-- Commits -------------------------------------------------------------------
-- ADO: GET /{owner}/_apis/git/repositories/{repo}/commits

b:rest("get_repo_commits", function(owner, repo_name)
  local limit = GetParam("per_page") or "30"
  local page = tonumber(GetParam("page")) or 1
  local skip = (page - 1) * (tonumber(limit) or 30)
  local ref = GetParam("sha") or ""
  local url =
    ado_url(repos_base(owner) .. "/" .. repo_name .. "/commits?$top=" .. limit .. "&$skip=" .. skip)
  if ref ~= "" then
    url = url .. "&searchCriteria.itemVersion.version=" .. ref
  end
  proxy_json(function(data)
    return translate_list(translate_ado_commit, data.value)
  end, fetch_json(url))
end)

b:rest("get_repo_commit", function(owner, repo_name, ref)
  proxy_json(
    translate_ado_commit,
    fetch_json(ado_url(repos_base(owner) .. "/" .. repo_name .. "/commits/" .. ref))
  )
end)

-- Contents ------------------------------------------------------------------
-- ADO: GET /{owner}/_apis/git/repositories/{repo}/items?path={path}&version={ref}

b:rest("get_repo_readme", function(owner, repo_name)
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
      respond_json(200, {
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
  respond_json(404, { message = "Not Found" })
end)

-- GET /repos/{owner}/{repo}/license
-- ADO has no license template API; fetch the LICENSE file via the items endpoint.
b:rest("get_repo_license", function(owner, repo_name)
  local candidates = { "LICENSE", "LICENSE.md", "LICENSE.txt", "COPYING" }
  for _, fname in ipairs(candidates) do
    local url = ado_url(repos_base(owner) .. "/" .. repo_name .. "/items?path=/" .. fname)
    local ok, status, _, body = fetch_json(url)
    if ok and status == 200 then
      respond_json(200, {
        type = "file",
        name = fname,
        path = fname,
        sha = "",
        size = #body,
        encoding = "base64",
        content = EncodeBase64(body),
        license = nil,
      })
      return
    end
  end
  respond_json(404, { message = "License file not found" })
end)

b:rest("get_repo_content", function(owner, repo_name, path)
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
    respond_json(200, {
      type = "file",
      name = path:match("[^/]+$") or path,
      path = path,
      sha = "",
      size = #body,
      encoding = "base64",
      content = EncodeBase64(body),
    })
  elseif ok then
    respond_json(status, { message = "Error" })
  else
    respond_json(503, {})
  end
end)

-- Archive -------------------------------------------------------------------

b:rest("get_repo_tarball", function(owner, repo_name, ref)
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
end)

b:rest("get_repo_zipball", function(owner, repo_name, ref)
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
end)

-- Forks ---------------------------------------------------------------------
-- ADO: GET /{owner}/_apis/git/repositories/{repo}/forks/{project}

b:rest("get_repo_forks", function(owner, repo_name)
  proxy_json(function(data)
    return translate_list(translate_ado_repo, data.value)
  end, fetch_json(ado_url(repos_base(owner) .. "/" .. repo_name .. "/forks/" .. owner)))
end)

b:rest("post_repo_forks", function(owner, repo_name)
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
end)

-- Webhooks ------------------------------------------------------------------
-- ADO: GET /_apis/hooks/subscriptions?publisherInputs.repository={repo_id}

b:rest("get_repo_hooks", function(owner, repo_name)
  -- First resolve repo ID
  local ok, status, _, body = fetch_json(ado_url(repos_base(owner) .. "/" .. repo_name))
  if not ok or status ~= 200 then
    respond_json(ok and status or 503, {})
    return
  end
  local repo_id = (DecodeJson(body) or {}).id or repo_name
  proxy_json(
    function(data)
      return translate_list(translate_ado_hook, data.value)
    end,
    fetch_json(
      ado_url(
        config.base_url .. "/_apis/hooks/subscriptions?publisherInputs.repository=" .. repo_id
      )
    )
  )
end)

-- Users' repos --------------------------------------------------------------

b:rest("get_users_repos", function(username)
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
end)

-- Teams ---------------------------------------------------------------------

b:rest("get_org_teams", function(org)
  proxy_json(function(data)
    return translate_list(translate_ado_team, data.value)
  end, fetch_json(ado_url(config.base_url .. "/_apis/projects/" .. org .. "/teams")))
end)

b:rest("post_org_teams", function(org)
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
end)

b:rest("get_org_team", function(org, slug)
  local t = ado_find_team(org, slug)
  if not t then
    respond_json(404, { message = "Not Found" })
    return
  end
  respond_json(200, translate_ado_team(t))
end)

b:rest("patch_org_team", function(org, slug)
  local t = ado_find_team(org, slug)
  if not t then
    respond_json(404, { message = "Not Found" })
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
end)

b:rest("delete_org_team", function(org, slug)
  local t = ado_find_team(org, slug)
  if not t then
    respond_json(404, { message = "Not Found" })
    return
  end
  local dopts = auth() or {}
  dopts.method = "DELETE"
  proxy_204(
    { 200 },
    pcall(Fetch, ado_url(config.base_url .. "/_apis/projects/" .. org .. "/teams/" .. t.id), dopts)
  )
end)

b:rest("get_org_team_members", function(org, slug)
  local t = ado_find_team(org, slug)
  if not t then
    respond_json(404, { message = "Not Found" })
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
end)

b:rest("get_org_team_membership", function(org, slug, username)
  local t = ado_find_team(org, slug)
  if not t then
    respond_json(404, { message = "Not Found" })
    return
  end
  local ok, status, _, body = fetch_json(
    ado_url(config.base_url .. "/_apis/projects/" .. org .. "/teams/" .. t.id .. "/members")
  )
  if not ok or status ~= 200 then
    respond_json(ok and status or 503, {})
    return
  end
  for _, m in ipairs((DecodeJson(body) or {}).value or {}) do
    local ident = m.identity or {}
    local name = ident.uniqueName or ident.displayName or ""
    local short = name:match("^([^@]+)") or name
    if name == username or short == username then
      respond_json(200, {
        url = "",
        role = m.isTeamAdmin and "maintainer" or "member",
        state = "active",
      })
      return
    end
  end
  respond_json(404, { message = "Not Found" })
end)

-- ADO team membership is managed through security groups (no simple add/remove
-- in the Teams REST API). Forward as best-effort and pass through the response.
b:rest("put_org_team_membership", function(org, slug, username)
  local t = ado_find_team(org, slug)
  if not t then
    respond_json(404, { message = "Not Found" })
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
    respond_json(200, { url = "", role = role, state = "active" })
  elseif ok and (status == 204 or status == 201) then
    respond_json(200, { url = "", role = role, state = "active" })
  else
    respond_json(200, { url = "", role = role, state = "pending" })
  end
end)

b:rest("delete_org_team_membership", function(org, slug, username)
  local t = ado_find_team(org, slug)
  if not t then
    respond_json(404, { message = "Not Found" })
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
end)

-- ADO does not model team-repo associations at this level; returns empty list via default.
-- PUT/DELETE team repo not supported in ADO model.
b:rest("put_org_team_repo", function()
  respond_json(
    422,
    "Unprocessable Entity",
    { message = "Team repository associations are not supported by Azure DevOps" }
  )
end)
b:rest("delete_org_team_repo", function()
  SetStatus(204, "No Content")
end)

-- Legacy team-by-id API (/teams/{team_id}) ----------------------------------
-- team_id is the ADO team GUID (e.g. "team-abc123").

b:rest("get_user_teams", function()
  proxy_json(function(data)
    local result = {}
    for _, t in ipairs(data.value or {}) do
      result[#result + 1] = translate_ado_team(t)
    end
    return result
  end, fetch_json(ado_url(config.base_url .. "/_apis/teams")))
end)

b:rest("get_team", function(team_id)
  local t = ado_get_team_by_id(team_id)
  if not t then
    respond_json(404, { message = "Not Found" })
    return
  end
  respond_json(200, translate_ado_team(t))
end)

b:rest("patch_team", function(team_id)
  local t = ado_get_team_by_id(team_id)
  if not t then
    respond_json(404, { message = "Not Found" })
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
end)

b:rest("delete_team", function(team_id)
  local t = ado_get_team_by_id(team_id)
  if not t then
    respond_json(404, { message = "Not Found" })
    return
  end
  local dopts = auth() or {}
  dopts.method = "DELETE"
  proxy_204(
    { 200 },
    pcall(
      Fetch,
      ado_url(
        config.base_url .. "/_apis/projects/" .. (t.projectName or "") .. "/teams/" .. team_id
      ),
      dopts
    )
  )
end)

b:rest("get_team_members", function(team_id)
  local t = ado_get_team_by_id(team_id)
  if not t then
    respond_json(404, { message = "Not Found" })
    return
  end
  local data = ado_fetch_team_members(t.projectName or "", team_id)
  if not data then
    respond_json(503, {})
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
  respond_json(200, result)
end)

b:rest("get_team_member", function(team_id, username)
  local t = ado_get_team_by_id(team_id)
  if not t then
    respond_json(404, { message = "Not Found" })
    return
  end
  local ok, member = ado_find_team_member(t.projectName or "", team_id, username)
  if not ok then
    respond_json(503, {})
    return
  end
  if member then
    SetStatus(204, "No Content")
    return
  end
  respond_json(404, { message = "Not Found" })
end)

b:rest("put_team_member", function(team_id, username)
  local t = ado_get_team_by_id(team_id)
  if not t then
    respond_json(404, { message = "Not Found" })
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
end)

b:rest("delete_team_member", function(team_id, username)
  local t = ado_get_team_by_id(team_id)
  if not t then
    respond_json(404, { message = "Not Found" })
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
end)

b:rest("get_team_membership", function(team_id, username)
  local t = ado_get_team_by_id(team_id)
  if not t then
    respond_json(404, { message = "Not Found" })
    return
  end
  local ok, member = ado_find_team_member(t.projectName or "", team_id, username)
  if not ok then
    respond_json(503, {})
    return
  end
  if member then
    respond_json(200, {
      url = "",
      role = member.isTeamAdmin and "maintainer" or "member",
      state = "active",
    })
    return
  end
  respond_json(404, { message = "Not Found" })
end)

b:rest("put_team_membership", function(team_id, username)
  local t = ado_get_team_by_id(team_id)
  if not t then
    respond_json(404, { message = "Not Found" })
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
    respond_json(200, { url = "", role = role, state = "active" })
  else
    respond_json(200, { url = "", role = role, state = "pending" })
  end
end)

b:rest("delete_team_membership", function(team_id, username)
  local t = ado_get_team_by_id(team_id)
  if not t then
    respond_json(404, { message = "Not Found" })
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
end)

b:rest("put_team_repo", function()
  respond_json(
    422,
    "Unprocessable Entity",
    { message = "Team repository associations are not supported by Azure DevOps" }
  )
end)
b:rest("delete_team_repo", function()
  SetStatus(204, "No Content")
end)

-- Issues (Azure Boards work items) -----------------------------------------

b:rest("get_repo_issues", function(owner, _repo_name)
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
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
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
end)

b:rest("get_repo_issue", function(owner, _repo_name, issue_number)
  proxy_json(
    translate_ado_workitem,
    fetch_json(
      ado_url(
        config.base_url .. "/" .. owner .. "/_apis/wit/workitems/" .. issue_number .. "?$expand=all"
      )
    )
  )
end)

b:rest("post_repo_issues", function(owner, _repo_name)
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
  proxy_json_created(
    translate_ado_workitem,
    pcall(Fetch, ado_url(config.base_url .. "/" .. owner .. "/_apis/wit/workitems/$Issue"), opts)
  )
end)

b:rest("patch_repo_issue", function(owner, _repo_name, issue_number)
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
    respond_json(200, translate_ado_workitem(DecodeJson(pbody) or {}))
  elseif pok then
    respond_json(pstatus, {})
  else
    respond_json(503, {})
  end
end)

b:rest("get_issue_comments", function(owner, _repo_name, issue_number)
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
end)

b:rest("post_issue_comment", function(owner, _repo_name, issue_number)
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
end)

-- Checks (via ADO git commit statuses) -------------------------------------

-- POST /repos/{owner}/{repo}/check-runs
b:rest("post_check_runs", function(owner, repo_name)
  local req = DecodeJson(GetBody() or "{}")
  local sha = req.head_sha or ""
  proxy_json_created(
    translate_ado_status_to_check_run,
    fetch_json(
      ado_url(repos_base(owner) .. "/" .. repo_name .. "/commits/" .. sha .. "/statuses"),
      "POST",
      gh_check_run_to_ado_status(req)
    )
  )
end)

-- GET /repos/{owner}/{repo}/commits/{ref}/check-runs
b:rest("get_commit_check_runs", function(owner, repo_name, ref)
  local ok, status, _, body =
    fetch_json(ado_url(repos_base(owner) .. "/" .. repo_name .. "/commits/" .. ref .. "/statuses"))
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local data = DecodeJson(body) or {}
  local list = data.value or {}
  local runs = {}
  for _, s in ipairs(list) do
    runs[#runs + 1] = translate_ado_status_to_check_run(s)
  end
  respond_json(200, { total_count = #runs, check_runs = runs })
end)

-- POST /repos/{owner}/{repo}/check-suites
b:rest("post_check_suites", function(owner, repo_name)
  local req = DecodeJson(GetBody() or "{}")
  respond_json(201, {
    id = 0,
    node_id = "",
    head_sha = req.head_sha or "",
    status = "queued",
    conclusion = nil,
    url = "",
    repository = { id = 0, name = repo_name, full_name = owner .. "/" .. repo_name },
  })
end)

-- GET /repos/{owner}/{repo}/check-suites/{check_suite_id}
b:rest("get_check_suite", function(owner, repo_name, check_suite_id)
  respond_json(200, {
    id = tonumber(check_suite_id) or 0,
    node_id = "",
    head_sha = "",
    status = "completed",
    conclusion = "success",
    url = "",
    repository = { id = 0, name = repo_name, full_name = owner .. "/" .. repo_name },
  })
end)

-- Code Scanning (via ADO Advanced Security / GHAzDO) ------------------------
--
-- Azure DevOps Advanced Security provides code scanning alerts at the
-- repository level via:
--   GET  /{owner}/_apis/advancedsecurity/alerts/{repo}?alertType=code
--   GET  /{owner}/_apis/advancedsecurity/alerts/{repo}/{alertId}
--   PATCH /{owner}/_apis/advancedsecurity/alerts/{repo}/{alertId}
--   GET  /{owner}/_apis/advancedsecurity/analyses/{repo}
--   POST /{owner}/_apis/advancedsecurity/sarifs/{repo}
--
-- Org-level alert listing is not natively supported; returns empty list.
-- CodeQL databases, variant analyses, default-setup, and per-analysis
-- detail/delete have no direct ADO equivalent and fall back to 501.
--
-- ADO alert state mapping:
--   active    → open
--   dismissed → dismissed
--   fixed     → fixed
--
-- ADO dismissal reason mapping:
--   falsePositive  → false positive
--   wontFix        → won't fix
--   (other)        → used in tests

local ADVSEC_API_VER = "api-version=7.2-preview.1"

local function advsec_url(path)
  return path .. (path:find("?") and "&" or "?") .. ADVSEC_API_VER
end

local function advsec_base(owner)
  return config.base_url .. "/" .. owner .. "/_apis/advancedsecurity"
end

local ADO_STATE_TO_GH = {
  active = "open",
  dismissed = "dismissed",
  fixed = "fixed",
}

local ADO_DISMISS_REASON_TO_GH = {
  falsePositive = "false positive",
  wontFix = "won't fix",
  usedInTests = "used in tests",
}

local GH_STATE_TO_ADO = {
  open = "active",
  dismissed = "dismissed",
}

local GH_DISMISS_REASON_TO_ADO = {
  ["false positive"] = "falsePositive",
  ["won't fix"] = "wontFix",
  ["used in tests"] = "usedInTests",
}

local function translate_ado_alert(a)
  if not a then
    return {}
  end
  local state = ADO_STATE_TO_GH[a.state or ""] or "open"
  local dismissal = a.dismissal or {}
  local dismissed_reason = ADO_DISMISS_REASON_TO_GH[dismissal.dismissalType or ""]
  local rule = a.rule or {}
  local locations = a.physicalLocations or {}
  local loc = locations[1] or {}
  local region = loc.region or {}
  return {
    number = a.alertId or 0,
    state = state,
    fixed_at = a.fixedDate,
    dismissed_at = a.dismissedDate,
    dismissed_reason = dismissed_reason,
    dismissed_comment = dismissal.message or nil,
    rule = {
      id = rule.id or "",
      name = rule.name or "",
      severity = (a.severity or ""):lower(),
      description = rule.description or "",
      full_description = { text = rule.description or "" },
      help = { text = "" },
      help_uri = "",
      tags = {},
    },
    tool = { name = "Advanced Security", guid = nil, version = nil },
    most_recent_instance = {
      ref = "",
      analysis_key = "",
      environment = "{}",
      state = state,
      commit_sha = "",
      location = {
        path = loc.physicalLocation and (loc.physicalLocation.artifactLocation or {}).uri or "",
        start_line = region.startLine or 0,
        end_line = region.endLine or region.startLine or 0,
        start_column = region.startColumn or 0,
        end_column = region.endColumn or region.startColumn or 0,
      },
      classifications = {},
    },
    created_at = a.firstSeenDate or "",
    updated_at = a.firstSeenDate or "",
    url = "",
    html_url = "",
    instances_url = "",
  }
end

local function translate_ado_analysis(an)
  if not an then
    return {}
  end
  return {
    ref = an.branch or "",
    commit_sha = an.commitId or "",
    analysis_key = tostring(an.analysisId or 0),
    environment = "{}",
    category = "",
    error = "",
    created_at = an.createdDate or "",
    results_count = an.resultCount or 0,
    rules_count = 0,
    id = an.analysisId or 0,
    url = "",
    sarif_id = "",
    tool = { name = "Advanced Security", guid = nil, version = nil },
    deletable = false,
    warning = "",
  }
end

-- Code scanning handlers (kept below for readability; same builder b).

b:rest("list_repo_code_scanning_alerts", function(owner, repo_name)
  local alert_type = GetParam("tool_name") or "code"
  local url =
    advsec_url(advsec_base(owner) .. "/alerts/" .. repo_name .. "?alertType=" .. alert_type)
  local ok, status, _, body = fetch_json(url)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local data = DecodeJson(body) or {}
  respond_json(200, translate_list(translate_ado_alert, data.value))
end)

b:rest("get_code_scanning_alert", function(owner, repo_name, alert_number)
  local url = advsec_url(advsec_base(owner) .. "/alerts/" .. repo_name .. "/" .. alert_number)
  local ok, status, _, body = fetch_json(url)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  respond_json(200, translate_ado_alert(DecodeJson(body) or {}))
end)

b:rest("update_code_scanning_alert", function(owner, repo_name, alert_number)
  local req = DecodeJson(GetBody() or "{}")
  local ado_state = GH_STATE_TO_ADO[req.state or ""] or "active"
  local patch = { state = ado_state }
  if req.dismissed_reason then
    patch.dismissal = {
      dismissalType = GH_DISMISS_REASON_TO_ADO[req.dismissed_reason] or "wontFix",
      message = req.dismissed_comment or "",
    }
  end
  local url = advsec_url(advsec_base(owner) .. "/alerts/" .. repo_name .. "/" .. alert_number)
  local ok, status, _, body = fetch_json(url, "PATCH", EncodeJson(patch))
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  respond_json(200, translate_ado_alert(DecodeJson(body) or {}))
end)

b:rest("list_code_scanning_analyses", function(owner, repo_name)
  local url = advsec_url(advsec_base(owner) .. "/analyses/" .. repo_name)
  local ok, status, _, body = fetch_json(url)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local data = DecodeJson(body) or {}
  respond_json(200, translate_list(translate_ado_analysis, data.value))
end)

b:rest("upload_code_scanning_sarif", function(owner, repo_name)
  local body = GetBody() or "{}"
  local url = advsec_url(advsec_base(owner) .. "/sarifs/" .. repo_name)
  local ok, status, _, rbody = fetch_json(url, "POST", body)
  if not ok then
    respond_json(503, {})
    return
  end
  if status == 200 or status == 202 then
    local data = DecodeJson(rbody) or {}
    respond_json(202, {
      id = tostring(data.sarif_id or data.sarifId or ""),
      url = "",
    })
  else
    respond_json(status, {})
  end
end)

-- Dependabot alerts via ADO Advanced Security dependency scanning -----------------
--
-- Uses the same /_apis/advancedsecurity/alerts/{repo} endpoint as code scanning
-- but with alertType=dependency. Secrets and repository-access have no ADO
-- equivalent and fall back to defaults (501 / empty list).
--
-- ADO dependency alert fields used:
--   alertId, state, severity, firstSeenDate, dismissedDate, dismissal,
--   dependency.{componentName, componentVersion, packageManager}, title, cve

local ADO_PACKAGE_MANAGER_TO_ECOSYSTEM = {
  npm = "npm",
  nuget = "nuget",
  pypi = "pip",
  maven = "maven",
  cargo = "cargo",
  rubygems = "rubygems",
  composer = "composer",
  go = "go",
}

local GH_DEPENDABOT_DISMISS_REASON_TO_ADO = {
  inaccurate = "falsePositive",
  ["fix_started"] = "wontFix",
  ["no_bandwidth"] = "wontFix",
  ["not_used"] = "wontFix",
  ["tolerable_risk"] = "wontFix",
}

local function translate_ado_dependency_alert(a)
  if not a then
    return {}
  end
  local state = ADO_STATE_TO_GH[a.state or ""] or "open"
  local dismissal = a.dismissal or {}
  local dismissed_reason = ADO_DISMISS_REASON_TO_GH[dismissal.dismissalType or ""]
  local dep = a.dependency or {}
  local pm = (dep.packageManager or ""):lower()
  local ecosystem = ADO_PACKAGE_MANAGER_TO_ECOSYSTEM[pm] or pm
  local package = { ecosystem = ecosystem, name = dep.componentName or "" }
  return {
    number = a.alertId or 0,
    state = state,
    dependency = {
      package = package,
      manifest_path = "",
      scope = "runtime",
    },
    security_advisory = {
      ghsa_id = "",
      cve_id = a.cve or nil,
      summary = a.title or "",
      description = a.title or "",
      severity = (a.severity or ""):lower(),
      identifiers = {},
      references = {},
      published_at = a.firstSeenDate or "",
      updated_at = a.firstSeenDate or "",
      withdrawn_at = nil,
      vulnerabilities = {},
    },
    security_vulnerability = {
      package = package,
      severity = (a.severity or ""):lower(),
      vulnerable_version_range = dep.componentVersion and ("= " .. dep.componentVersion) or "",
      first_patched_version = nil,
    },
    url = "",
    html_url = "",
    created_at = a.firstSeenDate or "",
    updated_at = a.firstSeenDate or "",
    dismissed_at = a.dismissedDate,
    dismissed_by = nil,
    dismissed_reason = dismissed_reason,
    dismissed_comment = dismissal.message or nil,
    fixed_at = nil,
    auto_dismissed_at = nil,
  }
end

b:rest("list_repo_dependabot_alerts", function(owner, repo_name)
  local url = advsec_url(advsec_base(owner) .. "/alerts/" .. repo_name .. "?alertType=dependency")
  local ok, status, _, body = fetch_json(url)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local data = DecodeJson(body) or {}
  respond_json(200, translate_list(translate_ado_dependency_alert, data.value))
end)

b:rest("get_repo_dependabot_alert", function(owner, repo_name, alert_number)
  local url = advsec_url(advsec_base(owner) .. "/alerts/" .. repo_name .. "/" .. alert_number)
  local ok, status, _, body = fetch_json(url)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  respond_json(200, translate_ado_dependency_alert(DecodeJson(body) or {}))
end)

b:rest("update_repo_dependabot_alert", function(owner, repo_name, alert_number)
  local req = DecodeJson(GetBody() or "{}")
  local ado_state = GH_STATE_TO_ADO[req.state or ""] or "active"
  local patch = { state = ado_state }
  if req.dismissed_reason then
    patch.dismissal = {
      dismissalType = GH_DEPENDABOT_DISMISS_REASON_TO_ADO[req.dismissed_reason] or "wontFix",
      message = req.dismissed_comment or "",
    }
  end
  local url = advsec_url(advsec_base(owner) .. "/alerts/" .. repo_name .. "/" .. alert_number)
  local ok, status, _, body = fetch_json(url, "PATCH", EncodeJson(patch))
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  respond_json(200, translate_ado_dependency_alert(DecodeJson(body) or {}))
end)

-- Secret Scanning via ADO Advanced Security -----------------------------------------
--
-- Azure DevOps Advanced Security exposes secret scanning alerts at the
-- repository level via the same /_apis/advancedsecurity/alerts/{repo} endpoint
-- used by code scanning, selecting alertType=secret:
--   GET  /{owner}/_apis/advancedsecurity/alerts/{repo}?alertType=secret
--   GET  /{owner}/_apis/advancedsecurity/alerts/{repo}/{alertId}
--   PATCH /{owner}/_apis/advancedsecurity/alerts/{repo}/{alertId}
--
-- Org-level listing, alert locations, push-protection bypasses, and scan
-- history have no ADO equivalent and fall back to defaults.
--
-- ADO secret alert fields:
--   alertId, state, severity, firstSeenDate, fixedDate, dismissedDate,
--   dismissal.{dismissalType, message}, rule.{id, name},
--   logicalLocations[0].fullyQualifiedName (secret value)
--
-- ADO dismissal type → GitHub resolution mapping for secrets:
--   falsePositive  → false_positive
--   wontFix        → wont_fix
--   usedInTests    → used_in_tests
--   revokedSecret  → revoked

local ADO_SECRET_DISMISS_REASON_TO_GH = {
  falsePositive = "false_positive",
  wontFix = "wont_fix",
  usedInTests = "used_in_tests",
  revokedSecret = "revoked",
}

local GH_SECRET_DISMISS_REASON_TO_ADO = {
  false_positive = "falsePositive",
  wont_fix = "wontFix",
  used_in_tests = "usedInTests",
  revoked = "revokedSecret",
  pattern_deleted = "wontFix",
  pattern_edited = "wontFix",
}

local ADO_SECRET_STATE_TO_GH = {
  active = "open",
  dismissed = "dismissed",
  fixed = "resolved",
}

local function translate_ado_secret_alert(a)
  if not a then
    return {}
  end
  local state = ADO_SECRET_STATE_TO_GH[a.state or ""] or "open"
  local dismissal = a.dismissal or {}
  local resolution = ADO_SECRET_DISMISS_REASON_TO_GH[dismissal.dismissalType or ""]
  local rule = a.rule or {}
  local locs = a.logicalLocations or {}
  local secret = (locs[1] or {}).fullyQualifiedName or ""
  local resolved_at = a.fixedDate or a.dismissedDate
  return {
    number = a.alertId or 0,
    created_at = a.firstSeenDate or "",
    updated_at = a.firstSeenDate or "",
    url = "",
    html_url = "",
    locations_url = "",
    state = state,
    resolution = resolution,
    resolved_by = nil,
    resolved_at = resolved_at,
    resolution_comment = dismissal.message or nil,
    secret_type = rule.id or "",
    secret_type_display_name = rule.name or "",
    secret = secret,
    push_protection_bypassed = nil,
    push_protection_bypassed_by = nil,
    push_protection_bypassed_at = nil,
    validity = "unknown",
    publicly_leaked = false,
    multi_repo = false,
    auto_dismissed_at = nil,
  }
end

b:rest("list_repo_secret_scanning_alerts", function(owner, repo_name)
  local url = advsec_url(advsec_base(owner) .. "/alerts/" .. repo_name .. "?alertType=secret")
  local ok, status, _, body = fetch_json(url)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local data = DecodeJson(body) or {}
  respond_json(200, translate_list(translate_ado_secret_alert, data.value))
end)

b:rest("get_secret_scanning_alert", function(owner, repo_name, alert_number)
  local url = advsec_url(advsec_base(owner) .. "/alerts/" .. repo_name .. "/" .. alert_number)
  local ok, status, _, body = fetch_json(url)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  respond_json(200, translate_ado_secret_alert(DecodeJson(body) or {}))
end)

b:rest("update_secret_scanning_alert", function(owner, repo_name, alert_number)
  local req = DecodeJson(GetBody() or "{}")
  local ado_state = GH_STATE_TO_ADO[req.state or ""] or "active"
  local patch = { state = ado_state }
  if req.resolution then
    patch.dismissal = {
      dismissalType = GH_SECRET_DISMISS_REASON_TO_ADO[req.resolution] or "wontFix",
      message = req.resolution_comment or "",
    }
  end
  local url = advsec_url(advsec_base(owner) .. "/alerts/" .. repo_name .. "/" .. alert_number)
  local ok, status, _, body = fetch_json(url, "PATCH", EncodeJson(patch))
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  respond_json(200, translate_ado_secret_alert(DecodeJson(body) or {}))
end)

-- Git database (refs only; blobs/commits/tag-objects/trees have no ADO equivalent) ----

local ZERO_SHA = "0000000000000000000000000000000000000000"

b:rest("list_git_matching_refs", function(owner, repo_name, ref)
  local filter
  if ref:sub(1, 6) == "heads/" or ref:sub(1, 5) == "tags/" then
    filter = ref
  else
    filter = "heads/" .. ref
  end
  local url = ado_url(repos_base(owner) .. "/" .. repo_name .. "/refs?filter=" .. filter)
  proxy_json(function(data)
    local refs = data.value or {}
    for i, r in ipairs(refs) do
      refs[i] = translate_ado_ref(r)
    end
    return refs
  end, fetch_json(url))
end)

b:rest("get_git_ref", function(owner, repo_name, ref)
  local filter
  if ref:sub(1, 6) == "heads/" or ref:sub(1, 5) == "tags/" then
    filter = ref
  else
    respond_json(422, { message = "Invalid ref format" })
    return
  end
  local url = ado_url(repos_base(owner) .. "/" .. repo_name .. "/refs?filter=" .. filter)
  proxy_json(function(data)
    local first = (data.value or {})[1]
    return first and translate_ado_ref(first) or {}
  end, fetch_json(url))
end)

b:rest("create_git_ref", function(owner, repo_name)
  local req = DecodeJson(GetBody() or "{}")
  local full_ref = req.ref or ""
  local sha = req.sha or ""
  local url = ado_url(repos_base(owner) .. "/" .. repo_name .. "/refs")
  local bb_body = EncodeJson({
    { name = full_ref, newObjectId = sha, oldObjectId = ZERO_SHA },
  })
  local ok, status, _, body = fetch_json(url, "POST", bb_body)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local data = DecodeJson(body) or {}
  local first = (data.value or {})[1]
  respond_json(201, first and translate_ado_ref(first) or {})
end)

b:rest("delete_git_ref", function(owner, repo_name, ref)
  local full_ref
  if ref:sub(1, 6) == "heads/" or ref:sub(1, 5) == "tags/" then
    full_ref = "refs/" .. ref
  else
    respond_json(422, { message = "Invalid ref format" })
    return
  end
  -- ADO delete requires the current objectId; fetch the ref first.
  local filter_url = ado_url(repos_base(owner) .. "/" .. repo_name .. "/refs?filter=" .. ref)
  local ok1, status1, _, body1 = fetch_json(filter_url)
  if not ok1 then
    respond_json(503, {})
    return
  end
  if status1 ~= 200 then
    respond_json(status1, {})
    return
  end
  local data1 = DecodeJson(body1) or {}
  local current = (data1.value or {})[1]
  local old_sha = current and current.objectId or ZERO_SHA
  local url = ado_url(repos_base(owner) .. "/" .. repo_name .. "/refs")
  local del_body = EncodeJson({
    { name = full_ref, newObjectId = ZERO_SHA, oldObjectId = old_sha },
  })
  proxy_204({ 200 }, fetch_json(url, "POST", del_body))
end)

-- GraphQL resolvers -----------------------------------------------------------
-- Minimum foothold: Query.repository and node.Repository only.
-- ADO has no GET /user, so Query.viewer returns null (handled by default).
-- Work Items ≠ GitHub Issues, so issue resolvers are omitted.

b:graphql("Query.repository", function(_parent, args, ctx)
  if not args.owner or not args.name then
    graphql_error(ctx, "repository requires owner and name arguments")
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, ado_url(repos_base(args.owner) .. "/" .. args.name))
  if not data then
    return nil
  end
  return graphql_translate_repo(translate_ado_repo(data))
end)

b:graphql("node.Repository", function(local_id, _ctx)
  local owner, name = local_id:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, ado_url(repos_base(owner) .. "/" .. name))
  if not data then
    return nil
  end
  return graphql_translate_repo(translate_ado_repo(data))
end)

-- Webhook handlers: Azure DevOps embeds the event type in payload.eventType.
-- The dispatcher extracts it from the body (no header-based dispatch).
--
-- Relevant event types:
--   workitem.created          → issues / opened
--   workitem.deleted          → issues / closed
--   workitem.restored         → issues / reopened
--   workitem.updated          → issues / edited | closed | reopened  (derived from state diff)
--   workitem.commented        → issue_comment / created
--   git.pullrequest.created   → pull_request / opened
--   git.pullrequest.updated   → pull_request / closed | synchronize  (derived from status)
--
-- Payload shapes:
--   workitem.created/workitem.updated:
--     resource            — work item object (fields as strings for created;
--                           revision.fields as strings + fields as diffs for updated)
--   workitem.commented:
--     resource.workItemId — ID of the parent work item
--     resource.text       — comment body
--     resource.revisedBy  — commenter
--     resource.revisedDate

-- Helper: build a sender user table from an ADO user field object.
local function ado_user(u)
  return {
    login = ado_identity_login(u),
    id = 0,
    node_id = "",
    avatar_url = "",
    type = "User",
  }
end

-- Helper: derive canonical issues action for workitem.updated from the
-- diff in resource.fields.  Each changed field is { newValue = ..., oldValue = ... }.
local function ado_workitem_updated_action(resource)
  local fields = resource.fields or {}
  local state_diff = fields["System.State"]
  if type(state_diff) == "table" then
    local new_gh = ado_state_to_github(state_diff.newValue)
    local old_gh = ado_state_to_github(state_diff.oldValue)
    if new_gh == "closed" and old_gh == "open" then
      return "closed"
    elseif new_gh == "open" and old_gh == "closed" then
      return "reopened"
    end
  end
  return "edited"
end

-- Translate an ADO pull request resource to GitHub format.
local function translate_ado_pull(pr)
  if not pr then
    return {}
  end
  local status = pr.status or "active"
  local is_merged = status == "completed"
  local gh_state = status == "active" and "open" or "closed"
  local src_ref = pr.sourceRefName and pr.sourceRefName:match("refs/heads/(.+)")
    or (pr.sourceRefName or "")
  local tgt_ref = pr.targetRefName and pr.targetRefName:match("refs/heads/(.+)")
    or (pr.targetRefName or "")
  local src_sha = (pr.lastMergeSourceCommit or {}).commitId or ""
  local tgt_sha = (pr.lastMergeTargetCommit or {}).commitId or ""
  return {
    id = pr.pullRequestId or 0,
    node_id = "",
    number = pr.pullRequestId or 0,
    state = gh_state,
    locked = false,
    title = pr.title or "",
    body = pr.description or "",
    user = ado_user(pr.createdBy),
    head = { label = src_ref, ref = src_ref, sha = src_sha },
    base = { label = tgt_ref, ref = tgt_ref, sha = tgt_sha },
    draft = pr.isDraft or false,
    created_at = pr.creationDate or "",
    updated_at = pr.closedDate or pr.creationDate or "",
    closed_at = (not is_merged and gh_state == "closed") and pr.closedDate or nil,
    merged_at = is_merged and pr.closedDate or nil,
    merge_commit_sha = nil,
    merged_by = nil,
    html_url = "",
    url = "",
    mergeable = status == "active" or nil,
    comments = 0,
    review_comments = 0,
    commits = 0,
    additions = 0,
    deletions = 0,
    changed_files = 0,
  }
end

b:webhook("workitem.created", function(payload)
  local resource = payload.resource or {}
  local issue = translate_ado_workitem(resource)
  local fields = resource.fields or {}
  return make_internal_event({
    event = "issues",
    action = "opened",
    provider = "azuredevops",
    raw = payload,
    data = {
      action = "opened",
      issue = issue,
      repository = {},
      sender = ado_user(fields["System.ChangedBy"] or fields["System.CreatedBy"]),
    },
    timestamp = fields["System.CreatedDate"] or "",
  })
end)

b:webhook("workitem.updated", function(payload)
  local resource = payload.resource or {}
  -- revision.fields has current field values as plain strings.
  local revision = resource.revision or resource
  local action = ado_workitem_updated_action(resource)
  local issue = translate_ado_workitem(revision)
  local rev_fields = revision.fields or {}
  return make_internal_event({
    event = "issues",
    action = action,
    provider = "azuredevops",
    raw = payload,
    data = {
      action = action,
      issue = issue,
      repository = {},
      sender = ado_user(rev_fields["System.ChangedBy"]),
    },
    timestamp = rev_fields["System.ChangedDate"] or "",
  })
end)

local function ado_workitem_lifecycle_handler(action)
  return function(payload)
    local resource = payload.resource or {}
    local fields = resource.fields or {}
    return make_internal_event({
      event = "issues",
      action = action,
      provider = "azuredevops",
      raw = payload,
      data = {
        action = action,
        issue = translate_ado_workitem(resource),
        repository = {},
        sender = ado_user(fields["System.ChangedBy"] or fields["System.CreatedBy"]),
      },
      timestamp = fields["System.ChangedDate"] or payload.createdDate or "",
    })
  end
end

b:webhook("workitem.deleted", ado_workitem_lifecycle_handler("closed"))
b:webhook("workitem.restored", ado_workitem_lifecycle_handler("reopened"))

b:webhook("workitem.commented", function(payload)
  local resource = payload.resource or {}
  local wid = resource.workItemId or 0
  local comment = translate_ado_workitem_comment(resource)
  local revised_by = resource.revisedBy or {}
  return make_internal_event({
    event = "issue_comment",
    action = "created",
    provider = "azuredevops",
    raw = payload,
    data = {
      action = "created",
      issue = { id = wid, number = wid },
      comment = comment,
      repository = {},
      sender = ado_user(revised_by),
    },
    timestamp = resource.revisedDate or "",
  })
end)

b:webhook("git.pullrequest.created", function(payload)
  local resource = payload.resource or {}
  return make_internal_event({
    event = "pull_request",
    action = "opened",
    provider = "azuredevops",
    raw = payload,
    data = {
      action = "opened",
      number = resource.pullRequestId,
      pull_request = translate_ado_pull(resource),
      repository = translate_ado_repo(resource.repository),
      sender = ado_user(resource.createdBy),
    },
    timestamp = payload.createdDate or "",
  })
end)

b:webhook("git.pullrequest.updated", function(payload)
  local resource = payload.resource or {}
  local status = resource.status or "active"
  local action
  if status == "completed" or status == "abandoned" then
    action = "closed"
  else
    action = "synchronize"
  end
  return make_internal_event({
    event = "pull_request",
    action = action,
    provider = "azuredevops",
    raw = payload,
    data = {
      action = action,
      number = resource.pullRequestId,
      pull_request = translate_ado_pull(resource),
      repository = translate_ado_repo(resource.repository),
      sender = ado_user(resource.createdBy),
    },
    timestamp = payload.createdDate or "",
  })
end)

-- pull_request_review events.
-- Azure DevOps emits git.pullrequest.reviewervote when a reviewer's vote changes.
--
-- ADO vote values and their GitHub state mappings:
--   10  Approved                  → submitted / APPROVED
--    5  Approved with suggestions → submitted / APPROVED
--    0  No vote (reset / removed) → dismissed / DISMISSED
--   -5  Waiting for author        → submitted / CHANGES_REQUESTED
--  -10  Rejected                  → submitted / CHANGES_REQUESTED
local ADO_VOTE_MAP = {
  [10] = { state = "APPROVED", action = "submitted" },
  [5] = { state = "APPROVED", action = "submitted" },
  [0] = { state = "DISMISSED", action = "dismissed" },
  [-5] = { state = "CHANGES_REQUESTED", action = "submitted" },
  [-10] = { state = "CHANGES_REQUESTED", action = "submitted" },
}

b:webhook("git.pullrequest.reviewervote", function(payload)
  local resource = payload.resource or {}
  local reviewer = resource.reviewer or {}
  local raw_pr = resource.pullRequest or {}
  local vote = tonumber(resource.vote) or 0
  local mapping = ADO_VOTE_MAP[vote] or { state = "APPROVED", action = "submitted" }
  local review = {
    id = 0,
    node_id = "",
    user = ado_user(reviewer),
    body = "",
    state = mapping.state,
    submitted_at = payload.createdDate or "",
    html_url = "",
    pull_request_url = "",
  }
  return make_internal_event({
    event = "pull_request_review",
    action = mapping.action,
    provider = "azuredevops",
    raw = payload,
    data = {
      action = mapping.action,
      review = review,
      pull_request = translate_ado_pull(raw_pr),
      repository = translate_ado_repo(raw_pr.repository),
      sender = ado_user(reviewer),
    },
    timestamp = payload.createdDate or "",
  })
end)

-- build.complete: fires when a Classic or YAML pipeline build finishes.
-- Maps to GitHub workflow_run / completed.  The ADO result field
-- (succeeded/failed/canceled/partiallySucceeded) determines the conclusion.
-- There is no in-progress build event in ADO webhooks, so only "completed"
-- actions are produced here.
local ADO_BUILD_RESULT_TO_CONCLUSION = {
  succeeded = "success",
  failed = "failure",
  canceled = "cancelled",
  partiallySucceeded = "failure",
}

local function ado_project_repo(project, name)
  project = project or {}
  name = name or project.name or ""
  return translate_ado_repo({
    id = "",
    name = name,
    remoteUrl = "",
    defaultBranch = "refs/heads/main",
    isPrivate = false,
    project = project,
  })
end

local function ado_release_web_url(release)
  release = release or {}
  return ((release._links or {}).web or {}).href or release.url or ""
end

local function ado_release_project(release, resource)
  release = release or {}
  resource = resource or {}
  local definition = release.releaseDefinition or {}
  return release.project
    or definition.project
    or definition.projectReference
    or resource.project
    or {}
end

local function translate_ado_release(release, resource)
  release = release or {}
  resource = resource or {}
  local definition = release.releaseDefinition or {}
  local created_by = release.createdBy or release.modifiedBy or {}
  return {
    id = release.id or 0,
    tag_name = release.name or "",
    name = release.name,
    body = (resource.message or {}).text or (resource.detailedMessage or {}).text or "",
    draft = false,
    prerelease = false,
    html_url = ado_release_web_url(release),
    tarball_url = nil,
    zipball_url = nil,
    author = ado_user(created_by),
    created_at = release.createdOn or resource.createdDate or "",
    published_at = release.createdOn or resource.createdDate or "",
    target_commitish = definition.name or "",
  }
end

local function ado_release_repository(release, resource)
  release = release or {}
  local definition = release.releaseDefinition or {}
  local project = ado_release_project(release, resource)
  return ado_project_repo(project, definition.name or release.name or "")
end

local function ado_release_sender(release, resource)
  release = release or {}
  resource = resource or {}
  return ado_user(release.modifiedBy or release.createdBy or resource.requestedBy)
end

local function ado_release_event_handler(action)
  return function(payload)
    local resource = payload.resource or {}
    local release = resource.release or resource
    local data = {
      action = action,
      release = translate_ado_release(release, resource),
      repository = ado_release_repository(release, resource),
      sender = ado_release_sender(release, resource),
    }
    return make_internal_event({
      event = "release",
      action = action,
      provider = "azuredevops",
      raw = payload,
      data = data,
      timestamp = release.modifiedOn or release.createdOn or payload.createdDate or "",
    })
  end
end

local ADO_DEPLOYMENT_STATUS_STATE = {
  queued = "queued",
  inProgress = "in_progress",
  inprogress = "in_progress",
  succeeded = "success",
  partiallySucceeded = "failure",
  failed = "failure",
  rejected = "failure",
  canceled = "inactive",
  cancelled = "inactive",
}

local function ado_deployment_parts(resource)
  resource = resource or {}
  local deployment = resource.deployment or {}
  local release = deployment.release or resource.release or {}
  local environment = deployment.environment or resource.environment or {}
  return deployment, release, environment
end

local function ado_deployment_url(release, environment)
  release = release or {}
  environment = environment or {}
  local release_url = ado_release_web_url(release)
  if release_url ~= "" then
    return release_url
  end
  return ((environment._links or {}).web or {}).href or environment.url or ""
end

local function translate_ado_deployment(resource)
  local deployment, release, environment = ado_deployment_parts(resource)
  local owner = environment.owner or release.createdBy or release.modifiedBy or {}
  local timestamp = deployment.startedOn
    or environment.modifiedOn
    or release.modifiedOn
    or release.createdOn
    or ""
  return {
    id = deployment.id or environment.id or 0,
    node_id = "",
    sha = "",
    ref = release.name or "",
    task = "deploy",
    environment = environment.name or "",
    original_environment = "",
    description = (resource.message or {}).text or "",
    payload = {},
    creator = ado_user(owner),
    created_at = timestamp,
    updated_at = deployment.completedOn or environment.modifiedOn or timestamp,
    statuses_url = "",
    repository_url = "",
    production_environment = false,
    transient_environment = false,
  }
end

local function ado_deployment_status(resource, state)
  local deployment, _release, environment = ado_deployment_parts(resource)
  local timestamp = deployment.completedOn
    or deployment.startedOn
    or environment.modifiedOn
    or environment.scheduledDeploymentTime
    or ""
  return {
    id = deployment.id or 0,
    node_id = "",
    state = state,
    description = (resource.detailedMessage or {}).text or (resource.message or {}).text or "",
    environment = environment.name or "",
    environment_url = "",
    log_url = "",
    target_url = "",
    deployment_url = ado_deployment_url(_release, environment),
    creator = ado_user(environment.owner or _release.modifiedBy or _release.createdBy),
    created_at = timestamp,
    updated_at = timestamp,
  }
end

local function ado_deployment_repository(resource)
  local _, release, environment = ado_deployment_parts(resource)
  local definition = release.releaseDefinition or {}
  local project = ado_release_project(release, resource)
  return ado_project_repo(project, definition.name or environment.name or release.name or "")
end

local function ado_deployment_sender(resource)
  local _, release, environment = ado_deployment_parts(resource)
  return ado_user(environment.owner or release.modifiedBy or release.createdBy)
end

local function ado_deployment_status_handler(payload)
  local resource = payload.resource or {}
  local deployment = (resource.deployment or {})
  local state = ADO_DEPLOYMENT_STATUS_STATE[deployment.status or ""] or "error"
  return make_internal_event({
    event = "deployment_status",
    action = "created",
    provider = "azuredevops",
    raw = payload,
    data = {
      action = "created",
      deployment_status = ado_deployment_status(resource, state),
      deployment = translate_ado_deployment(resource),
      repository = ado_deployment_repository(resource),
      sender = ado_deployment_sender(resource),
    },
    timestamp = deployment.completedOn or payload.createdDate or "",
  })
end

local function ado_approval_reviewers(approval)
  approval = approval or {}
  local approver = approval.approver
  if not approver then
    return {}
  end
  return {
    { type = "User", reviewer = ado_user(approver) },
  }
end

local function ado_deployment_review_handler(action)
  return function(payload)
    local resource = payload.resource or {}
    local approval = resource.approval or {}
    local release = resource.release or approval.release or {}
    local environment = resource.environment or approval.releaseEnvironment or {}
    local repository = ado_release_repository(release, resource)
    local sender = ado_user(approval.approver)
    local data = {
      action = action,
      approver = action ~= "requested" and sender or nil,
      comment = approval.comments,
      since = approval.createdOn or payload.createdDate or "",
      environment = environment.name or "",
      reviewers = ado_approval_reviewers(approval),
      workflow_run = nil,
      repository = repository,
      sender = sender,
    }
    return make_internal_event({
      event = "deployment_review",
      action = action,
      provider = "azuredevops",
      raw = payload,
      data = data,
      timestamp = approval.modifiedOn or approval.createdOn or payload.createdDate or "",
    })
  end
end

local function ado_advsec_repo_parts(resource)
  resource = resource or {}
  local url = resource.repositoryUrl or ""
  local project, repo = url:match("dev%.azure%.com/[^/]+/([^/]+)/_git/([^/?#]+)")
  if not project then
    project, repo = url:match("[^/]+%.visualstudio%.com/([^/]+)/_git/([^/?#]+)")
  end
  project = project or "azuredevops"
  repo = repo or "advanced-security"
  return project, repo
end

local function ado_advsec_repository(resource)
  local project, repo = ado_advsec_repo_parts(resource)
  return ado_project_repo({ name = project }, repo)
end

local function ado_advsec_sender(resource)
  resource = resource or {}
  local dismissal = resource.dismissal or {}
  return ado_user(
    dismissal.stateChangedByIdentity
      or dismissal.stateChangedBy
      or resource.modifiedBy
      or resource.createdBy
  )
end

local ADO_ADVSEC_EVENT_BY_TYPE = {
  code = "code_scanning_alert",
  dependency = "dependabot_alert",
  secret = "secret_scanning_alert",
}

local ADO_ADVSEC_TRANSLATOR_BY_EVENT = {
  code_scanning_alert = translate_ado_alert,
  dependabot_alert = translate_ado_dependency_alert,
  secret_scanning_alert = translate_ado_secret_alert,
}

local function ado_advsec_event(resource)
  local alert_type = (resource.alertType or ""):lower()
  return ADO_ADVSEC_EVENT_BY_TYPE[alert_type] or "code_scanning_alert"
end

local function ado_advsec_state_action(event, resource)
  local state = (resource.state or ""):lower()
  if event == "code_scanning_alert" then
    if state == "fixed" then
      return "fixed"
    elseif state == "dismissed" then
      return "closed_by_user"
    elseif state == "active" then
      return "reopened"
    end
  elseif event == "dependabot_alert" then
    if state == "fixed" then
      return "fixed"
    elseif state == "dismissed" then
      return "dismissed"
    elseif state == "active" then
      return "reopened"
    end
  elseif event == "secret_scanning_alert" then
    if state == "fixed" or state == "dismissed" then
      return "resolved"
    elseif state == "active" then
      return "reopened"
    end
  end
  return "unknown"
end

local ADO_ADVSEC_UPDATED_ACTION_BY_EVENT = {
  code_scanning_alert = "updated_assignment",
  dependabot_alert = "assignees_changed",
  secret_scanning_alert = "validated",
}

local function ado_advsec_handler(action_kind)
  return function(payload)
    local resource = payload.resource or {}
    local event = ado_advsec_event(resource)
    local action = action_kind
    if action_kind == "state_changed" then
      action = ado_advsec_state_action(event, resource)
    elseif action_kind == "updated" then
      action = ADO_ADVSEC_UPDATED_ACTION_BY_EVENT[event] or "unknown"
    end
    local translator = ADO_ADVSEC_TRANSLATOR_BY_EVENT[event] or translate_ado_alert
    local data = {
      action = action,
      alert = translator(resource),
      repository = ado_advsec_repository(resource),
      sender = ado_advsec_sender(resource),
    }
    return make_internal_event({
      event = event,
      action = action,
      raw_action = action == "unknown" and action_kind or nil,
      provider = "azuredevops",
      raw = payload,
      data = data,
      timestamp = resource.lastSeenDate or resource.firstSeenDate or payload.createdDate or "",
    })
  end
end

-- git.push: fires when commits are pushed to a Git repository, including
-- branch/tag creation (oldObjectId = zero SHA) and deletion (newObjectId = zero SHA).
-- Azure DevOps does not emit separate create/delete webhook events; confusio
-- derives the GitHub event type from the before/after SHA patterns.
b:webhook("git.push", function(payload)
  local resource = payload.resource or {}
  local repo = resource.repository or {}
  local ref_updates = resource.refUpdates or {}
  local update = ref_updates[1] or {}
  local pushed_by = resource.pushedBy or {}

  local ref_name_full = update.name or ""
  local before = update.oldObjectId or ZERO_SHA
  local after = update.newObjectId or ZERO_SHA

  local sender = ado_user(pushed_by)
  local repository = translate_ado_repo(repo)
  -- Derive ref_type from ref path; short name strips the refs/heads/ or refs/tags/ prefix.
  local ref_type = ref_name_full:match("^refs/tags/") and "tag" or "branch"
  local ref_short = ref_name_full:match("^refs/[^/]+/(.+)") or ref_name_full

  if before == ZERO_SHA then
    -- Branch or tag created — emit GitHub create event.
    return make_internal_event({
      event = "create",
      action = "create",
      provider = "azuredevops",
      raw = payload,
      data = {
        ref = ref_short,
        ref_type = ref_type,
        master_branch = repository.default_branch or "",
        description = repository.description,
        pusher_type = "user",
        repository = repository,
        sender = sender,
      },
      timestamp = payload.createdDate or "",
    })
  end

  if after == ZERO_SHA then
    -- Branch or tag deleted — emit GitHub delete event.
    return make_internal_event({
      event = "delete",
      action = "delete",
      provider = "azuredevops",
      raw = payload,
      data = {
        ref = ref_short,
        ref_type = ref_type,
        master_branch = repository.default_branch or "",
        description = repository.description,
        pusher_type = "user",
        repository = repository,
        sender = sender,
      },
      timestamp = payload.createdDate or "",
    })
  end

  -- Regular push — emit GitHub push event.
  local push_commits = {}
  for _, c in ipairs(resource.commits or {}) do
    push_commits[#push_commits + 1] = translate_ado_commit(c)
  end
  local head_commit = #push_commits > 0 and push_commits[1] or nil
  return make_internal_event({
    event = "push",
    action = "push",
    provider = "azuredevops",
    raw = payload,
    data = {
      ref = ref_name_full,
      before = before,
      after = after,
      created = false,
      deleted = false,
      forced = false,
      compare = "",
      commits = push_commits,
      head_commit = head_commit,
      pusher = {
        name = pushed_by.displayName or pushed_by.uniqueName or "",
        email = pushed_by.uniqueName or "",
      },
      repository = repository,
      sender = sender,
    },
    timestamp = payload.createdDate or "",
  })
end)

-- build.complete: fires when a Classic or YAML pipeline build finishes.
-- repository lifecycle: created, deleted, renamed.
-- ADO event types: git.repo.created, git.repo.deleted, git.repo.renamed.
-- For renamed events ADO does not include the old name in the payload, so
-- data.changes is omitted.  Mapped as ~ (partial) in the compatibility matrix.
local function ado_repo_lifecycle_handler(action)
  return function(payload)
    local resource = payload.resource or {}
    local data = {
      action = action,
      repository = translate_ado_repo(resource),
      sender = ado_user(resource.pushedBy or resource.createdBy),
    }
    return make_internal_event({
      event = "repository",
      action = action,
      provider = "azuredevops",
      raw = payload,
      data = data,
      timestamp = payload.createdDate or "",
    })
  end
end

b:webhook("git.repo.created", ado_repo_lifecycle_handler("created"))
b:webhook("git.repo.deleted", ado_repo_lifecycle_handler("deleted"))
b:webhook("git.repo.renamed", ado_repo_lifecycle_handler("renamed"))

b:webhook("ms.azure-devops-release.release-created-event", ado_release_event_handler("published"))
b:webhook("ms.azure-devops-release.release-abandoned-event", ado_release_event_handler("deleted"))

b:webhook("ms.azure-devops-release.deployment-started-event", function(payload)
  local resource = payload.resource or {}
  return make_internal_event({
    event = "deployment",
    action = "created",
    provider = "azuredevops",
    raw = payload,
    data = {
      action = "created",
      deployment = translate_ado_deployment(resource),
      repository = ado_deployment_repository(resource),
      sender = ado_deployment_sender(resource),
    },
    timestamp = payload.createdDate or "",
  })
end)

b:webhook("ms.azure-devops-release.deployment-completed-event", ado_deployment_status_handler)
b:webhook(
  "ms.azure-devops-release.deployment-approval-pending-event",
  ado_deployment_review_handler("requested")
)
b:webhook("ms.azure-devops-release.deployment-approval-completed-event", function(payload)
  local approval = ((payload.resource or {}).approval or {})
  local action = approval.status == "rejected" and "rejected" or "approved"
  return ado_deployment_review_handler(action)(payload)
end)

b:webhook("ms.vss-alerts.alert-created-event", ado_advsec_handler("created"))
b:webhook("ms.vss-alerts.alert-state-changed-event", ado_advsec_handler("state_changed"))
b:webhook("ms.vss-alerts.alert-updated-event", ado_advsec_handler("updated"))

b:webhook("build.complete", function(payload)
  local resource = payload.resource or {}
  local definition = resource.definition or {}
  local result = resource.result or ""
  local conclusion = ADO_BUILD_RESULT_TO_CONCLUSION[result] or "failure"
  -- Extract short branch name from "refs/heads/..." if present.
  local source_branch = resource.sourceBranch or ""
  local head_branch = source_branch:match("refs/heads/(.+)") or source_branch
  -- Prefer the browser-accessible URL from _links.web over the API URL.
  local web_href = ((resource._links or {}).web or {}).href or resource.url or ""
  local workflow_run = {
    id = resource.id,
    name = definition.name or "",
    head_branch = head_branch,
    head_sha = resource.sourceVersion or "",
    run_number = resource.id,
    event = "push",
    display_title = resource.buildNumber or "",
    status = "completed",
    conclusion = conclusion,
    workflow_id = definition.id or 0,
    url = web_href,
    html_url = web_href,
    pull_requests = {},
    created_at = resource.queueTime or "",
    updated_at = resource.finishTime or resource.startTime or "",
    run_attempt = 1,
    referenced_workflows = {},
    actor = ado_user(resource.requestedBy or resource.requestedFor),
    triggering_actor = ado_user(resource.requestedFor or resource.requestedBy),
  }
  local workflow = {
    id = definition.id or 0,
    name = definition.name or "",
    path = "",
    state = "active",
    url = "",
    html_url = "",
    badge_url = "",
    created_at = "",
    updated_at = "",
  }
  return make_internal_event({
    event = "workflow_run",
    action = "completed",
    provider = "azuredevops",
    raw = payload,
    data = {
      action = "completed",
      workflow_run = workflow_run,
      workflow = workflow,
      repository = translate_ado_repo(resource.repository),
      sender = ado_user(resource.requestedBy or resource.requestedFor),
    },
    timestamp = resource.finishTime or resource.startTime or "",
  })
end)

local ADO_ACTIONLESS_NORMALIZED_EVENTS = {
  create = true,
  delete = true,
  push = true,
}

local ADO_NORMALIZED_WEBHOOK_EVENTS = {
  "issues",
  "issue_comment",
  "pull_request",
  "pull_request_review",
  "workflow_run",
  "push",
  "create",
  "delete",
  "repository",
  "release",
  "deployment",
  "deployment_status",
  "deployment_review",
  "code_scanning_alert",
  "dependabot_alert",
  "secret_scanning_alert",
}

local function ado_normalized_payload_without_envelope_fields(data)
  local payload = {}
  for k, v in pairs(data or {}) do
    if k ~= "sender" and k ~= "repository" then
      payload[k] = v
    end
  end
  return payload
end

local function translate_ado_normalized_webhook(internal_event, fields)
  local data = internal_event.data or {}
  fields = fields or {}
  return make_normalized_webhook_envelope(internal_event, {
    id = fields.id,
    type = fields.type
      or (
        ADO_ACTIONLESS_NORMALIZED_EVENTS[internal_event.event]
          and normalized_webhook_event_type(internal_event.event, "")
        or normalized_webhook_event_type(internal_event.event, internal_event.action)
      ),
    occurred_at = fields.occurred_at,
    actor = fields.actor or data.sender,
    repository = fields.repository or data.repository,
    payload = fields.payload or ado_normalized_payload_without_envelope_fields(data),
  })
end

local function translate_ado_github_webhook(internal_event, fields)
  return github_webhook_payload(internal_event, fields)
end

for _, event in ipairs(ADO_NORMALIZED_WEBHOOK_EVENTS) do
  b:webhook_translator(event, translate_ado_normalized_webhook)
  b:webhook_github_translator(event, translate_ado_github_webhook)
end

b:build()
