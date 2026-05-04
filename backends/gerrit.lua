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

local function gerrit_project_parts(full, owner, repo_name)
  full = full or (owner and (owner .. "/" .. (repo_name or "")) or "")
  local o, n = full:match("^(.+)/([^/]+)$")
  if not o then
    o = ""
    n = full
  end
  return full, o, n
end

-- Map a Gerrit project object to GitHub format.
local translate_gerrit_repo_owner = make_translator({
  login = computed(function(r, owner, repo_name)
    local _, o = gerrit_project_parts(r.name, owner, repo_name)
    return o
  end),
  id = const(0),
  node_id = const(""),
  avatar_url = const(""),
  url = const(""),
  html_url = const(""),
  type = const("User"),
})

local translate_gerrit_repo = make_translator({
  id = const(0),
  node_id = const(""),
  name = computed(function(r, owner, repo_name)
    local _, _, n = gerrit_project_parts(r.name, owner, repo_name)
    return n
  end),
  full_name = computed(function(r, owner, repo_name)
    local full = gerrit_project_parts(r.name, owner, repo_name)
    return full
  end),
  private = const(false),
  owner = computed(function(r, owner, repo_name)
    return translate_gerrit_repo_owner(r, owner, repo_name)
  end),
  html_url = computed(function(r, owner, repo_name)
    local full = gerrit_project_parts(r.name, owner, repo_name)
    return config.base_url .. "/admin/repos/" .. full
  end),
  description = "description",
  fork = const(false),
  url = const(""),
  clone_url = const(""),
  homepage = const(""),
  size = const(0),
  stargazers_count = const(0),
  watchers_count = const(0),
  language = const(nil),
  has_issues = const(false),
  has_wiki = const(false),
  forks_count = const(0),
  archived = computed(function(r)
    return r.state == "READ_ONLY"
  end),
  disabled = computed(function(r)
    return r.state == "HIDDEN"
  end),
  open_issues_count = const(0),
  default_branch = computed(function(_r, _owner, _repo_name, opts)
    opts = opts or {}
    return opts.default_branch or "main"
  end),
  visibility = const("public"),
  forks = const(0),
  open_issues = const(0),
  watchers = const(0),
  created_at = const(nil),
  updated_at = const(nil),
  pushed_at = const(nil),
})

-- Gerrit prepends ")]}'\n" (5 chars) to all JSON responses as XSSI protection.
local function gerrit_decode(body)
  if body and body:sub(1, 4) == ")]}'" then
    return DecodeJson(body:sub(6)) or {}
  end
  return DecodeJson(body) or {}
end

-- Map a Gerrit account object to GitHub user format.
local translate_gerrit_user = make_translator({
  login = field("username", { default = "" }),
  id = field("_account_id", { default = 0 }),
  node_id = const(""),
  avatar_url = const(""),
  html_url = const(""),
  type = const("User"),
  site_admin = const(false),
  name = field("name", { default = "" }),
  email = field("email", { default = "" }),
})

-- Gerrit branch: { ref, revision }
local translate_gerrit_branch_commit = make_translator({
  sha = field("revision", { default = "" }),
  url = const(""),
})

local translate_gerrit_branch = make_translator({
  name = computed(function(b)
    return b.ref and b.ref:match("^refs/heads/(.+)") or (b.ref or "")
  end),
  commit = computed(function(b)
    return translate_gerrit_branch_commit(b)
  end),
  protected = const(false),
})

-- Gerrit tag: { ref, revision, object }
local translate_gerrit_tag_commit = make_translator({
  sha = computed(function(t)
    return t.revision or t.object or ""
  end),
  url = const(""),
})

local translate_gerrit_tag = make_translator({
  name = computed(function(t)
    return t.ref and t.ref:match("^refs/tags/(.+)") or (t.ref or "")
  end),
  commit = computed(function(t)
    return translate_gerrit_tag_commit(t)
  end),
})

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

local function gerrit_patchset_timestamp(patchSet)
  return (patchSet or {}).createdOn and tostring((patchSet or {}).createdOn) or ""
end

local function gerrit_event_timestamp(payload)
  payload = payload or {}
  if payload.eventCreatedOn then
    return tostring(payload.eventCreatedOn)
  end
  local patch_ts = gerrit_patchset_timestamp(payload.patchSet)
  if patch_ts ~= "" then
    return patch_ts
  end
  return (payload.change or {}).updated or ""
end

local ZERO_SHA = "0000000000000000000000000000000000000000"

local function gerrit_ref_update_project(refUpdate)
  return (refUpdate or {}).project or ""
end

local function gerrit_ref_name(refUpdate)
  return (refUpdate or {}).refName or ""
end

local function gerrit_short_ref(ref)
  return (ref or ""):match("^refs/[^/]+/(.+)") or (ref or "")
end

local function gerrit_ref_type(ref)
  return (ref or ""):match("^refs/tags/") and "tag" or "branch"
end

local function gerrit_ref_repo(refUpdate)
  return translate_gerrit_repo({ name = gerrit_ref_update_project(refUpdate) })
end

local function gerrit_project_repo(payload)
  payload = payload or {}
  local head = gerrit_short_ref(payload.newHead or payload.headName or payload.projectHead)
  local opts = head ~= "" and { default_branch = head } or nil
  return translate_gerrit_repo({ name = payload.projectName }, nil, nil, opts)
end

local translate_gerrit_pull_head = make_translator({
  ref = field("branch", { default = "" }),
  sha = computed(function(_change, patchSet)
    return (patchSet or {}).revision or ""
  end),
  repo = const(nil),
})

local translate_gerrit_pull_base = make_translator({
  ref = field("branch", { default = "" }),
  sha = const(""),
  repo = const(nil),
})

local translate_gerrit_pull_request = make_translator({
  id = field("_number", { default = 0 }),
  node_id = const(""),
  number = field("_number", { default = 0 }),
  title = field("subject", { default = "" }),
  body = const(""),
  state = computed(function(_change, _patchSet, opts)
    opts = opts or {}
    return opts.state or "open"
  end),
  draft = field("wip", { default = false }),
  html_url = computed(function(change)
    return config.base_url .. "/c/" .. (change.project or "") .. "/+/" .. (change._number or "")
  end),
  url = const(""),
  user = nested(translate_gerrit_user, "owner"),
  head = computed(function(change, patchSet)
    return translate_gerrit_pull_head(change, patchSet)
  end),
  base = computed(function(change)
    return translate_gerrit_pull_base(change)
  end),
  created_at = field("created", { default = "" }),
  updated_at = field("updated", { default = "" }),
  closed_at = computed(function(_change, _patchSet, opts)
    opts = opts or {}
    return opts.closed_at
  end),
  merged = computed(function(_change, _patchSet, opts)
    opts = opts or {}
    return opts.merged or false
  end),
  merged_at = computed(function(_change, _patchSet, opts)
    opts = opts or {}
    return opts.merged_at
  end),
})

local function gerrit_change(change, patchSet, opts)
  change = change or {}
  local repo = translate_gerrit_repo(
    { name = change.project },
    nil,
    nil,
    { default_branch = change.branch or "main" }
  )
  local pr = translate_gerrit_pull_request(change, patchSet, opts)
  return pr, repo
end

local function gerrit_change_actor(payload)
  payload = payload or {}
  return payload.uploader
    or payload.submitter
    or payload.abandoner
    or payload.restorer
    or payload.changer
    or payload.editor
    or payload.adder
    or payload.remover
    or payload.author
    or (payload.change or {}).owner
    or {}
end

local translate_gerrit_label = make_translator({
  id = const(0),
  node_id = const(""),
  url = const(""),
  name = computed(function(name)
    return name or ""
  end),
  color = const(""),
  description = const(""),
  default = const(false),
})

local function gerrit_hashtags(hashtags)
  return translate_list(translate_gerrit_label, hashtags)
end

local function gerrit_pull_request_event(payload, action, opts)
  payload = payload or {}
  opts = opts or {}
  local timestamp = gerrit_event_timestamp(payload)
  local actor = gerrit_change_actor(payload)
  local pr, repo = gerrit_change(payload.change, payload.patchSet, {
    state = opts.state,
    closed_at = opts.closed_at and timestamp or nil,
    merged = opts.merged,
    merged_at = opts.merged and timestamp or nil,
  })
  local data = {
    action = action,
    number = (payload.change or {})._number,
    pull_request = pr,
    repository = repo,
    sender = translate_gerrit_user(actor),
  }
  if payload.reason then
    data.reason = payload.reason
  end
  if opts.changes then
    data.changes = opts.changes
  end
  if opts.label then
    data.label = opts.label
  end
  if opts.assignee then
    data.assignee = opts.assignee
  end
  if opts.assignee ~= nil then
    data.pull_request.assignee = opts.assignee
  end
  if opts.requested_reviewer then
    data.requested_reviewer = opts.requested_reviewer
  end
  if opts.requested_reviewers then
    data.pull_request.requested_reviewers = opts.requested_reviewers
  end
  if opts.labels then
    data.pull_request.labels = opts.labels
  end
  return make_internal_event({
    event = "pull_request",
    action = action,
    provider = "gerrit",
    raw = payload,
    data = data,
    timestamp = timestamp,
  })
end

local function gerrit_reviewer_event(payload, action)
  payload = payload or {}
  local reviewer = translate_gerrit_user(payload.reviewer)
  return gerrit_pull_request_event(payload, action, {
    requested_reviewer = reviewer,
    requested_reviewers = action == "review_requested" and { reviewer } or {},
    changes = {
      reviewer = {
        from = action == "review_request_removed" and reviewer or nil,
        to = action == "review_requested" and reviewer or nil,
      },
      approvals = payload.approvals,
    },
  })
end

local function gerrit_ref_update_event(payload, refUpdate)
  payload = payload or {}
  refUpdate = refUpdate or payload.refUpdate or {}
  local before = refUpdate.oldRev or ZERO_SHA
  local after = refUpdate.newRev or ZERO_SHA
  local ref = gerrit_ref_name(refUpdate)
  local repo = gerrit_ref_repo(refUpdate)
  local sender = translate_gerrit_user(payload.submitter)
  local timestamp = gerrit_event_timestamp(payload)
  local ref_type = gerrit_ref_type(ref)
  local ref_short = gerrit_short_ref(ref)

  if before == ZERO_SHA then
    return make_internal_event({
      event = "create",
      action = "create",
      provider = "gerrit",
      raw = payload,
      data = {
        ref = ref_short,
        ref_type = ref_type,
        master_branch = repo.default_branch or "",
        description = repo.description,
        pusher_type = "user",
        repository = repo,
        sender = sender,
      },
      timestamp = timestamp,
    })
  end

  if after == ZERO_SHA then
    return make_internal_event({
      event = "delete",
      action = "delete",
      provider = "gerrit",
      raw = payload,
      data = {
        ref = ref_short,
        ref_type = ref_type,
        master_branch = repo.default_branch or "",
        description = repo.description,
        pusher_type = "user",
        repository = repo,
        sender = sender,
      },
      timestamp = timestamp,
    })
  end

  return make_internal_event({
    event = "push",
    action = "push",
    provider = "gerrit",
    raw = payload,
    data = {
      ref = ref,
      before = before,
      after = after,
      created = false,
      deleted = false,
      forced = false,
      compare = "",
      commits = {},
      head_commit = nil,
      pusher = {
        name = (payload.submitter or {}).name or (payload.submitter or {}).username or "",
        email = (payload.submitter or {}).email or "",
      },
      repository = repo,
      sender = sender,
      ref_updates = payload.refUpdates,
    },
    timestamp = timestamp,
  })
end

local function gerrit_project_created_event(payload)
  payload = payload or {}
  local head = payload.headName or payload.projectHead or ""
  local repository = gerrit_project_repo(payload)
  local sender = translate_gerrit_user(payload.submitter or payload.creator or payload.createdBy)
  return make_internal_event({
    event = "repository",
    action = "created",
    provider = "gerrit",
    raw = payload,
    data = {
      action = "created",
      repository = repository,
      sender = sender,
      project_head = head,
    },
    timestamp = gerrit_event_timestamp(payload),
  })
end

local function gerrit_project_deleted_event(payload)
  payload = payload or {}
  local repository = gerrit_project_repo(payload)
  local sender = translate_gerrit_user(payload.submitter or payload.deleter or payload.deletedBy)
  return make_internal_event({
    event = "repository",
    action = "deleted",
    provider = "gerrit",
    raw = payload,
    data = {
      action = "deleted",
      repository = repository,
      sender = sender,
    },
    timestamp = gerrit_event_timestamp(payload),
  })
end

local function gerrit_project_head_updated_event(payload)
  payload = payload or {}
  local repository = gerrit_project_repo(payload)
  local sender = translate_gerrit_user(payload.submitter or payload.updater or payload.updatedBy)
  return make_internal_event({
    event = "repository",
    action = "edited",
    provider = "gerrit",
    raw = payload,
    data = {
      action = "edited",
      repository = repository,
      sender = sender,
      changes = {
        repository = {
          default_branch = {
            from = gerrit_short_ref(payload.oldHead),
          },
        },
      },
      project_head = payload.newHead or "",
    },
    timestamp = gerrit_event_timestamp(payload),
  })
end

local function gerrit_topic_changed_event(payload)
  payload = payload or {}
  return gerrit_pull_request_event(payload, "edited", {
    changes = {
      topic = {
        from = payload.oldTopic or "",
        to = (payload.change or {}).topic or "",
      },
    },
  })
end

local function gerrit_hashtags_changed_event(payload)
  payload = payload or {}
  local added = payload.added or {}
  local removed = payload.removed or {}
  local action = #added > 0 and "labeled" or (#removed > 0 and "unlabeled" or "edited")
  local label_name = (#added > 0 and added[1]) or (#removed > 0 and removed[1]) or nil
  return gerrit_pull_request_event(payload, action, {
    label = label_name and translate_gerrit_label(label_name) or nil,
    labels = gerrit_hashtags(payload.hashtags),
    changes = {
      labels = {
        added = gerrit_hashtags(added),
        removed = gerrit_hashtags(removed),
      },
    },
  })
end

local function gerrit_wip_state_changed_event(payload)
  payload = payload or {}
  return gerrit_pull_request_event(payload, "edited", {
    changes = {
      draft = {
        to = (payload.change or {}).wip or false,
      },
    },
  })
end

local function gerrit_private_state_changed_event(payload)
  payload = payload or {}
  return gerrit_pull_request_event(payload, "edited", {
    changes = {
      private = {
        to = (payload.change or {}).private or false,
      },
    },
  })
end

local function gerrit_assignee_changed_event(payload)
  payload = payload or {}
  local assignee = payload.assignee and translate_gerrit_user(payload.assignee) or nil
  local action = assignee and "assigned" or "unassigned"
  return gerrit_pull_request_event(payload, action, {
    assignee = assignee,
    changes = {
      assignee = {
        from = payload.oldAssignee and translate_gerrit_user(payload.oldAssignee) or nil,
        to = assignee,
      },
    },
  })
end

local translate_gerrit_review = make_translator({
  id = const(0),
  node_id = const(""),
  user = nested(translate_gerrit_user, "author"),
  body = field("comment", { default = "" }),
  state = computed(function(_payload, state)
    return state
  end),
  submitted_at = computed(function(payload)
    return gerrit_patchset_timestamp(payload.patchSet)
  end),
  html_url = const(""),
  pull_request_url = const(""),
})

local function gerrit_vote_deleted_event(payload)
  payload = payload or {}
  local reviewer = payload.reviewer or {}
  local remover = payload.remover or {}
  local pr, repo = gerrit_change(payload.change, payload.patchSet)
  local review = {
    id = 0,
    node_id = "",
    user = translate_gerrit_user(reviewer),
    body = payload.comment or "",
    state = "DISMISSED",
    submitted_at = gerrit_event_timestamp(payload),
    html_url = "",
    pull_request_url = "",
  }
  return make_internal_event({
    event = "pull_request_review",
    action = "dismissed",
    provider = "gerrit",
    raw = payload,
    data = {
      action = "dismissed",
      review = review,
      pull_request = pr,
      repository = repo,
      sender = translate_gerrit_user(remover),
      reviewer = translate_gerrit_user(reviewer),
      approvals = payload.approvals or {},
    },
    timestamp = review.submitted_at,
  })
end

b:webhook("comment-added", function(payload)
  local state = gerrit_approval_state(payload.approvals)
  local author = payload.author or {}
  local pr, repo = gerrit_change(payload.change, payload.patchSet)
  local review = translate_gerrit_review(payload, state)
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

local GERRIT_ACTIONLESS_NORMALIZED_EVENTS = {
  create = true,
  delete = true,
  push = true,
}

local GERRIT_NORMALIZED_WEBHOOK_EVENTS = {
  "create",
  "delete",
  "pull_request",
  "pull_request_review",
  "push",
  "repository",
}

b:webhook("patchset-created", function(payload)
  local patch_number = tonumber(((payload or {}).patchSet or {}).number) or 0
  local action = patch_number <= 1 and "opened" or "synchronize"
  return gerrit_pull_request_event(payload, action)
end)

b:webhook("change-merged", function(payload)
  return gerrit_pull_request_event(payload, "closed", {
    state = "closed",
    closed_at = true,
    merged = true,
  })
end)

b:webhook("change-abandoned", function(payload)
  return gerrit_pull_request_event(payload, "closed", {
    state = "closed",
    closed_at = true,
  })
end)

b:webhook("change-restored", function(payload)
  return gerrit_pull_request_event(payload, "reopened")
end)

b:webhook("reviewer-added", function(payload)
  return gerrit_reviewer_event(payload, "review_requested")
end)

b:webhook("reviewer-deleted", function(payload)
  return gerrit_reviewer_event(payload, "review_request_removed")
end)

b:webhook("vote-deleted", gerrit_vote_deleted_event)

b:webhook("ref-updated", function(payload)
  return gerrit_ref_update_event(payload, (payload or {}).refUpdate)
end)

b:webhook("batch-ref-updated", function(payload)
  return gerrit_ref_update_event(payload, ((payload or {}).refUpdates or {})[1])
end)

b:webhook("project-created", gerrit_project_created_event)

b:webhook("project-deleted", gerrit_project_deleted_event)

b:webhook("project-head-updated", gerrit_project_head_updated_event)

b:webhook("topic-changed", gerrit_topic_changed_event)

b:webhook("hashtags-changed", gerrit_hashtags_changed_event)

b:webhook("wip-state-changed", gerrit_wip_state_changed_event)

b:webhook("private-state-changed", gerrit_private_state_changed_event)

b:webhook("assignee-changed", gerrit_assignee_changed_event)

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
      or (
        GERRIT_ACTIONLESS_NORMALIZED_EVENTS[internal_event.event]
          and normalized_webhook_event_type(internal_event.event, "")
        or normalized_webhook_event_type(internal_event.event, internal_event.action)
      ),
    occurred_at = fields.occurred_at,
    actor = fields.actor or data.sender,
    repository = fields.repository or data.repository,
    payload = fields.payload or gerrit_normalized_payload_without_envelope_fields(data),
  })
end

local function translate_gerrit_github_webhook(internal_event, fields)
  return github_webhook_payload(internal_event, fields)
end

for _, event in ipairs(GERRIT_NORMALIZED_WEBHOOK_EVENTS) do
  b:webhook_translator(event, translate_gerrit_normalized_webhook)
  b:webhook_github_translator(event, translate_gerrit_github_webhook)
end

b:build()
