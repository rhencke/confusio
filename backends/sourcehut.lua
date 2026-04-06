-- Sourcehut backend handler overrides.
-- Uses git.sr.ht REST API at /api/~{username}/repos/{name}.
-- Issues use todo.sr.ht REST API at /api/~{username}/trackers/{name}/tickets.
if config.base_url == "" then
  config.base_url = "https://git.sr.ht"
end

local base = function()
  return config.base_url .. "/api"
end

-- Derive the todo.sr.ht base URL from the git.sr.ht base URL.
-- In production: https://git.sr.ht → https://todo.sr.ht
-- In tests (IP:PORT): unchanged, same mock server handles both API path prefixes.
local todo_base = function()
  return config.base_url:gsub("git%.sr%.ht", "todo.sr.ht") .. "/api"
end
local auth = function()
  return make_fetch_opts("token")
end
local PAGES = { per_page = "limit" }

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
  if not r then
    return {}
  end
  local owner = r.owner or {}
  local canonical = owner.canonical_name or ""
  -- canonical_name is like "~username", strip the tilde for login
  local login = canonical:sub(1, 1) == "~" and canonical:sub(2) or canonical
  local vis = r.visibility or "public"
  return {
    id = r.id or 0,
    node_id = "",
    name = r.name,
    full_name = login .. "/" .. (r.name or ""),
    private = vis == "private",
    owner = {
      login = login,
      id = 0,
      node_id = "",
      avatar_url = "",
      url = "",
      html_url = config.base_url .. "/" .. canonical,
      type = "User",
    },
    html_url = config.base_url .. "/" .. canonical .. "/" .. (r.name or ""),
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
    archived = false,
    disabled = false,
    open_issues_count = 0,
    default_branch = r.HEAD and r.HEAD.name or "main",
    visibility = vis == "private" and "private" or "public",
    forks = 0,
    open_issues = 0,
    watchers = 0,
    created_at = r.created,
    updated_at = r.updated,
    pushed_at = r.updated,
  }
end

-- Translate GitHub create/update request body to Sourcehut format.
local function translate_srht_req(body_str)
  local req = DecodeJson(body_str or "{}")
  local sr = {}
  if req.name then
    sr.name = req.name
  end
  if req.description then
    sr.description = req.description
  end
  if req.private ~= nil then
    sr.visibility = req.private and "private" or "public"
  end
  return EncodeJson(sr)
end

-- Translate a Sourcehut ref to a GitHub branch object.
-- Only call for refs with names like "refs/heads/main".
local function translate_srht_branch(ref)
  if not ref then
    return {}
  end
  local name = ref.name and ref.name:match("^refs/heads/(.+)") or (ref.name or "")
  return {
    name = name,
    commit = { sha = ref.target or "", url = "" },
    protected = false,
  }
end

-- Translate a todo.sr.ht ticket to GitHub issue format.
-- Sourcehut: { id, created, updated, title, body, status, submitter: { canonical_name, name } }
local function translate_srht_ticket(t)
  if not t then
    return {}
  end
  local submitter = t.submitter or {}
  local canonical = submitter.canonical_name or ""
  local login = canonical:sub(1, 1) == "~" and canonical:sub(2) or (submitter.name or canonical)
  local status = t.status or "reported"
  local state = (status == "resolved" or status == "closed") and "closed" or "open"
  return {
    id = t.id or 0,
    node_id = "",
    number = t.id or 0,
    title = t.title or "",
    body = t.body or "",
    state = state,
    user = { login = login, id = 0, node_id = "", avatar_url = "", url = "", type = "User" },
    assignees = {},
    labels = {},
    milestone = nil,
    created_at = t.created or "",
    updated_at = t.updated or t.created or "",
    closed_at = nil,
    html_url = "",
  }
end

-- Translate a todo.sr.ht event to GitHub issue comment format.
-- Events with no comment field (status changes, etc.) are skipped by the caller.
-- event: { id, created, event_type, comment: { id, created, text, author } }
local function translate_srht_event_comment(e)
  if not e or not e.comment then
    return nil
  end
  local comment = e.comment
  local author = comment.author or {}
  local canonical = author.canonical_name or ""
  local login = canonical:sub(1, 1) == "~" and canonical:sub(2) or (author.name or canonical)
  return {
    id = comment.id or e.id or 0,
    node_id = "",
    url = "",
    body = comment.text or "",
    user = { login = login, id = 0, node_id = "", avatar_url = "", url = "", type = "User" },
    created_at = comment.created or e.created or "",
    updated_at = comment.created or e.created or "",
    html_url = "",
  }
end

-- Translate a Sourcehut log entry to GitHub commit format.
-- Sourcehut: { id, message, timestamp, author: { name, email } }
local proxy_handler = make_proxy_handler(fetch_json)

local function translate_srht_commit(c)
  if not c then
    return {}
  end
  local author = c.author or {}
  return {
    sha = c.id or "",
    commit = {
      message = c.message or "",
      author = { name = author.name or "", email = author.email or "", date = c.timestamp or "" },
      committer = { name = author.name or "", email = author.email or "", date = c.timestamp or "" },
    },
    author = { login = author.name or "", id = 0, avatar_url = "" },
    committer = { login = author.name or "", id = 0, avatar_url = "" },
  }
end

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, config.base_url .. "/api/version", auth())
    if ok and status == 200 then
      respond_json(200, {})
    else
      respond_json(503, {})
    end
  end,

  get_repo = proxy_handler(translate_srht_repo, function(owner, repo_name)
    return base() .. "/~" .. owner .. "/repos/" .. repo_name
  end),

  patch_repo = function(owner, repo_name)
    -- Sourcehut uses PUT for updates
    proxy_json(
      translate_srht_repo,
      fetch_json(
        base() .. "/~" .. owner .. "/repos/" .. repo_name,
        "PUT",
        translate_srht_req(GetBody())
      )
    )
  end,

  delete_repo = function(owner, repo_name)
    local url = base() .. "/~" .. owner .. "/repos/" .. repo_name
    local dopts = auth() or {}
    dopts.method = "DELETE"
    local ok, status = pcall(Fetch, url, dopts)
    if ok and (status == 204 or status == 200) then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, {})
    else
      respond_json(503, {})
    end
  end,

  get_user_repos = function()
    -- Sourcehut: need to know the authenticated user. Use /api/user first.
    local ok, status, _, ubody = fetch_json(config.base_url .. "/api/user")
    if not ok or status ~= 200 then
      respond_json(503, {})
      return
    end
    local user = DecodeJson(ubody)
    local canonical = user.canonical_name or ("~" .. (user.name or ""))
    proxy_json(
      function(data)
        local repos = data.results or {}
        for i, r in ipairs(repos) do
          repos[i] = translate_srht_repo(r)
        end
        return repos
      end,
      -- Sourcehut uses cursor-based pagination; only limit is supported for page size
      fetch_json(append_page_params(base() .. "/" .. canonical .. "/repos", PAGES))
    )
  end,

  post_user_repos = function()
    -- Sourcehut: create via POST /api/~{user}/repos — need user context
    local ok, status, _, ubody = fetch_json(config.base_url .. "/api/user")
    if not ok or status ~= 200 then
      respond_json(503, {})
      return
    end
    local user = DecodeJson(ubody)
    local canonical = user.canonical_name or ("~" .. (user.name or ""))
    proxy_json_created(
      translate_srht_repo,
      fetch_json(base() .. "/" .. canonical .. "/repos", "POST", translate_srht_req(GetBody()))
    )
  end,

  -- Branches ------------------------------------------------------------------
  -- Sourcehut: filter /refs for refs starting with "refs/heads/"

  get_repo_branches = proxy_handler(function(data)
    local branches = {}
    for _, ref in ipairs(data.results or {}) do
      if ref.name and ref.name:match("^refs/heads/") then
        branches[#branches + 1] = translate_srht_branch(ref)
      end
    end
    return branches
  end, function(owner, repo_name)
    return base() .. "/~" .. owner .. "/repos/" .. repo_name .. "/refs"
  end),

  get_repo_branch = proxy_handler(function(data, _owner, _repo_name, branch)
    for _, ref in ipairs(data.results or {}) do
      if ref.name == "refs/heads/" .. branch then
        return translate_srht_branch(ref)
      end
    end
    return {}
  end, function(owner, repo_name)
    return base() .. "/~" .. owner .. "/repos/" .. repo_name .. "/refs"
  end),

  -- Tags ----------------------------------------------------------------------
  -- Sourcehut /refs returns { results: [...] } with name and target fields
  -- Filter to tags only (refs starting with "refs/tags/")

  get_repo_tags = function(owner, repo_name)
    proxy_json(function(data)
      local tags = {}
      for _, ref in ipairs(data.results or {}) do
        local tag_name = ref.name and ref.name:match("^refs/tags/(.+)")
        if tag_name then
          tags[#tags + 1] = { name = tag_name, commit = { sha = ref.target or "", url = "" } }
        end
      end
      return tags
    end, fetch_json(base() .. "/~" .. owner .. "/repos/" .. repo_name .. "/refs"))
  end,

  -- Commits -------------------------------------------------------------------
  -- Sourcehut: GET /api/~{owner}/repos/{name}/log or /log/{ref}

  get_repo_commits = function(owner, repo_name)
    local ref = GetParam("sha") or ""
    local url = base() .. "/~" .. owner .. "/repos/" .. repo_name .. "/log"
    if ref ~= "" then
      url = url .. "/" .. ref
    end
    url = append_page_params(url, PAGES)
    proxy_json(function(data)
      local commits = data.results or {}
      for i, c in ipairs(commits) do
        commits[i] = translate_srht_commit(c)
      end
      return commits
    end, fetch_json(url))
  end,

  get_repo_commit = function(owner, repo_name, ref)
    -- Fetch the log at the specific ref and return first entry.
    proxy_json(
      function(data)
        local c = (data.results or {})[1]
        return translate_srht_commit(c)
      end,
      fetch_json(base() .. "/~" .. owner .. "/repos/" .. repo_name .. "/log/" .. ref .. "?limit=1")
    )
  end,

  -- Contents ------------------------------------------------------------------
  -- Sourcehut: GET /api/~{owner}/repos/{name}/blob/{ref}/{path} — raw bytes.

  get_repo_readme = function(owner, repo_name)
    local ref = GetParam("ref") or "HEAD"
    local candidates = { "README.md", "README", "readme.md", "README.rst" }
    for _, fname in ipairs(candidates) do
      local url = base()
        .. "/~"
        .. owner
        .. "/repos/"
        .. repo_name
        .. "/blob/"
        .. ref
        .. "/"
        .. fname
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
  end,

  get_repo_content = function(owner, repo_name, path)
    local ref = GetParam("ref") or "HEAD"
    local url = base() .. "/~" .. owner .. "/repos/" .. repo_name .. "/blob/" .. ref .. "/" .. path
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
  end,

  -- Users' repos --------------------------------------------------------------

  get_users_repos = function(username)
    proxy_json(function(data)
      local repos = data.results or {}
      for i, r in ipairs(repos) do
        repos[i] = translate_srht_repo(r)
      end
      return repos
    end, fetch_json(append_page_params(base() .. "/~" .. username .. "/repos", PAGES)))
  end,

  -- Users ---------------------------------------------------------------------

  -- GET /user
  get_user = function()
    proxy_json(function(u)
      if not u then
        return {}
      end
      local canonical = u.canonical_name or ""
      local login = canonical:sub(1, 1) == "~" and canonical:sub(2) or canonical
      return {
        login = login,
        id = 0,
        node_id = "",
        avatar_url = "",
        html_url = config.base_url .. "/" .. canonical,
        type = "User",
        site_admin = false,
        name = u.name or canonical,
        email = u.email or "",
        blog = u.url or "",
      }
    end, fetch_json(base() .. "/user"))
  end,

  -- Issues --------------------------------------------------------------------
  -- todo.sr.ht: GET /api/~{owner}/trackers/{repo}/tickets

  get_repo_issues = function(owner, repo_name)
    local url = todo_base() .. "/~" .. owner .. "/trackers/" .. repo_name .. "/tickets"
    url = append_page_params(url, PAGES)
    proxy_json(function(data)
      local tickets = data.results or {}
      local result = {}
      for _, t in ipairs(tickets) do
        result[#result + 1] = translate_srht_ticket(t)
      end
      return result
    end, fetch_json(url))
  end,

  -- GET /repos/{owner}/{repo}/issues/{issue_number}
  get_repo_issue = function(owner, repo_name, issue_number)
    local url = todo_base()
      .. "/~"
      .. owner
      .. "/trackers/"
      .. repo_name
      .. "/tickets/"
      .. issue_number
    local ok, status, _, body = fetch_json(url)
    if not ok then
      respond_json(503, {})
      return
    end
    if status == 404 then
      respond_json(404, { message = "Not Found" })
      return
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    local ticket = DecodeJson(body)
    respond_json(200, translate_srht_ticket(ticket))
  end,

  -- POST /repos/{owner}/{repo}/issues
  post_repo_issues = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
    local payload = EncodeJson({ title = req.title or "", description = req.body or "" })
    local ok, status, _, body = fetch_json(
      todo_base() .. "/~" .. owner .. "/trackers/" .. repo_name .. "/tickets",
      "POST",
      payload
    )
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 and status ~= 201 then
      respond_json(status, {})
      return
    end
    local ticket = DecodeJson(body)
    respond_json(201, translate_srht_ticket(ticket))
  end,

  -- GET /repos/{owner}/{repo}/issues/{issue_number}/comments
  -- todo.sr.ht: GET /api/~{owner}/trackers/{repo}/tickets/{id}/events
  -- Filter events to only those with a comment field.
  get_issue_comments = function(owner, repo_name, issue_number)
    local url = todo_base()
      .. "/~"
      .. owner
      .. "/trackers/"
      .. repo_name
      .. "/tickets/"
      .. issue_number
      .. "/events"
    url = append_page_params(url, PAGES)
    proxy_json(function(data)
      local events = data.results or {}
      local comments = {}
      for _, e in ipairs(events) do
        local c = translate_srht_event_comment(e)
        if c then
          comments[#comments + 1] = c
        end
      end
      return comments
    end, fetch_json(url))
  end,

  -- POST /repos/{owner}/{repo}/issues/{issue_number}/comments
  post_issue_comment = function(owner, repo_name, issue_number)
    local req = DecodeJson(GetBody() or "{}")
    local payload = EncodeJson({ comment = req.body or "" })
    local url = todo_base()
      .. "/~"
      .. owner
      .. "/trackers/"
      .. repo_name
      .. "/tickets/"
      .. issue_number
      .. "/events"
    local ok, status, _, body = fetch_json(url, "POST", payload)
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 and status ~= 201 then
      respond_json(status, {})
      return
    end
    local event = DecodeJson(body)
    local comment = translate_srht_event_comment(event)
    respond_json(201, comment or {})
  end,
}
