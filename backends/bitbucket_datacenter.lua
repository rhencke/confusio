-- Bitbucket Datacenter (Server) backend handler overrides.
-- Uses Bitbucket Server REST API v1 at /rest/api/1.0/.
-- Repos are addressed as /projects/{projectKey}/repos/{slug}.
-- Personal project keys use the ~username convention (e.g. ~octocat).

local base = function()
  return config.base_url .. "/rest/api/1.0"
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

-- Bitbucket DC pagination: { values, isLastPage, start, limit }
-- Upstream query params: start (offset) and limit (page size).
local function bbs_page_url(url)
  local sep = url:find("?") and "&" or "?"
  local pp = GetParam("per_page")
  local pg = GetParam("page")
  if pp and pp ~= "" then
    local limit = tonumber(pp) or 25
    local page = tonumber(pg) or 1
    url = url .. sep .. "limit=" .. limit .. "&start=" .. ((page - 1) * limit)
  end
  return url
end

-- Map a Bitbucket DC project key + repo object to GitHub format.
local function translate_bbs_repo(r, proj_key)
  if not r then
    return {}
  end
  local proj = r.project or {}
  local key = proj_key or proj.key or ""
  -- Strip leading ~ for the display login; keep ~ if it's a personal project
  local login = key:match("^~(.+)$") or key
  local links = r.links or {}
  local self_links = links.self or {}
  local html_url = (self_links[1] and self_links[1].href) or ""
  return {
    id = r.id or 0,
    node_id = "",
    name = r.slug or r.name or "",
    full_name = login .. "/" .. (r.slug or r.name or ""),
    private = not (r.public or false),
    owner = {
      login = login,
      id = proj.id or 0,
      node_id = "",
      avatar_url = "",
      url = "",
      html_url = "",
      type = proj.type == "PERSONAL" and "User" or "Organization",
    },
    html_url = html_url,
    description = r.description,
    fork = r.origin ~= nil,
    url = html_url,
    clone_url = "",
    homepage = "",
    size = 0,
    stargazers_count = 0,
    watchers_count = 0,
    language = nil,
    has_issues = false,
    has_wiki = false,
    forks_count = 0,
    archived = r.archived or false,
    disabled = false,
    open_issues_count = 0,
    default_branch = r.default_branch or "main",
    visibility = (r.public or false) and "public" or "private",
    forks = 0,
    open_issues = 0,
    watchers = 0,
    created_at = nil,
    updated_at = nil,
    pushed_at = nil,
  }
end

-- Map a Bitbucket DC user object to GitHub format.
local function translate_bbs_user(u)
  if not u then
    return {}
  end
  return {
    login = u.name or u.slug or "",
    id = u.id or 0,
    node_id = "",
    avatar_url = "",
    html_url = "",
    type = "User",
    site_admin = false,
    name = u.displayName or "",
    email = u.emailAddress or "",
  }
end

local function translate_bbs_repos(data, proj_key)
  local repos = (data and data.values) or {}
  for i, r in ipairs(repos) do
    repos[i] = translate_bbs_repo(r, proj_key)
  end
  return repos
end

-- Translate GitHub create/update request body to Bitbucket DC format.
local function translate_bbs_req(body_str)
  local req = DecodeJson(body_str or "{}")
  local bbs = {}
  if req.name then
    bbs.name = req.name
  end
  if req.description then
    bbs.description = req.description
  end
  if req.private ~= nil then
    bbs.public = not req.private
  end
  return EncodeJson(bbs)
end

-- Translate a DC branch object to GitHub format.
-- DC: { id: "refs/heads/main", displayId: "main", latestCommit: "abc123..." }
local function translate_bbs_branch(b)
  if not b then
    return {}
  end
  return {
    name = b.displayId or b.id and b.id:match("refs/heads/(.+)") or "",
    commit = { sha = b.latestCommit or b.latestChangeset or "", url = "" },
    protected = false,
  }
end

-- Translate a DC commit object to GitHub format.
-- DC: { id, displayId, author: { name, emailAddress }, authorTimestamp, message }
local function translate_bbs_commit(c)
  if not c then
    return {}
  end
  local author = c.author or {}
  local ts = c.authorTimestamp
  local date = ts and os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(ts / 1000)) or ""
  return {
    sha = c.id or "",
    commit = {
      message = c.message or "",
      author = { name = author.name or "", email = author.emailAddress or "", date = date },
      committer = { name = author.name or "", email = author.emailAddress or "", date = date },
    },
    author = { login = author.name or "", id = 0, avatar_url = "" },
    committer = { login = author.name or "", id = 0, avatar_url = "" },
  }
end

-- Translate a DC deploy key to GitHub format.
-- DC: { id, key: { id, label, text, createdDate } }
local function translate_bbs_key(k)
  if not k then
    return {}
  end
  local key = k.key or {}
  return {
    id = k.id or 0,
    key = key.text or "",
    title = key.label or "",
    read_only = true,
    verified = true,
    created_at = nil,
  }
end

-- Translate a DC webhook to GitHub format.
-- DC: { id, name, url, events: [...], active, configuration: {...} }
local function translate_bbs_hook(h)
  if not h then
    return {}
  end
  return {
    id = h.id or 0,
    name = h.name or "web",
    active = h.active ~= false,
    events = h.events or {},
    config = { url = h.url or "", content_type = "json" },
    created_at = nil,
    updated_at = nil,
  }
end

local function translate_bbs_hook_req(body_str)
  local req = DecodeJson(body_str or "{}")
  local cfg = req.config or {}
  return EncodeJson({
    name = req.name or "web",
    url = cfg.url or "",
    active = req.active ~= false,
    events = req.events or { "repo:refs_changed" },
  })
end

-- Proxy a BBS paginated response to the GitHub search envelope.
local function proxy_search_bbs(translate_item, url)
  local ok, status, _, body = fetch_json(url)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local raw = DecodeJson(body) or {}
  local items = {}
  for i, item in ipairs(raw.values or {}) do
    items[i] = translate_item(item)
  end
  set_preamble()
  Write(
    '{"total_count":'
      .. #items
      .. ',"incomplete_results":false,"items":'
      .. (#items > 0 and EncodeJson(items) or "[]")
      .. "}"
  )
end

local proxy_handler = make_proxy_handler(fetch_json)

-- Repo path helper: /projects/{owner}/repos/{repo}
local function repo_path(owner, repo_name)
  return base() .. "/projects/" .. owner .. "/repos/" .. repo_name
end

-- DC timestamp (ms epoch) to ISO-8601 string.
local function bbs_ts(ms)
  if not ms then
    return nil
  end
  return os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(ms / 1000))
end

-- Map a DC pull request ref (fromRef/toRef) to GitHub head/base format.
local function translate_bbs_pr_ref(ref)
  if not ref then
    return {}
  end
  local repo = ref.repository or {}
  local proj = repo.project or {}
  local owner = proj.key or ""
  -- Strip leading ~ for personal projects
  owner = owner:match("^~(.+)$") or owner
  return {
    label = owner ~= "" and (owner .. "/" .. (repo.slug or "") .. ":" .. (ref.displayId or ""))
      or (ref.displayId or ""),
    ref = ref.displayId or (ref.id and ref.id:match("refs/heads/(.+)")) or "",
    sha = ref.latestCommit or "",
  }
end

-- Map a DC pull request object to GitHub format.
local function translate_bbs_pull(pr)
  if not pr then
    return {}
  end
  local state = pr.state or ""
  local is_merged = state == "MERGED"
  local gh_state = state == "OPEN" and "open" or "closed"
  local author_obj = pr.author or {}
  local created = bbs_ts(pr.createdDate)
  local updated = bbs_ts(pr.updatedDate)
  local self_links = (pr.links and pr.links.self) or {}
  local html_url = (self_links[1] and self_links[1].href) or ""
  return {
    id = pr.id or 0,
    node_id = "",
    number = pr.id or 0,
    state = gh_state,
    locked = false,
    title = pr.title or "",
    body = pr.description or "",
    user = translate_bbs_user(author_obj.user),
    head = translate_bbs_pr_ref(pr.fromRef),
    base = translate_bbs_pr_ref(pr.toRef),
    draft = false,
    created_at = created or "",
    updated_at = updated or "",
    closed_at = (not is_merged and gh_state == "closed") and updated or nil,
    merged_at = is_merged and updated or nil,
    merge_commit_sha = nil,
    merged_by = nil,
    html_url = html_url,
    url = html_url,
    diff_url = "",
    patch_url = "",
    mergeable = state == "OPEN" or nil,
    comments = 0,
    review_comments = 0,
    commits = 0,
    additions = 0,
    deletions = 0,
    changed_files = 0,
  }
end

local function translate_bbs_pulls(data)
  local prs = (data and data.values) or {}
  for i, pr in ipairs(prs) do
    prs[i] = translate_bbs_pull(pr)
  end
  return prs
end

-- Map a DC pull request change entry to GitHub file format.
-- DC: { path: { toString: "README.md" }, type: "ADD"|"MODIFY"|"DELETE"|"MOVE" }
local function translate_bbs_pr_change(c)
  if not c then
    return {}
  end
  local path_obj = c.path or {}
  local fname = path_obj.toString or path_obj.name or ""
  local dc_type = c.type or "MODIFY"
  local status = dc_type == "ADD" and "added"
    or dc_type == "DELETE" and "removed"
    or dc_type == "MOVE" and "renamed"
    or "modified"
  return {
    sha = "",
    filename = fname,
    status = status,
    additions = 0,
    deletions = 0,
    changes = 0,
    patch = "",
  }
end

-- Map a DC pull request comment to GitHub review comment format.
-- DC: { id, text, author: { name, displayName, ... }, createdDate, updatedDate,
--       anchor: { path, line, lineType, fileType } }
local function translate_bbs_pr_comment(c)
  if not c then
    return {}
  end
  local anchor = c.anchor or {}
  return {
    id = c.id or 0,
    node_id = "",
    path = anchor.path or "",
    position = anchor.line,
    original_position = anchor.line,
    commit_id = "",
    original_commit_id = "",
    diff_hunk = "",
    body = c.text or "",
    user = translate_bbs_user(c.author),
    created_at = bbs_ts(c.createdDate) or "",
    updated_at = bbs_ts(c.updatedDate) or "",
    html_url = "",
    pull_request_url = "",
    url = "",
  }
end

-- Map DC PR reviewers array to GitHub reviews format.
-- DC reviewer: { user: {...}, role: "REVIEWER", approved: true, status: "APPROVED" }
local function translate_bbs_reviewers_to_reviews(reviewers)
  local result = {}
  local idx = 0
  for _, r in ipairs(reviewers or {}) do
    if r.approved then
      idx = idx + 1
      result[idx] = {
        id = idx,
        node_id = "",
        user = translate_bbs_user(r.user),
        body = "",
        state = "APPROVED",
        submitted_at = "",
        html_url = "",
        pull_request_url = "",
      }
    end
  end
  return result
end

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, base() .. "/repos", auth())
    if ok and status == 200 then
      respond_json(200, {})
    else
      respond_json(503, {})
    end
  end,

  get_repo = proxy_handler(translate_bbs_repo, function(owner, repo_name)
    return repo_path(owner, repo_name)
  end),

  patch_repo = function(owner, repo_name)
    proxy_json(function(r)
      return translate_bbs_repo(r, owner)
    end, fetch_json(repo_path(owner, repo_name), "PUT", translate_bbs_req(GetBody())))
  end,

  delete_repo = function(owner, repo_name)
    local dopts = auth() or {}
    dopts.method = "DELETE"
    local ok, status = pcall(Fetch, repo_path(owner, repo_name), dopts)
    if ok and (status == 202 or status == 204) then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, {})
    else
      respond_json(503, {})
    end
  end,

  -- GET /user/repos — DC: GET /repos (all repos visible to the auth'd user)
  get_user_repos = proxy_handler(translate_bbs_repos, function()
    return bbs_page_url(base() .. "/repos")
  end),

  post_user_repos = function()
    -- DC requires a project key; no generic "my repos" create endpoint.
    respond_json(
      501,
      "Not Implemented",
      { message = "POST /user/repos requires a project key; use POST /orgs/{project}/repos" }
    )
  end,

  get_org_repos = proxy_handler(translate_bbs_repos, function(project_key)
    return bbs_page_url(base() .. "/projects/" .. project_key .. "/repos")
  end),

  post_org_repos = function(project_key)
    proxy_json_created(
      function(r)
        return translate_bbs_repo(r, project_key)
      end,
      fetch_json(
        base() .. "/projects/" .. project_key .. "/repos",
        "POST",
        translate_bbs_req(GetBody())
      )
    )
  end,

  -- GET /users/{username}/repos — via personal project ~username
  get_users_repos = proxy_handler(function(data, username)
    return translate_bbs_repos(data, "~" .. username)
  end, function(username)
    return bbs_page_url(base() .. "/projects/~" .. username .. "/repos")
  end),

  -- GET /repositories — all repos visible to the authenticated user
  get_repositories = proxy_handler(translate_bbs_repos, function()
    return bbs_page_url(base() .. "/repos")
  end),

  -- Tags -----------------------------------------------------------------------
  -- DC: GET /projects/{proj}/repos/{slug}/tags → { values: [{id, displayId, latestCommit}] }

  get_repo_tags = proxy_handler(function(data)
    local tags = data.values or {}
    local result = {}
    for _, t in ipairs(tags) do
      result[#result + 1] = {
        name = t.displayId or t.id or "",
        commit = { sha = t.latestCommit or t.latestChangeset or "", url = "" },
      }
    end
    return result
  end, function(owner, repo_name)
    return bbs_page_url(repo_path(owner, repo_name) .. "/tags")
  end),

  -- Branches -------------------------------------------------------------------

  get_repo_branches = proxy_handler(function(data)
    local branches = data.values or {}
    for i, b in ipairs(branches) do
      branches[i] = translate_bbs_branch(b)
    end
    return branches
  end, function(owner, repo_name)
    return bbs_page_url(repo_path(owner, repo_name) .. "/branches")
  end),

  get_repo_branch = proxy_handler(function(data)
    local b = (data.values or {})[1]
    return b and translate_bbs_branch(b) or {}
  end, function(owner, repo_name, branch)
    return repo_path(owner, repo_name) .. "/branches?filterText=" .. branch .. "&limit=1"
  end),

  -- Commits --------------------------------------------------------------------

  get_repo_commits = function(owner, repo_name)
    local ref = GetParam("sha") or ""
    local url = bbs_page_url(repo_path(owner, repo_name) .. "/commits")
    if ref ~= "" then
      local sep = url:find("?") and "&" or "?"
      url = url .. sep .. "until=" .. ref
    end
    proxy_json(function(data)
      local commits = data.values or {}
      for i, c in ipairs(commits) do
        commits[i] = translate_bbs_commit(c)
      end
      return commits
    end, fetch_json(url))
  end,

  get_repo_commit = proxy_handler(translate_bbs_commit, function(owner, repo_name, sha)
    return repo_path(owner, repo_name) .. "/commits/" .. sha
  end),

  -- Contents -------------------------------------------------------------------
  -- DC: GET /projects/{proj}/repos/{slug}/raw/{path}?at={ref}

  get_repo_readme = function(owner, repo_name)
    local ref = GetParam("ref") or ""
    local candidates = { "README.md", "README", "readme.md", "README.rst" }
    for _, fname in ipairs(candidates) do
      local url = repo_path(owner, repo_name) .. "/raw/" .. fname
      if ref ~= "" then
        url = url .. "?at=" .. ref
      end
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

  -- GET /repos/{owner}/{repo}/license
  -- BBS has no license template API; fetch the LICENSE file via raw endpoint.
  get_repo_license = function(owner, repo_name)
    local candidates = { "LICENSE", "LICENSE.md", "LICENSE.txt", "COPYING" }
    for _, fname in ipairs(candidates) do
      local ok, status, _, body = fetch_json(repo_path(owner, repo_name) .. "/raw/" .. fname)
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
  end,

  get_repo_content = function(owner, repo_name, path)
    local ref = GetParam("ref") or ""
    local url = repo_path(owner, repo_name) .. "/raw/" .. path
    if ref ~= "" then
      url = url .. "?at=" .. ref
    end
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

  -- Forks ----------------------------------------------------------------------

  get_repo_forks = proxy_handler(translate_bbs_repos, function(owner, repo_name)
    return bbs_page_url(repo_path(owner, repo_name) .. "/forks")
  end),

  post_repo_forks = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
    local bb = {}
    if req.organization then
      bb.project = { key = req.organization }
    end
    proxy_json_created(function(r)
      return translate_bbs_repo(r, owner)
    end, fetch_json(repo_path(owner, repo_name) .. "/forks", "POST", EncodeJson(bb)))
  end,

  -- Deploy keys ----------------------------------------------------------------
  -- DC: /ssh endpoint (not /deploy-keys)

  get_repo_keys = proxy_handler(function(data)
    local keys = data.values or {}
    for i, k in ipairs(keys) do
      keys[i] = translate_bbs_key(k)
    end
    return keys
  end, function(owner, repo_name)
    return bbs_page_url(repo_path(owner, repo_name) .. "/ssh")
  end),

  post_repo_keys = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
    local bb = {
      key = { text = req.key or "", label = req.title or "" },
      permission = "REPO_READ",
    }
    proxy_json_created(
      translate_bbs_key,
      fetch_json(repo_path(owner, repo_name) .. "/ssh", "POST", EncodeJson(bb))
    )
  end,

  get_repo_key = proxy_handler(translate_bbs_key, function(owner, repo_name, key_id)
    return repo_path(owner, repo_name) .. "/ssh/" .. key_id
  end),

  delete_repo_key = function(owner, repo_name, key_id)
    local dopts = auth() or {}
    dopts.method = "DELETE"
    local ok, status = pcall(Fetch, repo_path(owner, repo_name) .. "/ssh/" .. key_id, dopts)
    if ok and (status == 204 or status == 200) then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, {})
    else
      respond_json(503, {})
    end
  end,

  -- Webhooks -------------------------------------------------------------------

  get_repo_hooks = proxy_handler(function(data)
    local hooks = data.values or {}
    for i, h in ipairs(hooks) do
      hooks[i] = translate_bbs_hook(h)
    end
    return hooks
  end, function(owner, repo_name)
    return bbs_page_url(repo_path(owner, repo_name) .. "/webhooks")
  end),

  post_repo_hooks = function(owner, repo_name)
    proxy_json_created(
      translate_bbs_hook,
      fetch_json(
        repo_path(owner, repo_name) .. "/webhooks",
        "POST",
        translate_bbs_hook_req(GetBody())
      )
    )
  end,

  get_repo_hook = proxy_handler(translate_bbs_hook, function(owner, repo_name, hook_id)
    return repo_path(owner, repo_name) .. "/webhooks/" .. hook_id
  end),

  patch_repo_hook = function(owner, repo_name, hook_id)
    proxy_json(
      translate_bbs_hook,
      fetch_json(
        repo_path(owner, repo_name) .. "/webhooks/" .. hook_id,
        "PUT",
        translate_bbs_hook_req(GetBody())
      )
    )
  end,

  delete_repo_hook = function(owner, repo_name, hook_id)
    local dopts = auth() or {}
    dopts.method = "DELETE"
    local ok, status = pcall(Fetch, repo_path(owner, repo_name) .. "/webhooks/" .. hook_id, dopts)
    if ok and (status == 204 or status == 200) then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, {})
    else
      respond_json(503, {})
    end
  end,

  get_repo_hook_config = proxy_handler(function(h)
    return (translate_bbs_hook(h)).config or {}
  end, function(owner, repo_name, hook_id)
    return repo_path(owner, repo_name) .. "/webhooks/" .. hook_id
  end),

  -- Users ---------------------------------------------------------------------

  -- GET /users/{username}
  get_users_username = proxy_handler(translate_bbs_user, function(username)
    return base() .. "/users/" .. username
  end),

  -- GET /users
  get_users = proxy_handler(function(data)
    local users = (data and data.values) or {}
    for i, u in ipairs(users) do
      users[i] = translate_bbs_user(u)
    end
    return users
  end, function()
    return bbs_page_url(base() .. "/users")
  end),

  -- Pull Requests ---------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/pulls
  get_repo_pulls = function(owner, repo_name)
    local state = GetParam("state") or "open"
    local dc_state = state == "closed" and "MERGED,DECLINED" or state == "all" and "ALL" or "OPEN"
    local url = bbs_page_url(repo_path(owner, repo_name) .. "/pull-requests?state=" .. dc_state)
    proxy_json(translate_bbs_pulls, fetch_json(url))
  end,

  -- POST /repos/{owner}/{repo}/pulls
  post_repo_pulls = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
    local dc = {}
    if req.title then
      dc.title = req.title
    end
    if req.body then
      dc.description = req.body
    end
    if req.head then
      dc.fromRef = { id = "refs/heads/" .. req.head }
    end
    if req.base then
      dc.toRef = { id = "refs/heads/" .. req.base }
    end
    proxy_json_created(
      translate_bbs_pull,
      fetch_json(repo_path(owner, repo_name) .. "/pull-requests", "POST", EncodeJson(dc))
    )
  end,

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}
  get_repo_pull = proxy_handler(translate_bbs_pull, function(owner, repo_name, pull_number)
    return repo_path(owner, repo_name) .. "/pull-requests/" .. pull_number
  end),

  -- PATCH /repos/{owner}/{repo}/pulls/{pull_number}
  -- DC uses PUT for updates and requires a version field.
  patch_repo_pull = function(owner, repo_name, pull_number)
    local pr_url = repo_path(owner, repo_name) .. "/pull-requests/" .. pull_number
    local ok, status, _, body = fetch_json(pr_url)
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    local current = DecodeJson(body) or {}
    local req = DecodeJson(GetBody() or "{}")
    local dc = { version = current.version or 0 }
    if req.title then
      dc.title = req.title
    end
    if req.body then
      dc.description = req.body
    end
    proxy_json(translate_bbs_pull, fetch_json(pr_url, "PUT", EncodeJson(dc)))
  end,

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/commits
  get_pull_commits = proxy_handler(function(data)
    local commits = (data and data.values) or {}
    for i, c in ipairs(commits) do
      commits[i] = translate_bbs_commit(c)
    end
    return commits
  end, function(owner, repo_name, pull_number)
    return bbs_page_url(
      repo_path(owner, repo_name) .. "/pull-requests/" .. pull_number .. "/commits"
    )
  end),

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/files
  -- DC uses /changes for per-file info (no line stats).
  get_pull_files = proxy_handler(function(data)
    local changes = (data and data.values) or {}
    for i, c in ipairs(changes) do
      changes[i] = translate_bbs_pr_change(c)
    end
    return changes
  end, function(owner, repo_name, pull_number)
    return bbs_page_url(
      repo_path(owner, repo_name) .. "/pull-requests/" .. pull_number .. "/changes"
    )
  end),

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/merge
  -- Returns 204 if PR is merged, 404 otherwise.
  get_pull_merge = function(owner, repo_name, pull_number)
    local ok, status, _, body =
      fetch_json(repo_path(owner, repo_name) .. "/pull-requests/" .. pull_number)
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    local pr = DecodeJson(body) or {}
    if pr.state == "MERGED" then
      SetStatus(204, "No Content")
    else
      respond_json(404, { message = "Pull Request is not merged" })
    end
  end,

  -- PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge
  -- DC: POST /pull-requests/{id}/merge; requires version from current PR.
  put_pull_merge = function(owner, repo_name, pull_number)
    local pr_url = repo_path(owner, repo_name) .. "/pull-requests/" .. pull_number
    local ok, status, _, body = fetch_json(pr_url)
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    local current = DecodeJson(body) or {}
    local req = DecodeJson(GetBody() or "{}")
    local dc = { version = current.version or 0 }
    if req.commit_message then
      dc.message = req.commit_message
    end
    local mok, mstatus = fetch_json(pr_url .. "/merge", "POST", EncodeJson(dc))
    if mok and (mstatus == 200 or mstatus == 204) then
      SetStatus(204, "No Content")
    elseif mok then
      respond_json(mstatus, {})
    else
      respond_json(503, {})
    end
  end,

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/requested_reviewers
  -- DC: reviewers in PR object who have not yet approved.
  get_pull_requested_reviewers = function(owner, repo_name, pull_number)
    local ok, status, _, body =
      fetch_json(repo_path(owner, repo_name) .. "/pull-requests/" .. pull_number)
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    local pr = DecodeJson(body) or {}
    local users = {}
    for _, r in ipairs(pr.reviewers or {}) do
      if not r.approved then
        users[#users + 1] = translate_bbs_user(r.user)
      end
    end
    respond_json(200, { users = users, teams = {} })
  end,

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews
  -- DC: reviewers with approved=true in PR object.
  get_pull_reviews = function(owner, repo_name, pull_number)
    local ok, status, _, body =
      fetch_json(repo_path(owner, repo_name) .. "/pull-requests/" .. pull_number)
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    local pr = DecodeJson(body) or {}
    respond_json(200, translate_bbs_reviewers_to_reviews(pr.reviewers))
  end,

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}
  get_pull_review = function(owner, repo_name, pull_number, review_id)
    local ok, status, _, body =
      fetch_json(repo_path(owner, repo_name) .. "/pull-requests/" .. pull_number)
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    local pr = DecodeJson(body) or {}
    local reviews = translate_bbs_reviewers_to_reviews(pr.reviewers)
    local rid = tonumber(review_id)
    if rid and reviews[rid] then
      respond_json(200, reviews[rid])
    else
      respond_json(404, { message = "Not Found" })
    end
  end,

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}/comments
  -- DC has no per-review comments; return all PR inline comments.
  get_pull_review_comments = function(owner, repo_name, pull_number)
    local ok, status, _, body = fetch_json(
      bbs_page_url(repo_path(owner, repo_name) .. "/pull-requests/" .. pull_number .. "/comments")
    )
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    local data = DecodeJson(body) or {}
    local result = {}
    for _, c in ipairs(data.values or {}) do
      if c.anchor then
        result[#result + 1] = translate_bbs_pr_comment(c)
      end
    end
    respond_json(200, result)
  end,

  -- Issues -----------------------------------------------------------------------
  -- Bitbucket Datacenter has no native issue tracker; it relies on Jira.
  -- All issues, labels, milestones, and assignees endpoints fall back to the
  -- default empty-list handlers defined in .init.lua.

  -- Search -----------------------------------------------------------------------

  -- GET /search/repositories — DC: GET /repos?name=<q>
  search_repositories = function()
    local q = GetParam("q") or ""
    proxy_search_bbs(translate_bbs_repo, bbs_page_url(base() .. "/repos?name=" .. q))
  end,

  -- GET /search/users — DC: GET /users?filter=<q>
  search_users = function()
    local q = GetParam("q") or ""
    proxy_search_bbs(translate_bbs_user, bbs_page_url(base() .. "/users?filter=" .. q))
  end,

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/comments
  -- DC inline PR comments (those with an anchor field).
  get_pull_comments = function(owner, repo_name, pull_number)
    local ok, status, _, body = fetch_json(
      bbs_page_url(repo_path(owner, repo_name) .. "/pull-requests/" .. pull_number .. "/comments")
    )
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    local data = DecodeJson(body) or {}
    local result = {}
    for _, c in ipairs(data.values or {}) do
      if c.anchor then
        result[#result + 1] = translate_bbs_pr_comment(c)
      end
    end
    respond_json(200, result)
  end,

  -- Checks (via Bitbucket DC build status API) ------------------------------------
  --
  -- Bitbucket DC has a dedicated build status REST API at:
  --   POST /rest/build-status/1.0/commits/{sha}  — create/update a build status
  --   GET  /rest/build-status/1.0/commits/{sha}  — list build statuses for a commit
  --
  -- GitHub Check Runs map onto DC build statuses:
  --   • POST check-runs → POST /rest/build-status/1.0/commits/{sha}
  --   • GET check-runs/{id} → minimal stub (no reverse lookup by ID)
  --   • PATCH check-runs/{id} → minimal stub
  --   • GET commits/{ref}/check-runs → build statuses list
  --   • Check Suites have no DC equivalent; all suite endpoints are stubs.
  --   • Annotations are always empty.
  --
  -- Status mapping (GitHub → DC):
  --   queued/in_progress     → INPROGRESS
  --   completed/success      → SUCCESSFUL
  --   completed/failure      → FAILED
  --   completed/neutral      → SUCCESSFUL
  --   completed/skipped      → SUCCESSFUL
  --   completed/cancelled    → STOPPED
  --   completed/(other)      → FAILED
  --
  -- Status mapping (DC → GitHub):
  --   INPROGRESS  → status=in_progress, conclusion=null
  --   SUCCESSFUL  → status=completed,   conclusion=success
  --   FAILED      → status=completed,   conclusion=failure
  --   STOPPED     → status=completed,   conclusion=cancelled
  --   other       → status=completed,   conclusion=failure

  post_check_runs = function(owner, repo_name) -- luacheck: ignore 212
    local req = DecodeJson(GetBody() or "{}")
    local sha = req.head_sha or ""
    local gh_status = req.status or "queued"
    local conclusion = req.conclusion
    local gh_conclusion_to_dc = {
      success = "SUCCESSFUL",
      neutral = "SUCCESSFUL",
      skipped = "SUCCESSFUL",
      cancelled = "STOPPED",
    }
    local dc_state = gh_status == "completed" and (gh_conclusion_to_dc[conclusion] or "FAILED")
      or "INPROGRESS"
    local dc_to_gh = {
      INPROGRESS = { status = "in_progress", conclusion = nil },
      SUCCESSFUL = { status = "completed", conclusion = "success" },
      FAILED = { status = "completed", conclusion = "failure" },
      STOPPED = { status = "completed", conclusion = "cancelled" },
    }
    local dc_body = EncodeJson({
      state = dc_state,
      key = req.name or "",
      url = req.details_url or "",
      name = req.name or "",
      description = (req.output and req.output.summary) or req.name or "",
    })
    -- DC POST returns 204 No Content on success (no body); synthesise a GitHub response.
    local ok, up_status =
      fetch_json(config.base_url .. "/rest/build-status/1.0/commits/" .. sha, "POST", dc_body)
    if not ok then
      respond_json(503, {})
      return
    end
    if up_status ~= 204 and up_status ~= 200 and up_status ~= 201 then
      respond_json(up_status, {})
      return
    end
    local mapped = dc_to_gh[dc_state] or { status = "completed", conclusion = "failure" }
    respond_json(201, {
      id = 0,
      node_id = "",
      head_sha = sha,
      name = req.name or "",
      status = mapped.status,
      conclusion = mapped.conclusion,
      started_at = nil,
      completed_at = mapped.status == "completed" and "" or nil,
      output = {
        title = (req.output and req.output.title) or req.name or "",
        summary = (req.output and req.output.summary) or req.name or "",
        text = "",
        annotations_count = 0,
        annotations_url = "",
      },
      url = "",
      html_url = req.details_url or "",
      details_url = req.details_url or "",
    })
  end,

  -- GET /repos/{owner}/{repo}/commits/{ref}/check-runs
  -- Uses DC build status API.
  get_commit_check_runs = function(_owner, _repo_name, ref)
    local ok, status, _, body =
      fetch_json(config.base_url .. "/rest/build-status/1.0/commits/" .. ref)
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    local data = DecodeJson(body) or {}
    local dc_to_gh = {
      INPROGRESS = { status = "in_progress", conclusion = nil },
      SUCCESSFUL = { status = "completed", conclusion = "success" },
      FAILED = { status = "completed", conclusion = "failure" },
      STOPPED = { status = "completed", conclusion = "cancelled" },
    }
    local runs = {}
    for i, s in ipairs(data.values or {}) do
      local mapped = dc_to_gh[s.state] or { status = "completed", conclusion = "failure" }
      runs[i] = {
        id = i,
        node_id = "",
        head_sha = ref,
        name = s.key or s.name or "",
        status = mapped.status,
        conclusion = mapped.conclusion,
        started_at = nil,
        completed_at = mapped.status == "completed" and "" or nil,
        output = {
          title = s.description or "",
          summary = s.description or "",
          text = "",
          annotations_count = 0,
          annotations_url = "",
        },
        url = "",
        html_url = s.url or "",
        details_url = s.url or "",
      }
    end
    respond_json(200, { total_count = #runs, check_runs = runs })
  end,

  -- Check suites have no DC equivalent; all suite endpoints fall back to
  -- the route_defaults stubs defined in .init.lua.
}

-- Code Scanning via Bitbucket DC Code Insights API.
-- BBS Code Insights (/rest/insights/1.0) stores per-commit analysis reports
-- and annotations. Alerts map to annotations on the HEAD commit; analyses map
-- to Insights reports.
--
-- Endpoint            BBS equivalent
-- ──────────────────────────────────────────────────────────────────────────
-- list alerts         GET /rest/insights/1.0/{proj}/{repo}/commits/{sha}/annotations
-- list analyses       GET /rest/insights/1.0/{proj}/{repo}/commits/{sha}/reports
-- everything else     501 (no native equivalent)
--
-- The SARIF upload endpoint is not implemented: GitHub's SARIF format is
-- gzip+base64 encoded and BBS Insights has no SARIF import endpoint — the
-- translation would require decompression and parsing that is not feasible
-- inside Redbean's Lua environment.

local function insights_base(owner, repo_name)
  return config.base_url .. "/rest/insights/1.0/projects/" .. owner .. "/repos/" .. repo_name
end

-- Resolve the HEAD SHA for the ref in the request (defaults to default branch).
-- Returns the SHA string, or nil on failure.
local function resolve_ref_sha(owner, repo_name)
  local ref = GetParam("ref") or ""
  if ref ~= "" then
    -- Strip refs/heads/ prefix if present
    local branch = ref:match("^refs/heads/(.+)$") or ref
    local url = repo_path(owner, repo_name) .. "/branches?filterText=" .. branch .. "&limit=1"
    local ok, status, _, body = fetch_json(url)
    if ok and status == 200 then
      local data = DecodeJson(body) or {}
      local first = (data.values or {})[1]
      if first then
        return first.latestCommit or first.latestChangeset
      end
    end
    return nil
  end
  -- No ref specified: use the default branch.
  local url = repo_path(owner, repo_name) .. "/branches?limit=25"
  local ok, status, _, body = fetch_json(url)
  if not ok or status ~= 200 then
    return nil
  end
  local data = DecodeJson(body) or {}
  for _, b in ipairs(data.values or {}) do
    if b.isDefault then
      return b.latestCommit or b.latestChangeset
    end
  end
  -- Fall back to first branch if no default found.
  local first = (data.values or {})[1]
  return first and (first.latestCommit or first.latestChangeset)
end

-- Translate a BBS Code Insights annotation to a GitHub code-scanning alert.
-- BBS annotation: { reportKey, externalId, message, path, line, severity, type, link }
local function translate_bbs_annotation(ann, idx)
  local severity = ann.severity or "MEDIUM"
  local gh_severity = severity == "CRITICAL" and "critical"
    or severity == "HIGH" and "high"
    or severity == "MEDIUM" and "medium"
    or "low"
  return {
    number = idx,
    state = "open",
    dismissed_by = nil,
    dismissed_at = nil,
    dismissed_reason = nil,
    dismissed_comment = nil,
    fixed_at = nil,
    rule = {
      id = ann.reportKey or "",
      name = ann.reportKey or "",
      description = ann.message or "",
      severity = gh_severity,
    },
    tool = {
      name = ann.reportKey or "",
      guid = nil,
      version = nil,
    },
    most_recent_instance = {
      ref = "",
      analysis_key = ann.reportKey or "",
      state = "open",
      commit_sha = "",
      location = {
        path = ann.path or "",
        start_line = ann.line or 1,
        end_line = ann.line or 1,
        start_column = nil,
        end_column = nil,
      },
      message = { text = ann.message or "" },
    },
    instances_url = "",
    html_url = "",
    url = "",
    created_at = "",
    updated_at = "",
  }
end

-- Translate a BBS Code Insights report to a GitHub code-scanning analysis.
-- BBS report: { key, title, reporter, result, createdDate, updatedDate }
local function translate_bbs_report(rpt, idx, sha)
  local ts = rpt.createdDate
  local created = ts and os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(ts / 1000)) or ""
  return {
    ref = "",
    commit_sha = sha or "",
    analysis_key = rpt.key or "",
    environment = "{}",
    category = rpt.key or "",
    error = "",
    created_at = created,
    results_count = 0,
    rules_count = 0,
    id = idx,
    url = "",
    sarif_id = "",
    tool = {
      name = rpt.reporter or rpt.title or rpt.key or "",
      guid = nil,
      version = nil,
    },
    deletable = false,
    warning = "",
  }
end

local _b = backend_impl

_b.list_repo_code_scanning_alerts = function(owner, repo_name)
  local sha = resolve_ref_sha(owner, repo_name)
  if not sha then
    respond_json(200, {})
    return
  end
  local url = insights_base(owner, repo_name) .. "/commits/" .. sha .. "/annotations"
  local ok, status, _, body = fetch_json(url)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(200, {})
    return
  end
  local data = DecodeJson(body) or {}
  local result = {}
  for i, ann in ipairs(data.annotations or data.values or {}) do
    result[i] = translate_bbs_annotation(ann, i)
  end
  respond_json(200, result)
end

_b.list_code_scanning_analyses = function(owner, repo_name)
  local sha = resolve_ref_sha(owner, repo_name)
  if not sha then
    respond_json(200, {})
    return
  end
  local url = insights_base(owner, repo_name) .. "/commits/" .. sha .. "/reports"
  local ok, status, _, body = fetch_json(url)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(200, {})
    return
  end
  local data = DecodeJson(body) or {}
  local result = {}
  for i, rpt in ipairs(data.reports or data.values or {}) do
    result[i] = translate_bbs_report(rpt, i, sha)
  end
  respond_json(200, result)
end

-- Git database (refs only; blobs/commits/tag-objects/trees have no DC equivalent) -----

local function translate_bbs_ref(r)
  local ref_id = r.id or ""
  local sha = r.latestCommit or r.latestChangeset or ""
  return {
    ref = ref_id,
    node_id = "",
    url = "",
    object = { type = "commit", sha = sha, url = "" },
  }
end

_b.list_git_matching_refs = function(owner, repo_name, ref)
  local endpoint, prefix
  if ref:sub(1, 6) == "heads/" then
    endpoint = "/branches"
    prefix = ref:sub(7)
  elseif ref:sub(1, 5) == "tags/" then
    endpoint = "/tags"
    prefix = ref:sub(6)
  else
    endpoint = "/branches"
    prefix = ref
  end
  local url = bbs_page_url(repo_path(owner, repo_name) .. endpoint .. "?filterText=" .. prefix)
  proxy_json(function(data)
    local refs = data.values or {}
    for i, r in ipairs(refs) do
      refs[i] = translate_bbs_ref(r)
    end
    return refs
  end, fetch_json(url))
end

_b.get_git_ref = function(owner, repo_name, ref)
  local endpoint, prefix
  if ref:sub(1, 6) == "heads/" then
    endpoint = "/branches"
    prefix = ref:sub(7)
  elseif ref:sub(1, 5) == "tags/" then
    endpoint = "/tags"
    prefix = ref:sub(6)
  else
    respond_json(422, { message = "Invalid ref format" })
    return
  end
  local url = repo_path(owner, repo_name) .. endpoint .. "?filterText=" .. prefix .. "&limit=1"
  proxy_json(function(data)
    local first = (data.values or {})[1]
    return first and translate_bbs_ref(first) or {}
  end, fetch_json(url))
end

_b.create_git_ref = function(owner, repo_name)
  local req = DecodeJson(GetBody() or "{}")
  local full_ref = req.ref or ""
  local sha = req.sha or ""
  local endpoint, bb_body
  if full_ref:sub(1, 11) == "refs/heads/" then
    endpoint = "/branches"
    bb_body = EncodeJson({ name = full_ref:sub(12), startPoint = sha })
  elseif full_ref:sub(1, 10) == "refs/tags/" then
    endpoint = "/tags"
    bb_body = EncodeJson({ name = full_ref:sub(11), startCommit = sha, message = "" })
  else
    respond_json(422, { message = "Invalid ref format" })
    return
  end
  proxy_json_created(
    translate_bbs_ref,
    fetch_json(repo_path(owner, repo_name) .. endpoint, "POST", bb_body)
  )
end

_b.delete_git_ref = function(owner, repo_name, ref)
  local endpoint, body_or_nil
  if ref:sub(1, 6) == "heads/" then
    endpoint = "/branches"
    body_or_nil = EncodeJson({ name = "refs/heads/" .. ref:sub(7), dryRun = false })
  elseif ref:sub(1, 5) == "tags/" then
    endpoint = "/tags/" .. ref:sub(6)
    body_or_nil = nil
  else
    respond_json(422, { message = "Invalid ref format" })
    return
  end
  local url = repo_path(owner, repo_name) .. endpoint
  local dopts = auth() or {}
  dopts.method = "DELETE"
  if body_or_nil then
    dopts.body = body_or_nil
    dopts.headers = dopts.headers or {}
    dopts.headers["Content-Type"] = "application/json"
  end
  local ok, status = pcall(Fetch, url, dopts)
  if ok and (status == 204 or status == 200 or status == 202) then
    SetStatus(204, "No Content")
  elseif ok then
    respond_json(status, {})
  else
    respond_json(503, {})
  end
end
