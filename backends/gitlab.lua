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
local proxy_handler_created = _t.proxy_handler_created
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

local function translate_gl_users(users)
  return translate_list(translate_gl_user, users)
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

local function translate_gl_mrs(mrs)
  return translate_list(translate_gl_mr, mrs)
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

backend_impl = {
  get_root = function()
    proxy_health_check(pcall(Fetch, base() .. "/version", auth()))
  end,

  get_repo = proxy_handler(translate_gl_repo, function(owner, repo_name)
    return base() .. "/projects/" .. project_id(owner, repo_name)
  end),

  patch_repo = function(owner, repo_name)
    proxy_json(
      translate_gl_repo,
      fetch_json(
        base() .. "/projects/" .. project_id(owner, repo_name),
        "PUT",
        translate_gl_req(GetBody())
      )
    )
  end,

  delete_repo = function(owner, repo_name)
    local url = base() .. "/projects/" .. project_id(owner, repo_name)
    local dopts = auth() or {}
    dopts.method = "DELETE"
    -- GitLab returns 202 Accepted for async deletion
    proxy_204({ 202 }, pcall(Fetch, url, dopts))
  end,

  get_user_repos = proxy_handler_paged(translate_gl_projects, function()
    return append_page_params(base() .. "/projects?owned=true&membership=true", PAGES)
  end),

  post_user_repos = function()
    proxy_json_created(
      translate_gl_repo,
      fetch_json(base() .. "/projects", "POST", translate_gl_req(GetBody()))
    )
  end,

  get_org_repos = proxy_handler_paged(translate_gl_projects, function(org)
    return append_page_params(base() .. "/groups/" .. org .. "/projects", PAGES)
  end),

  post_org_repos = function(org)
    local gl_req = translate_gl_req(GetBody())
    local gl = DecodeJson(gl_req)
    gl.namespace_id = org
    proxy_json_created(translate_gl_repo, fetch_json(base() .. "/projects", "POST", EncodeJson(gl)))
  end,

  get_repo_topics = proxy_handler(function(p)
    return { names = p.topics or {} }
  end, function(owner, repo_name)
    return base() .. "/projects/" .. project_id(owner, repo_name)
  end),

  put_repo_topics = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
    proxy_json(
      function(p)
        return { names = p.topics or {} }
      end,
      fetch_json(
        base() .. "/projects/" .. project_id(owner, repo_name),
        "PUT",
        EncodeJson({ topics = req.names or {} })
      )
    )
  end,

  get_repo_languages = proxy_handler(nil, function(owner, repo_name)
    return base() .. "/projects/" .. project_id(owner, repo_name) .. "/languages"
  end),

  get_repo_contributors = proxy_handler_paged(function(contribs)
    for i, c in ipairs(contribs) do
      contribs[i] = { login = c.name, contributions = c.commits }
    end
    return contribs
  end, function(owner, repo_name)
    return append_page_params(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/repository/contributors",
      PAGES
    )
  end),

  get_repo_tags = proxy_handler_paged(function(tags)
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
  end),

  -- Branches ------------------------------------------------------------------

  get_repo_branches = proxy_handler_paged(function(branches)
    for _, b in ipairs(branches or {}) do
      if b.commit then
        b.commit.sha = b.commit.id
      end
    end
    return branches or {}
  end, function(owner, repo_name)
    return append_page_params(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/repository/branches",
      PAGES
    )
  end),

  get_repo_branch = proxy_handler(function(b)
    if b and b.commit then
      b.commit.sha = b.commit.id
    end
    return b or {}
  end, function(owner, repo_name, branch)
    return base()
      .. "/projects/"
      .. project_id(owner, repo_name)
      .. "/repository/branches/"
      .. branch
  end),

  -- Commits -------------------------------------------------------------------

  get_repo_commits = proxy_handler_paged(function(commits)
    local result = {}
    for _, c in ipairs(commits or {}) do
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
    return result
  end, function(owner, repo_name)
    return append_page_params(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/repository/commits",
      PAGES
    )
  end),

  get_repo_commit = proxy_handler(function(c)
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
  end, function(owner, repo_name, ref)
    return base() .. "/projects/" .. project_id(owner, repo_name) .. "/repository/commits/" .. ref
  end),

  -- Statuses ------------------------------------------------------------------

  -- GitLab status mapping: running→pending, failed→failure, canceled→error
  get_commit_statuses = function(owner, repo_name, ref)
    proxy_json_paged(
      function(statuses)
        local result = {}
        for _, s in ipairs(statuses or {}) do
          result[#result + 1] = {
            id = s.id,
            state = GL_STATUS_TO_GH[s.status] or s.status,
            description = s.description,
            target_url = s.target_url,
            context = s.name,
            created_at = s.created_at,
            updated_at = s.updated_at,
          }
        end
        return result
      end,
      PAGES,
      fetch_json(
        append_page_params(
          base()
            .. "/projects/"
            .. project_id(owner, repo_name)
            .. "/repository/commits/"
            .. ref
            .. "/statuses",
          PAGES
        )
      )
    )
  end,

  get_commit_combined_status = function(owner, repo_name, ref)
    -- GitLab has no single-object combined status; return the list as-is
    -- and wrap in a GitHub-style combined status object.
    proxy_json(
      function(statuses)
        local state = "success"
        local result = {}
        for _, s in ipairs(statuses or {}) do
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
        return { state = state, statuses = result, total_count = #result }
      end,
      fetch_json(
        base()
          .. "/projects/"
          .. project_id(owner, repo_name)
          .. "/repository/commits/"
          .. ref
          .. "/statuses"
      )
    )
  end,

  post_commit_status = function(owner, repo_name, sha)
    local req = DecodeJson(GetBody() or "{}")
    local gh_to_gl =
      { pending = "pending", success = "success", failure = "failed", error = "failed" }
    local gl_body = EncodeJson({
      state = gh_to_gl[req.state] or req.state,
      name = req.context or "default",
      description = req.description,
      target_url = req.target_url,
    })
    proxy_json_created(
      function(s)
        return {
          id = s.id,
          state = GL_STATUS_TO_GH[s.status] or s.status,
          description = s.description,
          target_url = s.target_url,
          context = s.name,
        }
      end,
      fetch_json(
        base() .. "/projects/" .. project_id(owner, repo_name) .. "/statuses/" .. sha,
        "POST",
        gl_body
      )
    )
  end,

  -- Contents ------------------------------------------------------------------

  get_repo_readme = proxy_handler(function(f)
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
  end, function(owner, repo_name)
    return base()
      .. "/projects/"
      .. project_id(owner, repo_name)
      .. "/repository/files/README.md?ref=HEAD"
  end),

  get_repo_readme_dir = function(owner, repo_name, dir)
    local enc_path = dir:gsub("/", "%%2F") .. "%%2FREADME.md"
    proxy_json(
      function(f)
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
      end,
      fetch_json(
        base()
          .. "/projects/"
          .. project_id(owner, repo_name)
          .. "/repository/files/"
          .. enc_path
          .. "?ref=HEAD"
      )
    )
  end,

  get_repo_content = function(owner, repo_name, path)
    local enc_path = path:gsub("/", "%%2F")
    proxy_json(
      function(f)
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
      end,
      fetch_json(
        base()
          .. "/projects/"
          .. project_id(owner, repo_name)
          .. "/repository/files/"
          .. enc_path
          .. "?ref=HEAD"
      )
    )
  end,

  put_repo_content = function(owner, repo_name, path)
    local enc_path = path:gsub("/", "%%2F")
    local req = DecodeJson(GetBody() or "{}")
    -- Check if file exists to decide create vs update
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
    proxy_json(
      nil,
      fetch_json(
        base() .. "/projects/" .. project_id(owner, repo_name) .. "/repository/files/" .. enc_path,
        method,
        gl_body
      )
    )
  end,

  delete_repo_content = function(owner, repo_name, path)
    local enc_path = path:gsub("/", "%%2F")
    local req = DecodeJson(GetBody() or "{}")
    local gl_body = EncodeJson({
      branch = req.branch or "main",
      commit_message = req.message,
      sha = req.sha,
    })
    proxy_json(
      nil,
      fetch_json(
        base() .. "/projects/" .. project_id(owner, repo_name) .. "/repository/files/" .. enc_path,
        "DELETE",
        gl_body
      )
    )
  end,

  get_repo_tarball = function(owner, repo_name, ref)
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
  end,

  get_repo_zipball = function(owner, repo_name, ref)
    SetStatus(302, "Found")
    SetHeader(
      "Location",
      base()
        .. "/projects/"
        .. project_id(owner, repo_name)
        .. "/repository/archive.zip?sha="
        .. ref
    )
    Write("")
  end,

  -- Compare -------------------------------------------------------------------

  get_repo_compare = function(owner, repo_name, basehead)
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
  end,

  -- Collaborators -------------------------------------------------------------

  get_repo_collaborators = proxy_handler_paged(function(members)
    local result = {}
    for _, m in ipairs(members or {}) do
      result[#result + 1] = {
        login = m.username,
        id = m.id,
        avatar_url = m.avatar_url or "",
        type = "User",
        permissions = {
          admin = (m.access_level or 0) >= 50,
          push = (m.access_level or 0) >= 30,
          pull = (m.access_level or 0) >= 10,
        },
      }
    end
    return result
  end, function(owner, repo_name)
    return append_page_params(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/members/all",
      PAGES
    )
  end),

  get_repo_collaborator = function(owner, repo_name, username)
    -- Resolve username to user ID, then check membership
    local ok, status, _, ubody = fetch_json(base() .. "/users?username=" .. username)
    if not ok or status ~= 200 then
      respond_json(404, {})
      return
    end
    local users = DecodeJson(ubody) or {}
    local uid = users[1] and users[1].id
    if not uid then
      respond_json(404, {})
      return
    end
    local ok2, status2 = pcall(
      Fetch,
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/members/" .. uid,
      auth()
    )
    if ok2 and status2 == 200 then
      SetStatus(204, "No Content")
    else
      respond_json(404, { message = "Not a collaborator" })
    end
  end,

  put_repo_collaborator = function(owner, repo_name, username)
    local ok, status, _, ubody = fetch_json(base() .. "/users?username=" .. username)
    if not ok or status ~= 200 then
      respond_json(404, {})
      return
    end
    local users = DecodeJson(ubody) or {}
    local uid = users[1] and users[1].id
    if not uid then
      respond_json(404, {})
      return
    end
    local req = DecodeJson(GetBody() or "{}")
    local perm = req.permission or "push"
    local level_map = { pull = 30, push = 30, admin = 50 }
    local body = EncodeJson({ user_id = uid, access_level = level_map[perm] or 30 })
    -- Try add first; if conflict, update
    local ok2, status2 =
      fetch_json(base() .. "/projects/" .. project_id(owner, repo_name) .. "/members", "POST", body)
    if ok2 and (status2 == 201 or status2 == 200) then
      SetStatus(204, "No Content")
    elseif ok2 and status2 == 409 then
      -- Already a member — update
      local ok3, status3 = fetch_json(
        base() .. "/projects/" .. project_id(owner, repo_name) .. "/members/" .. uid,
        "PUT",
        body
      )
      if ok3 and (status3 == 200 or status3 == 201) then
        SetStatus(204, "No Content")
      else
        respond_json(status3 or 503, {})
      end
    else
      respond_json(status2 or 503, {})
    end
  end,

  delete_repo_collaborator = function(owner, repo_name, username)
    local ok, status, _, ubody = fetch_json(base() .. "/users?username=" .. username)
    if not ok or status ~= 200 then
      respond_json(404, {})
      return
    end
    local users = DecodeJson(ubody) or {}
    local uid = users[1] and users[1].id
    if not uid then
      respond_json(404, {})
      return
    end
    local ok2, status2 = fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/members/" .. uid,
      "DELETE"
    )
    proxy_204({ 200 }, ok2, status2)
  end,

  get_repo_collaborator_permission = function(owner, repo_name, username)
    local ok, status, _, ubody = fetch_json(base() .. "/users?username=" .. username)
    if not ok or status ~= 200 then
      respond_json(404, {})
      return
    end
    local users = DecodeJson(ubody) or {}
    local uid = users[1] and users[1].id
    if not uid then
      respond_json(404, {})
      return
    end
    proxy_json(function(m)
      local al = m and m.access_level or 0
      local perm = al >= 50 and "admin" or (al >= 30 and "write" or "read")
      return { permission = perm, user = { login = username, id = uid } }
    end, fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/members/" .. uid
    ))
  end,

  -- Forks ---------------------------------------------------------------------

  get_repo_forks = proxy_handler_paged(translate_gl_projects, function(owner, repo_name)
    return append_page_params(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/forks",
      PAGES
    )
  end),

  post_repo_forks = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
    local body = req.organization and EncodeJson({ namespace = req.organization }) or "{}"
    proxy_json_created(
      translate_gl_repo,
      fetch_json(base() .. "/projects/" .. project_id(owner, repo_name) .. "/fork", "POST", body)
    )
  end,

  -- Releases ------------------------------------------------------------------
  -- GitLab releases use tag_name as identifier rather than an integer ID.

  get_repo_releases = proxy_handler_paged(function(rels)
    local result = {}
    for i, r in ipairs(rels or {}) do
      result[i] = {
        id = i,
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
    return result
  end, function(owner, repo_name)
    return append_page_params(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/releases",
      PAGES
    )
  end),

  post_repo_releases = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
    local body = EncodeJson({
      tag_name = req.tag_name,
      name = req.name,
      description = req.body,
    })
    proxy_json_created(
      function(r)
        return {
          id = 1,
          tag_name = r.tag_name,
          name = r.name,
          body = r.description,
          draft = false,
          prerelease = false,
          created_at = r.created_at,
          published_at = r.released_at or r.created_at,
          assets = {},
        }
      end,
      fetch_json(
        base() .. "/projects/" .. project_id(owner, repo_name) .. "/releases",
        "POST",
        body
      )
    )
  end,

  get_repo_release_latest = proxy_handler(function(r)
    return {
      id = 1,
      tag_name = r.tag_name,
      name = r.name,
      body = r.description,
      draft = false,
      prerelease = false,
      created_at = r.created_at,
      published_at = r.released_at or r.created_at,
      assets = {},
    }
  end, function(owner, repo_name)
    return base() .. "/projects/" .. project_id(owner, repo_name) .. "/releases/permalink/latest"
  end),

  get_repo_release_by_tag = proxy_handler(function(r)
    return {
      id = 1,
      tag_name = r.tag_name,
      name = r.name,
      body = r.description,
      draft = false,
      prerelease = false,
      created_at = r.created_at,
      published_at = r.released_at or r.created_at,
      assets = {},
    }
  end, function(owner, repo_name, tag)
    return base() .. "/projects/" .. project_id(owner, repo_name) .. "/releases/" .. tag
  end),

  get_repo_release = function(owner, repo_name, release_id)
    local tag = gl_tag_by_id(owner, repo_name, release_id)
    if not tag then
      respond_json(404, { message = "Not Found" })
      return
    end
    proxy_json(function(r)
      return translate_gl_release(r, tonumber(release_id))
    end, fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/releases/" .. tag
    ))
  end,

  patch_repo_release = function(owner, repo_name, release_id)
    local tag = gl_tag_by_id(owner, repo_name, release_id)
    if not tag then
      respond_json(404, { message = "Not Found" })
      return
    end
    local req = DecodeJson(GetBody() or "{}")
    local body = EncodeJson({ name = req.name, description = req.body })
    proxy_json(
      function(r)
        return translate_gl_release(r, tonumber(release_id))
      end,
      fetch_json(
        base() .. "/projects/" .. project_id(owner, repo_name) .. "/releases/" .. tag,
        "PUT",
        body
      )
    )
  end,

  delete_repo_release = function(owner, repo_name, release_id)
    local tag = gl_tag_by_id(owner, repo_name, release_id)
    if not tag then
      respond_json(404, { message = "Not Found" })
      return
    end
    local ok, status = fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/releases/" .. tag,
      "DELETE"
    )
    proxy_204({ 200 }, ok, status)
  end,

  get_repo_release_assets = function(owner, repo_name, release_id)
    local tag = gl_tag_by_id(owner, repo_name, release_id)
    if not tag then
      respond_json(404, { message = "Not Found" })
      return
    end
    proxy_json_paged(
      function(links)
        local result = {}
        for i, l in ipairs(links or {}) do
          result[i] = translate_gl_link(l)
        end
        return result
      end,
      PAGES,
      fetch_json(
        append_page_params(
          base()
            .. "/projects/"
            .. project_id(owner, repo_name)
            .. "/releases/"
            .. tag
            .. "/assets/links",
          PAGES
        )
      )
    )
  end,

  post_repo_release_assets = function(owner, repo_name, release_id)
    local tag = gl_tag_by_id(owner, repo_name, release_id)
    if not tag then
      respond_json(404, { message = "Not Found" })
      return
    end
    local req = DecodeJson(GetBody() or "{}")
    local body = EncodeJson({ name = req.name, url = req.url or "" })
    proxy_json_created(
      translate_gl_link,
      fetch_json(
        base()
          .. "/projects/"
          .. project_id(owner, repo_name)
          .. "/releases/"
          .. tag
          .. "/assets/links",
        "POST",
        body
      )
    )
  end,

  get_repo_release_asset = function(owner, repo_name, asset_id)
    local tag = gl_find_link(owner, repo_name, asset_id)
    if not tag then
      respond_json(404, { message = "Not Found" })
      return
    end
    proxy_json(
      translate_gl_link,
      fetch_json(
        base()
          .. "/projects/"
          .. project_id(owner, repo_name)
          .. "/releases/"
          .. tag
          .. "/assets/links/"
          .. asset_id
      )
    )
  end,

  patch_repo_release_asset = function(owner, repo_name, asset_id)
    local tag = gl_find_link(owner, repo_name, asset_id)
    if not tag then
      respond_json(404, { message = "Not Found" })
      return
    end
    local req = DecodeJson(GetBody() or "{}")
    local body = EncodeJson({ name = req.name })
    proxy_json(
      translate_gl_link,
      fetch_json(
        base()
          .. "/projects/"
          .. project_id(owner, repo_name)
          .. "/releases/"
          .. tag
          .. "/assets/links/"
          .. asset_id,
        "PUT",
        body
      )
    )
  end,

  delete_repo_release_asset = function(owner, repo_name, asset_id)
    local tag = gl_find_link(owner, repo_name, asset_id)
    if not tag then
      respond_json(404, { message = "Not Found" })
      return
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
    proxy_204({ 200 }, ok, status)
  end,

  -- Deploy keys ---------------------------------------------------------------

  get_repo_keys = proxy_handler_paged(nil, function(owner, repo_name)
    return append_page_params(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/deploy_keys",
      PAGES
    )
  end),

  post_repo_keys = function(owner, repo_name)
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
  end,

  get_repo_key = proxy_handler(nil, function(owner, repo_name, key_id)
    return base() .. "/projects/" .. project_id(owner, repo_name) .. "/deploy_keys/" .. key_id
  end),

  delete_repo_key = function(owner, repo_name, key_id)
    local ok, status = fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/deploy_keys/" .. key_id,
      "DELETE"
    )
    proxy_204({ 200 }, ok, status)
  end,

  -- Webhooks ------------------------------------------------------------------

  get_repo_hooks = proxy_handler_paged(nil, function(owner, repo_name)
    return append_page_params(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/hooks",
      PAGES
    )
  end),

  post_repo_hooks = function(owner, repo_name)
    proxy_json_created(
      nil,
      fetch_json(
        base() .. "/projects/" .. project_id(owner, repo_name) .. "/hooks",
        "POST",
        GetBody()
      )
    )
  end,

  get_repo_hook = proxy_handler(nil, function(owner, repo_name, hook_id)
    return base() .. "/projects/" .. project_id(owner, repo_name) .. "/hooks/" .. hook_id
  end),

  -- GitLab uses PUT for hook updates
  patch_repo_hook = function(owner, repo_name, hook_id)
    proxy_json(
      nil,
      fetch_json(
        base() .. "/projects/" .. project_id(owner, repo_name) .. "/hooks/" .. hook_id,
        "PUT",
        GetBody()
      )
    )
  end,

  delete_repo_hook = function(owner, repo_name, hook_id)
    local ok, status = fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/hooks/" .. hook_id,
      "DELETE"
    )
    proxy_204({ 200 }, ok, status)
  end,

  get_repo_hook_config = proxy_handler(function(h)
    return { url = h.url }
  end, function(owner, repo_name, hook_id)
    return base() .. "/projects/" .. project_id(owner, repo_name) .. "/hooks/" .. hook_id
  end),

  patch_repo_hook_config = function(owner, repo_name, hook_id)
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
  end,

  -- GET /users/{username}/repos -----------------------------------------------
  get_users_repos = proxy_handler_paged(translate_gl_projects, function(username)
    return append_page_params(base() .. "/users/" .. username .. "/projects", PAGES)
  end),

  -- GET /repositories (all public projects) -----------------------------------
  get_repositories = proxy_handler_paged(translate_gl_projects, function()
    return append_page_params(base() .. "/projects?visibility=public", PAGES)
  end),

  -- Commit comments -----------------------------------------------------------
  -- GitLab uses notes on commits: /projects/{id}/repository/commits/{sha}/comments
  get_commit_comments = proxy_handler_paged(nil, function(owner, repo_name, commit_sha)
    return append_page_params(
      base()
        .. "/projects/"
        .. project_id(owner, repo_name)
        .. "/repository/commits/"
        .. commit_sha
        .. "/comments",
      PAGES
    )
  end),

  post_commit_comment = function(owner, repo_name, commit_sha)
    proxy_json_created(
      nil,
      fetch_json(
        base()
          .. "/projects/"
          .. project_id(owner, repo_name)
          .. "/repository/commits/"
          .. commit_sha
          .. "/comments",
        "POST",
        GetBody()
      )
    )
  end,

  -- Users ---------------------------------------------------------------------

  -- GET /user
  get_user = proxy_handler(translate_gl_user, function()
    return base() .. "/user"
  end),

  -- PATCH /user
  patch_user = function()
    proxy_json(translate_gl_user, fetch_json(base() .. "/user", "PUT", GetBody()))
  end,

  -- GET /users/{username}
  get_users_username = proxy_handler(function(list)
    local u = (list and list[1]) or {}
    return translate_gl_user(u)
  end, function(username)
    return base() .. "/users?username=" .. username
  end),

  -- GET /users
  get_users = proxy_handler_paged(translate_gl_users, function()
    return append_page_params(base() .. "/users", PAGES)
  end),

  -- Emails --------------------------------------------------------------------

  -- GET /user/emails
  get_user_emails = proxy_handler(nil, function()
    return base() .. "/user/emails"
  end),

  -- POST /user/emails
  post_user_emails = function()
    proxy_json_created(nil, fetch_json(base() .. "/user/emails", "POST", GetBody()))
  end,

  -- SSH Keys ------------------------------------------------------------------

  -- GET /user/keys
  get_user_keys = proxy_handler_paged(nil, function()
    return append_page_params(base() .. "/user/keys", PAGES)
  end),

  -- POST /user/keys
  post_user_keys = function()
    proxy_json_created(nil, fetch_json(base() .. "/user/keys", "POST", GetBody()))
  end,

  -- GET /user/keys/{key_id}
  get_user_key = proxy_handler(nil, function(key_id)
    return base() .. "/user/keys/" .. key_id
  end),

  -- DELETE /user/keys/{key_id}
  delete_user_key = function(key_id)
    local opts = auth() or {}
    opts.method = "DELETE"
    proxy_204(nil, pcall(Fetch, base() .. "/user/keys/" .. key_id, opts))
  end,

  -- GET /users/{username}/keys
  get_users_keys = function(username)
    local uid = gl_user_id(username)
    if not uid then
      respond_json(404, { message = "Not Found" })
      return
    end
    proxy_json(nil, fetch_json(base() .. "/users/" .. uid .. "/keys"))
  end,

  -- GPG Keys ------------------------------------------------------------------

  -- GET /user/gpg_keys
  get_user_gpg_keys = proxy_handler_paged(nil, function()
    return append_page_params(base() .. "/user/gpg_keys", PAGES)
  end),

  -- POST /user/gpg_keys
  post_user_gpg_keys = function()
    proxy_json_created(nil, fetch_json(base() .. "/user/gpg_keys", "POST", GetBody()))
  end,

  -- GET /user/gpg_keys/{gpg_key_id}
  get_user_gpg_key = proxy_handler(nil, function(gpg_key_id)
    return base() .. "/user/gpg_keys/" .. gpg_key_id
  end),

  -- DELETE /user/gpg_keys/{gpg_key_id}
  delete_user_gpg_key = function(gpg_key_id)
    local opts = auth() or {}
    opts.method = "DELETE"
    proxy_204(nil, pcall(Fetch, base() .. "/user/gpg_keys/" .. gpg_key_id, opts))
  end,

  -- GET /users/{username}/gpg_keys
  get_users_gpg_keys = function(username)
    local uid = gl_user_id(username)
    if not uid then
      respond_json(404, { message = "Not Found" })
      return
    end
    proxy_json(nil, fetch_json(base() .. "/users/" .. uid .. "/gpg_keys"))
  end,

  -- Teams — mapped to GitLab subgroups ----------------------------------------
  -- GitHub: /orgs/{org}/teams/{team_slug}  →  GitLab: /groups/{org}%2F{slug}
  -- GitLab group members have access levels; repos are the group's projects.

  -- GET /orgs/{org}/teams
  get_org_teams = function(org)
    proxy_json_paged(function(groups)
      for i, g in ipairs(groups) do
        groups[i] = translate_gl_team(g)
      end
      return groups
    end, PAGES, fetch_json(
      append_page_params(base() .. "/groups/" .. org .. "/subgroups", PAGES)
    ))
  end,

  -- POST /orgs/{org}/teams
  post_org_teams = function(org)
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
  end,

  -- GET /orgs/{org}/teams/{team_slug}
  get_org_team = function(org, slug)
    proxy_json(translate_gl_team, fetch_json(base() .. "/groups/" .. org .. "%2F" .. slug))
  end,

  -- PATCH /orgs/{org}/teams/{team_slug}
  patch_org_team = function(org, slug)
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
  end,

  -- DELETE /orgs/{org}/teams/{team_slug}
  delete_org_team = function(org, slug)
    local ok, status, _, body = fetch_json(base() .. "/groups/" .. org .. "%2F" .. slug)
    if not ok or status ~= 200 then
      respond_json(ok and status or 503, {})
      return
    end
    local gid = (DecodeJson(body) or {}).id
    local dopts = auth() or {}
    dopts.method = "DELETE"
    proxy_204({ 202 }, pcall(Fetch, base() .. "/groups/" .. gid, dopts))
  end,

  -- GET /orgs/{org}/teams/{team_slug}/members
  get_org_team_members = function(org, slug)
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
  end,

  -- GET /orgs/{org}/teams/{team_slug}/memberships/{username}
  get_org_team_membership = function(org, slug, username)
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
  end,

  -- PUT /orgs/{org}/teams/{team_slug}/memberships/{username}
  put_org_team_membership = function(org, slug, username)
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
  end,

  -- DELETE /orgs/{org}/teams/{team_slug}/memberships/{username}
  delete_org_team_membership = function(org, slug, username)
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
  end,

  -- GET /orgs/{org}/teams/{team_slug}/repos
  get_org_team_repos = function(org, slug)
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
  end,

  -- GET /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}
  get_org_team_repo = function(org, slug, owner, repo_name)
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
  end,

  -- PUT /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}
  put_org_team_repo = function(org, slug, owner, repo_name)
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
  end,

  -- DELETE /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}
  delete_org_team_repo = function(org, slug, owner, repo_name)
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
  end,

  -- GET /orgs/{org}/teams/{team_slug}/teams — list sub-subgroups
  get_org_team_children = function(org, slug)
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
    end, PAGES, fetch_json(
      append_page_params(base() .. "/groups/" .. gid .. "/subgroups", PAGES)
    ))
  end,

  -- Legacy team-by-id API (/teams/{team_id}) ------------------------------------
  -- team_id maps to GitLab group numeric ID.

  -- GET /user/teams — all groups the authenticated user belongs to
  get_user_teams = function()
    proxy_json_paged(function(groups)
      for i, g in ipairs(groups) do
        groups[i] = translate_gl_team(g)
      end
      return groups
    end, PAGES, fetch_json(append_page_params(base() .. "/groups?min_access_level=10", PAGES)))
  end,

  -- GET /teams/{team_id}
  get_team = function(team_id)
    proxy_json(translate_gl_team, fetch_json(base() .. "/groups/" .. team_id))
  end,

  -- PATCH /teams/{team_id}
  patch_team = function(team_id)
    local req = DecodeJson(GetBody() or "{}")
    local upd = {}
    if req.name then
      upd.name = req.name
    end
    if req.description then
      upd.description = req.description
    end
    proxy_json(
      translate_gl_team,
      fetch_json(base() .. "/groups/" .. team_id, "PUT", EncodeJson(upd))
    )
  end,

  -- DELETE /teams/{team_id}
  delete_team = function(team_id)
    local dopts = auth() or {}
    dopts.method = "DELETE"
    proxy_204({ 202 }, pcall(Fetch, base() .. "/groups/" .. team_id, dopts))
  end,

  -- GET /teams/{team_id}/members
  get_team_members = function(team_id)
    proxy_json_paged(
      function(members)
        local out = {}
        for _, m in ipairs(members) do
          out[#out + 1] = translate_gl_member(m)
        end
        return out
      end,
      PAGES,
      fetch_json(append_page_params(base() .. "/groups/" .. team_id .. "/members", PAGES))
    )
  end,

  -- GET /teams/{team_id}/members/{username} — deprecated legacy, 204 if member
  get_team_member = function(team_id, username)
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
  end,

  -- PUT /teams/{team_id}/members/{username} — deprecated legacy
  put_team_member = function(team_id, username)
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
  end,

  -- DELETE /teams/{team_id}/members/{username} — deprecated legacy
  delete_team_member = function(team_id, username)
    local uid = gl_user_id(username)
    if not uid then
      respond_json(404, { message = "Not Found" })
      return
    end
    local dopts = auth() or {}
    dopts.method = "DELETE"
    proxy_204({ 200 }, pcall(Fetch, base() .. "/groups/" .. team_id .. "/members/" .. uid, dopts))
  end,

  -- GET /teams/{team_id}/memberships/{username}
  get_team_membership = function(team_id, username)
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
  end,

  -- PUT /teams/{team_id}/memberships/{username}
  put_team_membership = function(team_id, username)
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
  end,

  -- DELETE /teams/{team_id}/memberships/{username}
  delete_team_membership = function(team_id, username)
    local uid = gl_user_id(username)
    if not uid then
      respond_json(404, { message = "Not Found" })
      return
    end
    local dopts = auth() or {}
    dopts.method = "DELETE"
    proxy_204({ 200 }, pcall(Fetch, base() .. "/groups/" .. team_id .. "/members/" .. uid, dopts))
  end,

  -- GET /teams/{team_id}/repos
  get_team_repos = function(team_id)
    proxy_json_paged(
      translate_gl_projects,
      PAGES,
      fetch_json(append_page_params(base() .. "/groups/" .. team_id .. "/projects", PAGES))
    )
  end,

  -- GET /teams/{team_id}/repos/{owner}/{repo}
  get_team_repo = function(team_id, owner, repo_name)
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
  end,

  -- PUT /teams/{team_id}/repos/{owner}/{repo}
  put_team_repo = function(team_id, owner, repo_name)
    local pid = project_id(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
    local access = req.permission == "admin" and 50 or (req.permission == "push" and 30 or 20)
    local ok, status = fetch_json(
      base() .. "/projects/" .. pid .. "/share",
      "POST",
      EncodeJson({ group_id = team_id, group_access = access })
    )
    proxy_204({ 200, 201 }, ok, status)
  end,

  -- DELETE /teams/{team_id}/repos/{owner}/{repo}
  delete_team_repo = function(team_id, owner, repo_name)
    local pid = project_id(owner, repo_name)
    local dopts = auth() or {}
    dopts.method = "DELETE"
    proxy_204({ 200 }, pcall(Fetch, base() .. "/projects/" .. pid .. "/share/" .. team_id, dopts))
  end,

  -- GET /teams/{team_id}/teams — sub-subgroups
  get_team_children = function(team_id)
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
  end,

  -- Issues -------------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/issues
  get_repo_issues = proxy_handler_paged(translate_gl_issues, function(o, r)
    return append_page_params(base() .. "/projects/" .. project_id(o, r) .. "/issues", PAGES)
  end),

  -- POST /repos/{owner}/{repo}/issues
  post_repo_issues = proxy_handler_created(translate_gl_issue, function(o, r)
    local req = DecodeJson(GetBody() or "{}")
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
    return base() .. "/projects/" .. project_id(o, r) .. "/issues", "POST", EncodeJson(gl)
  end),

  -- GET /repos/{owner}/{repo}/issues/{issue_number}
  get_repo_issue = proxy_handler(translate_gl_issue, function(o, r, n)
    return base() .. "/projects/" .. project_id(o, r) .. "/issues/" .. n
  end),

  -- PATCH /repos/{owner}/{repo}/issues/{issue_number}
  patch_repo_issue = proxy_handler(translate_gl_issue, function(o, r, n)
    local req = DecodeJson(GetBody() or "{}")
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
    return base() .. "/projects/" .. project_id(o, r) .. "/issues/" .. n, "PUT", EncodeJson(gl)
  end),

  -- GET /repos/{owner}/{repo}/issues/{issue_number}/comments
  get_issue_comments = proxy_handler_paged(translate_gl_notes, function(o, r, n)
    return append_page_params(
      base() .. "/projects/" .. project_id(o, r) .. "/issues/" .. n .. "/notes",
      PAGES
    )
  end),

  -- POST /repos/{owner}/{repo}/issues/{issue_number}/comments
  post_issue_comment = proxy_handler_created(translate_gl_note, function(o, r, n)
    local req = DecodeJson(GetBody() or "{}")
    return base() .. "/projects/" .. project_id(o, r) .. "/issues/" .. n .. "/notes",
      "POST",
      EncodeJson({ body = req.body })
  end),

  -- GET /repos/{owner}/{repo}/issues/{issue_number}/labels
  get_issue_labels = function(owner, repo_name, issue_number)
    -- Fetch the issue and extract its labels.
    local ok, status, _, body = fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/issues/" .. issue_number
    )
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    local issue = DecodeJson(body) or {}
    local labels = {}
    for _, l in ipairs(issue.labels or {}) do
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
    respond_json(200, labels)
  end,

  -- POST /repos/{owner}/{repo}/issues/{issue_number}/labels
  post_issue_labels = function(owner, repo_name, issue_number)
    local req = DecodeJson(GetBody() or "{}")
    local existing_ok, existing_status, _, existing_body = fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/issues/" .. issue_number
    )
    if not existing_ok or existing_status ~= 200 then
      respond_json(404, { message = "Not Found" })
      return
    end
    local issue = DecodeJson(existing_body) or {}
    local all_labels = issue.labels or {}
    for _, name in ipairs(req.labels or {}) do
      all_labels[#all_labels + 1] = name
    end
    proxy_json(
      function(i)
        local labels = {}
        for _, l in ipairs(i.labels or {}) do
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
      end,
      fetch_json(
        base() .. "/projects/" .. project_id(owner, repo_name) .. "/issues/" .. issue_number,
        "PUT",
        EncodeJson({ labels = all_labels })
      )
    )
  end,

  -- PUT /repos/{owner}/{repo}/issues/{issue_number}/labels  (replace all)
  put_issue_labels = function(owner, repo_name, issue_number)
    local req = DecodeJson(GetBody() or "{}")
    proxy_json(
      function(i)
        local labels = {}
        for _, l in ipairs(i.labels or {}) do
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
      end,
      fetch_json(
        base() .. "/projects/" .. project_id(owner, repo_name) .. "/issues/" .. issue_number,
        "PUT",
        EncodeJson({ labels = req.labels or {} })
      )
    )
  end,

  -- DELETE /repos/{owner}/{repo}/issues/{issue_number}/labels  (remove all)
  delete_issue_labels = function(owner, repo_name, issue_number)
    proxy_204(
      { 200 },
      fetch_json(
        base() .. "/projects/" .. project_id(owner, repo_name) .. "/issues/" .. issue_number,
        "PUT",
        EncodeJson({ labels = {} })
      )
    )
  end,

  -- DELETE /repos/{owner}/{repo}/issues/{issue_number}/labels/{name}
  delete_issue_label = function(owner, repo_name, issue_number, label_name)
    local ok, status, _, body = fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/issues/" .. issue_number
    )
    if not ok or status ~= 200 then
      respond_json(404, { message = "Not Found" })
      return
    end
    local issue = DecodeJson(body) or {}
    local labels = {}
    for _, l in ipairs(issue.labels or {}) do
      local name = type(l) == "table" and l.name or l
      if name ~= label_name then
        labels[#labels + 1] = name
      end
    end
    local upok, upstatus = fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/issues/" .. issue_number,
      "PUT",
      EncodeJson({ labels = labels })
    )
    proxy_204({ 200 }, upok, upstatus)
  end,

  -- GET /repos/{owner}/{repo}/labels
  get_repo_labels = proxy_handler_paged(translate_gl_labels, function(o, r)
    return append_page_params(base() .. "/projects/" .. project_id(o, r) .. "/labels", PAGES)
  end),

  -- POST /repos/{owner}/{repo}/labels
  post_repo_labels = proxy_handler_created(translate_gl_label, function(o, r)
    return base() .. "/projects/" .. project_id(o, r) .. "/labels", "POST", GetBody()
  end),

  -- GET /repos/{owner}/{repo}/labels/{name}
  get_repo_label = function(owner, repo_name, label_name)
    local id = gl_find_label_id(owner, repo_name, label_name)
    if not id then
      respond_json(404, { message = "Label not found" })
      return
    end
    proxy_json(
      translate_gl_label,
      fetch_json(base() .. "/projects/" .. project_id(owner, repo_name) .. "/labels/" .. id)
    )
  end,

  -- PATCH /repos/{owner}/{repo}/labels/{name}
  patch_repo_label = function(owner, repo_name, label_name)
    local id = gl_find_label_id(owner, repo_name, label_name)
    if not id then
      respond_json(404, { message = "Label not found" })
      return
    end
    proxy_json(
      translate_gl_label,
      fetch_json(
        base() .. "/projects/" .. project_id(owner, repo_name) .. "/labels/" .. id,
        "PUT",
        GetBody()
      )
    )
  end,

  -- DELETE /repos/{owner}/{repo}/labels/{name}
  delete_repo_label = function(owner, repo_name, label_name)
    local id = gl_find_label_id(owner, repo_name, label_name)
    if not id then
      respond_json(404, { message = "Label not found" })
      return
    end
    local dopts = auth() or {}
    dopts.method = "DELETE"
    local ok, status = pcall(
      Fetch,
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/labels/" .. id,
      dopts
    )
    proxy_204({ 200 }, ok, status)
  end,

  -- Milestones ----------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/milestones
  get_repo_milestones = proxy_handler_paged(translate_gl_milestones, function(o, r)
    return append_page_params(base() .. "/projects/" .. project_id(o, r) .. "/milestones", PAGES)
  end),

  -- POST /repos/{owner}/{repo}/milestones
  post_repo_milestones = proxy_handler_created(translate_gl_milestone, function(o, r)
    local req = DecodeJson(GetBody() or "{}")
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
    return base() .. "/projects/" .. project_id(o, r) .. "/milestones", "POST", EncodeJson(gl)
  end),

  -- GET /repos/{owner}/{repo}/milestones/{milestone_number}
  get_repo_milestone = proxy_handler(translate_gl_milestone, function(o, r, n)
    return base() .. "/projects/" .. project_id(o, r) .. "/milestones/" .. n
  end),

  -- PATCH /repos/{owner}/{repo}/milestones/{milestone_number}
  patch_repo_milestone = proxy_handler(translate_gl_milestone, function(o, r, n)
    local req = DecodeJson(GetBody() or "{}")
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
    return base() .. "/projects/" .. project_id(o, r) .. "/milestones/" .. n, "PUT", EncodeJson(gl)
  end),

  -- DELETE /repos/{owner}/{repo}/milestones/{milestone_number}
  delete_repo_milestone = function(owner, repo_name, milestone_number)
    local dopts = auth() or {}
    dopts.method = "DELETE"
    local ok, status = pcall(
      Fetch,
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/milestones/" .. milestone_number,
      dopts
    )
    proxy_204({ 200 }, ok, status)
  end,

  -- Assignees -----------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/assignees  (users eligible for assignment)
  get_repo_assignees = proxy_handler_paged(translate_gl_members, function(o, r)
    return append_page_params(base() .. "/projects/" .. project_id(o, r) .. "/members/all", PAGES)
  end),

  -- Pull Requests (mapped to GitLab Merge Requests) --------------------------

  -- GET /repos/{owner}/{repo}/pulls
  get_repo_pulls = proxy_handler_paged(translate_gl_mrs, function(o, r)
    return append_page_params(
      base() .. "/projects/" .. project_id(o, r) .. "/merge_requests",
      PAGES
    )
  end),

  -- POST /repos/{owner}/{repo}/pulls
  post_repo_pulls = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
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
    proxy_json_created(
      translate_gl_mr,
      fetch_json(
        base() .. "/projects/" .. project_id(owner, repo_name) .. "/merge_requests",
        "POST",
        EncodeJson(gl)
      )
    )
  end,

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}
  get_repo_pull = proxy_handler(translate_gl_mr, function(o, r, n)
    return base() .. "/projects/" .. project_id(o, r) .. "/merge_requests/" .. n
  end),

  -- PATCH /repos/{owner}/{repo}/pulls/{pull_number}
  patch_repo_pull = function(owner, repo_name, pull_number)
    local req = DecodeJson(GetBody() or "{}")
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
    proxy_json(
      translate_gl_mr,
      fetch_json(
        base() .. "/projects/" .. project_id(owner, repo_name) .. "/merge_requests/" .. pull_number,
        "PUT",
        EncodeJson(gl)
      )
    )
  end,

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/commits
  get_pull_commits = proxy_handler_paged(function(commits)
    local result = {}
    for _, c in ipairs(commits or {}) do
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
    return result
  end, function(o, r, n)
    return append_page_params(
      base() .. "/projects/" .. project_id(o, r) .. "/merge_requests/" .. n .. "/commits",
      PAGES
    )
  end),

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/files
  -- GitLab uses /changes which wraps the diff list in a parent object.
  get_pull_files = proxy_handler(function(mr)
    local result = {}
    for _, c in ipairs((mr or {}).changes or {}) do
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
    return result
  end, function(o, r, n)
    return base() .. "/projects/" .. project_id(o, r) .. "/merge_requests/" .. n .. "/changes"
  end),

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/merge
  -- Returns 204 if the MR is merged, 404 if not.
  get_pull_merge = function(owner, repo_name, pull_number)
    local ok, status, _, body = fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/merge_requests/" .. pull_number
    )
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    local mr = DecodeJson(body) or {}
    if mr.state == "merged" or mr.merged_at ~= nil then
      SetStatus(204, "No Content")
    else
      respond_json(404, { message = "Pull Request is not merged" })
    end
  end,

  -- PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge
  put_pull_merge = function(owner, repo_name, pull_number)
    local req = DecodeJson(GetBody() or "{}")
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
    proxy_204({ 200 }, ok, status)
  end,

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/requested_reviewers
  -- GitLab: reviewers assigned to the MR.
  get_pull_requested_reviewers = function(owner, repo_name, pull_number)
    local ok, status, _, body = fetch_json(
      base()
        .. "/projects/"
        .. project_id(owner, repo_name)
        .. "/merge_requests/"
        .. pull_number
        .. "/reviewers"
    )
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    local reviewers = DecodeJson(body) or {}
    local users = {}
    for _, u in ipairs(reviewers) do
      users[#users + 1] = translate_gl_user(u)
    end
    respond_json(200, { users = users, teams = {} })
  end,

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews
  -- GitLab: MR approvals mapped to GitHub reviews.
  get_pull_reviews = function(owner, repo_name, pull_number)
    local ok, status, _, body = fetch_json(
      base()
        .. "/projects/"
        .. project_id(owner, repo_name)
        .. "/merge_requests/"
        .. pull_number
        .. "/approvals"
    )
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    local approvals = DecodeJson(body) or {}
    respond_json(200, translate_gl_approvals_to_reviews(approvals))
  end,

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}
  get_pull_review = function(owner, repo_name, pull_number, review_id)
    local ok, status, _, body = fetch_json(
      base()
        .. "/projects/"
        .. project_id(owner, repo_name)
        .. "/merge_requests/"
        .. pull_number
        .. "/approvals"
    )
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    local approvals = DecodeJson(body) or {}
    local reviews = translate_gl_approvals_to_reviews(approvals)
    local rid = tonumber(review_id)
    if rid and reviews[rid] then
      respond_json(200, reviews[rid])
    else
      respond_json(404, { message = "Not Found" })
    end
  end,

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}/comments
  -- GitLab has no per-review inline comments; return all inline MR notes.
  get_pull_review_comments = function(owner, repo_name, pull_number)
    local result, status = fetch_gl_mr_review_comments(owner, repo_name, pull_number)
    if not result then
      respond_json(status or 503, {})
      return
    end
    respond_json(200, result)
  end,

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/comments
  -- GitLab: inline (position-based) MR notes.
  get_pull_comments = function(owner, repo_name, pull_number)
    local result, status = fetch_gl_mr_review_comments(owner, repo_name, pull_number)
    if not result then
      respond_json(status or 503, {})
      return
    end
    respond_json(200, result)
  end,

  -- Search -----------------------------------------------------------------------

  -- GET /search/repositories — maps to GitLab GET /projects?search=<q>
  search_repositories = function()
    local q = GetParam("q") or ""
    proxy_search_gl(
      translate_gl_repo,
      append_page_params(base() .. "/projects?search=" .. q, PAGES)
    )
  end,

  -- GET /search/users — maps to GitLab GET /users?search=<q>
  search_users = function()
    local q = GetParam("q") or ""
    proxy_search_gl(translate_gl_user, append_page_params(base() .. "/users?search=" .. q, PAGES))
  end,

  -- Gitignore -----------------------------------------------------------------

  -- GET /gitignore/templates → GitLab GET /api/v4/templates/gitignores
  -- GitLab returns [{key,name}, ...]; GitHub returns ["Name", ...]
  get_gitignore_templates = function()
    proxy_json(function(list)
      local names = {}
      for i, t in ipairs(list or {}) do
        names[i] = t.name
      end
      return names
    end, fetch_json(base() .. "/templates/gitignores"))
  end,

  -- GET /gitignore/templates/{name} → GitLab GET /api/v4/templates/gitignores/{name}
  -- GitLab returns {name, content}; GitHub returns {name, source}
  get_gitignore_template = function(name)
    proxy_json(function(t)
      if not t then
        return {}
      end
      return { name = t.name, source = t.content }
    end, fetch_json(base() .. "/templates/gitignores/" .. name))
  end,

  -- Licenses -----------------------------------------------------------------

  -- GET /licenses → GitLab GET /api/v4/templates/licenses
  -- GitLab returns [{key,name,...}]; GitHub returns [{key,name,...}] (license-simple)
  get_licenses = function()
    proxy_json(function(list)
      local result = {}
      for i, t in ipairs(list or {}) do
        result[i] = { key = t.key, name = t.name }
      end
      return result
    end, fetch_json(base() .. "/templates/licenses"))
  end,

  -- GET /licenses/{license} → GitLab GET /api/v4/templates/licenses/{key}
  -- GitLab returns {key,name,content,description,conditions,permissions,limitations,html_url}
  -- GitHub returns {key,name,body,description,conditions,permissions,limitations,html_url,...}
  get_license = function(license_name)
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
  end,

  -- GET /repos/{owner}/{repo}/license
  -- Combines /repository/files/LICENSE content with project license metadata.
  get_repo_license = function(owner, repo_name)
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
  end,

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

  -- Translate a GitLab commit status object to a GitHub check run object.
  -- id is taken from the GitLab status.id field (used as check_run_id).
  post_check_runs = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
    local sha = req.head_sha or ""
    local status = req.status or "queued"
    local conclusion = req.conclusion
    local gh_conclusion_to_gl = {
      success = "success",
      neutral = "success",
      skipped = "success",
    }
    local gl_state = status == "completed" and (gh_conclusion_to_gl[conclusion] or "failed")
      or "running"
    local gl_body = EncodeJson({
      state = gl_state,
      target_url = req.details_url or "",
      description = (req.output and req.output.summary) or req.name or "",
      name = req.name or "",
      context = req.name or "",
      ref = sha,
    })
    local function translate(s)
      if not s then
        return {}
      end
      local mapped = GL_STATUS_TO_CHECK_RUN[s.status]
        or { status = "completed", conclusion = "failure" }
      return {
        id = s.id,
        node_id = "",
        head_sha = sha,
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
    proxy_json_created(
      translate,
      fetch_json(
        base() .. "/projects/" .. project_id(owner, repo_name) .. "/statuses/" .. sha,
        "POST",
        gl_body
      )
    )
  end,

  -- GET /repos/{owner}/{repo}/commits/{ref}/check-runs
  -- Uses GitLab commit statuses.
  get_commit_check_runs = function(owner, repo_name, ref)
    local ok, status, _, body = fetch_json(
      base()
        .. "/projects/"
        .. project_id(owner, repo_name)
        .. "/repository/commits/"
        .. ref
        .. "/statuses"
    )
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    local statuses = DecodeJson(body) or {}
    local runs = {}
    for i, s in ipairs(statuses) do
      local mapped = GL_STATUS_TO_CHECK_RUN[s.status]
        or { status = "completed", conclusion = "failure" }
      runs[i] = {
        id = s.id,
        node_id = "",
        head_sha = ref,
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
    respond_json(200, { total_count = #runs, check_runs = runs })
  end,

  -- Check suites have no GitLab equivalent; all suite endpoints fall back to
  -- the route_defaults stubs defined in .init.lua.

  -- Packages (org via GitLab group packages API) --------------------------------

  get_org_packages = function(org)
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
  end,

  get_org_package = function(org, pkg_type, pkg_name)
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
  end,

  delete_org_package = function(org, pkg_type, pkg_name)
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
  end,

  get_org_package_versions = function(org, pkg_type, pkg_name)
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
  end,

  get_org_package_version = function(org, pkg_type, pkg_name, version_id)
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
  end,

  delete_org_package_version = function(org, pkg_type, pkg_name, version_id)
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
  end,

  -- Markdown -------------------------------------------------------------------

  -- POST /markdown → POST /api/v4/markdown
  -- GitLab returns {"html": "..."} JSON; extract the html field.
  render_markdown = function()
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
  end,

  -- Git database (https://docs.github.com/en/rest/git) -----------------------

  -- GET /repos/{owner}/{repo}/git/blobs/{file_sha}
  -- GitLab: GET /projects/:id/repository/blobs/:sha
  -- Returns {size, encoding, content, sha} — translate to GitHub blob shape.
  get_git_blob = function(owner, repo_name, file_sha)
    proxy_json(
      function(b)
        return {
          content = b.content,
          encoding = b.encoding,
          url = "",
          sha = b.sha,
          size = b.size,
          node_id = "",
        }
      end,
      fetch_json(
        base() .. "/projects/" .. project_id(owner, repo_name) .. "/repository/blobs/" .. file_sha
      )
    )
  end,

  -- POST /markdown/raw → POST /api/v4/markdown
  -- GitLab has no separate raw endpoint; wrap the plain-text body in JSON.
  render_markdown_raw = function()
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
  end,
}

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

local _b = backend_impl

_b.list_repo_dependabot_alerts = function(owner, repo_name)
  proxy_json_paged(
    translate_gl_vuln_list,
    PAGES,
    fetch_json(base() .. "/projects/" .. project_id(owner, repo_name) .. "/vulnerabilities")
  )
end

_b.get_repo_dependabot_alert = function(owner, repo_name, alert_number)
  proxy_json(
    translate_gl_vulnerability,
    fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/vulnerabilities/" .. alert_number
    )
  )
end

_b.update_repo_dependabot_alert = function(_owner, _repo_name, alert_number)
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
end

_b.list_org_dependabot_alerts = function(org)
  proxy_json_paged(
    translate_gl_vuln_list,
    PAGES,
    fetch_json(base() .. "/groups/" .. org .. "/vulnerabilities")
  )
end

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

_b.list_repo_secret_scanning_alerts = function(owner, repo_name)
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
end

_b.list_org_secret_scanning_alerts = function(org)
  proxy_json_paged(
    translate_gl_secret_list,
    PAGES,
    fetch_json(base() .. "/groups/" .. org .. "/vulnerabilities?report_type=secret_detection")
  )
end

_b.get_secret_scanning_alert = function(owner, repo_name, alert_number)
  proxy_json(
    translate_gl_secret_alert,
    fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/vulnerabilities/" .. alert_number
    )
  )
end

_b.update_secret_scanning_alert = function(_owner, _repo_name, alert_number)
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
end

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

_b.get_gists = function()
  proxy_json_list(translate_gl_snippets, fetch_json(base() .. "/snippets"))
end

_b.get_gists_public = function()
  proxy_json_list(translate_gl_snippets, fetch_json(base() .. "/snippets/public"))
end

_b.post_gists = function()
  local req = DecodeJson(GetBody() or "{}") or {}
  proxy_json_created(
    translate_gl_snippet,
    fetch_json(base() .. "/snippets", "POST", gl_snippet_req(req))
  )
end

_b.get_gist = function(id)
  proxy_json(translate_gl_snippet, fetch_json(base() .. "/snippets/" .. id))
end

_b.patch_gist = function(id)
  local req = DecodeJson(GetBody() or "{}") or {}
  proxy_json(
    translate_gl_snippet,
    fetch_json(base() .. "/snippets/" .. id, "PUT", gl_snippet_req(req))
  )
end

_b.delete_gist = function(id)
  delete_snippet(base() .. "/snippets/" .. id)
end

_b.get_gist_comments = function(id)
  proxy_json_list(translate_gl_snippet_notes, fetch_json(base() .. "/snippets/" .. id .. "/notes"))
end

_b.post_gist_comment = function(id)
  local req = DecodeJson(GetBody() or "{}") or {}
  proxy_json_created(
    translate_gl_snippet_note,
    fetch_json(
      base() .. "/snippets/" .. id .. "/notes",
      "POST",
      EncodeJson({ body = req.body or "" })
    )
  )
end

_b.get_gist_comment = function(id, comment_id)
  proxy_json(
    translate_gl_snippet_note,
    fetch_json(base() .. "/snippets/" .. id .. "/notes/" .. comment_id)
  )
end

_b.patch_gist_comment = function(id, comment_id)
  local req = DecodeJson(GetBody() or "{}") or {}
  proxy_json(
    translate_gl_snippet_note,
    fetch_json(
      base() .. "/snippets/" .. id .. "/notes/" .. comment_id,
      "PUT",
      EncodeJson({ body = req.body or "" })
    )
  )
end

_b.delete_gist_comment = function(id, comment_id)
  delete_snippet(base() .. "/snippets/" .. id .. "/notes/" .. comment_id)
end

_b.get_user_gists = function(_username)
  -- GitLab doesn't expose per-user public snippet lists; approximate with own snippets.
  proxy_json_list(translate_gl_snippets, fetch_json(base() .. "/snippets"))
end

-- ── Reactions (GitLab award emoji) ────────────────────────────────────────────
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

-- Issue reactions: GitLab has full award_emoji support on issues.
_b.get_issue_reactions = proxy_handler_paged(
  translate_gl_awards,
  function(owner, repo_name, issue_number)
    return append_page_params(
      base()
        .. "/projects/"
        .. project_id(owner, repo_name)
        .. "/issues/"
        .. issue_number
        .. "/award_emoji",
      PAGES
    )
  end
)

_b.post_issue_reaction = proxy_handler_created(
  translate_gl_award,
  function(owner, repo_name, issue_number)
    local req = DecodeJson(GetBody() or "{}") or {}
    local emoji = CONTENT_TO_GL_EMOJI[req.content or ""] or req.content or ""
    return base()
      .. "/projects/"
      .. project_id(owner, repo_name)
      .. "/issues/"
      .. issue_number
      .. "/award_emoji",
      "POST",
      EncodeJson({ name = emoji })
  end
)

_b.delete_issue_reaction = function(owner, repo_name, issue_number, reaction_id)
  local url = base()
    .. "/projects/"
    .. project_id(owner, repo_name)
    .. "/issues/"
    .. issue_number
    .. "/award_emoji/"
    .. reaction_id
  local dopts = auth() or {}
  dopts.method = "DELETE"
  local ok, status, _, body = pcall(Fetch, url, dopts)
  if ok and status == 204 then
    SetStatus(204, "No Content")
  elseif ok then
    respond_json(status, DecodeJson(body) or {})
  else
    respond_json(503, {})
  end
end

-- ---------------------------------------------------------------------------
-- GraphQL resolvers — Query root fields and node resolvers
-- ---------------------------------------------------------------------------

-- Helper: translate a GitLab group (from /groups/{id}) to GitHub org REST shape
-- suitable for graphql_translate_org.
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

-- Helper: fetch a GitLab user by username.
-- GitLab returns an array from /users?username=X; we take the first element.
local function gl_fetch_user(username)
  local data, err = graphql_fetch(fetch_json, base() .. "/users?username=" .. username)
  if not data then
    return nil, err
  end
  local u = data[1]
  if not u then
    return nil, "not found: user " .. username
  end
  return u, nil
end

-- Query.repositoryOwner: look up a User or Organization (GitLab group) by login.
graphql_resolvers["Query.repositoryOwner"] = function(_parent, args, ctx)
  if not args.login then
    graphql_error(ctx, "repositoryOwner requires a login argument")
    return nil
  end
  local udata, _ = gl_fetch_user(args.login)
  if udata then
    return graphql_translate_user(translate_gl_user(udata))
  end
  local gdata, _ = graphql_fetch(fetch_json, base() .. "/groups/" .. args.login)
  if gdata then
    return graphql_translate_org(translate_gl_group_to_org(gdata))
  end
  return nil
end

-- Query.viewer: resolve the authenticated user via GET /user.
graphql_resolvers["Query.viewer"] = function(_parent, _args, ctx)
  local data = graphql_fetch_or_error(fetch_json, base() .. "/user", ctx, nil)
  if not data then
    return nil
  end
  local u = graphql_translate_user(translate_gl_user(data))
  u.isViewer = true
  return u
end

-- Query.user: look up a User by login.
graphql_resolvers["Query.user"] = function(_parent, args, ctx)
  if not args.login then
    graphql_error(ctx, "user requires a login argument")
    return nil
  end
  local udata, _ = gl_fetch_user(args.login)
  if not udata then
    return nil
  end
  return graphql_translate_user(translate_gl_user(udata))
end

-- Query.organization: look up a GitLab group by path.
graphql_resolvers["Query.organization"] = function(_parent, args, ctx)
  if not args.login then
    graphql_error(ctx, "organization requires a login argument")
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, base() .. "/groups/" .. args.login)
  if not data then
    return nil
  end
  return graphql_translate_org(translate_gl_group_to_org(data))
end

-- Query.repository: look up a Repository by owner and name.
graphql_resolvers["Query.repository"] = function(_parent, args, ctx)
  if not args.owner or not args.name then
    graphql_error(ctx, "repository requires owner and name arguments")
    return nil
  end
  local data, _ =
    graphql_fetch(fetch_json, base() .. "/projects/" .. project_id(args.owner, args.name))
  if not data then
    return nil
  end
  return graphql_translate_repo(translate_gl_repo(data))
end

-- node.Repository: fetch a repository by "owner/repo" local ID.
graphql_resolvers["node.Repository"] = function(local_id, _ctx)
  local owner, repo = local_id:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, base() .. "/projects/" .. project_id(owner, repo))
  if not data then
    return nil
  end
  return graphql_translate_repo(translate_gl_repo(data))
end

-- node.User: fetch a user by login.
graphql_resolvers["node.User"] = function(local_id, _ctx)
  local udata, _ = gl_fetch_user(local_id)
  if not udata then
    return nil
  end
  return graphql_translate_user(translate_gl_user(udata))
end

-- node.Organization: fetch a group by path.
graphql_resolvers["node.Organization"] = function(local_id, _ctx)
  local data, _ = graphql_fetch(fetch_json, base() .. "/groups/" .. local_id)
  if not data then
    return nil
  end
  return graphql_translate_org(translate_gl_group_to_org(data))
end

-- node.Issue: fetch an issue by "owner/repo/iid" local ID.
graphql_resolvers["node.Issue"] = function(local_id, _ctx)
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
end

-- node.PullRequest: fetch a merge request by "owner/repo/iid" local ID.
graphql_resolvers["node.PullRequest"] = function(local_id, _ctx)
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
end

-- node.IssueComment: fetch an issue note by "owner/repo/iid/note_id" local ID.
-- GitLab notes require the issue iid in the path, so the local ID encodes four segments.
graphql_resolvers["node.IssueComment"] = function(local_id, _ctx)
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
end

-- node.Release: fetch a release by "owner/repo/tag_name" local ID.
-- GitLab identifies releases by tag_name, not integer ID.
graphql_resolvers["node.Release"] = function(local_id, _ctx)
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
end

-- node.Label: fetch a label by "owner/repo/label_id" local ID.
graphql_resolvers["node.Label"] = function(local_id, _ctx)
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
end

-- node.Milestone: fetch a milestone by "owner/repo/number" local ID.
-- GitLab milestone numbers are iid (project-local); stored as number in the node ID.
graphql_resolvers["node.Milestone"] = function(local_id, _ctx)
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
end

-- node.Commit: fetch a commit by "owner/repo/sha" local ID.
-- GitLab returns a flat commit object; translate to REST shape before passing to the shared translator.
graphql_resolvers["node.Commit"] = function(local_id, _ctx)
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
end

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
graphql_resolvers["Repository.issues"] = function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitlab_repo_connection(owner, name, "/issues", args, ctx, function(i)
    return graphql_translate_issue(translate_gl_issue(i), owner, name)
  end, graphql_issues_connection)
end

-- Repository.pullRequests: paginated list of merge requests.
graphql_resolvers["Repository.pullRequests"] = function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitlab_repo_connection(owner, name, "/merge_requests", args, ctx, function(mr)
    return graphql_translate_pr(translate_gl_mr(mr), owner, name)
  end, graphql_prs_connection)
end

-- Repository.releases: paginated list of releases.
-- GitLab releases use tag_name as identifier; we assign a synthetic integer id.
graphql_resolvers["Repository.releases"] = function(parent, args, ctx)
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
end

-- Repository.labels: paginated list of labels.
graphql_resolvers["Repository.labels"] = function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitlab_repo_connection(owner, name, "/labels", args, ctx, function(l)
    return graphql_translate_label(translate_gl_label(l), owner, name)
  end, graphql_labels_connection)
end

-- Repository.milestones: paginated list of milestones.
graphql_resolvers["Repository.milestones"] = function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitlab_repo_connection(owner, name, "/milestones", args, ctx, function(m)
    return graphql_translate_milestone(translate_gl_milestone(m), owner, name)
  end, function(n, a, t, c)
    return graphql_make_connection("Milestone", n, a, t, c)
  end)
end

-- Repository.refs: paginated list of branches as Ref objects.
-- GitLab branch objects use commit.id for the SHA; normalise to commit.sha.
graphql_resolvers["Repository.refs"] = function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitlab_repo_connection(owner, name, "/repository/branches", args, ctx, function(b)
    if b.commit then
      b.commit.sha = b.commit.id
    end
    return graphql_translate_ref(b, parent)
  end, graphql_refs_connection)
end

-- Repository.collaborators: paginated list of project members as Users.
-- GitLab uses /members/all (not /collaborators) — consistent with the REST handler.
graphql_resolvers["Repository.collaborators"] = function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitlab_repo_connection(owner, name, "/members/all", args, ctx, function(m)
    return graphql_translate_user(translate_gl_member(m))
  end, function(n, a, t, c)
    return graphql_make_connection("RepositoryCollaborator", n, a, t, c)
  end)
end

-- Repository.defaultBranchRef: enrich the inline stub with full branch data.
-- The parent already carries {__typename="Ref",name="main"} from graphql_translate_repo.
-- GitLab branch objects use commit.id for the SHA; normalise to commit.sha.
graphql_resolvers["Repository.defaultBranchRef"] = function(parent, _args, _ctx)
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
end

-- ---------------------------------------------------------------------------
-- Issue and PullRequest sub-resolvers
-- ---------------------------------------------------------------------------

-- Issue.comments: paginated list of notes for a single issue.
-- GitLab notes are fetched from /projects/{id}/issues/{iid}/notes.
-- Comment node IDs encode four segments (owner/repo/iid/note_id) so the
-- node.IssueComment resolver can reconstruct the GitLab API path.
graphql_resolvers["Issue.comments"] = function(parent, args, ctx)
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
end

-- PullRequest.commits: paginated commit list for a merge request.
-- GitLab MR commits use .id for the SHA and flat author/committer fields.
graphql_resolvers["PullRequest.commits"] = function(parent, args, ctx)
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
end

-- PullRequest.reviews: MR approvals mapped to review objects.
-- GitLab's approvals endpoint returns a single object (not a paginated list),
-- so we fetch it directly and build an inline connection.
graphql_resolvers["PullRequest.reviews"] = function(parent, args, ctx)
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
end

-- Repository.languages: fetch language breakdown as a LanguageConnection.
-- GitLab returns {"Language": percentage, ...} (percentages, not byte counts).
-- We use the percentage as the "size" in edges since byte counts are unavailable.
graphql_resolvers["Repository.languages"] = function(parent, _args, _ctx)
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
end

-- ---------------------------------------------------------------------------
-- Query.search
-- ---------------------------------------------------------------------------

-- Query.search: map GitHub GraphQL search to GitLab search endpoints.
-- Supports REPOSITORY, USER, and ISSUE types; all others return empty.
-- GitLab uses /projects?search=, /users?search=, and /issues?search=.
graphql_resolvers["Query.search"] = function(_parent, args, ctx)
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
end
