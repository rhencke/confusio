-- Harness Code backend handler overrides.
-- Uses Harness Code (Gitness) REST API via /gateway/code/api/v1/.
-- repo_ref is owner/repo URL-encoded as owner%2Frepo.
if config.base_url == "" then
  config.base_url = "https://app.harness.io"
end

local base = function()
  return config.base_url .. "/gateway/code/api/v1"
end
local auth = function()
  return make_fetch_opts("bearer")
end
local PAGES = { per_page = "limit", page = "page" }
local _t = make_backend_transport("bearer", PAGES)
local fetch_json = _t.fetch_json
local proxy_handler = _t.proxy_handler

local repo_ref = owner_repo_id

local function harness_repo_parts(r)
  local path = (r or {}).path or ""
  -- path is like "space/reponame"; split on last /
  local owner_part, name_part = path:match("^(.+)/([^/]+)$")
  if not owner_part then
    owner_part = ""
    name_part = path
  end
  return owner_part, name_part, path
end

local translate_harness_repo_owner = make_translator({
  login = computed(function(r)
    local owner_part = harness_repo_parts(r)
    return owner_part
  end),
  id = const(0),
  node_id = const(""),
  avatar_url = const(""),
  url = const(""),
  html_url = const(""),
  type = const("User"),
})

-- Map a Harness Code repository object to GitHub format.
local translate_harness_repo = make_translator({
  id = field("id", { default = 0 }),
  node_id = const(""),
  name = computed(function(r)
    local _, name_part = harness_repo_parts(r)
    return name_part
  end),
  full_name = computed(function(r)
    local _, _, path = harness_repo_parts(r)
    return path
  end),
  private = computed(function(r)
    return not r.is_public
  end),
  owner = computed(function(r)
    return translate_harness_repo_owner(r)
  end),
  html_url = computed(function(r)
    local _, _, path = harness_repo_parts(r)
    return config.base_url .. "/" .. path
  end),
  description = "description",
  fork = computed(function(r)
    return r.fork_id ~= nil and r.fork_id > 0
  end),
  url = const(""),
  clone_url = field("git_url", { default = "" }),
  homepage = const(""),
  size = field("size", { default = 0 }),
  stargazers_count = field("num_stars", { default = 0 }),
  watchers_count = const(0),
  language = const(nil),
  has_issues = const(false),
  has_wiki = const(false),
  forks_count = field("num_forks", { default = 0 }),
  archived = const(false),
  disabled = const(false),
  open_issues_count = const(0),
  default_branch = field("default_branch", { default = "main" }),
  visibility = computed(function(r)
    return r.is_public and "public" or "private"
  end),
  forks = field("num_forks", { default = 0 }),
  open_issues = const(0),
  watchers = const(0),
  created_at = computed(function(r)
    return r.created and tostring(r.created) or nil
  end),
  updated_at = computed(function(r)
    return r.updated and tostring(r.updated) or nil
  end),
  pushed_at = computed(function(r)
    return r.updated and tostring(r.updated) or nil
  end),
})

local function harness_repo_list(repos)
  return translate_list(translate_harness_repo, repos)
end

-- Translate GitHub create/update request body to Harness Code format.
local function translate_harness_req(body_str)
  local req = DecodeJson(body_str or "{}")
  local h = {}
  if req.name then
    h.identifier = req.name
  end
  if req.description then
    h.description = req.description
  end
  if req.private ~= nil then
    h.is_public = not req.private
  end
  if req.default_branch then
    h.default_branch = req.default_branch
  end
  return EncodeJson(h)
end

-- Translate a Harness branch object to GitHub format.
-- Harness: { name, sha, is_default }
local translate_harness_branch_commit = make_translator({
  sha = field("sha", { default = "" }),
  url = const(""),
})

local translate_harness_branch = make_translator({
  name = "name",
  commit = computed(function(b)
    return translate_harness_branch_commit(b)
  end),
  protected = const(false),
})

-- Translate a Harness commit to GitHub format.
-- Harness: { sha, message, author: { identity: { name, email }, when }, committer: {...}, parent_shas }
local function harness_identity(actor)
  return (actor or {}).identity or {}
end

local translate_harness_commit_signature = make_translator({
  name = computed(function(actor)
    return harness_identity(actor).name or ""
  end),
  email = computed(function(actor)
    return harness_identity(actor).email or ""
  end),
  date = field("when", { default = "" }),
})

local translate_harness_commit_user = make_translator({
  login = computed(function(actor)
    return harness_identity(actor).name or ""
  end),
  id = const(0),
  avatar_url = const(""),
})

local translate_harness_commit_body = make_translator({
  message = field("message", { default = "" }),
  author = computed(function(c)
    return translate_harness_commit_signature(c.author or {})
  end),
  committer = computed(function(c)
    return translate_harness_commit_signature(c.committer or {})
  end),
})

local translate_harness_commit = make_translator({
  sha = field("sha", { default = "" }),
  commit = computed(function(c)
    return translate_harness_commit_body(c)
  end),
  author = computed(function(c)
    return translate_harness_commit_user(c.author or {})
  end),
  committer = computed(function(c)
    return translate_harness_commit_user(c.committer or {})
  end),
})

-- Translate a Harness deploy key to GitHub format.
-- Harness: { id, identifier, public_key, created, usage }
local translate_harness_key = make_translator({
  id = field("id", { default = 0 }),
  key = field("public_key", { default = "" }),
  title = field("identifier", { default = "" }),
  verified = const(true),
  created_at = computed(function(k)
    return k.created and tostring(k.created) or nil
  end),
  url = const(""),
  read_only = computed(function(k)
    return k.usage == "read"
  end),
})

-- Translate a Harness webhook to GitHub format.
-- Harness: { id, identifier, url, enabled, triggers: [...] }
local translate_harness_hook_config = make_translator({
  url = field("url", { default = "" }),
  content_type = const("json"),
})

local translate_harness_hook = make_translator({
  id = field("id", { default = 0 }),
  name = const("web"),
  active = field("enabled", { default = false }),
  events = computed(function(h)
    return h.triggers or {}
  end),
  config = computed(function(h)
    return translate_harness_hook_config(h)
  end),
  created_at = computed(function(h)
    return h.created and tostring(h.created) or nil
  end),
  updated_at = computed(function(h)
    return h.updated and tostring(h.updated) or nil
  end),
})

-- Translate GitHub webhook request to Harness format.
local function translate_harness_hook_req(body_str)
  local req = DecodeJson(body_str or "{}")
  local cfg = req.config or {}
  return EncodeJson({
    identifier = req.name or "web",
    url = cfg.url or "",
    enabled = req.active ~= false,
    triggers = req.events or {},
  })
end

local b = make_backend_builder()
b:rest("get_root", function()
  proxy_health_check(pcall(Fetch, base(), auth()))
end)

b:rest(
  "get_repo",
  proxy_handler(translate_harness_repo, function(owner, repo_name)
    return base() .. "/repos/" .. repo_ref(owner, repo_name)
  end)
)

b:rest("patch_repo", function(owner, repo_name)
  proxy_json(
    translate_harness_repo,
    fetch_json(
      base() .. "/repos/" .. repo_ref(owner, repo_name),
      "PATCH",
      translate_harness_req(GetBody())
    )
  )
end)

b:rest("delete_repo", function(owner, repo_name)
  local url = base() .. "/repos/" .. repo_ref(owner, repo_name)
  local dopts = auth() or {}
  dopts.method = "DELETE"
  proxy_204({ 200 }, pcall(Fetch, url, dopts))
end)

b:rest(
  "get_user_repos",
  proxy_handler(harness_repo_list, function()
    return append_page_params(base() .. "/repos", PAGES)
  end)
)

b:rest("post_user_repos", function()
  proxy_json_created(
    translate_harness_repo,
    fetch_json(base() .. "/repos", "POST", translate_harness_req(GetBody()))
  )
end)

b:rest(
  "get_org_repos",
  proxy_handler(harness_repo_list, function(space)
    return append_page_params(base() .. "/spaces/" .. space .. "/repos", PAGES)
  end)
)

b:rest("post_org_repos", function(space)
  local req = DecodeJson(GetBody() or "{}")
  req.parent_ref = space
  proxy_json_created(
    translate_harness_repo,
    fetch_json(base() .. "/repos", "POST", EncodeJson(req))
  )
end)

-- GET /repos/{owner}/{repo}/tags
b:rest("get_repo_tags", function(owner, repo_name)
  proxy_json(
    function(tags)
      tags = tags or {}
      for i, t in ipairs(tags) do
        tags[i] = { name = t.name, commit = { sha = t.sha or t.target or "", url = "" } }
      end
      return tags
    end,
    fetch_json(
      append_page_params(base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/tags", PAGES)
    )
  )
end)

-- Branches ------------------------------------------------------------------

b:rest("get_repo_branches", function(owner, repo_name)
  proxy_json(
    function(branches)
      return translate_list(translate_harness_branch, branches)
    end,
    fetch_json(
      append_page_params(base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/branches", PAGES)
    )
  )
end)

b:rest(
  "get_repo_branch",
  proxy_handler(translate_harness_branch, function(owner, repo_name, branch)
    return base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/branches/" .. branch
  end)
)

-- Commits -------------------------------------------------------------------

b:rest("get_repo_commits", function(owner, repo_name)
  local ref = GetParam("sha") or ""
  local url = base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/commits"
  if ref ~= "" then
    url = url .. "?git_ref=" .. ref
  end
  url = append_page_params(url, PAGES)
  proxy_json(function(commits)
    return translate_list(translate_harness_commit, commits)
  end, fetch_json(url))
end)

b:rest(
  "get_repo_commit",
  proxy_handler(translate_harness_commit, function(owner, repo_name, ref)
    return base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/commits/" .. ref
  end)
)

-- Statuses ------------------------------------------------------------------
-- Harness uses /check/commits/{sha} for CI results.

b:rest(
  "get_commit_statuses",
  proxy_handler(nil, function(owner, repo_name, ref)
    return base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/check/commits/" .. ref
  end)
)

b:rest(
  "get_commit_combined_status",
  proxy_handler(nil, function(owner, repo_name, ref)
    return base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/check/commits/" .. ref
  end)
)

b:rest("post_commit_status", function(owner, repo_name, sha)
  proxy_json_created(
    nil,
    fetch_json(
      base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/check/commits/" .. sha,
      "POST",
      GetBody()
    )
  )
end)

-- Contents ------------------------------------------------------------------
-- Harness content API returns the same shape as GitHub (type, name, path, sha, encoding, content).

b:rest("get_repo_readme", function(owner, repo_name)
  -- Harness has no dedicated readme endpoint; fetch root contents and find README.
  local ref = GetParam("ref") or ""
  local url = base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/content/README.md"
  if ref ~= "" then
    url = url .. "?git_ref=" .. ref
  end
  proxy_json(nil, fetch_json(url))
end)

b:rest("get_repo_content", function(owner, repo_name, path)
  local ref = GetParam("ref") or ""
  local url = base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/content/" .. path
  if ref ~= "" then
    url = url .. "?git_ref=" .. ref
  end
  proxy_json(function(data)
    -- Directory listing: Harness returns { type="dir", entries=[...] }; GitHub expects array.
    if data and data.type == "dir" then
      return data.entries or {}
    end
    return data or {}
  end, fetch_json(url))
end)

b:rest("put_repo_content", function(owner, repo_name, path)
  proxy_json(
    nil,
    fetch_json(
      base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/content/" .. path,
      "PUT",
      GetBody()
    )
  )
end)

b:rest("delete_repo_content", function(owner, repo_name, path)
  proxy_json(
    nil,
    fetch_json(
      base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/content/" .. path,
      "DELETE",
      GetBody()
    )
  )
end)

-- Forks ---------------------------------------------------------------------

b:rest(
  "get_repo_forks",
  proxy_handler(harness_repo_list, function(owner, repo_name)
    return append_page_params(base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/forks", PAGES)
  end)
)

b:rest("post_repo_forks", function(owner, repo_name)
  proxy_json_created(
    translate_harness_repo,
    fetch_json(base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/fork", "POST", GetBody())
  )
end)

-- Deploy keys ---------------------------------------------------------------

b:rest("get_repo_keys", function(owner, repo_name)
  proxy_json(
    function(keys)
      return translate_list(translate_harness_key, keys)
    end,
    fetch_json(
      append_page_params(base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/keys", PAGES)
    )
  )
end)

b:rest("post_repo_keys", function(owner, repo_name)
  local req = DecodeJson(GetBody() or "{}")
  local h = {
    identifier = req.title or "",
    public_key = req.key or "",
    usage = req.read_only and "read" or "readwrite",
  }
  proxy_json_created(
    translate_harness_key,
    fetch_json(base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/keys", "POST", EncodeJson(h))
  )
end)

b:rest(
  "get_repo_key",
  proxy_handler(translate_harness_key, function(owner, repo_name, key_id)
    return base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/keys/" .. key_id
  end)
)

b:rest("delete_repo_key", function(owner, repo_name, key_id)
  proxy_204(
    { 200 },
    fetch_json(base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/keys/" .. key_id, "DELETE")
  )
end)

-- Webhooks ------------------------------------------------------------------

b:rest("get_repo_hooks", function(owner, repo_name)
  proxy_json(
    function(hooks)
      return translate_list(translate_harness_hook, hooks)
    end,
    fetch_json(
      append_page_params(base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/webhooks", PAGES)
    )
  )
end)

b:rest("post_repo_hooks", function(owner, repo_name)
  proxy_json_created(
    translate_harness_hook,
    fetch_json(
      base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/webhooks",
      "POST",
      translate_harness_hook_req(GetBody())
    )
  )
end)

b:rest(
  "get_repo_hook",
  proxy_handler(translate_harness_hook, function(owner, repo_name, hook_id)
    return base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/webhooks/" .. hook_id
  end)
)

b:rest("patch_repo_hook", function(owner, repo_name, hook_id)
  proxy_json(
    translate_harness_hook,
    fetch_json(
      base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/webhooks/" .. hook_id,
      "PATCH",
      translate_harness_hook_req(GetBody())
    )
  )
end)

b:rest("delete_repo_hook", function(owner, repo_name, hook_id)
  proxy_204(
    { 200 },
    fetch_json(
      base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/webhooks/" .. hook_id,
      "DELETE"
    )
  )
end)

-- Hook config ---------------------------------------------------------------

b:rest("get_repo_hook_config", function(owner, repo_name, hook_id)
  proxy_json(function(h)
    return (translate_harness_hook(h)).config or {}
  end, fetch_json(base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/webhooks/" .. hook_id))
end)

b:rest("patch_repo_hook_config", function(owner, repo_name, hook_id)
  local url = base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/webhooks/" .. hook_id
  local ok, status, _, body = fetch_json(url)
  if not ok or status ~= 200 then
    if ok then
      respond_json(status, {})
    else
      respond_json(503, {})
    end
    return
  end
  local hook = DecodeJson(body) or {}
  local new_cfg = DecodeJson(GetBody() or "{}")
  if new_cfg.url then
    hook.url = new_cfg.url
  end
  proxy_json(function(h)
    return (translate_harness_hook(h)).config or {}
  end, fetch_json(url, "PATCH", EncodeJson(hook)))
end)

b:rest("post_repo_hook_test", function(owner, repo_name, hook_id)
  proxy_204(
    { 200 },
    fetch_json(
      base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/webhooks/" .. hook_id .. "/test",
      "POST"
    )
  )
end)

-- Languages -----------------------------------------------------------------

b:rest(
  "get_repo_languages",
  proxy_handler(nil, function(owner, repo_name)
    return base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/languages"
  end)
)

-- Archive -------------------------------------------------------------------

b:rest("get_repo_tarball", function(owner, repo_name, ref)
  SetStatus(302, "Found")
  SetHeader(
    "Location",
    base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/archive?format=tar.gz&git_ref=" .. ref
  )
  Write("")
end)

b:rest("get_repo_zipball", function(owner, repo_name, ref)
  SetStatus(302, "Found")
  SetHeader(
    "Location",
    base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/archive?format=zip&git_ref=" .. ref
  )
  Write("")
end)

-- Users' repos --------------------------------------------------------------

b:rest(
  "get_users_repos",
  proxy_handler(harness_repo_list, function(username)
    return append_page_params(base() .. "/spaces/" .. username .. "/repos", PAGES)
  end)
)

-- Users ---------------------------------------------------------------------

-- GET /user
b:rest("get_user", function()
  proxy_json(function(u)
    if not u then
      return {}
    end
    return {
      login = u.uid or "",
      id = u.id or 0,
      node_id = "",
      avatar_url = u.url or "",
      html_url = "",
      type = "User",
      site_admin = u.admin or false,
      name = u.display_name or "",
      email = u.email or "",
    }
  end, fetch_json(base() .. "/user"))
end)

-- Checks (via Harness Code /check/commits/{sha}) --------------------------------
--
-- Harness Code stores CI results as check statuses on commit SHAs.  Each check
-- entry has id, status, check_suite_name, started, and ended fields.
--   • GET commits/{ref}/check-runs → GET /check/commits/{sha}
--   • Check Suites have no native equivalent; all suite endpoints are stubs.
--
-- Status mapping (Harness → GitHub):
--   running/pending → status=in_progress, conclusion=null
--   success         → status=completed,   conclusion=success
--   failure/error   → status=completed,   conclusion=failure
--   cancelled       → status=completed,   conclusion=cancelled

-- GET /repos/{owner}/{repo}/commits/{ref}/check-runs
-- Maps to Harness Code GET /check/commits/{sha}.
b:rest("get_commit_check_runs", function(owner, repo_name, ref)
  local ok, status, _, body =
    fetch_json(base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/check/commits/" .. ref)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local list = DecodeJson(body) or {}
  local runs = {}
  for _, c in ipairs(list) do
    local s = c.status or "pending"
    local harness_to_gh = {
      success = { status = "completed", conclusion = "success" },
      failure = { status = "completed", conclusion = "failure" },
      error = { status = "completed", conclusion = "failure" },
      cancelled = { status = "completed", conclusion = "cancelled" },
    }
    local mapped = harness_to_gh[s] or { status = "in_progress", conclusion = nil }
    local gh_status, gh_conclusion = mapped.status, mapped.conclusion
    runs[#runs + 1] = {
      id = c.id or 0,
      node_id = "",
      head_sha = ref,
      name = c.check_suite_name or tostring(c.id or 0),
      status = gh_status,
      conclusion = gh_conclusion,
      started_at = c.started,
      completed_at = gh_status == "completed" and (c.ended or c.started) or nil,
      output = {
        title = c.check_suite_name or "",
        summary = c.check_suite_name or "",
        text = "",
        annotations_count = 0,
        annotations_url = "",
      },
      url = "",
      html_url = "",
      details_url = "",
    }
  end
  respond_json(200, { total_count = #runs, check_runs = runs })
end)

-- Issues -----------------------------------------------------------------------
-- Harness Code has no native issue tracker.
-- Issue management in the Harness platform is handled via Jira integration.
-- All issues, labels, milestones, and assignees endpoints fall back to the
-- default empty-list / 404 handlers defined in .init.lua.

-- PATCH /user
b:rest("patch_user", function()
  proxy_json(function(u)
    if not u then
      return {}
    end
    return {
      login = u.uid or "",
      id = u.id or 0,
      node_id = "",
      avatar_url = u.url or "",
      html_url = "",
      type = "User",
      site_admin = u.admin or false,
      name = u.display_name or "",
      email = u.email or "",
    }
  end, fetch_json(base() .. "/user", "PATCH", GetBody()))
end)

-- Webhook handlers: Harness CI pipeline execution events -------------------
--
-- Harness CI embeds the event type in payload.eventType (no event-type
-- header).  Pipeline execution events map to GitHub workflow_run; stage
-- execution events map to workflow_job.
--
-- Pipeline event types:
--   pipeline_execution_started → workflow_run / in_progress
--   pipeline_execution_success → workflow_run / completed / success
--   pipeline_execution_failed  → workflow_run / completed / failure
--   pipeline_execution_aborted → workflow_run / completed / cancelled
--
-- Stage event types:
--   stage_execution_started → workflow_job / in_progress
--   stage_execution_success → workflow_job / completed / success
--   stage_execution_failed  → workflow_job / completed / failure
--   stage_execution_aborted → workflow_job / completed / cancelled
--
-- Harness timestamps are epoch milliseconds; convert to ISO 8601 for GitHub.

local function harness_ts(ms)
  if not ms or ms == 0 then
    return nil
  end
  return os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(ms / 1000))
end

local function harness_webhook_sender(payload)
  local tb = payload.triggeredBy or {}
  return {
    login = tb.name or tb.email or "",
    id = 0,
    node_id = "",
    avatar_url = "",
    url = "",
    html_url = "",
    type = "User",
    site_admin = false,
  }
end

local function harness_webhook_repo(payload)
  local ci = (payload.moduleInfo or {}).ci or {}
  local owner = payload.orgIdentifier or payload.projectIdentifier or ""
  local name = ci.repoName or ""
  return {
    id = 0,
    node_id = "",
    name = name,
    full_name = owner ~= "" and (owner .. "/" .. name) or name,
    private = true,
    owner = {
      login = owner,
      id = 0,
      node_id = "",
      avatar_url = "",
      url = "",
      html_url = "",
      type = "Organization",
    },
    html_url = "",
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
    default_branch = "main",
    visibility = "private",
    forks = 0,
    open_issues = 0,
    watchers = 0,
    created_at = nil,
    updated_at = nil,
    pushed_at = nil,
  }
end

-- harness_pipeline_event builds a workflow_run internal event.
-- gh_action: "in_progress" | "completed"
-- gh_status: "in_progress" | "completed"
-- gh_conclusion: "success" | "failure" | "cancelled" | nil
local function harness_pipeline_event(payload, gh_action, gh_status, gh_conclusion)
  local ci = (payload.moduleInfo or {}).ci or {}
  local sender = harness_webhook_sender(payload)
  local start_iso = harness_ts(payload.startTs)
  local end_iso = harness_ts(payload.endTs)
  local workflow_run = {
    id = 0,
    node_id = "",
    name = payload.pipelineIdentifier or "",
    head_branch = ci.branch or "",
    head_sha = ci.commitSha or ci.sha or "",
    run_number = payload.runSequence or 0,
    event = "push",
    display_title = payload.pipelineIdentifier or "",
    status = gh_status,
    conclusion = gh_conclusion,
    workflow_id = 0,
    url = "",
    html_url = "",
    pull_requests = {},
    created_at = start_iso or "",
    updated_at = end_iso or start_iso or "",
    run_attempt = 1,
    referenced_workflows = {},
    actor = sender,
    triggering_actor = sender,
  }
  local workflow = {
    id = 0,
    name = payload.pipelineIdentifier or "",
    path = "",
    state = "active",
    url = "",
    html_url = "",
    badge_url = "",
    created_at = "",
    updated_at = "",
  }
  return make_internal_event({
    event = "workflow_run",
    action = gh_action,
    provider = "harness",
    raw = payload,
    data = {
      action = gh_action,
      workflow_run = workflow_run,
      workflow = workflow,
      repository = harness_webhook_repo(payload),
      sender = sender,
    },
    timestamp = end_iso or start_iso or "",
  })
end

-- harness_stage_event builds a workflow_job internal event.
local function harness_stage_event(payload, gh_action, gh_status, gh_conclusion)
  local sender = harness_webhook_sender(payload)
  local start_iso = harness_ts(payload.startTs)
  local end_iso = harness_ts(payload.endTs)
  local job = {
    id = 0,
    run_id = 0,
    run_url = "",
    run_attempt = 1,
    node_id = "",
    head_sha = "",
    url = "",
    html_url = "",
    status = gh_status,
    conclusion = gh_conclusion,
    started_at = start_iso or "",
    completed_at = gh_status == "completed" and (end_iso or start_iso) or nil,
    name = payload.stageName or payload.stageIdentifier or "",
    steps = {},
    check_run_url = "",
    labels = {},
    runner_id = nil,
    runner_name = nil,
    runner_group_id = nil,
    runner_group_name = nil,
    workflow_name = payload.pipelineIdentifier or "",
    head_branch = "",
  }
  return make_internal_event({
    event = "workflow_job",
    action = gh_action,
    provider = "harness",
    raw = payload,
    data = {
      action = gh_action,
      workflow_job = job,
      repository = harness_webhook_repo(payload),
      sender = sender,
    },
    timestamp = end_iso or start_iso or "",
  })
end

b:webhook("pipeline_execution_started", function(payload)
  return harness_pipeline_event(payload, "in_progress", "in_progress", nil)
end)

b:webhook("pipeline_execution_success", function(payload)
  return harness_pipeline_event(payload, "completed", "completed", "success")
end)

b:webhook("pipeline_execution_failed", function(payload)
  return harness_pipeline_event(payload, "completed", "completed", "failure")
end)

b:webhook("pipeline_execution_aborted", function(payload)
  return harness_pipeline_event(payload, "completed", "completed", "cancelled")
end)

b:webhook("stage_execution_started", function(payload)
  return harness_stage_event(payload, "in_progress", "in_progress", nil)
end)

b:webhook("stage_execution_success", function(payload)
  return harness_stage_event(payload, "completed", "completed", "success")
end)

b:webhook("stage_execution_failed", function(payload)
  return harness_stage_event(payload, "completed", "completed", "failure")
end)

b:webhook("stage_execution_aborted", function(payload)
  return harness_stage_event(payload, "completed", "completed", "cancelled")
end)

local HARNESS_NORMALIZED_WEBHOOK_EVENTS = {
  "workflow_run",
  "workflow_job",
}

local function harness_normalized_payload_without_envelope_fields(data)
  local payload = {}
  for k, v in pairs(data or {}) do
    if k ~= "sender" and k ~= "repository" then
      payload[k] = v
    end
  end
  return payload
end

local function translate_harness_normalized_webhook(internal_event, fields)
  local data = internal_event.data or {}
  fields = fields or {}
  return make_normalized_webhook_envelope(internal_event, {
    id = fields.id,
    type = fields.type
      or normalized_webhook_event_type(internal_event.event, internal_event.action),
    occurred_at = fields.occurred_at,
    actor = fields.actor or data.sender,
    repository = fields.repository or data.repository,
    payload = fields.payload or harness_normalized_payload_without_envelope_fields(data),
  })
end

local function translate_harness_github_webhook(internal_event, fields)
  return github_webhook_payload(internal_event, fields)
end

for _, event in ipairs(HARNESS_NORMALIZED_WEBHOOK_EVENTS) do
  b:webhook_translator(event, translate_harness_normalized_webhook)
  b:webhook_github_translator(event, translate_harness_github_webhook)
end

b:build()
