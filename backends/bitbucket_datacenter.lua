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
local _t = make_backend_transport("basic")
local fetch_json = _t.fetch_json
local proxy_handler = _t.proxy_handler

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
  return translate_list(function(r)
    return translate_bbs_repo(r, proj_key)
  end, (data and data.values))
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

-- Translate a DC tag object to GitHub format.
-- DC: { id: "refs/tags/v1.0", displayId: "v1.0", latestCommit: "abc..." }
local function translate_bbs_tag(t)
  return {
    name = t.displayId or t.id or "",
    commit = { sha = t.latestCommit or t.latestChangeset or "", url = "" },
  }
end

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
  return translate_list(translate_bbs_pull, (data and data.values))
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

-- DC build-status state → GitHub check_run status/conclusion mapping.
-- Shared by post_check_runs and get_commit_check_runs.
local bbs_dc_to_gh = {
  INPROGRESS = { status = "in_progress", conclusion = nil },
  SUCCESSFUL = { status = "completed", conclusion = "success" },
  FAILED = { status = "completed", conclusion = "failure" },
  STOPPED = { status = "completed", conclusion = "cancelled" },
}

local b = make_backend_builder()
b:rest("get_root", function()
  proxy_health_check(pcall(Fetch, base() .. "/repos", auth()))
end)

b:rest(
  "get_repo",
  proxy_handler(translate_bbs_repo, function(owner, repo_name)
    return repo_path(owner, repo_name)
  end)
)

b:rest("patch_repo", function(owner, repo_name)
  proxy_json(function(r)
    return translate_bbs_repo(r, owner)
  end, fetch_json(repo_path(owner, repo_name), "PUT", translate_bbs_req(GetBody())))
end)

b:rest("delete_repo", function(owner, repo_name)
  local dopts = auth() or {}
  dopts.method = "DELETE"
  proxy_204({ 202 }, pcall(Fetch, repo_path(owner, repo_name), dopts))
end)

-- GET /user/repos — DC: GET /repos (all repos visible to the auth'd user)
b:rest(
  "get_user_repos",
  proxy_handler(translate_bbs_repos, function()
    return bbs_page_url(base() .. "/repos")
  end)
)

b:rest("post_user_repos", function()
  -- DC requires a project key; no generic "my repos" create endpoint.
  respond_json(
    501,
    "Not Implemented",
    { message = "POST /user/repos requires a project key; use POST /orgs/{project}/repos" }
  )
end)

b:rest(
  "get_org_repos",
  proxy_handler(translate_bbs_repos, function(project_key)
    return bbs_page_url(base() .. "/projects/" .. project_key .. "/repos")
  end)
)

b:rest("post_org_repos", function(project_key)
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
end)

-- GET /users/{username}/repos — via personal project ~username
b:rest(
  "get_users_repos",
  proxy_handler(function(data, username)
    return translate_bbs_repos(data, "~" .. username)
  end, function(username)
    return bbs_page_url(base() .. "/projects/~" .. username .. "/repos")
  end)
)

-- GET /repositories — all repos visible to the authenticated user
b:rest(
  "get_repositories",
  proxy_handler(translate_bbs_repos, function()
    return bbs_page_url(base() .. "/repos")
  end)
)

-- Tags -----------------------------------------------------------------------
-- DC: GET /projects/{proj}/repos/{slug}/tags → { values: [{id, displayId, latestCommit}] }

b:rest(
  "get_repo_tags",
  proxy_handler(function(data)
    return translate_list(translate_bbs_tag, data.values)
  end, function(owner, repo_name)
    return bbs_page_url(repo_path(owner, repo_name) .. "/tags")
  end)
)

-- Branches -------------------------------------------------------------------

b:rest(
  "get_repo_branches",
  proxy_handler(function(data)
    return translate_list(translate_bbs_branch, data.values)
  end, function(owner, repo_name)
    return bbs_page_url(repo_path(owner, repo_name) .. "/branches")
  end)
)

b:rest(
  "get_repo_branch",
  proxy_handler(function(data)
    local br = (data.values or {})[1]
    return br and translate_bbs_branch(br) or {}
  end, function(owner, repo_name, branch)
    return repo_path(owner, repo_name) .. "/branches?filterText=" .. branch .. "&limit=1"
  end)
)

-- Commits --------------------------------------------------------------------

b:rest("get_repo_commits", function(owner, repo_name)
  local ref = GetParam("sha") or ""
  local url = bbs_page_url(repo_path(owner, repo_name) .. "/commits")
  if ref ~= "" then
    local sep = url:find("?") and "&" or "?"
    url = url .. sep .. "until=" .. ref
  end
  proxy_json(function(data)
    return translate_list(translate_bbs_commit, data.values)
  end, fetch_json(url))
end)

b:rest(
  "get_repo_commit",
  proxy_handler(translate_bbs_commit, function(owner, repo_name, sha)
    return repo_path(owner, repo_name) .. "/commits/" .. sha
  end)
)

-- Contents -------------------------------------------------------------------
-- DC: GET /projects/{proj}/repos/{slug}/raw/{path}?at={ref}

b:rest("get_repo_readme", function(owner, repo_name)
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
end)

-- GET /repos/{owner}/{repo}/license
-- BBS has no license template API; fetch the LICENSE file via raw endpoint.
b:rest("get_repo_license", function(owner, repo_name)
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
end)

b:rest("get_repo_content", function(owner, repo_name, path)
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
end)

-- Forks ----------------------------------------------------------------------

b:rest(
  "get_repo_forks",
  proxy_handler(translate_bbs_repos, function(owner, repo_name)
    return bbs_page_url(repo_path(owner, repo_name) .. "/forks")
  end)
)

b:rest("post_repo_forks", function(owner, repo_name)
  local req = DecodeJson(GetBody() or "{}")
  local bb = {}
  if req.organization then
    bb.project = { key = req.organization }
  end
  proxy_json_created(function(r)
    return translate_bbs_repo(r, owner)
  end, fetch_json(repo_path(owner, repo_name) .. "/forks", "POST", EncodeJson(bb)))
end)

-- Deploy keys ----------------------------------------------------------------
-- DC: /ssh endpoint (not /deploy-keys)

b:rest(
  "get_repo_keys",
  proxy_handler(function(data)
    return translate_list(translate_bbs_key, data.values)
  end, function(owner, repo_name)
    return bbs_page_url(repo_path(owner, repo_name) .. "/ssh")
  end)
)

b:rest("post_repo_keys", function(owner, repo_name)
  local req = DecodeJson(GetBody() or "{}")
  local bb = {
    key = { text = req.key or "", label = req.title or "" },
    permission = "REPO_READ",
  }
  proxy_json_created(
    translate_bbs_key,
    fetch_json(repo_path(owner, repo_name) .. "/ssh", "POST", EncodeJson(bb))
  )
end)

b:rest(
  "get_repo_key",
  proxy_handler(translate_bbs_key, function(owner, repo_name, key_id)
    return repo_path(owner, repo_name) .. "/ssh/" .. key_id
  end)
)

b:rest("delete_repo_key", function(owner, repo_name, key_id)
  local dopts = auth() or {}
  dopts.method = "DELETE"
  proxy_204({ 200 }, pcall(Fetch, repo_path(owner, repo_name) .. "/ssh/" .. key_id, dopts))
end)

-- Webhooks -------------------------------------------------------------------

b:rest(
  "get_repo_hooks",
  proxy_handler(function(data)
    return translate_list(translate_bbs_hook, data.values)
  end, function(owner, repo_name)
    return bbs_page_url(repo_path(owner, repo_name) .. "/webhooks")
  end)
)

b:rest("post_repo_hooks", function(owner, repo_name)
  proxy_json_created(
    translate_bbs_hook,
    fetch_json(
      repo_path(owner, repo_name) .. "/webhooks",
      "POST",
      translate_bbs_hook_req(GetBody())
    )
  )
end)

b:rest(
  "get_repo_hook",
  proxy_handler(translate_bbs_hook, function(owner, repo_name, hook_id)
    return repo_path(owner, repo_name) .. "/webhooks/" .. hook_id
  end)
)

b:rest("patch_repo_hook", function(owner, repo_name, hook_id)
  proxy_json(
    translate_bbs_hook,
    fetch_json(
      repo_path(owner, repo_name) .. "/webhooks/" .. hook_id,
      "PUT",
      translate_bbs_hook_req(GetBody())
    )
  )
end)

b:rest("delete_repo_hook", function(owner, repo_name, hook_id)
  local dopts = auth() or {}
  dopts.method = "DELETE"
  proxy_204({ 200 }, pcall(Fetch, repo_path(owner, repo_name) .. "/webhooks/" .. hook_id, dopts))
end)

b:rest(
  "get_repo_hook_config",
  proxy_handler(function(h)
    return (translate_bbs_hook(h)).config or {}
  end, function(owner, repo_name, hook_id)
    return repo_path(owner, repo_name) .. "/webhooks/" .. hook_id
  end)
)

-- Users ---------------------------------------------------------------------

-- GET /users/{username}
b:rest(
  "get_users_username",
  proxy_handler(translate_bbs_user, function(username)
    return base() .. "/users/" .. username
  end)
)

-- GET /users
b:rest(
  "get_users",
  proxy_handler(function(data)
    return translate_list(translate_bbs_user, (data and data.values))
  end, function()
    return bbs_page_url(base() .. "/users")
  end)
)

-- Pull Requests ---------------------------------------------------------------

-- GET /repos/{owner}/{repo}/pulls
b:rest("get_repo_pulls", function(owner, repo_name)
  local state = GetParam("state") or "open"
  local dc_state = state == "closed" and "MERGED,DECLINED" or state == "all" and "ALL" or "OPEN"
  local url = bbs_page_url(repo_path(owner, repo_name) .. "/pull-requests?state=" .. dc_state)
  proxy_json(translate_bbs_pulls, fetch_json(url))
end)

-- POST /repos/{owner}/{repo}/pulls
b:rest("post_repo_pulls", function(owner, repo_name)
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
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}
b:rest(
  "get_repo_pull",
  proxy_handler(translate_bbs_pull, function(owner, repo_name, pull_number)
    return repo_path(owner, repo_name) .. "/pull-requests/" .. pull_number
  end)
)

-- PATCH /repos/{owner}/{repo}/pulls/{pull_number}
-- DC uses PUT for updates and requires a version field.
b:rest("patch_repo_pull", function(owner, repo_name, pull_number)
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
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/commits
b:rest(
  "get_pull_commits",
  proxy_handler(function(data)
    return translate_list(translate_bbs_commit, (data and data.values))
  end, function(owner, repo_name, pull_number)
    return bbs_page_url(
      repo_path(owner, repo_name) .. "/pull-requests/" .. pull_number .. "/commits"
    )
  end)
)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/files
-- DC uses /changes for per-file info (no line stats).
b:rest(
  "get_pull_files",
  proxy_handler(function(data)
    return translate_list(translate_bbs_pr_change, (data and data.values))
  end, function(owner, repo_name, pull_number)
    return bbs_page_url(
      repo_path(owner, repo_name) .. "/pull-requests/" .. pull_number .. "/changes"
    )
  end)
)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/merge
-- Cannot use proxy_json: DC always returns 200 with a PR object; the response
-- status (204 merged / 404 not merged) is synthesised from the body's state field.
b:rest("get_pull_merge", function(owner, repo_name, pull_number)
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
end)

-- PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge
-- DC: POST /pull-requests/{id}/merge; requires version from current PR.
b:rest("put_pull_merge", function(owner, repo_name, pull_number)
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
  proxy_204({ 200 }, fetch_json(pr_url .. "/merge", "POST", EncodeJson(dc)))
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/requested_reviewers
-- DC: reviewers in PR object who have not yet approved.
b:rest("get_pull_requested_reviewers", function(owner, repo_name, pull_number)
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
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews
-- DC: reviewers with approved=true in PR object.
b:rest("get_pull_reviews", function(owner, repo_name, pull_number)
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
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}
b:rest("get_pull_review", function(owner, repo_name, pull_number, review_id)
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
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}/comments
-- DC has no per-review comments; return all PR inline comments.
b:rest("get_pull_review_comments", function(owner, repo_name, pull_number)
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
end)

-- Issues -----------------------------------------------------------------------
-- Bitbucket Datacenter has no native issue tracker; it relies on Jira.
-- All issues, labels, milestones, and assignees endpoints fall back to the
-- default empty-list handlers defined in .init.lua.

-- Search -----------------------------------------------------------------------

-- GET /search/repositories — DC: GET /repos?name=<q>
b:rest("search_repositories", function()
  local q = GetParam("q") or ""
  proxy_search_envelope(
    translate_bbs_repo,
    "values",
    fetch_json(bbs_page_url(base() .. "/repos?name=" .. q))
  )
end)

-- GET /search/users — DC: GET /users?filter=<q>
b:rest("search_users", function()
  local q = GetParam("q") or ""
  proxy_search_envelope(
    translate_bbs_user,
    "values",
    fetch_json(bbs_page_url(base() .. "/users?filter=" .. q))
  )
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/comments
-- DC inline PR comments (those with an anchor field).
b:rest("get_pull_comments", function(owner, repo_name, pull_number)
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
end)

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

b:rest("post_check_runs", function(owner, repo_name) -- luacheck: ignore 212
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
  local mapped = bbs_dc_to_gh[dc_state] or { status = "completed", conclusion = "failure" }
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
end)

-- GET /repos/{owner}/{repo}/commits/{ref}/check-runs
-- Uses DC build status API.
b:rest("get_commit_check_runs", function(_owner, _repo_name, ref)
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
  local runs = {}
  for i, s in ipairs(data.values or {}) do
    local mapped = bbs_dc_to_gh[s.state] or { status = "completed", conclusion = "failure" }
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
end)

-- Check suites have no DC equivalent; all suite endpoints fall back to
-- the route_defaults stubs defined in .init.lua.

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
  for _, br in ipairs(data.values or {}) do
    if br.isDefault then
      return br.latestCommit or br.latestChangeset
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

b:rest("list_repo_code_scanning_alerts", function(owner, repo_name)
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
end)

b:rest("list_code_scanning_analyses", function(owner, repo_name)
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
end)

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

b:rest("list_git_matching_refs", function(owner, repo_name, ref)
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
    return translate_list(translate_bbs_ref, data.values)
  end, fetch_json(url))
end)

b:rest("get_git_ref", function(owner, repo_name, ref)
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
end)

b:rest("create_git_ref", function(owner, repo_name)
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
end)

b:rest("delete_git_ref", function(owner, repo_name, ref)
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
  proxy_204({ 200, 202 }, pcall(Fetch, url, dopts))
end)

-- GraphQL resolvers -----------------------------------------------------------
-- BBS scope: Query.repository, Query.user, Repository.pullRequests.
-- No GET /user → Query.viewer returns null (handled by default).
-- No native issue tracker → issue resolvers omitted.

-- Shared pagination helper for BBS /values arrays.
-- BBS pagination uses start (offset) and limit (page size);
-- graphql_cursor_url can't be used because BBS start = (page-1)*limit, not page number.
--
-- Backward pagination (last/before):
--   before: cursor(P) → page P-1, start (P-2)*limit (graphql_make_connection handles before(1))
--   last: N without before → page 1 fallback (BBS has no total-count endpoint)
local function bbs_repo_connection(owner, repo_name, suffix, args, ctx, translate_fn, make_conn)
  local per_page = args.last or args.first or 30
  local page = 1
  if args.before then
    local before_page = graphql_cursor_to_page(args.before)
    if before_page and before_page >= 2 then
      page = before_page - 1
    end
    -- else: before page 1 or invalid → page 1; graphql_make_connection returns empty
  elseif args.after then
    local p = graphql_cursor_to_page(args.after)
    if p then
      page = p + 1
    end
  end
  local start = (page - 1) * per_page
  local url = repo_path(owner, repo_name) .. suffix
  local sep = url:find("?", 1, true) and "&" or "?"
  url = url .. sep .. "limit=" .. tostring(per_page)
  if start > 0 then
    url = url .. "&start=" .. tostring(start)
  end
  local data, _, err = graphql_fetch_with_headers(fetch_json, url)
  if not data then
    graphql_error(ctx, err)
    return nil
  end
  local nodes = {}
  for _, item in ipairs(data.values or {}) do
    nodes[#nodes + 1] = translate_fn(item)
  end
  return make_conn(nodes, args, nil, ctx)
end

b:graphql("Query.repository", function(_parent, args, ctx)
  if not args.owner or not args.name then
    graphql_error(ctx, "repository requires owner and name arguments")
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, repo_path(args.owner, args.name))
  if not data then
    return nil
  end
  return graphql_translate_repo(translate_bbs_repo(data))
end)

b:graphql("node.Repository", function(local_id, _ctx)
  local owner, name = local_id:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, repo_path(owner, name))
  if not data then
    return nil
  end
  return graphql_translate_repo(translate_bbs_repo(data))
end)

b:graphql("Query.user", function(_parent, args, ctx)
  if not args.login then
    graphql_error(ctx, "user requires a login argument")
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, base() .. "/users/" .. args.login)
  if not data then
    return nil
  end
  return graphql_translate_user(translate_bbs_user(data))
end)

b:graphql("node.User", function(local_id, _ctx)
  local data, _ = graphql_fetch(fetch_json, base() .. "/users/" .. local_id)
  if not data then
    return nil
  end
  return graphql_translate_user(translate_bbs_user(data))
end)

b:graphql("Repository.pullRequests", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return bbs_repo_connection(owner, name, "/pull-requests", args, ctx, function(pr)
    return graphql_translate_pr(translate_bbs_pull(pr), owner, name)
  end, graphql_prs_connection)
end)

b:graphql("node.PullRequest", function(local_id, _ctx)
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, repo_path(owner, repo) .. "/pull-requests/" .. number)
  if not data then
    return nil
  end
  return graphql_translate_pr(translate_bbs_pull(data), owner, repo)
end)

-- Webhook handlers: Bitbucket Data Center has no native issue tracker
-- (it defers to Jira for issue management), so no issue:created /
-- issue:updated / issue:comment_created events exist.
--
-- pull_request events are registered below using BBS-specific event keys.
-- BBS PR webhook payloads use pullRequest (capital R) for the PR object,
-- actor for the sender, and toRef.repository for the target repository.
local function bbs_pr_event(payload, action)
  local raw_pr = payload.pullRequest or {}
  local repo = (raw_pr.toRef or {}).repository
  return make_internal_event({
    event = "pull_request",
    action = action,
    provider = "bitbucket_datacenter",
    raw = payload,
    data = {
      action = action,
      number = raw_pr.id,
      pull_request = translate_bbs_pull(raw_pr),
      repository = translate_bbs_repo(repo),
      sender = translate_bbs_user(payload.actor or {}),
    },
    timestamp = bbs_ts(raw_pr.updatedDate) or "",
  })
end

b:webhook("pr:opened", function(payload)
  return bbs_pr_event(payload, "opened")
end)

b:webhook("pr:modified", function(payload)
  -- pr:modified fires on title/description changes and when a DECLINED PR is
  -- reopened.  Without prior-state tracking, reopen is indistinguishable from
  -- edit; both map to "edited".
  return bbs_pr_event(payload, "edited")
end)

b:webhook("pr:from_ref_updated", function(payload)
  return bbs_pr_event(payload, "synchronize")
end)

b:webhook("pr:reviewer:updated", function(payload)
  local added = payload.addedReviewers or {}
  local action = #added > 0 and "review_requested" or "review_request_removed"
  return bbs_pr_event(payload, action)
end)

b:webhook("pr:merged", function(payload)
  return bbs_pr_event(payload, "closed")
end)

b:webhook("pr:declined", function(payload)
  return bbs_pr_event(payload, "closed")
end)

b:webhook("pr:deleted", function(payload)
  return bbs_pr_event(payload, "closed")
end)

-- pull_request_review events.
-- pr:reviewer:approved   → submitted / APPROVED
-- pr:reviewer:needs_work → submitted / CHANGES_REQUESTED
--
-- Bitbucket Datacenter does not have an explicit dismiss action; both
-- approved and needs_work map to "submitted" with the corresponding state.
-- The participant object carries the reviewer; the pullRequest carries
-- the PR context and timestamp.
local function bbs_review_event(payload, state)
  local raw_pr = payload.pullRequest or {}
  local repo = (raw_pr.toRef or {}).repository
  local participant = payload.participant or {}
  local reviewer = participant.user or {}
  local review = {
    id = 0,
    node_id = "",
    user = translate_bbs_user(reviewer),
    body = "",
    state = state,
    submitted_at = bbs_ts(raw_pr.updatedDate) or "",
    html_url = "",
    pull_request_url = "",
  }
  return make_internal_event({
    event = "pull_request_review",
    action = "submitted",
    provider = "bitbucket_datacenter",
    raw = payload,
    data = {
      action = "submitted",
      review = review,
      pull_request = translate_bbs_pull(raw_pr),
      repository = translate_bbs_repo(repo),
      sender = translate_bbs_user(payload.actor or {}),
    },
    timestamp = bbs_ts(raw_pr.updatedDate) or "",
  })
end

b:webhook("pr:reviewer:approved", function(payload)
  return bbs_review_event(payload, "APPROVED")
end)

b:webhook("pr:reviewer:needs_work", function(payload)
  return bbs_review_event(payload, "CHANGES_REQUESTED")
end)

-- Build status events: build:status_created, build:status_updated.
-- Bitbucket Data Center emits these when an external CI system posts a build
-- result against a commit.  Both events carry the same payload shape and map
-- to the GitHub status event.  The translated state is promoted to the action
-- slot for consumer-side filtering without payload inspection.
-- DC uses camelCase field names and epoch-millisecond timestamps (bbs_ts).
-- The commit SHA is the top-level commit.id field (unlike Bitbucket Cloud,
-- where it must be extracted from a link href).
local BBS_BUILD_STATE_TO_GITHUB = {
  INPROGRESS = "pending",
  SUCCESSFUL = "success",
  FAILED = "failure",
  STOPPED = "error",
}
local function bbs_build_status_event(payload)
  local bs = payload.buildStatus or {}
  local commit = payload.commit or {}
  local state = BBS_BUILD_STATE_TO_GITHUB[bs.state or ""] or "error"
  local sha = commit.id or ""
  local repo = payload.repository or {}
  local data = {
    id = 0,
    sha = sha,
    name = repo.slug or "",
    target_url = bs.url,
    context = bs.key or "",
    description = bs.description or "",
    state = state,
    commit = nil,
    branches = {},
    created_at = bbs_ts(bs.createdDate) or "",
    updated_at = bbs_ts(bs.updatedDate) or "",
    repository = translate_bbs_repo(repo),
    sender = translate_bbs_user(payload.actor or {}),
  }
  return make_internal_event({
    event = "status",
    action = state,
    provider = "bitbucket_datacenter",
    raw = payload,
    data = data,
    timestamp = bbs_ts(bs.updatedDate) or bbs_ts(bs.createdDate) or "",
  })
end

b:webhook("build:status_created", function(payload)
  return bbs_build_status_event(payload)
end)

b:webhook("build:status_updated", function(payload)
  return bbs_build_status_event(payload)
end)

-- repo:refs_changed: branch or tag push (including creation and deletion).
-- BBS uses a single `repo:refs_changed` event for all ref operations.
-- The change.type field identifies the operation:
--   "ADD"    → branch or tag created → GitHub create event
--   "DELETE" → branch or tag deleted → GitHub delete event
--   "UPDATE" → regular push           → GitHub push event
-- BBS webhook payloads do not include a commit list in refs_changed; the push
-- event therefore has an empty commits array and no head_commit.
b:webhook("repo:refs_changed", function(payload)
  local changes = payload.changes or {}
  local change = changes[1] or {}
  local ref = change.ref or {}
  local repo = payload.repository or {}
  local actor = payload.actor or {}
  local sender = translate_bbs_user(actor)
  local repository = translate_bbs_repo(repo)
  local ref_type = (ref.type or "BRANCH"):lower()
  local ref_name = ref.displayId or ""
  local full_ref = ref.id or ""
  local change_type = change.type or ""

  if change_type == "ADD" then
    -- Branch or tag created — emit GitHub create event.
    return make_internal_event({
      event = "create",
      action = "create",
      provider = "bitbucket_datacenter",
      raw = payload,
      data = {
        ref = ref_name,
        ref_type = ref_type,
        master_branch = repository.default_branch or "",
        description = repo.description,
        pusher_type = "user",
        repository = repository,
        sender = sender,
      },
      timestamp = "",
    })
  end

  if change_type == "DELETE" then
    -- Branch or tag deleted — emit GitHub delete event.
    return make_internal_event({
      event = "delete",
      action = "delete",
      provider = "bitbucket_datacenter",
      raw = payload,
      data = {
        ref = ref_name,
        ref_type = ref_type,
        master_branch = repository.default_branch or "",
        description = repo.description,
        pusher_type = "user",
        repository = repository,
        sender = sender,
      },
      timestamp = "",
    })
  end

  -- Regular push (UPDATE) — emit GitHub push event.
  -- BBS does not include a commit list in refs_changed payloads.
  local before = change.fromHash or "0000000000000000000000000000000000000000"
  local after = change.toHash or "0000000000000000000000000000000000000000"
  return make_internal_event({
    event = "push",
    action = "push",
    provider = "bitbucket_datacenter",
    raw = payload,
    data = {
      ref = full_ref,
      before = before,
      after = after,
      created = false,
      deleted = false,
      forced = false,
      compare = "",
      commits = {},
      head_commit = nil,
      pusher = {
        name = actor.name or actor.displayName or "",
        email = actor.emailAddress or "",
      },
      repository = repository,
      sender = sender,
    },
    timestamp = "",
  })
end)

b:build()
