-- RhodeCode backend handler overrides.
local b = make_backend_builder()
b:rest("get_root", function()
  proxy_health_check(pcall(Fetch, config.base_url .. "/_admin/api", make_fetch_opts("bearer")))
end)

-- Issues -----------------------------------------------------------------------
-- RhodeCode has no native issue tracker; it integrates with external trackers
-- such as JIRA. All issues, labels, milestones, and assignees endpoints fall
-- back to the default empty-list / 404 handlers defined in .init.lua.

local ZERO_SHA = "0000000000000000000000000000000000000000"

local function first_non_empty(...)
  for i = 1, select("#", ...) do
    local value = select(i, ...)
    if value ~= nil and value ~= "" then
      return value
    end
  end
  return nil
end

local function is_zero_sha(value)
  return value == ZERO_SHA
end

local function bool_value(value)
  if value == true or value == 1 then
    return true
  end
  if type(value) == "string" then
    local lower = value:lower()
    return lower == "true" or lower == "1" or lower == "yes"
  end
  return false
end

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
  elseif ref.ref_name_full and ref.ref_name_full ~= "" then
    return ref.ref_name_full
  elseif ref.branch and ref.branch ~= "" then
    return "refs/heads/" .. ref.branch
  elseif
    ref.type == "tag"
    or ref.type == "tags"
    or ref.ref_type == "tag"
    or ref.ref_type == "tags"
  then
    return "refs/tags/" .. (ref.name or "")
  end
  return "refs/heads/" .. (ref.name or "")
end

local function rhodecode_user_login(payload)
  if type(payload) == "string" then
    return payload
  end
  payload = payload or {}
  return payload.username
    or payload.user
    or payload.user_name
    or payload.actor
    or payload.created_by
    or payload.deleted_by
    or payload.owner
    or ""
end

local function rhodecode_user_url(login)
  return login ~= "" and (config.base_url .. "/_admin/users/edit/" .. login) or ""
end

local translate_rhodecode_user = make_translator({
  login = computed(rhodecode_user_login),
  id = const(0),
  node_id = const(""),
  avatar_url = const(""),
  html_url = computed(function(payload)
    return rhodecode_user_url(rhodecode_user_login(payload))
  end),
  type = const("User"),
  site_admin = const(false),
  name = computed(rhodecode_user_login),
  email = computed(function(payload)
    if type(payload) == "table" then
      return payload.email or ""
    end
    return ""
  end),
  blog = const(""),
})

local function rhodecode_user(payload)
  return translate_rhodecode_user(payload or "")
end

local repo_name_from_payload
local repo_table
local pr_repo_name

local function rhodecode_repo_source(payload)
  return repo_table(payload)
end

local function rhodecode_repo_private(payload)
  local source = rhodecode_repo_source(payload)
  return bool_value(source.private or source.repo_private or source.is_private)
end

local function rhodecode_repo_full_name(payload)
  return repo_name_from_payload(payload)
end

local translate_rhodecode_repo_owner = make_translator({
  login = computed(function(payload)
    local owner = split_repo_name(rhodecode_repo_full_name(payload))
    return owner
  end),
  id = computed(function(payload)
    return rhodecode_repo_source(payload).owner_id or 0
  end),
  node_id = const(""),
  avatar_url = const(""),
  url = const(""),
  html_url = computed(function(payload)
    local owner = split_repo_name(rhodecode_repo_full_name(payload))
    return rhodecode_user_url(owner)
  end),
  type = const("User"),
})

local translate_rhodecode_repo = make_translator({
  id = computed(function(payload)
    local source = rhodecode_repo_source(payload)
    return source.repo_id or source.repository_id or source.id or 0
  end),
  node_id = const(""),
  name = computed(function(payload)
    local _, repo_name = split_repo_name(rhodecode_repo_full_name(payload))
    return repo_name
  end),
  full_name = computed(rhodecode_repo_full_name),
  private = computed(rhodecode_repo_private),
  owner = computed(function(payload)
    return translate_rhodecode_repo_owner(payload)
  end),
  html_url = computed(function(payload)
    local source = rhodecode_repo_source(payload)
    local full_name = rhodecode_repo_full_name(payload)
    return source.html_url or (full_name ~= "" and (config.base_url .. "/" .. full_name) or "")
  end),
  description = computed(function(payload)
    return rhodecode_repo_source(payload).description
  end),
  fork = computed(function(payload)
    return rhodecode_repo_source(payload).fork_id ~= nil
  end),
  url = const(""),
  git_url = const(""),
  ssh_url = const(""),
  clone_url = computed(function(payload)
    local source = rhodecode_repo_source(payload)
    local full_name = rhodecode_repo_full_name(payload)
    return source.clone_uri
      or source.clone_url
      or (full_name ~= "" and (config.base_url .. "/" .. full_name) or "")
  end),
  homepage = const(""),
  size = const(0),
  stargazers_count = const(0),
  watchers_count = const(0),
  language = const(nil),
  has_issues = const(false),
  has_wiki = computed(function(payload)
    return bool_value(rhodecode_repo_source(payload).enable_downloads)
  end),
  forks_count = const(0),
  archived = const(false),
  disabled = const(false),
  open_issues_count = const(0),
  default_branch = computed(function(payload)
    return rhodecode_repo_source(payload).default_branch or "main"
  end),
  visibility = computed(function(payload)
    return rhodecode_repo_private(payload) and "private" or "public"
  end),
  forks = const(0),
  open_issues = const(0),
  watchers = const(0),
  created_at = computed(function(payload)
    return rhodecode_repo_source(payload).created_on
  end),
  updated_at = computed(function(payload)
    return rhodecode_repo_source(payload).updated_on
  end),
  pushed_at = computed(function(payload)
    return rhodecode_repo_source(payload).pushed_at
  end),
})

local function rhodecode_commit_author(c)
  return (c or {}).author or {}
end

local function rhodecode_commit_committer(c)
  return (c or {}).committer or rhodecode_commit_author(c)
end

local translate_rhodecode_push_commit_author = make_translator({
  name = computed(function(c)
    local author = rhodecode_commit_author(c)
    return author.name or c.author_name or ""
  end),
  email = computed(function(c)
    local author = rhodecode_commit_author(c)
    return author.email or c.author_email or ""
  end),
  username = computed(function(c)
    return rhodecode_commit_author(c).username or ""
  end),
})

local translate_rhodecode_push_commit_committer = make_translator({
  name = computed(function(c)
    local committer = rhodecode_commit_committer(c)
    local author = rhodecode_commit_author(c)
    return committer.name or c.committer_name or author.name or ""
  end),
  email = computed(function(c)
    local committer = rhodecode_commit_committer(c)
    local author = rhodecode_commit_author(c)
    return committer.email or c.committer_email or author.email or ""
  end),
  username = computed(function(c)
    local committer = rhodecode_commit_committer(c)
    local author = rhodecode_commit_author(c)
    return committer.username or author.username or ""
  end),
})

local translate_rhodecode_push_commit = make_translator({
  id = computed(function(c)
    return c.id or c.sha or c.raw_id or ""
  end),
  message = field("message", { default = "" }),
  timestamp = computed(function(c)
    return c.timestamp or c.date or c.created_on or ""
  end),
  url = field("url", { default = "" }),
  author = computed(function(c)
    return translate_rhodecode_push_commit_author(c)
  end),
  committer = computed(function(c)
    return translate_rhodecode_push_commit_committer(c)
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

local translate_pr_branch = make_translator({
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
    return translate_rhodecode_repo({ repo_name = repo_name })
  end),
})

local function rhodecode_payload_pr(payload)
  return (payload or {}).pull_request or payload or {}
end

local function rhodecode_pr_status(payload)
  local pr = rhodecode_payload_pr(payload)
  return pr.status or (payload or {}).status or "new"
end

local function rhodecode_pr_state(payload)
  local status = rhodecode_pr_status(payload)
  return (status == "closed" or status == "merged") and "closed" or "open"
end

local function rhodecode_pr_target_repo(payload)
  local pr = rhodecode_payload_pr(payload)
  local target_repo = pr_repo_name(pr.org_repo_name or pr.target_repo or (payload or {}).repository)
  if target_repo == "" then
    target_repo = repo_name_from_payload(payload)
  end
  return target_repo
end

local function rhodecode_pr_source_repo(payload)
  local pr = rhodecode_payload_pr(payload)
  local source_repo =
    pr_repo_name(pr.other_repo_name or pr.source_repo or (payload or {}).source_repository)
  if source_repo == "" then
    source_repo = rhodecode_pr_target_repo(payload)
  end
  return source_repo
end

local function rhodecode_pr_number(payload)
  local pr = rhodecode_payload_pr(payload)
  return (payload or {}).pull_request_id or pr.pull_request_id or pr.id or 0
end

local function rhodecode_pr_updated_at(payload)
  local pr = rhodecode_payload_pr(payload)
  return pr.updated_on or pr.updated_at or (payload or {}).updated_on or ""
end

local function rhodecode_pr_merged(payload)
  local pr = rhodecode_payload_pr(payload)
  return rhodecode_pr_status(payload) == "merged"
    or (payload or {}).action == "merged"
    or pr.action == "merged"
end

function repo_name_from_payload(payload)
  payload = payload or {}
  local repo = payload.repo or payload.repository or payload.project
  if type(repo) == "table" then
    return first_non_empty(
      repo.full_name,
      repo.repo_name,
      repo.repo_name_with_group,
      repo.path_with_namespace,
      repo.name
    ) or ""
  end
  return first_non_empty(
    payload.repo_name,
    payload.repo_name_with_group,
    payload.path_with_namespace,
    repo
  ) or ""
end

function repo_table(payload)
  payload = payload or {}
  local repo = payload.repo or payload.repository or payload.project
  if type(repo) == "table" then
    return repo
  end
  return payload
end

local function ref_from_pushed_rev(rev)
  local action, name = tostring(rev or ""):match("^([^=]+)=>(.+)$")
  if action == "delete_branch" then
    return { ref = "refs/heads/" .. name, old_rev = "", new_rev = ZERO_SHA }
  elseif action == "delete_tag" then
    return { ref = "refs/tags/" .. name, old_rev = "", new_rev = ZERO_SHA }
  elseif action == "tag" then
    return { ref = "refs/tags/" .. name, old_rev = ZERO_SHA, new_rev = "" }
  elseif action == "branch" or action == "new_branch" then
    return { ref = "refs/heads/" .. name, old_rev = ZERO_SHA, new_rev = "" }
  end
  return nil
end

local function first_ref_update(payload)
  for _, r in ipairs(payload.refs or payload.ref_updates or {}) do
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
  if payload.ref or payload.branch then
    return payload
  end
  return nil
end

local function ref_before(ref)
  return first_non_empty(ref.old_rev, ref.old, ref.before, ref.from, ref.from_hash) or ZERO_SHA
end

local function ref_after(ref)
  return first_non_empty(
    ref.new_rev,
    ref.new,
    ref.after,
    ref.to,
    ref.to_hash,
    ref.commit_id,
    ref.sha
  )
end

local function rhodecode_ref_webhook(payload)
  local ref = first_ref_update(payload)
  if not ref then
    return nil, "No RhodeCode ref update"
  end

  local raw_ref = full_ref(ref)
  local before = ref_before(ref)
  local after = ref_after(ref) or ""
  if after == "" and before ~= "" then
    after = ZERO_SHA
  end
  local repository = translate_rhodecode_repo(payload)
  local sender = translate_rhodecode_user(payload)
  local kind = ref_type(raw_ref)
  local name = ref_name(raw_ref)

  if is_zero_sha(before) then
    return make_internal_event({
      event = "create",
      action = "create",
      provider = "rhodecode",
      raw = payload,
      data = {
        ref = name,
        ref_type = kind,
        master_branch = repository.default_branch or "",
        description = repository.description,
        pusher_type = "user",
        repository = repository,
        sender = sender,
      },
      timestamp = payload.updated_on or payload.pushed_at or payload.created_on or "",
    })
  end

  if is_zero_sha(after) then
    return make_internal_event({
      event = "delete",
      action = "delete",
      provider = "rhodecode",
      raw = payload,
      data = {
        ref = name,
        ref_type = kind,
        master_branch = repository.default_branch or "",
        description = repository.description,
        pusher_type = "user",
        repository = repository,
        sender = sender,
      },
      timestamp = payload.updated_on or payload.pushed_at or payload.deleted_on or "",
    })
  end

  local commits = {}
  for _, c in ipairs(payload.commits or ref.commits or {}) do
    commits[#commits + 1] = translate_rhodecode_push_commit(c)
  end
  local head_commit = #commits > 0 and commits[#commits] or nil
  return make_internal_event({
    event = "push",
    action = "push",
    provider = "rhodecode",
    raw = payload,
    data = {
      ref = raw_ref,
      before = before,
      after = after,
      created = false,
      deleted = false,
      forced = payload.forced or false,
      compare = payload.compare or "",
      commits = commits,
      head_commit = head_commit,
      pusher = {
        name = sender.login or "",
        email = sender.email or "",
      },
      repository = repository,
      sender = sender,
    },
    timestamp = head_commit and head_commit.timestamp
      or payload.updated_on
      or payload.pushed_at
      or "",
  })
end

function pr_repo_name(value)
  if type(value) == "table" then
    return repo_name_from_payload({ repository = value })
  end
  return value or ""
end

local function pr_branch(payload, repo_name, ref, sha)
  local branch = translate_pr_branch(repo_name, ref)
  branch.sha = sha or ""
  if branch.repo.full_name == "" then
    branch.repo = translate_rhodecode_repo(payload)
  end
  return branch
end

local function pr_action(payload, pr)
  local action = payload.action or payload.event_action or pr.action or ""
  local status = pr.status or payload.status or ""
  if
    action == "created"
    or action == "create"
    or action == "open"
    or action == "opened"
    or status == "new"
    or status == "open"
    or status == "opened"
    or (action == "" and status == "")
  then
    return "opened"
  elseif
    action == "updated"
    or action == "update"
    or action == "synchronize"
    or action == "synchronized"
    or status == "updated"
    or status == "synchronize"
    or status == "synchronized"
  then
    return "synchronize"
  elseif
    action == "merged"
    or status == "merged"
    or action == "closed"
    or action == "close"
    or status == "closed"
  then
    return "closed"
  elseif action == "reopened" or action == "reopen" or status == "reopened" then
    return "reopened"
  end
  return "unknown", action ~= "" and action or status
end

local translate_rhodecode_pull_request = make_translator({
  id = computed(rhodecode_pr_number),
  node_id = const(""),
  number = computed(rhodecode_pr_number),
  state = computed(rhodecode_pr_state),
  locked = const(false),
  title = computed(function(payload)
    return rhodecode_payload_pr(payload).title or ""
  end),
  body = computed(function(payload)
    local pr = rhodecode_payload_pr(payload)
    return pr.description or pr.body or ""
  end),
  user = computed(function(payload)
    local pr = rhodecode_payload_pr(payload)
    return rhodecode_user(pr.owner or (payload or {}).created_by or (payload or {}).username)
  end),
  head = computed(function(payload)
    local pr = rhodecode_payload_pr(payload)
    return pr_branch(
      payload,
      rhodecode_pr_source_repo(payload),
      pr.other_ref or pr.source_ref or (payload or {}).source_ref,
      pr.other_rev or pr.source_rev or pr.source_sha or (payload or {}).source_sha
    )
  end),
  base = computed(function(payload)
    local pr = rhodecode_payload_pr(payload)
    return pr_branch(
      payload,
      rhodecode_pr_target_repo(payload),
      pr.org_ref or pr.target_ref or (payload or {}).target_ref,
      pr.org_rev or pr.target_rev or pr.target_sha or (payload or {}).target_sha
    )
  end),
  draft = const(false),
  created_at = computed(function(payload)
    local pr = rhodecode_payload_pr(payload)
    return pr.created_on or pr.created_at or (payload or {}).created_on or ""
  end),
  updated_at = computed(rhodecode_pr_updated_at),
  closed_at = computed(function(payload)
    local updated_at = rhodecode_pr_updated_at(payload)
    return rhodecode_pr_state(payload) == "closed" and updated_at or nil
  end),
  merged_at = computed(function(payload)
    local updated_at = rhodecode_pr_updated_at(payload)
    return rhodecode_pr_merged(payload) and updated_at or nil
  end),
  merge_commit_sha = computed(function(payload)
    local pr = rhodecode_payload_pr(payload)
    return pr.merge_commit_id or pr.merge_commit_sha or (payload or {}).merge_commit_sha
  end),
  merged = computed(rhodecode_pr_merged),
  merged_by = computed(function(payload)
    if not rhodecode_pr_merged(payload) then
      return nil
    end
    local pr = rhodecode_payload_pr(payload)
    return rhodecode_user(pr.merged_by or (payload or {}).merged_by)
  end),
  diff_url = const(""),
  patch_url = const(""),
  html_url = computed(function(payload)
    local target_repo = rhodecode_pr_target_repo(payload)
    local number = rhodecode_pr_number(payload)
    return target_repo ~= ""
        and (config.base_url .. "/" .. target_repo .. "/pull-request/" .. number)
      or ""
  end),
  url = const(""),
  mergeable = computed(function(payload)
    return rhodecode_pr_state(payload) == "open" or nil
  end),
  comments = const(0),
  review_comments = const(0),
  commits = const(0),
  additions = const(0),
  deletions = const(0),
  changed_files = const(0),
})

local function rhodecode_pull_request_event(payload)
  local pr = payload.pull_request or payload
  local action, raw_action = pr_action(payload, pr)
  local repository_name = pr_repo_name(payload.repository or pr.org_repo_name or pr.target_repo)
  if repository_name == "" then
    repository_name = repo_name_from_payload(payload)
  end
  return make_internal_event({
    event = "pull_request",
    action = action,
    raw_action = raw_action,
    provider = "rhodecode",
    raw = payload,
    data = {
      action = action,
      number = payload.pull_request_id or pr.pull_request_id or pr.id,
      pull_request = translate_rhodecode_pull_request(payload),
      repository = translate_rhodecode_repo({ repo_name = repository_name }),
      sender = rhodecode_user(payload.created_by or pr.owner or payload.username),
    },
    timestamp = pr.updated_on or pr.updated_at or pr.created_on or pr.created_at or "",
  })
end

local function repo_action(payload, fallback)
  local action = payload.action or payload.event_action or fallback or ""
  if action == "create" or action == "created" then
    return "created"
  elseif action == "delete" or action == "deleted" or action == "destroyed" then
    return "deleted"
  end
  return nil
end

local function rhodecode_repository_event(action)
  return function(payload)
    local normalized_action = repo_action(payload, action)
    if not normalized_action then
      return nil, "Unsupported RhodeCode repository action"
    end
    return make_internal_event({
      event = "repository",
      action = normalized_action,
      provider = "rhodecode",
      raw = payload,
      data = {
        action = normalized_action,
        repository = translate_rhodecode_repo(payload),
        sender = translate_rhodecode_user(payload),
      },
      timestamp = payload.updated_on or payload.created_on or payload.deleted_on or "",
    })
  end
end

b:webhook("push", rhodecode_ref_webhook)
b:webhook("PUSH_HOOK", rhodecode_ref_webhook)
b:webhook("POST_PUSH", rhodecode_ref_webhook)
b:webhook("pull_request", rhodecode_pull_request_event)
b:webhook("CREATE_PULLREQUEST_HOOK", function(payload)
  payload.action = payload.action or "opened"
  return rhodecode_pull_request_event(payload)
end)
b:webhook("CLOSE_PULLREQUEST_HOOK", function(payload)
  payload.action = payload.action or "closed"
  return rhodecode_pull_request_event(payload)
end)
b:webhook("repository", function(payload)
  local action = repo_action(payload)
  if action then
    return rhodecode_repository_event(action)(payload)
  end
  return nil, "Unsupported RhodeCode repository action"
end)
b:webhook("CREATE_REPO_HOOK", rhodecode_repository_event("created"))
b:webhook("DELETE_REPO_HOOK", rhodecode_repository_event("deleted"))

local RHODECODE_ACTIONLESS_NORMALIZED_EVENTS = {
  create = true,
  delete = true,
  push = true,
}

local function normalized_payload_without_envelope_fields(data)
  local payload = {}
  for k, v in pairs(data or {}) do
    if k ~= "sender" and k ~= "repository" then
      payload[k] = v
    end
  end
  return payload
end

local function translate_rhodecode_normalized_webhook(internal_event, fields)
  local data = internal_event.data or {}
  fields = fields or {}
  return make_normalized_webhook_envelope(internal_event, {
    id = fields.id,
    type = fields.type
      or (
        RHODECODE_ACTIONLESS_NORMALIZED_EVENTS[internal_event.event]
          and normalized_webhook_event_type(internal_event.event, "")
        or normalized_webhook_event_type(internal_event.event, internal_event.action)
      ),
    occurred_at = fields.occurred_at,
    actor = fields.actor or data.sender,
    repository = fields.repository or data.repository,
    payload = fields.payload or normalized_payload_without_envelope_fields(data),
  })
end

local function translate_rhodecode_github_webhook(internal_event, fields)
  return github_webhook_payload(internal_event, fields)
end

for _, event in ipairs({ "push", "create", "delete", "pull_request", "repository" }) do
  b:webhook_translator(event, translate_rhodecode_normalized_webhook)
  b:webhook_github_translator(event, translate_rhodecode_github_webhook)
end

b:build()
