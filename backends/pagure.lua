-- Pagure backend handler overrides.
-- Uses Pagure REST API at /api/0/.
-- Repos are addressed as /api/0/{namespace}/{repo} (owner = namespace/username).
if config.base_url == "" then
  config.base_url = "https://pagure.io"
end

local base = function()
  return config.base_url .. "/api/0"
end
local auth = function()
  return make_fetch_opts("token")
end
local PAGES = { per_page = "per_page", page = "page" }
local _t = make_backend_transport("token", PAGES)
local fetch_json = _t.fetch_json
local proxy_handler = _t.proxy_handler

-- Map a Pagure project object to GitHub repo format.
local function translate_pagure_repo(r)
  if not r then
    return {}
  end
  local user = r.user or {}
  local ns = r.namespace or ""
  local owner_login = ns ~= "" and ns or user.name or ""
  return {
    id = r.id or 0,
    node_id = "",
    name = r.name,
    full_name = r.fullname or (owner_login .. "/" .. (r.name or "")),
    private = r.private or false,
    owner = {
      login = owner_login,
      id = 0,
      node_id = "",
      avatar_url = "",
      url = "",
      html_url = config.base_url .. "/" .. (user.url_path or user.name or ""),
      type = ns ~= "" and "Organization" or "User",
    },
    html_url = config.base_url .. "/" .. (r.url_path or ""),
    description = r.description,
    fork = r.parent ~= nil,
    url = "",
    clone_url = r.full_url or "",
    homepage = r.url or "",
    size = 0,
    stargazers_count = r.stars or 0,
    watchers_count = 0,
    language = nil,
    has_issues = true,
    has_wiki = r.settings and r.settings.wiki_enabled or false,
    forks_count = r.forks_count or 0,
    archived = r.close_status ~= nil and r.close_status ~= "",
    disabled = false,
    open_issues_count = 0,
    default_branch = r.default_branch or "main",
    visibility = (r.private or false) and "private" or "public",
    forks = r.forks_count or 0,
    open_issues = 0,
    watchers = 0,
    created_at = r.date_created,
    updated_at = r.date_modified,
    pushed_at = r.date_modified,
  }
end

-- Translate a Pagure branch name to GitHub format.
-- Pagure branch list returns only names, no commit SHAs.
local function translate_pagure_branch(name)
  return { name = name, commit = { sha = "", url = "" }, protected = false }
end

-- Translate a Pagure commit object to GitHub format.
-- Pagure: { id, message, date, date_utc, author: { name, email } }

-- Translate a Pagure user to GitHub format.
local function translate_pagure_user(u)
  if not u then
    return {}
  end
  return {
    login = u.name or u.username or "",
    id = 0,
    node_id = "",
    avatar_url = u.avatar_url or "",
    html_url = config.base_url .. "/" .. (u.url_path or u.name or ""),
    type = "User",
    site_admin = false,
    name = u.fullname or u.name or "",
  }
end

-- Translate a Pagure issue tag (string) to a GitHub label object.
local function translate_pagure_tag(tag)
  return {
    id = 0,
    node_id = "",
    url = "",
    name = tag or "",
    color = "",
    description = "",
    default = false,
  }
end

-- Translate a Pagure issue to GitHub format.
-- Pagure states: "Open", "Closed"
-- Pagure dates: Unix timestamps as strings
local function translate_pagure_issue(i)
  if not i then
    return {}
  end
  local state = (i.status == "Open") and "open" or "closed"
  local labels = {}
  for _, tag in ipairs(i.tags or {}) do
    labels[#labels + 1] = translate_pagure_tag(tag)
  end
  local assignees = {}
  if i.assignee then
    assignees[1] = translate_pagure_user(i.assignee)
  end
  local user = translate_pagure_user(i.user)
  -- Pagure date_created is a Unix timestamp string; convert to ISO 8601
  local function ts(v)
    if not v then
      return ""
    end
    -- Try to return as-is if it looks like a timestamp (digits only)
    return tostring(v)
  end
  return {
    id = i.id or 0,
    number = i.id or 0,
    title = i.title or "",
    body = i.content or "",
    state = state,
    user = user,
    assignees = assignees,
    labels = labels,
    milestone = nil,
    created_at = ts(i.date_created),
    updated_at = ts(i.last_updated),
    closed_at = nil,
    html_url = config.base_url .. "/" .. (i.full_url or ""),
  }
end

-- Translate a Pagure comment to GitHub format.
local function translate_pagure_comment(c)
  if not c then
    return {}
  end
  return {
    id = c.id or 0,
    body = c.comment or "",
    user = translate_pagure_user(c.user),
    created_at = tostring(c.date_created or ""),
    updated_at = tostring(c.date_created or ""),
    html_url = "",
  }
end

local function translate_pagure_commit(c)
  if not c then
    return {}
  end
  local author = c.author or {}
  return {
    sha = c.id or "",
    commit = {
      message = c.message or "",
      author = { name = author.name or "", email = author.email or "", date = c.date_utc or "" },
      committer = { name = author.name or "", email = author.email or "", date = c.date_utc or "" },
    },
    author = { login = author.name or "", id = 0, avatar_url = "" },
    committer = { login = author.name or "", id = 0, avatar_url = "" },
  }
end

local function translate_pagure_issues(data)
  return translate_list(translate_pagure_issue, data.issues)
end

-- Map Pagure flag statuses to GitHub check-run status/conclusion.
local pagure_to_gh = {
  pending = { status = "in_progress", conclusion = nil },
  success = { status = "completed", conclusion = "success" },
  canceled = { status = "completed", conclusion = "cancelled" },
}

local b = make_backend_builder()
b:rest("get_root", function()
  proxy_health_check(pcall(Fetch, base() .. "/version", auth()))
end)

b:rest(
  "get_repo",
  proxy_handler(translate_pagure_repo, function(owner, repo_name)
    return base() .. "/" .. owner .. "/" .. repo_name
  end)
)

b:rest("patch_repo", function(owner, repo_name)
  -- Pagure: update project description via POST /api/0/{owner}/{repo}/modify
  local url = base() .. "/" .. owner .. "/" .. repo_name .. "/modify"
  local req = DecodeJson(GetBody() or "{}")
  local pg = {}
  if req.description then
    pg.description = req.description
  end
  if req.private ~= nil then
    pg.private = req.private
  end
  -- Pagure /modify returns { "repo": {...} }
  proxy_json(function(resp)
    return translate_pagure_repo(resp.repo or resp)
  end, fetch_json(url, "POST", EncodeJson(pg)))
end)

b:rest("delete_repo", function(owner, repo_name)
  -- Pagure: delete project via POST /api/0/{owner}/{repo}/delete
  local url = base() .. "/" .. owner .. "/" .. repo_name .. "/delete"
  proxy_204({ 200 }, fetch_json(url, "POST", "{}"))
end)

b:rest("get_user_repos", function()
  -- Pagure: /api/0/projects?author={user} — need to know the authenticated user first
  local ok, status, _, ubody = fetch_json(base() .. "/-/whoami")
  if not ok or status ~= 200 then
    respond_json(503, {})
    return
  end
  local me = DecodeJson(ubody)
  local username = me.username or me.name or ""
  proxy_json(function(data)
    return translate_list(translate_pagure_repo, data.projects)
  end, fetch_json(append_page_params(base() .. "/user/" .. username .. "/projects", PAGES)))
end)

b:rest("post_user_repos", function()
  -- Pagure: create project via POST /api/0/new
  local req = DecodeJson(GetBody() or "{}")
  local pg = {
    name = req.name,
    description = req.description or "",
    private = req.private or false,
  }
  proxy_json_created(function(resp)
    return translate_pagure_repo(resp.project or resp)
  end, fetch_json(base() .. "/new", "POST", EncodeJson(pg)))
end)

b:rest(
  "get_org_repos",
  proxy_handler(function(data)
    return translate_list(translate_pagure_repo, data.projects)
  end, function(namespace)
    return append_page_params(base() .. "/projects?namespace=" .. namespace, PAGES)
  end)
)

b:rest("post_org_repos", function(namespace)
  -- Pagure: create project with namespace
  local req = DecodeJson(GetBody() or "{}")
  local pg = {
    name = req.name,
    description = req.description or "",
    private = req.private or false,
    namespace = namespace,
  }
  proxy_json_created(function(resp)
    return translate_pagure_repo(resp.project or resp)
  end, fetch_json(base() .. "/new", "POST", EncodeJson(pg)))
end)

b:rest(
  "get_repo_topics",
  proxy_handler(function(r)
    return { names = r.tags or {} }
  end, function(owner, repo_name)
    return base() .. "/" .. owner .. "/" .. repo_name
  end)
)

b:rest("put_repo_topics", function(owner, repo_name)
  -- Pagure: set tags via POST /api/0/{owner}/{repo}/modify with tags field
  local url = base() .. "/" .. owner .. "/" .. repo_name .. "/modify"
  local req = DecodeJson(GetBody() or "{}")
  proxy_json(function(resp)
    local r = resp.repo or resp
    return { names = r.tags or {} }
  end, fetch_json(url, "POST", EncodeJson({ tags = req.names or {} })))
end)

-- Branches ------------------------------------------------------------------
-- Pagure: GET /api/0/{owner}/{repo}/git/branches → { branches: ["main", ...] }
-- No commit SHAs in branch list response.

b:rest(
  "get_repo_branches",
  proxy_handler(function(data)
    return translate_list(translate_pagure_branch, data.branches)
  end, function(owner, repo_name)
    return base() .. "/" .. owner .. "/" .. repo_name .. "/git/branches"
  end)
)

-- Commits -------------------------------------------------------------------
-- Pagure: GET /api/0/{owner}/{repo}/commits?branch={branch}&limit={n}&start={offset}

b:rest("get_repo_commits", function(owner, repo_name)
  local branch = GetParam("sha") or GetParam("branch") or ""
  local limit = GetParam("per_page") or "30"
  local page = tonumber(GetParam("page")) or 1
  local limit_n = tonumber(limit) or 30
  local start = (page - 1) * limit_n
  local url = base()
    .. "/"
    .. owner
    .. "/"
    .. repo_name
    .. "/commits?limit="
    .. limit
    .. "&start="
    .. start
  if branch ~= "" then
    url = url .. "&branch=" .. branch
  end
  proxy_json(function(data)
    return translate_list(translate_pagure_commit, data.commits)
  end, fetch_json(url))
end)

-- Tags ----------------------------------------------------------------------
-- Pagure returns { "tags": ["v1.0", ...] } — just tag names, no commit info

b:rest(
  "get_repo_tags",
  proxy_handler(function(data)
    local tags = {}
    for _, name in ipairs(data.tags or {}) do
      tags[#tags + 1] = { name = name, commit = { sha = "", url = "" } }
    end
    return tags
  end, function(owner, repo_name)
    return base() .. "/" .. owner .. "/" .. repo_name .. "/git/tags"
  end)
)

-- Contents ------------------------------------------------------------------
-- Pagure: GET /api/0/{owner}/{repo}/raw/{path}?ref={ref} — returns raw bytes.
-- We base64-encode and return a GitHub-shaped content object.

b:rest("get_repo_readme", function(owner, repo_name)
  local ref = GetParam("ref") or ""
  -- Try common README filenames in order.
  local candidates = { "README.md", "README", "readme.md", "README.rst" }
  for _, fname in ipairs(candidates) do
    local url = base() .. "/" .. owner .. "/" .. repo_name .. "/raw/" .. fname
    if ref ~= "" then
      url = url .. "?ref=" .. ref
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

b:rest("get_repo_content", function(owner, repo_name, path)
  local ref = GetParam("ref") or ""
  local url = base() .. "/" .. owner .. "/" .. repo_name .. "/raw/" .. path
  if ref ~= "" then
    url = url .. "?ref=" .. ref
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

-- Forks ---------------------------------------------------------------------
-- Pagure: POST /api/0/fork with form body

b:rest(
  "get_repo_forks",
  proxy_handler(function(data)
    return translate_list(translate_pagure_repo, data.forks)
  end, function(owner, repo_name)
    return base() .. "/" .. owner .. "/" .. repo_name
  end)
)

b:rest("post_repo_forks", function(owner, repo_name)
  -- Pagure fork endpoint expects form-encoded body
  local req = DecodeJson(GetBody() or "{}")
  local fopts = auth() or {}
  fopts.method = "POST"
  fopts.body = "repo=" .. repo_name .. "&namespace=" .. owner
  if req.organization then
    fopts.body = fopts.body .. "&username=" .. req.organization
  end
  fopts.headers = fopts.headers or {}
  fopts.headers["Content-Type"] = "application/x-www-form-urlencoded"
  proxy_json_created(function(resp)
    return translate_pagure_repo(resp.project or resp)
  end, pcall(Fetch, base() .. "/fork", fopts))
end)

-- Users ---------------------------------------------------------------------

-- GET /user — two-step: whoami then full profile
b:rest("get_user", function()
  local ok, status, _, ubody = fetch_json(base() .. "/-/whoami")
  if not ok or status ~= 200 then
    respond_json(503, {})
    return
  end
  local me = DecodeJson(ubody) or {}
  local username = me.username or ""
  if username == "" then
    respond_json(503, {})
    return
  end
  proxy_json(function(data)
    local u = data.user or data
    return {
      login = u.username or "",
      id = 0,
      node_id = "",
      avatar_url = u.avatar_url or "",
      html_url = config.base_url .. "/" .. (u.username or ""),
      type = "User",
      site_admin = false,
      name = u.fullname or "",
      email = (u.emails and u.emails[1]) or "",
    }
  end, fetch_json(base() .. "/user/" .. username))
end)

-- GET /users/{username}
b:rest(
  "get_users_username",
  proxy_handler(function(data)
    local u = data.user or data
    return {
      login = u.username or "",
      id = 0,
      node_id = "",
      avatar_url = u.avatar_url or "",
      html_url = config.base_url .. "/" .. (u.username or ""),
      type = "User",
      site_admin = false,
      name = u.fullname or "",
    }
  end, function(username)
    return base() .. "/user/" .. username
  end)
)

-- GET /users
b:rest(
  "get_users",
  proxy_handler(function(data)
    local users = {}
    for _, name in ipairs(data.users or {}) do
      users[#users + 1] = {
        login = name,
        id = 0,
        node_id = "",
        avatar_url = "",
        html_url = config.base_url .. "/" .. name,
        type = "User",
        site_admin = false,
      }
    end
    return users
  end, function()
    return base() .. "/users"
  end)
)

-- Users' repos --------------------------------------------------------------

b:rest(
  "get_users_repos",
  proxy_handler(function(data)
    return translate_list(translate_pagure_repo, data.repos or data.projects)
  end, function(username)
    return append_page_params(base() .. "/user/" .. username .. "/projects", PAGES)
  end)
)

-- Public repos list ---------------------------------------------------------

b:rest("get_repositories", function()
  proxy_json(function(data)
    return translate_list(translate_pagure_repo, data.projects)
  end, fetch_json(append_page_params(base() .. "/repos", PAGES)))
end)

-- Issues --------------------------------------------------------------------

b:rest(
  "get_repo_issues",
  proxy_handler(translate_pagure_issues, function(o, r)
    return append_page_params(base() .. "/" .. o .. "/" .. r .. "/issues", PAGES)
  end)
)

-- Pagure uses /issue/{id} (singular) for individual issues
b:rest(
  "get_repo_issue",
  proxy_handler(translate_pagure_issue, function(o, r, n)
    return base() .. "/" .. o .. "/" .. r .. "/issue/" .. n
  end)
)

b:rest("get_issue_comments", function(owner, repo_name, issue_number)
  -- Pagure returns comments embedded in the issue object
  local ok, status, _, body =
    fetch_json(base() .. "/" .. owner .. "/" .. repo_name .. "/issue/" .. issue_number)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local issue = DecodeJson(body or "{}") or {}
  respond_json(200, translate_list(translate_pagure_comment, issue.comments))
end)

b:rest("get_repo_labels", function(_owner, _repo_name)
  -- Pagure has no repo-level label list endpoint; return empty list
  respond_json(200, {})
end)

-- Checks (via Pagure commit flags) ------------------------------------------
--
-- Pagure exposes a flags API for CI status at:
--   GET  /api/0/{owner}/{repo}/c/{commit}/flag  — list flags on a commit
--   POST /api/0/{owner}/{repo}/c/{commit}/flag  — create/update a flag
--
-- Pagure flag fields: uid, username, percent, comment, url, status,
--   date_created, date_updated
-- Pagure flag statuses: "success", "failure", "error", "pending", "canceled"
--
-- GitHub → Pagure state:
--   queued/in_progress          → pending
--   completed/success|neutral|skipped → success
--   completed/failure           → failure
--   completed/(other)           → error
--
-- Pagure → GitHub:
--   pending   → status=in_progress, conclusion=nil
--   success   → status=completed,   conclusion=success
--   failure   → status=completed,   conclusion=failure
--   error     → status=completed,   conclusion=failure
--   canceled  → status=completed,   conclusion=cancelled

b:rest("post_check_runs", function(owner, repo_name)
  local req = DecodeJson(GetBody() or "{}") or {}
  local sha = req.head_sha or ""
  local status = req.status or "queued"
  local conclusion = req.conclusion
  local gh_conclusion_to_pagure = {
    success = "success",
    neutral = "success",
    skipped = "success",
    cancelled = "canceled",
    failure = "failure",
  }
  local pg_status = status == "completed" and (gh_conclusion_to_pagure[conclusion] or "error")
    or "pending"
  local url = base() .. "/" .. owner .. "/" .. repo_name .. "/c/" .. sha .. "/flag"
  local flag = {
    username = req.name or "",
    percent = (pg_status == "success") and 100 or (pg_status == "pending" and 0 or 0),
    comment = (req.output and req.output.summary) or req.name or "",
    url = req.details_url or "",
    uid = req.name or sha,
    status = pg_status,
  }
  local function translate(f)
    if not f then
      return {}
    end
    local s = f.status or "pending"
    local mapped = pagure_to_gh[s] or { status = "completed", conclusion = "failure" }
    local gh_status, gh_conclusion = mapped.status, mapped.conclusion
    return {
      id = 1,
      node_id = "",
      head_sha = sha,
      name = f.username or req.name or "",
      status = gh_status,
      conclusion = gh_conclusion,
      started_at = f.date_created,
      completed_at = gh_status == "completed" and f.date_updated or nil,
      output = {
        title = f.comment or "",
        summary = f.comment or "",
        text = "",
        annotations_count = 0,
        annotations_url = "",
      },
      url = "",
      html_url = f.url or "",
      details_url = f.url or "",
    }
  end
  local ok, pg_status_code, _, body = fetch_json(url, "POST", EncodeJson(flag))
  if not ok then
    respond_json(503, {})
    return
  end
  -- Pagure returns the created flag object
  local resp = DecodeJson(body or "{}") or {}
  local flag_obj = resp.flag or flag
  if pg_status_code == 200 or pg_status_code == 201 then
    respond_json(201, translate(flag_obj))
  else
    respond_json(pg_status_code, {})
  end
end)

b:rest("get_commit_check_runs", function(owner, repo_name, ref)
  local url = base() .. "/" .. owner .. "/" .. repo_name .. "/c/" .. ref .. "/flag"
  local ok, status, _, body = fetch_json(url)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local data = DecodeJson(body or "{}") or {}
  local flags = data.flags or {}
  local runs = {}
  for i, f in ipairs(flags) do
    local s = f.status or "pending"
    local mapped = pagure_to_gh[s] or { status = "completed", conclusion = "failure" }
    local gh_status, gh_conclusion = mapped.status, mapped.conclusion
    runs[i] = {
      id = i,
      node_id = "",
      head_sha = ref,
      name = f.username or "",
      status = gh_status,
      conclusion = gh_conclusion,
      started_at = f.date_created,
      completed_at = gh_status == "completed" and f.date_updated or nil,
      output = {
        title = f.comment or "",
        summary = f.comment or "",
        text = "",
        annotations_count = 0,
        annotations_url = "",
      },
      url = "",
      html_url = f.url or "",
      details_url = f.url or "",
    }
  end
  respond_json(200, { total_count = #runs, check_runs = runs })
end)

-- Check suites have no Pagure equivalent; all suite endpoints fall back to
-- the route_defaults stubs defined in .init.lua.

-- ---------------------------------------------------------------------------
-- GraphQL resolvers
-- ---------------------------------------------------------------------------

-- Query.viewer: resolve the authenticated user via whoami then /user/{username}.
b:graphql("Query.viewer", function(_parent, _args, ctx)
  local whoami, _ = graphql_fetch(fetch_json, base() .. "/-/whoami")
  if not whoami then
    graphql_error(ctx, "could not determine authenticated user", nil, "FORBIDDEN")
    return nil
  end
  local username = whoami.username or ""
  if username == "" then
    graphql_error(ctx, "empty username from whoami", nil, "FORBIDDEN")
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, base() .. "/user/" .. username)
  if not data then
    return nil
  end
  local u = data.user or data
  local gh_user = translate_pagure_user(u)
  gh_user.email = (u.emails and u.emails[1]) or ""
  local result = graphql_translate_user(gh_user)
  result.isViewer = true
  return result
end)

-- Query.user: look up a User by login.
b:graphql("Query.user", function(_parent, args, ctx)
  if not args.login then
    graphql_error(ctx, "user requires a login argument")
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, base() .. "/user/" .. args.login)
  if not data then
    return nil
  end
  local u = data.user or data
  local gh_user = translate_pagure_user(u)
  gh_user.email = (u.emails and u.emails[1]) or ""
  return graphql_translate_user(gh_user)
end)

-- Query.repositoryOwner: look up a user by login.
-- Pagure has no organization concept; all owners are users.
b:graphql("Query.repositoryOwner", function(_parent, args, ctx)
  if not args.login then
    graphql_error(ctx, "repositoryOwner requires a login argument")
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, base() .. "/user/" .. args.login)
  if not data then
    return nil
  end
  local u = data.user or data
  local gh_user = translate_pagure_user(u)
  gh_user.email = (u.emails and u.emails[1]) or ""
  return graphql_translate_user(gh_user)
end)

-- Query.repository: look up a Repository by owner and name.
b:graphql("Query.repository", function(_parent, args, ctx)
  if not args.owner or not args.name then
    graphql_error(ctx, "repository requires owner and name arguments")
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, base() .. "/" .. args.owner .. "/" .. args.name)
  if not data then
    return nil
  end
  return graphql_translate_repo(translate_pagure_repo(data))
end)

-- node.Repository: fetch a repository by "owner/repo" local ID.
b:graphql("node.Repository", function(local_id, _ctx)
  local data, _ = graphql_fetch(fetch_json, base() .. "/" .. local_id)
  if not data then
    return nil
  end
  return graphql_translate_repo(translate_pagure_repo(data))
end)

-- node.User: fetch a user by login.
b:graphql("node.User", function(local_id, _ctx)
  local data, _ = graphql_fetch(fetch_json, base() .. "/user/" .. local_id)
  if not data then
    return nil
  end
  local u = data.user or data
  local gh_user = translate_pagure_user(u)
  gh_user.email = (u.emails and u.emails[1]) or ""
  return graphql_translate_user(gh_user)
end)

-- node.Issue: fetch an issue by "owner/repo/number" local ID.
-- Pagure uses /issue/{number} (singular) for individual issues.
b:graphql("node.Issue", function(local_id, _ctx)
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ =
    graphql_fetch(fetch_json, base() .. "/" .. owner .. "/" .. repo .. "/issue/" .. number)
  if not data then
    return nil
  end
  return graphql_translate_issue(translate_pagure_issue(data), owner, repo)
end)

-- node.IssueComment: fetch a comment by "owner/repo/issue_number/comment_id" local ID.
-- Pagure embeds comments in the issue; we fetch the issue and find the comment by id.
b:graphql("node.IssueComment", function(local_id, _ctx)
  local owner, repo, issue_num, cid = local_id:match("^([^/]+)/([^/]+)/(%d+)/(%d+)$")
  if not owner then
    return nil
  end
  local cid_n = tonumber(cid)
  local data, _ =
    graphql_fetch(fetch_json, base() .. "/" .. owner .. "/" .. repo .. "/issue/" .. issue_num)
  if not data then
    return nil
  end
  for _, c in ipairs(data.comments or {}) do
    if c.id == cid_n then
      local gh_comment = translate_pagure_comment(c)
      local comment_node = graphql_translate_comment(gh_comment, owner, repo)
      comment_node.id =
        encode_node_id("IssueComment", owner .. "/" .. repo .. "/" .. issue_num .. "/" .. cid)
      return comment_node
    end
  end
  return nil
end)

-- Repository.issues: paginated list of issues.
-- Pagure returns {"issues": [...], "total_issues": N}.
b:graphql("Repository.issues", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  local url_base = base() .. "/" .. owner .. "/" .. name .. "/issues"
  local total
  if args.last and not args.before then
    local count_url = graphql_cursor_url(url_base, { first = 1 }, PAGES)
    local pdata, _, _ = graphql_fetch_with_headers(fetch_json, count_url)
    if pdata then
      total = (type(pdata) == "table") and pdata.total_issues or nil
    end
  end
  local url = graphql_cursor_url(url_base, args, PAGES, total)
  local data, _, err = graphql_fetch_with_headers(fetch_json, url)
  if not data then
    graphql_error(ctx, err)
    return nil
  end
  local items = (type(data) == "table") and (data.issues or {}) or {}
  total = ((type(data) == "table") and data.total_issues or nil) or total
  local nodes = {}
  for _, i in ipairs(items) do
    nodes[#nodes + 1] = graphql_translate_issue(translate_pagure_issue(i), owner, name)
  end
  return graphql_issues_connection(nodes, args, total, ctx)
end)

-- Repository.refs: paginated list of branches as Ref objects.
-- Pagure returns {"branches": ["name1", ...], "total_branches": N} — no commit SHAs.
b:graphql("Repository.refs", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  local url_base = base() .. "/" .. owner .. "/" .. name .. "/git/branches"
  local total
  if args.last and not args.before then
    local count_url = graphql_cursor_url(url_base, { first = 1 }, PAGES)
    local pdata, _, _ = graphql_fetch_with_headers(fetch_json, count_url)
    if pdata then
      total = (type(pdata) == "table") and pdata.total_branches or nil
    end
  end
  local url = graphql_cursor_url(url_base, args, PAGES, total)
  local data, _, err = graphql_fetch_with_headers(fetch_json, url)
  if not data then
    graphql_error(ctx, err)
    return nil
  end
  local items = (type(data) == "table") and (data.branches or {}) or {}
  total = ((type(data) == "table") and data.total_branches or nil) or total
  local nodes = {}
  for _, b_name in ipairs(items) do
    -- Pagure branch list returns only names; no commit SHA is available.
    nodes[#nodes + 1] = graphql_translate_ref({ name = b_name }, parent)
  end
  return graphql_refs_connection(nodes, args, total, ctx)
end)

-- Issue.comments: extract embedded comments from a Pagure issue.
-- Pagure embeds all comments in the issue object; we re-fetch to get them.
-- IssueComment node IDs use "owner/repo/issue_number/comment_id" for resolvability.
b:graphql("Issue.comments", function(parent, args, ctx)
  local _, local_id = decode_node_id(parent.id)
  if not local_id then
    return nil
  end
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ =
    graphql_fetch(fetch_json, base() .. "/" .. owner .. "/" .. repo .. "/issue/" .. number)
  if not data then
    graphql_error(ctx, "could not fetch issue comments")
    return nil
  end
  local comments = data.comments or {}
  local nodes = {}
  for _, c in ipairs(comments) do
    local gh_comment = translate_pagure_comment(c)
    local comment_node = graphql_translate_comment(gh_comment, owner, repo)
    comment_node.id = encode_node_id(
      "IssueComment",
      owner .. "/" .. repo .. "/" .. number .. "/" .. tostring(c.id or "")
    )
    nodes[#nodes + 1] = comment_node
  end
  return graphql_make_connection("IssueComment", nodes, args, #nodes, ctx)
end)

-- Query.search: map GitHub GraphQL search to Pagure search endpoints.
-- REPOSITORY: GET /projects?search={query}
-- USER: GET /users?username={query}  (returns name list; build minimal user objects)
-- ISSUE: Pagure has no simple keyword issue search; returns empty.
b:graphql("Query.search", function(_parent, args, ctx)
  local query = args.query or ""
  local search_type = args.type or "REPOSITORY"
  local per_page = args.first or 30
  local q = EscapeParam(query)

  local nodes = {}
  local repo_count, user_count, issue_count = 0, 0, 0

  if search_type == "REPOSITORY" then
    local data, _, err = graphql_fetch_with_headers(
      fetch_json,
      base() .. "/projects?search=" .. q .. "&per_page=" .. per_page
    )
    if not data then
      graphql_error(ctx, err)
    else
      local items = (type(data) == "table") and (data.projects or {}) or {}
      for _, r in ipairs(items) do
        nodes[#nodes + 1] = graphql_translate_repo(translate_pagure_repo(r))
      end
      repo_count = #nodes
    end
  elseif search_type == "USER" then
    local data, _, err = graphql_fetch_with_headers(
      fetch_json,
      base() .. "/users?username=" .. q .. "&per_page=" .. per_page
    )
    if not data then
      graphql_error(ctx, err)
    else
      -- Pagure /users returns an array of login names, not full user objects.
      local items = (type(data) == "table") and (data.users or {}) or {}
      for _, u_name in ipairs(items) do
        nodes[#nodes + 1] = graphql_translate_user({
          login = u_name,
          name = nil,
          email = "",
          avatar_url = "",
          html_url = config.base_url .. "/" .. u_name,
          site_admin = false,
        })
      end
      user_count = #nodes
    end
  end

  local edges = {}
  for i, node in ipairs(nodes) do
    edges[i] = {
      __typename = "SearchResultItemEdge",
      cursor = graphql_page_to_cursor(1, i),
      node = node,
    }
  end
  local n = #edges
  return {
    __typename = "SearchResultItemConnection",
    nodes = nodes,
    edges = edges,
    pageInfo = {
      __typename = "PageInfo",
      hasNextPage = false,
      hasPreviousPage = false,
      startCursor = n > 0 and edges[1].cursor or nil,
      endCursor = n > 0 and edges[n].cursor or nil,
    },
    repositoryCount = repo_count,
    userCount = user_count,
    issueCount = issue_count,
    codeCount = 0,
    discussionCount = 0,
    wikiCount = 0,
  }
end)

-- Webhook handlers: Pagure uses X-Pagure-Event header.
-- All issue and comment events share the same payload envelope:
--   msg.issue   — the Pagure issue object
--   msg.project — the Pagure project (repository)
--   msg.agent   — username of the acting user (plain string)
--   msg.comment — present only for comment events
--
-- Relevant X-Pagure-Event values:
--   issue.new              → issues / opened
--   issue.edit             → issues / edited
--   issue.status.change    → issues / closed | reopened  (derived from issue.status)
--   issue.comment.added    → issue_comment / created
--   pull-request.new       → pull_request / opened
--   pull-request.updated   → pull_request / synchronize
--   pull-request.closed    → pull_request / closed  (status: Merged or Closed)

-- Helper: build a GitHub-shaped user from a Pagure agent string (bare username).
local function pagure_agent_user(agent)
  return translate_pagure_user({ name = agent or "" })
end

-- Translate a Pagure pull request to GitHub format.
local function translate_pagure_pull(pr)
  if not pr then
    return {}
  end
  local status = pr.status or "Open"
  local is_merged = status == "Merged"
  local gh_state = status == "Open" and "open" or "closed"
  local repo_from = pr.repo_from or {}
  return {
    id = pr.id or 0,
    node_id = "",
    number = pr.id or 0,
    state = gh_state,
    locked = false,
    title = pr.title or "",
    body = pr.initial_comment or "",
    user = translate_pagure_user(pr.user),
    head = {
      label = (repo_from.fullname or "") .. ":" .. (pr.branch_from or ""),
      ref = pr.branch_from or "",
      sha = pr.commit_stop or "",
    },
    base = {
      label = "" .. ":" .. (pr.branch or ""),
      ref = pr.branch or "",
      sha = "",
    },
    draft = false,
    created_at = tostring(pr.date_created or ""),
    updated_at = tostring(pr.last_updated or ""),
    closed_at = (not is_merged and gh_state == "closed") and tostring(pr.last_updated or "") or nil,
    merged_at = is_merged and tostring(pr.last_updated or "") or nil,
    merge_commit_sha = nil,
    merged_by = nil,
    html_url = config.base_url .. "/" .. (pr.full_url or ""),
    url = "",
    mergeable = status == "Open" or nil,
    comments = 0,
    review_comments = 0,
    commits = 0,
    additions = 0,
    deletions = 0,
    changed_files = 0,
  }
end

b:webhook("issue.new", function(payload)
  local msg = payload.msg or {}
  return make_internal_event({
    event = "issues",
    action = "opened",
    provider = "pagure",
    raw = payload,
    data = {
      action = "opened",
      issue = translate_pagure_issue(msg.issue),
      repository = translate_pagure_repo(msg.project),
      sender = pagure_agent_user(msg.agent),
    },
    timestamp = tostring((msg.issue or {}).date_created or ""),
  })
end)

b:webhook("issue.edit", function(payload)
  local msg = payload.msg or {}
  return make_internal_event({
    event = "issues",
    action = "edited",
    provider = "pagure",
    raw = payload,
    data = {
      action = "edited",
      issue = translate_pagure_issue(msg.issue),
      repository = translate_pagure_repo(msg.project),
      sender = pagure_agent_user(msg.agent),
    },
    timestamp = tostring((msg.issue or {}).last_updated or ""),
  })
end)

b:webhook("issue.status.change", function(payload)
  local msg = payload.msg or {}
  local issue = msg.issue or {}
  local action = (issue.status == "Open") and "reopened" or "closed"
  return make_internal_event({
    event = "issues",
    action = action,
    provider = "pagure",
    raw = payload,
    data = {
      action = action,
      issue = translate_pagure_issue(issue),
      repository = translate_pagure_repo(msg.project),
      sender = pagure_agent_user(msg.agent),
    },
    timestamp = tostring(issue.last_updated or ""),
  })
end)

b:webhook("issue.comment.added", function(payload)
  local msg = payload.msg or {}
  return make_internal_event({
    event = "issue_comment",
    action = "created",
    provider = "pagure",
    raw = payload,
    data = {
      action = "created",
      issue = translate_pagure_issue(msg.issue),
      comment = translate_pagure_comment(msg.comment),
      repository = translate_pagure_repo(msg.project),
      sender = pagure_agent_user(msg.agent),
    },
    timestamp = tostring((msg.comment or {}).date_created or ""),
  })
end)

b:webhook("pull-request.new", function(payload)
  local msg = payload.msg or {}
  local pr = msg.pullrequest or {}
  return make_internal_event({
    event = "pull_request",
    action = "opened",
    provider = "pagure",
    raw = payload,
    data = {
      action = "opened",
      number = pr.id,
      pull_request = translate_pagure_pull(pr),
      repository = translate_pagure_repo(msg.project),
      sender = pagure_agent_user(msg.agent),
    },
    timestamp = tostring(pr.date_created or ""),
  })
end)

b:webhook("pull-request.updated", function(payload)
  local msg = payload.msg or {}
  local pr = msg.pullrequest or {}
  return make_internal_event({
    event = "pull_request",
    action = "synchronize",
    provider = "pagure",
    raw = payload,
    data = {
      action = "synchronize",
      number = pr.id,
      pull_request = translate_pagure_pull(pr),
      repository = translate_pagure_repo(msg.project),
      sender = pagure_agent_user(msg.agent),
    },
    timestamp = tostring(pr.last_updated or ""),
  })
end)

b:webhook("pull-request.closed", function(payload)
  local msg = payload.msg or {}
  local pr = msg.pullrequest or {}
  return make_internal_event({
    event = "pull_request",
    action = "closed",
    provider = "pagure",
    raw = payload,
    data = {
      action = "closed",
      number = pr.id,
      pull_request = translate_pagure_pull(pr),
      repository = translate_pagure_repo(msg.project),
      sender = pagure_agent_user(msg.agent),
    },
    timestamp = tostring(pr.last_updated or ""),
  })
end)

b:build()
