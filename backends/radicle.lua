-- Radicle backend handler overrides.
-- Uses Radicle HTTP API at /api/v1/.
-- Radicle repos are identified by their RID (Radicle ID), e.g. rad:z3gqcJUoA1n9HaHKufZs1.
-- GitHub {owner}/{repo} maps to: owner = node DID (ignored), repo = RID.
if config.base_url == "" then
  config.base_url = "http://127.0.0.1:8080"
end

local base = function()
  return config.base_url .. "/api/v1"
end
local auth = function()
  return make_fetch_opts("bearer")
end
local PAGES = { per_page = "perPage", page = "page" }
local fetch_json = with_pagination(PAGES, with_auth("bearer", base_transport)).fetch_json
local ZERO_SHA = "0000000000000000000000000000000000000000"

local function radicle_short_ref(ref)
  return (ref or ""):match("^refs/[^/]+/(.+)") or (ref or "")
end

local function radicle_ref_type(ref)
  return (ref or ""):match("^refs/tags/") and "tag" or "branch"
end

local function translate_radicle_user(u)
  u = u or {}
  local id = u.id or u.did or ""
  local login = u.alias or u.username or u.login or u.name or id
  return {
    login = login or "",
    id = 0,
    node_id = id,
    avatar_url = u.avatar_url or "",
    url = "",
    html_url = u.html_url or "",
    type = "User",
    site_admin = false,
    name = u.name,
    email = u.email,
  }
end

-- Map a Radicle repository object to GitHub format.
local function translate_radicle_repo(r)
  if not r then
    return {}
  end
  -- Radicle project payload is under payloads["xyz.radicle.project"]
  local proj = (r.payloads and r.payloads["xyz.radicle.project"])
    or {
      name = r.name,
      description = r.description,
      defaultBranch = r.defaultBranch or r.default_branch,
    }
  local delegates = r.delegates or {}
  local owner = r.owner or {}
  local owner_did = owner.id or owner.did or (delegates[1] and delegates[1].id) or ""
  -- DID looks like "did:key:z6Mk..."; extract the key part as login
  local login = owner.alias or owner.login or owner_did:match("did:key:(.+)$") or owner_did
  return {
    id = 0,
    node_id = r.rid or "",
    name = proj.name or r.rid or "",
    full_name = (login ~= "" and (login .. "/") or "") .. (proj.name or r.rid or ""),
    private = r.private or false,
    owner = {
      login = login,
      id = 0,
      node_id = owner_did,
      avatar_url = "",
      url = "",
      html_url = "",
      type = "User",
    },
    html_url = r.web_url or (config.base_url .. "/repos/" .. (r.rid or "")),
    description = proj.description,
    fork = false,
    url = "",
    clone_url = r.clone_url or (r.rid and ("rad://" .. r.rid) or ""),
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
    default_branch = proj.defaultBranch or "main",
    visibility = (r.private or false) and "private" or "public",
    forks = 0,
    open_issues = 0,
    watchers = 0,
    created_at = nil,
    updated_at = nil,
    pushed_at = nil,
  }
end

-- Translate GitHub create request body to Radicle format.
local function translate_radicle_req(body_str)
  local req = DecodeJson(body_str or "{}")
  local r = {}
  if req.name then
    r.name = req.name
  end
  if req.description then
    r.description = req.description
  end
  if req.private ~= nil then
    r.private = req.private
  end
  if req.default_branch then
    r.defaultBranch = req.default_branch
  end
  return EncodeJson(r)
end

local function translate_radicle_repos(repos)
  return translate_list(translate_radicle_repo, repos)
end

local function translate_radicle_commit(c)
  c = c or {}
  local author = c.author or {}
  local committer = c.committer or author
  return {
    id = c.id or "",
    tree_id = c.tree_id or "",
    distinct = c.distinct ~= false,
    message = c.message or "",
    timestamp = c.timestamp or "",
    url = c.url or "",
    author = {
      name = author.name or "",
      email = author.email or "",
      username = author.username or author.alias or author.name or "",
    },
    committer = {
      name = committer.name or author.name or "",
      email = committer.email or author.email or "",
      username = committer.username or committer.alias or committer.name or author.name or "",
    },
  }
end

local function translate_radicle_commits(commits)
  local result = {}
  for _, commit in ipairs(commits or {}) do
    result[#result + 1] = translate_radicle_commit(commit)
  end
  return result
end

local function radicle_ref_event(payload)
  payload = payload or {}
  local before = payload.before or ZERO_SHA
  local after = payload.after or ZERO_SHA
  local ref = payload.ref
    or (payload.tag and ("refs/tags/" .. payload.tag))
    or (payload.branch and ("refs/heads/" .. payload.branch))
    or ""
  local repository = translate_radicle_repo(payload.repository or {})
  local sender = translate_radicle_user(payload.pusher or payload.sender)
  local ref_type = radicle_ref_type(ref)
  local ref_short = radicle_short_ref(ref)

  if before == ZERO_SHA then
    return make_internal_event({
      event = "create",
      action = "create",
      provider = "radicle",
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
      timestamp = payload.occurred_at or "",
    })
  end

  if after == ZERO_SHA then
    return make_internal_event({
      event = "delete",
      action = "delete",
      provider = "radicle",
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
      timestamp = payload.occurred_at or "",
    })
  end

  local commits = translate_radicle_commits(payload.commits)
  return make_internal_event({
    event = "push",
    action = "push",
    provider = "radicle",
    raw = payload,
    data = {
      ref = ref,
      before = before,
      after = after,
      created = false,
      deleted = false,
      forced = payload.forced or false,
      compare = payload.compare or "",
      commits = commits,
      head_commit = commits[#commits],
      pusher = {
        name = (payload.pusher or {}).name or (payload.pusher or {}).alias or "",
        email = (payload.pusher or {}).email or "",
      },
      repository = repository,
      sender = sender,
    },
    timestamp = payload.occurred_at or "",
  })
end

local RADICLE_PATCH_ACTIONS = {
  created = "opened",
  updated = "synchronize",
}

local function translate_radicle_patch(payload)
  payload = payload or {}
  local patch = payload.patch or {}
  local repository = translate_radicle_repo(payload.repository or {})
  local author = translate_radicle_user(patch.author or payload.sender)
  local number = tonumber(patch.number) or 0
  return {
    id = number,
    node_id = patch.id or "",
    number = number,
    title = patch.title or "",
    body = patch.description or "",
    state = patch.state or "open",
    draft = false,
    html_url = patch.url or "",
    url = patch.url or "",
    user = author,
    head = {
      ref = patch.head_ref or ("patch/" .. tostring(number)),
      sha = patch.head or "",
      repo = repository,
    },
    base = {
      ref = patch.target_branch or repository.default_branch or "",
      sha = patch.base or "",
      repo = repository,
    },
    created_at = patch.created_at or "",
    updated_at = patch.updated_at or "",
    closed_at = patch.closed_at,
    merged = false,
    merged_at = nil,
  }
end

local function radicle_patch_event(payload)
  payload = payload or {}
  local raw_action = payload.action or ""
  local action = RADICLE_PATCH_ACTIONS[raw_action]
  local pr = translate_radicle_patch(payload)
  return make_internal_event({
    event = "pull_request",
    action = action or "unknown",
    raw_action = action and nil or raw_action,
    provider = "radicle",
    raw = payload,
    data = {
      action = action or "unknown",
      number = pr.number,
      pull_request = pr,
      repository = translate_radicle_repo(payload.repository or {}),
      sender = translate_radicle_user(payload.sender or (payload.patch or {}).author),
      revisions = (payload.patch or {}).revisions,
    },
    timestamp = payload.occurred_at or pr.updated_at or pr.created_at or "",
  })
end

local RADICLE_ACTIONLESS_NORMALIZED_EVENTS = {
  create = true,
  delete = true,
  push = true,
}

local function radicle_normalized_payload_without_envelope_fields(data)
  local payload = {}
  for k, v in pairs(data or {}) do
    if k ~= "sender" and k ~= "repository" then
      payload[k] = v
    end
  end
  return payload
end

local function translate_radicle_normalized_webhook(internal_event, fields)
  local data = internal_event.data or {}
  fields = fields or {}
  return make_normalized_webhook_envelope(internal_event, {
    id = fields.id,
    type = fields.type
      or (
        RADICLE_ACTIONLESS_NORMALIZED_EVENTS[internal_event.event]
          and normalized_webhook_event_type(internal_event.event, "")
        or normalized_webhook_event_type(internal_event.event, internal_event.action)
      ),
    occurred_at = fields.occurred_at,
    actor = fields.actor or data.sender,
    repository = fields.repository or data.repository,
    payload = fields.payload or radicle_normalized_payload_without_envelope_fields(data),
  })
end

local function translate_radicle_github_webhook(internal_event, fields)
  return github_webhook_payload(internal_event, fields)
end

local b = make_backend_builder()
b:rest("get_root", function()
  proxy_health_check(pcall(Fetch, base(), auth()))
end)

-- GET /repos/{owner}/{rid} — owner is ignored; repo = RID
b:rest("get_repo", function(_, rid)
  proxy_json(translate_radicle_repo, fetch_json(base() .. "/repos/" .. rid))
end)

b:rest("patch_repo", function(_, rid)
  proxy_json(
    translate_radicle_repo,
    fetch_json(base() .. "/repos/" .. rid, "PATCH", translate_radicle_req(GetBody()))
  )
end)

-- Radicle has no delete endpoint
b:rest("delete_repo", function()
  respond_json(
    405,
    "Method Not Allowed",
    { message = "Radicle does not support repository deletion" }
  )
end)

b:rest("get_user_repos", function()
  -- Radicle: list repos seeded/hosted locally
  proxy_json(
    translate_radicle_repos,
    fetch_json(append_page_params(base() .. "/repos?show=local", PAGES))
  )
end)

b:rest("post_user_repos", function()
  proxy_json_created(
    translate_radicle_repo,
    fetch_json(base() .. "/repos", "POST", translate_radicle_req(GetBody()))
  )
end)

b:rest("get_repo_tags", function(_, rid)
  -- Radicle returns [{ name, oid }] or [{ ref, oid }]
  proxy_json(function(tags)
    tags = tags or {}
    local result = {}
    for _, t in ipairs(tags) do
      result[#result + 1] = {
        name = t.name or t.ref or "",
        commit = { sha = t.oid or t.target or "", url = "" },
      }
    end
    return result
  end, fetch_json(base() .. "/repos/" .. rid .. "/tags"))
end)

-- Branches ------------------------------------------------------------------
-- Radicle: GET /api/v1/repos/{rid}/branches → [{ name, head }]

b:rest("get_repo_branches", function(_, rid)
  proxy_json(function(branches)
    branches = branches or {}
    local result = {}
    for _, br in ipairs(branches) do
      result[#result + 1] = {
        name = br.name or "",
        commit = { sha = br.head or "", url = "" },
        protected = false,
      }
    end
    return result
  end, fetch_json(base() .. "/repos/" .. rid .. "/branches"))
end)

b:rest("get_repo_branch", function(_, rid, branch)
  -- Fetch all branches and find the named one.
  proxy_json(function(branches)
    for _, br in ipairs(branches or {}) do
      if br.name == branch then
        return { name = br.name, commit = { sha = br.head or "", url = "" }, protected = false }
      end
    end
    return {}
  end, fetch_json(base() .. "/repos/" .. rid .. "/branches"))
end)

-- Commits -------------------------------------------------------------------
-- Radicle: GET /api/v1/repos/{rid}/commits?branch={branch}

b:rest("get_repo_commits", function(_, rid)
  local branch = GetParam("sha") or ""
  local url = base() .. "/repos/" .. rid .. "/commits"
  if branch ~= "" then
    url = url .. "?branch=" .. branch
  end
  proxy_json(function(commits)
    commits = commits or {}
    local result = {}
    for _, c in ipairs(commits) do
      local author = c.author or {}
      result[#result + 1] = {
        sha = c.id or "",
        commit = {
          message = c.message or "",
          author = { name = author.name or "", email = author.email or "", date = "" },
          committer = { name = author.name or "", email = author.email or "", date = "" },
        },
        author = { login = author.name or "", id = 0, avatar_url = "" },
        committer = { login = author.name or "", id = 0, avatar_url = "" },
      }
    end
    return result
  end, fetch_json(url))
end)

b:rest("get_repo_commit", function(_, rid, ref)
  proxy_json(function(c)
    if not c then
      return {}
    end
    local author = c.author or {}
    return {
      sha = c.id or "",
      commit = {
        message = c.message or "",
        author = { name = author.name or "", email = author.email or "", date = "" },
        committer = { name = author.name or "", email = author.email or "", date = "" },
      },
    }
  end, fetch_json(base() .. "/repos/" .. rid .. "/commits/" .. ref))
end)

-- Issues -----------------------------------------------------------------------
-- Radicle has a decentralized issues system (rad issue) but it uses a
-- peer-to-peer protocol not compatible with the GitHub Issues REST API shape.
-- All issues, labels, milestones, and assignees endpoints fall back to the
-- default empty-list / 404 handlers defined in .init.lua.

-- Contents ------------------------------------------------------------------
-- Radicle: GET /api/v1/repos/{rid}/blob/{commit}/{path} — raw bytes

b:rest("get_repo_readme", function(_, rid)
  local ref = GetParam("ref") or "HEAD"
  local candidates = { "README.md", "README", "readme.md", "README.rst" }
  for _, fname in ipairs(candidates) do
    local ok, status, _, body =
      fetch_json(base() .. "/repos/" .. rid .. "/blob/" .. ref .. "/" .. fname)
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

b:rest("get_repo_content", function(_, rid, path)
  local ref = GetParam("ref") or "HEAD"
  local ok, status, _, body =
    fetch_json(base() .. "/repos/" .. rid .. "/blob/" .. ref .. "/" .. path)
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

-- Users' repos --------------------------------------------------------------

b:rest("get_users_repos", function(username)
  -- Radicle: list repos seeded by a specific node/delegate
  proxy_json(
    translate_radicle_repos,
    fetch_json(append_page_params(base() .. "/repos?show=all&delegate=" .. username, PAGES))
  )
end)

b:rest("get_repositories", function()
  proxy_json(
    translate_radicle_repos,
    fetch_json(append_page_params(base() .. "/repos?show=all", PAGES))
  )
end)

b:webhook("push", radicle_ref_event)
b:webhook("patch", radicle_patch_event)

for _, event in ipairs({ "push", "create", "delete", "pull_request" }) do
  b:webhook_translator(event, translate_radicle_normalized_webhook)
  b:webhook_github_translator(event, translate_radicle_github_webhook)
end

b:build()
