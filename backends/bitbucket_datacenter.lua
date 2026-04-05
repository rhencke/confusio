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
      respond_json(200, "OK", {})
    else
      respond_json(503, "Service Unavailable", {})
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
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
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
    local url = repo_path(owner, repo_name) .. "/raw/" .. path
    if ref ~= "" then
      url = url .. "?at=" .. ref
    end
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
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
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
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
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
      respond_json(503, "Service Unavailable", {})
      return
    end
    if status ~= 200 then
      respond_json(status, "Error", {})
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
      respond_json(503, "Service Unavailable", {})
      return
    end
    if status ~= 200 then
      respond_json(status, "Error", {})
      return
    end
    local pr = DecodeJson(body) or {}
    if pr.state == "MERGED" then
      SetStatus(204, "No Content")
    else
      respond_json(404, "Not Found", { message = "Pull Request is not merged" })
    end
  end,

  -- PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge
  -- DC: POST /pull-requests/{id}/merge; requires version from current PR.
  put_pull_merge = function(owner, repo_name, pull_number)
    local pr_url = repo_path(owner, repo_name) .. "/pull-requests/" .. pull_number
    local ok, status, _, body = fetch_json(pr_url)
    if not ok then
      respond_json(503, "Service Unavailable", {})
      return
    end
    if status ~= 200 then
      respond_json(status, "Error", {})
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
      respond_json(mstatus, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/requested_reviewers
  -- DC: reviewers in PR object who have not yet approved.
  get_pull_requested_reviewers = function(owner, repo_name, pull_number)
    local ok, status, _, body =
      fetch_json(repo_path(owner, repo_name) .. "/pull-requests/" .. pull_number)
    if not ok then
      respond_json(503, "Service Unavailable", {})
      return
    end
    if status ~= 200 then
      respond_json(status, "Error", {})
      return
    end
    local pr = DecodeJson(body) or {}
    local users = {}
    for _, r in ipairs(pr.reviewers or {}) do
      if not r.approved then
        users[#users + 1] = translate_bbs_user(r.user)
      end
    end
    respond_json(200, "OK", { users = users, teams = {} })
  end,

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews
  -- DC: reviewers with approved=true in PR object.
  get_pull_reviews = function(owner, repo_name, pull_number)
    local ok, status, _, body =
      fetch_json(repo_path(owner, repo_name) .. "/pull-requests/" .. pull_number)
    if not ok then
      respond_json(503, "Service Unavailable", {})
      return
    end
    if status ~= 200 then
      respond_json(status, "Error", {})
      return
    end
    local pr = DecodeJson(body) or {}
    respond_json(200, "OK", translate_bbs_reviewers_to_reviews(pr.reviewers))
  end,

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}
  get_pull_review = function(owner, repo_name, pull_number, review_id)
    local ok, status, _, body =
      fetch_json(repo_path(owner, repo_name) .. "/pull-requests/" .. pull_number)
    if not ok then
      respond_json(503, "Service Unavailable", {})
      return
    end
    if status ~= 200 then
      respond_json(status, "Error", {})
      return
    end
    local pr = DecodeJson(body) or {}
    local reviews = translate_bbs_reviewers_to_reviews(pr.reviewers)
    local rid = tonumber(review_id)
    if rid and reviews[rid] then
      respond_json(200, "OK", reviews[rid])
    else
      respond_json(404, "Not Found", { message = "Not Found" })
    end
  end,

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}/comments
  -- DC has no per-review comments; return all PR inline comments.
  get_pull_review_comments = function(owner, repo_name, pull_number)
    local ok, status, _, body = fetch_json(
      bbs_page_url(repo_path(owner, repo_name) .. "/pull-requests/" .. pull_number .. "/comments")
    )
    if not ok then
      respond_json(503, "Service Unavailable", {})
      return
    end
    if status ~= 200 then
      respond_json(status, "Error", {})
      return
    end
    local data = DecodeJson(body) or {}
    local result = {}
    for _, c in ipairs(data.values or {}) do
      if c.anchor then
        result[#result + 1] = translate_bbs_pr_comment(c)
      end
    end
    respond_json(200, "OK", result)
  end,

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/comments
  -- DC inline PR comments (those with an anchor field).
  get_pull_comments = function(owner, repo_name, pull_number)
    local ok, status, _, body = fetch_json(
      bbs_page_url(repo_path(owner, repo_name) .. "/pull-requests/" .. pull_number .. "/comments")
    )
    if not ok then
      respond_json(503, "Service Unavailable", {})
      return
    end
    if status ~= 200 then
      respond_json(status, "Error", {})
      return
    end
    local data = DecodeJson(body) or {}
    local result = {}
    for _, c in ipairs(data.values or {}) do
      if c.anchor then
        result[#result + 1] = translate_bbs_pr_comment(c)
      end
    end
    respond_json(200, "OK", result)
  end,
}
