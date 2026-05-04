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

local function pagure_ts(v)
  if not v then
    return ""
  end
  return tostring(v)
end

local function pagure_repo_owner_login(r)
  local user = r.user or {}
  local ns = r.namespace or ""
  return ns ~= "" and ns or user.name or ""
end

local translate_pagure_repo_owner = make_translator({
  login = computed(function(_user, repo)
    return pagure_repo_owner_login(repo or {})
  end),
  id = const(0),
  node_id = const(""),
  avatar_url = const(""),
  url = const(""),
  html_url = computed(function(user)
    return config.base_url .. "/" .. (user.url_path or user.name or "")
  end),
  type = computed(function(_user, repo)
    return (repo and repo.namespace or "") ~= "" and "Organization" or "User"
  end),
})

-- Map a Pagure project object to GitHub repo format.
local translate_pagure_repo = make_translator({
  id = field("id", { default = 0 }),
  node_id = const(""),
  name = "name",
  full_name = computed(function(r)
    return r.fullname or (pagure_repo_owner_login(r) .. "/" .. (r.name or ""))
  end),
  private = field("private", { default = false }),
  owner = computed(function(r)
    return translate_pagure_repo_owner(r.user or {}, r)
  end),
  html_url = computed(function(r)
    return config.base_url .. "/" .. (r.url_path or "")
  end),
  description = "description",
  fork = computed(function(r)
    return r.parent ~= nil
  end),
  url = const(""),
  clone_url = field("full_url", { default = "" }),
  homepage = field("url", { default = "" }),
  size = const(0),
  stargazers_count = field("stars", { default = 0 }),
  watchers_count = const(0),
  language = const(nil),
  has_issues = const(true),
  has_wiki = computed(function(r)
    return r.settings and r.settings.wiki_enabled or false
  end),
  forks_count = field("forks_count", { default = 0 }),
  archived = computed(function(r)
    return r.close_status ~= nil and r.close_status ~= ""
  end),
  disabled = const(false),
  open_issues_count = const(0),
  default_branch = field("default_branch", { default = "main" }),
  visibility = computed(function(r)
    return (r.private or false) and "private" or "public"
  end),
  forks = field("forks_count", { default = 0 }),
  open_issues = const(0),
  watchers = const(0),
  created_at = "date_created",
  updated_at = "date_modified",
  pushed_at = "date_modified",
})

-- Translate a Pagure branch name to GitHub format.
-- Pagure branch list returns only names, no commit SHAs.
local translate_pagure_branch = make_translator({
  name = computed(function(name)
    return name
  end),
  commit = const({ sha = "", url = "" }),
  protected = const(false),
})

-- Translate a Pagure commit object to GitHub format.
-- Pagure: { id, message, date, date_utc, author: { name, email } }

-- Translate a Pagure user to GitHub format.
local translate_pagure_user = make_translator({
  login = computed(function(u)
    return u.name or u.username or ""
  end),
  id = const(0),
  node_id = const(""),
  avatar_url = field("avatar_url", { default = "" }),
  html_url = computed(function(u)
    return config.base_url .. "/" .. (u.url_path or u.name or "")
  end),
  type = const("User"),
  site_admin = const(false),
  name = computed(function(u)
    return u.fullname or u.name or ""
  end),
})

-- Translate a Pagure issue tag (string) to a GitHub label object.
local translate_pagure_tag = make_translator({
  id = const(0),
  node_id = const(""),
  url = const(""),
  name = computed(function(tag)
    return tag or ""
  end),
  color = const(""),
  description = const(""),
  default = const(false),
})

local translate_pagure_milestone_spec = make_translator({
  id = field("id", { default = 0 }),
  node_id = const(""),
  number = field("id", { default = 0 }),
  title = computed(function(milestone)
    return milestone.title or milestone.name or ""
  end),
  description = field("description", { default = "" }),
  state = computed(function(milestone)
    return (milestone.closed or milestone.status == "Closed") and "closed" or "open"
  end),
  created_at = computed(function(milestone)
    return tostring(milestone.date_created or milestone.created_at or "")
  end),
  updated_at = computed(function(milestone)
    return tostring(milestone.last_updated or milestone.updated_at or "")
  end),
  due_on = computed(function(milestone)
    return milestone.due_on or milestone.date_due
  end),
  closed_at = computed(function(milestone)
    return milestone.closed_at or milestone.date_closed
  end),
}, { nil_returns_nil = true })

local function translate_pagure_milestone(milestone)
  if milestone == "" then
    return nil
  end
  if type(milestone) ~= "table" and milestone ~= nil then
    milestone = { title = tostring(milestone) }
  end
  return translate_pagure_milestone_spec(milestone)
end

-- Translate a Pagure issue to GitHub format.
-- Pagure states: "Open", "Closed"
-- Pagure dates: Unix timestamps as strings
local translate_pagure_issue = make_translator({
  id = field("id", { default = 0 }),
  number = field("id", { default = 0 }),
  title = field("title", { default = "" }),
  body = field("content", { default = "" }),
  state = computed(function(i)
    return (i.status == "Open") and "open" or "closed"
  end),
  user = nested(translate_pagure_user, "user"),
  assignees = computed(function(i)
    if i.assignee then
      return { translate_pagure_user(i.assignee) }
    end
    return {}
  end),
  labels = each(translate_pagure_tag, "tags"),
  created_at = field("date_created", { transform = pagure_ts }),
  updated_at = field("last_updated", { transform = pagure_ts }),
  closed_at = computed(function(i)
    if i.status == "Open" then
      return nil
    end
    return pagure_ts(i.closed_at or i.date_closed or i.closed_date or i.closed_on or i.last_updated)
  end),
  html_url = computed(function(i)
    return config.base_url .. "/" .. (i.full_url or "")
  end),
  milestone = computed(function(i)
    return translate_pagure_milestone(i.milestone)
  end),
})

-- Translate a Pagure comment to GitHub format.
local translate_pagure_comment = make_translator({
  id = field("id", { default = 0 }),
  body = field("comment", { default = "" }),
  user = nested(translate_pagure_user, "user"),
  created_at = computed(function(c)
    return tostring(c.date_created or "")
  end),
  updated_at = computed(function(c)
    return tostring(c.last_updated or c.date_updated or c.date_created or "")
  end),
  html_url = computed(function(c, issue)
    local html_url = c.full_url and (config.base_url .. "/" .. c.full_url) or ""
    if html_url == "" and issue and issue.full_url and c.id then
      html_url = config.base_url .. "/" .. issue.full_url .. "#comment-" .. c.id
    end
    return html_url
  end),
})

local translate_pagure_commit_actor = make_translator({
  login = field("name", { default = "" }),
  id = const(0),
  avatar_url = const(""),
})

local translate_pagure_commit_signature = make_translator({
  name = field("name", { default = "" }),
  email = field("email", { default = "" }),
  date = computed(function(_author, commit)
    return commit.date_utc or ""
  end),
})

local translate_pagure_commit_body = make_translator({
  message = field("message", { default = "" }),
  author = computed(function(c)
    return translate_pagure_commit_signature(c.author or {}, c)
  end),
  committer = computed(function(c)
    return translate_pagure_commit_signature(c.author or {}, c)
  end),
})

local translate_pagure_commit = make_translator({
  sha = field("id", { default = "" }),
  commit = computed(function(c)
    return translate_pagure_commit_body(c)
  end),
  author = computed(function(c)
    return translate_pagure_commit_actor(c.author or {})
  end),
  committer = computed(function(c)
    return translate_pagure_commit_actor(c.author or {})
  end),
})

local function pagure_issues(data)
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
  proxy_handler(pagure_issues, function(o, r)
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

local function pagure_pull_status(pr)
  return pr.status or "Open"
end

local translate_pagure_pull_head = make_translator({
  label = computed(function(pr)
    local repo_from = pr.repo_from or {}
    return (repo_from.fullname or "") .. ":" .. (pr.branch_from or "")
  end),
  ref = field("branch_from", { default = "" }),
  sha = field("commit_stop", { default = "" }),
  repo = computed(function(pr)
    return translate_pagure_repo(pr.repo_from or {})
  end),
})

local translate_pagure_pull_base = make_translator({
  label = computed(function(pr, project)
    return (project and project.fullname or "") .. ":" .. (pr.branch or "")
  end),
  ref = field("branch", { default = "" }),
  sha = field("commit_start", { default = "" }),
  repo = computed(function(_pr, project)
    return translate_pagure_repo(project)
  end),
})

-- Translate a Pagure pull request to GitHub format.
local translate_pagure_pull = make_translator({
  id = field("id", { default = 0 }),
  node_id = const(""),
  number = field("id", { default = 0 }),
  state = computed(function(pr)
    return pagure_pull_status(pr) == "Open" and "open" or "closed"
  end),
  locked = const(false),
  title = field("title", { default = "" }),
  body = field("initial_comment", { default = "" }),
  user = nested(translate_pagure_user, "user"),
  head = computed(function(pr)
    return translate_pagure_pull_head(pr)
  end),
  base = computed(function(pr, project)
    return translate_pagure_pull_base(pr, project)
  end),
  draft = const(false),
  created_at = computed(function(pr)
    return tostring(pr.date_created or "")
  end),
  updated_at = computed(function(pr)
    return tostring(pr.last_updated or "")
  end),
  closed_at = computed(function(pr)
    local status = pagure_pull_status(pr)
    if status ~= "Open" and status ~= "Merged" then
      return tostring(pr.last_updated or "")
    end
    return nil
  end),
  merged_at = computed(function(pr)
    return pagure_pull_status(pr) == "Merged" and tostring(pr.last_updated or "") or nil
  end),
  merge_commit_sha = computed(function(pr)
    return pagure_pull_status(pr) == "Merged" and (pr.commit_stop or nil) or nil
  end),
  merged = computed(function(pr)
    return pagure_pull_status(pr) == "Merged"
  end),
  merged_by = computed(function(pr, _project, actor)
    return pagure_pull_status(pr) == "Merged"
        and pagure_agent_user(pr.closed_by or pr.merged_by or actor)
      or nil
  end),
  html_url = computed(function(pr)
    return config.base_url .. "/" .. (pr.full_url or "")
  end),
  url = const(""),
  mergeable = computed(function(pr)
    return pagure_pull_status(pr) == "Open" or nil
  end),
  comments = const(0),
  review_comments = const(0),
  commits = const(0),
  additions = const(0),
  deletions = const(0),
  changed_files = const(0),
})

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
      comment = translate_pagure_comment(msg.comment, msg.issue),
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
      pull_request = translate_pagure_pull(pr, msg.project, msg.agent),
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
      pull_request = translate_pagure_pull(pr, msg.project, msg.agent),
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
      pull_request = translate_pagure_pull(pr, msg.project, msg.agent),
      repository = translate_pagure_repo(msg.project),
      sender = pagure_agent_user(msg.agent),
    },
    timestamp = tostring(pr.last_updated or ""),
  })
end)

-- git.receive: fires for all branch/tag ref updates (push, create, delete).
-- Pagure does not emit discrete create/delete events; confusio splits them by
-- inspecting start_commit / end_commit for all-zero SHA patterns.
-- msg fields: agent, repo (project), branch (full ref), start_commit (before),
-- end_commit (after), forced, total_commits, commits (array)
local PAGURE_ZERO_SHA = "0000000000000000000000000000000000000000"
b:webhook("git.receive", function(payload)
  local msg = payload.msg or {}
  local repo = msg.repo or msg.project or {}
  local actor = msg.agent or ""
  local sender = pagure_agent_user(actor)
  local repository = translate_pagure_repo(repo)
  local branch = msg.branch or ""
  local before = msg.start_commit or PAGURE_ZERO_SHA
  local after = msg.end_commit or PAGURE_ZERO_SHA

  -- Derive ref_type from branch path; short name strips prefix.
  local ref_type = branch:match("^refs/tags/") and "tag" or "branch"
  local ref_short = branch:match("^refs/[^/]+/(.+)") or branch

  if before == PAGURE_ZERO_SHA then
    -- Branch or tag created — emit GitHub create event.
    return make_internal_event({
      event = "create",
      action = "create",
      provider = "pagure",
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
      timestamp = "",
    })
  end

  if after == PAGURE_ZERO_SHA then
    -- Branch or tag deleted — emit GitHub delete event.
    return make_internal_event({
      event = "delete",
      action = "delete",
      provider = "pagure",
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
      timestamp = "",
    })
  end

  -- Regular push — emit GitHub push event.
  local push_commits = {}
  for _, c in ipairs(msg.commits or {}) do
    push_commits[#push_commits + 1] = translate_pagure_commit(c)
  end
  local head_commit = #push_commits > 0 and push_commits[1] or nil
  return make_internal_event({
    event = "push",
    action = "push",
    provider = "pagure",
    raw = payload,
    data = {
      ref = branch,
      before = before,
      after = after,
      created = false,
      deleted = false,
      forced = msg.forced or false,
      compare = "",
      commits = push_commits,
      head_commit = head_commit,
      pusher = { name = actor, email = "" },
      repository = repository,
      sender = sender,
    },
    timestamp = ((msg.commits or {})[1] or {}).date_utc or "",
  })
end)

-- project.forked: fires when a user forks a repository.
-- msg fields: agent, project (the upstream), fork (the new fork)
b:webhook("project.forked", function(payload)
  local msg = payload.msg or {}
  return make_internal_event({
    event = "fork",
    action = "fork",
    provider = "pagure",
    raw = payload,
    data = {
      forkee = translate_pagure_repo(msg.fork or {}),
      repository = translate_pagure_repo(msg.project or {}),
      sender = pagure_agent_user(msg.agent),
    },
    timestamp = "",
  })
end)

local PAGURE_ACTIONLESS_NORMALIZED_EVENTS = {
  create = true,
  delete = true,
  fork = true,
  push = true,
}

local PAGURE_NORMALIZED_WEBHOOK_EVENTS = {
  "issues",
  "issue_comment",
  "pull_request",
  "push",
  "create",
  "delete",
  "fork",
}

local function pagure_normalized_payload_without_envelope_fields(data)
  local payload = {}
  for k, v in pairs(data or {}) do
    if k ~= "sender" and k ~= "repository" then
      payload[k] = v
    end
  end
  return payload
end

local function translate_pagure_normalized_webhook(internal_event, fields)
  local data = internal_event.data or {}
  fields = fields or {}
  return make_normalized_webhook_envelope(internal_event, {
    id = fields.id,
    type = fields.type
      or (
        PAGURE_ACTIONLESS_NORMALIZED_EVENTS[internal_event.event]
          and normalized_webhook_event_type(internal_event.event, "")
        or normalized_webhook_event_type(internal_event.event, internal_event.action)
      ),
    occurred_at = fields.occurred_at,
    actor = fields.actor or data.sender,
    repository = fields.repository or data.repository,
    payload = fields.payload or pagure_normalized_payload_without_envelope_fields(data),
  })
end

local function translate_pagure_github_webhook(internal_event, fields)
  return github_webhook_payload(internal_event, fields)
end

for _, event in ipairs(PAGURE_NORMALIZED_WEBHOOK_EVENTS) do
  b:webhook_translator(event, translate_pagure_normalized_webhook)
  b:webhook_github_translator(event, translate_pagure_github_webhook)
end

b:build()
