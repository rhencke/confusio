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
local fetch_json = make_backend_transport("bearer", PAGES).fetch_json
local ZERO_SHA = "0000000000000000000000000000000000000000"

local function radicle_short_ref(ref)
  return (ref or ""):match("^refs/[^/]+/(.+)") or (ref or "")
end

local function radicle_ref_type(ref)
  return (ref or ""):match("^refs/tags/") and "tag" or "branch"
end

local function radicle_user_id(u)
  return u.id or u.did or ""
end

local function radicle_user_login(u)
  local id = radicle_user_id(u)
  return u.alias or u.username or u.login or u.name or id or ""
end

local translate_radicle_user = make_translator({
  login = computed(radicle_user_login),
  id = const(0),
  node_id = computed(radicle_user_id),
  avatar_url = field("avatar_url", { default = "" }),
  url = const(""),
  html_url = field("html_url", { default = "" }),
  type = const("User"),
  site_admin = const(false),
  name = "name",
  email = "email",
})

-- Map a Radicle repository object to GitHub format.
local function radicle_project(r)
  return (r.payloads and r.payloads["xyz.radicle.project"])
    or {
      name = r.name,
      description = r.description,
      defaultBranch = r.defaultBranch or r.default_branch,
    }
end

local function radicle_repo_owner(r)
  return r.owner or {}
end

local function radicle_repo_delegates(r)
  return r.delegates or {}
end

local function radicle_repo_owner_did(r)
  local delegates = radicle_repo_delegates(r)
  local owner = radicle_repo_owner(r)
  return owner.id or owner.did or (delegates[1] and delegates[1].id) or ""
end

local function radicle_repo_owner_login(r)
  local owner = radicle_repo_owner(r)
  local owner_did = radicle_repo_owner_did(r)
  return owner.alias or owner.login or owner_did:match("did:key:(.+)$") or owner_did
end

local function radicle_repo_name(r)
  local proj = radicle_project(r)
  return proj.name or r.rid or ""
end

local function radicle_repo_private(r)
  return r.private or false
end

local translate_radicle_repo_owner = make_translator({
  login = computed(radicle_repo_owner_login),
  id = const(0),
  node_id = computed(radicle_repo_owner_did),
  avatar_url = const(""),
  url = const(""),
  html_url = const(""),
  type = const("User"),
})

local translate_radicle_repo = make_translator({
  id = const(0),
  node_id = field("rid", { default = "" }),
  name = computed(radicle_repo_name),
  full_name = computed(function(r)
    local login = radicle_repo_owner_login(r)
    local name = radicle_repo_name(r)
    return (login ~= "" and (login .. "/") or "") .. name
  end),
  private = computed(radicle_repo_private),
  owner = computed(function(r)
    return translate_radicle_repo_owner(r)
  end),
  html_url = computed(function(r)
    return r.web_url or (config.base_url .. "/repos/" .. (r.rid or ""))
  end),
  description = computed(function(r)
    return radicle_project(r).description
  end),
  fork = const(false),
  url = const(""),
  clone_url = computed(function(r)
    return r.clone_url or (r.rid and ("rad://" .. r.rid) or "")
  end),
  homepage = const(""),
  size = const(0),
  stargazers_count = const(0),
  watchers_count = const(0),
  language = const(nil),
  has_issues = const(false),
  has_wiki = const(false),
  forks_count = const(0),
  archived = const(false),
  disabled = const(false),
  open_issues_count = const(0),
  default_branch = computed(function(r)
    return radicle_project(r).defaultBranch or "main"
  end),
  visibility = computed(function(r)
    return radicle_repo_private(r) and "private" or "public"
  end),
  forks = const(0),
  open_issues = const(0),
  watchers = const(0),
  created_at = const(nil),
  updated_at = const(nil),
  pushed_at = const(nil),
})

local function translate_radicle_repo_or_empty(r)
  if r == nil then
    return {}
  end
  return translate_radicle_repo(r)
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
  return translate_list(translate_radicle_repo_or_empty, repos)
end

local function radicle_commit_author(c)
  return c.author or {}
end

local function radicle_commit_committer(c)
  return c.committer or radicle_commit_author(c)
end

local translate_radicle_commit_author = make_translator({
  name = field("name", { default = "" }),
  email = field("email", { default = "" }),
  username = computed(function(author)
    return author.username or author.alias or author.name or ""
  end),
})

local translate_radicle_commit_committer = make_translator({
  name = computed(function(c)
    local committer = radicle_commit_committer(c)
    local author = radicle_commit_author(c)
    return committer.name or author.name or ""
  end),
  email = computed(function(c)
    local committer = radicle_commit_committer(c)
    local author = radicle_commit_author(c)
    return committer.email or author.email or ""
  end),
  username = computed(function(c)
    local committer = radicle_commit_committer(c)
    local author = radicle_commit_author(c)
    return committer.username or committer.alias or committer.name or author.name or ""
  end),
})

local translate_radicle_commit = make_translator({
  id = field("id", { default = "" }),
  tree_id = field("tree_id", { default = "" }),
  distinct = computed(function(c)
    return c.distinct ~= false
  end),
  message = field("message", { default = "" }),
  timestamp = field("timestamp", { default = "" }),
  url = field("url", { default = "" }),
  author = computed(function(c)
    return translate_radicle_commit_author(radicle_commit_author(c))
  end),
  committer = computed(function(c)
    return translate_radicle_commit_committer(c)
  end),
})

local function translate_radicle_commits(commits)
  return translate_list(translate_radicle_commit, commits)
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
  local sender = translate_radicle_user(payload.pusher or payload.sender or {})
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

local function radicle_patch_payload(payload)
  return (payload or {}).patch or {}
end

local function radicle_patch_repository(payload)
  return translate_radicle_repo((payload or {}).repository or {})
end

local function radicle_patch_number(payload)
  return tonumber(radicle_patch_payload(payload).number) or 0
end

local translate_radicle_patch_head = make_translator({
  ref = computed(function(payload)
    local patch = radicle_patch_payload(payload)
    return patch.head_ref or ("patch/" .. tostring(radicle_patch_number(payload)))
  end),
  sha = computed(function(payload)
    return radicle_patch_payload(payload).head or ""
  end),
  repo = computed(radicle_patch_repository),
})

local translate_radicle_patch_base = make_translator({
  ref = computed(function(payload)
    local patch = radicle_patch_payload(payload)
    local repository = radicle_patch_repository(payload)
    return patch.target_branch or repository.default_branch or ""
  end),
  sha = computed(function(payload)
    return radicle_patch_payload(payload).base or ""
  end),
  repo = computed(radicle_patch_repository),
})

local translate_radicle_patch = make_translator({
  id = computed(radicle_patch_number),
  node_id = computed(function(payload)
    return radicle_patch_payload(payload).id or ""
  end),
  number = computed(radicle_patch_number),
  title = computed(function(payload)
    return radicle_patch_payload(payload).title or ""
  end),
  body = computed(function(payload)
    return radicle_patch_payload(payload).description or ""
  end),
  state = computed(function(payload)
    return radicle_patch_payload(payload).state or "open"
  end),
  draft = const(false),
  html_url = computed(function(payload)
    return radicle_patch_payload(payload).url or ""
  end),
  url = computed(function(payload)
    return radicle_patch_payload(payload).url or ""
  end),
  user = computed(function(payload)
    local patch = radicle_patch_payload(payload)
    return translate_radicle_user(patch.author or (payload or {}).sender or {})
  end),
  head = computed(function(payload)
    return translate_radicle_patch_head(payload)
  end),
  base = computed(function(payload)
    return translate_radicle_patch_base(payload)
  end),
  created_at = computed(function(payload)
    return radicle_patch_payload(payload).created_at or ""
  end),
  updated_at = computed(function(payload)
    return radicle_patch_payload(payload).updated_at or ""
  end),
  closed_at = computed(function(payload)
    return radicle_patch_payload(payload).closed_at
  end),
  merged = const(false),
  merged_at = const(nil),
})

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
      sender = translate_radicle_user(payload.sender or (payload.patch or {}).author or {}),
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
