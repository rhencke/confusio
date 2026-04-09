-- OneDev backend handler overrides.
-- Uses OneDev REST API at /~api/.
-- Projects are addressed by integer ID; owner/repo maps via path query.
if config.base_url == "" then
  config.base_url = "https://code.onedev.io"
end

local base = function()
  return config.base_url .. "/~api"
end
local auth = function()
  return make_fetch_opts("bearer")
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

-- Resolve owner/repo to a OneDev project ID by querying by path.
local function resolve_project_id(owner, repo_name)
  local path = owner ~= "" and (owner .. "/" .. repo_name) or repo_name
  -- OneDev query language: "Path" is "owner/repo"
  local query = "%22Path%22+is+%22" .. path .. "%22"
  local ok, status, _, body = fetch_json(base() .. "/projects?query=" .. query .. "&count=1")
  if not ok or status ~= 200 then
    return nil
  end
  local projects = DecodeJson(body) or {}
  return projects[1] and projects[1].id
end

-- Map a OneDev project object to GitHub format.
local function translate_onedev_repo(r)
  if not r then
    return {}
  end
  local path = r.path or r.name or ""
  local owner_part, name_part = path:match("^(.+)/([^/]+)$")
  if not owner_part then
    owner_part = ""
    name_part = path
  end
  return {
    id = r.id or 0,
    node_id = "",
    name = name_part,
    full_name = path,
    private = not (r.public or false),
    owner = {
      login = owner_part,
      id = 0,
      node_id = "",
      avatar_url = "",
      url = "",
      html_url = "",
      type = "User",
    },
    html_url = config.base_url .. "/" .. path,
    description = r.description,
    fork = r.forkedFrom ~= nil,
    url = "",
    clone_url = "",
    homepage = "",
    size = 0,
    stargazers_count = 0,
    watchers_count = 0,
    language = nil,
    has_issues = true,
    has_wiki = false,
    forks_count = 0,
    archived = false,
    disabled = false,
    open_issues_count = 0,
    default_branch = r.defaultBranch or "main",
    visibility = (r.public or false) and "public" or "private",
    forks = 0,
    open_issues = 0,
    watchers = 0,
    created_at = nil,
    updated_at = nil,
    pushed_at = nil,
  }
end

-- Translate GitHub create/update request body to OneDev format.
local function translate_onedev_req(body_str)
  local req = DecodeJson(body_str or "{}")
  local od = {}
  if req.name then
    od.name = req.name
  end
  if req.description then
    od.description = req.description
  end
  if req.private ~= nil then
    od.public = not req.private
  end
  return EncodeJson(od)
end

local function translate_onedev_repos(repos)
  repos = repos or {}
  for i, r in ipairs(repos) do
    repos[i] = translate_onedev_repo(r)
  end
  return repos
end

local proxy_handler = make_proxy_handler(fetch_json)

local function translate_onedev_user(u)
  if not u then
    return {}
  end
  return {
    login = u.name or "",
    id = u.id or 0,
    node_id = "",
    avatar_url = "",
    html_url = "",
    type = "User",
    site_admin = false,
    name = u.fullName or u.name or "",
    email = u.email or "",
  }
end

-- Translate a OneDev issue object to GitHub format.
-- OneDev: { id, number, title, state, description, project, submitter, submitDate, updateDate }
local function translate_onedev_issue(i)
  if not i then
    return {}
  end
  local project = i.project or {}
  local state = (i.state == "Open") and "open" or "closed"
  local number = i.number or i.id or 0
  return {
    id = i.id or 0,
    node_id = "",
    number = number,
    title = i.title or "",
    body = i.description or "",
    state = state,
    user = translate_onedev_user(i.submitter or {}),
    assignees = {},
    labels = {},
    milestone = nil,
    created_at = i.submitDate or "",
    updated_at = i.updateDate or i.submitDate or "",
    closed_at = nil,
    html_url = config.base_url .. "/" .. (project.path or "") .. "/issues/" .. number,
  }
end

-- Translate a OneDev issue comment to GitHub format.
-- OneDev: { id, issueId, user, content, date }
local function translate_onedev_issue_comment(c)
  if not c then
    return {}
  end
  return {
    id = c.id or 0,
    node_id = "",
    url = "",
    body = c.content or "",
    user = translate_onedev_user(c.user or {}),
    created_at = c.date or "",
    updated_at = c.date or "",
    html_url = "",
  }
end

-- Translate a OneDev branch object to GitHub format.
-- OneDev: { name, commitHash }
local function translate_onedev_branch(b)
  if not b then
    return {}
  end
  return {
    name = b.name,
    commit = { sha = b.commitHash or "", url = "" },
    protected = false,
  }
end

-- Translate a OneDev commit object to GitHub format.
-- OneDev: { hash, message, author: { name, emailAddress, date }, committer: {...} }
local function translate_onedev_commit(c)
  if not c then
    return {}
  end
  local author = c.author or {}
  local committer = c.committer or {}
  return {
    sha = c.hash or "",
    commit = {
      message = c.message or "",
      author = {
        name = author.name or "",
        email = author.emailAddress or "",
        date = author.date or "",
      },
      committer = {
        name = committer.name or "",
        email = committer.emailAddress or "",
        date = committer.date or "",
      },
    },
    author = { login = author.name or "", id = 0, avatar_url = "" },
    committer = { login = committer.name or "", id = 0, avatar_url = "" },
  }
end

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, base() .. "/server-version", auth())
    if ok and status == 200 then
      respond_json(200, {})
    else
      respond_json(503, {})
    end
  end,

  get_repo = function(owner, repo_name)
    local id = resolve_project_id(owner, repo_name)
    if not id then
      respond_json(404, { message = "Not Found" })
      return
    end
    proxy_json(translate_onedev_repo, fetch_json(base() .. "/projects/" .. id))
  end,

  patch_repo = function(owner, repo_name)
    local id = resolve_project_id(owner, repo_name)
    if not id then
      respond_json(404, { message = "Not Found" })
      return
    end
    proxy_json(
      translate_onedev_repo,
      fetch_json(base() .. "/projects/" .. id, "PATCH", translate_onedev_req(GetBody()))
    )
  end,

  delete_repo = function(owner, repo_name)
    local id = resolve_project_id(owner, repo_name)
    if not id then
      respond_json(404, { message = "Not Found" })
      return
    end
    local dopts = auth() or {}
    dopts.method = "DELETE"
    local ok, status = pcall(Fetch, base() .. "/projects/" .. id, dopts)
    if ok and (status == 200 or status == 204) then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, {})
    else
      respond_json(503, {})
    end
  end,

  get_user_repos = function()
    -- OneDev uses offset-based pagination: count=N, offset=(page-1)*N
    local count = tonumber(GetParam("per_page")) or 30
    local page = tonumber(GetParam("page")) or 1
    proxy_json(
      translate_onedev_repos,
      fetch_json(base() .. "/projects?count=" .. count .. "&offset=" .. ((page - 1) * count))
    )
  end,

  post_user_repos = function()
    proxy_json_created(
      translate_onedev_repo,
      fetch_json(base() .. "/projects", "POST", translate_onedev_req(GetBody()))
    )
  end,

  get_org_repos = function(org)
    -- OneDev groups/orgs map to parent projects; query by parent path.
    local query = "%22Parent%22+is+%22" .. org .. "%22"
    local count = tonumber(GetParam("per_page")) or 30
    local page = tonumber(GetParam("page")) or 1
    proxy_json(
      translate_onedev_repos,
      fetch_json(
        base()
          .. "/projects?query="
          .. query
          .. "&count="
          .. count
          .. "&offset="
          .. ((page - 1) * count)
      )
    )
  end,

  post_org_repos = function(org)
    local req = DecodeJson(GetBody() or "{}")
    local od = {
      name = req.name,
      description = req.description or "",
      public = not (req.private or false),
      parent = { path = org },
    }
    proxy_json_created(
      translate_onedev_repo,
      fetch_json(base() .. "/projects", "POST", EncodeJson(od))
    )
  end,

  -- Branches ------------------------------------------------------------------
  -- OneDev: GET /~api/projects/{id}/branches → [{ name, commitHash }]

  get_repo_branches = function(owner, repo_name)
    local id = resolve_project_id(owner, repo_name)
    if not id then
      respond_json(404, { message = "Not Found" })
      return
    end
    local count = tonumber(GetParam("per_page")) or 30
    local page = tonumber(GetParam("page")) or 1
    proxy_json(
      function(branches)
        branches = branches or {}
        for i, b in ipairs(branches) do
          branches[i] = translate_onedev_branch(b)
        end
        return branches
      end,
      fetch_json(
        base()
          .. "/projects/"
          .. id
          .. "/branches?count="
          .. count
          .. "&offset="
          .. ((page - 1) * count)
      )
    )
  end,

  get_repo_branch = function(owner, repo_name, branch)
    local id = resolve_project_id(owner, repo_name)
    if not id then
      respond_json(404, { message = "Not Found" })
      return
    end
    -- OneDev: GET /~api/projects/{id}/branches?query=name+is+{branch}&count=1
    local query = "%22Name%22+is+%22" .. branch .. "%22"
    proxy_json(function(branches)
      local b = (branches or {})[1]
      if not b then
        return {}
      end
      return translate_onedev_branch(b)
    end, fetch_json(base() .. "/projects/" .. id .. "/branches?query=" .. query .. "&count=1"))
  end,

  -- Commits -------------------------------------------------------------------
  -- OneDev: GET /~api/projects/{id}/commits?revision={ref}&count={n}&offset={offset}
  -- Returns [{ hash, message, author, committer }]

  get_repo_commits = function(owner, repo_name)
    local id = resolve_project_id(owner, repo_name)
    if not id then
      respond_json(404, { message = "Not Found" })
      return
    end
    local ref = GetParam("sha") or ""
    local count = tonumber(GetParam("per_page")) or 30
    local page = tonumber(GetParam("page")) or 1
    local url = base()
      .. "/projects/"
      .. id
      .. "/commits?count="
      .. count
      .. "&offset="
      .. ((page - 1) * count)
    if ref ~= "" then
      url = url .. "&revision=" .. ref
    end
    proxy_json(function(commits)
      commits = commits or {}
      for i, c in ipairs(commits) do
        commits[i] = translate_onedev_commit(c)
      end
      return commits
    end, fetch_json(url))
  end,

  get_repo_commit = function(owner, repo_name, ref)
    local id = resolve_project_id(owner, repo_name)
    if not id then
      respond_json(404, { message = "Not Found" })
      return
    end
    proxy_json(
      translate_onedev_commit,
      fetch_json(base() .. "/projects/" .. id .. "/commits/" .. ref)
    )
  end,

  -- Tags ----------------------------------------------------------------------

  get_repo_tags = function(owner, repo_name)
    local id = resolve_project_id(owner, repo_name)
    if not id then
      respond_json(404, { message = "Not Found" })
      return
    end
    -- OneDev returns [{ name, commitHash }]
    proxy_json(function(tags)
      tags = tags or {}
      local result = {}
      for _, t in ipairs(tags) do
        result[#result + 1] =
          { name = t.name or "", commit = { sha = t.commitHash or "", url = "" } }
      end
      return result
    end, fetch_json(base() .. "/projects/" .. id .. "/tags"))
  end,

  -- Contents ------------------------------------------------------------------
  -- OneDev: GET /~api/blobs/{projectId}/{revision}/{path}
  -- Returns raw file content; we wrap it in a GitHub-shaped object.

  get_repo_content = function(owner, repo_name, path)
    local id = resolve_project_id(owner, repo_name)
    if not id then
      respond_json(404, { message = "Not Found" })
      return
    end
    local ref = GetParam("ref") or "HEAD"
    local url = base() .. "/blobs/" .. id .. "/" .. ref .. "/" .. path
    local ok, status, _, body = fetch_json(url)
    if ok and status == 200 then
      respond_json(200, {
        type = "file",
        name = path:match("[^/]+$") or path,
        path = path,
        sha = "",
        size = #body,
        encoding = "base64",
        content = EncodeBase64(body),
      })
    elseif ok then
      respond_json(status, { message = "Error" })
    else
      respond_json(503, {})
    end
  end,

  -- Forks ---------------------------------------------------------------------

  post_repo_forks = function(owner, repo_name)
    local id = resolve_project_id(owner, repo_name)
    if not id then
      respond_json(404, { message = "Not Found" })
      return
    end
    proxy_json_created(
      translate_onedev_repo,
      fetch_json(base() .. "/projects/" .. id .. "/forks", "POST", GetBody())
    )
  end,

  -- Users' repos --------------------------------------------------------------

  get_users_repos = function(username)
    local query = "%22Owner%22+is+%22" .. username .. "%22"
    local count = tonumber(GetParam("per_page")) or 30
    local page = tonumber(GetParam("page")) or 1
    proxy_json(
      translate_onedev_repos,
      fetch_json(
        base()
          .. "/projects?query="
          .. query
          .. "&count="
          .. count
          .. "&offset="
          .. ((page - 1) * count)
      )
    )
  end,

  -- Public repos list ---------------------------------------------------------

  get_repositories = function()
    local query = "%22Public%22+is+%22true%22"
    local count = tonumber(GetParam("per_page")) or 30
    local page = tonumber(GetParam("page")) or 1
    proxy_json(
      translate_onedev_repos,
      fetch_json(
        base()
          .. "/projects?query="
          .. query
          .. "&count="
          .. count
          .. "&offset="
          .. ((page - 1) * count)
      )
    )
  end,

  -- Users ---------------------------------------------------------------------

  -- GET /users
  get_users = function()
    local count = GetParam("per_page") or "30"
    local page = tonumber(GetParam("page")) or 1
    local offset = (page - 1) * (tonumber(count) or 30)
    proxy_json(function(users)
      users = users or {}
      for i, u in ipairs(users) do
        users[i] = translate_onedev_user(u)
      end
      return users
    end, fetch_json(base() .. "/users?offset=" .. offset .. "&count=" .. count))
  end,

  -- GET /users/{username} — query by name, take first match
  get_users_username = proxy_handler(function(users)
    local u = (users and users[1]) or {}
    return translate_onedev_user(u)
  end, function(username)
    return base() .. "/users?query=name+is+%22" .. username .. "%22&count=1"
  end),

  -- Issues --------------------------------------------------------------------
  -- OneDev: GET /~api/issues?query="Project" is "owner/repo"&count=N&offset=O

  get_repo_issues = function(owner, repo_name)
    local path = owner ~= "" and (owner .. "/" .. repo_name) or repo_name
    local count = tonumber(GetParam("per_page")) or 30
    local page = tonumber(GetParam("page")) or 1
    local state = GetParam("state") or "open"
    local query = "%22Project%22+is+%22" .. path .. "%22"
    if state == "closed" then
      query = query .. "+%22State%22+is+%22Closed%22"
    elseif state ~= "all" then
      query = query .. "+%22State%22+is+%22Open%22"
    end
    proxy_json(
      function(issues)
        issues = issues or {}
        for i, iss in ipairs(issues) do
          issues[i] = translate_onedev_issue(iss)
        end
        return issues
      end,
      fetch_json(
        base()
          .. "/issues?query="
          .. query
          .. "&count="
          .. count
          .. "&offset="
          .. ((page - 1) * count)
      )
    )
  end,

  -- GET /repos/{owner}/{repo}/issues/{issue_number}
  -- OneDev: query by project path + per-project number, take first result.
  get_repo_issue = function(owner, repo_name, issue_number)
    local path = owner ~= "" and (owner .. "/" .. repo_name) or repo_name
    local query = "%22Project%22+is+%22"
      .. path
      .. "%22+%22Number%22+is+%22"
      .. issue_number
      .. "%22"
    local ok, status, _, body = fetch_json(base() .. "/issues?query=" .. query .. "&count=1")
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    local issues = DecodeJson(body) or {}
    if not issues[1] then
      respond_json(404, { message = "Not Found" })
      return
    end
    respond_json(200, translate_onedev_issue(issues[1]))
  end,

  -- POST /repos/{owner}/{repo}/issues
  post_repo_issues = function(owner, repo_name)
    local id = resolve_project_id(owner, repo_name)
    if not id then
      respond_json(404, { message = "Not Found" })
      return
    end
    local req = DecodeJson(GetBody() or "{}")
    local od = { projectId = id, title = req.title or "", description = req.body or "" }
    proxy_json_created(
      translate_onedev_issue,
      fetch_json(base() .. "/issues", "POST", EncodeJson(od))
    )
  end,

  -- GET /repos/{owner}/{repo}/issues/{issue_number}/comments
  -- OneDev: resolve global issue ID first, then query /~api/issue-comments.
  get_issue_comments = function(owner, repo_name, issue_number)
    local path = owner ~= "" and (owner .. "/" .. repo_name) or repo_name
    local nq = "%22Project%22+is+%22" .. path .. "%22+%22Number%22+is+%22" .. issue_number .. "%22"
    local ok, status, _, body = fetch_json(base() .. "/issues?query=" .. nq .. "&count=1")
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    local issues = DecodeJson(body) or {}
    if not issues[1] then
      respond_json(404, { message = "Not Found" })
      return
    end
    local issue_id = issues[1].id
    local count = tonumber(GetParam("per_page")) or 30
    local page = tonumber(GetParam("page")) or 1
    local cq = "%22Issue%22+is+%22" .. issue_id .. "%22"
    proxy_json(
      function(comments)
        comments = comments or {}
        for i, c in ipairs(comments) do
          comments[i] = translate_onedev_issue_comment(c)
        end
        return comments
      end,
      fetch_json(
        base()
          .. "/issue-comments?query="
          .. cq
          .. "&count="
          .. count
          .. "&offset="
          .. ((page - 1) * count)
      )
    )
  end,

  -- POST /repos/{owner}/{repo}/issues/{issue_number}/comments
  post_issue_comment = function(owner, repo_name, issue_number)
    local path = owner ~= "" and (owner .. "/" .. repo_name) or repo_name
    local nq = "%22Project%22+is+%22" .. path .. "%22+%22Number%22+is+%22" .. issue_number .. "%22"
    local ok, status, _, body = fetch_json(base() .. "/issues?query=" .. nq .. "&count=1")
    if not ok or status ~= 200 then
      respond_json(status or 503, {})
      return
    end
    local issues = DecodeJson(body) or {}
    if not issues[1] then
      respond_json(404, { message = "Not Found" })
      return
    end
    local issue_id = issues[1].id
    local req = DecodeJson(GetBody() or "{}")
    local od = { issueId = issue_id, content = req.body or "" }
    proxy_json_created(
      translate_onedev_issue_comment,
      fetch_json(base() .. "/issue-comments", "POST", EncodeJson(od))
    )
  end,

  -- Checks (via OneDev CI builds) -----------------------------------------------
  --
  -- OneDev CI builds are the natural mapping for GitHub Check Runs.
  --   • GET commits/{ref}/check-runs → query /~api/builds by project + commit hash.
  --   • POST check-runs              → stub (no API to push an external check status).
  --   • GET/PATCH by check_run_id   → minimal stub (would need a reverse-lookup).
  --   • Check Suites have no OneDev equivalent; all suite endpoints are stubs.
  --   • Annotations are always empty.
  --
  -- OneDev build status → GitHub status/conclusion mapping:
  --   WAITING    → status=queued,      conclusion=null
  --   RUNNING    → status=in_progress, conclusion=null
  --   SUCCESSFUL → status=completed,   conclusion=success
  --   FAILED     → status=completed,   conclusion=failure
  --   CANCELLED  → status=completed,   conclusion=cancelled
  --   TIMED_OUT  → status=completed,   conclusion=timed_out

  -- POST /repos/{owner}/{repo}/check-runs
  -- OneDev has no external check-status push API; return a minimal stub.
  post_check_runs = function(_owner, _repo_name)
    local req = DecodeJson(GetBody() or "{}") or {}
    respond_json(201, {
      id = 0,
      node_id = "",
      head_sha = req.head_sha or "",
      name = req.name or "",
      status = req.status or "queued",
      conclusion = req.conclusion,
      started_at = nil,
      completed_at = nil,
      output = {
        title = "",
        summary = "",
        text = "",
        annotations_count = 0,
        annotations_url = "",
      },
      url = "",
      html_url = "",
      details_url = req.details_url or "",
    })
  end,

  -- GET /repos/{owner}/{repo}/check-runs/{check_run_id}
  -- No reverse-lookup by ID without the commit SHA; return a minimal stub.
  get_check_run = function(_owner, _repo_name, check_run_id)
    respond_json(200, {
      id = tonumber(check_run_id) or 0,
      node_id = "",
      head_sha = "",
      name = "",
      status = "completed",
      conclusion = "success",
      started_at = nil,
      completed_at = nil,
      output = { title = "", summary = "", text = "", annotations_count = 0, annotations_url = "" },
      url = "",
      html_url = "",
      details_url = "",
    })
  end,

  -- PATCH /repos/{owner}/{repo}/check-runs/{check_run_id}
  -- Cannot update by ID alone; return a stub.
  patch_check_run = function(_owner, _repo_name, check_run_id)
    respond_json(200, {
      id = tonumber(check_run_id) or 0,
      node_id = "",
      head_sha = "",
      name = "",
      status = "completed",
      conclusion = "success",
      started_at = nil,
      completed_at = nil,
      output = { title = "", summary = "", text = "", annotations_count = 0, annotations_url = "" },
      url = "",
      html_url = "",
      details_url = "",
    })
  end,

  -- GET /repos/{owner}/{repo}/check-runs/{check_run_id}/annotations
  -- OneDev has no annotations concept; always return [].
  get_check_run_annotations = function(_owner, _repo_name, _check_run_id)
    set_preamble()
    Write("[]")
  end,

  -- POST /repos/{owner}/{repo}/check-runs/{check_run_id}/rerequest
  -- No OneDev equivalent; return 201 stub.
  post_check_run_rerequest = function(_owner, _repo_name, _check_run_id)
    respond_json(201, {})
  end,

  -- GET /repos/{owner}/{repo}/commits/{ref}/check-runs
  -- Maps to OneDev GET /~api/builds?query="Project" is "owner/repo" "Commit" is "{ref}".
  -- OneDev build objects: { id, number, jobName, status, commitHash, refName, project }
  get_commit_check_runs = function(owner, repo_name, ref)
    local path = owner ~= "" and (owner .. "/" .. repo_name) or repo_name
    local query = "%22Project%22+is+%22" .. path .. "%22+%22Commit%22+is+%22" .. ref .. "%22"
    local count = tonumber(GetParam("per_page")) or 30
    local page = tonumber(GetParam("page")) or 1
    local ok, status, _, body = fetch_json(
      base()
        .. "/builds?query="
        .. query
        .. "&count="
        .. count
        .. "&offset="
        .. ((page - 1) * count)
    )
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    local builds = DecodeJson(body) or {}
    local runs = {}
    for _, b in ipairs(builds) do
      local od_status = b.status or "WAITING"
      local od_to_gh = {
        WAITING = { status = "queued", conclusion = nil },
        RUNNING = { status = "in_progress", conclusion = nil },
        SUCCESSFUL = { status = "completed", conclusion = "success" },
        CANCELLED = { status = "completed", conclusion = "cancelled" },
        TIMED_OUT = { status = "completed", conclusion = "timed_out" },
      }
      local mapped = od_to_gh[od_status] or { status = "completed", conclusion = "failure" }
      local gh_status, gh_conclusion = mapped.status, mapped.conclusion
      runs[#runs + 1] = {
        id = b.id or 0,
        node_id = "",
        head_sha = b.commitHash or ref,
        name = b.jobName or tostring(b.number or b.id or 0),
        status = gh_status,
        conclusion = gh_conclusion,
        started_at = nil,
        completed_at = gh_status == "completed" and "" or nil,
        output = {
          title = b.jobName or "",
          summary = b.jobName or "",
          text = "",
          annotations_count = 0,
          annotations_url = "",
        },
        url = "",
        html_url = b.id and (config.base_url .. "/" .. path .. "/~builds/" .. (b.number or b.id))
          or "",
        details_url = "",
      }
    end
    respond_json(200, { total_count = #runs, check_runs = runs })
  end,

  -- Check Suites — no OneDev equivalent; all are stubs --------------------------

  -- POST /repos/{owner}/{repo}/check-suites
  post_check_suites = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}") or {}
    respond_json(201, {
      id = 0,
      node_id = "",
      head_sha = req.head_sha or "",
      status = "completed",
      conclusion = "success",
      app = { id = 0, slug = "", name = "" },
      repository = { full_name = owner .. "/" .. repo_name },
    })
  end,

  -- PATCH /repos/{owner}/{repo}/check-suites/preferences
  patch_check_suites_preferences = function(_owner, _repo_name) -- luacheck: ignore 212
    local req = DecodeJson(GetBody() or "{}") or {}
    respond_json(200, {
      preferences = req.auto_trigger_checks or {},
    })
  end,

  -- GET /repos/{owner}/{repo}/check-suites/{check_suite_id}
  get_check_suite = function(owner, repo_name, check_suite_id)
    respond_json(200, {
      id = tonumber(check_suite_id) or 0,
      node_id = "",
      head_sha = "",
      status = "completed",
      conclusion = "success",
      app = { id = 0, slug = "", name = "" },
      repository = { full_name = owner .. "/" .. repo_name },
    })
  end,

  -- GET /repos/{owner}/{repo}/check-suites/{check_suite_id}/check-runs
  get_check_suite_check_runs = function(_owner, _repo_name, _check_suite_id)
    respond_json(200, { total_count = 0, check_runs = {} })
  end,

  -- POST /repos/{owner}/{repo}/check-suites/{check_suite_id}/rerequest
  post_check_suite_rerequest = function(_owner, _repo_name, _check_suite_id)
    respond_json(201, {})
  end,

  -- GET /repos/{owner}/{repo}/commits/{ref}/check-suites
  get_commit_check_suites = function(_owner, _repo_name, _ref)
    respond_json(200, { total_count = 0, check_suites = {} })
  end,
  -- Migrations (https://docs.github.com/en/rest/migrations) ------------------
  -- OneDev has no org/user migration export API matching GitHub's stateful
  -- multi-repo model. All endpoints return fixed responses listed explicitly here.

  get_org_migrations = function()
    set_preamble()
    Write("[]")
  end,
  post_org_migrations = function()
    respond_json(501, { message = "Migrations are not supported by this backend." })
  end,
  get_org_migration = function()
    respond_json(404, { message = "Not Found" })
  end,
  get_org_migration_archive = function()
    respond_json(404, { message = "Not Found" })
  end,
  delete_org_migration_archive = function()
    respond_json(404, { message = "Not Found" })
  end,
  delete_org_migration_repo_lock = function()
    respond_json(404, { message = "Not Found" })
  end,
  get_org_migration_repos = function()
    set_preamble()
    Write("[]")
  end,
  get_user_migrations = function()
    set_preamble()
    Write("[]")
  end,
  post_user_migrations = function()
    respond_json(501, { message = "Migrations are not supported by this backend." })
  end,
  get_user_migration = function()
    respond_json(404, { message = "Not Found" })
  end,
  get_user_migration_archive = function()
    respond_json(404, { message = "Not Found" })
  end,
  delete_user_migration_archive = function()
    respond_json(404, { message = "Not Found" })
  end,
  delete_user_migration_repo_lock = function()
    respond_json(404, { message = "Not Found" })
  end,
  get_user_migration_repos = function()
    set_preamble()
    Write("[]")
  end,
}
