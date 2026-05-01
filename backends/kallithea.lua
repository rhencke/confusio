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

local function translate_kallithea_user(payload)
  local login = payload.username or payload.user or ""
  return {
    login = login,
    id = 0,
    node_id = "",
    avatar_url = "",
    html_url = login ~= "" and (config.base_url .. "/_admin/users/edit/" .. login) or "",
    type = "User",
    site_admin = false,
    name = login,
    email = payload.email or "",
    blog = "",
  }
end

local function translate_kallithea_named_user(login, email)
  login = login or ""
  return {
    login = login,
    id = 0,
    node_id = "",
    avatar_url = "",
    html_url = login ~= "" and (config.base_url .. "/_admin/users/edit/" .. login) or "",
    type = "User",
    site_admin = false,
    name = login,
    email = email or "",
    blog = "",
  }
end

local function translate_kallithea_repo(payload)
  local full_name = payload.repo_name or payload.repository or ""
  local owner, repo_name = split_repo_name(full_name)
  return {
    id = payload.repo_id or 0,
    node_id = "",
    name = repo_name,
    full_name = full_name,
    private = payload.private or false,
    owner = {
      login = owner,
      id = payload.owner_id or 0,
      node_id = "",
      avatar_url = "",
      url = "",
      html_url = owner ~= "" and (config.base_url .. "/_admin/users/edit/" .. owner) or "",
      type = "User",
    },
    html_url = full_name ~= "" and (config.base_url .. "/" .. full_name) or "",
    description = payload.description,
    fork = payload.fork_id ~= nil,
    url = "",
    git_url = "",
    ssh_url = "",
    clone_url = payload.clone_uri
      or (full_name ~= "" and (config.base_url .. "/" .. full_name) or ""),
    homepage = "",
    size = 0,
    stargazers_count = 0,
    watchers_count = 0,
    language = nil,
    has_issues = false,
    has_wiki = payload.enable_downloads or false,
    forks_count = 0,
    archived = false,
    disabled = false,
    open_issues_count = 0,
    default_branch = payload.default_branch or "main",
    visibility = payload.private and "private" or "public",
    forks = 0,
    open_issues = 0,
    watchers = 0,
    created_at = payload.created_on,
    updated_at = payload.updated_on,
    pushed_at = payload.pushed_at,
  }
end

local function timestamp_string(value)
  if value == nil then
    return ""
  end
  return tostring(value)
end

local function translate_kallithea_push_commit(c)
  if not c then
    return {}
  end
  local author = c.author or {}
  local committer = c.committer or author
  return {
    id = c.id or c.sha or "",
    message = c.message or "",
    timestamp = c.timestamp or c.date or "",
    url = c.url or "",
    author = {
      name = author.name or "",
      email = author.email or "",
      username = author.username or "",
    },
    committer = {
      name = committer.name or "",
      email = committer.email or "",
      username = committer.username or "",
    },
    added = c.added or {},
    removed = c.removed or {},
    modified = c.modified or {},
  }
end

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
          payload.created_by or payload.deleted_by or payload.username
        ),
      },
      timestamp = timestamp_string(payload.updated_on or payload.deleted_on or payload.created_on),
    })
  end
end

local function translate_kallithea_pr_branch(repo_name, ref)
  return {
    label = repo_name ~= "" and (repo_name .. ":" .. (ref or "")) or (ref or ""),
    ref = ref or "",
    sha = "",
    repo = translate_kallithea_repo({ repo_name = repo_name }),
  }
end

local function translate_kallithea_pull_request(payload)
  local pr = payload.pull_request or {}
  local status = pr.status or "new"
  local state = (status == "closed" or status == "merged") and "closed" or "open"
  local target_repo = pr.org_repo_name or payload.repository or ""
  local source_repo = pr.other_repo_name or payload.source_repository or target_repo
  local number = payload.pull_request_id or pr.id or 0
  return {
    id = pr.id or payload.pull_request_id or 0,
    node_id = "",
    number = number,
    state = state,
    locked = false,
    title = pr.title or "",
    body = pr.description or "",
    user = translate_kallithea_named_user(pr.owner or payload.created_by),
    head = translate_kallithea_pr_branch(source_repo, pr.other_ref or payload.source_ref),
    base = translate_kallithea_pr_branch(target_repo, pr.org_ref or payload.target_ref),
    draft = false,
    created_at = pr.created_on or "",
    updated_at = pr.updated_on or "",
    closed_at = state == "closed" and (pr.updated_on or "") or nil,
    merged_at = status == "merged" and (pr.updated_on or "") or nil,
    merge_commit_sha = nil,
    merged_by = nil,
    diff_url = "",
    patch_url = "",
    html_url = target_repo ~= ""
        and (config.base_url .. "/" .. target_repo .. "/pull-request/" .. number)
      or "",
    url = "",
    mergeable = state == "open" or nil,
    comments = 0,
    review_comments = 0,
    commits = 0,
    additions = 0,
    deletions = 0,
    changed_files = 0,
  }
end

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
      sender = translate_kallithea_named_user(payload.created_by or pr.owner),
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
      sender = translate_kallithea_named_user(payload.created_by or payload.deleted_by),
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

for _, event in ipairs({ "push", "create", "delete", "repository", "pull_request" }) do
  b:webhook_translator(event, translate_kallithea_normalized_webhook)
end

b:build()
