-- Kallithea backend handler overrides.
local b = make_backend_builder()
b:rest("get_root", function()
  proxy_health_check(pcall(Fetch, config.base_url .. "/_admin/api", make_fetch_opts("bearer")))
end)

-- Issues -----------------------------------------------------------------------
-- Kallithea has no native issue tracker.
-- All issues, labels, milestones, and assignees endpoints fall back to the
-- default empty-list / 404 handlers defined in .init.lua.

local ZERO_SHA = "0000000000000000000000000000000000000000"

local function split_repo_name(name)
  local owner, repo = (name or ""):match("^([^/]+)/(.+)$")
  return owner or "", repo or (name or "")
end

local function ref_name(ref)
  return (ref or ""):match("^refs/heads/(.+)$")
    or (ref or ""):match("^refs/tags/(.+)$")
    or (ref or "")
end

local function ref_type(ref)
  if (ref or ""):match("^refs/tags/") then
    return "tag"
  end
  return "branch"
end

local function full_ref(ref)
  if ref.ref and ref.ref ~= "" then
    return ref.ref
  elseif ref.ref_name and ref.ref_name ~= "" then
    return ref.ref_name
  elseif ref.type == "tags" then
    return "refs/tags/" .. (ref.name or "")
  end
  return "refs/heads/" .. (ref.name or "")
end

local function kallithea_user_login(payload)
  return (payload or {}).username or (payload or {}).user or ""
end

local function kallithea_user_url(login)
  return login ~= "" and (config.base_url .. "/_admin/users/edit/" .. login) or ""
end

local translate_kallithea_user = make_translator({
  login = computed(kallithea_user_login),
  id = const(0),
  node_id = const(""),
  avatar_url = const(""),
  html_url = computed(function(payload)
    return kallithea_user_url(kallithea_user_login(payload))
  end),
  type = const("User"),
  site_admin = const(false),
  name = computed(kallithea_user_login),
  email = field("email", { default = "" }),
  blog = const(""),
})

local translate_kallithea_named_user = make_translator({
  login = computed(function(login)
    return login or ""
  end),
  id = const(0),
  node_id = const(""),
  avatar_url = const(""),
  html_url = computed(function(login)
    return kallithea_user_url(login or "")
  end),
  type = const("User"),
  site_admin = const(false),
  name = computed(function(login)
    return login or ""
  end),
  email = computed(function(_login, email)
    return email or ""
  end),
  blog = const(""),
})

local function kallithea_repo_full_name(payload)
  return (payload or {}).repo_name or (payload or {}).repository or ""
end

local translate_kallithea_repo_owner = make_translator({
  login = computed(function(payload)
    local owner = split_repo_name(kallithea_repo_full_name(payload))
    return owner
  end),
  id = field("owner_id", { default = 0 }),
  node_id = const(""),
  avatar_url = const(""),
  url = const(""),
  html_url = computed(function(payload)
    local owner = split_repo_name(kallithea_repo_full_name(payload))
    return kallithea_user_url(owner)
  end),
  type = const("User"),
})

local translate_kallithea_repo = make_translator({
  id = field("repo_id", { default = 0 }),
  node_id = const(""),
  name = computed(function(payload)
    local _, repo_name = split_repo_name(kallithea_repo_full_name(payload))
    return repo_name
  end),
  full_name = computed(kallithea_repo_full_name),
  private = field("private", { default = false }),
  owner = computed(function(payload)
    return translate_kallithea_repo_owner(payload)
  end),
  html_url = computed(function(payload)
    local full_name = kallithea_repo_full_name(payload)
    return full_name ~= "" and (config.base_url .. "/" .. full_name) or ""
  end),
  description = "description",
  fork = computed(function(payload)
    return payload.fork_id ~= nil
  end),
  url = const(""),
  git_url = const(""),
  ssh_url = const(""),
  clone_url = computed(function(payload)
    local full_name = kallithea_repo_full_name(payload)
    return payload.clone_uri or (full_name ~= "" and (config.base_url .. "/" .. full_name) or "")
  end),
  homepage = const(""),
  size = const(0),
  stargazers_count = const(0),
  watchers_count = const(0),
  language = const(nil),
  has_issues = const(false),
  has_wiki = field("enable_downloads", { default = false }),
  forks_count = const(0),
  archived = const(false),
  disabled = const(false),
  open_issues_count = const(0),
  default_branch = field("default_branch", { default = "main" }),
  visibility = computed(function(payload)
    return payload.private and "private" or "public"
  end),
  forks = const(0),
  open_issues = const(0),
  watchers = const(0),
  created_at = "created_on",
  updated_at = "updated_on",
  pushed_at = "pushed_at",
})

local function timestamp_string(value)
  if value == nil then
    return ""
  end
  return tostring(value)
end

local translate_kallithea_push_commit_actor = make_translator({
  name = field("name", { default = "" }),
  email = field("email", { default = "" }),
  username = field("username", { default = "" }),
})

local translate_kallithea_push_commit = make_translator({
  id = computed(function(c)
    return c.id or c.sha or ""
  end),
  message = field("message", { default = "" }),
  timestamp = computed(function(c)
    return c.timestamp or c.date or ""
  end),
  url = field("url", { default = "" }),
  author = computed(function(c)
    return translate_kallithea_push_commit_actor(c.author or {})
  end),
  committer = computed(function(c)
    return translate_kallithea_push_commit_actor(c.committer or c.author or {})
  end),
  added = computed(function(c)
    return c.added or {}
  end),
  removed = computed(function(c)
    return c.removed or {}
  end),
  modified = computed(function(c)
    return c.modified or {}
  end),
})

local function ref_from_pushed_rev(rev)
  local action, name = tostring(rev or ""):match("^([^=]+)=>(.+)$")
  if action == "delete_branch" then
    return {
      ref = "refs/heads/" .. name,
      old_rev = "",
      new_rev = ZERO_SHA,
    }
  elseif action == "delete_tag" then
    return {
      ref = "refs/tags/" .. name,
      old_rev = "",
      new_rev = ZERO_SHA,
    }
  elseif action == "tag" then
    return {
      ref = "refs/tags/" .. name,
      old_rev = ZERO_SHA,
      new_rev = "",
    }
  end
  return nil
end

local function first_ref_update(payload)
  for _, r in ipairs(payload.refs or {}) do
    if type(r) == "table" then
      return r
    end
  end
  for _, rev in ipairs(payload.pushed_revs or {}) do
    local r = ref_from_pushed_rev(rev)
    if r then
      return r
    end
  end
  return nil
end

local function kallithea_ref_webhook(payload)
  local ref = first_ref_update(payload)
  if not ref then
    return nil, "No Kallithea ref update"
  end

  local raw_ref = full_ref(ref)
  local before = ref.old_rev or ref.old or ""
  local after = ref.new_rev or ref.new or ""
  local repository = translate_kallithea_repo(payload)
  local sender = translate_kallithea_user(payload)

  if before == ZERO_SHA then
    return make_internal_event({
      event = "create",
      action = "create",
      provider = "kallithea",
      raw = payload,
      data = {
        ref = ref_name(raw_ref),
        ref_type = ref_type(raw_ref),
        master_branch = repository.default_branch or "",
        description = repository.description,
        pusher_type = "user",
        repository = repository,
        sender = sender,
      },
      timestamp = "",
    })
  end

  if after == ZERO_SHA then
    return make_internal_event({
      event = "delete",
      action = "delete",
      provider = "kallithea",
      raw = payload,
      data = {
        ref = ref_name(raw_ref),
        ref_type = ref_type(raw_ref),
        master_branch = repository.default_branch or "",
        description = repository.description,
        pusher_type = "user",
        repository = repository,
        sender = sender,
      },
      timestamp = "",
    })
  end

  local commits = {}
  for _, c in ipairs(payload.commits or {}) do
    commits[#commits + 1] = translate_kallithea_push_commit(c)
  end
  local head_commit = #commits > 0 and commits[#commits] or nil
  return make_internal_event({
    event = "push",
    action = "push",
    provider = "kallithea",
    raw = payload,
    data = {
      ref = raw_ref,
      before = before,
      after = after,
      created = false,
      deleted = false,
      forced = payload.forced or false,
      compare = "",
      commits = commits,
      head_commit = head_commit,
      pusher = {
        name = payload.username or "",
        email = payload.email or "",
      },
      repository = repository,
      sender = sender,
    },
    timestamp = head_commit and head_commit.timestamp or "",
  })
end

local function kallithea_repo_lifecycle_handler(action)
  return function(payload)
    return make_internal_event({
      event = "repository",
      action = action,
      provider = "kallithea",
      raw = payload,
      data = {
        action = action,
        repository = translate_kallithea_repo(payload),
        sender = translate_kallithea_named_user(
          payload.created_by or payload.deleted_by or payload.username or ""
        ),
      },
      timestamp = timestamp_string(payload.updated_on or payload.deleted_on or payload.created_on),
    })
  end
end

local translate_kallithea_pr_branch = make_translator({
  label = computed(function(repo_name, ref)
    repo_name = repo_name or ""
    return repo_name ~= "" and (repo_name .. ":" .. (ref or "")) or (ref or "")
  end),
  ref = computed(function(_repo_name, ref)
    return ref or ""
  end),
  sha = const(""),
  repo = computed(function(repo_name)
    repo_name = repo_name or ""
    return translate_kallithea_repo({ repo_name = repo_name })
  end),
})

local function kallithea_payload_pr(payload)
  return (payload or {}).pull_request or {}
end

local function kallithea_pr_status(payload)
  return kallithea_payload_pr(payload).status or "new"
end

local function kallithea_pr_state(payload)
  local status = kallithea_pr_status(payload)
  return (status == "closed" or status == "merged") and "closed" or "open"
end

local function kallithea_pr_target_repo(payload)
  local pr = kallithea_payload_pr(payload)
  return pr.org_repo_name or payload.repository or ""
end

local function kallithea_pr_source_repo(payload)
  local pr = kallithea_payload_pr(payload)
  return pr.other_repo_name or payload.source_repository or kallithea_pr_target_repo(payload)
end

local function kallithea_pr_number(payload)
  local pr = kallithea_payload_pr(payload)
  return payload.pull_request_id or pr.id or 0
end

local translate_kallithea_pull_request = make_translator({
  id = computed(function(payload)
    local pr = kallithea_payload_pr(payload)
    return pr.id or payload.pull_request_id or 0
  end),
  node_id = const(""),
  number = computed(kallithea_pr_number),
  state = computed(kallithea_pr_state),
  locked = const(false),
  title = computed(function(payload)
    return kallithea_payload_pr(payload).title or ""
  end),
  body = computed(function(payload)
    return kallithea_payload_pr(payload).description or ""
  end),
  user = computed(function(payload)
    local pr = kallithea_payload_pr(payload)
    return translate_kallithea_named_user(pr.owner or payload.created_by or "")
  end),
  head = computed(function(payload)
    local pr = kallithea_payload_pr(payload)
    return translate_kallithea_pr_branch(
      kallithea_pr_source_repo(payload),
      pr.other_ref or payload.source_ref
    )
  end),
  base = computed(function(payload)
    local pr = kallithea_payload_pr(payload)
    return translate_kallithea_pr_branch(
      kallithea_pr_target_repo(payload),
      pr.org_ref or payload.target_ref
    )
  end),
  draft = const(false),
  created_at = computed(function(payload)
    return kallithea_payload_pr(payload).created_on or ""
  end),
  updated_at = computed(function(payload)
    return kallithea_payload_pr(payload).updated_on or ""
  end),
  closed_at = computed(function(payload)
    local pr = kallithea_payload_pr(payload)
    return kallithea_pr_state(payload) == "closed" and (pr.updated_on or "") or nil
  end),
  merged_at = computed(function(payload)
    local pr = kallithea_payload_pr(payload)
    return kallithea_pr_status(payload) == "merged" and (pr.updated_on or "") or nil
  end),
  merge_commit_sha = const(nil),
  merged_by = const(nil),
  diff_url = const(""),
  patch_url = const(""),
  html_url = computed(function(payload)
    local target_repo = kallithea_pr_target_repo(payload)
    local number = kallithea_pr_number(payload)
    return target_repo ~= ""
        and (config.base_url .. "/" .. target_repo .. "/pull-request/" .. number)
      or ""
  end),
  url = const(""),
  mergeable = computed(function(payload)
    return kallithea_pr_state(payload) == "open" or nil
  end),
  comments = const(0),
  review_comments = const(0),
  commits = const(0),
  additions = const(0),
  deletions = const(0),
  changed_files = const(0),
})

local function kallithea_pull_request_event(payload, action)
  local pr = payload.pull_request or {}
  return make_internal_event({
    event = "pull_request",
    action = action,
    provider = "kallithea",
    raw = payload,
    data = {
      action = action,
      number = payload.pull_request_id or pr.id,
      pull_request = translate_kallithea_pull_request(payload),
      repository = translate_kallithea_repo({ repo_name = payload.repository or pr.org_repo_name }),
      sender = translate_kallithea_named_user(payload.created_by or pr.owner or ""),
    },
    timestamp = pr.updated_on or pr.created_on or "",
  })
end

b:webhook("push", kallithea_ref_webhook)
b:webhook("PUSH_HOOK", kallithea_ref_webhook)
b:webhook("repository", function(payload)
  local action = payload.action or "unknown"
  if action == "created" then
    return kallithea_repo_lifecycle_handler("created")(payload)
  elseif action == "deleted" then
    return kallithea_repo_lifecycle_handler("deleted")(payload)
  end
  return make_internal_event({
    event = "repository",
    action = "unknown",
    raw_action = action,
    provider = "kallithea",
    raw = payload,
    data = {
      action = "unknown",
      repository = translate_kallithea_repo(payload),
      sender = translate_kallithea_named_user(payload.created_by or payload.deleted_by or ""),
    },
    timestamp = timestamp_string(payload.updated_on or payload.deleted_on or payload.created_on),
  })
end)
b:webhook("CREATE_REPO_HOOK", kallithea_repo_lifecycle_handler("created"))
b:webhook("DELETE_REPO_HOOK", kallithea_repo_lifecycle_handler("deleted"))
b:webhook("pull_request", function(payload)
  return kallithea_pull_request_event(payload, payload.action or "opened")
end)
b:webhook("CREATE_PULLREQUEST_HOOK", function(payload)
  return kallithea_pull_request_event(payload, "opened")
end)

local function kallithea_normalized_payload_without_envelope_fields(data)
  local payload = {}
  for k, v in pairs(data or {}) do
    if k ~= "sender" and k ~= "repository" then
      payload[k] = v
    end
  end
  return payload
end

local KALLITHEA_ACTIONLESS_NORMALIZED_EVENTS = {
  create = true,
  delete = true,
  push = true,
}

local function translate_kallithea_normalized_webhook(internal_event, fields)
  local data = internal_event.data or {}
  fields = fields or {}
  return make_normalized_webhook_envelope(internal_event, {
    id = fields.id,
    type = fields.type
      or (
        KALLITHEA_ACTIONLESS_NORMALIZED_EVENTS[internal_event.event]
          and normalized_webhook_event_type(internal_event.event, "")
        or normalized_webhook_event_type(internal_event.event, internal_event.action)
      ),
    occurred_at = fields.occurred_at,
    actor = fields.actor or data.sender,
    repository = fields.repository or data.repository,
    payload = fields.payload or kallithea_normalized_payload_without_envelope_fields(data),
  })
end

local function translate_kallithea_github_webhook(internal_event, fields)
  return github_webhook_payload(internal_event, fields)
end

for _, event in ipairs({ "push", "create", "delete", "repository", "pull_request" }) do
  b:webhook_translator(event, translate_kallithea_normalized_webhook)
  b:webhook_github_translator(event, translate_kallithea_github_webhook)
end

b:build()
