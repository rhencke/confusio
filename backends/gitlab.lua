-- GitLab backend handler overrides.
-- GitLab identifies projects by URL-encoded "namespace/path" as the project ID.
if config.base_url == "" then
  config.base_url = "https://gitlab.com"
end

local base = function()
  return config.base_url .. "/api/v4"
end
local auth = function()
  return make_fetch_opts("bearer")
end
local PAGES = { per_page = "per_page", page = "page" }
local _t = make_backend_transport("bearer", PAGES)
local fetch_json = _t.fetch_json
local proxy_handler = _t.proxy_handler
local proxy_handler_paged = _t.proxy_handler_paged

local project_id = owner_repo_id

-- Map a GitLab project object to GitHub repo format.
local function translate_gl_repo(p)
  if not p then
    return {}
  end
  local ns = p.namespace or {}
  local owner = {
    login = ns.path or ns.name or "",
    id = ns.id or 0,
    node_id = "",
    avatar_url = ns.avatar_url or "",
    url = "",
    html_url = ns.web_url or "",
    type = ns.kind == "group" and "Organization" or "User",
  }
  return {
    id = p.id,
    node_id = "",
    name = p.path,
    full_name = p.path_with_namespace,
    private = p.visibility == "private",
    owner = owner,
    html_url = p.web_url,
    description = p.description,
    fork = (p.forked_from_project ~= nil),
    url = p.web_url,
    ssh_url = p.ssh_url_to_repo,
    clone_url = p.http_url_to_repo,
    homepage = p.web_url,
    size = p.statistics and p.statistics.repository_size or 0,
    stargazers_count = p.star_count or 0,
    watchers_count = p.star_count or 0,
    language = nil,
    has_issues = p.issues_enabled,
    has_wiki = p.wiki_enabled,
    forks_count = p.forks_count or 0,
    archived = p.archived,
    disabled = false,
    open_issues_count = p.open_issues_count or 0,
    default_branch = p.default_branch,
    visibility = p.visibility or "public",
    forks = p.forks_count or 0,
    open_issues = p.open_issues_count or 0,
    watchers = p.star_count or 0,
    created_at = p.created_at,
    updated_at = p.last_activity_at,
    pushed_at = p.last_activity_at,
  }
end

-- Translate a GitLab create/update request body from GitHub format to GitLab.
local function translate_gl_req(body_str)
  local req = DecodeJson(body_str or "{}")
  local gl = {}
  if req.name then
    gl.name = req.name
  end
  if req.description then
    gl.description = req.description
  end
  if req.private ~= nil then
    gl.visibility = req.private and "private" or "public"
  end
  if req.homepage then
    gl.web_url = req.homepage
  end
  if req.has_issues ~= nil then
    gl.issues_enabled = req.has_issues
  end
  if req.has_wiki ~= nil then
    gl.wiki_enabled = req.has_wiki
  end
  return EncodeJson(gl)
end

-- Map a GitLab user object to GitHub format.
local function translate_gl_user(u)
  if not u then
    return {}
  end
  return {
    login = u.username,
    id = u.id,
    node_id = "",
    avatar_url = u.avatar_url or "",
    html_url = u.web_url or "",
    type = "User",
    site_admin = u.is_admin or false,
    name = u.name,
    email = u.email,
    location = u.location,
    blog = u.website_url,
    created_at = u.created_at,
  }
end

-- Look up a GitLab user ID by username. Returns nil on failure.
local function gl_user_id(username)
  local ok, status, _, body = fetch_json(base() .. "/users?username=" .. username)
  if not ok or status ~= 200 then
    return nil
  end
  local list = DecodeJson(body) or {}
  return list[1] and list[1].id
end

-- Translate a GitLab group to GitHub team format.
-- Teams in GitHub map to subgroups in GitLab.
local function translate_gl_team(g)
  if not g then
    return {}
  end
  return {
    id = g.id,
    node_id = "",
    name = g.name,
    slug = g.path,
    description = g.description or "",
    privacy = g.visibility == "private" and "secret" or "closed",
    notification_setting = "notifications_enabled",
    permission = "pull",
    members_url = "",
    repositories_url = "",
    parent = nil,
  }
end

-- Translate a GitLab group member to GitHub user format.
local function translate_gl_member(m)
  if not m then
    return {}
  end
  return {
    login = m.username,
    id = m.id,
    node_id = "",
    avatar_url = m.avatar_url or "",
    html_url = m.web_url or "",
    type = "User",
    site_admin = false,
  }
end

-- Map a GitLab label object to GitHub format.
-- GitLab color includes '#' prefix; GitHub does not.
local function translate_gl_label(l)
  if not l then
    return {}
  end
  return {
    id = l.id,
    node_id = "",
    url = "",
    name = l.name,
    color = (l.color or ""):gsub("^#", ""),
    description = l.description or "",
    default = false,
  }
end

-- Map a GitLab milestone object to GitHub format.
-- GitLab state: "active"/"closed" → GitHub: "open"/"closed"
local function translate_gl_milestone(m)
  if not m then
    return nil
  end
  return {
    id = m.id,
    node_id = "",
    number = m.iid or m.id,
    title = m.title,
    description = m.description or "",
    state = m.state == "active" and "open" or "closed",
    open_issues = 0,
    closed_issues = 0,
    created_at = m.created_at,
    updated_at = m.updated_at,
    closed_at = m.closed_at,
    due_on = m.due_date,
  }
end

-- Map a GitLab issue object to GitHub format.
-- GitLab uses iid (project-local number) and "opened"/"closed" states.
local function translate_gl_issue(i)
  if not i then
    return {}
  end
  local labels, assignees = {}, {}
  for _, l in ipairs(i.labels or {}) do
    if type(l) == "table" then
      labels[#labels + 1] = translate_gl_label(l)
    else
      labels[#labels + 1] =
        { id = 0, node_id = "", url = "", name = l, color = "", description = "", default = false }
    end
  end
  for _, u in ipairs(i.assignees or {}) do
    assignees[#assignees + 1] = translate_gl_user(u)
  end
  return {
    id = i.id,
    node_id = "",
    number = i.iid,
    title = i.title,
    body = i.description,
    state = i.state == "opened" and "open" or i.state,
    user = translate_gl_user(i.author),
    assignees = assignees,
    labels = labels,
    milestone = translate_gl_milestone(i.milestone),
    comments = i.user_notes_count or 0,
    created_at = i.created_at,
    updated_at = i.updated_at,
    closed_at = i.closed_at,
    html_url = i.web_url or "",
    url = i.web_url or "",
    pull_request = nil,
  }
end

-- Map a GitLab note (issue comment) to GitHub format.
local function translate_gl_note(c)
  if not c then
    return {}
  end
  return {
    id = c.id,
    node_id = "",
    url = "",
    html_url = "",
    body = c.body,
    user = translate_gl_user(c.author),
    created_at = c.created_at,
    updated_at = c.updated_at,
  }
end

local function translate_gl_issues(issues)
  return translate_list(translate_gl_issue, issues)
end
local function translate_gl_notes(notes)
  return translate_list(translate_gl_note, notes)
end
local function translate_gl_labels(labels)
  return translate_list(translate_gl_label, labels)
end
local function translate_gl_milestones(milestones)
  return translate_list(translate_gl_milestone, milestones)
end
local function translate_gl_members(members)
  return translate_list(translate_gl_member, members)
end

-- Map a GitLab group to GitHub organization REST shape.
-- Used by orgs capability module and GraphQL resolvers.
local function translate_gl_group_to_org(g)
  if not g then
    return nil
  end
  return {
    login = g.path or g.full_path or "",
    name = g.name,
    description = g.description,
    avatar_url = g.avatar_url or "",
    html_url = g.web_url or "",
    blog = "",
    email = "",
    location = "",
    created_at = g.created_at,
  }
end

-- Map a GitLab MR (merge request) object to GitHub PR format.
-- GitLab uses "opened"/"closed"/"merged"; GitHub uses "open"/"closed"/"merged".
local function translate_gl_mr(mr)
  if not mr then
    return {}
  end
  local state = mr.state
  if state == "opened" then
    state = "open"
  end
  local diff_refs = mr.diff_refs or {}
  return {
    id = mr.id,
    node_id = "",
    number = mr.iid,
    state = state,
    locked = false,
    title = mr.title,
    body = mr.description,
    user = translate_gl_user(mr.author),
    head = {
      label = mr.source_branch or "",
      ref = mr.source_branch or "",
      sha = diff_refs.head_sha or mr.sha or "",
      repo = nil,
    },
    base = {
      label = mr.target_branch or "",
      ref = mr.target_branch or "",
      sha = diff_refs.base_sha or "",
      repo = nil,
    },
    draft = mr.draft or false,
    created_at = mr.created_at,
    updated_at = mr.updated_at,
    closed_at = mr.closed_at,
    merged_at = mr.merged_at,
    merge_commit_sha = mr.merge_commit_sha,
    merged_by = mr.merged_by and translate_gl_user(mr.merged_by) or nil,
    diff_url = mr.web_url and (mr.web_url .. ".diff") or "",
    patch_url = mr.web_url and (mr.web_url .. ".patch") or "",
    html_url = mr.web_url or "",
    url = mr.web_url or "",
    mergeable = mr.merge_status == "can_be_merged",
    comments = mr.user_notes_count or 0,
    changed_files = mr.changes_count and tonumber(mr.changes_count) or 0,
  }
end

-- Map GitLab MR approvals to GitHub reviews (APPROVED state).
-- GitLab uses an approvals object; GitHub uses an array of review objects.
local function translate_gl_approvals_to_reviews(approvals)
  if not approvals then
    return {}
  end
  local result = {}
  for i, a in ipairs(approvals.approved_by or {}) do
    result[i] = {
      id = i,
      node_id = "",
      user = translate_gl_user(a.user),
      body = "",
      state = "APPROVED",
      submitted_at = approvals.created_at or "",
      html_url = "",
      pull_request_url = "",
    }
  end
  return result
end

-- Map a GitLab MR inline note (position-based) to GitHub review comment format.
local function translate_gl_mr_note_to_review_comment(n)
  if not n then
    return {}
  end
  local pos = n.position or {}
  return {
    id = n.id,
    node_id = "",
    path = pos.new_path or pos.old_path or "",
    position = pos.new_line or pos.old_line,
    original_position = pos.old_line,
    commit_id = pos.head_sha or "",
    original_commit_id = pos.base_sha or "",
    diff_hunk = "",
    body = n.body or "",
    user = translate_gl_user(n.author),
    created_at = n.created_at,
    updated_at = n.updated_at,
    html_url = "",
    pull_request_url = "",
    url = "",
  }
end

-- Fetch inline MR notes (position-based) for a given MR.
local function fetch_gl_mr_review_comments(owner, repo_name, pull_number)
  local ok, status, _, body = fetch_json(
    append_page_params(
      base()
        .. "/projects/"
        .. project_id(owner, repo_name)
        .. "/merge_requests/"
        .. pull_number
        .. "/notes",
      PAGES
    )
  )
  if not ok or status ~= 200 then
    return nil, status
  end
  local notes = DecodeJson(body) or {}
  local result = {}
  for _, n in ipairs(notes) do
    if not n.system and n.position then
      result[#result + 1] = translate_gl_mr_note_to_review_comment(n)
    end
  end
  return result, 200
end

-- Look up a GitLab label ID by name within a project.
local function gl_find_label_id(owner, repo_name, label_name)
  local ok, status, _, body =
    fetch_json(base() .. "/projects/" .. project_id(owner, repo_name) .. "/labels?per_page=100")
  if not ok or status ~= 200 then
    return nil
  end
  for _, l in ipairs(DecodeJson(body) or {}) do
    if l.name == label_name then
      return l.id
    end
  end
  return nil
end

-- Helper: resolve a GitHub integer release_id to a GitLab tag_name by fetching the
-- releases list and returning the tag_name at the given index position.
local function gl_tag_by_id(owner, repo_name, release_id)
  local ok, status, _, body =
    fetch_json(base() .. "/projects/" .. project_id(owner, repo_name) .. "/releases")
  if not ok or status ~= 200 then
    return nil
  end
  local rels = DecodeJson(body)
  local idx = tonumber(release_id)
  if not rels or not idx or not rels[idx] then
    return nil
  end
  return rels[idx].tag_name
end

-- Helper: translate a single GitLab release object to GitHub release format.
local function translate_gl_release(r, idx)
  return {
    id = idx or 1,
    tag_name = r.tag_name,
    name = r.name,
    body = r.description,
    draft = false,
    prerelease = false,
    created_at = r.created_at,
    published_at = r.released_at or r.created_at,
    assets = {},
  }
end

-- Helper: translate a GitLab release link to GitHub release asset format.
local function translate_gl_link(l)
  return {
    id = l.id,
    name = l.name,
    label = l.name,
    state = "uploaded",
    content_type = "application/octet-stream",
    size = 0,
    download_count = 0,
    created_at = l.created_at or "",
    updated_at = l.updated_at or "",
    browser_download_url = l.url,
  }
end

-- Helper: scan all releases for the one containing a link with the given ID.
-- Returns tag_name or nil. GitLab has no direct link-by-ID endpoint without tag_name.
local function gl_find_link(owner, repo_name, asset_id)
  local ok, status, _, body =
    fetch_json(base() .. "/projects/" .. project_id(owner, repo_name) .. "/releases")
  if not ok or status ~= 200 then
    return nil
  end
  local rels = DecodeJson(body)
  if not rels then
    return nil
  end
  for _, r in ipairs(rels) do
    local ok2, s2, _, b2 = fetch_json(
      base()
        .. "/projects/"
        .. project_id(owner, repo_name)
        .. "/releases/"
        .. r.tag_name
        .. "/assets/links"
    )
    if ok2 and s2 == 200 then
      for _, l in ipairs(DecodeJson(b2) or {}) do
        if tostring(l.id) == tostring(asset_id) then
          return r.tag_name
        end
      end
    end
  end
  return nil
end

-- GitLab commit status → GitHub commit status (simple string).
-- Used by get_commit_statuses, get_commit_combined_status, post_commit_status.
local GL_STATUS_TO_GH = {
  pending = "pending",
  running = "pending",
  success = "success",
  failed = "failure",
  canceled = "error",
}

-- GitLab commit status → GitHub check run status/conclusion.
-- Used by post_check_runs and get_commit_check_runs.
local GL_STATUS_TO_CHECK_RUN = {
  pending = { status = "queued", conclusion = nil },
  running = { status = "in_progress", conclusion = nil },
  success = { status = "completed", conclusion = "success" },
  failed = { status = "completed", conclusion = "failure" },
  canceled = { status = "completed", conclusion = "cancelled" },
}

-- Map a GitLab branch object to GitHub branch format.
-- Normalises commit.id → commit.sha in place and returns the branch.
local function translate_gl_branch(br)
  if not br then
    return {}
  end
  if br.commit then
    br.commit.sha = br.commit.id
  end
  return br
end

-- Map a GitLab commit object to GitHub commit format.
local function translate_gl_commit(c)
  if not c then
    return {}
  end
  return {
    sha = c.id,
    html_url = c.web_url or "",
    commit = {
      message = c.message,
      author = { name = c.author_name, email = c.author_email, date = c.authored_date },
      committer = {
        name = c.committer_name or c.author_name,
        email = c.committer_email or c.author_email,
        date = c.committed_date or c.authored_date,
      },
    },
    stats = c.stats,
  }
end

-- Map a GitLab commit status object to GitHub status format.
local function translate_gl_status(s)
  if not s then
    return {}
  end
  return {
    id = s.id,
    state = GL_STATUS_TO_GH[s.status] or s.status,
    description = s.description,
    target_url = s.target_url,
    context = s.name,
    created_at = s.created_at,
    updated_at = s.updated_at,
  }
end

-- Map a GitLab commit status object to a GitHub check run object.
-- sha: the commit SHA to embed as head_sha (GitLab status may not include it).
local function translate_gl_status_to_check_run(s, sha)
  if not s then
    return {}
  end
  local mapped = GL_STATUS_TO_CHECK_RUN[s.status]
    or { status = "completed", conclusion = "failure" }
  return {
    id = s.id,
    node_id = "",
    head_sha = sha or "",
    name = s.name or "",
    status = mapped.status,
    conclusion = mapped.conclusion,
    started_at = s.created_at,
    completed_at = mapped.status == "completed" and s.updated_at or nil,
    output = {
      title = s.description or "",
      summary = s.description or "",
      text = "",
      annotations_count = 0,
      annotations_url = "",
    },
    url = "",
    html_url = s.target_url or "",
    details_url = s.target_url or "",
  }
end

-- ---------------------------------------------------------------------------
-- Repos capability module
-- ---------------------------------------------------------------------------
-- Owns fetch + translate_gl_repo for all repository operations.
-- REST handlers and GraphQL resolvers both call into this table rather than
-- duplicating the URL construction, error mapping, and translation logic.
-- All operations return (data, nil) on success or (nil, err) on failure.
-- Paged list operations return (items, headers, nil) or (nil, nil, err).

local repos = {}

-- get: fetch a single repository.
repos.get = function(owner, repo_name)
  local raw, err = cap_fetch(fetch_json, base() .. "/projects/" .. project_id(owner, repo_name))
  if not raw then
    return nil, err
  end
  return translate_gl_repo(raw), nil
end

-- update: apply a partial update (GitLab uses PUT for project updates).
-- body: raw GitHub-format request body string (translated internally).
repos.update = function(owner, repo_name, body)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name),
    "PUT",
    translate_gl_req(body)
  )
  if not raw then
    return nil, err
  end
  return translate_gl_repo(raw), nil
end

-- delete: permanently remove a repository.
-- GitLab returns 202 Accepted for async deletion.
-- Returns (true, nil) on 202 success or (nil, err) on failure.
repos.delete = function(owner, repo_name)
  local url = base() .. "/projects/" .. project_id(owner, repo_name)
  local dopts = auth() or {}
  dopts.method = "DELETE"
  local ok, status = pcall(Fetch, url, dopts)
  if not ok then
    return nil, cap_err(0, "network error deleting " .. owner .. "/" .. repo_name)
  end
  if status ~= 202 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting repository")
  end
  return true, nil
end

-- list_user: paginated list of repos for the authenticated user.
repos.list_user = function()
  local url = append_page_params(base() .. "/projects?owned=true&membership=true", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_repo, items), hdrs, nil
end

-- create_user: create a repository under the authenticated user.
repos.create_user = function(body)
  local raw, err = cap_fetch(fetch_json, base() .. "/projects", "POST", translate_gl_req(body))
  if not raw then
    return nil, err
  end
  return translate_gl_repo(raw), nil
end

-- list_org: paginated list of repos for a GitLab group.
repos.list_org = function(org)
  local url = append_page_params(base() .. "/groups/" .. org .. "/projects", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_repo, items), hdrs, nil
end

-- create_org: create a repository inside a GitLab group (namespace).
repos.create_org = function(org, body)
  local gl_req = translate_gl_req(body)
  local gl = DecodeJson(gl_req)
  gl.namespace_id = org
  local raw, err = cap_fetch(fetch_json, base() .. "/projects", "POST", EncodeJson(gl))
  if not raw then
    return nil, err
  end
  return translate_gl_repo(raw), nil
end

-- list_by_user: paginated list of public repos for a specific user.
repos.list_by_user = function(username)
  local url = append_page_params(base() .. "/users/" .. username .. "/projects", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_repo, items), hdrs, nil
end

-- list_all: paginated list of all public projects.
repos.list_all = function()
  local url = append_page_params(base() .. "/projects?visibility=public", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_repo, items), hdrs, nil
end

-- get_topics: fetch project topics, returned as { names = [...] }.
repos.get_topics = function(owner, repo_name)
  local raw, err = cap_fetch(fetch_json, base() .. "/projects/" .. project_id(owner, repo_name))
  if not raw then
    return nil, err
  end
  return { names = raw.topics or {} }, nil
end

-- put_topics: replace project topics.
repos.put_topics = function(owner, repo_name, body)
  local req = DecodeJson(body or "{}")
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name),
    "PUT",
    EncodeJson({ topics = req.names or {} })
  )
  if not raw then
    return nil, err
  end
  return { names = raw.topics or {} }, nil
end

-- ---------------------------------------------------------------------------
-- Users capability module
-- ---------------------------------------------------------------------------
-- Owns fetch + translate_gl_user for all user operations.
-- REST handlers and GraphQL resolvers call into this table rather than
-- duplicating URL construction, error mapping, and translation logic.
-- User operations return (data, nil) on success or (nil, err) on failure.
-- Email/key/GPG operations return raw upstream data with no translation.
-- Paged list operations return (items, headers, nil) or (nil, nil, err).

local users = {}

-- get_authenticated: fetch the currently authenticated user.
users.get_authenticated = function()
  local raw, err = cap_fetch(fetch_json, base() .. "/user")
  if not raw then
    return nil, err
  end
  return translate_gl_user(raw), nil
end

-- update_authenticated: update the authenticated user (GitLab uses PUT /user).
users.update_authenticated = function(body)
  local raw, err = cap_fetch(fetch_json, base() .. "/user", "PUT", body)
  if not raw then
    return nil, err
  end
  return translate_gl_user(raw), nil
end

-- by_username: fetch a single user by username (GitLab returns an array from
-- /users?username=X; we take the first element).
-- Returns the GitHub REST user shape or (nil, err) when no user is found.
users.by_username = function(username)
  local raw, err = cap_fetch(fetch_json, base() .. "/users?username=" .. username)
  if not raw then
    return nil, err
  end
  local u = type(raw) == "table" and raw[1]
  if not u then
    return nil, cap_err(404, "user not found: " .. username)
  end
  return translate_gl_user(u), nil
end

-- list_all: paginated list of all users.
users.list_all = function()
  local url = append_page_params(base() .. "/users", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_user, items), hdrs, nil
end

-- list_emails: list email addresses for the authenticated user.
-- Returns raw upstream array (no translation).
users.list_emails = function()
  local raw, err = cap_fetch(fetch_json, base() .. "/user/emails")
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- create_email: add an email address for the authenticated user.
users.create_email = function(body)
  local raw, err = cap_fetch(fetch_json, base() .. "/user/emails", "POST", body)
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- list_keys: paginated list of SSH keys for the authenticated user.
users.list_keys = function()
  local url = append_page_params(base() .. "/user/keys", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return items, hdrs, nil
end

-- create_key: add an SSH key for the authenticated user.
users.create_key = function(body)
  local raw, err = cap_fetch(fetch_json, base() .. "/user/keys", "POST", body)
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- get_key: fetch a single SSH key by ID.
users.get_key = function(key_id)
  local raw, err = cap_fetch(fetch_json, base() .. "/user/keys/" .. key_id)
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- delete_key: delete an SSH key by ID.
-- Returns (true, nil) on 204 success or (nil, err) on failure.
users.delete_key = function(key_id)
  local ok, status = fetch_json(base() .. "/user/keys/" .. key_id, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error deleting key " .. tostring(key_id))
  end
  if status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting key")
  end
  return true, nil
end

-- list_by_username_keys: list SSH keys for a specific user (by username).
-- Returns raw upstream array (no translation).
users.list_by_username_keys = function(username)
  local uid = gl_user_id(username)
  if not uid then
    return nil, cap_err(404, "user not found: " .. username)
  end
  local raw, err = cap_fetch(fetch_json, base() .. "/users/" .. uid .. "/keys")
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- list_gpg_keys: paginated list of GPG keys for the authenticated user.
users.list_gpg_keys = function()
  local url = append_page_params(base() .. "/user/gpg_keys", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return items, hdrs, nil
end

-- create_gpg_key: add a GPG key for the authenticated user.
users.create_gpg_key = function(body)
  local raw, err = cap_fetch(fetch_json, base() .. "/user/gpg_keys", "POST", body)
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- get_gpg_key: fetch a single GPG key by ID.
users.get_gpg_key = function(gpg_key_id)
  local raw, err = cap_fetch(fetch_json, base() .. "/user/gpg_keys/" .. gpg_key_id)
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- delete_gpg_key: delete a GPG key by ID.
-- Returns (true, nil) on 204 success or (nil, err) on failure.
users.delete_gpg_key = function(gpg_key_id)
  local ok, status = fetch_json(base() .. "/user/gpg_keys/" .. gpg_key_id, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error deleting GPG key " .. tostring(gpg_key_id))
  end
  if status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting GPG key")
  end
  return true, nil
end

-- list_by_username_gpg_keys: list GPG keys for a specific user (by username).
-- Returns raw upstream array (no translation).
users.list_by_username_gpg_keys = function(username)
  local uid = gl_user_id(username)
  if not uid then
    return nil, cap_err(404, "user not found: " .. username)
  end
  local raw, err = cap_fetch(fetch_json, base() .. "/users/" .. uid .. "/gpg_keys")
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- ---------------------------------------------------------------------------
-- Orgs capability module
-- ---------------------------------------------------------------------------
-- Shared fetch + translate operations for organization (GitLab group) resources.
-- orgs.get returns the GitHub REST-compatible org shape (translate_gl_group_to_org
-- applied), ready for graphql_translate_org in GraphQL resolvers.
-- Operations return (data, nil) on success or (nil, err) on failure.

local orgs = {}

-- get: fetch a single organization (GitLab group) by login/path.
-- Returns the GitHub REST org shape (translate_gl_group_to_org applied).
orgs.get = function(login)
  local raw, err = cap_fetch(fetch_json, base() .. "/groups/" .. login)
  if not raw then
    return nil, err
  end
  return translate_gl_group_to_org(raw), nil
end

-- ---------------------------------------------------------------------------
-- Branches capability module
-- ---------------------------------------------------------------------------
-- Owns fetch + translate_gl_branch for all branch operations.
-- Paged list operations return (items, headers, nil) or (nil, nil, err).
-- Single-item operations return (data, nil) or (nil, err).

local branches = {}

-- list: paginated list of branches for a repository.
branches.list = function(owner, repo_name)
  local url = append_page_params(
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/repository/branches",
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_branch, items), hdrs, nil
end

-- get: fetch a single branch by name.
branches.get = function(owner, repo_name, branch)
  local url = base()
    .. "/projects/"
    .. project_id(owner, repo_name)
    .. "/repository/branches/"
    .. branch
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  return translate_gl_branch(raw), nil
end

-- ---------------------------------------------------------------------------
-- Commits capability module
-- ---------------------------------------------------------------------------
-- Owns fetch + translate_gl_commit for all commit operations.
-- Paged list operations return (items, headers, nil) or (nil, nil, err).
-- Single-item operations return (data, nil) or (nil, err).

local commits = {}

-- list: paginated list of commits for a repository.
commits.list = function(owner, repo_name)
  local url = append_page_params(
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/repository/commits",
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_commit, items), hdrs, nil
end

-- get: fetch a single commit by ref (SHA, branch, or tag).
commits.get = function(owner, repo_name, ref)
  local url = base()
    .. "/projects/"
    .. project_id(owner, repo_name)
    .. "/repository/commits/"
    .. ref
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  return translate_gl_commit(raw), nil
end

-- ---------------------------------------------------------------------------
-- Statuses capability module
-- ---------------------------------------------------------------------------
-- Owns fetch + translation for commit statuses and check runs.
-- GitLab has no check-run concept; both map to the GitLab commit statuses API.
-- Paged list operations return (items, headers, nil) or (nil, nil, err).
-- Single-item and aggregate operations return (data, nil) or (nil, err).

local statuses_cap = {}

-- list: paginated list of commit statuses for a ref.
statuses_cap.list = function(owner, repo_name, ref)
  local url = append_page_params(
    base()
      .. "/projects/"
      .. project_id(owner, repo_name)
      .. "/repository/commits/"
      .. ref
      .. "/statuses",
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_status, items), hdrs, nil
end

-- get_combined: aggregate all commit statuses into a GitHub combined status.
-- Returns ({ state, statuses, total_count }, nil) or (nil, err).
statuses_cap.get_combined = function(owner, repo_name, ref)
  local url = base()
    .. "/projects/"
    .. project_id(owner, repo_name)
    .. "/repository/commits/"
    .. ref
    .. "/statuses"
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  local state = "success"
  local result = {}
  for _, s in ipairs(raw) do
    local gh_state = GL_STATUS_TO_GH[s.status] or s.status
    if gh_state == "failure" or gh_state == "error" then
      state = gh_state
    end
    if gh_state == "pending" and state == "success" then
      state = "pending"
    end
    result[#result + 1] = {
      id = s.id,
      state = gh_state,
      context = s.name,
      description = s.description,
      target_url = s.target_url,
    }
  end
  return { state = state, statuses = result, total_count = #result }, nil
end

-- create: create a commit status from a GitHub-format request body.
-- Returns the created status in GitHub format or (nil, err).
statuses_cap.create = function(owner, repo_name, sha, body)
  local req = DecodeJson(body or "{}")
  local gh_to_gl =
    { pending = "pending", success = "success", failure = "failed", error = "failed" }
  local gl_body = EncodeJson({
    state = gh_to_gl[req.state] or req.state,
    name = req.context or "default",
    description = req.description,
    target_url = req.target_url,
  })
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/statuses/" .. sha,
    "POST",
    gl_body
  )
  if not raw then
    return nil, err
  end
  return translate_gl_status(raw), nil
end

-- list_check_runs: fetch commit statuses shaped as GitHub check runs for a ref.
-- Returns ({ total_count, check_runs }, nil) or (nil, err).
statuses_cap.list_check_runs = function(owner, repo_name, ref)
  local url = base()
    .. "/projects/"
    .. project_id(owner, repo_name)
    .. "/repository/commits/"
    .. ref
    .. "/statuses"
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  local runs = {}
  for i, s in ipairs(raw) do
    runs[i] = translate_gl_status_to_check_run(s, ref)
  end
  return { total_count = #runs, check_runs = runs }, nil
end

-- create_check_run: create a GitHub check run via GitLab commit status.
-- body: raw GitHub-format request body string.
-- Returns the created check run in GitHub format or (nil, err).
statuses_cap.create_check_run = function(owner, repo_name, body)
  local req = DecodeJson(body or "{}")
  local sha = req.head_sha or ""
  local check_status = req.status or "queued"
  local conclusion = req.conclusion
  local gh_conclusion_to_gl = {
    success = "success",
    neutral = "success",
    skipped = "success",
  }
  local gl_state = check_status == "completed" and (gh_conclusion_to_gl[conclusion] or "failed")
    or "running"
  local gl_body = EncodeJson({
    state = gl_state,
    target_url = req.details_url or "",
    description = (req.output and req.output.summary) or req.name or "",
    name = req.name or "",
    context = req.name or "",
    ref = sha,
  })
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/statuses/" .. sha,
    "POST",
    gl_body
  )
  if not raw then
    return nil, err
  end
  return translate_gl_status_to_check_run(raw, sha), nil
end

-- GitLab award emoji → GitHub reaction content (8 supported types).
local GL_EMOJI_TO_CONTENT = {
  thumbsup = "+1",
  thumbsdown = "-1",
  laughing = "laugh",
  confused = "confused",
  heart = "heart",
  tada = "hooray",
  rocket = "rocket",
  eyes = "eyes",
}
local CONTENT_TO_GL_EMOJI = {
  ["+1"] = "thumbsup",
  ["-1"] = "thumbsdown",
  laugh = "laughing",
  confused = "confused",
  heart = "heart",
  hooray = "tada",
  rocket = "rocket",
  eyes = "eyes",
}

local function translate_gl_award(a)
  if not a then
    return {}
  end
  local user = translate_gl_user(a.user or {})
  return {
    id = a.id,
    node_id = "",
    user = user,
    content = GL_EMOJI_TO_CONTENT[a.name] or a.name,
    created_at = a.created_at or "2020-01-01T00:00:00Z",
  }
end

local function translate_gl_awards(awards)
  return translate_list(translate_gl_award, awards)
end

-- ---------------------------------------------------------------------------
-- Issues capability module
-- ---------------------------------------------------------------------------
-- Owns fetch + translate_gl_issue / translate_gl_note for all issue and
-- issue-comment operations.  REST handlers call cap_rest_* adapters.
-- Single-item operations: (data, nil) on success, (nil, err) on failure.
-- Paged list operations:  (items, headers, nil) or (nil, nil, err).

local issues_cap = {}

-- list: paginated list of issues for a repository.
issues_cap.list = function(owner, repo_name)
  local url =
    append_page_params(base() .. "/projects/" .. project_id(owner, repo_name) .. "/issues", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_gl_issues(items), hdrs, nil
end

-- get: fetch a single issue by iid.
issues_cap.get = function(owner, repo_name, issue_number)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/issues/" .. issue_number
  )
  if not raw then
    return nil, err
  end
  return translate_gl_issue(raw), nil
end

-- create: open a new issue.  body is raw GitHub-format JSON string.
issues_cap.create = function(owner, repo_name, body)
  local req = DecodeJson(body or "{}")
  local gl = {}
  if req.title then
    gl.title = req.title
  end
  if req.body then
    gl.description = req.body
  end
  if req.milestone then
    gl.milestone_id = req.milestone
  end
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/issues",
    "POST",
    EncodeJson(gl)
  )
  if not raw then
    return nil, err
  end
  return translate_gl_issue(raw), nil
end

-- update: partially update an issue.  body is raw GitHub-format JSON string.
issues_cap.update = function(owner, repo_name, issue_number, body)
  local req = DecodeJson(body or "{}")
  local gl = {}
  if req.title then
    gl.title = req.title
  end
  if req.body then
    gl.description = req.body
  end
  if req.state then
    gl.state_event = req.state == "closed" and "close" or "reopen"
  end
  if req.milestone then
    gl.milestone_id = req.milestone
  end
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/issues/" .. issue_number,
    "PUT",
    EncodeJson(gl)
  )
  if not raw then
    return nil, err
  end
  return translate_gl_issue(raw), nil
end

-- list_comments: paginated list of notes (comments) on an issue.
issues_cap.list_comments = function(owner, repo_name, issue_number)
  local url = append_page_params(
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/issues/" .. issue_number .. "/notes",
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_gl_notes(items), hdrs, nil
end

-- create_comment: add a note (comment) to an issue.
issues_cap.create_comment = function(owner, repo_name, issue_number, body)
  local req = DecodeJson(body or "{}")
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/issues/" .. issue_number .. "/notes",
    "POST",
    EncodeJson({ body = req.body })
  )
  if not raw then
    return nil, err
  end
  return translate_gl_note(raw), nil
end

-- ---------------------------------------------------------------------------
-- Labels capability module
-- ---------------------------------------------------------------------------
-- Owns fetch + translate_gl_label for all label operations (repo-level and
-- per-issue label assignment/removal).
-- Single-item operations: (data, nil) on success, (nil, err) on failure.
-- Paged list operations:  (items, headers, nil) or (nil, nil, err).
-- Delete operations:      (true, nil) on success, (nil, err) on failure.

local labels_cap = {}

-- Helper: extract GitHub-shape label list from a raw GitLab issue body (which
-- stores labels as either strings or label objects depending on scope).
local function issue_labels_from_raw(issue)
  local labels = {}
  for _, l in ipairs((issue or {}).labels or {}) do
    if type(l) == "table" then
      labels[#labels + 1] = translate_gl_label(l)
    else
      labels[#labels + 1] = {
        id = 0,
        node_id = "",
        url = "",
        name = l,
        color = "",
        description = "",
        default = false,
      }
    end
  end
  return labels
end

-- list_repo: paginated list of labels for a repository.
labels_cap.list_repo = function(owner, repo_name)
  local url =
    append_page_params(base() .. "/projects/" .. project_id(owner, repo_name) .. "/labels", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_gl_labels(items), hdrs, nil
end

-- create_repo: create a label in a repository.  body is raw GitHub-format JSON.
labels_cap.create_repo = function(owner, repo_name, body)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/labels",
    "POST",
    body
  )
  if not raw then
    return nil, err
  end
  return translate_gl_label(raw), nil
end

-- get_repo: fetch a single repository label by name.
labels_cap.get_repo = function(owner, repo_name, label_name)
  local id = gl_find_label_id(owner, repo_name, label_name)
  if not id then
    return nil, cap_err(404, "Label not found")
  end
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/labels/" .. id
  )
  if not raw then
    return nil, err
  end
  return translate_gl_label(raw), nil
end

-- update_repo: update a repository label by name.  body is raw GitHub-format JSON.
labels_cap.update_repo = function(owner, repo_name, label_name, body)
  local id = gl_find_label_id(owner, repo_name, label_name)
  if not id then
    return nil, cap_err(404, "Label not found")
  end
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/labels/" .. id,
    "PUT",
    body
  )
  if not raw then
    return nil, err
  end
  return translate_gl_label(raw), nil
end

-- delete_repo: delete a repository label by name.
-- Returns (true, nil) on success or (nil, err) on failure.
labels_cap.delete_repo = function(owner, repo_name, label_name)
  local id = gl_find_label_id(owner, repo_name, label_name)
  if not id then
    return nil, cap_err(404, "Label not found")
  end
  local ok, status =
    fetch_json(base() .. "/projects/" .. project_id(owner, repo_name) .. "/labels/" .. id, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error deleting label " .. label_name)
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting label")
  end
  return true, nil
end

-- list_issue: return the labels currently on a single issue.
labels_cap.list_issue = function(owner, repo_name, issue_number)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/issues/" .. issue_number
  )
  if not raw then
    return nil, err
  end
  return issue_labels_from_raw(raw), nil
end

-- set_issue: add labels to an issue (merge with existing).
-- new_labels is an array of label name strings.
labels_cap.set_issue = function(owner, repo_name, issue_number, new_labels)
  -- Fetch current labels first so we can merge.
  local existing_raw, existing_err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/issues/" .. issue_number
  )
  if not existing_raw then
    return nil, existing_err
  end
  local all_labels = existing_raw.labels or {}
  for _, name in ipairs(new_labels or {}) do
    all_labels[#all_labels + 1] = name
  end
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/issues/" .. issue_number,
    "PUT",
    EncodeJson({ labels = all_labels })
  )
  if not raw then
    return nil, err
  end
  return issue_labels_from_raw(raw), nil
end

-- replace_issue: replace all labels on an issue.
-- label_names is an array of label name strings.
labels_cap.replace_issue = function(owner, repo_name, issue_number, label_names)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/issues/" .. issue_number,
    "PUT",
    EncodeJson({ labels = label_names or {} })
  )
  if not raw then
    return nil, err
  end
  return issue_labels_from_raw(raw), nil
end

-- delete_issue_all: remove all labels from an issue.
-- Returns (true, nil) on success or (nil, err) on failure.
labels_cap.delete_issue_all = function(owner, repo_name, issue_number)
  local ok, status = fetch_json(
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/issues/" .. issue_number,
    "PUT",
    EncodeJson({ labels = {} })
  )
  if not ok then
    return nil,
      cap_err(0, "network error removing all labels from issue " .. tostring(issue_number))
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " removing labels")
  end
  return true, nil
end

-- delete_issue_one: remove a single named label from an issue.
-- Returns (true, nil) on success or (nil, err) on failure.
labels_cap.delete_issue_one = function(owner, repo_name, issue_number, label_name)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/issues/" .. issue_number
  )
  if not raw then
    return nil, err
  end
  local labels = {}
  for _, l in ipairs(raw.labels or {}) do
    local name = type(l) == "table" and l.name or l
    if name ~= label_name then
      labels[#labels + 1] = name
    end
  end
  local ok, status = fetch_json(
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/issues/" .. issue_number,
    "PUT",
    EncodeJson({ labels = labels })
  )
  if not ok then
    return nil, cap_err(0, "network error removing label " .. label_name)
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " removing label")
  end
  return true, nil
end

-- ---------------------------------------------------------------------------
-- Milestones capability module
-- ---------------------------------------------------------------------------
-- Owns fetch + translate_gl_milestone for all milestone operations.
-- Single-item operations: (data, nil) on success, (nil, err) on failure.
-- Paged list operations:  (items, headers, nil) or (nil, nil, err).
-- Delete operations:      (true, nil) on success, (nil, err) on failure.

local milestones_cap = {}

-- list: paginated list of milestones for a repository.
milestones_cap.list = function(owner, repo_name)
  local url = append_page_params(
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/milestones",
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_gl_milestones(items), hdrs, nil
end

-- create: create a milestone.  body is raw GitHub-format JSON string.
milestones_cap.create = function(owner, repo_name, body)
  local req = DecodeJson(body or "{}")
  local gl = {}
  if req.title then
    gl.title = req.title
  end
  if req.description then
    gl.description = req.description
  end
  if req.due_on then
    gl.due_date = req.due_on
  end
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/milestones",
    "POST",
    EncodeJson(gl)
  )
  if not raw then
    return nil, err
  end
  return translate_gl_milestone(raw), nil
end

-- get: fetch a single milestone by number (iid).
milestones_cap.get = function(owner, repo_name, milestone_number)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/milestones/" .. milestone_number
  )
  if not raw then
    return nil, err
  end
  return translate_gl_milestone(raw), nil
end

-- update: partially update a milestone.  body is raw GitHub-format JSON string.
milestones_cap.update = function(owner, repo_name, milestone_number, body)
  local req = DecodeJson(body or "{}")
  local gl = {}
  if req.title then
    gl.title = req.title
  end
  if req.description then
    gl.description = req.description
  end
  if req.state then
    gl.state_event = req.state == "closed" and "close" or "activate"
  end
  if req.due_on then
    gl.due_date = req.due_on
  end
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/milestones/" .. milestone_number,
    "PUT",
    EncodeJson(gl)
  )
  if not raw then
    return nil, err
  end
  return translate_gl_milestone(raw), nil
end

-- delete: permanently remove a milestone.
-- Returns (true, nil) on success or (nil, err) on failure.
milestones_cap.delete = function(owner, repo_name, milestone_number)
  local ok, status = fetch_json(
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/milestones/" .. milestone_number,
    "DELETE"
  )
  if not ok then
    return nil, cap_err(0, "network error deleting milestone " .. tostring(milestone_number))
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting milestone")
  end
  return true, nil
end

-- ---------------------------------------------------------------------------
-- Reactions capability module
-- ---------------------------------------------------------------------------
-- Owns fetch + translate_gl_award for all reaction (award emoji) operations.
-- Paged list operations:  (items, headers, nil) or (nil, nil, err).
-- Single-item operations: (data, nil) on success, (nil, err) on failure.
-- Delete operations:      (true, nil) on success, (nil, err) on failure.

local reactions_cap = {}

-- list_issue: paginated list of reactions for an issue.
reactions_cap.list_issue = function(owner, repo_name, issue_number)
  local url = append_page_params(
    base()
      .. "/projects/"
      .. project_id(owner, repo_name)
      .. "/issues/"
      .. issue_number
      .. "/award_emoji",
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_gl_awards(items), hdrs, nil
end

-- create_issue: add a reaction to an issue.  body is raw GitHub-format JSON string.
reactions_cap.create_issue = function(owner, repo_name, issue_number, body)
  local req = DecodeJson(body or "{}") or {}
  local emoji = CONTENT_TO_GL_EMOJI[req.content or ""] or req.content or ""
  local raw, err = cap_fetch(
    fetch_json,
    base()
      .. "/projects/"
      .. project_id(owner, repo_name)
      .. "/issues/"
      .. issue_number
      .. "/award_emoji",
    "POST",
    EncodeJson({ name = emoji })
  )
  if not raw then
    return nil, err
  end
  return translate_gl_award(raw), nil
end

-- delete_issue: remove a reaction from an issue by reaction id.
-- Returns (true, nil) on success or (nil, err) on failure.
reactions_cap.delete_issue = function(owner, repo_name, issue_number, reaction_id)
  local ok, status = fetch_json(
    base()
      .. "/projects/"
      .. project_id(owner, repo_name)
      .. "/issues/"
      .. issue_number
      .. "/award_emoji/"
      .. reaction_id,
    "DELETE"
  )
  if not ok then
    return nil, cap_err(0, "network error deleting reaction " .. tostring(reaction_id))
  end
  if status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting reaction")
  end
  return true, nil
end

-- ---------------------------------------------------------------------------
-- Contents capability module
-- ---------------------------------------------------------------------------
-- Owns fetch + translate for repository file operations (GitLab repository files API).
-- Single-item operations return (data, nil) on success or (nil, err) on failure.
-- PUT/DELETE operations proxy the raw upstream response (no GitHub translation).

local contents_cap = {}

-- translate_gl_file: map a GitLab file metadata object to GitHub content shape.
local function translate_gl_file(f)
  if not f then
    return {}
  end
  return {
    name = f.file_name,
    path = f.file_path,
    sha = f.blob_id,
    size = f.size,
    type = "file",
    encoding = f.encoding,
    content = f.content,
  }
end

-- get_readme: fetch the root README.md for a repository.
-- Returns translated file shape or (nil, err).
contents_cap.get_readme = function(owner, repo_name)
  local url = base()
    .. "/projects/"
    .. project_id(owner, repo_name)
    .. "/repository/files/README.md?ref=HEAD"
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  return translate_gl_file(raw), nil
end

-- get_readme_dir: fetch a README.md inside a subdirectory.
-- Returns translated file shape or (nil, err).
contents_cap.get_readme_dir = function(owner, repo_name, dir)
  local enc_path = dir:gsub("/", "%%2F") .. "%%2FREADME.md"
  local url = base()
    .. "/projects/"
    .. project_id(owner, repo_name)
    .. "/repository/files/"
    .. enc_path
    .. "?ref=HEAD"
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  return translate_gl_file(raw), nil
end

-- get: fetch a single file by path.
-- Returns translated file shape or (nil, err).
contents_cap.get = function(owner, repo_name, path)
  local enc_path = path:gsub("/", "%%2F")
  local url = base()
    .. "/projects/"
    .. project_id(owner, repo_name)
    .. "/repository/files/"
    .. enc_path
    .. "?ref=HEAD"
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  return translate_gl_file(raw), nil
end

-- put: create or update a file.  body is raw GitHub-format JSON string.
-- Returns the raw upstream response (no GitHub translation) or (nil, err).
contents_cap.put = function(owner, repo_name, path, body)
  local enc_path = path:gsub("/", "%%2F")
  local req = DecodeJson(body or "{}") or {}
  -- Check if file exists to decide create vs update.
  local ok, status = pcall(
    Fetch,
    base()
      .. "/projects/"
      .. project_id(owner, repo_name)
      .. "/repository/files/"
      .. enc_path
      .. "?ref="
      .. (req.branch or "HEAD"),
    auth()
  )
  local method = (ok and status == 200) and "PUT" or "POST"
  local gl_body = EncodeJson({
    branch = req.branch or "main",
    content = req.content,
    commit_message = req.message,
    encoding = req.encoding or "base64",
  })
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/repository/files/" .. enc_path,
    method,
    gl_body
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- delete: delete a file by path.  body is raw GitHub-format JSON string.
-- Returns the raw upstream response or (nil, err).
contents_cap.delete = function(owner, repo_name, path, body)
  local enc_path = path:gsub("/", "%%2F")
  local req = DecodeJson(body or "{}") or {}
  local gl_body = EncodeJson({
    branch = req.branch or "main",
    commit_message = req.message,
    sha = req.sha,
  })
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/repository/files/" .. enc_path,
    "DELETE",
    gl_body
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- ---------------------------------------------------------------------------
-- Commit comments capability module
-- ---------------------------------------------------------------------------
-- Owns fetch + translate for commit comment operations.
-- GitLab uses /projects/{id}/repository/commits/{sha}/comments.
-- Paginated list operations return (items, headers, nil) or (nil, nil, err).
-- Create operations return (data, nil) or (nil, err).

local commit_comments_cap = {}

-- list: paginated list of comments for a commit.
commit_comments_cap.list = function(owner, repo_name, commit_sha)
  local url = append_page_params(
    base()
      .. "/projects/"
      .. project_id(owner, repo_name)
      .. "/repository/commits/"
      .. commit_sha
      .. "/comments",
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return items, hdrs, nil
end

-- create: post a new comment on a commit.  body is raw JSON string.
-- Returns the raw upstream response or (nil, err).
commit_comments_cap.create = function(owner, repo_name, commit_sha, body)
  local url = base()
    .. "/projects/"
    .. project_id(owner, repo_name)
    .. "/repository/commits/"
    .. commit_sha
    .. "/comments"
  local raw, err = cap_fetch(fetch_json, url, "POST", body)
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- ---------------------------------------------------------------------------
-- Collaborators capability module
-- ---------------------------------------------------------------------------
-- Owns fetch + translate for project member operations.
-- GitLab uses /projects/{id}/members/all (list) and /projects/{id}/members/{uid}.
-- Username→UID resolution is done internally via /users?username=.
-- Paginated list operations return (items, headers, nil) or (nil, nil, err).
-- Single-item and 204 operations return (data, nil) or (nil, err).

local collaborators_cap = {}

-- translate_gl_collaborator: map a GitLab project member object to GitHub collaborator shape.
local function translate_gl_collaborator(m)
  if not m then
    return {}
  end
  local al = m.access_level or 0
  return {
    login = m.username,
    id = m.id,
    avatar_url = m.avatar_url or "",
    type = "User",
    permissions = {
      admin = al >= 50,
      push = al >= 30,
      pull = al >= 10,
    },
  }
end

-- resolve_uid: look up a GitLab user ID by username.
-- Returns (uid, nil) or (nil, err).
local function resolve_uid(username)
  local ok, status, _, ubody = fetch_json(base() .. "/users?username=" .. username)
  if not ok or status ~= 200 then
    return nil, cap_err(status or 0, "user lookup failed")
  end
  local ulist = DecodeJson(ubody) or {}
  local uid = ulist[1] and ulist[1].id
  if not uid then
    return nil, cap_err(404, "user not found")
  end
  return uid, nil
end

-- list: paginated list of project members.
collaborators_cap.list = function(owner, repo_name)
  local url = append_page_params(
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/members/all",
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_collaborator, items), hdrs, nil
end

-- check: return (true, nil) if username is a member, (nil, err) if not.
collaborators_cap.check = function(owner, repo_name, username)
  local uid, uerr = resolve_uid(username)
  if not uid then
    return nil, uerr
  end
  local ok, status = pcall(
    Fetch,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/members/" .. uid,
    auth()
  )
  if ok and status == 200 then
    return true, nil
  end
  return nil, cap_err(404, "Not a collaborator")
end

-- put: add or update a member.  body is raw GitHub-format JSON.
-- Returns (true, nil) on success or (nil, err).
collaborators_cap.put = function(owner, repo_name, username, body)
  local uid, uerr = resolve_uid(username)
  if not uid then
    return nil, uerr
  end
  local req = DecodeJson(body or "{}") or {}
  local perm = req.permission or "push"
  local level_map = { pull = 30, push = 30, admin = 50 }
  local gl_body = EncodeJson({ user_id = uid, access_level = level_map[perm] or 30 })
  -- Try add first; if conflict (409), update instead.
  local ok2, status2 = fetch_json(
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/members",
    "POST",
    gl_body
  )
  if ok2 and (status2 == 201 or status2 == 200) then
    return true, nil
  elseif ok2 and status2 == 409 then
    local ok3, status3 = fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/members/" .. uid,
      "PUT",
      gl_body
    )
    if ok3 and (status3 == 200 or status3 == 201) then
      return true, nil
    else
      return nil, cap_err(status3 or 0, "update member failed")
    end
  else
    return nil, cap_err(status2 or 0, "add member failed")
  end
end

-- delete: remove a member.  Returns (true, nil) or (nil, err).
collaborators_cap.delete = function(owner, repo_name, username)
  local uid, uerr = resolve_uid(username)
  if not uid then
    return nil, uerr
  end
  local ok2, status2 = fetch_json(
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/members/" .. uid,
    "DELETE"
  )
  if ok2 and (status2 == 204 or status2 == 200) then
    return true, nil
  end
  return nil, cap_err(status2 or 0, "remove member failed")
end

-- get_permission: return permission level for a user.
-- Returns (data, nil) or (nil, err).
collaborators_cap.get_permission = function(owner, repo_name, username)
  local uid, uerr = resolve_uid(username)
  if not uid then
    return nil, uerr
  end
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/members/" .. uid
  )
  if not raw then
    return nil, err
  end
  local al = raw.access_level or 0
  local perm = al >= 50 and "admin" or (al >= 30 and "write" or "read")
  return { permission = perm, user = { login = username, id = uid } }, nil
end

-- ---------------------------------------------------------------------------
-- Forks capability module
-- ---------------------------------------------------------------------------
-- Owns fetch + translate for fork operations.
-- GitLab uses /projects/{id}/forks (list) and /projects/{id}/fork (create).
-- Paginated list operations return (items, headers, nil) or (nil, nil, err).
-- Create operation returns (data, nil) or (nil, err).

local forks_cap = {}

-- list: paginated list of forks for a repository.
forks_cap.list = function(owner, repo_name)
  local url =
    append_page_params(base() .. "/projects/" .. project_id(owner, repo_name) .. "/forks", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_repo, items), hdrs, nil
end

-- create: fork a repository.  body is raw GitHub-format JSON.
-- Returns translated repo shape or (nil, err).
forks_cap.create = function(owner, repo_name, body)
  local req = DecodeJson(body or "{}") or {}
  local gl_body = req.organization and EncodeJson({ namespace = req.organization }) or "{}"
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/fork",
    "POST",
    gl_body
  )
  if not raw then
    return nil, err
  end
  return translate_gl_repo(raw), nil
end

-- ---------------------------------------------------------------------------
-- Pulls capability module
-- ---------------------------------------------------------------------------
-- Owns fetch + translate for pull request (merge request) operations.
-- GitLab uses /projects/{id}/merge_requests and related sub-resources.

local pulls_cap = {}

-- list: paginated list of merge requests for a repository.
-- Returns (items, headers, nil) or (nil, nil, err).
pulls_cap.list = function(owner, repo_name)
  local url = append_page_params(
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/merge_requests",
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_mr, items), hdrs, nil
end

-- create: open a new merge request.  body is raw GitHub-format JSON.
-- Returns (data, nil) or (nil, err).
pulls_cap.create = function(owner, repo_name, body)
  local req = DecodeJson(body or "{}") or {}
  local gl = {}
  if req.title then
    gl.title = req.title
  end
  if req.body then
    gl.description = req.body
  end
  if req.head then
    gl.source_branch = req.head
  end
  if req.base then
    gl.target_branch = req.base
  end
  if req.draft ~= nil then
    gl.draft = req.draft
  end
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/merge_requests",
    "POST",
    EncodeJson(gl)
  )
  if not raw then
    return nil, err
  end
  return translate_gl_mr(raw), nil
end

-- get: fetch a single merge request by iid.
-- Returns (data, nil) or (nil, err).
pulls_cap.get = function(owner, repo_name, pull_number)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/merge_requests/" .. pull_number
  )
  if not raw then
    return nil, err
  end
  return translate_gl_mr(raw), nil
end

-- update: update a merge request.  body is raw GitHub-format JSON.
-- Returns (data, nil) or (nil, err).
pulls_cap.update = function(owner, repo_name, pull_number, body)
  local req = DecodeJson(body or "{}") or {}
  local gl = {}
  if req.title then
    gl.title = req.title
  end
  if req.body then
    gl.description = req.body
  end
  if req.state then
    gl.state_event = req.state == "closed" and "close" or "reopen"
  end
  if req.draft ~= nil then
    gl.draft = req.draft
  end
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/merge_requests/" .. pull_number,
    "PUT",
    EncodeJson(gl)
  )
  if not raw then
    return nil, err
  end
  return translate_gl_mr(raw), nil
end

-- list_commits: paginated list of commits for a merge request.
-- Returns (items, headers, nil) or (nil, nil, err).
pulls_cap.list_commits = function(owner, repo_name, pull_number)
  local url = append_page_params(
    base()
      .. "/projects/"
      .. project_id(owner, repo_name)
      .. "/merge_requests/"
      .. pull_number
      .. "/commits",
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  local result = {}
  for _, c in ipairs(items) do
    result[#result + 1] = {
      sha = c.id,
      html_url = c.web_url or "",
      commit = {
        message = c.message,
        author = { name = c.author_name, email = c.author_email, date = c.authored_date },
        committer = {
          name = c.committer_name or c.author_name,
          email = c.committer_email or c.author_email,
          date = c.committed_date or c.authored_date,
        },
      },
    }
  end
  return result, hdrs, nil
end

-- list_files: get changed files for a merge request.
-- Returns (data, nil) or (nil, err).
pulls_cap.list_files = function(owner, repo_name, pull_number)
  local raw, err = cap_fetch(
    fetch_json,
    base()
      .. "/projects/"
      .. project_id(owner, repo_name)
      .. "/merge_requests/"
      .. pull_number
      .. "/changes"
  )
  if not raw then
    return nil, err
  end
  local result = {}
  for _, c in ipairs((raw or {}).changes or {}) do
    local status = "modified"
    if c.new_file then
      status = "added"
    elseif c.deleted_file then
      status = "removed"
    elseif c.renamed_file then
      status = "renamed"
    end
    result[#result + 1] = {
      sha = "",
      filename = c.new_path or c.old_path or "",
      status = status,
      additions = 0,
      deletions = 0,
      changes = 0,
      patch = c.diff,
    }
  end
  return result, nil
end

-- check_merged: return (true, nil) if the MR is merged, (nil, err) if not.
-- Uses err.status == 404 to indicate "not merged".
pulls_cap.check_merged = function(owner, repo_name, pull_number)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/merge_requests/" .. pull_number
  )
  if not raw then
    return nil, err
  end
  if raw.state == "merged" or raw.merged_at ~= nil then
    return true, nil
  end
  return nil, cap_err(404, "Pull Request is not merged")
end

-- merge: merge a merge request.  body is raw GitHub-format JSON.
-- Returns (true, nil) or (nil, err).
pulls_cap.merge = function(owner, repo_name, pull_number, body)
  local req = DecodeJson(body or "{}") or {}
  local gl = {}
  if req.merge_method then
    gl.merge_method = req.merge_method
  end
  local ok, status = fetch_json(
    base()
      .. "/projects/"
      .. project_id(owner, repo_name)
      .. "/merge_requests/"
      .. pull_number
      .. "/merge",
    "PUT",
    EncodeJson(gl)
  )
  if ok and (status == 200 or status == 201 or status == 204) then
    return true, nil
  end
  return nil, cap_err(status or 0, "merge failed")
end

-- list_requested_reviewers: get reviewers assigned to a merge request.
-- Returns (data, nil) or (nil, err).
pulls_cap.list_requested_reviewers = function(owner, repo_name, pull_number)
  local raw, err = cap_fetch(
    fetch_json,
    base()
      .. "/projects/"
      .. project_id(owner, repo_name)
      .. "/merge_requests/"
      .. pull_number
      .. "/reviewers"
  )
  if not raw then
    return nil, err
  end
  local reviewer_users = {}
  for _, u in ipairs(raw) do
    reviewer_users[#reviewer_users + 1] = translate_gl_user(u)
  end
  return { users = reviewer_users, teams = {} }, nil
end

-- list_reviews: get approvals mapped to GitHub review objects.
-- Returns (data, nil) or (nil, err).
pulls_cap.list_reviews = function(owner, repo_name, pull_number)
  local raw, err = cap_fetch(
    fetch_json,
    base()
      .. "/projects/"
      .. project_id(owner, repo_name)
      .. "/merge_requests/"
      .. pull_number
      .. "/approvals"
  )
  if not raw then
    return nil, err
  end
  return translate_gl_approvals_to_reviews(raw), nil
end

-- get_review: get a single review by 1-based index id.
-- Returns (data, nil) or (nil, err).
pulls_cap.get_review = function(owner, repo_name, pull_number, review_id)
  local reviews, err = pulls_cap.list_reviews(owner, repo_name, pull_number)
  if not reviews then
    return nil, err
  end
  local rid = tonumber(review_id)
  if rid and reviews[rid] then
    return reviews[rid], nil
  end
  return nil, cap_err(404, "Not Found")
end

-- list_review_comments: get inline (position-based) MR notes.
-- GitLab has no per-review inline comments; returns all inline MR notes.
-- Returns (data, nil) or (nil, err).
pulls_cap.list_review_comments = function(owner, repo_name, pull_number)
  local result, status = fetch_gl_mr_review_comments(owner, repo_name, pull_number)
  if not result then
    return nil, cap_err(status or 0, "fetch review comments failed")
  end
  return result, nil
end

-- ---------------------------------------------------------------------------
-- Releases capability module
-- ---------------------------------------------------------------------------
-- Owns fetch + translate for release and release asset (link) operations.
-- GitLab identifies releases by tag_name; GitHub uses integer IDs.
-- gl_tag_by_id and gl_find_link are helpers defined above.

local releases_cap = {}

-- list: paginated list of releases for a repository.
-- Returns (items, headers, nil) or (nil, nil, err).
releases_cap.list = function(owner, repo_name)
  local url =
    append_page_params(base() .. "/projects/" .. project_id(owner, repo_name) .. "/releases", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  local result = {}
  for i, r in ipairs(items) do
    result[i] = translate_gl_release(r, i)
  end
  return result, hdrs, nil
end

-- create: create a new release.  body is raw GitHub-format JSON.
-- Returns (data, nil) or (nil, err).
releases_cap.create = function(owner, repo_name, body)
  local req = DecodeJson(body or "{}") or {}
  local gl_body = EncodeJson({
    tag_name = req.tag_name,
    name = req.name,
    description = req.body,
  })
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/releases",
    "POST",
    gl_body
  )
  if not raw then
    return nil, err
  end
  return translate_gl_release(raw, 1), nil
end

-- get_latest: get the latest release.
-- Returns (data, nil) or (nil, err).
releases_cap.get_latest = function(owner, repo_name)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/releases/permalink/latest"
  )
  if not raw then
    return nil, err
  end
  return translate_gl_release(raw, 1), nil
end

-- get_by_tag: get a release by its tag name.
-- Returns (data, nil) or (nil, err).
releases_cap.get_by_tag = function(owner, repo_name, tag)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/releases/" .. tag
  )
  if not raw then
    return nil, err
  end
  return translate_gl_release(raw, 1), nil
end

-- get: get a release by GitHub integer release_id (resolved via gl_tag_by_id).
-- Returns (data, nil) or (nil, err).
releases_cap.get = function(owner, repo_name, release_id)
  local tag = gl_tag_by_id(owner, repo_name, release_id)
  if not tag then
    return nil, cap_err(404, "Not Found")
  end
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/releases/" .. tag
  )
  if not raw then
    return nil, err
  end
  return translate_gl_release(raw, tonumber(release_id)), nil
end

-- update: update a release by GitHub integer release_id.  body is raw GitHub-format JSON.
-- Returns (data, nil) or (nil, err).
releases_cap.update = function(owner, repo_name, release_id, body)
  local tag = gl_tag_by_id(owner, repo_name, release_id)
  if not tag then
    return nil, cap_err(404, "Not Found")
  end
  local req = DecodeJson(body or "{}") or {}
  local gl_body = EncodeJson({ name = req.name, description = req.body })
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/releases/" .. tag,
    "PUT",
    gl_body
  )
  if not raw then
    return nil, err
  end
  return translate_gl_release(raw, tonumber(release_id)), nil
end

-- delete: delete a release by GitHub integer release_id.
-- Returns (true, nil) or (nil, err).
releases_cap.delete = function(owner, repo_name, release_id)
  local tag = gl_tag_by_id(owner, repo_name, release_id)
  if not tag then
    return nil, cap_err(404, "Not Found")
  end
  local ok, status = fetch_json(
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/releases/" .. tag,
    "DELETE"
  )
  if not ok or (status ~= 200 and status ~= 204) then
    return nil, cap_err(status or 0, "delete release failed")
  end
  return true, nil
end

-- list_assets: paginated list of release assets (links) by GitHub integer release_id.
-- Returns (items, headers, nil) or (nil, nil, err).
releases_cap.list_assets = function(owner, repo_name, release_id)
  local tag = gl_tag_by_id(owner, repo_name, release_id)
  if not tag then
    return nil, nil, cap_err(404, "Not Found")
  end
  local url = append_page_params(
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/releases/" .. tag .. "/assets/links",
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_link, items), hdrs, nil
end

-- create_asset: create a release asset (link) for a release by GitHub integer release_id.
-- Returns (data, nil) or (nil, err).
releases_cap.create_asset = function(owner, repo_name, release_id, body)
  local tag = gl_tag_by_id(owner, repo_name, release_id)
  if not tag then
    return nil, cap_err(404, "Not Found")
  end
  local req = DecodeJson(body or "{}") or {}
  local gl_body = EncodeJson({ name = req.name, url = req.url or "" })
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/releases/" .. tag .. "/assets/links",
    "POST",
    gl_body
  )
  if not raw then
    return nil, err
  end
  return translate_gl_link(raw), nil
end

-- get_asset: get a release asset (link) by asset_id.
-- Returns (data, nil) or (nil, err).
releases_cap.get_asset = function(owner, repo_name, asset_id)
  local tag = gl_find_link(owner, repo_name, asset_id)
  if not tag then
    return nil, cap_err(404, "Not Found")
  end
  local raw, err = cap_fetch(
    fetch_json,
    base()
      .. "/projects/"
      .. project_id(owner, repo_name)
      .. "/releases/"
      .. tag
      .. "/assets/links/"
      .. asset_id
  )
  if not raw then
    return nil, err
  end
  return translate_gl_link(raw), nil
end

-- update_asset: update a release asset (link) by asset_id.  body is raw GitHub-format JSON.
-- Returns (data, nil) or (nil, err).
releases_cap.update_asset = function(owner, repo_name, asset_id, body)
  local tag = gl_find_link(owner, repo_name, asset_id)
  if not tag then
    return nil, cap_err(404, "Not Found")
  end
  local req = DecodeJson(body or "{}") or {}
  local gl_body = EncodeJson({ name = req.name })
  local raw, err = cap_fetch(
    fetch_json,
    base()
      .. "/projects/"
      .. project_id(owner, repo_name)
      .. "/releases/"
      .. tag
      .. "/assets/links/"
      .. asset_id,
    "PUT",
    gl_body
  )
  if not raw then
    return nil, err
  end
  return translate_gl_link(raw), nil
end

-- delete_asset: delete a release asset (link) by asset_id.
-- Returns (true, nil) or (nil, err).
releases_cap.delete_asset = function(owner, repo_name, asset_id)
  local tag = gl_find_link(owner, repo_name, asset_id)
  if not tag then
    return nil, cap_err(404, "Not Found")
  end
  local ok, status = fetch_json(
    base()
      .. "/projects/"
      .. project_id(owner, repo_name)
      .. "/releases/"
      .. tag
      .. "/assets/links/"
      .. asset_id,
    "DELETE"
  )
  if not ok or (status ~= 200 and status ~= 204) then
    return nil, cap_err(status or 0, "delete release asset failed")
  end
  return true, nil
end

local b = make_backend_builder()

b:rest("get_root", function()
  proxy_health_check(pcall(Fetch, base() .. "/version", auth()))
end)

-- GET /repos/{owner}/{repo}
b:rest("get_repo", function(owner, repo_name)
  local data, err = repos.get(owner, repo_name)
  cap_rest_respond(data, err)
end)

-- PATCH /repos/{owner}/{repo}
b:rest("patch_repo", function(owner, repo_name)
  local data, err = repos.update(owner, repo_name, GetBody())
  cap_rest_respond(data, err)
end)

-- DELETE /repos/{owner}/{repo}
b:rest("delete_repo", function(owner, repo_name)
  local ok, err = repos.delete(owner, repo_name)
  cap_rest_204(ok, err)
end)

-- GET /user/repos
b:rest("get_user_repos", function()
  local items, hdrs, err = repos.list_user()
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- POST /user/repos
b:rest("post_user_repos", function()
  local data, err = repos.create_user(GetBody())
  cap_rest_created(data, err)
end)

-- GET /orgs/{org}/repos
b:rest("get_org_repos", function(org)
  local items, hdrs, err = repos.list_org(org)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- POST /orgs/{org}/repos
b:rest("post_org_repos", function(org)
  local data, err = repos.create_org(org, GetBody())
  cap_rest_created(data, err)
end)

-- GET /repos/{owner}/{repo}/topics
b:rest("get_repo_topics", function(owner, repo_name)
  local data, err = repos.get_topics(owner, repo_name)
  cap_rest_respond(data, err)
end)

-- PUT /repos/{owner}/{repo}/topics
b:rest("put_repo_topics", function(owner, repo_name)
  local data, err = repos.put_topics(owner, repo_name, GetBody())
  cap_rest_respond(data, err)
end)

b:rest(
  "get_repo_languages",
  proxy_handler(nil, function(owner, repo_name)
    return base() .. "/projects/" .. project_id(owner, repo_name) .. "/languages"
  end)
)

b:rest(
  "get_repo_contributors",
  proxy_handler_paged(function(contribs)
    for i, c in ipairs(contribs) do
      contribs[i] = { login = c.name, contributions = c.commits }
    end
    return contribs
  end, function(owner, repo_name)
    return append_page_params(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/repository/contributors",
      PAGES
    )
  end)
)

b:rest(
  "get_repo_tags",
  proxy_handler_paged(function(tags)
    for i, t in ipairs(tags) do
      local c = t.commit or {}
      tags[i] = { name = t.name, commit = { sha = c.id, url = "" } }
    end
    return tags
  end, function(owner, repo_name)
    return append_page_params(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/repository/tags",
      PAGES
    )
  end)
)

-- Branches ------------------------------------------------------------------

-- GET /repos/{owner}/{repo}/branches
b:rest("get_repo_branches", function(owner, repo_name)
  local items, hdrs, err = branches.list(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- GET /repos/{owner}/{repo}/branches/{branch}
b:rest("get_repo_branch", function(owner, repo_name, branch)
  local data, err = branches.get(owner, repo_name, branch)
  cap_rest_respond(data, err)
end)

-- Commits -------------------------------------------------------------------

-- GET /repos/{owner}/{repo}/commits
b:rest("get_repo_commits", function(owner, repo_name)
  local items, hdrs, err = commits.list(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- GET /repos/{owner}/{repo}/commits/{ref}
b:rest("get_repo_commit", function(owner, repo_name, ref)
  local data, err = commits.get(owner, repo_name, ref)
  cap_rest_respond(data, err)
end)

-- Statuses ------------------------------------------------------------------

-- GET /repos/{owner}/{repo}/commits/{ref}/statuses
b:rest("get_commit_statuses", function(owner, repo_name, ref)
  local items, hdrs, err = statuses_cap.list(owner, repo_name, ref)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- GET /repos/{owner}/{repo}/commits/{ref}/status
b:rest("get_commit_combined_status", function(owner, repo_name, ref)
  local data, err = statuses_cap.get_combined(owner, repo_name, ref)
  cap_rest_respond(data, err)
end)

-- POST /repos/{owner}/{repo}/statuses/{sha}
b:rest("post_commit_status", function(owner, repo_name, sha)
  local data, err = statuses_cap.create(owner, repo_name, sha, GetBody())
  cap_rest_created(data, err)
end)

-- Contents ------------------------------------------------------------------

b:rest("get_repo_readme", function(owner, repo_name)
  local data, err = contents_cap.get_readme(owner, repo_name)
  cap_rest_respond(data, err)
end)

b:rest("get_repo_readme_dir", function(owner, repo_name, dir)
  local data, err = contents_cap.get_readme_dir(owner, repo_name, dir)
  cap_rest_respond(data, err)
end)

b:rest("get_repo_content", function(owner, repo_name, path)
  local data, err = contents_cap.get(owner, repo_name, path)
  cap_rest_respond(data, err)
end)

b:rest("put_repo_content", function(owner, repo_name, path)
  local data, err = contents_cap.put(owner, repo_name, path, GetBody())
  cap_rest_respond(data, err)
end)

b:rest("delete_repo_content", function(owner, repo_name, path)
  local data, err = contents_cap.delete(owner, repo_name, path, GetBody())
  cap_rest_respond(data, err)
end)

b:rest("get_repo_tarball", function(owner, repo_name, ref)
  SetStatus(302, "Found")
  SetHeader(
    "Location",
    base()
      .. "/projects/"
      .. project_id(owner, repo_name)
      .. "/repository/archive.tar.gz?sha="
      .. ref
  )
  Write("")
end)

b:rest("get_repo_zipball", function(owner, repo_name, ref)
  SetStatus(302, "Found")
  SetHeader(
    "Location",
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/repository/archive.zip?sha=" .. ref
  )
  Write("")
end)

-- Compare -------------------------------------------------------------------

b:rest("get_repo_compare", function(owner, repo_name, basehead)
  -- Split "base...head" or "base..head"
  local base_ref, head_ref = basehead:match("^(.-)%.%.%.(.+)$")
  if not base_ref then
    base_ref, head_ref = basehead:match("^(.-)%.%.(.+)$")
  end
  if not base_ref then
    base_ref = "HEAD"
    head_ref = basehead
  end
  proxy_json(
    nil,
    fetch_json(
      base()
        .. "/projects/"
        .. project_id(owner, repo_name)
        .. "/repository/compare?from="
        .. base_ref
        .. "&to="
        .. head_ref
    )
  )
end)

-- Collaborators -------------------------------------------------------------

-- GET /repos/{owner}/{repo}/collaborators
b:rest("get_repo_collaborators", function(owner, repo_name)
  local items, hdrs, err = collaborators_cap.list(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- GET /repos/{owner}/{repo}/collaborators/{username}
b:rest("get_repo_collaborator", function(owner, repo_name, username)
  local ok, err = collaborators_cap.check(owner, repo_name, username)
  cap_rest_204(ok, err)
end)

-- PUT /repos/{owner}/{repo}/collaborators/{username}
b:rest("put_repo_collaborator", function(owner, repo_name, username)
  local ok, err = collaborators_cap.put(owner, repo_name, username, GetBody())
  cap_rest_204(ok, err)
end)

-- DELETE /repos/{owner}/{repo}/collaborators/{username}
b:rest("delete_repo_collaborator", function(owner, repo_name, username)
  local ok, err = collaborators_cap.delete(owner, repo_name, username)
  cap_rest_204(ok, err)
end)

-- GET /repos/{owner}/{repo}/collaborators/{username}/permission
b:rest("get_repo_collaborator_permission", function(owner, repo_name, username)
  local data, err = collaborators_cap.get_permission(owner, repo_name, username)
  cap_rest_respond(data, err)
end)

-- Forks ---------------------------------------------------------------------

-- GET /repos/{owner}/{repo}/forks
b:rest("get_repo_forks", function(owner, repo_name)
  local items, hdrs, err = forks_cap.list(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- POST /repos/{owner}/{repo}/forks
b:rest("post_repo_forks", function(owner, repo_name)
  local data, err = forks_cap.create(owner, repo_name, GetBody())
  cap_rest_created(data, err)
end)

-- Releases ------------------------------------------------------------------
-- GitLab releases use tag_name as identifier rather than an integer ID.

b:rest("get_repo_releases", function(owner, repo_name)
  local items, hdrs, err = releases_cap.list(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

b:rest("post_repo_releases", function(owner, repo_name)
  local data, err = releases_cap.create(owner, repo_name, GetBody())
  cap_rest_created(data, err)
end)

b:rest("get_repo_release_latest", function(owner, repo_name)
  local data, err = releases_cap.get_latest(owner, repo_name)
  cap_rest_respond(data, err)
end)

b:rest("get_repo_release_by_tag", function(owner, repo_name, tag)
  local data, err = releases_cap.get_by_tag(owner, repo_name, tag)
  cap_rest_respond(data, err)
end)

b:rest("get_repo_release", function(owner, repo_name, release_id)
  local data, err = releases_cap.get(owner, repo_name, release_id)
  cap_rest_respond(data, err)
end)

b:rest("patch_repo_release", function(owner, repo_name, release_id)
  local data, err = releases_cap.update(owner, repo_name, release_id, GetBody())
  cap_rest_respond(data, err)
end)

b:rest("delete_repo_release", function(owner, repo_name, release_id)
  local ok, err = releases_cap.delete(owner, repo_name, release_id)
  cap_rest_204(ok, err)
end)

b:rest("get_repo_release_assets", function(owner, repo_name, release_id)
  local items, hdrs, err = releases_cap.list_assets(owner, repo_name, release_id)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

b:rest("post_repo_release_assets", function(owner, repo_name, release_id)
  local data, err = releases_cap.create_asset(owner, repo_name, release_id, GetBody())
  cap_rest_created(data, err)
end)

b:rest("get_repo_release_asset", function(owner, repo_name, asset_id)
  local data, err = releases_cap.get_asset(owner, repo_name, asset_id)
  cap_rest_respond(data, err)
end)

b:rest("patch_repo_release_asset", function(owner, repo_name, asset_id)
  local data, err = releases_cap.update_asset(owner, repo_name, asset_id, GetBody())
  cap_rest_respond(data, err)
end)

b:rest("delete_repo_release_asset", function(owner, repo_name, asset_id)
  local ok, err = releases_cap.delete_asset(owner, repo_name, asset_id)
  cap_rest_204(ok, err)
end)

-- Deploy keys ---------------------------------------------------------------

local deploy_keys_cap = {}

-- list: paginated list of deploy keys for a repository.
-- Returns (items, headers, nil) or (nil, nil, err).
deploy_keys_cap.list = function(owner, repo_name)
  local url = append_page_params(
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/deploy_keys",
    PAGES
  )
  return cap_fetch_paged(fetch_json, url)
end

-- create: create a deploy key.  body is raw GitHub-format JSON.
-- Returns (data, nil) or (nil, err).
deploy_keys_cap.create = function(owner, repo_name, body)
  local req = DecodeJson(body or "{}") or {}
  local gl_body = EncodeJson({
    title = req.title,
    key = req.key,
    can_push = req.read_only == false,
  })
  return cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/deploy_keys",
    "POST",
    gl_body
  )
end

-- get: get a single deploy key by key_id.
-- Returns (data, nil) or (nil, err).
deploy_keys_cap.get = function(owner, repo_name, key_id)
  return cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/deploy_keys/" .. key_id
  )
end

-- delete: delete a deploy key by key_id.
-- Returns (true, nil) or (nil, err).
deploy_keys_cap.delete = function(owner, repo_name, key_id)
  local ok, status = fetch_json(
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/deploy_keys/" .. key_id,
    "DELETE"
  )
  if not ok or (status ~= 200 and status ~= 204) then
    return nil, cap_err(status or 0, "delete deploy key failed")
  end
  return true, nil
end

b:rest("get_repo_keys", function(owner, repo_name)
  local items, hdrs, err = deploy_keys_cap.list(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

b:rest("post_repo_keys", function(owner, repo_name)
  local data, err = deploy_keys_cap.create(owner, repo_name, GetBody())
  cap_rest_created(data, err)
end)

b:rest("get_repo_key", function(owner, repo_name, key_id)
  local data, err = deploy_keys_cap.get(owner, repo_name, key_id)
  cap_rest_respond(data, err)
end)

b:rest("delete_repo_key", function(owner, repo_name, key_id)
  local ok, err = deploy_keys_cap.delete(owner, repo_name, key_id)
  cap_rest_204(ok, err)
end)

-- Webhooks ------------------------------------------------------------------

local webhooks_cap = {}

-- list: paginated list of webhooks for a repository.
-- Returns (items, headers, nil) or (nil, nil, err).
webhooks_cap.list = function(owner, repo_name)
  local url =
    append_page_params(base() .. "/projects/" .. project_id(owner, repo_name) .. "/hooks", PAGES)
  return cap_fetch_paged(fetch_json, url)
end

-- create: create a webhook.  body is raw JSON passthrough.
-- Returns (data, nil) or (nil, err).
webhooks_cap.create = function(owner, repo_name, body)
  return cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/hooks",
    "POST",
    body
  )
end

-- get: get a single webhook by hook_id.
-- Returns (data, nil) or (nil, err).
webhooks_cap.get = function(owner, repo_name, hook_id)
  return cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/hooks/" .. hook_id
  )
end

-- update: update a webhook by hook_id.  GitLab uses PUT for hook updates.
-- Returns (data, nil) or (nil, err).
webhooks_cap.update = function(owner, repo_name, hook_id, body)
  return cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/hooks/" .. hook_id,
    "PUT",
    body
  )
end

-- delete: delete a webhook by hook_id.
-- Returns (true, nil) or (nil, err).
webhooks_cap.delete = function(owner, repo_name, hook_id)
  local ok, status = fetch_json(
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/hooks/" .. hook_id,
    "DELETE"
  )
  if not ok or (status ~= 200 and status ~= 204) then
    return nil, cap_err(status or 0, "delete webhook failed")
  end
  return true, nil
end

-- get_config: get the config (url only) for a webhook.
-- Returns (data, nil) or (nil, err).
webhooks_cap.get_config = function(owner, repo_name, hook_id)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/hooks/" .. hook_id
  )
  if not raw then
    return nil, err
  end
  return { url = raw.url }, nil
end

-- update_config: merge new_cfg into existing hook config (url field only).
-- Returns (data, nil) or (nil, err).
webhooks_cap.update_config = function(owner, repo_name, hook_id, new_cfg)
  local url = base() .. "/projects/" .. project_id(owner, repo_name) .. "/hooks/" .. hook_id
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  local hook = raw
  if new_cfg.url then
    hook.url = new_cfg.url
  end
  local updated, uerr = cap_fetch(fetch_json, url, "PUT", EncodeJson(hook))
  if not updated then
    return nil, uerr
  end
  return { url = updated.url }, nil
end

b:rest("get_repo_hooks", function(owner, repo_name)
  local items, hdrs, err = webhooks_cap.list(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

b:rest("post_repo_hooks", function(owner, repo_name)
  local data, err = webhooks_cap.create(owner, repo_name, GetBody())
  cap_rest_created(data, err)
end)

b:rest("get_repo_hook", function(owner, repo_name, hook_id)
  local data, err = webhooks_cap.get(owner, repo_name, hook_id)
  cap_rest_respond(data, err)
end)

-- GitLab uses PUT for hook updates
b:rest("patch_repo_hook", function(owner, repo_name, hook_id)
  local data, err = webhooks_cap.update(owner, repo_name, hook_id, GetBody())
  cap_rest_respond(data, err)
end)

b:rest("delete_repo_hook", function(owner, repo_name, hook_id)
  local ok, err = webhooks_cap.delete(owner, repo_name, hook_id)
  cap_rest_204(ok, err)
end)

b:rest("get_repo_hook_config", function(owner, repo_name, hook_id)
  local data, err = webhooks_cap.get_config(owner, repo_name, hook_id)
  cap_rest_respond(data, err)
end)

b:rest("patch_repo_hook_config", function(owner, repo_name, hook_id)
  local new_cfg = DecodeJson(GetBody() or "{}")
  local data, err = webhooks_cap.update_config(owner, repo_name, hook_id, new_cfg)
  cap_rest_respond(data, err)
end)

-- GET /users/{username}/repos -----------------------------------------------
b:rest("get_users_repos", function(username)
  local items, hdrs, err = repos.list_by_user(username)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- GET /repositories (all public projects) -----------------------------------
b:rest("get_repositories", function()
  local items, hdrs, err = repos.list_all()
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- Commit comments -----------------------------------------------------------
-- GitLab uses notes on commits: /projects/{id}/repository/commits/{sha}/comments

b:rest("get_commit_comments", function(owner, repo_name, commit_sha)
  local items, hdrs, err = commit_comments_cap.list(owner, repo_name, commit_sha)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

b:rest("post_commit_comment", function(owner, repo_name, commit_sha)
  local data, err = commit_comments_cap.create(owner, repo_name, commit_sha, GetBody())
  cap_rest_created(data, err)
end)

-- Users ---------------------------------------------------------------------

-- GET /user
b:rest("get_user", function()
  local data, err = users.get_authenticated()
  cap_rest_respond(data, err)
end)

-- PATCH /user
b:rest("patch_user", function()
  local data, err = users.update_authenticated(GetBody())
  cap_rest_respond(data, err)
end)

-- GET /users/{username}
b:rest("get_users_username", function(username)
  local data, err = users.by_username(username)
  cap_rest_respond(data, err)
end)

-- GET /users
b:rest("get_users", function()
  local items, hdrs, err = users.list_all()
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- Emails --------------------------------------------------------------------

-- GET /user/emails
b:rest("get_user_emails", function()
  local data, err = users.list_emails()
  cap_rest_respond(data, err)
end)

-- POST /user/emails
b:rest("post_user_emails", function()
  local data, err = users.create_email(GetBody())
  cap_rest_created(data, err)
end)

-- SSH Keys ------------------------------------------------------------------

-- GET /user/keys
b:rest("get_user_keys", function()
  local items, hdrs, err = users.list_keys()
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- POST /user/keys
b:rest("post_user_keys", function()
  local data, err = users.create_key(GetBody())
  cap_rest_created(data, err)
end)

-- GET /user/keys/{key_id}
b:rest("get_user_key", function(key_id)
  local data, err = users.get_key(key_id)
  cap_rest_respond(data, err)
end)

-- DELETE /user/keys/{key_id}
b:rest("delete_user_key", function(key_id)
  local ok, err = users.delete_key(key_id)
  cap_rest_204(ok, err)
end)

-- GET /users/{username}/keys
b:rest("get_users_keys", function(username)
  local data, err = users.list_by_username_keys(username)
  cap_rest_respond(data, err)
end)

-- GPG Keys ------------------------------------------------------------------

-- GET /user/gpg_keys
b:rest("get_user_gpg_keys", function()
  local items, hdrs, err = users.list_gpg_keys()
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- POST /user/gpg_keys
b:rest("post_user_gpg_keys", function()
  local data, err = users.create_gpg_key(GetBody())
  cap_rest_created(data, err)
end)

-- GET /user/gpg_keys/{gpg_key_id}
b:rest("get_user_gpg_key", function(gpg_key_id)
  local data, err = users.get_gpg_key(gpg_key_id)
  cap_rest_respond(data, err)
end)

-- DELETE /user/gpg_keys/{gpg_key_id}
b:rest("delete_user_gpg_key", function(gpg_key_id)
  local ok, err = users.delete_gpg_key(gpg_key_id)
  cap_rest_204(ok, err)
end)

-- GET /users/{username}/gpg_keys
b:rest("get_users_gpg_keys", function(username)
  local data, err = users.list_by_username_gpg_keys(username)
  cap_rest_respond(data, err)
end)

-- ---------------------------------------------------------------------------
-- Teams capability module
-- ---------------------------------------------------------------------------
-- Teams in GitHub map to GitLab subgroups.
-- GitHub: /orgs/{org}/teams/{team_slug}  →  GitLab: /groups/{org}%2F{slug}
-- Legacy /teams/{team_id} API maps team_id to a GitLab group numeric ID.
-- GitLab group members have access levels; repos are the group's projects.

local teams_cap = {}

-- resolve_group_id: look up the numeric GitLab group ID for a slug path.
-- path is the URL-encoded group path (e.g. "org%2Fslug").
-- Returns (gid, nil) or (nil, err).
local function resolve_group_id(path)
  local ok, status, _, body = fetch_json(base() .. "/groups/" .. path)
  if not ok or status ~= 200 then
    return nil, cap_err(status or 0, "group lookup failed")
  end
  local g = DecodeJson(body) or {}
  if not g.id then
    return nil, cap_err(404, "group not found")
  end
  return g.id, nil
end

-- resolve_team_uid: look up a GitLab user ID by username for team operations.
-- Returns (uid, nil) or (nil, err).
local function resolve_team_uid(username)
  local uid = gl_user_id(username)
  if not uid then
    return nil, cap_err(404, "user not found")
  end
  return uid, nil
end

-- list_org_teams: paginated list of subgroups (teams) under an org.
-- Returns (items, headers, nil) or (nil, nil, err).
teams_cap.list_org_teams = function(org)
  local url = append_page_params(base() .. "/groups/" .. org .. "/subgroups", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_team, items), hdrs, nil
end

-- create_org_team: create a subgroup under org.  body is raw GitHub-format JSON.
-- Returns (data, nil) or (nil, err).
teams_cap.create_org_team = function(org, body)
  local req = DecodeJson(body or "{}") or {}
  local parent, perr = cap_fetch(fetch_json, base() .. "/groups/" .. org)
  if not parent then
    return nil, perr
  end
  local gl_body = EncodeJson({
    name = req.name,
    path = (req.name or ""):lower():gsub("[^%w%-]", "-"),
    parent_id = parent.id,
    description = req.description,
    visibility = req.privacy == "secret" and "private" or "internal",
  })
  local raw, err = cap_fetch(fetch_json, base() .. "/groups", "POST", gl_body)
  if not raw then
    return nil, err
  end
  return translate_gl_team(raw), nil
end

-- get_org_team: get a single team (subgroup) by org and slug.
-- Returns (data, nil) or (nil, err).
teams_cap.get_org_team = function(org, slug)
  local raw, err = cap_fetch(fetch_json, base() .. "/groups/" .. org .. "%2F" .. slug)
  if not raw then
    return nil, err
  end
  return translate_gl_team(raw), nil
end

-- update_org_team: update a team by org and slug.  body is raw GitHub-format JSON.
-- Returns (data, nil) or (nil, err).
teams_cap.update_org_team = function(org, slug, body)
  local gid, gerr = resolve_group_id(org .. "%2F" .. slug)
  if not gid then
    return nil, gerr
  end
  local req = DecodeJson(body or "{}") or {}
  local upd = { name = req.name, description = req.description }
  local raw, err = cap_fetch(fetch_json, base() .. "/groups/" .. gid, "PUT", EncodeJson(upd))
  if not raw then
    return nil, err
  end
  return translate_gl_team(raw), nil
end

-- delete_org_team: delete a team by org and slug.
-- Returns (true, nil) or (nil, err).
teams_cap.delete_org_team = function(org, slug)
  local gid, gerr = resolve_group_id(org .. "%2F" .. slug)
  if not gid then
    return nil, gerr
  end
  local ok, status = fetch_json(base() .. "/groups/" .. gid, "DELETE")
  if not ok or (status ~= 200 and status ~= 202 and status ~= 204) then
    return nil, cap_err(status or 0, "delete team failed")
  end
  return true, nil
end

-- list_org_team_members: paginated list of members for a team (by org/slug).
-- Returns (items, headers, nil) or (nil, nil, err).
teams_cap.list_org_team_members = function(org, slug)
  local gid, gerr = resolve_group_id(org .. "%2F" .. slug)
  if not gid then
    return nil, nil, gerr
  end
  local url = append_page_params(base() .. "/groups/" .. gid .. "/members", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_member, items), hdrs, nil
end

-- get_org_team_membership: get membership for a user in a team (by org/slug).
-- Returns (data, nil) or (nil, err).
-- data = { url, role, state }
teams_cap.get_org_team_membership = function(org, slug, username)
  local gid, gerr = resolve_group_id(org .. "%2F" .. slug)
  if not gid then
    return nil, gerr
  end
  local uid, uerr = resolve_team_uid(username)
  if not uid then
    return nil, uerr
  end
  local raw, err = cap_fetch(fetch_json, base() .. "/groups/" .. gid .. "/members/" .. uid)
  if not raw then
    return nil, err
  end
  local role = (raw.access_level or 0) >= 50 and "maintainer" or "member"
  return { url = "", role = role, state = "active" }, nil
end

-- put_org_team_membership: add or update membership for a user in a team (by org/slug).
-- Returns (data, nil) or (nil, err).
teams_cap.put_org_team_membership = function(org, slug, username, body)
  local gid, gerr = resolve_group_id(org .. "%2F" .. slug)
  if not gid then
    return nil, gerr
  end
  local uid, uerr = resolve_team_uid(username)
  if not uid then
    return nil, uerr
  end
  local req = DecodeJson(body or "{}") or {}
  local level = req.role == "maintainer" and 50 or 30
  local ok, status = fetch_json(
    base() .. "/groups/" .. gid .. "/members",
    "POST",
    EncodeJson({ user_id = uid, access_level = level })
  )
  if not ok then
    return nil, cap_err(0, "add member failed")
  end
  if status ~= 200 and status ~= 201 then
    return nil, cap_err(status, "add member failed")
  end
  return { url = "", role = req.role or "member", state = "active" }, nil
end

-- delete_org_team_membership: remove a user from a team (by org/slug).
-- Returns (true, nil) or (nil, err).
teams_cap.delete_org_team_membership = function(org, slug, username)
  local gid, gerr = resolve_group_id(org .. "%2F" .. slug)
  if not gid then
    return nil, gerr
  end
  local uid, uerr = resolve_team_uid(username)
  if not uid then
    return nil, uerr
  end
  local ok, status = fetch_json(base() .. "/groups/" .. gid .. "/members/" .. uid, "DELETE")
  if not ok or (status ~= 200 and status ~= 204) then
    return nil, cap_err(status or 0, "remove member failed")
  end
  return true, nil
end

-- list_org_team_repos: paginated list of projects for a team (by org/slug).
-- Returns (items, headers, nil) or (nil, nil, err).
teams_cap.list_org_team_repos = function(org, slug)
  local gid, gerr = resolve_group_id(org .. "%2F" .. slug)
  if not gid then
    return nil, nil, gerr
  end
  local url = append_page_params(base() .. "/groups/" .. gid .. "/projects", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_repo, items), hdrs, nil
end

-- get_org_team_repo: check if a repo belongs to a team (by org/slug) and return it.
-- Returns (data, nil) or (nil, err).
teams_cap.get_org_team_repo = function(org, slug, owner, repo_name)
  local gid, gerr = resolve_group_id(org .. "%2F" .. slug)
  if not gid then
    return nil, gerr
  end
  local pid = project_id(owner, repo_name)
  local raw, ferr = cap_fetch(fetch_json, base() .. "/projects/" .. pid)
  if not raw then
    return nil, ferr
  end
  local ns = raw.namespace or {}
  if tostring(ns.id) ~= tostring(gid) then
    return nil, cap_err(404, "Not Found")
  end
  return translate_gl_repo(raw), nil
end

-- put_org_team_repo: share a repo with a team (by org/slug).
-- Returns (true, nil) or (nil, err).
teams_cap.put_org_team_repo = function(org, slug, owner, repo_name, body)
  local gid, gerr = resolve_group_id(org .. "%2F" .. slug)
  if not gid then
    return nil, gerr
  end
  local pid = project_id(owner, repo_name)
  local req = DecodeJson(body or "{}") or {}
  local access = req.permission == "admin" and 50 or (req.permission == "push" and 30 or 20)
  local ok, status = fetch_json(
    base() .. "/projects/" .. pid .. "/share",
    "POST",
    EncodeJson({ group_id = gid, group_access = access })
  )
  if not ok or (status ~= 200 and status ~= 201 and status ~= 204) then
    return nil, cap_err(status or 0, "share project failed")
  end
  return true, nil
end

-- delete_org_team_repo: unshare a repo from a team (by org/slug).
-- Returns (true, nil) or (nil, err).
teams_cap.delete_org_team_repo = function(org, slug, owner, repo_name)
  local gid, gerr = resolve_group_id(org .. "%2F" .. slug)
  if not gid then
    return nil, gerr
  end
  local pid = project_id(owner, repo_name)
  local ok, status = fetch_json(base() .. "/projects/" .. pid .. "/share/" .. gid, "DELETE")
  if not ok or (status ~= 200 and status ~= 204) then
    return nil, cap_err(status or 0, "unshare project failed")
  end
  return true, nil
end

-- list_org_team_children: paginated list of sub-subgroups for a team (by org/slug).
-- Returns (items, headers, nil) or (nil, nil, err).
teams_cap.list_org_team_children = function(org, slug)
  local gid, gerr = resolve_group_id(org .. "%2F" .. slug)
  if not gid then
    return nil, nil, gerr
  end
  local url = append_page_params(base() .. "/groups/" .. gid .. "/subgroups", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  -- Translate in-place to preserve JSON array encoding metadata from DecodeJson.
  for i, g in ipairs(items) do
    items[i] = translate_gl_team(g)
  end
  return items, hdrs, nil
end

-- list_user_teams: all groups the authenticated user belongs to.
-- Returns (items, headers, nil) or (nil, nil, err).
teams_cap.list_user_teams = function()
  local url = append_page_params(base() .. "/groups?min_access_level=10", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_team, items), hdrs, nil
end

-- get_team: get a team by numeric ID.
-- Returns (data, nil) or (nil, err).
teams_cap.get_team = function(team_id)
  local raw, err = cap_fetch(fetch_json, base() .. "/groups/" .. team_id)
  if not raw then
    return nil, err
  end
  return translate_gl_team(raw), nil
end

-- update_team: update a team by numeric ID.  body is raw GitHub-format JSON.
-- Returns (data, nil) or (nil, err).
teams_cap.update_team = function(team_id, body)
  local req = DecodeJson(body or "{}") or {}
  local upd = { name = req.name, description = req.description }
  local raw, err = cap_fetch(fetch_json, base() .. "/groups/" .. team_id, "PUT", EncodeJson(upd))
  if not raw then
    return nil, err
  end
  return translate_gl_team(raw), nil
end

-- delete_team: delete a team by numeric ID.
-- Returns (true, nil) or (nil, err).
teams_cap.delete_team = function(team_id)
  local ok, status = fetch_json(base() .. "/groups/" .. team_id, "DELETE")
  if not ok or (status ~= 200 and status ~= 202 and status ~= 204) then
    return nil, cap_err(status or 0, "delete team failed")
  end
  return true, nil
end

-- list_team_members: paginated list of members for a team by numeric ID.
-- Returns (items, headers, nil) or (nil, nil, err).
teams_cap.list_team_members = function(team_id)
  local url = append_page_params(base() .. "/groups/" .. team_id .. "/members", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_member, items), hdrs, nil
end

-- get_team_member: deprecated legacy — returns (true, nil) if member, (nil, err) if not.
-- On success callers emit 204 No Content.
teams_cap.get_team_member = function(team_id, username)
  local uid, uerr = resolve_team_uid(username)
  if not uid then
    return nil, uerr
  end
  local ok, status = pcall(Fetch, base() .. "/groups/" .. team_id .. "/members/" .. uid, auth())
  if ok and status == 200 then
    return true, nil
  end
  return nil, cap_err(ok and status or 0, "Not a member")
end

-- put_team_member: deprecated legacy — add a member.
-- Returns (true, nil) or (nil, err).
teams_cap.put_team_member = function(team_id, username)
  local uid, uerr = resolve_team_uid(username)
  if not uid then
    return nil, uerr
  end
  local ok, status = fetch_json(
    base() .. "/groups/" .. team_id .. "/members",
    "POST",
    EncodeJson({ user_id = uid, access_level = 30 })
  )
  if not ok or (status ~= 200 and status ~= 201) then
    return nil, cap_err(status or 0, "add member failed")
  end
  return true, nil
end

-- delete_team_member: deprecated legacy — remove a member.
-- Returns (true, nil) or (nil, err).
teams_cap.delete_team_member = function(team_id, username)
  local uid, uerr = resolve_team_uid(username)
  if not uid then
    return nil, uerr
  end
  local ok, status = fetch_json(base() .. "/groups/" .. team_id .. "/members/" .. uid, "DELETE")
  if not ok or (status ~= 200 and status ~= 204) then
    return nil, cap_err(status or 0, "remove member failed")
  end
  return true, nil
end

-- get_team_membership: get membership for a user in a team by numeric ID.
-- Returns (data, nil) or (nil, err).
teams_cap.get_team_membership = function(team_id, username)
  local uid, uerr = resolve_team_uid(username)
  if not uid then
    return nil, uerr
  end
  local raw, err = cap_fetch(fetch_json, base() .. "/groups/" .. team_id .. "/members/" .. uid)
  if not raw then
    return nil, err
  end
  local role = (raw.access_level or 0) >= 50 and "maintainer" or "member"
  return { url = "", role = role, state = "active" }, nil
end

-- put_team_membership: add or update membership for a user in a team by numeric ID.
-- Returns (data, nil) or (nil, err).
teams_cap.put_team_membership = function(team_id, username, body)
  local uid, uerr = resolve_team_uid(username)
  if not uid then
    return nil, uerr
  end
  local req = DecodeJson(body or "{}") or {}
  local level = req.role == "maintainer" and 50 or 30
  local ok, status = fetch_json(
    base() .. "/groups/" .. team_id .. "/members",
    "POST",
    EncodeJson({ user_id = uid, access_level = level })
  )
  if not ok then
    return nil, cap_err(0, "add member failed")
  end
  if status ~= 200 and status ~= 201 then
    return nil, cap_err(status, "add member failed")
  end
  return { url = "", role = req.role or "member", state = "active" }, nil
end

-- delete_team_membership: remove a user from a team by numeric ID.
-- Returns (true, nil) or (nil, err).
teams_cap.delete_team_membership = function(team_id, username)
  local uid, uerr = resolve_team_uid(username)
  if not uid then
    return nil, uerr
  end
  local ok, status = fetch_json(base() .. "/groups/" .. team_id .. "/members/" .. uid, "DELETE")
  if not ok or (status ~= 200 and status ~= 204) then
    return nil, cap_err(status or 0, "remove member failed")
  end
  return true, nil
end

-- list_team_repos: paginated list of projects for a team by numeric ID.
-- Returns (items, headers, nil) or (nil, nil, err).
teams_cap.list_team_repos = function(team_id)
  local url = append_page_params(base() .. "/groups/" .. team_id .. "/projects", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_repo, items), hdrs, nil
end

-- get_team_repo: check if a repo belongs to a team by numeric ID and return it.
-- Returns (data, nil) or (nil, err).
teams_cap.get_team_repo = function(team_id, owner, repo_name)
  local pid = project_id(owner, repo_name)
  local raw, ferr = cap_fetch(fetch_json, base() .. "/projects/" .. pid)
  if not raw then
    return nil, ferr
  end
  local ns = raw.namespace or {}
  if tostring(ns.id) ~= tostring(team_id) then
    return nil, cap_err(404, "Not Found")
  end
  return translate_gl_repo(raw), nil
end

-- put_team_repo: share a repo with a team by numeric ID.
-- Returns (true, nil) or (nil, err).
teams_cap.put_team_repo = function(team_id, owner, repo_name, body)
  local pid = project_id(owner, repo_name)
  local req = DecodeJson(body or "{}") or {}
  local access = req.permission == "admin" and 50 or (req.permission == "push" and 30 or 20)
  local ok, status = fetch_json(
    base() .. "/projects/" .. pid .. "/share",
    "POST",
    EncodeJson({ group_id = team_id, group_access = access })
  )
  if not ok or (status ~= 200 and status ~= 201 and status ~= 204) then
    return nil, cap_err(status or 0, "share project failed")
  end
  return true, nil
end

-- delete_team_repo: unshare a repo from a team by numeric ID.
-- Returns (true, nil) or (nil, err).
teams_cap.delete_team_repo = function(team_id, owner, repo_name)
  local pid = project_id(owner, repo_name)
  local ok, status = fetch_json(base() .. "/projects/" .. pid .. "/share/" .. team_id, "DELETE")
  if not ok or (status ~= 200 and status ~= 204) then
    return nil, cap_err(status or 0, "unshare project failed")
  end
  return true, nil
end

-- list_team_children: paginated list of sub-subgroups for a team by numeric ID.
-- Returns (items, headers, nil) or (nil, nil, err).
teams_cap.list_team_children = function(team_id)
  local url = append_page_params(base() .. "/groups/" .. team_id .. "/subgroups", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  -- Translate in-place to preserve JSON array encoding metadata from DecodeJson.
  for i, g in ipairs(items) do
    items[i] = translate_gl_team(g)
  end
  return items, hdrs, nil
end

-- GET /orgs/{org}/teams
b:rest("get_org_teams", function(org)
  local items, hdrs, err = teams_cap.list_org_teams(org)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- POST /orgs/{org}/teams
b:rest("post_org_teams", function(org)
  local data, err = teams_cap.create_org_team(org, GetBody())
  cap_rest_created(data, err)
end)

-- GET /orgs/{org}/teams/{team_slug}
b:rest("get_org_team", function(org, slug)
  local data, err = teams_cap.get_org_team(org, slug)
  cap_rest_respond(data, err)
end)

-- PATCH /orgs/{org}/teams/{team_slug}
b:rest("patch_org_team", function(org, slug)
  local data, err = teams_cap.update_org_team(org, slug, GetBody())
  cap_rest_respond(data, err)
end)

-- DELETE /orgs/{org}/teams/{team_slug}
b:rest("delete_org_team", function(org, slug)
  local ok, err = teams_cap.delete_org_team(org, slug)
  cap_rest_204(ok, err)
end)

-- GET /orgs/{org}/teams/{team_slug}/members
b:rest("get_org_team_members", function(org, slug)
  local items, hdrs, err = teams_cap.list_org_team_members(org, slug)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- GET /orgs/{org}/teams/{team_slug}/memberships/{username}
b:rest("get_org_team_membership", function(org, slug, username)
  local data, err = teams_cap.get_org_team_membership(org, slug, username)
  cap_rest_respond(data, err)
end)

-- PUT /orgs/{org}/teams/{team_slug}/memberships/{username}
b:rest("put_org_team_membership", function(org, slug, username)
  local data, err = teams_cap.put_org_team_membership(org, slug, username, GetBody())
  cap_rest_respond(data, err)
end)

-- DELETE /orgs/{org}/teams/{team_slug}/memberships/{username}
b:rest("delete_org_team_membership", function(org, slug, username)
  local ok, err = teams_cap.delete_org_team_membership(org, slug, username)
  cap_rest_204(ok, err)
end)

-- GET /orgs/{org}/teams/{team_slug}/repos
b:rest("get_org_team_repos", function(org, slug)
  local items, hdrs, err = teams_cap.list_org_team_repos(org, slug)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- GET /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}
b:rest("get_org_team_repo", function(org, slug, owner, repo_name)
  local data, err = teams_cap.get_org_team_repo(org, slug, owner, repo_name)
  cap_rest_respond(data, err)
end)

-- PUT /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}
b:rest("put_org_team_repo", function(org, slug, owner, repo_name)
  local ok, err = teams_cap.put_org_team_repo(org, slug, owner, repo_name, GetBody())
  cap_rest_204(ok, err)
end)

-- DELETE /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}
b:rest("delete_org_team_repo", function(org, slug, owner, repo_name)
  local ok, err = teams_cap.delete_org_team_repo(org, slug, owner, repo_name)
  cap_rest_204(ok, err)
end)

-- GET /orgs/{org}/teams/{team_slug}/teams — list sub-subgroups
b:rest("get_org_team_children", function(org, slug)
  local items, hdrs, err = teams_cap.list_org_team_children(org, slug)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- Legacy team-by-id API (/teams/{team_id}) ------------------------------------
-- team_id maps to GitLab group numeric ID.

-- GET /user/teams — all groups the authenticated user belongs to
b:rest("get_user_teams", function()
  local items, hdrs, err = teams_cap.list_user_teams()
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- GET /teams/{team_id}
b:rest("get_team", function(team_id)
  local data, err = teams_cap.get_team(team_id)
  cap_rest_respond(data, err)
end)

-- PATCH /teams/{team_id}
b:rest("patch_team", function(team_id)
  local data, err = teams_cap.update_team(team_id, GetBody())
  cap_rest_respond(data, err)
end)

-- DELETE /teams/{team_id}
b:rest("delete_team", function(team_id)
  local ok, err = teams_cap.delete_team(team_id)
  cap_rest_204(ok, err)
end)

-- GET /teams/{team_id}/members
b:rest("get_team_members", function(team_id)
  local items, hdrs, err = teams_cap.list_team_members(team_id)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- GET /teams/{team_id}/members/{username} — deprecated legacy, 204 if member
b:rest("get_team_member", function(team_id, username)
  local ok, err = teams_cap.get_team_member(team_id, username)
  if ok then
    SetStatus(204, "No Content")
  else
    cap_rest_204(nil, err)
  end
end)

-- PUT /teams/{team_id}/members/{username} — deprecated legacy
b:rest("put_team_member", function(team_id, username)
  local ok, err = teams_cap.put_team_member(team_id, username)
  cap_rest_204(ok, err)
end)

-- DELETE /teams/{team_id}/members/{username} — deprecated legacy
b:rest("delete_team_member", function(team_id, username)
  local ok, err = teams_cap.delete_team_member(team_id, username)
  cap_rest_204(ok, err)
end)

-- GET /teams/{team_id}/memberships/{username}
b:rest("get_team_membership", function(team_id, username)
  local data, err = teams_cap.get_team_membership(team_id, username)
  cap_rest_respond(data, err)
end)

-- PUT /teams/{team_id}/memberships/{username}
b:rest("put_team_membership", function(team_id, username)
  local data, err = teams_cap.put_team_membership(team_id, username, GetBody())
  cap_rest_respond(data, err)
end)

-- DELETE /teams/{team_id}/memberships/{username}
b:rest("delete_team_membership", function(team_id, username)
  local ok, err = teams_cap.delete_team_membership(team_id, username)
  cap_rest_204(ok, err)
end)

-- GET /teams/{team_id}/repos
b:rest("get_team_repos", function(team_id)
  local items, hdrs, err = teams_cap.list_team_repos(team_id)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- GET /teams/{team_id}/repos/{owner}/{repo}
b:rest("get_team_repo", function(team_id, owner, repo_name)
  local data, err = teams_cap.get_team_repo(team_id, owner, repo_name)
  cap_rest_respond(data, err)
end)

-- PUT /teams/{team_id}/repos/{owner}/{repo}
b:rest("put_team_repo", function(team_id, owner, repo_name)
  local ok, err = teams_cap.put_team_repo(team_id, owner, repo_name, GetBody())
  cap_rest_204(ok, err)
end)

-- DELETE /teams/{team_id}/repos/{owner}/{repo}
b:rest("delete_team_repo", function(team_id, owner, repo_name)
  local ok, err = teams_cap.delete_team_repo(team_id, owner, repo_name)
  cap_rest_204(ok, err)
end)

-- GET /teams/{team_id}/teams — sub-subgroups
b:rest("get_team_children", function(team_id)
  local items, hdrs, err = teams_cap.list_team_children(team_id)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- Issues -------------------------------------------------------------------

-- GET /repos/{owner}/{repo}/issues
b:rest("get_repo_issues", function(owner, repo_name)
  local items, hdrs, err = issues_cap.list(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- POST /repos/{owner}/{repo}/issues
b:rest("post_repo_issues", function(owner, repo_name)
  local data, err = issues_cap.create(owner, repo_name, GetBody())
  cap_rest_created(data, err)
end)

-- GET /repos/{owner}/{repo}/issues/{issue_number}
b:rest("get_repo_issue", function(owner, repo_name, issue_number)
  local data, err = issues_cap.get(owner, repo_name, issue_number)
  cap_rest_respond(data, err)
end)

-- PATCH /repos/{owner}/{repo}/issues/{issue_number}
b:rest("patch_repo_issue", function(owner, repo_name, issue_number)
  local data, err = issues_cap.update(owner, repo_name, issue_number, GetBody())
  cap_rest_respond(data, err)
end)

-- GET /repos/{owner}/{repo}/issues/{issue_number}/comments
b:rest("get_issue_comments", function(owner, repo_name, issue_number)
  local items, hdrs, err = issues_cap.list_comments(owner, repo_name, issue_number)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- POST /repos/{owner}/{repo}/issues/{issue_number}/comments
b:rest("post_issue_comment", function(owner, repo_name, issue_number)
  local data, err = issues_cap.create_comment(owner, repo_name, issue_number, GetBody())
  cap_rest_created(data, err)
end)

-- GET /repos/{owner}/{repo}/issues/{issue_number}/labels
b:rest("get_issue_labels", function(owner, repo_name, issue_number)
  local data, err = labels_cap.list_issue(owner, repo_name, issue_number)
  cap_rest_respond(data, err)
end)

-- POST /repos/{owner}/{repo}/issues/{issue_number}/labels
b:rest("post_issue_labels", function(owner, repo_name, issue_number)
  local req = DecodeJson(GetBody() or "{}")
  local data, err = labels_cap.set_issue(owner, repo_name, issue_number, req.labels or {})
  cap_rest_respond(data, err)
end)

-- PUT /repos/{owner}/{repo}/issues/{issue_number}/labels  (replace all)
b:rest("put_issue_labels", function(owner, repo_name, issue_number)
  local req = DecodeJson(GetBody() or "{}")
  local data, err = labels_cap.replace_issue(owner, repo_name, issue_number, req.labels or {})
  cap_rest_respond(data, err)
end)

-- DELETE /repos/{owner}/{repo}/issues/{issue_number}/labels  (remove all)
b:rest("delete_issue_labels", function(owner, repo_name, issue_number)
  local ok, err = labels_cap.delete_issue_all(owner, repo_name, issue_number)
  cap_rest_204(ok, err)
end)

-- DELETE /repos/{owner}/{repo}/issues/{issue_number}/labels/{name}
b:rest("delete_issue_label", function(owner, repo_name, issue_number, label_name)
  local ok, err = labels_cap.delete_issue_one(owner, repo_name, issue_number, label_name)
  cap_rest_204(ok, err)
end)

-- GET /repos/{owner}/{repo}/labels
b:rest("get_repo_labels", function(owner, repo_name)
  local items, hdrs, err = labels_cap.list_repo(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- POST /repos/{owner}/{repo}/labels
b:rest("post_repo_labels", function(owner, repo_name)
  local data, err = labels_cap.create_repo(owner, repo_name, GetBody())
  cap_rest_created(data, err)
end)

-- GET /repos/{owner}/{repo}/labels/{name}
b:rest("get_repo_label", function(owner, repo_name, label_name)
  local data, err = labels_cap.get_repo(owner, repo_name, label_name)
  cap_rest_respond(data, err)
end)

-- PATCH /repos/{owner}/{repo}/labels/{name}
b:rest("patch_repo_label", function(owner, repo_name, label_name)
  local data, err = labels_cap.update_repo(owner, repo_name, label_name, GetBody())
  cap_rest_respond(data, err)
end)

-- DELETE /repos/{owner}/{repo}/labels/{name}
b:rest("delete_repo_label", function(owner, repo_name, label_name)
  local ok, err = labels_cap.delete_repo(owner, repo_name, label_name)
  cap_rest_204(ok, err)
end)

-- Milestones ----------------------------------------------------------------

-- GET /repos/{owner}/{repo}/milestones
b:rest("get_repo_milestones", function(owner, repo_name)
  local items, hdrs, err = milestones_cap.list(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- POST /repos/{owner}/{repo}/milestones
b:rest("post_repo_milestones", function(owner, repo_name)
  local data, err = milestones_cap.create(owner, repo_name, GetBody())
  cap_rest_created(data, err)
end)

-- GET /repos/{owner}/{repo}/milestones/{milestone_number}
b:rest("get_repo_milestone", function(owner, repo_name, milestone_number)
  local data, err = milestones_cap.get(owner, repo_name, milestone_number)
  cap_rest_respond(data, err)
end)

-- PATCH /repos/{owner}/{repo}/milestones/{milestone_number}
b:rest("patch_repo_milestone", function(owner, repo_name, milestone_number)
  local data, err = milestones_cap.update(owner, repo_name, milestone_number, GetBody())
  cap_rest_respond(data, err)
end)

-- DELETE /repos/{owner}/{repo}/milestones/{milestone_number}
b:rest("delete_repo_milestone", function(owner, repo_name, milestone_number)
  local ok, err = milestones_cap.delete(owner, repo_name, milestone_number)
  cap_rest_204(ok, err)
end)

-- Assignees -----------------------------------------------------------------

-- GET /repos/{owner}/{repo}/assignees  (users eligible for assignment)
b:rest(
  "get_repo_assignees",
  proxy_handler_paged(translate_gl_members, function(o, r)
    return append_page_params(base() .. "/projects/" .. project_id(o, r) .. "/members/all", PAGES)
  end)
)

-- Pull Requests (mapped to GitLab Merge Requests) --------------------------

-- GET /repos/{owner}/{repo}/pulls
b:rest("get_repo_pulls", function(owner, repo_name)
  local items, hdrs, err = pulls_cap.list(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- POST /repos/{owner}/{repo}/pulls
b:rest("post_repo_pulls", function(owner, repo_name)
  local data, err = pulls_cap.create(owner, repo_name, GetBody())
  cap_rest_created(data, err)
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}
b:rest("get_repo_pull", function(owner, repo_name, pull_number)
  local data, err = pulls_cap.get(owner, repo_name, pull_number)
  cap_rest_respond(data, err)
end)

-- PATCH /repos/{owner}/{repo}/pulls/{pull_number}
b:rest("patch_repo_pull", function(owner, repo_name, pull_number)
  local data, err = pulls_cap.update(owner, repo_name, pull_number, GetBody())
  cap_rest_respond(data, err)
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/commits
b:rest("get_pull_commits", function(owner, repo_name, pull_number)
  local items, hdrs, err = pulls_cap.list_commits(owner, repo_name, pull_number)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/files
-- GitLab uses /changes which wraps the diff list in a parent object.
b:rest("get_pull_files", function(owner, repo_name, pull_number)
  local data, err = pulls_cap.list_files(owner, repo_name, pull_number)
  cap_rest_respond(data, err)
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/merge
-- Returns 204 if the MR is merged, 404 if not.
b:rest("get_pull_merge", function(owner, repo_name, pull_number)
  local ok, err = pulls_cap.check_merged(owner, repo_name, pull_number)
  if ok then
    SetStatus(204, "No Content")
  elseif err and err.status == 404 then
    respond_json(404, { message = err.message })
  else
    cap_rest_204(nil, err)
  end
end)

-- PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge
b:rest("put_pull_merge", function(owner, repo_name, pull_number)
  local ok, err = pulls_cap.merge(owner, repo_name, pull_number, GetBody())
  cap_rest_204(ok, err)
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/requested_reviewers
-- GitLab: reviewers assigned to the MR.
b:rest("get_pull_requested_reviewers", function(owner, repo_name, pull_number)
  local data, err = pulls_cap.list_requested_reviewers(owner, repo_name, pull_number)
  cap_rest_respond(data, err)
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews
-- GitLab: MR approvals mapped to GitHub reviews.
b:rest("get_pull_reviews", function(owner, repo_name, pull_number)
  local data, err = pulls_cap.list_reviews(owner, repo_name, pull_number)
  cap_rest_respond(data, err)
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}
b:rest("get_pull_review", function(owner, repo_name, pull_number, review_id)
  local data, err = pulls_cap.get_review(owner, repo_name, pull_number, review_id)
  cap_rest_respond(data, err)
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}/comments
-- GitLab has no per-review inline comments; return all inline MR notes.
b:rest("get_pull_review_comments", function(owner, repo_name, pull_number)
  local data, err = pulls_cap.list_review_comments(owner, repo_name, pull_number)
  cap_rest_respond(data, err)
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/comments
-- GitLab: inline (position-based) MR notes.
b:rest("get_pull_comments", function(owner, repo_name, pull_number)
  local data, err = pulls_cap.list_review_comments(owner, repo_name, pull_number)
  cap_rest_respond(data, err)
end)

-- ---------------------------------------------------------------------------
-- Search capability module
-- ---------------------------------------------------------------------------
-- Owns fetch + translate for search operations.
-- Paged list operations return (items, headers, nil) or (nil, nil, err).

local search_cap = {}

-- repos: paginated search of projects by query string.
-- Returns (items, headers, nil) or (nil, nil, err).
search_cap.repos = function(q)
  local url = append_page_params(base() .. "/projects?search=" .. q, PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_repo, items), hdrs, nil
end

-- users: paginated search of users by query string.
-- Returns (items, headers, nil) or (nil, nil, err).
search_cap.users = function(q)
  local url = append_page_params(base() .. "/users?search=" .. q, PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_user, items), hdrs, nil
end

-- Helper: write a GitHub search envelope from a paged cap result.
-- items: translated array; hdrs: raw response headers (for Link forwarding).
local function write_search_envelope(items, hdrs)
  local link = hdrs and (hdrs["Link"] or hdrs["link"])
  local rewritten = rewrite_link_header(link, PAGES)
  set_preamble()
  if rewritten then
    SetHeader("Link", rewritten)
  end
  Write(
    '{"total_count":'
      .. #items
      .. ',"incomplete_results":false,"items":'
      .. (#items > 0 and EncodeJson(items) or "[]")
      .. "}"
  )
end

-- Search -----------------------------------------------------------------------

-- GET /search/repositories — maps to GitLab GET /projects?search=<q>
b:rest("search_repositories", function()
  local q = GetParam("q") or ""
  local items, hdrs, err = search_cap.repos(q)
  if not items then
    respond_json(err and err.status ~= 0 and err.status or 503, {})
    return
  end
  write_search_envelope(items, hdrs)
end)

-- GET /search/users — maps to GitLab GET /users?search=<q>
b:rest("search_users", function()
  local q = GetParam("q") or ""
  local items, hdrs, err = search_cap.users(q)
  if not items then
    respond_json(err and err.status ~= 0 and err.status or 503, {})
    return
  end
  write_search_envelope(items, hdrs)
end)

-- ---------------------------------------------------------------------------
-- Gitignore capability module
-- ---------------------------------------------------------------------------
-- Owns fetch + translate for gitignore template operations.
-- list returns (names_array, nil) or (nil, err).
-- get returns ({name, source}, nil) or (nil, err).

local gitignore_cap = {}

-- list: fetch all gitignore template names.
-- GitLab returns [{key,name},...]; GitHub returns ["Name",...].
-- Returns (names_array, nil) or (nil, err).
gitignore_cap.list = function()
  local raw, err = cap_fetch(fetch_json, base() .. "/templates/gitignores")
  if not raw then
    return nil, err
  end
  local names = {}
  for i, t in ipairs(raw) do
    names[i] = t.name
  end
  return names, nil
end

-- get: fetch a single gitignore template by name.
-- GitLab returns {name, content}; GitHub returns {name, source}.
-- Returns ({name, source}, nil) or (nil, err).
gitignore_cap.get = function(name)
  local raw, err = cap_fetch(fetch_json, base() .. "/templates/gitignores/" .. name)
  if not raw then
    return nil, err
  end
  return { name = raw.name, source = raw.content }, nil
end

-- Gitignore -----------------------------------------------------------------

-- GET /gitignore/templates → GitLab GET /api/v4/templates/gitignores
-- GitLab returns [{key,name}, ...]; GitHub returns ["Name", ...]
b:rest("get_gitignore_templates", function()
  local data, err = gitignore_cap.list()
  cap_rest_respond(data, err)
end)

-- GET /gitignore/templates/{name} → GitLab GET /api/v4/templates/gitignores/{name}
-- GitLab returns {name, content}; GitHub returns {name, source}
b:rest("get_gitignore_template", function(name)
  local data, err = gitignore_cap.get(name)
  cap_rest_respond(data, err)
end)

-- ---------------------------------------------------------------------------
-- Licenses capability module
-- ---------------------------------------------------------------------------
-- Owns fetch + translate for license template and repo license operations.
-- list returns (array, nil) or (nil, err).
-- get returns (object, nil) or (nil, err).

local licenses_cap = {}

-- list: fetch all license template summaries.
-- GitLab returns [{key,name,...}]; GitHub returns [{key,name}] (license-simple).
-- Returns (array, nil) or (nil, err).
licenses_cap.list = function()
  local raw, err = cap_fetch(fetch_json, base() .. "/templates/licenses")
  if not raw then
    return nil, err
  end
  local result = {}
  for i, t in ipairs(raw) do
    result[i] = { key = t.key, name = t.name }
  end
  return result, nil
end

-- get: fetch a single license template by key.
-- GitLab returns {key,name,content,...}; maps content → body for GitHub shape.
-- Returns (object, nil) or (nil, err).
licenses_cap.get = function(license_name)
  local raw, err = cap_fetch(fetch_json, base() .. "/templates/licenses/" .. license_name)
  if not raw then
    return nil, err
  end
  return {
    key = raw.key,
    name = raw.name,
    html_url = raw.html_url,
    description = raw.description,
    body = raw.content,
    permissions = raw.permissions or {},
    conditions = raw.conditions or {},
    limitations = raw.limitations or {},
  },
    nil
end

-- get_repo_license: fetch the LICENSE file and project license metadata.
-- Combines /repository/files/LICENSE with project.license field.
-- Returns (object, nil) or (nil, err).
licenses_cap.get_repo_license = function(owner, repo_name)
  local pid = project_id(owner, repo_name)
  local f, ferr =
    cap_fetch(fetch_json, base() .. "/projects/" .. pid .. "/repository/files/LICENSE?ref=HEAD")
  if not f then
    return nil, ferr
  end
  local proj, _ = cap_fetch(fetch_json, base() .. "/projects/" .. pid)
  local license_meta = nil
  if proj and proj.license then
    license_meta = { key = proj.license.key, name = proj.license.name }
  end
  return {
    name = f.file_name,
    path = f.file_path,
    sha = f.blob_id,
    size = f.size,
    type = "file",
    content = f.content,
    encoding = f.encoding,
    license = license_meta,
  },
    nil
end

-- Licenses -----------------------------------------------------------------

-- GET /licenses → GitLab GET /api/v4/templates/licenses
-- GitLab returns [{key,name,...}]; GitHub returns [{key,name,...}] (license-simple)
b:rest("get_licenses", function()
  local data, err = licenses_cap.list()
  cap_rest_respond(data, err)
end)

-- GET /licenses/{license} → GitLab GET /api/v4/templates/licenses/{key}
-- GitLab returns {key,name,content,description,conditions,permissions,limitations,html_url}
-- GitHub returns {key,name,body,description,conditions,permissions,limitations,html_url,...}
b:rest("get_license", function(license_name)
  local data, err = licenses_cap.get(license_name)
  cap_rest_respond(data, err)
end)

-- GET /repos/{owner}/{repo}/license
-- Combines /repository/files/LICENSE content with project license metadata.
b:rest("get_repo_license", function(owner, repo_name)
  local data, err = licenses_cap.get_repo_license(owner, repo_name)
  cap_rest_respond(data, err)
end)

-- Checks (via GitLab commit statuses and pipelines) -------------------------
--
-- GitHub Check Runs map onto GitLab commit statuses.  GitLab has no concept
-- of a check run independent of a commit SHA, so:
--   • POST check-runs → POST /projects/{id}/statuses/{sha}
--   • GET check-runs/{id} → minimal stub (no reverse lookup by ID)
--   • PATCH check-runs/{id} → minimal stub
--   • GET commits/{ref}/check-runs → commit statuses list
--   • Check Suites have no GitLab equivalent; all suite endpoints are stubs.
--   • Annotations are always empty.
--
-- Status mapping (GitHub → GitLab):
--   queued/in_progress     → running
--   completed/success      → success
--   completed/failure      → failed
--   completed/neutral      → success
--   completed/skipped      → success
--   completed/(other)      → failed
--
-- Status mapping (GitLab → GitHub):
--   pending → status=queued,      conclusion=null
--   running → status=in_progress, conclusion=null
--   success → status=completed,   conclusion=success
--   failed  → status=completed,   conclusion=failure
--   canceled→ status=completed,   conclusion=cancelled
--   other   → status=completed,   conclusion=failure

-- POST /repos/{owner}/{repo}/check-runs
b:rest("post_check_runs", function(owner, repo_name)
  local data, err = statuses_cap.create_check_run(owner, repo_name, GetBody())
  cap_rest_created(data, err)
end)

-- GET /repos/{owner}/{repo}/commits/{ref}/check-runs
b:rest("get_commit_check_runs", function(owner, repo_name, ref)
  local data, err = statuses_cap.list_check_runs(owner, repo_name, ref)
  cap_rest_respond(data, err)
end)

-- Check suites have no GitLab equivalent; all suite endpoints fall back to
-- the route_defaults stubs defined in .init.lua.

-- ---------------------------------------------------------------------------
-- Packages capability module
-- ---------------------------------------------------------------------------
-- Owns fetch + translation for GitLab group package registry operations.
-- Maps GitLab package objects to the GitHub Packages REST shape.
-- Paged list operations: (items, headers, nil) or (nil, nil, err).
-- Single-item operations: (data, nil) or (nil, err).
-- Delete operations: (true, nil) or (nil, err).

local packages_cap = {}

-- Helper: translate a single GitLab package entry to GitHub Packages format.
local function translate_gl_package(p, version_count)
  return {
    id = p.id,
    name = p.name or "",
    package_type = p.package_type or "",
    url = "",
    html_url = p._links and p._links.web_path or "",
    version_count = version_count or 1,
    visibility = "public",
    owner = nil,
    repository = nil,
    created_at = p.created_at,
    updated_at = p.created_at,
  }
end

-- Helper: translate a single GitLab package entry to GitHub package version format.
local function translate_gl_package_version(p)
  return {
    id = p.id,
    name = p.version or "",
    url = "",
    package_html_url = "",
    html_url = p._links and p._links.web_path or "",
    license = "",
    description = "",
    created_at = p.created_at,
    updated_at = p.created_at,
    deleted_at = nil,
    metadata = { package_type = p.package_type or "" },
  }
end

-- list_org: paginated list of packages for an org (GitLab group), optionally
-- filtered by package_type.  pkg_type may be "" to list all types.
packages_cap.list_org = function(org, pkg_type)
  local url = base() .. "/groups/" .. org .. "/packages"
  if pkg_type and pkg_type ~= "" then
    url = url .. "?package_type=" .. pkg_type
  end
  url = append_page_params(url, PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_package, items), hdrs, nil
end

-- get_org: fetch a single package from an org by type+name.
-- Returns (package_data, nil) or (nil, err).
packages_cap.get_org = function(org, pkg_type, pkg_name)
  local url = base()
    .. "/groups/"
    .. org
    .. "/packages?package_type="
    .. pkg_type
    .. "&package_name="
    .. pkg_name
    .. "&per_page=100"
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  local entries = type(raw) == "table" and raw or {}
  if #entries == 0 then
    return nil, cap_err(404, "Not Found")
  end
  return translate_gl_package(entries[1], #entries), nil
end

-- delete_org: delete all versions of a package from an org by type+name.
-- Returns (true, nil) on success or (nil, err).
packages_cap.delete_org = function(org, pkg_type, pkg_name)
  local url = base()
    .. "/groups/"
    .. org
    .. "/packages?package_type="
    .. pkg_type
    .. "&package_name="
    .. pkg_name
    .. "&per_page=100"
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  local entries = type(raw) == "table" and raw or {}
  if #entries == 0 then
    return nil, cap_err(404, "Not Found")
  end
  for _, p in ipairs(entries) do
    fetch_json(base() .. "/projects/" .. p.project_id .. "/packages/" .. p.id, "DELETE")
  end
  return true, nil
end

-- list_org_versions: paginated list of versions of a package in an org.
packages_cap.list_org_versions = function(org, pkg_type, pkg_name)
  local url = base()
    .. "/groups/"
    .. org
    .. "/packages?package_type="
    .. pkg_type
    .. "&package_name="
    .. pkg_name
  url = append_page_params(url, PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_package_version, items), hdrs, nil
end

-- get_org_version: fetch a single package version from an org by version_id.
-- Returns (version_data, nil) or (nil, err).
packages_cap.get_org_version = function(org, pkg_type, pkg_name, version_id)
  local url = base()
    .. "/groups/"
    .. org
    .. "/packages?package_type="
    .. pkg_type
    .. "&package_name="
    .. pkg_name
    .. "&per_page=100"
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  local vid = tonumber(version_id)
  for _, p in ipairs(type(raw) == "table" and raw or {}) do
    if p.id == vid then
      return translate_gl_package_version(p), nil
    end
  end
  return nil, cap_err(404, "Not Found")
end

-- delete_org_version: delete a single package version from an org by version_id.
-- Returns (true, nil) on success or (nil, err).
packages_cap.delete_org_version = function(org, pkg_type, pkg_name, version_id)
  local url = base()
    .. "/groups/"
    .. org
    .. "/packages?package_type="
    .. pkg_type
    .. "&package_name="
    .. pkg_name
    .. "&per_page=100"
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  local vid = tonumber(version_id)
  for _, p in ipairs(type(raw) == "table" and raw or {}) do
    if p.id == vid then
      local dopts = auth() or {}
      dopts.method = "DELETE"
      local dok, dstatus =
        pcall(Fetch, base() .. "/projects/" .. p.project_id .. "/packages/" .. p.id, dopts)
      if not dok then
        return nil, cap_err(0, "network error deleting package version " .. tostring(version_id))
      end
      if dstatus ~= 204 then
        return nil,
          cap_err(dstatus, "upstream error " .. tostring(dstatus) .. " deleting package version")
      end
      return true, nil
    end
  end
  return nil, cap_err(404, "Not Found")
end

b:rest("get_org_packages", function(org)
  local pkg_type = GetParam("package_type") or ""
  local items, hdrs, err = packages_cap.list_org(org, pkg_type)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

b:rest("get_org_package", function(org, pkg_type, pkg_name)
  local data, err = packages_cap.get_org(org, pkg_type, pkg_name)
  cap_rest_respond(data, err)
end)

b:rest("delete_org_package", function(org, pkg_type, pkg_name)
  local ok, err = packages_cap.delete_org(org, pkg_type, pkg_name)
  cap_rest_204(ok, err)
end)

b:rest("get_org_package_versions", function(org, pkg_type, pkg_name)
  local items, hdrs, err = packages_cap.list_org_versions(org, pkg_type, pkg_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

b:rest("get_org_package_version", function(org, pkg_type, pkg_name, version_id)
  local data, err = packages_cap.get_org_version(org, pkg_type, pkg_name, version_id)
  cap_rest_respond(data, err)
end)

b:rest("delete_org_package_version", function(org, pkg_type, pkg_name, version_id)
  local ok, err = packages_cap.delete_org_version(org, pkg_type, pkg_name, version_id)
  cap_rest_204(ok, err)
end)

-- ---------------------------------------------------------------------------
-- Markdown capability module
-- ---------------------------------------------------------------------------
-- Owns fetch + HTML extraction for markdown rendering.
-- render(text) returns (html_string, status, nil) or (nil, nil, err).
-- render_raw(text) wraps plain text in JSON for the same GitLab endpoint.

local markdown_cap = {}

-- render: POST markdown text; returns (html_string, upstream_status, nil) or (nil, nil, err).
-- text: GitHub-format text field; gfm is always true for GitLab.
markdown_cap.render = function(text)
  local payload = EncodeJson({ text = text or "", gfm = true })
  local opts = auth() or {}
  opts.method = "POST"
  opts.body = payload
  opts.headers = opts.headers or {}
  opts.headers["Content-Type"] = "application/json"
  local ok, status, _, body = pcall(Fetch, base() .. "/markdown", opts)
  if not ok then
    return nil, nil, cap_err(0, "network error rendering markdown")
  end
  local parsed = DecodeJson(body or "{}") or {}
  return parsed.html or "", status, nil
end

-- ---------------------------------------------------------------------------
-- Git database capability module
-- ---------------------------------------------------------------------------
-- Owns fetch + translate for git object operations (blobs).
-- get_blob returns ({content, encoding, url, sha, size, node_id}, nil) or (nil, err).

local git_db_cap = {}

-- get_blob: fetch a git blob by SHA.
-- GitLab: GET /projects/:id/repository/blobs/:sha
-- Returns GitHub blob shape or (nil, err).
git_db_cap.get_blob = function(owner, repo_name, file_sha)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/repository/blobs/" .. file_sha
  )
  if not raw then
    return nil, err
  end
  return {
    content = raw.content,
    encoding = raw.encoding,
    url = "",
    sha = raw.sha,
    size = raw.size,
    node_id = "",
  },
    nil
end

-- Markdown -------------------------------------------------------------------

-- POST /markdown → POST /api/v4/markdown
-- GitLab returns {"html": "..."} JSON; extract the html field.
b:rest("render_markdown", function()
  local incoming = DecodeJson(GetBody() or "{}") or {}
  local html, status, err = markdown_cap.render(incoming.text)
  if not html then
    respond_json(err and err.status ~= 0 and err.status or 503, {})
    return
  end
  set_preamble(status, "text/html; charset=utf-8")
  Write(html)
end)

-- Git database (https://docs.github.com/en/rest/git) -----------------------

-- GET /repos/{owner}/{repo}/git/blobs/{file_sha}
-- GitLab: GET /projects/:id/repository/blobs/:sha
-- Returns {size, encoding, content, sha} — translate to GitHub blob shape.
b:rest("get_git_blob", function(owner, repo_name, file_sha)
  local data, err = git_db_cap.get_blob(owner, repo_name, file_sha)
  cap_rest_respond(data, err)
end)

-- POST /markdown/raw → POST /api/v4/markdown
-- GitLab has no separate raw endpoint; wrap the plain-text body in JSON.
b:rest("render_markdown_raw", function()
  local raw_text = GetBody() or ""
  local html, status, err = markdown_cap.render(raw_text)
  if not html then
    respond_json(err and err.status ~= 0 and err.status or 503, {})
    return
  end
  set_preamble(status, "text/html; charset=utf-8")
  Write(html)
end)

-- Dependabot alerts via GitLab Vulnerabilities API (requires Ultimate tier).
--
-- Endpoint mapping:
--   GET  /repos/{owner}/{repo}/dependabot/alerts       → GET  /projects/:id/vulnerabilities
--   GET  /repos/{owner}/{repo}/dependabot/alerts/{n}   → GET  /projects/:id/vulnerabilities/:n
--   PATCH /repos/{owner}/{repo}/dependabot/alerts/{n}  → POST /vulnerabilities/:n/dismiss|revert-to-detected
--   GET  /orgs/{org}/dependabot/alerts                 → GET  /groups/:org/vulnerabilities
--
-- GitLab state mapping:
--   detected / confirmed → open
--   dismissed            → dismissed
--   resolved             → fixed
--
-- Secrets and repository-access have no GitLab equivalent; those handlers
-- remain at their defaults (501 Not Implemented).

local GL_VULN_STATE_TO_GH = {
  detected = "open",
  confirmed = "open",
  dismissed = "dismissed",
  resolved = "fixed",
}

local GH_STATE_TO_GL_ACTION = {
  open = "revert-to-detected",
  dismissed = "dismiss",
}

local function translate_gl_vulnerability(v)
  if not v then
    return {}
  end
  local loc = v.location or {}
  local dep = loc.dependency or {}
  local pkg = dep.package or {}
  local identifiers = v.identifiers or {}
  local cve_id = nil
  for _, id in ipairs(identifiers) do
    if id.type == "cve" then
      cve_id = id.value
      break
    end
  end
  local package = { ecosystem = "unknown", name = pkg.name or "" }
  return {
    number = v.id or 0,
    state = GL_VULN_STATE_TO_GH[v.state or ""] or "open",
    dependency = {
      package = package,
      manifest_path = loc.file or "",
      scope = "runtime",
    },
    security_advisory = {
      ghsa_id = "",
      cve_id = cve_id,
      summary = v.title or "",
      description = v.description or "",
      severity = v.severity or "unknown",
      identifiers = identifiers,
      references = {},
      published_at = v.created_at or "",
      updated_at = v.updated_at or "",
      withdrawn_at = nil,
      vulnerabilities = {},
    },
    security_vulnerability = {
      package = package,
      severity = v.severity or "unknown",
      vulnerable_version_range = dep.version and ("= " .. dep.version) or "",
      first_patched_version = nil,
    },
    url = "",
    html_url = "",
    created_at = v.created_at or "",
    updated_at = v.updated_at or "",
    dismissed_at = v.dismissed_at,
    dismissed_by = nil,
    dismissed_reason = v.dismissed_reason,
    dismissed_comment = nil,
    fixed_at = nil,
    auto_dismissed_at = nil,
  }
end

-- ---------------------------------------------------------------------------
-- Security capability module
-- ---------------------------------------------------------------------------
-- Owns fetch + translation for GitLab vulnerability (Dependabot) and secret
-- detection (Secret Scanning) operations.
-- Paged list operations: (items, headers, nil) or (nil, nil, err).
-- Single-item operations: (data, nil) or (nil, err).

local security_cap = {}

-- Secret Scanning state/reason mappings (shared with security_cap operations).
--
-- GitLab dismissed_reason → GitHub resolution:
--   false_positive   → false_positive
--   acceptable_risk  → wont_fix
--   used_in_tests    → used_in_tests
--   mitigating_control / not_applicable → wont_fix

local GL_SECRET_DISMISS_REASON_TO_GH = {
  false_positive = "false_positive",
  acceptable_risk = "wont_fix",
  used_in_tests = "used_in_tests",
  mitigating_control = "wont_fix",
  not_applicable = "wont_fix",
}

local GH_SECRET_STATE_TO_GL_ACTION = {
  open = "revert-to-detected",
  dismissed = "dismiss",
  resolved = "resolve",
}

local function translate_gl_secret_alert(v)
  if not v then
    return {}
  end
  local state = GL_VULN_STATE_TO_GH[v.state or ""] or "open"
  if v.state == "resolved" then
    state = "resolved"
  end
  local identifiers = v.identifiers or {}
  local secret_type = ""
  for _, id in ipairs(identifiers) do
    if id.type == "secret_detection" then
      secret_type = id.value or ""
      break
    end
  end
  local scanner = v.scanner or {}
  if secret_type == "" then
    secret_type = scanner.id or ""
  end
  return {
    number = v.id or 0,
    created_at = v.created_at or "",
    updated_at = v.updated_at or "",
    url = "",
    html_url = "",
    locations_url = "",
    state = state,
    resolution = GL_SECRET_DISMISS_REASON_TO_GH[v.dismissed_reason or ""],
    resolved_by = nil,
    resolved_at = v.dismissed_at,
    resolution_comment = nil,
    secret_type = secret_type,
    secret_type_display_name = v.title or "",
    secret = "",
    push_protection_bypassed = nil,
    push_protection_bypassed_by = nil,
    push_protection_bypassed_at = nil,
    validity = "unknown",
    publicly_leaked = false,
    multi_repo = false,
    auto_dismissed_at = nil,
  }
end

-- list_repo_dependabot: paginated list of dependabot (vulnerability) alerts for a repo.
security_cap.list_repo_dependabot = function(owner, repo_name)
  local url = append_page_params(
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/vulnerabilities",
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_vulnerability, items), hdrs, nil
end

-- get_repo_dependabot: fetch a single dependabot alert by number.
security_cap.get_repo_dependabot = function(owner, repo_name, alert_number)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/vulnerabilities/" .. alert_number
  )
  if not raw then
    return nil, err
  end
  return translate_gl_vulnerability(raw), nil
end

-- update_repo_dependabot: update (dismiss/reopen) a dependabot alert.
-- body: raw GitHub-format JSON string with a "state" field.
security_cap.update_repo_dependabot = function(_owner, _repo_name, alert_number, body)
  local req = DecodeJson(body or "{}")
  local action = GH_STATE_TO_GL_ACTION[req.state or ""] or "revert-to-detected"
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/vulnerabilities/" .. alert_number .. "/" .. action,
    "POST",
    EncodeJson({})
  )
  if not raw then
    return nil, err
  end
  return translate_gl_vulnerability(raw), nil
end

-- list_org_dependabot: paginated list of dependabot alerts for an org (GitLab group).
security_cap.list_org_dependabot = function(org)
  local url = append_page_params(base() .. "/groups/" .. org .. "/vulnerabilities", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_vulnerability, items), hdrs, nil
end

-- list_repo_secret: paginated list of secret-scanning alerts for a repo.
security_cap.list_repo_secret = function(owner, repo_name)
  local url = append_page_params(
    base()
      .. "/projects/"
      .. project_id(owner, repo_name)
      .. "/vulnerabilities?report_type=secret_detection",
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_secret_alert, items), hdrs, nil
end

-- list_org_secret: paginated list of secret-scanning alerts for an org.
security_cap.list_org_secret = function(org)
  local url = append_page_params(
    base() .. "/groups/" .. org .. "/vulnerabilities?report_type=secret_detection",
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gl_secret_alert, items), hdrs, nil
end

-- get_secret: fetch a single secret-scanning alert by number.
security_cap.get_secret = function(owner, repo_name, alert_number)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/vulnerabilities/" .. alert_number
  )
  if not raw then
    return nil, err
  end
  return translate_gl_secret_alert(raw), nil
end

-- update_secret: update (dismiss/reopen/resolve) a secret-scanning alert.
-- body: raw GitHub-format JSON string with a "state" field.
security_cap.update_secret = function(_owner, _repo_name, alert_number, body)
  local req = DecodeJson(body or "{}")
  local action = GH_SECRET_STATE_TO_GL_ACTION[req.state or ""] or "revert-to-detected"
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/vulnerabilities/" .. alert_number .. "/" .. action,
    "POST",
    EncodeJson({})
  )
  if not raw then
    return nil, err
  end
  return translate_gl_secret_alert(raw), nil
end

b:rest("list_repo_dependabot_alerts", function(owner, repo_name)
  local items, hdrs, err = security_cap.list_repo_dependabot(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

b:rest("get_repo_dependabot_alert", function(owner, repo_name, alert_number)
  local data, err = security_cap.get_repo_dependabot(owner, repo_name, alert_number)
  cap_rest_respond(data, err)
end)

b:rest("update_repo_dependabot_alert", function(owner, repo_name, alert_number)
  local data, err = security_cap.update_repo_dependabot(owner, repo_name, alert_number, GetBody())
  cap_rest_respond(data, err)
end)

b:rest("list_org_dependabot_alerts", function(org)
  local items, hdrs, err = security_cap.list_org_dependabot(org)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

b:rest("list_repo_secret_scanning_alerts", function(owner, repo_name)
  local items, hdrs, err = security_cap.list_repo_secret(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

b:rest("list_org_secret_scanning_alerts", function(org)
  local items, hdrs, err = security_cap.list_org_secret(org)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

b:rest("get_secret_scanning_alert", function(owner, repo_name, alert_number)
  local data, err = security_cap.get_secret(owner, repo_name, alert_number)
  cap_rest_respond(data, err)
end)

b:rest("update_secret_scanning_alert", function(owner, repo_name, alert_number)
  local data, err = security_cap.update_secret(owner, repo_name, alert_number, GetBody())
  cap_rest_respond(data, err)
end)

-- ---------------------------------------------------------------------------
-- Gists capability module (GitLab Snippets)
-- ---------------------------------------------------------------------------
-- Owns fetch + translation for GitLab snippet operations mapped to GitHub gists.
-- Single-item operations: (data, nil) or (nil, err).
-- List operations: (items, nil) or (nil, err).  (Not paginated — GitLab snippet
-- lists are small and proxy_json_list was used in the original code.)
-- Delete operations: (true, nil) or (nil, err).

local gists_cap = {}

local function translate_gl_snippet_author(a)
  if not a then
    return {}
  end
  return {
    login = a.username or "",
    id = a.id or 0,
    node_id = "",
    avatar_url = a.avatar_url or "",
    html_url = a.web_url or "",
    type = "User",
    site_admin = false,
  }
end

local function translate_gl_snippet(s)
  if not s then
    return {}
  end
  local files = {}
  for _, f in ipairs(s.files or {}) do
    local name = f.path or ""
    files[name] = { filename = name, raw_url = f.raw_url or "" }
  end
  -- Fall back to file_name for older single-file snippets.
  if not next(files) and s.file_name then
    files[s.file_name] = { filename = s.file_name, raw_url = s.raw_url or "" }
  end
  return {
    id = tostring(s.id or ""),
    description = s.title or "",
    public = s.visibility == "public",
    owner = translate_gl_snippet_author(s.author),
    files = files,
    created_at = s.created_at,
    updated_at = s.updated_at,
    html_url = s.web_url or "",
    url = "",
    node_id = "",
  }
end

local function translate_gl_snippet_note(n)
  if not n then
    return {}
  end
  return {
    id = n.id or 0,
    body = n.body or "",
    user = translate_gl_snippet_author(n.author),
    created_at = n.created_at,
    updated_at = n.updated_at,
    url = "",
    node_id = "",
  }
end

-- Helper: convert a GitHub gist create/update request body to GitLab snippet format.
local function gl_snippet_req(req)
  local gl = {}
  if req.description ~= nil then
    gl.title = req.description
  end
  if req.public ~= nil then
    gl.visibility = (req.public == true or req.public == "true") and "public" or "private"
  end
  if req.files ~= nil then
    local files = {}
    for name, f in pairs(req.files) do
      if f then
        table.insert(files, { file_path = name, content = f.content or "" })
      end
    end
    gl.files = files
  end
  return EncodeJson(gl)
end

-- list: list own snippets (mapped to authenticated user's gists).
gists_cap.list = function()
  local raw, err = cap_fetch(fetch_json, base() .. "/snippets")
  if not raw then
    return nil, err
  end
  return translate_list(translate_gl_snippet, type(raw) == "table" and raw or {}), nil
end

-- list_public: list public snippets (mapped to public gists).
gists_cap.list_public = function()
  local raw, err = cap_fetch(fetch_json, base() .. "/snippets/public")
  if not raw then
    return nil, err
  end
  return translate_list(translate_gl_snippet, type(raw) == "table" and raw or {}), nil
end

-- create: create a new snippet from a GitHub gist request body.
gists_cap.create = function(body)
  local req = DecodeJson(body or "{}") or {}
  local raw, err = cap_fetch(fetch_json, base() .. "/snippets", "POST", gl_snippet_req(req))
  if not raw then
    return nil, err
  end
  return translate_gl_snippet(raw), nil
end

-- get: fetch a single snippet by ID.
gists_cap.get = function(id)
  local raw, err = cap_fetch(fetch_json, base() .. "/snippets/" .. id)
  if not raw then
    return nil, err
  end
  return translate_gl_snippet(raw), nil
end

-- update: update (PUT) a snippet from a GitHub gist request body.
gists_cap.update = function(id, body)
  local req = DecodeJson(body or "{}") or {}
  local raw, err = cap_fetch(fetch_json, base() .. "/snippets/" .. id, "PUT", gl_snippet_req(req))
  if not raw then
    return nil, err
  end
  return translate_gl_snippet(raw), nil
end

-- delete: delete a snippet by ID.
-- Returns (true, nil) on 200/204 success or (nil, err) on failure.
gists_cap.delete = function(id)
  local dopts = auth() or {}
  dopts.method = "DELETE"
  local ok, status = pcall(Fetch, base() .. "/snippets/" .. id, dopts)
  if not ok then
    return nil, cap_err(0, "network error deleting snippet " .. tostring(id))
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting snippet")
  end
  return true, nil
end

-- list_comments: list notes (comments) on a snippet.
gists_cap.list_comments = function(id)
  local raw, err = cap_fetch(fetch_json, base() .. "/snippets/" .. id .. "/notes")
  if not raw then
    return nil, err
  end
  return translate_list(translate_gl_snippet_note, type(raw) == "table" and raw or {}), nil
end

-- create_comment: add a note to a snippet.
gists_cap.create_comment = function(id, body)
  local req = DecodeJson(body or "{}") or {}
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/snippets/" .. id .. "/notes",
    "POST",
    EncodeJson({ body = req.body or "" })
  )
  if not raw then
    return nil, err
  end
  return translate_gl_snippet_note(raw), nil
end

-- get_comment: fetch a single note on a snippet.
gists_cap.get_comment = function(id, comment_id)
  local raw, err = cap_fetch(fetch_json, base() .. "/snippets/" .. id .. "/notes/" .. comment_id)
  if not raw then
    return nil, err
  end
  return translate_gl_snippet_note(raw), nil
end

-- update_comment: update a note on a snippet.
gists_cap.update_comment = function(id, comment_id, body)
  local req = DecodeJson(body or "{}") or {}
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/snippets/" .. id .. "/notes/" .. comment_id,
    "PUT",
    EncodeJson({ body = req.body or "" })
  )
  if not raw then
    return nil, err
  end
  return translate_gl_snippet_note(raw), nil
end

-- delete_comment: delete a note on a snippet.
-- Returns (true, nil) on 200/204 success or (nil, err) on failure.
gists_cap.delete_comment = function(id, comment_id)
  local dopts = auth() or {}
  dopts.method = "DELETE"
  local ok, status = pcall(Fetch, base() .. "/snippets/" .. id .. "/notes/" .. comment_id, dopts)
  if not ok then
    return nil,
      cap_err(
        0,
        "network error deleting snippet comment " .. tostring(id) .. "/" .. tostring(comment_id)
      )
  end
  if status ~= 200 and status ~= 204 then
    return nil,
      cap_err(status, "upstream error " .. tostring(status) .. " deleting snippet comment")
  end
  return true, nil
end

b:rest("get_gists", function()
  local data, err = gists_cap.list()
  cap_rest_respond(data, err)
end)

b:rest("get_gists_public", function()
  local data, err = gists_cap.list_public()
  cap_rest_respond(data, err)
end)

b:rest("post_gists", function()
  local data, err = gists_cap.create(GetBody())
  cap_rest_created(data, err)
end)

b:rest("get_gist", function(id)
  local data, err = gists_cap.get(id)
  cap_rest_respond(data, err)
end)

b:rest("patch_gist", function(id)
  local data, err = gists_cap.update(id, GetBody())
  cap_rest_respond(data, err)
end)

b:rest("delete_gist", function(id)
  local ok, err = gists_cap.delete(id)
  cap_rest_204(ok, err)
end)

b:rest("get_gist_comments", function(id)
  local data, err = gists_cap.list_comments(id)
  cap_rest_respond(data, err)
end)

b:rest("post_gist_comment", function(id)
  local data, err = gists_cap.create_comment(id, GetBody())
  cap_rest_created(data, err)
end)

b:rest("get_gist_comment", function(id, comment_id)
  local data, err = gists_cap.get_comment(id, comment_id)
  cap_rest_respond(data, err)
end)

b:rest("patch_gist_comment", function(id, comment_id)
  local data, err = gists_cap.update_comment(id, comment_id, GetBody())
  cap_rest_respond(data, err)
end)

b:rest("delete_gist_comment", function(id, comment_id)
  local ok, err = gists_cap.delete_comment(id, comment_id)
  cap_rest_204(ok, err)
end)

b:rest("get_user_gists", function(_username)
  -- GitLab doesn't expose per-user public snippet lists; approximate with own snippets.
  local data, err = gists_cap.list()
  cap_rest_respond(data, err)
end)

-- ── Reactions (GitLab award emoji) ────────────────────────────────────────────

-- Issue reactions: GitLab has full award_emoji support on issues.
b:rest("get_issue_reactions", function(owner, repo_name, issue_number)
  local items, hdrs, err = reactions_cap.list_issue(owner, repo_name, issue_number)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

b:rest("post_issue_reaction", function(owner, repo_name, issue_number)
  local data, err = reactions_cap.create_issue(owner, repo_name, issue_number, GetBody())
  cap_rest_created(data, err)
end)

b:rest("delete_issue_reaction", function(owner, repo_name, issue_number, reaction_id)
  local ok, err = reactions_cap.delete_issue(owner, repo_name, issue_number, reaction_id)
  cap_rest_204(ok, err)
end)

-- ---------------------------------------------------------------------------
-- GraphQL resolvers — Query root fields and node resolvers
-- ---------------------------------------------------------------------------

-- Query.repositoryOwner: look up a User or Organization (GitLab group) by login.
b:graphql("Query.repositoryOwner", function(_parent, args, ctx)
  if not args.login then
    graphql_error(ctx, "repositoryOwner requires a login argument")
    return nil
  end
  local udata, _ = users.by_username(args.login)
  if udata then
    return graphql_translate_user(udata)
  end
  local gdata, _ = orgs.get(args.login)
  if gdata then
    return graphql_translate_org(gdata)
  end
  return nil
end)

-- Query.viewer: resolve the authenticated user via GET /user.
-- Uses graphql_fetch_or_error to surface FORBIDDEN errors when unauthenticated.
b:graphql("Query.viewer", function(_parent, _args, ctx)
  local data = graphql_fetch_or_error(fetch_json, base() .. "/user", ctx, nil)
  if not data then
    return nil
  end
  local u = graphql_translate_user(translate_gl_user(data))
  u.isViewer = true
  return u
end)

-- Query.user: look up a User by login.
b:graphql("Query.user", function(_parent, args, ctx)
  if not args.login then
    graphql_error(ctx, "user requires a login argument")
    return nil
  end
  local data, _ = users.by_username(args.login)
  if not data then
    return nil
  end
  return graphql_translate_user(data)
end)

-- Query.organization: look up a GitLab group by path.
b:graphql("Query.organization", function(_parent, args, ctx)
  if not args.login then
    graphql_error(ctx, "organization requires a login argument")
    return nil
  end
  local data, _ = orgs.get(args.login)
  if not data then
    return nil
  end
  return graphql_translate_org(data)
end)

-- Query.repository: look up a Repository by owner and name.
b:graphql("Query.repository", function(_parent, args, ctx)
  if not args.owner or not args.name then
    graphql_error(ctx, "repository requires owner and name arguments")
    return nil
  end
  local data, _ = repos.get(args.owner, args.name)
  if not data then
    return nil
  end
  return graphql_translate_repo(data)
end)

-- node.Repository: fetch a repository by "owner/repo" local ID.
b:graphql("node.Repository", function(local_id, _ctx)
  local owner, repo = local_id:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  local data, _ = repos.get(owner, repo)
  if not data then
    return nil
  end
  return graphql_translate_repo(data)
end)

-- node.User: fetch a user by login.
b:graphql("node.User", function(local_id, _ctx)
  local data, _ = users.by_username(local_id)
  if not data then
    return nil
  end
  return graphql_translate_user(data)
end)

-- node.Organization: fetch a group by path.
b:graphql("node.Organization", function(local_id, _ctx)
  local data, _ = orgs.get(local_id)
  if not data then
    return nil
  end
  return graphql_translate_org(data)
end)

-- node.Issue: fetch an issue by "owner/repo/iid" local ID.
b:graphql("node.Issue", function(local_id, _ctx)
  local owner, repo, iid = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ = graphql_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo) .. "/issues/" .. iid
  )
  if not data then
    return nil
  end
  return graphql_translate_issue(translate_gl_issue(data), owner, repo)
end)

-- node.PullRequest: fetch a merge request by "owner/repo/iid" local ID.
b:graphql("node.PullRequest", function(local_id, _ctx)
  local owner, repo, iid = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ = graphql_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo) .. "/merge_requests/" .. iid
  )
  if not data then
    return nil
  end
  return graphql_translate_pr(translate_gl_mr(data), owner, repo)
end)

-- node.IssueComment: fetch an issue note by "owner/repo/iid/note_id" local ID.
-- GitLab notes require the issue iid in the path, so the local ID encodes four segments.
b:graphql("node.IssueComment", function(local_id, _ctx)
  local owner, repo, iid, nid = local_id:match("^([^/]+)/([^/]+)/(%d+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ = graphql_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo) .. "/issues/" .. iid .. "/notes/" .. nid
  )
  if not data then
    return nil
  end
  return graphql_translate_comment(translate_gl_note(data), owner, repo)
end)

-- node.Release: fetch a release by "owner/repo/tag_name" local ID.
-- GitLab identifies releases by tag_name, not integer ID.
b:graphql("node.Release", function(local_id, _ctx)
  local owner, repo, tag = local_id:match("^([^/]+)/([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  local data, _ = graphql_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo) .. "/releases/" .. tag
  )
  if not data then
    return nil
  end
  return graphql_translate_release(translate_gl_release(data), owner, repo)
end)

-- node.Label: fetch a label by "owner/repo/label_id" local ID.
b:graphql("node.Label", function(local_id, _ctx)
  local owner, repo, lid = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ = graphql_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo) .. "/labels/" .. lid
  )
  if not data then
    return nil
  end
  return graphql_translate_label(translate_gl_label(data), owner, repo)
end)

-- node.Milestone: fetch a milestone by "owner/repo/number" local ID.
-- GitLab milestone numbers are iid (project-local); stored as number in the node ID.
b:graphql("node.Milestone", function(local_id, _ctx)
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ = graphql_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo) .. "/milestones/" .. number
  )
  if not data then
    return nil
  end
  return graphql_translate_milestone(translate_gl_milestone(data), owner, repo)
end)

-- node.Commit: fetch a commit by "owner/repo/sha" local ID.
-- GitLab returns a flat commit object; translate to REST shape before passing to the shared translator.
b:graphql("node.Commit", function(local_id, _ctx)
  local owner, repo, sha = local_id:match("^([^/]+)/([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  local c, _ = graphql_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo) .. "/repository/commits/" .. sha
  )
  if not c then
    return nil
  end
  local rest_commit = {
    sha = c.id,
    html_url = c.web_url or "",
    commit = {
      message = c.message,
      author = { name = c.author_name, email = c.author_email, date = c.authored_date },
      committer = {
        name = c.committer_name or c.author_name,
        email = c.committer_email or c.author_email,
        date = c.committed_date or c.authored_date,
      },
    },
  }
  return graphql_translate_commit(rest_commit, owner, repo)
end)

-- node.Ref: fetch a branch ref by "owner/repo/refs/heads/..." local ID.
-- GitLab branch objects use commit.id for the SHA; normalise to commit.sha before translating.
b:graphql("node.Ref", function(local_id, _ctx)
  local owner, repo, ref_path = local_id:match("^([^/]+)/([^/]+)/(refs/.+)$")
  if not owner then
    return nil
  end
  local branch = ref_path:match("^refs/heads/(.+)$")
  if not branch then
    return nil
  end
  local data, _ = graphql_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo) .. "/repository/branches/" .. branch
  )
  if not data then
    return nil
  end
  if data.commit then
    data.commit.sha = data.commit.id
  end
  local repo_stub = { __typename = "Repository", nameWithOwner = owner .. "/" .. repo }
  return graphql_translate_ref(data, repo_stub)
end)

-- node.Team: fetch a team (subgroup) by "org/slug" local ID.
-- GitLab teams map to subgroups; fetch by URL-encoded path /groups/{org}%2F{slug}.
b:graphql("node.Team", function(local_id, _ctx)
  local org, slug = local_id:match("^([^/]+)/([^/]+)$")
  if not org then
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, base() .. "/groups/" .. org .. "%2F" .. slug)
  if not data then
    return nil
  end
  return graphql_translate_team(translate_gl_team(data), org)
end)

-- ---------------------------------------------------------------------------
-- Repository connection sub-resolvers
-- ---------------------------------------------------------------------------

-- Headers GitLab uses for the total item count.
local GL_TOTAL_HEADERS = { "X-Total" }

-- Local helper: build a paginated Relay Connection from a GitLab list endpoint.
-- For backward pagination (last without before), prefetches total via a per_page=1 request
-- so graphql_cursor_url can seek the correct last page on the subsequent full fetch.
local function gitlab_repo_connection(owner, repo, suffix, args, ctx, translate_fn, make_conn)
  local url_base = base() .. "/projects/" .. project_id(owner, repo) .. suffix
  local total
  if args.last and not args.before then
    total = graphql_prefetch_total_from_headers(fetch_json, url_base, PAGES, GL_TOTAL_HEADERS)
  end
  local url = graphql_cursor_url(url_base, args, PAGES, total)
  local data, headers, err = graphql_fetch_with_headers(fetch_json, url)
  if not data then
    graphql_error(ctx, err)
    return nil
  end
  total = (headers["X-Total"] and tonumber(headers["X-Total"])) or total
  local nodes = {}
  for _, item in ipairs(data) do
    nodes[#nodes + 1] = translate_fn(item)
  end
  return make_conn(nodes, args, total, ctx)
end

-- Repository.issues: paginated list of issues.
-- GitLab issues are always real issues (no PR/issue mixing like Gitea).
b:graphql("Repository.issues", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitlab_repo_connection(owner, name, "/issues", args, ctx, function(i)
    return graphql_translate_issue(translate_gl_issue(i), owner, name)
  end, graphql_issues_connection)
end)

-- Repository.pullRequests: paginated list of merge requests.
b:graphql("Repository.pullRequests", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitlab_repo_connection(owner, name, "/merge_requests", args, ctx, function(mr)
    return graphql_translate_pr(translate_gl_mr(mr), owner, name)
  end, graphql_prs_connection)
end)

-- Repository.releases: paginated list of releases.
-- GitLab releases use tag_name as identifier; we assign a synthetic integer id.
b:graphql("Repository.releases", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitlab_repo_connection(owner, name, "/releases", args, ctx, function(r)
    local rel = graphql_translate_release(translate_gl_release(r), owner, name)
    -- Override node ID to use tag_name so node.Release can fetch via /releases/{tag}
    rel.id = encode_node_id("Release", owner .. "/" .. name .. "/" .. (r.tag_name or ""))
    return rel
  end, function(n, a, t, c)
    return graphql_make_connection("Release", n, a, t, c)
  end)
end)

-- Repository.labels: paginated list of labels.
b:graphql("Repository.labels", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitlab_repo_connection(owner, name, "/labels", args, ctx, function(l)
    return graphql_translate_label(translate_gl_label(l), owner, name)
  end, graphql_labels_connection)
end)

-- Repository.milestones: paginated list of milestones.
b:graphql("Repository.milestones", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitlab_repo_connection(owner, name, "/milestones", args, ctx, function(m)
    return graphql_translate_milestone(translate_gl_milestone(m), owner, name)
  end, function(n, a, t, c)
    return graphql_make_connection("Milestone", n, a, t, c)
  end)
end)

-- Repository.refs: paginated list of branches as Ref objects.
-- GitLab branch objects use commit.id for the SHA; normalise to commit.sha.
b:graphql("Repository.refs", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitlab_repo_connection(owner, name, "/repository/branches", args, ctx, function(br)
    if br.commit then
      br.commit.sha = br.commit.id
    end
    return graphql_translate_ref(br, parent)
  end, graphql_refs_connection)
end)

-- Repository.collaborators: paginated list of project members as Users.
-- GitLab uses /members/all (not /collaborators) — consistent with the REST handler.
b:graphql("Repository.collaborators", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitlab_repo_connection(owner, name, "/members/all", args, ctx, function(m)
    return graphql_translate_user(translate_gl_member(m))
  end, function(n, a, t, c)
    return graphql_make_connection("RepositoryCollaborator", n, a, t, c)
  end)
end)

-- Repository.defaultBranchRef: enrich the inline stub with full branch data.
-- The parent already carries {__typename="Ref",name="main"} from graphql_translate_repo.
-- GitLab branch objects use commit.id for the SHA; normalise to commit.sha.
b:graphql("Repository.defaultBranchRef", function(parent, _args, _ctx)
  local branch = parent.defaultBranchRef and parent.defaultBranchRef.name
  if not branch then
    return nil
  end
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  local data, _ = graphql_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, name) .. "/repository/branches/" .. branch
  )
  if not data then
    return nil
  end
  if data.commit then
    data.commit.sha = data.commit.id
  end
  return graphql_translate_ref(data, parent)
end)

-- ---------------------------------------------------------------------------
-- Issue and PullRequest sub-resolvers
-- ---------------------------------------------------------------------------

-- Issue.comments: paginated list of notes for a single issue.
-- GitLab notes are fetched from /projects/{id}/issues/{iid}/notes.
-- Comment node IDs encode four segments (owner/repo/iid/note_id) so the
-- node.IssueComment resolver can reconstruct the GitLab API path.
b:graphql("Issue.comments", function(parent, args, ctx)
  local _, local_id = decode_node_id(parent.id)
  if not local_id then
    return nil
  end
  local owner, repo, iid = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local url_base = base()
    .. "/projects/"
    .. project_id(owner, repo)
    .. "/issues/"
    .. iid
    .. "/notes"
  local total
  if args.last and not args.before then
    total = graphql_prefetch_total_from_headers(fetch_json, url_base, PAGES, GL_TOTAL_HEADERS)
  end
  local url = graphql_cursor_url(url_base, args, PAGES, total)
  local data, headers, err = graphql_fetch_with_headers(fetch_json, url)
  if not data then
    graphql_error(ctx, err)
    return nil
  end
  total = (headers["X-Total"] and tonumber(headers["X-Total"])) or total
  local nodes = {}
  for _, n in ipairs(data) do
    if not n.system then
      local comment = graphql_translate_comment(translate_gl_note(n), owner, repo)
      -- Override node ID to include the issue iid so node.IssueComment can fetch it back.
      comment.id =
        encode_node_id("IssueComment", owner .. "/" .. repo .. "/" .. iid .. "/" .. tostring(n.id))
      nodes[#nodes + 1] = comment
    end
  end
  return graphql_make_connection("IssueComment", nodes, args, total, ctx)
end)

-- PullRequest.commits: paginated commit list for a merge request.
-- GitLab MR commits use .id for the SHA and flat author/committer fields.
b:graphql("PullRequest.commits", function(parent, args, ctx)
  local _, local_id = decode_node_id(parent.id)
  if not local_id then
    return nil
  end
  local owner, repo, iid = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local url_base = base()
    .. "/projects/"
    .. project_id(owner, repo)
    .. "/merge_requests/"
    .. iid
    .. "/commits"
  local total
  if args.last and not args.before then
    total = graphql_prefetch_total_from_headers(fetch_json, url_base, PAGES, GL_TOTAL_HEADERS)
  end
  local url = graphql_cursor_url(url_base, args, PAGES, total)
  local data, headers, err = graphql_fetch_with_headers(fetch_json, url)
  if not data then
    graphql_error(ctx, err)
    return nil
  end
  total = (headers["X-Total"] and tonumber(headers["X-Total"])) or total
  local nodes = {}
  for _, c in ipairs(data) do
    -- Translate GitLab's flat commit format to the REST shape graphql_translate_commit expects.
    local rest_commit = {
      sha = c.id,
      html_url = c.web_url or "",
      commit = {
        message = c.message,
        author = { name = c.author_name, email = c.author_email, date = c.authored_date },
        committer = {
          name = c.committer_name or c.author_name,
          email = c.committer_email or c.author_email,
          date = c.committed_date or c.authored_date,
        },
      },
    }
    nodes[#nodes + 1] = {
      __typename = "PullRequestCommit",
      id = encode_node_id("PullRequestCommit", c.id or ""),
      commit = graphql_translate_commit(rest_commit, owner, repo),
      url = c.web_url or "",
    }
  end
  return graphql_make_connection("PullRequestCommit", nodes, args, total, ctx)
end)

-- PullRequest.reviews: MR approvals mapped to review objects.
-- GitLab's approvals endpoint returns a single object (not a paginated list),
-- so we fetch it directly and build an inline connection.
b:graphql("PullRequest.reviews", function(parent, args, ctx)
  local _, local_id = decode_node_id(parent.id)
  if not local_id then
    return nil
  end
  local owner, repo, iid = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, err = graphql_fetch(
    fetch_json,
    base() .. "/projects/" .. project_id(owner, repo) .. "/merge_requests/" .. iid .. "/approvals"
  )
  if not data then
    graphql_error(ctx, err)
    return nil
  end
  local reviews = translate_gl_approvals_to_reviews(data)
  local nodes = {}
  for _, r in ipairs(reviews) do
    nodes[#nodes + 1] = graphql_translate_review(r, owner, repo)
  end
  return graphql_make_connection("PullRequestReview", nodes, args, #nodes, ctx)
end)

-- Repository.languages: fetch language breakdown as a LanguageConnection.
-- GitLab returns {"Language": percentage, ...} (percentages, not byte counts).
-- We use the percentage as the "size" in edges since byte counts are unavailable.
b:graphql("Repository.languages", function(parent, _args, _ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  local data, _ =
    graphql_fetch(fetch_json, base() .. "/projects/" .. project_id(owner, name) .. "/languages")
  if not data then
    return nil
  end
  local nodes, edges = {}, {}
  local total_size = 0
  for lang_name, size in pairs(data) do
    total_size = total_size + size
    local node = {
      __typename = "Language",
      id = encode_node_id("Language", lang_name),
      name = lang_name,
      color = nil,
    }
    nodes[#nodes + 1] = node
    edges[#edges + 1] = { cursor = "", node = node, size = size }
  end
  return {
    __typename = "LanguageConnection",
    totalCount = #nodes,
    totalSize = total_size,
    pageInfo = {
      __typename = "PageInfo",
      hasNextPage = false,
      hasPreviousPage = false,
      startCursor = nil,
      endCursor = nil,
    },
    nodes = nodes,
    edges = edges,
  }
end)

-- ---------------------------------------------------------------------------
-- Query.search
-- ---------------------------------------------------------------------------

-- Query.search: map GitHub GraphQL search to GitLab search endpoints.
-- Supports REPOSITORY, USER, and ISSUE types; all others return empty.
-- GitLab uses /projects?search=, /users?search=, and /issues?search=.
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
      for _, r in ipairs(data) do
        nodes[#nodes + 1] = graphql_translate_repo(translate_gl_repo(r))
      end
      repo_count = #nodes
    end
  elseif search_type == "USER" then
    local data, _, err = graphql_fetch_with_headers(
      fetch_json,
      base() .. "/users?search=" .. q .. "&per_page=" .. per_page
    )
    if not data then
      graphql_error(ctx, err)
    else
      for _, u in ipairs(data) do
        nodes[#nodes + 1] = graphql_translate_user(translate_gl_user(u))
      end
      user_count = #nodes
    end
  elseif search_type == "ISSUE" then
    local data, _, err = graphql_fetch_with_headers(
      fetch_json,
      base() .. "/issues?search=" .. q .. "&per_page=" .. per_page
    )
    if not data then
      graphql_error(ctx, err)
    else
      for _, i in ipairs(data) do
        nodes[#nodes + 1] = graphql_translate_issue(translate_gl_issue(i))
      end
      issue_count = #nodes
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

-- ─── Inbound webhook event handlers ─────────────────────────────────────────
--
-- GitLab uses X-Gitlab-Event with values like "Issues Hook", "Note Hook".
-- Event data lives in payload.object_attributes; the project uses a simpler
-- format than the REST API (namespace is a string, not a nested object).

-- Translate a GitLab webhook project object to GitHub repo format.
-- Webhook project: namespace is a bare string; path_with_namespace gives owner/repo.
local function translate_gl_webhook_project(p)
  if not p then
    return {}
  end
  local pns = p.path_with_namespace or ""
  local slash = pns:find("/", 1, true)
  local owner_login = slash and pns:sub(1, slash - 1) or pns
  local repo_name = slash and pns:sub(slash + 1) or (p.name or pns)
  -- visibility_level: 0=private, 10=internal, 20=public (older versions)
  -- visibility: "private"/"internal"/"public" (newer versions)
  local vis = p.visibility_level or (p.visibility == "public" and 20 or 0)
  return {
    id = p.id,
    node_id = "",
    name = repo_name,
    full_name = pns,
    private = vis ~= 20,
    owner = {
      login = owner_login,
      id = 0,
      node_id = "",
      avatar_url = "",
      url = "",
      html_url = "",
      type = "User",
    },
    html_url = p.web_url or p.homepage or "",
    description = p.description or "",
    fork = false,
    url = p.web_url or p.homepage or "",
    ssh_url = p.git_ssh_url or "",
    clone_url = p.git_http_url or "",
    homepage = p.homepage or "",
    default_branch = p.default_branch or "",
    visibility = vis == 20 and "public" or "private",
  }
end

-- Build a normalized pull_request table from a Merge Request Hook payload.
-- object_attributes carries the MR data; labels, assignees, and reviewers are
-- top-level arrays in the payload (current state, not diffs).
local function webhook_mr_from_gl(payload)
  local oa = payload.object_attributes or {}
  local labels_arr, assignees_arr, reviewers_arr = {}, {}, {}
  for _, l in ipairs(payload.labels or {}) do
    labels_arr[#labels_arr + 1] = translate_gl_label(l)
  end
  for _, u in ipairs(payload.assignees or {}) do
    assignees_arr[#assignees_arr + 1] = translate_gl_user(u)
  end
  for _, u in ipairs(payload.reviewers or {}) do
    reviewers_arr[#reviewers_arr + 1] = translate_gl_user(u)
  end
  local diff_refs = oa.diff_refs or {}
  local state = oa.state or "opened"
  if state == "opened" then
    state = "open"
  elseif state == "merged" then
    state = "closed"
  end
  return {
    id = oa.id,
    node_id = "",
    number = oa.iid,
    state = state,
    locked = false,
    title = oa.title,
    body = oa.description,
    user = translate_gl_user(payload.user),
    head = {
      label = oa.source_branch or "",
      ref = oa.source_branch or "",
      sha = diff_refs.head_sha or (oa.last_commit and oa.last_commit.id) or "",
      repo = nil, -- source project not included for simplicity (same as REST translator)
    },
    base = {
      label = oa.target_branch or "",
      ref = oa.target_branch or "",
      sha = diff_refs.base_sha or "",
      repo = nil,
    },
    draft = oa.draft or oa.work_in_progress or false,
    created_at = oa.created_at,
    updated_at = oa.updated_at,
    closed_at = oa.closed_at,
    merged_at = oa.merged_at,
    merge_commit_sha = oa.merge_commit_sha,
    merged_by = oa.merged_by and translate_gl_user(oa.merged_by) or nil,
    diff_url = oa.url and (oa.url .. ".diff") or "",
    patch_url = oa.url and (oa.url .. ".patch") or "",
    html_url = oa.url or "",
    url = oa.url or "",
    mergeable = oa.merge_status == "can_be_merged",
    labels = labels_arr,
    assignees = assignees_arr,
    requested_reviewers = reviewers_arr,
  }
end

-- Determine the GitHub pull_request action from a Merge Request Hook payload.
-- GitLab's "update" covers many sub-events; disambiguate using the changes field.
local function gl_mr_action(oa, changes)
  local raw = oa.action or ""
  if raw == "open" then
    return "opened", nil
  elseif raw == "close" then
    return "closed", nil
  elseif raw == "merge" then
    return "closed", nil -- merged is a form of closed
  elseif raw == "reopen" then
    return "reopened", nil
  elseif raw ~= "update" then
    return "unknown", raw
  end
  -- Disambiguate GitLab's "update" action using the changes field (GitLab 10.2+).
  if changes.last_commit then
    return "synchronize", nil
  end
  local lc = changes.labels or {}
  local nprev_l = #(lc.previous or {})
  local ncurr_l = #(lc.current or {})
  if ncurr_l > nprev_l then
    return "labeled", nil
  elseif ncurr_l < nprev_l then
    return "unlabeled", nil
  end
  local ac = changes.assignees or {}
  local nprev_a = #(ac.previous or {})
  local ncurr_a = #(ac.current or {})
  if ncurr_a > nprev_a then
    return "assigned", nil
  elseif ncurr_a < nprev_a then
    return "unassigned", nil
  end
  local rc = changes.reviewers or {}
  local nprev_r = #(rc.previous or {})
  local ncurr_r = #(rc.current or {})
  if ncurr_r > nprev_r then
    return "review_requested", nil
  elseif ncurr_r < nprev_r then
    return "review_request_removed", nil
  end
  return "edited", nil
end

-- Build a normalized issue table from an Issues Hook payload.
-- object_attributes has the issue data; labels and assignees are top-level.
local function webhook_issue_from_gl(payload)
  local oa = payload.object_attributes or {}
  local labels_arr, assignees_arr = {}, {}
  for _, l in ipairs(payload.labels or {}) do
    labels_arr[#labels_arr + 1] = translate_gl_label(l)
  end
  for _, u in ipairs(payload.assignees or {}) do
    assignees_arr[#assignees_arr + 1] = translate_gl_user(u)
  end
  return {
    id = oa.id,
    node_id = "",
    number = oa.iid,
    title = oa.title,
    body = oa.description,
    state = oa.state == "opened" and "open" or (oa.state or "open"),
    -- author_id is available but not the full user object; use payload.user
    -- (the event sender) as a best-effort approximation.
    user = translate_gl_user(payload.user),
    assignees = assignees_arr,
    labels = labels_arr,
    milestone = translate_gl_milestone(payload.milestone),
    comments = oa.user_notes_count or 0,
    created_at = oa.created_at,
    updated_at = oa.updated_at,
    closed_at = oa.closed_at,
    html_url = oa.url or "",
    url = oa.url or "",
    pull_request = nil,
  }
end

-- Action maps: GitLab action string → canonical GitHub action string.
local GL_ISSUES_ACTIONS = {
  open = "opened",
  close = "closed",
  reopen = "reopened",
  update = "edited",
}
local GL_NOTE_ACTIONS = {
  create = "created",
  update = "edited",
  destroy = "deleted",
}
local GL_LABEL_ACTIONS = {
  create = "created",
  update = "edited",
  -- GitLab does not emit a delete event for labels.
}
local GL_MILESTONE_ACTIONS = {
  create = "created",
  update = "edited",
  close = "closed",
  reopen = "opened", -- GitHub calls this "opened" (re-open a closed milestone)
}
local GL_RELEASE_ACTIONS = {
  create = "published",
  update = "edited",
  delete = "deleted",
}

-- translate_gl_webhook_release: normalise a GitLab Release Hook payload into
-- a GitHub-shaped release object.  GitLab places release fields at the top
-- level of the payload (not under object_attributes like most other events).
-- GitLab uses "tag" instead of "tag_name"; url instead of html_url; and
-- "released_at" instead of "published_at".
local function translate_gl_webhook_release(payload)
  return {
    id = payload.id,
    tag_name = payload.tag or "",
    name = payload.name,
    body = payload.description,
    draft = false,
    prerelease = false,
    html_url = payload.url or "",
    tarball_url = nil,
    zipball_url = nil,
    author = nil, -- GitLab Release Hook does not include the triggering user
    created_at = payload.created_at or "",
    published_at = payload.released_at or payload.created_at,
  }
end

-- issues: opened, closed, reopened, edited.
-- Registered for X-Gitlab-Event: Issues Hook
b:webhook("Issues Hook", function(payload)
  local oa = payload.object_attributes or {}
  local raw_action = oa.action or ""
  local action = GL_ISSUES_ACTIONS[raw_action] or "unknown"
  return make_internal_event({
    event = "issues",
    action = action,
    raw_action = action == "unknown" and raw_action or nil,
    provider = config.backend,
    timestamp = oa.updated_at or "",
    raw = payload,
    data = {
      action = action,
      issue = webhook_issue_from_gl(payload),
      repository = translate_gl_webhook_project(payload.project),
      sender = translate_gl_user(payload.user),
    },
  })
end)

-- issue_comment: created, edited, deleted.
-- Registered for X-Gitlab-Event: Note Hook (covers notes on issues and MRs).
-- payload.issue is the parent issue in REST API format when noteable_type is Issue.
b:webhook("Note Hook", function(payload)
  local oa = payload.object_attributes or {}
  local raw_action = oa.action or ""
  local action = GL_NOTE_ACTIONS[raw_action] or "unknown"
  local comment = {
    id = oa.id,
    node_id = "",
    url = oa.url or "",
    html_url = oa.url or "",
    body = oa.note or "",
    user = translate_gl_user(payload.user),
    created_at = oa.created_at,
    updated_at = oa.updated_at,
  }
  return make_internal_event({
    event = "issue_comment",
    action = action,
    raw_action = action == "unknown" and raw_action or nil,
    provider = config.backend,
    timestamp = oa.updated_at or "",
    raw = payload,
    data = {
      action = action,
      issue = payload.issue and translate_gl_issue(payload.issue) or nil,
      comment = comment,
      repository = translate_gl_webhook_project(payload.project),
      sender = translate_gl_user(payload.user),
    },
  })
end)

-- label: created, edited.  GitLab does not emit a delete event for labels.
-- Registered for X-Gitlab-Event: Label Hook
b:webhook("Label Hook", function(payload)
  local oa = payload.object_attributes or {}
  local raw_action = oa.action or ""
  local action = GL_LABEL_ACTIONS[raw_action] or "unknown"
  local label = {
    id = oa.id,
    node_id = "",
    url = "",
    name = oa.title or "",
    color = (oa.color or ""):gsub("^#", ""),
    description = oa.description or "",
    default = false,
  }
  return make_internal_event({
    event = "label",
    action = action,
    raw_action = action == "unknown" and raw_action or nil,
    provider = config.backend,
    timestamp = oa.updated_at or "",
    raw = payload,
    data = {
      action = action,
      label = label,
      changes = {}, -- GitLab does not include changes in label webhook events
      repository = translate_gl_webhook_project(payload.project),
      sender = translate_gl_user(payload.user),
    },
  })
end)

-- milestone: created, closed, opened (reopen), edited.
-- GitLab does not emit a delete event for milestones.
-- Registered for X-Gitlab-Event: Milestone Hook
b:webhook("Milestone Hook", function(payload)
  local oa = payload.object_attributes or {}
  local raw_action = oa.action or ""
  local action = GL_MILESTONE_ACTIONS[raw_action] or "unknown"
  local milestone = {
    id = oa.id,
    node_id = "",
    number = oa.iid or oa.id,
    title = oa.title or "",
    description = oa.description or "",
    state = oa.state == "active" and "open" or "closed",
    html_url = oa.url or "",
    open_issues = 0, -- GitLab omits issue counts from milestone webhook payloads
    closed_issues = 0,
    due_on = oa.due_date,
    created_at = oa.created_at,
    updated_at = oa.updated_at,
    closed_at = oa.closed_at,
    creator = nil, -- GitLab does not include creator in milestone webhook events
  }
  return make_internal_event({
    event = "milestone",
    action = action,
    raw_action = action == "unknown" and raw_action or nil,
    provider = config.backend,
    timestamp = oa.updated_at or "",
    raw = payload,
    data = {
      action = action,
      milestone = milestone,
      repository = translate_gl_webhook_project(payload.project),
      sender = translate_gl_user(payload.user),
    },
  })
end)

-- release: published (create), edited (update), deleted.
-- GitLab places release fields at the top level of the payload; there is no
-- object_attributes wrapper.  GitLab does not include the triggering user.
-- Registered for X-Gitlab-Event: Release Hook
b:webhook("Release Hook", function(payload)
  local raw_action = payload.action or ""
  local action = GL_RELEASE_ACTIONS[raw_action] or "unknown"
  local rel = translate_gl_webhook_release(payload)
  local data = {
    action = action,
    release = rel,
    repository = translate_gl_webhook_project(payload.project),
    sender = nil, -- GitLab Release Hook does not carry a user field
  }
  if action == "edited" then
    data.changes = {}
  end
  return make_internal_event({
    event = "release",
    action = action,
    raw_action = action == "unknown" and raw_action or nil,
    provider = config.backend,
    timestamp = rel.published_at or rel.created_at or "",
    raw = payload,
    data = data,
  })
end)

-- pull_request: opened, closed, reopened, synchronize, edited, labeled,
-- unlabeled, assigned, unassigned, review_requested, review_request_removed.
-- pull_request_review: submitted (APPROVED) for "approved"; dismissed for
-- "unapproved".  Both arrive via X-Gitlab-Event: Merge Request Hook.
-- GitLab uses "merge request" terminology; confusio maps all events to the
-- GitHub pull_request / pull_request_review event families.
b:webhook("Merge Request Hook", function(payload)
  local oa = payload.object_attributes or {}
  local changes = payload.changes or {}
  local raw_gl_action = oa.action or ""

  -- GitLab "approved"/"unapproved" are review verdicts, not PR state changes.
  -- Map them to pull_request_review so consumers don't have to special-case them.
  if raw_gl_action == "approved" or raw_gl_action == "unapproved" then
    local review_action = raw_gl_action == "approved" and "submitted" or "dismissed"
    local review_state = raw_gl_action == "approved" and "APPROVED" or "DISMISSED"
    local review = {
      id = 0,
      node_id = "",
      user = translate_gl_user(payload.user),
      body = "",
      state = review_state,
      submitted_at = oa.updated_at or "",
      html_url = "",
      pull_request_url = "",
    }
    return make_internal_event({
      event = "pull_request_review",
      action = review_action,
      raw_action = nil,
      provider = config.backend,
      timestamp = oa.updated_at or "",
      raw = payload,
      data = {
        action = review_action,
        review = review,
        pull_request = webhook_mr_from_gl(payload),
        repository = translate_gl_webhook_project(payload.project),
        sender = translate_gl_user(payload.user),
      },
    })
  end

  local action, raw_action = gl_mr_action(oa, changes)
  local data = {
    action = action,
    number = oa.iid,
    pull_request = webhook_mr_from_gl(payload),
    repository = translate_gl_webhook_project(payload.project),
    sender = translate_gl_user(payload.user),
  }
  return make_internal_event({
    event = "pull_request",
    action = action,
    raw_action = raw_action,
    provider = config.backend,
    timestamp = oa.updated_at or "",
    raw = payload,
    data = data,
  })
end)

-- Pipeline Hook: maps GitLab pipeline lifecycle events to workflow_run.
-- GitLab uses a status field rather than an action field; the status drives
-- the canonical GitHub action.  Terminal statuses (success/failed/canceled/
-- skipped) become "completed"; running becomes "in_progress"; everything else
-- (created/pending/manual/scheduled/waiting_for_resource/preparing) → "requested".
local GL_PIPELINE_STATUS_TO_ACTION = {
  created = "requested",
  waiting_for_resource = "requested",
  preparing = "in_progress",
  pending = "requested",
  running = "in_progress",
  success = "completed",
  failed = "completed",
  canceled = "completed",
  cancelled = "completed", -- defensive alternate spelling
  skipped = "completed",
  manual = "requested",
  scheduled = "requested",
}
local GL_PIPELINE_CONCLUSION = {
  success = "success",
  failed = "failure",
  canceled = "cancelled",
  cancelled = "cancelled",
  skipped = "skipped",
}

b:webhook("Pipeline Hook", function(payload)
  local oa = payload.object_attributes or {}
  local gl_status = oa.status or ""
  local action = GL_PIPELINE_STATUS_TO_ACTION[gl_status]
  local conclusion = (action == "completed") and (GL_PIPELINE_CONCLUSION[gl_status] or "failure")
    or nil
  -- Map action to GitHub workflow_run.status vocabulary.
  local gh_status = (action == "in_progress") and "in_progress"
    or (action == "completed") and "completed"
    or "queued"
  local pipeline_url = oa.url or ""
  local commit = payload.commit or {}
  local workflow_run = {
    id = oa.id,
    name = "Pipeline",
    head_branch = oa.ref or "",
    head_sha = oa.sha or "",
    run_number = oa.iid or oa.id,
    event = oa.source or "push",
    display_title = commit.title or commit.message or "",
    status = gh_status,
    conclusion = conclusion,
    workflow_id = 0,
    url = pipeline_url,
    html_url = pipeline_url,
    pull_requests = {},
    created_at = oa.created_at or "",
    updated_at = oa.finished_at or oa.updated_at or oa.started_at or "",
    run_attempt = 1,
    referenced_workflows = {},
    actor = translate_gl_user(payload.user),
    triggering_actor = translate_gl_user(payload.user),
  }
  local workflow = {
    id = 0,
    name = "Pipeline",
    path = ".gitlab-ci.yml",
    state = "active",
    url = "",
    html_url = "",
    badge_url = "",
    created_at = "",
    updated_at = "",
  }
  return make_internal_event({
    event = "workflow_run",
    action = action or "unknown",
    raw_action = action and nil or gl_status,
    provider = config.backend,
    raw = payload,
    data = {
      action = action or "unknown",
      workflow_run = workflow_run,
      workflow = workflow,
      repository = translate_gl_webhook_project(payload.project),
      sender = translate_gl_user(payload.user),
    },
    timestamp = oa.finished_at or oa.updated_at or oa.started_at or "",
  })
end)

-- Job Hook: maps GitLab job lifecycle events to workflow_job.
-- Fields are top-level (build_id, build_name, build_status, …) rather than
-- nested under object_attributes.  Repository info is a lightweight object;
-- owner is extracted from project_name ("Group / Project" format).
local GL_JOB_STATUS_TO_ACTION = {
  created = "queued",
  pending = "queued",
  manual = "queued",
  scheduled = "queued",
  waiting_for_resource = "waiting",
  preparing = "in_progress",
  running = "in_progress",
  success = "completed",
  failed = "completed",
  canceled = "completed",
  cancelled = "completed", -- defensive alternate spelling
  skipped = "completed",
}
local GL_JOB_CONCLUSION = {
  success = "success",
  failed = "failure",
  canceled = "cancelled",
  cancelled = "cancelled",
  skipped = "skipped",
}

b:webhook("Job Hook", function(payload)
  local raw_status = payload.build_status or ""
  local action = GL_JOB_STATUS_TO_ACTION[raw_status]
  local conclusion = (action == "completed") and (GL_JOB_CONCLUSION[raw_status] or "failure") or nil
  local gh_status = (action == "in_progress") and "in_progress"
    or (action == "waiting") and "waiting"
    or (action == "completed") and "completed"
    or "queued"
  local runner = payload.runner or {}
  -- Build a repository object from the limited fields available in Job Hook.
  -- project_name is "Group / Project"; split to extract owner_login.
  local repo_info = payload.repository or {}
  local repo_name = repo_info.name or ""
  local repo_homepage = repo_info.homepage or ""
  local pname = payload.project_name or ""
  local sep = pname:find(" / ", 1, true)
  local owner_login = sep and pname:sub(1, sep - 1):gsub("%s+$", "") or ""
  local full_name = owner_login ~= "" and (owner_login .. "/" .. repo_name) or repo_name
  local repository = {
    id = payload.project_id,
    node_id = "",
    name = repo_name,
    full_name = full_name,
    private = false, -- not available in Job Hook
    owner = {
      login = owner_login,
      id = 0,
      node_id = "",
      avatar_url = "",
      url = "",
      html_url = "",
      type = "User",
    },
    html_url = repo_homepage,
    description = repo_info.description or "",
    fork = false,
    url = repo_homepage,
    default_branch = "",
  }
  local workflow_job = {
    id = payload.build_id,
    run_id = payload.pipeline_id,
    run_url = "",
    run_attempt = 1,
    name = payload.build_name or "",
    head_sha = payload.sha or "",
    url = "",
    html_url = "",
    status = gh_status,
    conclusion = conclusion,
    started_at = payload.build_started_at,
    completed_at = payload.build_finished_at,
    steps = {},
    labels = runner.tags or {},
    runner_id = runner.id,
    runner_name = runner.description or "",
  }
  return make_internal_event({
    event = "workflow_job",
    action = action or "unknown",
    raw_action = action and nil or raw_status,
    provider = config.backend,
    raw = payload,
    data = {
      action = action or "unknown",
      workflow_job = workflow_job,
      repository = repository,
      sender = translate_gl_user(payload.user),
    },
    timestamp = payload.build_finished_at or payload.build_started_at or "",
  })
end)

-- Zero SHA — GitLab uses this for the `before` field when a ref is created,
-- and for the `after` field when a ref is deleted.
local GL_ZERO_SHA = "0000000000000000000000000000000000000000"

-- Translate a push-event commit object (different from the REST API commit
-- shape: no committer field; author is {name, email}).
local function translate_gl_push_commit(c)
  if not c then
    return {}
  end
  local author = c.author or {}
  return {
    id = c.id or "",
    message = c.message or "",
    timestamp = c.timestamp or "",
    url = c.url or "",
    author = {
      name = author.name or "",
      email = author.email or "",
      username = "",
    },
    committer = {
      name = author.name or "",
      email = author.email or "",
      username = "",
    },
    added = c.added or {},
    removed = c.removed or {},
    modified = c.modified or {},
  }
end

-- Build a GitHub-style sender table from the top-level push payload user
-- fields.  Push Hook payloads do not have a nested `user` object — user info
-- sits directly at the root as user_id / user_username / user_name /
-- user_avatar.
local function gl_push_sender(payload)
  return {
    login = payload.user_username or "",
    id = payload.user_id or 0,
    node_id = "",
    avatar_url = payload.user_avatar or "",
    html_url = "",
    type = "User",
    site_admin = false,
  }
end

-- Push Hook: branch push — also handles branch creation (before = zero SHA)
-- and branch deletion (after = zero SHA) by routing them to the appropriate
-- GitHub event type.  GitLab has no separate create/delete webhook event for
-- branches; all three operations arrive via Push Hook.
b:webhook("Push Hook", function(payload)
  local before = payload.before or ""
  local after = payload.after or ""
  local project = payload.project or {}
  local sender = gl_push_sender(payload)
  local repository = translate_gl_webhook_project(project)

  if before == GL_ZERO_SHA then
    -- Branch created — emit GitHub create event.
    local raw_ref = payload.ref or ""
    local ref = raw_ref:match("^refs/heads/(.+)$") or raw_ref
    return make_internal_event({
      event = "create",
      action = "create",
      provider = config.backend,
      raw = payload,
      data = {
        ref = ref,
        ref_type = "branch",
        master_branch = project.default_branch or "",
        description = project.description,
        pusher_type = "user",
        repository = repository,
        sender = sender,
      },
      timestamp = "",
    })
  end

  if after == GL_ZERO_SHA then
    -- Branch deleted — emit GitHub delete event.
    local raw_ref = payload.ref or ""
    local ref = raw_ref:match("^refs/heads/(.+)$") or raw_ref
    return make_internal_event({
      event = "delete",
      action = "delete",
      provider = config.backend,
      raw = payload,
      data = {
        ref = ref,
        ref_type = "branch",
        master_branch = project.default_branch or "",
        description = project.description,
        pusher_type = "user",
        repository = repository,
        sender = sender,
      },
      timestamp = "",
    })
  end

  -- Regular branch push — emit GitHub push event.
  local push_commits = {}
  for _, c in ipairs(payload.commits or {}) do
    push_commits[#push_commits + 1] = translate_gl_push_commit(c)
  end
  local head_commit = #push_commits > 0 and push_commits[#push_commits] or nil
  local web_url = project.web_url or project.homepage or ""
  local compare = (before ~= "" and after ~= "")
      and (web_url .. "/compare/" .. before .. "..." .. after)
    or ""
  return make_internal_event({
    event = "push",
    action = "push",
    provider = config.backend,
    raw = payload,
    data = {
      ref = payload.ref or "",
      before = before,
      after = after,
      created = false,
      deleted = false,
      forced = false,
      compare = compare,
      commits = push_commits,
      head_commit = head_commit,
      pusher = {
        name = payload.user_name or "",
        email = payload.user_email or "",
      },
      repository = repository,
      sender = sender,
    },
    timestamp = head_commit and head_commit.timestamp or "",
  })
end)

-- Tag Push Hook: tag push — same routing logic as Push Hook (creation,
-- deletion, and regular push) but for tag refs.  GitLab fires this event
-- type exclusively for tag operations.
b:webhook("Tag Push Hook", function(payload)
  local before = payload.before or ""
  local after = payload.after or ""
  local project = payload.project or {}
  local sender = gl_push_sender(payload)
  local repository = translate_gl_webhook_project(project)

  if before == GL_ZERO_SHA then
    -- Tag created — emit GitHub create event.
    local raw_ref = payload.ref or ""
    local ref = raw_ref:match("^refs/tags/(.+)$") or raw_ref
    return make_internal_event({
      event = "create",
      action = "create",
      provider = config.backend,
      raw = payload,
      data = {
        ref = ref,
        ref_type = "tag",
        master_branch = project.default_branch or "",
        description = project.description,
        pusher_type = "user",
        repository = repository,
        sender = sender,
      },
      timestamp = "",
    })
  end

  if after == GL_ZERO_SHA then
    -- Tag deleted — emit GitHub delete event.
    local raw_ref = payload.ref or ""
    local ref = raw_ref:match("^refs/tags/(.+)$") or raw_ref
    return make_internal_event({
      event = "delete",
      action = "delete",
      provider = config.backend,
      raw = payload,
      data = {
        ref = ref,
        ref_type = "tag",
        master_branch = project.default_branch or "",
        description = project.description,
        pusher_type = "user",
        repository = repository,
        sender = sender,
      },
      timestamp = "",
    })
  end

  -- Regular tag push — emit GitHub push event.
  local push_commits = {}
  for _, c in ipairs(payload.commits or {}) do
    push_commits[#push_commits + 1] = translate_gl_push_commit(c)
  end
  local head_commit = #push_commits > 0 and push_commits[#push_commits] or nil
  local web_url = project.web_url or project.homepage or ""
  local compare = (before ~= "" and after ~= "")
      and (web_url .. "/compare/" .. before .. "..." .. after)
    or ""
  return make_internal_event({
    event = "push",
    action = "push",
    provider = config.backend,
    raw = payload,
    data = {
      ref = payload.ref or "",
      before = before,
      after = after,
      created = false,
      deleted = false,
      forced = false,
      compare = compare,
      commits = push_commits,
      head_commit = head_commit,
      pusher = {
        name = payload.user_name or "",
        email = payload.user_email or "",
      },
      repository = repository,
      sender = sender,
    },
    timestamp = head_commit and head_commit.timestamp or "",
  })
end)

-- GL_DEPLOYMENT_STATE: map GitLab deployment status to GitHub deployment_status state.
local GL_DEPLOYMENT_STATE = {
  running = "in_progress",
  success = "success",
  failed = "failure",
  canceled = "inactive",
  cancelled = "inactive", -- defensive alternate spelling
  blocked = "waiting",
}

-- translate_gl_webhook_deployment: build a GitHub-shaped deployment object from a
-- GitLab Deployment Hook payload.  Used in both deployment and deployment_status events.
local function translate_gl_webhook_deployment(payload)
  return {
    id = payload.deployment_id or 0,
    node_id = "",
    sha = payload.short_sha or "",
    ref = payload.ref or "",
    task = "deploy",
    environment = payload.environment or "",
    original_environment = "",
    description = nil,
    payload = {},
    creator = translate_gl_user(payload.user),
    created_at = payload.status_changed_at or "",
    updated_at = payload.status_changed_at or "",
    statuses_url = "",
    repository_url = "",
    production_environment = false,
    transient_environment = false,
  }
end

-- Deployment Hook: maps GitLab deployment lifecycle events to GitHub deployment
-- and deployment_status events.  GitLab fires one event per status transition.
--
-- Mapping:
--   running                           → deployment (created) — deployment initiated
--   success / failed / canceled / blocked → deployment_status (created) — status update
b:webhook("Deployment Hook", function(payload)
  local gl_status = payload.status or ""
  local project = payload.project or {}
  local repository = translate_gl_webhook_project(project)
  local sender = translate_gl_user(payload.user)
  local deployment = translate_gl_webhook_deployment(payload)
  local timestamp = payload.status_changed_at or ""

  if gl_status == "running" then
    -- Emit GitHub deployment (created) event for the initial deployment trigger.
    return make_internal_event({
      event = "deployment",
      action = "created",
      provider = config.backend,
      raw = payload,
      data = {
        action = "created",
        deployment = deployment,
        repository = repository,
        sender = sender,
      },
      timestamp = timestamp,
    })
  end

  -- All other status transitions map to deployment_status (created).
  local state = GL_DEPLOYMENT_STATE[gl_status] or "error"
  local deployment_status = {
    id = 0,
    node_id = "",
    state = state,
    description = "",
    environment = payload.environment or "",
    environment_url = "",
    log_url = payload.deployable_url or "",
    target_url = "",
    deployment_url = "",
    creator = sender,
    created_at = timestamp,
    updated_at = timestamp,
  }
  return make_internal_event({
    event = "deployment_status",
    action = "created",
    provider = config.backend,
    raw = payload,
    data = {
      action = "created",
      deployment_status = deployment_status,
      deployment = deployment,
      repository = repository,
      sender = sender,
    },
    timestamp = timestamp,
  })
end)

b:capability("repos", repos)
b:capability("users", users)
b:capability("orgs", orgs)
b:capability("branches", branches)
b:capability("commits", commits)
b:capability("statuses", statuses_cap)
b:capability("issues", issues_cap)
b:capability("labels", labels_cap)
b:capability("milestones", milestones_cap)
b:capability("reactions", reactions_cap)
b:capability("contents", contents_cap)
b:capability("commit_comments", commit_comments_cap)
b:capability("collaborators", collaborators_cap)
b:capability("forks", forks_cap)
b:capability("pulls", pulls_cap)
b:capability("releases", releases_cap)
b:capability("deploy_keys", deploy_keys_cap)
b:capability("webhooks", webhooks_cap)
b:capability("teams", teams_cap)
b:capability("search", search_cap)
b:capability("gitignore", gitignore_cap)
b:capability("licenses", licenses_cap)
b:capability("markdown", markdown_cap)
b:capability("git_db", git_db_cap)
b:capability("packages", packages_cap)
b:capability("security", security_cap)
b:capability("gists", gists_cap)
b:build()
