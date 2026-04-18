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

local function translate_gl_projects(projects)
  return translate_list(translate_gl_repo, projects)
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

-- Proxy a GitLab search response (plain JSON array) to the GitHub search
-- envelope {"total_count":N,"incomplete_results":false,"items":[...]}.
-- translate_item is applied to each element of the array.
local function proxy_search_gl(translate_item, url)
  local ok, status, headers, body = fetch_json(url)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local raw = DecodeJson(body) or {}
  local items = {}
  for i, item in ipairs(raw) do
    items[i] = translate_item(item)
  end
  local link = headers and (headers["Link"] or headers["link"])
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

b:rest(
  "get_repo_keys",
  proxy_handler_paged(nil, function(owner, repo_name)
    return append_page_params(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/deploy_keys",
      PAGES
    )
  end)
)

b:rest("post_repo_keys", function(owner, repo_name)
  local req = DecodeJson(GetBody() or "{}")
  local body = EncodeJson({
    title = req.title,
    key = req.key,
    can_push = req.read_only == false,
  })
  proxy_json_created(
    nil,
    fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/deploy_keys",
      "POST",
      body
    )
  )
end)

b:rest(
  "get_repo_key",
  proxy_handler(nil, function(owner, repo_name, key_id)
    return base() .. "/projects/" .. project_id(owner, repo_name) .. "/deploy_keys/" .. key_id
  end)
)

b:rest("delete_repo_key", function(owner, repo_name, key_id)
  local ok, status = fetch_json(
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/deploy_keys/" .. key_id,
    "DELETE"
  )
  proxy_204({ 200 }, ok, status)
end)

-- Webhooks ------------------------------------------------------------------

b:rest(
  "get_repo_hooks",
  proxy_handler_paged(nil, function(owner, repo_name)
    return append_page_params(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/hooks",
      PAGES
    )
  end)
)

b:rest("post_repo_hooks", function(owner, repo_name)
  proxy_json_created(
    nil,
    fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/hooks",
      "POST",
      GetBody()
    )
  )
end)

b:rest(
  "get_repo_hook",
  proxy_handler(nil, function(owner, repo_name, hook_id)
    return base() .. "/projects/" .. project_id(owner, repo_name) .. "/hooks/" .. hook_id
  end)
)

-- GitLab uses PUT for hook updates
b:rest("patch_repo_hook", function(owner, repo_name, hook_id)
  proxy_json(
    nil,
    fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/hooks/" .. hook_id,
      "PUT",
      GetBody()
    )
  )
end)

b:rest("delete_repo_hook", function(owner, repo_name, hook_id)
  local ok, status = fetch_json(
    base() .. "/projects/" .. project_id(owner, repo_name) .. "/hooks/" .. hook_id,
    "DELETE"
  )
  proxy_204({ 200 }, ok, status)
end)

b:rest(
  "get_repo_hook_config",
  proxy_handler(function(h)
    return { url = h.url }
  end, function(owner, repo_name, hook_id)
    return base() .. "/projects/" .. project_id(owner, repo_name) .. "/hooks/" .. hook_id
  end)
)

b:rest("patch_repo_hook_config", function(owner, repo_name, hook_id)
  local new_cfg = DecodeJson(GetBody() or "{}")
  local url = base() .. "/projects/" .. project_id(owner, repo_name) .. "/hooks/" .. hook_id
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
  if new_cfg.url then
    hook.url = new_cfg.url
  end
  proxy_json(function(h)
    return { url = h.url }
  end, fetch_json(url, "PUT", EncodeJson(hook)))
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

-- Teams — mapped to GitLab subgroups ----------------------------------------
-- GitHub: /orgs/{org}/teams/{team_slug}  →  GitLab: /groups/{org}%2F{slug}
-- GitLab group members have access levels; repos are the group's projects.

-- GET /orgs/{org}/teams
b:rest("get_org_teams", function(org)
  proxy_json_paged(function(groups)
    for i, g in ipairs(groups) do
      groups[i] = translate_gl_team(g)
    end
    return groups
  end, PAGES, fetch_json(append_page_params(base() .. "/groups/" .. org .. "/subgroups", PAGES)))
end)

-- POST /orgs/{org}/teams
b:rest("post_org_teams", function(org)
  local req = DecodeJson(GetBody() or "{}")
  local parent_ok, parent_status, _, parent_body = fetch_json(base() .. "/groups/" .. org)
  if not parent_ok or parent_status ~= 200 then
    respond_json(parent_ok and parent_status or 503, {})
    return
  end
  local parent = DecodeJson(parent_body) or {}
  local body = {
    name = req.name,
    path = (req.name or ""):lower():gsub("[^%w%-]", "-"),
    parent_id = parent.id,
    description = req.description,
    visibility = req.privacy == "secret" and "private" or "internal",
  }
  proxy_json_created(translate_gl_team, fetch_json(base() .. "/groups", "POST", EncodeJson(body)))
end)

-- GET /orgs/{org}/teams/{team_slug}
b:rest("get_org_team", function(org, slug)
  proxy_json(translate_gl_team, fetch_json(base() .. "/groups/" .. org .. "%2F" .. slug))
end)

-- PATCH /orgs/{org}/teams/{team_slug}
b:rest("patch_org_team", function(org, slug)
  local ok, status, _, body = fetch_json(base() .. "/groups/" .. org .. "%2F" .. slug)
  if not ok or status ~= 200 then
    respond_json(ok and status or 503, {})
    return
  end
  local gid = (DecodeJson(body) or {}).id
  local req = DecodeJson(GetBody() or "{}")
  local upd = {}
  if req.name then
    upd.name = req.name
  end
  if req.description then
    upd.description = req.description
  end
  proxy_json(translate_gl_team, fetch_json(base() .. "/groups/" .. gid, "PUT", EncodeJson(upd)))
end)

-- DELETE /orgs/{org}/teams/{team_slug}
b:rest("delete_org_team", function(org, slug)
  local ok, status, _, body = fetch_json(base() .. "/groups/" .. org .. "%2F" .. slug)
  if not ok or status ~= 200 then
    respond_json(ok and status or 503, {})
    return
  end
  local gid = (DecodeJson(body) or {}).id
  local dopts = auth() or {}
  dopts.method = "DELETE"
  proxy_204({ 202 }, pcall(Fetch, base() .. "/groups/" .. gid, dopts))
end)

-- GET /orgs/{org}/teams/{team_slug}/members
b:rest("get_org_team_members", function(org, slug)
  local ok, status, _, body = fetch_json(base() .. "/groups/" .. org .. "%2F" .. slug)
  if not ok or status ~= 200 then
    respond_json(ok and status or 503, {})
    return
  end
  local gid = (DecodeJson(body) or {}).id
  proxy_json_paged(function(members)
    local out = {}
    for _, m in ipairs(members) do
      out[#out + 1] = translate_gl_member(m)
    end
    return out
  end, PAGES, fetch_json(append_page_params(base() .. "/groups/" .. gid .. "/members", PAGES)))
end)

-- GET /orgs/{org}/teams/{team_slug}/memberships/{username}
b:rest("get_org_team_membership", function(org, slug, username)
  local ok, status, _, body = fetch_json(base() .. "/groups/" .. org .. "%2F" .. slug)
  if not ok or status ~= 200 then
    respond_json(ok and status or 503, {})
    return
  end
  local gid = (DecodeJson(body) or {}).id
  local uid = gl_user_id(username)
  if not uid then
    respond_json(404, { message = "Not Found" })
    return
  end
  local mok, mstatus, _, mbody = fetch_json(base() .. "/groups/" .. gid .. "/members/" .. uid)
  if mok and mstatus == 200 then
    local m = DecodeJson(mbody) or {}
    local role = (m.access_level or 0) >= 50 and "maintainer" or "member"
    respond_json(200, { url = "", role = role, state = "active" })
  elseif mok then
    respond_json(404, { message = "Not Found" })
  else
    respond_json(503, {})
  end
end)

-- PUT /orgs/{org}/teams/{team_slug}/memberships/{username}
b:rest("put_org_team_membership", function(org, slug, username)
  local ok, status, _, body = fetch_json(base() .. "/groups/" .. org .. "%2F" .. slug)
  if not ok or status ~= 200 then
    respond_json(ok and status or 503, {})
    return
  end
  local gid = (DecodeJson(body) or {}).id
  local uid = gl_user_id(username)
  if not uid then
    respond_json(404, { message = "Not Found" })
    return
  end
  local req = DecodeJson(GetBody() or "{}")
  local level = req.role == "maintainer" and 50 or 30
  local mok, mstatus = fetch_json(
    base() .. "/groups/" .. gid .. "/members",
    "POST",
    EncodeJson({ user_id = uid, access_level = level })
  )
  if mok and (mstatus == 200 or mstatus == 201) then
    respond_json(200, { url = "", role = req.role or "member", state = "active" })
  elseif mok then
    respond_json(mstatus, {})
  else
    respond_json(503, {})
  end
end)

-- DELETE /orgs/{org}/teams/{team_slug}/memberships/{username}
b:rest("delete_org_team_membership", function(org, slug, username)
  local ok, status, _, body = fetch_json(base() .. "/groups/" .. org .. "%2F" .. slug)
  if not ok or status ~= 200 then
    respond_json(ok and status or 503, {})
    return
  end
  local gid = (DecodeJson(body) or {}).id
  local uid = gl_user_id(username)
  if not uid then
    respond_json(404, { message = "Not Found" })
    return
  end
  local dopts = auth() or {}
  dopts.method = "DELETE"
  proxy_204({ 200 }, pcall(Fetch, base() .. "/groups/" .. gid .. "/members/" .. uid, dopts))
end)

-- GET /orgs/{org}/teams/{team_slug}/repos
b:rest("get_org_team_repos", function(org, slug)
  local ok, status, _, body = fetch_json(base() .. "/groups/" .. org .. "%2F" .. slug)
  if not ok or status ~= 200 then
    respond_json(ok and status or 503, {})
    return
  end
  local gid = (DecodeJson(body) or {}).id
  proxy_json_paged(
    translate_gl_projects,
    PAGES,
    fetch_json(append_page_params(base() .. "/groups/" .. gid .. "/projects", PAGES))
  )
end)

-- GET /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}
b:rest("get_org_team_repo", function(org, slug, owner, repo_name)
  local ok, status, _, body = fetch_json(base() .. "/groups/" .. org .. "%2F" .. slug)
  if not ok or status ~= 200 then
    respond_json(ok and status or 503, {})
    return
  end
  local gid = (DecodeJson(body) or {}).id
  local pid = project_id(owner, repo_name)
  -- Check if the project belongs to this subgroup
  local pok, pstatus, _, pbody = fetch_json(base() .. "/projects/" .. pid)
  if not pok or pstatus ~= 200 then
    respond_json(404, { message = "Not Found" })
    return
  end
  local proj = DecodeJson(pbody) or {}
  local ns = proj.namespace or {}
  if tostring(ns.id) ~= tostring(gid) then
    respond_json(404, { message = "Not Found" })
    return
  end
  respond_json(200, translate_gl_repo(proj))
end)

-- PUT /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}
b:rest("put_org_team_repo", function(org, slug, owner, repo_name)
  local ok, status, _, body = fetch_json(base() .. "/groups/" .. org .. "%2F" .. slug)
  if not ok or status ~= 200 then
    respond_json(ok and status or 503, {})
    return
  end
  local gid = (DecodeJson(body) or {}).id
  local pid = project_id(owner, repo_name)
  local req = DecodeJson(GetBody() or "{}")
  local access = req.permission == "admin" and 50 or (req.permission == "push" and 30 or 20)
  local pok, pstatus = fetch_json(
    base() .. "/projects/" .. pid .. "/share",
    "POST",
    EncodeJson({ group_id = gid, group_access = access })
  )
  proxy_204({ 200, 201 }, pok, pstatus)
end)

-- DELETE /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}
b:rest("delete_org_team_repo", function(org, slug, owner, repo_name)
  local ok, status, _, body = fetch_json(base() .. "/groups/" .. org .. "%2F" .. slug)
  if not ok or status ~= 200 then
    respond_json(ok and status or 503, {})
    return
  end
  local gid = (DecodeJson(body) or {}).id
  local pid = project_id(owner, repo_name)
  local dopts = auth() or {}
  dopts.method = "DELETE"
  proxy_204({ 200 }, pcall(Fetch, base() .. "/projects/" .. pid .. "/share/" .. gid, dopts))
end)

-- GET /orgs/{org}/teams/{team_slug}/teams — list sub-subgroups
b:rest("get_org_team_children", function(org, slug)
  local ok, status, _, body = fetch_json(base() .. "/groups/" .. org .. "%2F" .. slug)
  if not ok or status ~= 200 then
    respond_json(ok and status or 503, {})
    return
  end
  local gid = (DecodeJson(body) or {}).id
  proxy_json_paged(function(groups)
    for i, g in ipairs(groups) do
      groups[i] = translate_gl_team(g)
    end
    return groups
  end, PAGES, fetch_json(append_page_params(base() .. "/groups/" .. gid .. "/subgroups", PAGES)))
end)

-- Legacy team-by-id API (/teams/{team_id}) ------------------------------------
-- team_id maps to GitLab group numeric ID.

-- GET /user/teams — all groups the authenticated user belongs to
b:rest("get_user_teams", function()
  proxy_json_paged(function(groups)
    for i, g in ipairs(groups) do
      groups[i] = translate_gl_team(g)
    end
    return groups
  end, PAGES, fetch_json(append_page_params(base() .. "/groups?min_access_level=10", PAGES)))
end)

-- GET /teams/{team_id}
b:rest("get_team", function(team_id)
  proxy_json(translate_gl_team, fetch_json(base() .. "/groups/" .. team_id))
end)

-- PATCH /teams/{team_id}
b:rest("patch_team", function(team_id)
  local req = DecodeJson(GetBody() or "{}")
  local upd = {}
  if req.name then
    upd.name = req.name
  end
  if req.description then
    upd.description = req.description
  end
  proxy_json(translate_gl_team, fetch_json(base() .. "/groups/" .. team_id, "PUT", EncodeJson(upd)))
end)

-- DELETE /teams/{team_id}
b:rest("delete_team", function(team_id)
  local dopts = auth() or {}
  dopts.method = "DELETE"
  proxy_204({ 202 }, pcall(Fetch, base() .. "/groups/" .. team_id, dopts))
end)

-- GET /teams/{team_id}/members
b:rest("get_team_members", function(team_id)
  proxy_json_paged(function(members)
    local out = {}
    for _, m in ipairs(members) do
      out[#out + 1] = translate_gl_member(m)
    end
    return out
  end, PAGES, fetch_json(append_page_params(base() .. "/groups/" .. team_id .. "/members", PAGES)))
end)

-- GET /teams/{team_id}/members/{username} — deprecated legacy, 204 if member
b:rest("get_team_member", function(team_id, username)
  local uid = gl_user_id(username)
  if not uid then
    respond_json(404, { message = "Not Found" })
    return
  end
  local ok, status = pcall(Fetch, base() .. "/groups/" .. team_id .. "/members/" .. uid, auth())
  if ok and status == 200 then
    SetStatus(204, "No Content")
  elseif ok then
    respond_json(404, { message = "Not Found" })
  else
    respond_json(503, {})
  end
end)

-- PUT /teams/{team_id}/members/{username} — deprecated legacy
b:rest("put_team_member", function(team_id, username)
  local uid = gl_user_id(username)
  if not uid then
    respond_json(404, { message = "Not Found" })
    return
  end
  local ok, status = fetch_json(
    base() .. "/groups/" .. team_id .. "/members",
    "POST",
    EncodeJson({ user_id = uid, access_level = 30 })
  )
  proxy_204({ 200, 201 }, ok, status)
end)

-- DELETE /teams/{team_id}/members/{username} — deprecated legacy
b:rest("delete_team_member", function(team_id, username)
  local uid = gl_user_id(username)
  if not uid then
    respond_json(404, { message = "Not Found" })
    return
  end
  local dopts = auth() or {}
  dopts.method = "DELETE"
  proxy_204({ 200 }, pcall(Fetch, base() .. "/groups/" .. team_id .. "/members/" .. uid, dopts))
end)

-- GET /teams/{team_id}/memberships/{username}
b:rest("get_team_membership", function(team_id, username)
  local uid = gl_user_id(username)
  if not uid then
    respond_json(404, { message = "Not Found" })
    return
  end
  local ok, status, _, body = fetch_json(base() .. "/groups/" .. team_id .. "/members/" .. uid)
  if ok and status == 200 then
    local m = DecodeJson(body) or {}
    local role = (m.access_level or 0) >= 50 and "maintainer" or "member"
    respond_json(200, { url = "", role = role, state = "active" })
  elseif ok then
    respond_json(404, { message = "Not Found" })
  else
    respond_json(503, {})
  end
end)

-- PUT /teams/{team_id}/memberships/{username}
b:rest("put_team_membership", function(team_id, username)
  local uid = gl_user_id(username)
  if not uid then
    respond_json(404, { message = "Not Found" })
    return
  end
  local req = DecodeJson(GetBody() or "{}")
  local level = req.role == "maintainer" and 50 or 30
  local ok, status = fetch_json(
    base() .. "/groups/" .. team_id .. "/members",
    "POST",
    EncodeJson({ user_id = uid, access_level = level })
  )
  if ok and (status == 200 or status == 201) then
    respond_json(200, { url = "", role = req.role or "member", state = "active" })
  elseif ok then
    respond_json(status, {})
  else
    respond_json(503, {})
  end
end)

-- DELETE /teams/{team_id}/memberships/{username}
b:rest("delete_team_membership", function(team_id, username)
  local uid = gl_user_id(username)
  if not uid then
    respond_json(404, { message = "Not Found" })
    return
  end
  local dopts = auth() or {}
  dopts.method = "DELETE"
  proxy_204({ 200 }, pcall(Fetch, base() .. "/groups/" .. team_id .. "/members/" .. uid, dopts))
end)

-- GET /teams/{team_id}/repos
b:rest("get_team_repos", function(team_id)
  proxy_json_paged(
    translate_gl_projects,
    PAGES,
    fetch_json(append_page_params(base() .. "/groups/" .. team_id .. "/projects", PAGES))
  )
end)

-- GET /teams/{team_id}/repos/{owner}/{repo}
b:rest("get_team_repo", function(team_id, owner, repo_name)
  local pid = project_id(owner, repo_name)
  local ok, status, _, body = fetch_json(base() .. "/projects/" .. pid)
  if not ok or status ~= 200 then
    respond_json(404, { message = "Not Found" })
    return
  end
  local proj = DecodeJson(body) or {}
  local ns = proj.namespace or {}
  if tostring(ns.id) ~= tostring(team_id) then
    respond_json(404, { message = "Not Found" })
    return
  end
  respond_json(200, translate_gl_repo(proj))
end)

-- PUT /teams/{team_id}/repos/{owner}/{repo}
b:rest("put_team_repo", function(team_id, owner, repo_name)
  local pid = project_id(owner, repo_name)
  local req = DecodeJson(GetBody() or "{}")
  local access = req.permission == "admin" and 50 or (req.permission == "push" and 30 or 20)
  local ok, status = fetch_json(
    base() .. "/projects/" .. pid .. "/share",
    "POST",
    EncodeJson({ group_id = team_id, group_access = access })
  )
  proxy_204({ 200, 201 }, ok, status)
end)

-- DELETE /teams/{team_id}/repos/{owner}/{repo}
b:rest("delete_team_repo", function(team_id, owner, repo_name)
  local pid = project_id(owner, repo_name)
  local dopts = auth() or {}
  dopts.method = "DELETE"
  proxy_204({ 200 }, pcall(Fetch, base() .. "/projects/" .. pid .. "/share/" .. team_id, dopts))
end)

-- GET /teams/{team_id}/teams — sub-subgroups
b:rest("get_team_children", function(team_id)
  proxy_json_paged(
    function(groups)
      for i, g in ipairs(groups) do
        groups[i] = translate_gl_team(g)
      end
      return groups
    end,
    PAGES,
    fetch_json(append_page_params(base() .. "/groups/" .. team_id .. "/subgroups", PAGES))
  )
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

-- Search -----------------------------------------------------------------------

-- GET /search/repositories — maps to GitLab GET /projects?search=<q>
b:rest("search_repositories", function()
  local q = GetParam("q") or ""
  proxy_search_gl(translate_gl_repo, append_page_params(base() .. "/projects?search=" .. q, PAGES))
end)

-- GET /search/users — maps to GitLab GET /users?search=<q>
b:rest("search_users", function()
  local q = GetParam("q") or ""
  proxy_search_gl(translate_gl_user, append_page_params(base() .. "/users?search=" .. q, PAGES))
end)

-- Gitignore -----------------------------------------------------------------

-- GET /gitignore/templates → GitLab GET /api/v4/templates/gitignores
-- GitLab returns [{key,name}, ...]; GitHub returns ["Name", ...]
b:rest("get_gitignore_templates", function()
  proxy_json(function(list)
    local names = {}
    for i, t in ipairs(list or {}) do
      names[i] = t.name
    end
    return names
  end, fetch_json(base() .. "/templates/gitignores"))
end)

-- GET /gitignore/templates/{name} → GitLab GET /api/v4/templates/gitignores/{name}
-- GitLab returns {name, content}; GitHub returns {name, source}
b:rest("get_gitignore_template", function(name)
  proxy_json(function(t)
    if not t then
      return {}
    end
    return { name = t.name, source = t.content }
  end, fetch_json(base() .. "/templates/gitignores/" .. name))
end)

-- Licenses -----------------------------------------------------------------

-- GET /licenses → GitLab GET /api/v4/templates/licenses
-- GitLab returns [{key,name,...}]; GitHub returns [{key,name,...}] (license-simple)
b:rest("get_licenses", function()
  proxy_json(function(list)
    local result = {}
    for i, t in ipairs(list or {}) do
      result[i] = { key = t.key, name = t.name }
    end
    return result
  end, fetch_json(base() .. "/templates/licenses"))
end)

-- GET /licenses/{license} → GitLab GET /api/v4/templates/licenses/{key}
-- GitLab returns {key,name,content,description,conditions,permissions,limitations,html_url}
-- GitHub returns {key,name,body,description,conditions,permissions,limitations,html_url,...}
b:rest("get_license", function(license_name)
  proxy_json(function(t)
    if not t then
      return {}
    end
    return {
      key = t.key,
      name = t.name,
      html_url = t.html_url,
      description = t.description,
      body = t.content,
      permissions = t.permissions or {},
      conditions = t.conditions or {},
      limitations = t.limitations or {},
    }
  end, fetch_json(base() .. "/templates/licenses/" .. license_name))
end)

-- GET /repos/{owner}/{repo}/license
-- Combines /repository/files/LICENSE content with project license metadata.
b:rest("get_repo_license", function(owner, repo_name)
  local pid = project_id(owner, repo_name)
  local ok, status, _, body =
    fetch_json(base() .. "/projects/" .. pid .. "/repository/files/LICENSE?ref=HEAD")
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local f = DecodeJson(body) or {}
  local rok, rstatus, _, rbody = fetch_json(base() .. "/projects/" .. pid)
  local license_meta = nil
  if rok and rstatus == 200 then
    local lic = (DecodeJson(rbody) or {}).license
    if lic then
      license_meta = { key = lic.key, name = lic.name }
    end
  end
  respond_json(200, {
    name = f.file_name,
    path = f.file_path,
    sha = f.blob_id,
    size = f.size,
    type = "file",
    content = f.content,
    encoding = f.encoding,
    license = license_meta,
  })
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

-- Packages (org via GitLab group packages API) --------------------------------

b:rest("get_org_packages", function(org)
  local pkg_type = GetParam("package_type") or ""
  local url = base() .. "/groups/" .. org .. "/packages"
  if pkg_type ~= "" then
    url = url .. "?package_type=" .. pkg_type
  end
  url = append_page_params(url, PAGES)
  proxy_json_paged(function(entries)
    local pkgs = {}
    for i, p in ipairs(entries) do
      pkgs[i] = {
        id = p.id,
        name = p.name or "",
        package_type = p.package_type or "",
        url = "",
        html_url = p._links and p._links.web_path or "",
        version_count = 1,
        visibility = "public",
        owner = nil,
        repository = nil,
        created_at = p.created_at,
        updated_at = p.created_at,
      }
    end
    return pkgs
  end, PAGES, fetch_json(url))
end)

b:rest("get_org_package", function(org, pkg_type, pkg_name)
  local url = base()
    .. "/groups/"
    .. org
    .. "/packages?package_type="
    .. pkg_type
    .. "&package_name="
    .. pkg_name
    .. "&per_page=100"
  local ok, status, _, body = fetch_json(url)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local entries = DecodeJson(body) or {}
  if #entries == 0 then
    respond_json(404, { message = "Not Found" })
    return
  end
  local p = entries[1]
  respond_json(200, {
    id = p.id,
    name = p.name or "",
    package_type = p.package_type or "",
    url = "",
    html_url = p._links and p._links.web_path or "",
    version_count = #entries,
    visibility = "public",
    owner = nil,
    repository = nil,
    created_at = p.created_at,
    updated_at = p.created_at,
  })
end)

b:rest("delete_org_package", function(org, pkg_type, pkg_name)
  local url = base()
    .. "/groups/"
    .. org
    .. "/packages?package_type="
    .. pkg_type
    .. "&package_name="
    .. pkg_name
    .. "&per_page=100"
  local ok, status, _, body = fetch_json(url)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local entries = DecodeJson(body) or {}
  if #entries == 0 then
    respond_json(404, { message = "Not Found" })
    return
  end
  for _, p in ipairs(entries) do
    fetch_json(base() .. "/projects/" .. p.project_id .. "/packages/" .. p.id, "DELETE")
  end
  set_preamble(204)
end)

b:rest("get_org_package_versions", function(org, pkg_type, pkg_name)
  local url = base()
    .. "/groups/"
    .. org
    .. "/packages?package_type="
    .. pkg_type
    .. "&package_name="
    .. pkg_name
  url = append_page_params(url, PAGES)
  proxy_json_paged(function(entries)
    local versions = {}
    for i, p in ipairs(entries) do
      versions[i] = {
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
    return versions
  end, PAGES, fetch_json(url))
end)

b:rest("get_org_package_version", function(org, pkg_type, pkg_name, version_id)
  local url = base()
    .. "/groups/"
    .. org
    .. "/packages?package_type="
    .. pkg_type
    .. "&package_name="
    .. pkg_name
    .. "&per_page=100"
  local ok, status, _, body = fetch_json(url)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local vid = tonumber(version_id)
  for _, p in ipairs(DecodeJson(body) or {}) do
    if p.id == vid then
      respond_json(200, {
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
      })
      return
    end
  end
  respond_json(404, { message = "Not Found" })
end)

b:rest("delete_org_package_version", function(org, pkg_type, pkg_name, version_id)
  local url = base()
    .. "/groups/"
    .. org
    .. "/packages?package_type="
    .. pkg_type
    .. "&package_name="
    .. pkg_name
    .. "&per_page=100"
  local ok, status, _, body = fetch_json(url)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local vid = tonumber(version_id)
  for _, p in ipairs(DecodeJson(body) or {}) do
    if p.id == vid then
      local dopts = auth() or {}
      dopts.method = "DELETE"
      local dok, dstatus =
        pcall(Fetch, base() .. "/projects/" .. p.project_id .. "/packages/" .. p.id, dopts)
      if dok and dstatus == 204 then
        set_preamble(204)
      elseif dok then
        respond_json(dstatus, {})
      else
        respond_json(503, {})
      end
      return
    end
  end
  respond_json(404, { message = "Not Found" })
end)

-- Markdown -------------------------------------------------------------------

-- POST /markdown → POST /api/v4/markdown
-- GitLab returns {"html": "..."} JSON; extract the html field.
b:rest("render_markdown", function()
  local incoming = DecodeJson(GetBody() or "{}") or {}
  local payload = EncodeJson({ text = incoming.text or "", gfm = true })
  local opts = auth() or {}
  opts.method = "POST"
  opts.body = payload
  opts.headers = opts.headers or {}
  opts.headers["Content-Type"] = "application/json"
  local ok, status, _, body = pcall(Fetch, base() .. "/markdown", opts)
  if not ok then
    respond_json(503, {})
    return
  end
  local parsed = DecodeJson(body or "{}") or {}
  set_preamble(status, "text/html; charset=utf-8")
  Write(parsed.html or "")
end)

-- Git database (https://docs.github.com/en/rest/git) -----------------------

-- GET /repos/{owner}/{repo}/git/blobs/{file_sha}
-- GitLab: GET /projects/:id/repository/blobs/:sha
-- Returns {size, encoding, content, sha} — translate to GitHub blob shape.
b:rest("get_git_blob", function(owner, repo_name, file_sha)
  proxy_json(
    function(br)
      return {
        content = br.content,
        encoding = br.encoding,
        url = "",
        sha = br.sha,
        size = br.size,
        node_id = "",
      }
    end,
    fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/repository/blobs/" .. file_sha
    )
  )
end)

-- POST /markdown/raw → POST /api/v4/markdown
-- GitLab has no separate raw endpoint; wrap the plain-text body in JSON.
b:rest("render_markdown_raw", function()
  local raw = GetBody() or ""
  local payload = EncodeJson({ text = raw, gfm = true })
  local opts = auth() or {}
  opts.method = "POST"
  opts.body = payload
  opts.headers = opts.headers or {}
  opts.headers["Content-Type"] = "application/json"
  local ok, status, _, body = pcall(Fetch, base() .. "/markdown", opts)
  if not ok then
    respond_json(503, {})
    return
  end
  local parsed = DecodeJson(body or "{}") or {}
  set_preamble(status, "text/html; charset=utf-8")
  Write(parsed.html or "")
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

local function translate_gl_vuln_list(arr)
  local result = {}
  for _, v in ipairs(arr) do
    result[#result + 1] = translate_gl_vulnerability(v)
  end
  return result
end

b:rest("list_repo_dependabot_alerts", function(owner, repo_name)
  proxy_json_paged(
    translate_gl_vuln_list,
    PAGES,
    fetch_json(base() .. "/projects/" .. project_id(owner, repo_name) .. "/vulnerabilities")
  )
end)

b:rest("get_repo_dependabot_alert", function(owner, repo_name, alert_number)
  proxy_json(
    translate_gl_vulnerability,
    fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/vulnerabilities/" .. alert_number
    )
  )
end)

b:rest("update_repo_dependabot_alert", function(_owner, _repo_name, alert_number)
  local req = DecodeJson(GetBody() or "{}")
  local action = GH_STATE_TO_GL_ACTION[req.state or ""] or "revert-to-detected"
  local gl_url = base() .. "/vulnerabilities/" .. alert_number .. "/" .. action
  local ok, status, _, body = fetch_json(gl_url, "POST", EncodeJson({}))
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  respond_json(200, translate_gl_vulnerability(DecodeJson(body) or {}))
end)

b:rest("list_org_dependabot_alerts", function(org)
  proxy_json_paged(
    translate_gl_vuln_list,
    PAGES,
    fetch_json(base() .. "/groups/" .. org .. "/vulnerabilities")
  )
end)

-- Secret Scanning via GitLab Secret Detection ----------------------------------
--
-- GitLab Secret Detection stores findings as vulnerabilities with
-- report_type=secret_detection. Endpoint mapping:
--   GET  /repos/{owner}/{repo}/secret-scanning/alerts       → GET  /projects/:id/vulnerabilities?report_type=secret_detection
--   GET  /repos/{owner}/{repo}/secret-scanning/alerts/{n}   → GET  /projects/:id/vulnerabilities/:n
--   PATCH /repos/{owner}/{repo}/secret-scanning/alerts/{n}  → POST /vulnerabilities/:n/dismiss|revert-to-detected|resolve
--   GET  /orgs/{org}/secret-scanning/alerts                 → GET  /groups/:org/vulnerabilities?report_type=secret_detection
--
-- Alert locations, push-protection bypasses, pattern configurations, and
-- scan history have no GitLab equivalent and fall back to defaults.
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

local function translate_gl_secret_list(arr)
  local result = {}
  for _, v in ipairs(arr) do
    result[#result + 1] = translate_gl_secret_alert(v)
  end
  return result
end

b:rest("list_repo_secret_scanning_alerts", function(owner, repo_name)
  proxy_json_paged(
    translate_gl_secret_list,
    PAGES,
    fetch_json(
      base()
        .. "/projects/"
        .. project_id(owner, repo_name)
        .. "/vulnerabilities?report_type=secret_detection"
    )
  )
end)

b:rest("list_org_secret_scanning_alerts", function(org)
  proxy_json_paged(
    translate_gl_secret_list,
    PAGES,
    fetch_json(base() .. "/groups/" .. org .. "/vulnerabilities?report_type=secret_detection")
  )
end)

b:rest("get_secret_scanning_alert", function(owner, repo_name, alert_number)
  proxy_json(
    translate_gl_secret_alert,
    fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/vulnerabilities/" .. alert_number
    )
  )
end)

b:rest("update_secret_scanning_alert", function(_owner, _repo_name, alert_number)
  local req = DecodeJson(GetBody() or "{}")
  local action = GH_SECRET_STATE_TO_GL_ACTION[req.state or ""] or "revert-to-detected"
  local gl_url = base() .. "/vulnerabilities/" .. alert_number .. "/" .. action
  local ok, status, _, body = fetch_json(gl_url, "POST", EncodeJson({}))
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  respond_json(200, translate_gl_secret_alert(DecodeJson(body) or {}))
end)

-- Gists (GitLab Snippets) ----------------------------------------------------

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

local function translate_gl_snippets(data)
  return translate_list(translate_gl_snippet, data)
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

local function translate_gl_snippet_notes(data)
  return translate_list(translate_gl_snippet_note, data)
end

-- Convert a GitHub gist create/update request body to GitLab snippet format.
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

local function delete_snippet(url)
  local opts = auth() or {}
  opts.method = "DELETE"
  proxy_204({ 200 }, pcall(Fetch, url, opts))
end

b:rest("get_gists", function()
  proxy_json_list(translate_gl_snippets, fetch_json(base() .. "/snippets"))
end)

b:rest("get_gists_public", function()
  proxy_json_list(translate_gl_snippets, fetch_json(base() .. "/snippets/public"))
end)

b:rest("post_gists", function()
  local req = DecodeJson(GetBody() or "{}") or {}
  proxy_json_created(
    translate_gl_snippet,
    fetch_json(base() .. "/snippets", "POST", gl_snippet_req(req))
  )
end)

b:rest("get_gist", function(id)
  proxy_json(translate_gl_snippet, fetch_json(base() .. "/snippets/" .. id))
end)

b:rest("patch_gist", function(id)
  local req = DecodeJson(GetBody() or "{}") or {}
  proxy_json(
    translate_gl_snippet,
    fetch_json(base() .. "/snippets/" .. id, "PUT", gl_snippet_req(req))
  )
end)

b:rest("delete_gist", function(id)
  delete_snippet(base() .. "/snippets/" .. id)
end)

b:rest("get_gist_comments", function(id)
  proxy_json_list(translate_gl_snippet_notes, fetch_json(base() .. "/snippets/" .. id .. "/notes"))
end)

b:rest("post_gist_comment", function(id)
  local req = DecodeJson(GetBody() or "{}") or {}
  proxy_json_created(
    translate_gl_snippet_note,
    fetch_json(
      base() .. "/snippets/" .. id .. "/notes",
      "POST",
      EncodeJson({ body = req.body or "" })
    )
  )
end)

b:rest("get_gist_comment", function(id, comment_id)
  proxy_json(
    translate_gl_snippet_note,
    fetch_json(base() .. "/snippets/" .. id .. "/notes/" .. comment_id)
  )
end)

b:rest("patch_gist_comment", function(id, comment_id)
  local req = DecodeJson(GetBody() or "{}") or {}
  proxy_json(
    translate_gl_snippet_note,
    fetch_json(
      base() .. "/snippets/" .. id .. "/notes/" .. comment_id,
      "PUT",
      EncodeJson({ body = req.body or "" })
    )
  )
end)

b:rest("delete_gist_comment", function(id, comment_id)
  delete_snippet(base() .. "/snippets/" .. id .. "/notes/" .. comment_id)
end)

b:rest("get_user_gists", function(_username)
  -- GitLab doesn't expose per-user public snippet lists; approximate with own snippets.
  proxy_json_list(translate_gl_snippets, fetch_json(base() .. "/snippets"))
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
b:build()
