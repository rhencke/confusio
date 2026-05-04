-- Shared GitHub-compatible webhook payload builders.
--
-- Backend webhook normalizers already converge on internal_event.data.  This
-- module turns that common bag into GitHub-shaped payloads and entity defaults
-- so provider-specific translators only supply unusual source details.
--
-- Globals exported:
--   github_webhook_user
--   github_webhook_sender
--   github_webhook_repository
--   github_webhook_organization
--   github_webhook_issue
--   github_webhook_pull_request
--   github_webhook_label
--   github_webhook_milestone
--   github_webhook_release
--   github_webhook_deployment
--   github_webhook_deployment_status
--   github_webhook_check_run
--   github_webhook_check_suite
--   github_webhook_project
--   github_webhook_projects_v2
--   github_webhook_projects_v2_item
--   github_webhook_discussion
--   github_webhook_alert
--   github_webhook_installation
--   github_webhook_payload

local function copy_table(src)
  local out = {}
  for k, v in pairs(src or {}) do
    out[k] = v
  end
  return out
end

local function with_defaults(defaults, value, overrides)
  local out = copy_table(defaults)
  for k, v in pairs(value or {}) do
    out[k] = v
  end
  for k, v in pairs(overrides or {}) do
    out[k] = v
  end
  return out
end

local function github_webhook_url(login, path)
  if type(login) ~= "string" or login == "" then
    return ""
  end
  return "https://api.github.com/" .. path .. "/" .. login
end

local function github_webhook_url_child(login, path, suffix)
  local url = github_webhook_url(login, path)
  if url == "" then
    return ""
  end
  return url .. suffix
end

function github_webhook_user(value, overrides) -- luacheck: globals github_webhook_user
  value = value or {}
  local login = value.login or value.username or value.name or ""
  return with_defaults({
    login = login,
    id = value.id or 0,
    node_id = value.node_id or "",
    avatar_url = value.avatar_url or "",
    gravatar_id = value.gravatar_id or "",
    url = value.url or github_webhook_url(login, "users"),
    html_url = value.html_url or (login ~= "" and "https://github.com/" .. login or ""),
    followers_url = value.followers_url or github_webhook_url_child(login, "users", "/followers"),
    following_url = value.following_url
      or github_webhook_url_child(login, "users", "/following{/other_user}"),
    gists_url = value.gists_url or github_webhook_url_child(login, "users", "/gists{/gist_id}"),
    starred_url = value.starred_url
      or github_webhook_url_child(login, "users", "/starred{/owner}{/repo}"),
    subscriptions_url = value.subscriptions_url
      or github_webhook_url_child(login, "users", "/subscriptions"),
    organizations_url = value.organizations_url
      or github_webhook_url_child(login, "users", "/orgs"),
    repos_url = value.repos_url or github_webhook_url_child(login, "users", "/repos"),
    events_url = value.events_url or github_webhook_url_child(login, "users", "/events{/privacy}"),
    received_events_url = value.received_events_url
      or github_webhook_url_child(login, "users", "/received_events"),
    type = value.type or "User",
    site_admin = value.site_admin or false,
  }, value, overrides)
end

function github_webhook_sender(value, overrides) -- luacheck: globals github_webhook_sender
  return github_webhook_user(value, overrides)
end

function github_webhook_repository(value, overrides) -- luacheck: globals github_webhook_repository
  value = value or {}
  local full_name = value.full_name or value.name or ""
  local owner_name, repo_name = full_name:match("^([^/]+)/(.+)$")
  repo_name = value.name or repo_name or full_name
  local owner = github_webhook_user(value.owner or { login = owner_name or "" })
  local merged_value = copy_table(value)
  merged_value.owner = owner
  return with_defaults({
    id = value.id or 0,
    node_id = value.node_id or "",
    name = repo_name or "",
    full_name = full_name,
    private = value.private or false,
    owner = owner,
    html_url = value.html_url or (full_name ~= "" and "https://github.com/" .. full_name or ""),
    description = value.description,
    fork = value.fork or false,
    url = value.url or (full_name ~= "" and "https://api.github.com/repos/" .. full_name or ""),
    forks_url = value.forks_url or "",
    keys_url = value.keys_url or "",
    collaborators_url = value.collaborators_url or "",
    teams_url = value.teams_url or "",
    hooks_url = value.hooks_url or "",
    issue_events_url = value.issue_events_url or "",
    events_url = value.events_url or "",
    assignees_url = value.assignees_url or "",
    branches_url = value.branches_url or "",
    tags_url = value.tags_url or "",
    blobs_url = value.blobs_url or "",
    git_tags_url = value.git_tags_url or "",
    git_refs_url = value.git_refs_url or "",
    trees_url = value.trees_url or "",
    statuses_url = value.statuses_url or "",
    languages_url = value.languages_url or "",
    stargazers_url = value.stargazers_url or "",
    contributors_url = value.contributors_url or "",
    subscribers_url = value.subscribers_url or "",
    subscription_url = value.subscription_url or "",
    commits_url = value.commits_url or "",
    git_commits_url = value.git_commits_url or "",
    comments_url = value.comments_url or "",
    issue_comment_url = value.issue_comment_url or "",
    contents_url = value.contents_url or "",
    compare_url = value.compare_url or "",
    merges_url = value.merges_url or "",
    archive_url = value.archive_url or "",
    downloads_url = value.downloads_url or "",
    issues_url = value.issues_url or "",
    pulls_url = value.pulls_url or "",
    milestones_url = value.milestones_url or "",
    notifications_url = value.notifications_url or "",
    labels_url = value.labels_url or "",
    releases_url = value.releases_url or "",
    deployments_url = value.deployments_url or "",
    created_at = value.created_at or value.created or "",
    updated_at = value.updated_at or value.updated or "",
    pushed_at = value.pushed_at or value.updated_at or value.updated or "",
    git_url = value.git_url or "",
    ssh_url = value.ssh_url or "",
    clone_url = value.clone_url or "",
    svn_url = value.svn_url or value.html_url or "",
    homepage = value.homepage,
    size = value.size or 0,
    stargazers_count = value.stargazers_count or 0,
    watchers_count = value.watchers_count or value.stargazers_count or 0,
    language = value.language,
    has_issues = value.has_issues ~= false,
    has_projects = value.has_projects ~= false,
    has_downloads = value.has_downloads ~= false,
    has_wiki = value.has_wiki ~= false,
    has_pages = value.has_pages or false,
    forks_count = value.forks_count or value.forks or 0,
    mirror_url = value.mirror_url,
    archived = value.archived or false,
    disabled = value.disabled or false,
    open_issues_count = value.open_issues_count or value.open_issues or 0,
    license = value.license,
    allow_forking = value.allow_forking ~= false,
    is_template = value.is_template or false,
    web_commit_signoff_required = value.web_commit_signoff_required or false,
    topics = value.topics or {},
    visibility = value.visibility or (value.private and "private" or "public"),
    forks = value.forks or value.forks_count or 0,
    open_issues = value.open_issues or value.open_issues_count or 0,
    watchers = value.watchers or value.watchers_count or value.stargazers_count or 0,
    default_branch = value.default_branch or "",
  }, merged_value, overrides)
end

function github_webhook_organization(value, overrides) -- luacheck: globals github_webhook_organization
  return github_webhook_user(with_defaults({ type = "Organization" }, value or {}), overrides)
end

function github_webhook_issue(value, overrides) -- luacheck: globals github_webhook_issue
  value = value or {}
  local merged_value = copy_table(value)
  merged_value.user = github_webhook_user(value.user or value.author or {})
  return with_defaults({
    id = value.id or 0,
    node_id = value.node_id or "",
    url = value.url or "",
    repository_url = value.repository_url or "",
    labels_url = value.labels_url or "",
    comments_url = value.comments_url or "",
    events_url = value.events_url or "",
    html_url = value.html_url or "",
    number = value.number or 0,
    state = value.state or "open",
    title = value.title or "",
    body = value.body,
    user = merged_value.user,
    labels = value.labels or {},
    assignee = value.assignee,
    assignees = value.assignees or {},
    milestone = value.milestone,
    locked = value.locked or false,
    active_lock_reason = value.active_lock_reason,
    comments = value.comments or 0,
    pull_request = value.pull_request,
    closed_at = value.closed_at or value.closed,
    created_at = value.created_at or value.created or "",
    updated_at = value.updated_at or value.updated or "",
    author_association = value.author_association or "NONE",
    state_reason = value.state_reason,
  }, merged_value, overrides)
end

function github_webhook_pull_request(value, overrides) -- luacheck: globals github_webhook_pull_request
  value = value or {}
  local merged_value = copy_table(value)
  merged_value.user = github_webhook_user(value.user or value.author or {})
  return with_defaults({
    id = value.id or 0,
    node_id = value.node_id or "",
    number = value.number or 0,
    state = value.state or "open",
    locked = value.locked or false,
    title = value.title or "",
    user = merged_value.user,
    body = value.body,
    created_at = value.created_at or value.created or "",
    updated_at = value.updated_at or value.updated or "",
    closed_at = value.closed_at or value.closed,
    merged_at = value.merged_at,
    merge_commit_sha = value.merge_commit_sha,
    assignee = value.assignee,
    assignees = value.assignees or {},
    requested_reviewers = value.requested_reviewers or {},
    requested_teams = value.requested_teams or {},
    labels = value.labels or {},
    milestone = value.milestone,
    draft = value.draft or false,
    commits_url = value.commits_url or "",
    review_comments_url = value.review_comments_url or "",
    review_comment_url = value.review_comment_url or "",
    comments_url = value.comments_url or "",
    statuses_url = value.statuses_url or "",
    head = value.head or {},
    base = value.base or {},
    links = value.links or value._links or {},
    author_association = value.author_association or "NONE",
    auto_merge = value.auto_merge,
    active_lock_reason = value.active_lock_reason,
    merged = value.merged or false,
    mergeable = value.mergeable,
    rebaseable = value.rebaseable,
    mergeable_state = value.mergeable_state or "unknown",
    merged_by = value.merged_by,
    comments = value.comments or 0,
    review_comments = value.review_comments or 0,
    maintainer_can_modify = value.maintainer_can_modify ~= false,
    commits = value.commits or 0,
    additions = value.additions or 0,
    deletions = value.deletions or 0,
    changed_files = value.changed_files or 0,
  }, merged_value, overrides)
end

function github_webhook_label(value, overrides) -- luacheck: globals github_webhook_label
  value = value or {}
  return with_defaults({
    id = value.id or 0,
    node_id = value.node_id or "",
    url = value.url or "",
    name = value.name or "",
    color = value.color or "ededed",
    default = value.default or false,
    description = value.description,
  }, value, overrides)
end

function github_webhook_milestone(value, overrides) -- luacheck: globals github_webhook_milestone
  value = value or {}
  local merged_value = copy_table(value)
  merged_value.creator = github_webhook_user(value.creator or {})
  return with_defaults({
    id = value.id or 0,
    node_id = value.node_id or "",
    url = value.url or "",
    html_url = value.html_url or "",
    labels_url = value.labels_url or "",
    number = value.number or 0,
    state = value.state or "open",
    title = value.title or "",
    description = value.description,
    creator = merged_value.creator,
    open_issues = value.open_issues or 0,
    closed_issues = value.closed_issues or 0,
    created_at = value.created_at or value.created or "",
    updated_at = value.updated_at or value.updated or "",
    closed_at = value.closed_at or value.closed,
    due_on = value.due_on,
  }, merged_value, overrides)
end

function github_webhook_release(value, overrides) -- luacheck: globals github_webhook_release
  value = value or {}
  local merged_value = copy_table(value)
  merged_value.author = github_webhook_user(value.author or {})
  return with_defaults({
    id = value.id or 0,
    node_id = value.node_id or "",
    tag_name = value.tag_name or "",
    target_commitish = value.target_commitish or "",
    name = value.name,
    draft = value.draft or false,
    immutable = value.immutable or false,
    prerelease = value.prerelease or false,
    created_at = value.created_at or "",
    published_at = value.published_at,
    url = value.url or "",
    html_url = value.html_url or "",
    assets_url = value.assets_url or "",
    upload_url = value.upload_url or "",
    tarball_url = value.tarball_url,
    zipball_url = value.zipball_url,
    body = value.body,
    author = merged_value.author,
    assets = value.assets or {},
  }, merged_value, overrides)
end

function github_webhook_deployment(value, overrides) -- luacheck: globals github_webhook_deployment
  return with_defaults({
    id = 0,
    node_id = "",
    sha = "",
    ref = "",
    task = "deploy",
    environment = "production",
    description = nil,
    creator = {},
    created_at = "",
    updated_at = "",
    statuses_url = "",
    repository_url = "",
    transient_environment = false,
    production_environment = true,
  }, value or {}, overrides)
end

function github_webhook_deployment_status(value, overrides) -- luacheck: globals github_webhook_deployment_status
  return with_defaults({
    id = 0,
    node_id = "",
    state = "pending",
    creator = {},
    description = nil,
    environment = "production",
    target_url = "",
    created_at = "",
    updated_at = "",
    deployment_url = "",
    repository_url = "",
    environment_url = "",
    log_url = "",
  }, value or {}, overrides)
end

function github_webhook_check_run(value, overrides) -- luacheck: globals github_webhook_check_run
  return with_defaults({
    id = 0,
    node_id = "",
    head_sha = "",
    status = "queued",
    conclusion = nil,
    name = "",
    url = "",
    html_url = "",
    details_url = "",
    started_at = "",
    completed_at = nil,
    output = { title = nil, summary = nil, text = nil, annotations_count = 0, annotations_url = "" },
    check_suite = {},
    app = {},
    pull_requests = {},
  }, value or {}, overrides)
end

function github_webhook_check_suite(value, overrides) -- luacheck: globals github_webhook_check_suite
  return with_defaults({
    id = 0,
    node_id = "",
    head_branch = nil,
    head_sha = "",
    status = "queued",
    conclusion = nil,
    url = "",
    before = "",
    after = "",
    pull_requests = {},
    app = {},
    created_at = "",
    updated_at = "",
  }, value or {}, overrides)
end

function github_webhook_project(value, overrides) -- luacheck: globals github_webhook_project
  return with_defaults({
    id = 0,
    node_id = "",
    name = "",
    body = nil,
    url = "",
    html_url = "",
    columns_url = "",
    state = "open",
    creator = {},
    created_at = "",
    updated_at = "",
  }, value or {}, overrides)
end

function github_webhook_projects_v2(value, overrides) -- luacheck: globals github_webhook_projects_v2
  return with_defaults({
    id = 0,
    node_id = "",
    owner = {},
    creator = {},
    title = "",
    description = nil,
    public = false,
    closed = false,
    number = 0,
    short_description = nil,
    url = "",
    created_at = "",
    updated_at = "",
    closed_at = nil,
    deleted_at = nil,
  }, value or {}, overrides)
end

function github_webhook_projects_v2_item(value, overrides) -- luacheck: globals github_webhook_projects_v2_item
  return with_defaults({
    id = 0,
    node_id = "",
    project_node_id = "",
    content_node_id = "",
    content_type = "",
    creator = {},
    archived = false,
    type = "Issue",
    created_at = "",
    updated_at = "",
  }, value or {}, overrides)
end

function github_webhook_discussion(value, overrides) -- luacheck: globals github_webhook_discussion
  return with_defaults({
    id = 0,
    node_id = "",
    number = 0,
    title = "",
    body = "",
    user = {},
    state = "open",
    locked = false,
    comments = 0,
    created_at = "",
    updated_at = "",
    html_url = "",
    category = {},
  }, value or {}, overrides)
end

function github_webhook_alert(value, overrides) -- luacheck: globals github_webhook_alert
  return with_defaults({
    number = value and value.id or 0,
    state = "open",
    created_at = "",
    updated_at = "",
    url = "",
    html_url = "",
    fixed_at = nil,
    dismissed_at = nil,
    dismissed_by = nil,
    dismissed_reason = nil,
    rule = {},
  }, value or {}, overrides)
end

function github_webhook_installation(value, overrides) -- luacheck: globals github_webhook_installation
  return with_defaults({
    id = 0,
    node_id = "",
    account = {},
    repository_selection = "all",
    access_tokens_url = "",
    repositories_url = "",
    html_url = "",
    app_id = 0,
    app_slug = "confusio",
    target_id = 0,
    target_type = "Repository",
    permissions = {},
    events = {},
    created_at = "",
    updated_at = "",
    single_file_name = nil,
    has_multiple_single_files = false,
    single_file_paths = {},
    suspended_by = nil,
    suspended_at = nil,
  }, value or {}, overrides)
end

local ACTIONLESS_EVENTS = {
  create = true,
  delete = true,
  fork = true,
  push = true,
  status = true,
  ping = true,
  meta = true,
  public = true,
  gollum = true,
}

local function data_field(data, fields, name)
  return fields[name] or data[name]
end

local function include_if_present(payload, key, value)
  if value ~= nil then
    payload[key] = value
  end
end

function github_webhook_payload(internal_event, fields) -- luacheck: globals github_webhook_payload
  internal_event = internal_event or {}
  fields = fields or {}
  local data = internal_event.data or {}
  local event = internal_event.event or ""
  local payload = {}

  if not ACTIONLESS_EVENTS[event] then
    payload.action = fields.action or data.action or internal_event.action
  end
  payload.repository = fields.repository or github_webhook_repository(data.repository or {})
  include_if_present(payload, "organization", fields.organization or data.organization)
  payload.sender = fields.sender or github_webhook_sender(data.sender or {})
  include_if_present(payload, "installation", fields.installation or data.installation)

  if event == "issues" then
    payload.issue = fields.issue or github_webhook_issue(data.issue or {})
    include_if_present(payload, "label", fields.label or data.label)
    include_if_present(payload, "assignee", fields.assignee or data.assignee)
    include_if_present(payload, "milestone", fields.milestone or data.milestone)
  elseif event == "issue_comment" then
    payload.issue = fields.issue or github_webhook_issue(data.issue or {})
    payload.comment = data_field(data, fields, "comment") or {}
  elseif event == "pull_request" then
    payload.number = fields.number or data.number
    payload.pull_request = fields.pull_request
      or github_webhook_pull_request(data.pull_request or {})
    include_if_present(payload, "label", fields.label or data.label)
    include_if_present(payload, "assignee", fields.assignee or data.assignee)
    include_if_present(payload, "milestone", fields.milestone or data.milestone)
    include_if_present(
      payload,
      "requested_reviewer",
      fields.requested_reviewer or data.requested_reviewer
    )
    include_if_present(payload, "changes", fields.changes or data.changes)
  elseif event == "pull_request_review" then
    payload.review = data_field(data, fields, "review") or {}
    payload.pull_request = fields.pull_request
      or github_webhook_pull_request(data.pull_request or {})
  elseif event == "pull_request_review_comment" then
    payload.comment = data_field(data, fields, "comment") or {}
    payload.pull_request = fields.pull_request
      or github_webhook_pull_request(data.pull_request or {})
  elseif event == "label" then
    payload.label = fields.label or github_webhook_label(data.label or {})
    payload.changes = data_field(data, fields, "changes") or {}
  elseif event == "milestone" then
    payload.milestone = fields.milestone or github_webhook_milestone(data.milestone or {})
    payload.changes = data_field(data, fields, "changes") or {}
  elseif event == "release" then
    payload.release = fields.release or github_webhook_release(data.release or {})
    include_if_present(payload, "changes", fields.changes or data.changes)
  elseif event == "deployment" then
    payload.deployment = fields.deployment or github_webhook_deployment(data.deployment or {})
  elseif event == "deployment_status" then
    payload.deployment = data_field(data, fields, "deployment") or {}
    payload.deployment_status = fields.deployment_status
      or github_webhook_deployment_status(data.deployment_status or {})
  elseif event == "check_run" then
    payload.check_run = fields.check_run or github_webhook_check_run(data.check_run or {})
  elseif event == "check_suite" then
    payload.check_suite = fields.check_suite or github_webhook_check_suite(data.check_suite or {})
  elseif event == "workflow_run" then
    payload.workflow_run = data_field(data, fields, "workflow_run") or {}
    payload.workflow = data_field(data, fields, "workflow") or {}
  elseif event == "workflow_job" then
    payload.workflow_job = data_field(data, fields, "workflow_job") or {}
  elseif event == "push" then
    payload.ref = data.ref or ""
    payload.before = data.before or ""
    payload.after = data.after or ""
    payload.created = data.created or false
    payload.deleted = data.deleted or false
    payload.forced = data.forced or false
    payload.compare = data.compare or ""
    payload.commits = data.commits or {}
    payload.head_commit = data.head_commit
    payload.pusher = data.pusher or {}
  elseif event == "create" or event == "delete" then
    payload.ref = data.ref or ""
    payload.ref_type = data.ref_type or ""
    payload.master_branch = data.master_branch or ""
    payload.description = data.description
    payload.pusher_type = data.pusher_type or "user"
  elseif event == "fork" then
    payload.forkee = fields.forkee or github_webhook_repository(data.forkee or {})
  elseif event == "repository" then
    include_if_present(payload, "changes", fields.changes or data.changes)
  elseif event == "gollum" then
    payload.pages = data.pages or {}
  elseif event == "discussion" then
    payload.discussion = fields.discussion or github_webhook_discussion(data.discussion or {})
    include_if_present(payload, "label", fields.label or data.label)
  elseif event == "discussion_comment" then
    payload.discussion = fields.discussion or github_webhook_discussion(data.discussion or {})
    payload.comment = data_field(data, fields, "comment") or {}
  elseif event == "project" then
    payload.project = fields.project or github_webhook_project(data.project or {})
  elseif event == "projects_v2" then
    payload.projects_v2 = fields.projects_v2 or github_webhook_projects_v2(data.projects_v2 or {})
  elseif event == "projects_v2_item" then
    payload.projects_v2_item = fields.projects_v2_item
      or github_webhook_projects_v2_item(data.projects_v2_item or {})
    include_if_present(payload, "projects_v2", fields.projects_v2 or data.projects_v2)
  elseif
    event == "code_scanning_alert"
    or event == "dependabot_alert"
    or event == "secret_scanning_alert"
  then
    payload.alert = fields.alert or github_webhook_alert(data.alert or {})
  elseif event == "installation" then
    payload.installation = fields.installation
      or github_webhook_installation(data.installation or {})
  elseif event == "installation_repositories" then
    payload.installation = fields.installation
      or github_webhook_installation(data.installation or {})
    payload.repositories_added = data.repositories_added or {}
    payload.repositories_removed = data.repositories_removed or {}
    payload.repository_selection = data.repository_selection or "selected"
  else
    for k, v in pairs(data) do
      if k ~= "action" and k ~= "repository" and k ~= "sender" and payload[k] == nil then
        payload[k] = v
      end
    end
  end

  for k, v in pairs(fields.payload or {}) do
    payload[k] = v
  end
  return payload
end
