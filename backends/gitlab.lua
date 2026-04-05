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

-- Encode owner/repo as GitLab project ID (URL-encoded "owner/repo").
local function project_id(owner, repo_name)
  -- Replace / with %2F and percent-encode other special chars.
  -- owner and repo_name come from the URL path so they contain no slashes.
  return owner .. "%2F" .. repo_name
end

local function fetch_json(url, method, body)
  local opts = auth()
  if method ~= nil and method ~= "GET" then
    opts = opts or {}
    opts.method = method
    if body then
      opts.body = body
      opts.headers = opts.headers or {}
      opts.headers["Content-Type"] = "application/json"
    end
  end
  return pcall(Fetch, url, opts)
end

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
  for i, p in ipairs(projects) do
    projects[i] = translate_gl_repo(p)
  end
  return projects
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
  for i, u in ipairs(users) do
    users[i] = translate_gl_user(u)
  end
  return users
end

local proxy_handler = make_proxy_handler(fetch_json)
local proxy_handler_created = make_proxy_handler(fetch_json, proxy_json_created)

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
  for i, iss in ipairs(issues) do
    issues[i] = translate_gl_issue(iss)
  end
  return issues
end
local function translate_gl_notes(notes)
  for i, n in ipairs(notes) do
    notes[i] = translate_gl_note(n)
  end
  return notes
end
local function translate_gl_labels(labels)
  for i, l in ipairs(labels) do
    labels[i] = translate_gl_label(l)
  end
  return labels
end
local function translate_gl_milestones(milestones)
  for i, m in ipairs(milestones) do
    milestones[i] = translate_gl_milestone(m)
  end
  return milestones
end
local function translate_gl_members(members)
  for i, m in ipairs(members) do
    members[i] = translate_gl_member(m)
  end
  return members
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

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, base() .. "/version", auth())
    if ok and status == 200 then
      respond_json(200, "OK", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
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
    local ok, status = pcall(Fetch, url, dopts)
    -- GitLab returns 202 Accepted for async deletion
    if ok and (status == 202 or status == 204) then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  get_user_repos = proxy_handler(translate_gl_projects, function()
    return append_page_params(base() .. "/projects?owned=true&membership=true", PAGES)
  end),

  post_user_repos = function()
    proxy_json_created(
      translate_gl_repo,
      fetch_json(base() .. "/projects", "POST", translate_gl_req(GetBody()))
    )
  end,

  get_org_repos = proxy_handler(translate_gl_projects, function(org)
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

  get_repo_contributors = proxy_handler(function(contribs)
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

  get_repo_tags = proxy_handler(function(tags)
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

  -- GitLab does not have a direct equivalent of GitHub's /teams endpoint for repos.
  get_repo_teams = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  -- Branches ------------------------------------------------------------------

  get_repo_branches = proxy_handler(function(branches)
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

  get_repo_commits = proxy_handler(function(commits)
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
    local gl_to_gh = {
      pending = "pending",
      running = "pending",
      success = "success",
      failed = "failure",
      canceled = "error",
    }
    proxy_json(
      function(statuses)
        local result = {}
        for _, s in ipairs(statuses or {}) do
          result[#result + 1] = {
            id = s.id,
            state = gl_to_gh[s.status] or s.status,
            description = s.description,
            target_url = s.target_url,
            context = s.name,
            created_at = s.created_at,
            updated_at = s.updated_at,
          }
        end
        return result
      end,
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
    local gl_to_gh = {
      pending = "pending",
      running = "pending",
      success = "success",
      failed = "failure",
      canceled = "error",
    }
    proxy_json(
      function(statuses)
        local state = "success"
        local result = {}
        for _, s in ipairs(statuses or {}) do
          local gh_state = gl_to_gh[s.status] or s.status
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
        local gl_to_gh = {
          pending = "pending",
          running = "pending",
          success = "success",
          failed = "failure",
          canceled = "error",
        }
        return {
          id = s.id,
          state = gl_to_gh[s.status] or s.status,
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

  get_repo_collaborators = proxy_handler(function(members)
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
      respond_json(404, "Not Found", {})
      return
    end
    local users = DecodeJson(ubody) or {}
    local uid = users[1] and users[1].id
    if not uid then
      respond_json(404, "Not Found", {})
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
      respond_json(404, "Not Found", { message = "Not a collaborator" })
    end
  end,

  put_repo_collaborator = function(owner, repo_name, username)
    local ok, status, _, ubody = fetch_json(base() .. "/users?username=" .. username)
    if not ok or status ~= 200 then
      respond_json(404, "Not Found", {})
      return
    end
    local users = DecodeJson(ubody) or {}
    local uid = users[1] and users[1].id
    if not uid then
      respond_json(404, "Not Found", {})
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
        respond_json(status3 or 503, "Error", {})
      end
    else
      respond_json(status2 or 503, "Error", {})
    end
  end,

  delete_repo_collaborator = function(owner, repo_name, username)
    local ok, status, _, ubody = fetch_json(base() .. "/users?username=" .. username)
    if not ok or status ~= 200 then
      respond_json(404, "Not Found", {})
      return
    end
    local users = DecodeJson(ubody) or {}
    local uid = users[1] and users[1].id
    if not uid then
      respond_json(404, "Not Found", {})
      return
    end
    local ok2, status2 = fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/members/" .. uid,
      "DELETE"
    )
    if ok2 and (status2 == 200 or status2 == 204) then
      SetStatus(204, "No Content")
    else
      respond_json(status2 or 503, "Error", {})
    end
  end,

  get_repo_collaborator_permission = function(owner, repo_name, username)
    local ok, status, _, ubody = fetch_json(base() .. "/users?username=" .. username)
    if not ok or status ~= 200 then
      respond_json(404, "Not Found", {})
      return
    end
    local users = DecodeJson(ubody) or {}
    local uid = users[1] and users[1].id
    if not uid then
      respond_json(404, "Not Found", {})
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

  get_repo_forks = proxy_handler(translate_gl_projects, function(owner, repo_name)
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

  get_repo_releases = proxy_handler(function(rels)
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

  -- Deploy keys ---------------------------------------------------------------

  get_repo_keys = proxy_handler(nil, function(owner, repo_name)
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
      can_push = not (req.read_only ~= false),
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
    if ok and (status == 204 or status == 200) then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- Webhooks ------------------------------------------------------------------

  get_repo_hooks = proxy_handler(nil, function(owner, repo_name)
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
    if ok and (status == 204 or status == 200) then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
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
        respond_json(status, "Error", {})
      else
        respond_json(503, "Service Unavailable", {})
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
  get_users_repos = proxy_handler(translate_gl_projects, function(username)
    return append_page_params(base() .. "/users/" .. username .. "/projects", PAGES)
  end),

  -- GET /repositories (all public projects) -----------------------------------
  get_repositories = proxy_handler(translate_gl_projects, function()
    return append_page_params(base() .. "/projects?visibility=public", PAGES)
  end),

  -- Commit comments -----------------------------------------------------------
  -- GitLab uses notes on commits: /projects/{id}/repository/commits/{sha}/comments
  get_commit_comments = proxy_handler(nil, function(owner, repo_name, commit_sha)
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
  get_users = proxy_handler(translate_gl_users, function()
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

  -- DELETE /user/emails
  delete_user_emails = function()
    -- GitLab requires DELETE /user/emails/{id}; without an ID we can't delete by address.
    -- Return 204 as a best-effort passthrough.
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  -- SSH Keys ------------------------------------------------------------------

  -- GET /user/keys
  get_user_keys = proxy_handler(nil, function()
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
    local ok, status = pcall(Fetch, base() .. "/user/keys/" .. key_id, opts)
    if ok and status == 204 then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- GET /users/{username}/keys
  get_users_keys = function(username)
    local uid = gl_user_id(username)
    if not uid then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    proxy_json(nil, fetch_json(base() .. "/users/" .. uid .. "/keys"))
  end,

  -- GPG Keys ------------------------------------------------------------------

  -- GET /user/gpg_keys
  get_user_gpg_keys = proxy_handler(nil, function()
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
    local ok, status = pcall(Fetch, base() .. "/user/gpg_keys/" .. gpg_key_id, opts)
    if ok and status == 204 then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- GET /users/{username}/gpg_keys
  get_users_gpg_keys = function(username)
    local uid = gl_user_id(username)
    if not uid then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    proxy_json(nil, fetch_json(base() .. "/users/" .. uid .. "/gpg_keys"))
  end,

  -- Teams — mapped to GitLab subgroups ----------------------------------------
  -- GitHub: /orgs/{org}/teams/{team_slug}  →  GitLab: /groups/{org}%2F{slug}
  -- GitLab group members have access levels; repos are the group's projects.

  -- GET /orgs/{org}/teams
  get_org_teams = function(org)
    proxy_json(function(groups)
      for i, g in ipairs(groups) do
        groups[i] = translate_gl_team(g)
      end
      return groups
    end, fetch_json(append_page_params(base() .. "/groups/" .. org .. "/subgroups", PAGES)))
  end,

  -- POST /orgs/{org}/teams
  post_org_teams = function(org)
    local req = DecodeJson(GetBody() or "{}")
    local parent_ok, parent_status, _, parent_body = fetch_json(base() .. "/groups/" .. org)
    if not parent_ok or parent_status ~= 200 then
      respond_json(parent_ok and parent_status or 503, "Error", {})
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
      respond_json(ok and status or 503, "Error", {})
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
      respond_json(ok and status or 503, "Error", {})
      return
    end
    local gid = (DecodeJson(body) or {}).id
    local dopts = auth() or {}
    dopts.method = "DELETE"
    local dok, dstatus = pcall(Fetch, base() .. "/groups/" .. gid, dopts)
    if dok and (dstatus == 202 or dstatus == 204) then
      SetStatus(204, "No Content")
    elseif dok then
      respond_json(dstatus, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- GET /orgs/{org}/teams/{team_slug}/invitations — no concept in GitLab
  get_org_team_invitations = function()
    SetStatus(200, "OK")
    SetHeader("Content-Type", "application/json; charset=utf-8")
    Write("[]")
  end,

  -- GET /orgs/{org}/teams/{team_slug}/members
  get_org_team_members = function(org, slug)
    local ok, status, _, body = fetch_json(base() .. "/groups/" .. org .. "%2F" .. slug)
    if not ok or status ~= 200 then
      respond_json(ok and status or 503, "Error", {})
      return
    end
    local gid = (DecodeJson(body) or {}).id
    proxy_json(function(members)
      local out = {}
      for _, m in ipairs(members) do
        out[#out + 1] = translate_gl_member(m)
      end
      return out
    end, fetch_json(append_page_params(base() .. "/groups/" .. gid .. "/members", PAGES)))
  end,

  -- GET /orgs/{org}/teams/{team_slug}/memberships/{username}
  get_org_team_membership = function(org, slug, username)
    local ok, status, _, body = fetch_json(base() .. "/groups/" .. org .. "%2F" .. slug)
    if not ok or status ~= 200 then
      respond_json(ok and status or 503, "Error", {})
      return
    end
    local gid = (DecodeJson(body) or {}).id
    local uid = gl_user_id(username)
    if not uid then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    local mok, mstatus, _, mbody = fetch_json(base() .. "/groups/" .. gid .. "/members/" .. uid)
    if mok and mstatus == 200 then
      local m = DecodeJson(mbody) or {}
      local role = (m.access_level or 0) >= 50 and "maintainer" or "member"
      respond_json(200, "OK", { url = "", role = role, state = "active" })
    elseif mok then
      respond_json(404, "Not Found", { message = "Not Found" })
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- PUT /orgs/{org}/teams/{team_slug}/memberships/{username}
  put_org_team_membership = function(org, slug, username)
    local ok, status, _, body = fetch_json(base() .. "/groups/" .. org .. "%2F" .. slug)
    if not ok or status ~= 200 then
      respond_json(ok and status or 503, "Error", {})
      return
    end
    local gid = (DecodeJson(body) or {}).id
    local uid = gl_user_id(username)
    if not uid then
      respond_json(404, "Not Found", { message = "Not Found" })
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
      respond_json(200, "OK", { url = "", role = req.role or "member", state = "active" })
    elseif mok then
      respond_json(mstatus, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- DELETE /orgs/{org}/teams/{team_slug}/memberships/{username}
  delete_org_team_membership = function(org, slug, username)
    local ok, status, _, body = fetch_json(base() .. "/groups/" .. org .. "%2F" .. slug)
    if not ok or status ~= 200 then
      respond_json(ok and status or 503, "Error", {})
      return
    end
    local gid = (DecodeJson(body) or {}).id
    local uid = gl_user_id(username)
    if not uid then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    local dopts = auth() or {}
    dopts.method = "DELETE"
    local dok, dstatus = pcall(Fetch, base() .. "/groups/" .. gid .. "/members/" .. uid, dopts)
    if dok and (dstatus == 204 or dstatus == 200) then
      SetStatus(204, "No Content")
    elseif dok then
      respond_json(dstatus, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- GET /orgs/{org}/teams/{team_slug}/repos
  get_org_team_repos = function(org, slug)
    local ok, status, _, body = fetch_json(base() .. "/groups/" .. org .. "%2F" .. slug)
    if not ok or status ~= 200 then
      respond_json(ok and status or 503, "Error", {})
      return
    end
    local gid = (DecodeJson(body) or {}).id
    proxy_json(
      translate_gl_projects,
      fetch_json(append_page_params(base() .. "/groups/" .. gid .. "/projects", PAGES))
    )
  end,

  -- GET /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}
  get_org_team_repo = function(org, slug, owner, repo_name)
    local ok, status, _, body = fetch_json(base() .. "/groups/" .. org .. "%2F" .. slug)
    if not ok or status ~= 200 then
      respond_json(ok and status or 503, "Error", {})
      return
    end
    local gid = (DecodeJson(body) or {}).id
    local pid = project_id(owner, repo_name)
    -- Check if the project belongs to this subgroup
    local pok, pstatus, _, pbody = fetch_json(base() .. "/projects/" .. pid)
    if not pok or pstatus ~= 200 then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    local proj = DecodeJson(pbody) or {}
    local ns = proj.namespace or {}
    if tostring(ns.id) ~= tostring(gid) then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    respond_json(200, "OK", translate_gl_repo(proj))
  end,

  -- PUT /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}
  put_org_team_repo = function(org, slug, owner, repo_name)
    local ok, status, _, body = fetch_json(base() .. "/groups/" .. org .. "%2F" .. slug)
    if not ok or status ~= 200 then
      respond_json(ok and status or 503, "Error", {})
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
    if pok and (pstatus == 200 or pstatus == 201) then
      SetStatus(204, "No Content")
    elseif pok then
      respond_json(pstatus, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- DELETE /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}
  delete_org_team_repo = function(org, slug, owner, repo_name)
    local ok, status, _, body = fetch_json(base() .. "/groups/" .. org .. "%2F" .. slug)
    if not ok or status ~= 200 then
      respond_json(ok and status or 503, "Error", {})
      return
    end
    local gid = (DecodeJson(body) or {}).id
    local pid = project_id(owner, repo_name)
    local dopts = auth() or {}
    dopts.method = "DELETE"
    local dok, dstatus = pcall(Fetch, base() .. "/projects/" .. pid .. "/share/" .. gid, dopts)
    if dok and (dstatus == 204 or dstatus == 200) then
      SetStatus(204, "No Content")
    elseif dok then
      respond_json(dstatus, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- GET /orgs/{org}/teams/{team_slug}/teams — list sub-subgroups
  get_org_team_children = function(org, slug)
    local ok, status, _, body = fetch_json(base() .. "/groups/" .. org .. "%2F" .. slug)
    if not ok or status ~= 200 then
      respond_json(ok and status or 503, "Error", {})
      return
    end
    local gid = (DecodeJson(body) or {}).id
    proxy_json(function(groups)
      for i, g in ipairs(groups) do
        groups[i] = translate_gl_team(g)
      end
      return groups
    end, fetch_json(append_page_params(base() .. "/groups/" .. gid .. "/subgroups", PAGES)))
  end,

  -- Legacy team-by-id API (/teams/{team_id}) ------------------------------------
  -- team_id maps to GitLab group numeric ID.

  -- GET /user/teams — all groups the authenticated user belongs to
  get_user_teams = function()
    proxy_json(function(groups)
      for i, g in ipairs(groups) do
        groups[i] = translate_gl_team(g)
      end
      return groups
    end, fetch_json(append_page_params(base() .. "/groups?min_access_level=10", PAGES)))
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
    local ok, status = pcall(Fetch, base() .. "/groups/" .. team_id, dopts)
    if ok and (status == 202 or status == 204) then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- GET /teams/{team_id}/invitations — no concept in GitLab
  get_team_invitations = function()
    SetStatus(200, "OK")
    SetHeader("Content-Type", "application/json; charset=utf-8")
    Write("[]")
  end,

  -- GET /teams/{team_id}/members
  get_team_members = function(team_id)
    proxy_json(function(members)
      local out = {}
      for _, m in ipairs(members) do
        out[#out + 1] = translate_gl_member(m)
      end
      return out
    end, fetch_json(append_page_params(base() .. "/groups/" .. team_id .. "/members", PAGES)))
  end,

  -- GET /teams/{team_id}/members/{username} — deprecated legacy, 204 if member
  get_team_member = function(team_id, username)
    local uid = gl_user_id(username)
    if not uid then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    local ok, status = pcall(Fetch, base() .. "/groups/" .. team_id .. "/members/" .. uid, auth())
    if ok and status == 200 then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(404, "Not Found", { message = "Not Found" })
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- PUT /teams/{team_id}/members/{username} — deprecated legacy
  put_team_member = function(team_id, username)
    local uid = gl_user_id(username)
    if not uid then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    local ok, status = fetch_json(
      base() .. "/groups/" .. team_id .. "/members",
      "POST",
      EncodeJson({ user_id = uid, access_level = 30 })
    )
    if ok and (status == 200 or status == 201) then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- DELETE /teams/{team_id}/members/{username} — deprecated legacy
  delete_team_member = function(team_id, username)
    local uid = gl_user_id(username)
    if not uid then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    local dopts = auth() or {}
    dopts.method = "DELETE"
    local ok, status = pcall(Fetch, base() .. "/groups/" .. team_id .. "/members/" .. uid, dopts)
    if ok and (status == 204 or status == 200) then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- GET /teams/{team_id}/memberships/{username}
  get_team_membership = function(team_id, username)
    local uid = gl_user_id(username)
    if not uid then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    local ok, status, _, body = fetch_json(base() .. "/groups/" .. team_id .. "/members/" .. uid)
    if ok and status == 200 then
      local m = DecodeJson(body) or {}
      local role = (m.access_level or 0) >= 50 and "maintainer" or "member"
      respond_json(200, "OK", { url = "", role = role, state = "active" })
    elseif ok then
      respond_json(404, "Not Found", { message = "Not Found" })
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- PUT /teams/{team_id}/memberships/{username}
  put_team_membership = function(team_id, username)
    local uid = gl_user_id(username)
    if not uid then
      respond_json(404, "Not Found", { message = "Not Found" })
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
      respond_json(200, "OK", { url = "", role = req.role or "member", state = "active" })
    elseif ok then
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- DELETE /teams/{team_id}/memberships/{username}
  delete_team_membership = function(team_id, username)
    local uid = gl_user_id(username)
    if not uid then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    local dopts = auth() or {}
    dopts.method = "DELETE"
    local ok, status = pcall(Fetch, base() .. "/groups/" .. team_id .. "/members/" .. uid, dopts)
    if ok and (status == 204 or status == 200) then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- GET /teams/{team_id}/repos
  get_team_repos = function(team_id)
    proxy_json(
      translate_gl_projects,
      fetch_json(append_page_params(base() .. "/groups/" .. team_id .. "/projects", PAGES))
    )
  end,

  -- GET /teams/{team_id}/repos/{owner}/{repo}
  get_team_repo = function(team_id, owner, repo_name)
    local pid = project_id(owner, repo_name)
    local ok, status, _, body = fetch_json(base() .. "/projects/" .. pid)
    if not ok or status ~= 200 then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    local proj = DecodeJson(body) or {}
    local ns = proj.namespace or {}
    if tostring(ns.id) ~= tostring(team_id) then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    respond_json(200, "OK", translate_gl_repo(proj))
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
    if ok and (status == 200 or status == 201) then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- DELETE /teams/{team_id}/repos/{owner}/{repo}
  delete_team_repo = function(team_id, owner, repo_name)
    local pid = project_id(owner, repo_name)
    local dopts = auth() or {}
    dopts.method = "DELETE"
    local ok, status = pcall(Fetch, base() .. "/projects/" .. pid .. "/share/" .. team_id, dopts)
    if ok and (status == 204 or status == 200) then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- GET /teams/{team_id}/teams — sub-subgroups
  get_team_children = function(team_id)
    proxy_json(function(groups)
      for i, g in ipairs(groups) do
        groups[i] = translate_gl_team(g)
      end
      return groups
    end, fetch_json(append_page_params(base() .. "/groups/" .. team_id .. "/subgroups", PAGES)))
  end,

  -- Issues -------------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/issues
  get_repo_issues = proxy_handler(translate_gl_issues, function(o, r)
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
  get_issue_comments = proxy_handler(translate_gl_notes, function(o, r, n)
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

  -- GET /repos/{owner}/{repo}/issues/comments/{comment_id}
  get_repo_issue_comment = function(owner, repo_name, comment_id)
    -- GitLab requires the issue IID; without it we cannot fetch a note directly.
    -- Return 404 as there's no cross-issue comment lookup endpoint.
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  -- PATCH /repos/{owner}/{repo}/issues/comments/{comment_id}
  patch_repo_issue_comment = function(owner, repo_name, comment_id)
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  -- DELETE /repos/{owner}/{repo}/issues/comments/{comment_id}
  delete_repo_issue_comment = function(owner, repo_name, comment_id)
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  -- GET /repos/{owner}/{repo}/issues/{issue_number}/labels
  get_issue_labels = function(owner, repo_name, issue_number)
    -- Fetch the issue and extract its labels.
    local ok, status, _, body = fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/issues/" .. issue_number
    )
    if not ok then
      respond_json(503, "Service Unavailable", {})
      return
    end
    if status ~= 200 then
      respond_json(status, "Error", {})
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
    respond_json(200, "OK", labels)
  end,

  -- POST /repos/{owner}/{repo}/issues/{issue_number}/labels
  post_issue_labels = function(owner, repo_name, issue_number)
    local req = DecodeJson(GetBody() or "{}")
    local existing_ok, existing_status, _, existing_body = fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/issues/" .. issue_number
    )
    if not existing_ok or existing_status ~= 200 then
      respond_json(404, "Not Found", { message = "Not Found" })
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
    local ok, status = fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/issues/" .. issue_number,
      "PUT",
      EncodeJson({ labels = {} })
    )
    if ok and (status == 200 or status == 204) then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- DELETE /repos/{owner}/{repo}/issues/{issue_number}/labels/{name}
  delete_issue_label = function(owner, repo_name, issue_number, label_name)
    local ok, status, _, body = fetch_json(
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/issues/" .. issue_number
    )
    if not ok or status ~= 200 then
      respond_json(404, "Not Found", { message = "Not Found" })
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
    if upok and (upstatus == 200 or upstatus == 204) then
      SetStatus(204, "No Content")
    elseif upok then
      respond_json(upstatus, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- GET /repos/{owner}/{repo}/labels
  get_repo_labels = proxy_handler(translate_gl_labels, function(o, r)
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
      respond_json(404, "Not Found", { message = "Label not found" })
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
      respond_json(404, "Not Found", { message = "Label not found" })
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
      respond_json(404, "Not Found", { message = "Label not found" })
      return
    end
    local dopts = auth() or {}
    dopts.method = "DELETE"
    local ok, status = pcall(
      Fetch,
      base() .. "/projects/" .. project_id(owner, repo_name) .. "/labels/" .. id,
      dopts
    )
    if ok and (status == 204 or status == 200) then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- Milestones ----------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/milestones
  get_repo_milestones = proxy_handler(translate_gl_milestones, function(o, r)
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
    if ok and (status == 204 or status == 200) then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- Assignees -----------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/assignees  (users eligible for assignment)
  get_repo_assignees = proxy_handler(translate_gl_members, function(o, r)
    return append_page_params(base() .. "/projects/" .. project_id(o, r) .. "/members/all", PAGES)
  end),
}
