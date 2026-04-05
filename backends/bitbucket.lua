-- Bitbucket backend handler overrides.
-- Uses Bitbucket REST API v2 at /2.0/.
if config.base_url == "" then config.base_url = "https://api.bitbucket.org" end

local base = function() return config.base_url .. "/2.0" end
local auth = function() return make_fetch_opts("basic") end
local PAGES = { per_page = "pagelen", page = "page" }

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

-- Map a Bitbucket repository object to GitHub format.
local function translate_bb_repo(r)
  if not r then return {} end
  local owner = r.owner or {}
  local main = r.mainbranch or {}
  return {
    id                = 0,
    node_id           = r.uuid or "",
    name              = r.slug or r.name,
    full_name         = r.full_name,
    private           = r.is_private,
    owner             = {
      login      = owner.nickname or owner.display_name or "",
      id         = 0,
      node_id    = owner.uuid or "",
      avatar_url = (owner.links and owner.links.avatar and owner.links.avatar.href) or "",
      url        = "",
      html_url   = (owner.links and owner.links.html and owner.links.html.href) or "",
      type       = owner.type == "team" and "Organization" or "User",
    },
    html_url          = (r.links and r.links.html and r.links.html.href) or "",
    description       = r.description,
    fork              = r.parent ~= nil,
    url               = (r.links and r.links.self and r.links.self.href) or "",
    clone_url         = "",
    homepage          = r.website or "",
    size              = r.size or 0,
    stargazers_count  = 0,
    watchers_count    = 0,
    language          = r.language,
    has_issues        = r.has_issues,
    has_wiki          = r.has_wiki,
    forks_count       = 0,
    archived          = false,
    disabled          = false,
    open_issues_count = 0,
    default_branch    = main.name or "main",
    visibility        = r.is_private and "private" or "public",
    forks             = 0,
    open_issues       = 0,
    watchers          = 0,
    created_at        = r.created_on,
    updated_at        = r.updated_on,
    pushed_at         = r.updated_on,
  }
end

-- Translate GitHub create/update request body to Bitbucket format.
-- Map a Bitbucket user object to GitHub format.
local function translate_bb_user(u)
  if not u then return {} end
  local links = u.links or {}
  return {
    login      = u.nickname or u.display_name or "",
    id         = 0,
    node_id    = u.account_id or "",
    avatar_url = (links.avatar and links.avatar.href) or "",
    html_url   = (links.html and links.html.href) or "",
    type       = "User",
    site_admin = false,
    name       = u.display_name,
  }
end

local function translate_bb_req(body_str)
  local req = DecodeJson(body_str or "{}")
  local bb = {}
  if req.name        then bb.name        = req.name end
  if req.description then bb.description = req.description end
  if req.private ~= nil then bb.is_private = req.private end
  if req.homepage    then bb.website     = req.homepage end
  if req.has_issues  ~= nil then bb.has_issues = req.has_issues end
  if req.has_wiki    ~= nil then bb.has_wiki   = req.has_wiki end
  return EncodeJson(bb)
end

local function translate_bb_commit(c)
  if not c then return {} end
  local author = c.author or {}
  local user   = author.user or {}
  local parents = {}
  for _, p in ipairs(c.parents or {}) do
    parents[#parents + 1] = { sha = p.hash or "" }
  end
  return {
    sha    = c.hash or "",
    commit = {
      message   = c.message or "",
      author    = {
        name  = user.display_name or author.raw or "",
        email = "",
        date  = c.date or "",
      },
      committer = {
        name  = user.display_name or author.raw or "",
        email = "",
        date  = c.date or "",
      },
    },
    author    = { login = user.nickname or "", id = 0 },
    committer = { login = user.nickname or "", id = 0 },
    parents   = parents,
  }
end

local function bb_state_to_github(state)
  if state == "SUCCESSFUL" then return "success"
  elseif state == "FAILED"     then return "failure"
  elseif state == "INPROGRESS" then return "pending"
  else return "error" end
end

local function github_state_to_bb(state)
  if state == "success" then return "SUCCESSFUL"
  elseif state == "failure" then return "FAILED"
  elseif state == "pending" then return "INPROGRESS"
  else return "FAILED" end
end

local function translate_bb_status(s)
  return {
    state       = bb_state_to_github(s.state),
    context     = s.key or "",
    description = s.description or "",
    target_url  = s.url or "",
    created_at  = s.created_on or "",
    updated_at  = s.updated_on or "",
  }
end

local function translate_bb_key(k)
  return {
    id         = k.id or 0,
    key        = k.key or "",
    title      = k.label or "",
    read_only  = true,
    verified   = true,
    created_at = k.created_on or "",
  }
end

local function translate_bb_hook(h)
  local events = {}
  for _, e in ipairs(h.events or {}) do
    -- "repo:push" → "push", "pullrequest:created" → "pull_request"
    events[#events + 1] = (e:match(":(.+)$") or e):gsub("_", ".")
  end
  return {
    id     = h.uuid and h.uuid:gsub("[{}]", "") or "",
    config = { url = h.url or "", content_type = "json" },
    events = events,
    active = h.active ~= false,
  }
end

local proxy_handler         = make_proxy_handler(fetch_json)
local proxy_handler_created = make_proxy_handler_created(fetch_json)

-- Translate a Bitbucket issue to GitHub format.
-- Bitbucket states: "open", "resolved", "wontfix", "invalid", "duplicate", "on hold", "closed"
local function translate_bb_issue(i)
  if not i then return {} end
  local content = (i.content or {}).raw or ""
  local state = (i.state == "open") and "open" or "closed"
  local reporter = translate_bb_user(i.reporter)
  local assignees = {}
  if i.assignee then assignees[1] = translate_bb_user(i.assignee) end
  local ms = nil
  if i.milestone and i.milestone.name then
    ms = {
      id         = i.milestone.id or 0,
      number     = i.milestone.id or 0,
      title      = i.milestone.name,
      state      = "open",
      created_at = "",
      updated_at = "",
    }
  end
  return {
    id         = i.id or 0,
    number     = i.id or 0,
    title      = i.title or "",
    body       = content,
    state      = state,
    user       = reporter,
    assignees  = assignees,
    labels     = {},
    milestone  = ms,
    created_at = i.created_on or "",
    updated_at = i.updated_on or "",
    closed_at  = nil,
    html_url   = (i.links and i.links.html and i.links.html.href) or "",
  }
end

-- Translate a Bitbucket issue comment to GitHub format.
local function translate_bb_issue_comment(c)
  if not c then return {} end
  local content = (c.content or {}).raw or ""
  return {
    id         = c.id or 0,
    body       = content,
    user       = translate_bb_user(c.author),
    created_at = c.created_on or "",
    updated_at = c.updated_on or "",
    html_url   = (c.links and c.links.html and c.links.html.href) or "",
  }
end

-- Translate a Bitbucket milestone to GitHub format.
-- Bitbucket milestone: { id, name, resource_uri }
local function translate_bb_milestone(m)
  if not m then return {} end
  return {
    id         = m.id or 0,
    number     = m.id or 0,
    title      = m.name or "",
    state      = "open",
    created_at = "",
    updated_at = "",
  }
end

local function translate_bb_issues(data)
  local issues = data.values or {}
  for i, iss in ipairs(issues) do issues[i] = translate_bb_issue(iss) end
  return issues
end
local function translate_bb_issue_comments_list(data)
  local comments = data.values or {}
  for i, c in ipairs(comments) do comments[i] = translate_bb_issue_comment(c) end
  return comments
end
local function translate_bb_milestones(data)
  local ms = data.values or {}
  for i, m in ipairs(ms) do ms[i] = translate_bb_milestone(m) end
  return ms
end

local function translate_bb_hook_req(body_str)
  local req = DecodeJson(body_str or "{}")
  local bb_events = {}
  for _, e in ipairs(req.events or {}) do
    bb_events[#bb_events + 1] = "repo:" .. e
  end
  return EncodeJson({
    description = (req.config and req.config.url) or req.url or "",
    url         = (req.config and req.config.url) or req.url or "",
    active      = req.active ~= false,
    events      = #bb_events > 0 and bb_events or { "repo:push" },
  })
end

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, base() .. "/user", auth())
    if ok and status == 200 then respond_json(200, "OK", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_repo = proxy_handler(translate_bb_repo, function(o, r)
    return base().."/repositories/"..o.."/"..r
  end),

  patch_repo = function(owner, repo_name)
    proxy_json(translate_bb_repo,
      fetch_json(base() .. "/repositories/" .. owner .. "/" .. repo_name,
        "PUT", translate_bb_req(GetBody())))
  end,

  delete_repo = function(owner, repo_name)
    local url = base() .. "/repositories/" .. owner .. "/" .. repo_name
    local dopts = auth() or {}; dopts.method = "DELETE"
    local ok, status = pcall(Fetch, url, dopts)
    if ok and status == 204 then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_user_repos = function()
    -- Bitbucket: list repos for authenticated user via /repositories?role=member
    proxy_json(
      function(data)
        local repos = data.values or {}
        for i, r in ipairs(repos) do repos[i] = translate_bb_repo(r) end
        return repos
      end,
      fetch_json(append_page_params(base() .. "/repositories?role=member",
        PAGES)))
  end,

  post_user_repos = function()
    -- Bitbucket requires workspace; no equivalent single endpoint.
    respond_json(501, "Not Implemented",
      { message = "POST /user/repos requires workspace context; use POST /orgs/{workspace}/repos" })
  end,

  get_org_repos = function(workspace)
    proxy_json(
      function(data)
        local repos = data.values or {}
        for i, r in ipairs(repos) do repos[i] = translate_bb_repo(r) end
        return repos
      end,
      fetch_json(append_page_params(base() .. "/repositories/" .. workspace,
        PAGES)))
  end,

  post_org_repos = function(workspace)
    local raw = GetBody() or "{}"
    local req = DecodeJson(raw)
    local slug = req.name
    if not slug then
      respond_json(422, "Unprocessable Entity", { message = "name required" }); return
    end
    proxy_json_created(translate_bb_repo,
      fetch_json(base() .. "/repositories/" .. workspace .. "/" .. slug,
        "POST", translate_bb_req(raw)))
  end,

  -- GET /users/{username}/repos
  get_users_repos = function(username)
    proxy_json(
      function(data)
        local repos = data.values or {}
        for i, r in ipairs(repos) do repos[i] = translate_bb_repo(r) end
        return repos
      end,
      fetch_json(append_page_params(
        base() .. "/repositories/" .. username,
        PAGES)))
  end,

  -- GET /repositories (public)
  get_repositories = function()
    proxy_json(
      function(data)
        local repos = data.values or {}
        for i, r in ipairs(repos) do repos[i] = translate_bb_repo(r) end
        return repos
      end,
      fetch_json(append_page_params(base() .. "/repositories",
        PAGES)))
  end,

  get_repo_languages = function(owner, repo_name)
    -- Bitbucket exposes primary language only via repo object; no language breakdown.
    proxy_json(
      function(r)
        local lang = r.language
        return lang and lang ~= "" and { [lang] = 0 } or {}
      end,
      fetch_json(base() .. "/repositories/" .. owner .. "/" .. repo_name))
  end,

  get_repo_tags = function(owner, repo_name)
    proxy_json(
      function(data)
        local tags = data.values or {}
        for i, t in ipairs(tags) do
          local tgt = t.target or {}
          tags[i] = { name = t.name, commit = { sha = tgt.hash or "", url = "" } }
        end
        return tags
      end,
      fetch_json(append_page_params(
        base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/refs/tags",
        PAGES)))
  end,

  -- Branches ------------------------------------------------------------------

  get_repo_branches = function(owner, repo_name)
    proxy_json(
      function(data)
        local branches = data.values or {}
        for i, b in ipairs(branches) do
          branches[i] = {
            name      = b.name,
            commit    = { sha = (b.target and b.target.hash) or "", url = "" },
            protected = false,
          }
        end
        return branches
      end,
      fetch_json(append_page_params(
        base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/refs/branches",
        PAGES)))
  end,

  get_repo_branch = function(owner, repo_name, branch)
    proxy_json(
      function(b)
        return {
          name      = b.name,
          commit    = { sha = (b.target and b.target.hash) or "", url = "" },
          protected = false,
        }
      end,
      fetch_json(base() .. "/repositories/" .. owner .. "/" .. repo_name ..
        "/refs/branches/" .. branch))
  end,

  -- Commits -------------------------------------------------------------------

  get_repo_commits = function(owner, repo_name)
    proxy_json(
      function(data)
        local commits = data.values or {}
        for i, c in ipairs(commits) do commits[i] = translate_bb_commit(c) end
        return commits
      end,
      fetch_json(append_page_params(
        base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/commits",
        PAGES)))
  end,

  get_repo_commit = proxy_handler(translate_bb_commit, function(o, r, sha)
    return base().."/repositories/"..o.."/"..r.."/commit/"..sha
  end),

  -- Commit statuses -----------------------------------------------------------

  get_commit_statuses = function(owner, repo_name, sha)
    proxy_json(
      function(data)
        local statuses = data.values or {}
        for i, s in ipairs(statuses) do statuses[i] = translate_bb_status(s) end
        return statuses
      end,
      fetch_json(append_page_params(
        base() .. "/repositories/" .. owner .. "/" .. repo_name ..
          "/commit/" .. sha .. "/statuses",
        PAGES)))
  end,

  get_commit_combined_status = function(owner, repo_name, sha)
    proxy_json(
      function(data)
        local statuses = data.values or {}
        local combined = "success"
        for _, s in ipairs(statuses) do
          local g = bb_state_to_github(s.state)
          if g == "failure" or g == "error" then combined = g; break
          elseif g == "pending" then combined = "pending" end
        end
        local out = {}
        for i, s in ipairs(statuses) do out[i] = translate_bb_status(s) end
        return { state = combined, statuses = out, total_count = #out }
      end,
      fetch_json(base() .. "/repositories/" .. owner .. "/" .. repo_name ..
        "/commit/" .. sha .. "/statuses"))
  end,

  post_commit_status = function(owner, repo_name, sha)
    local req = DecodeJson(GetBody() or "{}")
    local bb = {
      state       = github_state_to_bb(req.state or ""),
      key         = req.context or "default",
      url         = req.target_url or "",
      name        = req.context or "default",
      description = req.description or "",
    }
    proxy_json(translate_bb_status,
      fetch_json(base() .. "/repositories/" .. owner .. "/" .. repo_name ..
        "/commit/" .. sha .. "/statuses/build", "POST", EncodeJson(bb)))
  end,

  -- Contents ------------------------------------------------------------------

  get_repo_readme = function(owner, repo_name)
    local repo_url = base() .. "/repositories/" .. owner .. "/" .. repo_name
    local ok, status, _, body = fetch_json(repo_url)
    if not ok or status ~= 200 then respond_json(404, "Not Found", {}); return end
    local repo = DecodeJson(body or "{}")
    local ref = (repo.mainbranch and repo.mainbranch.name) or "HEAD"
    for _, name in ipairs({ "README.md", "README", "readme.md", "Readme.md" }) do
      local ok2, status2, _, body2 = fetch_json(repo_url .. "/src/" .. ref .. "/" .. name)
      if ok2 and status2 == 200 then
        respond_json(200, "OK", {
          type = "file", encoding = "base64",
          content = EncodeBase64(body2 or ""),
          name = name, path = name, sha = "", size = #(body2 or ""),
        })
        return
      end
    end
    respond_json(404, "Not Found", { message = "README not found" })
  end,

  get_repo_content = function(owner, repo_name, path)
    local ref = GetParam("ref") or "HEAD"
    local ok, status, _, body = fetch_json(
      base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/src/" .. ref .. "/" .. path)
    if not ok then respond_json(503, "Service Unavailable", {}); return end
    if status ~= 200 then respond_json(status, "Not Found", {}); return end
    -- Detect directory listing (JSON with "values") vs raw file content
    local parsed = (body and body:sub(1, 1) == "{") and DecodeJson(body) or nil
    if parsed and parsed.values then
      local out = {}
      for _, e in ipairs(parsed.values or {}) do
        out[#out + 1] = {
          type = e.type == "commit_directory" and "dir" or "file",
          name = e.path and e.path:match("[^/]+$") or "",
          path = e.path or "",
          sha  = "",
          size = e.size or 0,
        }
      end
      respond_json(200, "OK", out)
    else
      respond_json(200, "OK", {
        type = "file", encoding = "base64",
        content = EncodeBase64(body or ""),
        name = path:match("[^/]+$") or path,
        path = path, sha = "", size = #(body or ""),
      })
    end
  end,

  -- Forks ---------------------------------------------------------------------

  get_repo_forks = function(owner, repo_name)
    proxy_json(
      function(data)
        local forks = data.values or {}
        for i, r in ipairs(forks) do forks[i] = translate_bb_repo(r) end
        return forks
      end,
      fetch_json(append_page_params(
        base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/forks",
        PAGES)))
  end,

  post_repo_forks = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
    local bb = {}
    if req.organization then bb.workspace = req.organization end
    if req.name         then bb.name      = req.name end
    proxy_json_created(translate_bb_repo,
      fetch_json(base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/forks",
        "POST", EncodeJson(bb)))
  end,

  -- Deploy keys ---------------------------------------------------------------

  get_repo_keys = function(owner, repo_name)
    proxy_json(
      function(data)
        local keys = data.values or {}
        for i, k in ipairs(keys) do keys[i] = translate_bb_key(k) end
        return keys
      end,
      fetch_json(append_page_params(
        base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/deploy-keys",
        PAGES)))
  end,

  post_repo_keys = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
    local bb = { key = req.key or "", label = req.title or "" }
    proxy_json_created(translate_bb_key,
      fetch_json(base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/deploy-keys",
        "POST", EncodeJson(bb)))
  end,

  get_repo_key = proxy_handler(translate_bb_key, function(o, r, key_id)
    return base().."/repositories/"..o.."/"..r.."/deploy-keys/"..key_id
  end),

  delete_repo_key = function(owner, repo_name, key_id)
    local url = base() .. "/repositories/" .. owner .. "/" .. repo_name ..
      "/deploy-keys/" .. key_id
    local dopts = auth() or {}; dopts.method = "DELETE"
    local ok, status = pcall(Fetch, url, dopts)
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- Webhooks ------------------------------------------------------------------

  get_repo_hooks = function(owner, repo_name)
    proxy_json(
      function(data)
        local hooks = data.values or {}
        for i, h in ipairs(hooks) do hooks[i] = translate_bb_hook(h) end
        return hooks
      end,
      fetch_json(append_page_params(
        base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/hooks",
        PAGES)))
  end,

  post_repo_hooks = function(owner, repo_name)
    proxy_json_created(translate_bb_hook,
      fetch_json(base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/hooks",
        "POST", translate_bb_hook_req(GetBody())))
  end,

  get_repo_hook = function(owner, repo_name, hook_id)
    proxy_json(translate_bb_hook,
      fetch_json(base() .. "/repositories/" .. owner .. "/" .. repo_name ..
        "/hooks/{" .. hook_id .. "}"))
  end,

  patch_repo_hook = function(owner, repo_name, hook_id)
    proxy_json(translate_bb_hook,
      fetch_json(base() .. "/repositories/" .. owner .. "/" .. repo_name ..
        "/hooks/{" .. hook_id .. "}", "PUT", translate_bb_hook_req(GetBody())))
  end,

  delete_repo_hook = function(owner, repo_name, hook_id)
    local url = base() .. "/repositories/" .. owner .. "/" .. repo_name ..
      "/hooks/{" .. hook_id .. "}"
    local dopts = auth() or {}; dopts.method = "DELETE"
    local ok, status = pcall(Fetch, url, dopts)
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- Users ---------------------------------------------------------------------

  -- GET /user
  get_user = proxy_handler(translate_bb_user, function() return base().."/user" end),

  -- GET /users/{username}
  get_users_username = proxy_handler(translate_bb_user, function(username)
    return base().."/users/"..username
  end),

  -- Issues --------------------------------------------------------------------

  get_repo_issues = proxy_handler(translate_bb_issues, function(o, r)
    return append_page_params(base().."/repositories/"..o.."/"..r.."/issues", PAGES)
  end),

  get_repo_issue = proxy_handler(translate_bb_issue, function(o, r, n)
    return base().."/repositories/"..o.."/"..r.."/issues/"..n
  end),

  get_issue_comments = proxy_handler(translate_bb_issue_comments_list, function(o, r, n)
    return append_page_params(
      base().."/repositories/"..o.."/"..r.."/issues/"..n.."/comments", PAGES)
  end),

  get_repo_milestones = proxy_handler(translate_bb_milestones, function(o, r)
    return base().."/repositories/"..o.."/"..r.."/milestones"
  end),
}
