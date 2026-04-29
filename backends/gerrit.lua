-- Gerrit backend handler overrides.
-- Uses Gerrit REST API at /a/ (authenticated) endpoints.
-- Projects in Gerrit use "/" as separator (e.g. "owner/repo"), URL-encoded as "owner%2Frepo".

local base = function()
  return config.base_url .. "/a"
end
local auth = function()
  return make_fetch_opts("basic")
end
local _t = make_backend_transport("basic")
local fetch_json = _t.fetch_json
local proxy_handler = _t.proxy_handler

local project_id = owner_repo_id

-- Map a Gerrit project object to GitHub format.
local function translate_gerrit_repo(r, owner, repo_name)
  if not r then
    return {}
  end
  local full = r.name or (owner and (owner .. "/" .. (repo_name or "")) or "")
  local o, n = full:match("^(.+)/([^/]+)$")
  if not o then
    o = ""
    n = full
  end
  return {
    id = 0,
    node_id = "",
    name = n,
    full_name = full,
    private = false,
    owner = {
      login = o,
      id = 0,
      node_id = "",
      avatar_url = "",
      url = "",
      html_url = "",
      type = "User",
    },
    html_url = config.base_url .. "/admin/repos/" .. full,
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
    archived = r.state == "READ_ONLY",
    disabled = r.state == "HIDDEN",
    open_issues_count = 0,
    default_branch = "main",
    visibility = "public",
    forks = 0,
    open_issues = 0,
    watchers = 0,
    created_at = nil,
    updated_at = nil,
    pushed_at = nil,
  }
end

-- Gerrit prepends ")]}'\n" (5 chars) to all JSON responses as XSSI protection.
local function gerrit_decode(body)
  if body and body:sub(1, 4) == ")]}'" then
    return DecodeJson(body:sub(6)) or {}
  end
  return DecodeJson(body) or {}
end

-- Map a Gerrit account object to GitHub user format.
local function translate_gerrit_user(u)
  if not u then
    return {}
  end
  return {
    login = u.username or "",
    id = u._account_id or 0,
    node_id = "",
    avatar_url = "",
    html_url = "",
    type = "User",
    site_admin = false,
    name = u.name or "",
    email = u.email or "",
  }
end

-- Gerrit branch: { ref, revision }
local function translate_gerrit_branch(b)
  if not b then
    return {}
  end
  local name = b.ref and b.ref:match("^refs/heads/(.+)") or (b.ref or "")
  return { name = name, commit = { sha = b.revision or "", url = "" }, protected = false }
end

-- Gerrit tag: { ref, revision, object }
local function translate_gerrit_tag(t)
  if not t then
    return {}
  end
  local name = t.ref and t.ref:match("^refs/tags/(.+)") or (t.ref or "")
  return { name = name, commit = { sha = t.revision or t.object or "", url = "" } }
end

-- Gerrit projects endpoints return a dict { project_name → project_info }.
-- This translate function is shared by get_user_repos, get_users_repos, and
-- get_repositories, all of which iterate the same dict shape.
local function gerrit_repos_from_dict(data)
  local repos = {}
  for name, r in pairs(data or {}) do
    r.name = name
    repos[#repos + 1] = translate_gerrit_repo(r)
  end
  return repos
end

local b = make_backend_builder()
b:rest("get_root", function()
  proxy_health_check(pcall(Fetch, config.base_url .. "/config/server/version", auth()))
end)
b:rest(
  "get_repo",
  proxy_handler(translate_gerrit_repo, function(owner, repo_name)
    return base() .. "/projects/" .. project_id(owner, repo_name)
  end)
)

b:rest("patch_repo", function(owner, repo_name)
  local req = DecodeJson(GetBody() or "{}")
  local g = {}
  if req.description then
    g.description = req.description
  end
  proxy_json(
    function(r)
      return translate_gerrit_repo(r, owner, repo_name)
    end,
    fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/config",
      "PUT",
      EncodeJson(g)
    )
  )
end)

-- Gerrit: GET /a/projects/ → dict of project_name → project_info
b:rest("get_user_repos", function()
  local limit = GetParam("per_page") or "30"
  local skip = ((tonumber(GetParam("page")) or 1) - 1) * (tonumber(limit) or 30)
  local url = base() .. "/projects/?n=" .. limit .. (skip > 0 and ("&S=" .. skip) or "")
  proxy_json(gerrit_repos_from_dict, fetch_json(url))
end)

b:rest("get_users_repos", function(username)
  local limit = GetParam("per_page") or "30"
  local skip = ((tonumber(GetParam("page")) or 1) - 1) * (tonumber(limit) or 30)
  local url = base()
    .. "/projects/?p="
    .. username
    .. "%2F&n="
    .. limit
    .. (skip > 0 and ("&S=" .. skip) or "")
  proxy_json(gerrit_repos_from_dict, fetch_json(url))
end)

b:rest("get_repositories", function()
  local limit = GetParam("per_page") or "30"
  local skip = ((tonumber(GetParam("page")) or 1) - 1) * (tonumber(limit) or 30)
  local url = base() .. "/projects/?n=" .. limit .. (skip > 0 and ("&S=" .. skip) or "")
  proxy_json(gerrit_repos_from_dict, fetch_json(url))
end)

-- Branches ------------------------------------------------------------------
-- GET /a/projects/{id}/branches/ → [{ ref, revision }]

b:rest(
  "get_repo_branches",
  proxy_handler(function(branches)
    local result = {}
    for _, br in ipairs(branches or {}) do
      if br.ref and br.ref:match("^refs/heads/") then
        result[#result + 1] = translate_gerrit_branch(br)
      end
    end
    return result
  end, function(owner, repo_name)
    return base() .. "/projects/" .. project_id(owner, repo_name) .. "/branches/"
  end)
)

b:rest(
  "get_repo_branch",
  proxy_handler(translate_gerrit_branch, function(owner, repo_name, branch)
    return base()
      .. "/projects/"
      .. project_id(owner, repo_name)
      .. "/branches/refs%2Fheads%2F"
      .. branch
  end)
)

-- Tags ----------------------------------------------------------------------
-- GET /a/projects/{id}/tags/ → [{ ref, revision, object }]

b:rest(
  "get_repo_tags",
  proxy_handler(function(tags)
    return translate_list(translate_gerrit_tag, tags)
  end, function(owner, repo_name)
    return base() .. "/projects/" .. project_id(owner, repo_name) .. "/tags/"
  end)
)

-- Commits -------------------------------------------------------------------
-- Gerrit: GET /a/projects/{id}/commits/{sha}

b:rest(
  "get_repo_commit",
  proxy_handler(function(c)
    if not c then
      return {}
    end
    local author = c.author or {}
    local committer = c.committer or {}
    return {
      sha = c.commit or "",
      commit = {
        message = c.message or "",
        author = { name = author.name or "", email = author.email or "", date = author.date or "" },
        committer = {
          name = committer.name or "",
          email = committer.email or "",
          date = committer.date or "",
        },
      },
    }
  end, function(owner, repo_name, ref)
    return base() .. "/projects/" .. project_id(owner, repo_name) .. "/commits/" .. ref
  end)
)

-- Users ---------------------------------------------------------------------
-- These handlers cannot use proxy_json: Gerrit prefixes every JSON response
-- with ")]}'\n" to prevent XSS cross-domain reads.  gerrit_decode strips that
-- prefix before passing the body to DecodeJson.

-- GET /user — authenticated user
b:rest("get_user", function()
  local ok, status, _, body = fetch_json(base() .. "/accounts/self?o=DETAILS")
  if ok and status == 200 then
    respond_json(200, translate_gerrit_user(gerrit_decode(body)))
  elseif ok then
    respond_json(status, {})
  else
    respond_json(503, {})
  end
end)

-- GET /users/{username}
b:rest("get_users_username", function(username)
  local ok, status, _, body = fetch_json(base() .. "/accounts/" .. username .. "?o=DETAILS")
  if ok and status == 200 then
    respond_json(200, translate_gerrit_user(gerrit_decode(body)))
  elseif ok then
    respond_json(status, {})
  else
    respond_json(503, {})
  end
end)

-- GET /users — search active accounts
b:rest("get_users", function()
  local limit = GetParam("per_page") or "30"
  local page = tonumber(GetParam("page")) or 1
  local skip = (page - 1) * (tonumber(limit) or 30)
  local url = base()
    .. "/accounts/?q=is:active&o=DETAILS&n="
    .. limit
    .. (skip > 0 and ("&S=" .. skip) or "")
  local ok, status, _, body = fetch_json(url)
  if ok and status == 200 then
    respond_json(200, translate_list(translate_gerrit_user, gerrit_decode(body)))
  elseif ok then
    respond_json(status, {})
  else
    respond_json(503, {})
  end
end)

-- Issues -----------------------------------------------------------------------
-- Gerrit has no native issue tracker; it is a code-review system only.
-- All issues, labels, milestones, and assignees endpoints fall back to the
-- default empty-list / 404 handlers defined in .init.lua.

-- Contents ------------------------------------------------------------------
-- Cannot use proxy_json: Gerrit returns the raw base64-encoded file bytes
-- directly (no JSON envelope), so DecodeJson is not applicable.

b:rest("get_repo_content", function(owner, repo_name, path)
  local ref = GetParam("ref") or "HEAD"
  local url = base()
    .. "/projects/"
    .. project_id(owner, repo_name)
    .. "/branches/"
    .. ref
    .. "/files/"
    .. path
    .. "/content"
  local ok, status, _, body = fetch_json(url)
  if ok and status == 200 then
    -- Gerrit returns already-base64-encoded content
    respond_json(200, {
      type = "file",
      name = path:match("[^/]+$") or path,
      path = path,
      sha = "",
      size = 0,
      encoding = "base64",
      content = body,
    })
  elseif ok then
    respond_json(status, { message = "Error" })
  else
    respond_json(503, {})
  end
end)

-- Webhook handlers -----------------------------------------------------------
-- Gerrit emits `comment-added` events when a reviewer adds a comment with an
-- approval score.  The `approvals` array contains entries like:
--   { type = "Code-Review", value = "+2", oldValue = "-1" }
--
-- Code-Review score → GitHub state mapping:
--   +2  Approved              → submitted / APPROVED
--   +1  Looks good to me      → submitted / APPROVED
--    0  No score              → submitted / COMMENTED
--   -1  I would prefer this   → submitted / CHANGES_REQUESTED
--   -2  Do not submit         → submitted / CHANGES_REQUESTED

local function gerrit_approval_state(approvals)
  local state = "COMMENTED"
  for _, a in ipairs(approvals or {}) do
    local v = tonumber(a.value) or 0
    if v >= 1 then
      state = "APPROVED"
      break
    elseif v <= -1 then
      state = "CHANGES_REQUESTED"
      break
    end
  end
  return state
end

local function translate_gerrit_change(change, patchSet)
  change = change or {}
  patchSet = patchSet or {}
  local full = change.project or ""
  local o, n = full:match("^(.+)/([^/]+)$")
  if not o then
    o = ""
    n = full
  end
  local repo = {
    id = 0,
    node_id = "",
    name = n,
    full_name = full,
    private = false,
    owner = {
      login = o,
      id = 0,
      node_id = "",
      avatar_url = "",
      url = "",
      html_url = "",
      type = "User",
    },
    html_url = config.base_url .. "/admin/repos/" .. full,
    description = nil,
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
    default_branch = change.branch or "main",
    visibility = "public",
    forks = 0,
    open_issues = 0,
    watchers = 0,
    created_at = nil,
    updated_at = nil,
    pushed_at = nil,
  }
  local pr = {
    id = change._number or 0,
    node_id = "",
    number = change._number or 0,
    title = change.subject or "",
    body = "",
    state = "open",
    draft = change.wip or false,
    html_url = config.base_url .. "/c/" .. full .. "/+/" .. (change._number or ""),
    url = "",
    user = translate_gerrit_user(change.owner),
    head = {
      ref = change.branch or "",
      sha = patchSet.revision or "",
      repo = nil,
    },
    base = {
      ref = change.branch or "",
      sha = "",
      repo = nil,
    },
    created_at = change.created or "",
    updated_at = change.updated or "",
    closed_at = nil,
  }
  return pr, repo
end

b:webhook("comment-added", function(payload)
  local approvals = payload.approvals or {}
  local state = gerrit_approval_state(approvals)
  local author = payload.author or {}
  local pr, repo = translate_gerrit_change(payload.change, payload.patchSet)
  local review = {
    id = 0,
    node_id = "",
    user = translate_gerrit_user(author),
    body = payload.comment or "",
    state = state,
    submitted_at = (payload.patchSet or {}).createdOn and tostring(
      (payload.patchSet or {}).createdOn
    ) or "",
    html_url = "",
    pull_request_url = "",
  }
  return make_internal_event({
    event = "pull_request_review",
    action = "submitted",
    provider = "gerrit",
    raw = payload,
    data = {
      action = "submitted",
      review = review,
      pull_request = pr,
      repository = repo,
      sender = translate_gerrit_user(author),
    },
    timestamp = review.submitted_at,
  })
end)

local GERRIT_NORMALIZED_WEBHOOK_EVENTS = {
  "pull_request_review",
}

local function gerrit_normalized_payload_without_envelope_fields(data)
  local payload = {}
  for k, v in pairs(data or {}) do
    if k ~= "sender" and k ~= "repository" then
      payload[k] = v
    end
  end
  return payload
end

local function translate_gerrit_normalized_webhook(internal_event, fields)
  local data = internal_event.data or {}
  fields = fields or {}
  return make_normalized_webhook_envelope(internal_event, {
    id = fields.id,
    type = fields.type
      or normalized_webhook_event_type(internal_event.event, internal_event.action),
    occurred_at = fields.occurred_at,
    actor = fields.actor or data.sender,
    repository = fields.repository or data.repository,
    payload = fields.payload or gerrit_normalized_payload_without_envelope_fields(data),
  })
end

for _, event in ipairs(GERRIT_NORMALIZED_WEBHOOK_EVENTS) do
  b:webhook_translator(event, translate_gerrit_normalized_webhook)
end

b:build()
