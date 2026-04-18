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
local _t = make_backend_transport("bearer")
local fetch_json = _t.fetch_json
local proxy_handler = _t.proxy_handler

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
  return translate_list(translate_onedev_repo, repos)
end

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

local b = make_backend_builder()
b:rest("get_root", function()
  proxy_health_check(pcall(Fetch, base() .. "/server-version", auth()))
end)

b:rest("get_repo", function(owner, repo_name)
  local id = resolve_project_id(owner, repo_name)
  if not id then
    respond_json(404, { message = "Not Found" })
    return
  end
  proxy_json(translate_onedev_repo, fetch_json(base() .. "/projects/" .. id))
end)

b:rest("patch_repo", function(owner, repo_name)
  local id = resolve_project_id(owner, repo_name)
  if not id then
    respond_json(404, { message = "Not Found" })
    return
  end
  proxy_json(
    translate_onedev_repo,
    fetch_json(base() .. "/projects/" .. id, "PATCH", translate_onedev_req(GetBody()))
  )
end)

b:rest("delete_repo", function(owner, repo_name)
  local id = resolve_project_id(owner, repo_name)
  if not id then
    respond_json(404, { message = "Not Found" })
    return
  end
  local dopts = auth() or {}
  dopts.method = "DELETE"
  proxy_204({ 200 }, pcall(Fetch, base() .. "/projects/" .. id, dopts))
end)

b:rest("get_user_repos", function()
  -- OneDev uses offset-based pagination: count=N, offset=(page-1)*N
  local count = tonumber(GetParam("per_page")) or 30
  local page = tonumber(GetParam("page")) or 1
  proxy_json(
    translate_onedev_repos,
    fetch_json(base() .. "/projects?count=" .. count .. "&offset=" .. ((page - 1) * count))
  )
end)

b:rest("post_user_repos", function()
  proxy_json_created(
    translate_onedev_repo,
    fetch_json(base() .. "/projects", "POST", translate_onedev_req(GetBody()))
  )
end)

b:rest("get_org_repos", function(org)
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
end)

b:rest("post_org_repos", function(org)
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
end)

-- Branches ------------------------------------------------------------------
-- OneDev: GET /~api/projects/{id}/branches → [{ name, commitHash }]

b:rest("get_repo_branches", function(owner, repo_name)
  local id = resolve_project_id(owner, repo_name)
  if not id then
    respond_json(404, { message = "Not Found" })
    return
  end
  local count = tonumber(GetParam("per_page")) or 30
  local page = tonumber(GetParam("page")) or 1
  proxy_json(
    function(branches)
      return translate_list(translate_onedev_branch, branches)
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
end)

b:rest("get_repo_branch", function(owner, repo_name, branch)
  local id = resolve_project_id(owner, repo_name)
  if not id then
    respond_json(404, { message = "Not Found" })
    return
  end
  -- OneDev: GET /~api/projects/{id}/branches?query=name+is+{branch}&count=1
  local query = "%22Name%22+is+%22" .. branch .. "%22"
  proxy_json(function(branches)
    local br = (branches or {})[1]
    if not br then
      return {}
    end
    return translate_onedev_branch(br)
  end, fetch_json(base() .. "/projects/" .. id .. "/branches?query=" .. query .. "&count=1"))
end)

-- Commits -------------------------------------------------------------------
-- OneDev: GET /~api/projects/{id}/commits?revision={ref}&count={n}&offset={offset}
-- Returns [{ hash, message, author, committer }]

b:rest("get_repo_commits", function(owner, repo_name)
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
    return translate_list(translate_onedev_commit, commits)
  end, fetch_json(url))
end)

b:rest("get_repo_commit", function(owner, repo_name, ref)
  local id = resolve_project_id(owner, repo_name)
  if not id then
    respond_json(404, { message = "Not Found" })
    return
  end
  proxy_json(
    translate_onedev_commit,
    fetch_json(base() .. "/projects/" .. id .. "/commits/" .. ref)
  )
end)

-- Tags ----------------------------------------------------------------------

b:rest("get_repo_tags", function(owner, repo_name)
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
      result[#result + 1] = { name = t.name or "", commit = { sha = t.commitHash or "", url = "" } }
    end
    return result
  end, fetch_json(base() .. "/projects/" .. id .. "/tags"))
end)

-- Contents ------------------------------------------------------------------
-- OneDev: GET /~api/blobs/{projectId}/{revision}/{path}
-- Returns raw file content; we wrap it in a GitHub-shaped object.

b:rest("get_repo_content", function(owner, repo_name, path)
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
end)

-- Forks ---------------------------------------------------------------------

b:rest("post_repo_forks", function(owner, repo_name)
  local id = resolve_project_id(owner, repo_name)
  if not id then
    respond_json(404, { message = "Not Found" })
    return
  end
  proxy_json_created(
    translate_onedev_repo,
    fetch_json(base() .. "/projects/" .. id .. "/forks", "POST", GetBody())
  )
end)

-- Users' repos --------------------------------------------------------------

b:rest("get_users_repos", function(username)
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
end)

-- Public repos list ---------------------------------------------------------

b:rest("get_repositories", function()
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
end)

-- Users ---------------------------------------------------------------------

-- GET /users
b:rest("get_users", function()
  local count = GetParam("per_page") or "30"
  local page = tonumber(GetParam("page")) or 1
  local offset = (page - 1) * (tonumber(count) or 30)
  proxy_json(function(users)
    return translate_list(translate_onedev_user, users)
  end, fetch_json(base() .. "/users?offset=" .. offset .. "&count=" .. count))
end)

-- GET /users/{username} — query by name, take first match
b:rest(
  "get_users_username",
  proxy_handler(function(users)
    local u = (users and users[1]) or {}
    return translate_onedev_user(u)
  end, function(username)
    return base() .. "/users?query=name+is+%22" .. username .. "%22&count=1"
  end)
)

-- Issues --------------------------------------------------------------------
-- OneDev: GET /~api/issues?query="Project" is "owner/repo"&count=N&offset=O

b:rest("get_repo_issues", function(owner, repo_name)
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
      return translate_list(translate_onedev_issue, issues)
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
end)

-- GET /repos/{owner}/{repo}/issues/{issue_number}
-- OneDev: query by project path + per-project number, take first result.
b:rest("get_repo_issue", function(owner, repo_name, issue_number)
  local path = owner ~= "" and (owner .. "/" .. repo_name) or repo_name
  local query = "%22Project%22+is+%22" .. path .. "%22+%22Number%22+is+%22" .. issue_number .. "%22"
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
end)

-- POST /repos/{owner}/{repo}/issues
b:rest("post_repo_issues", function(owner, repo_name)
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
end)

-- GET /repos/{owner}/{repo}/issues/{issue_number}/comments
-- OneDev: resolve global issue ID first, then query /~api/issue-comments.
b:rest("get_issue_comments", function(owner, repo_name, issue_number)
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
      return translate_list(translate_onedev_issue_comment, comments)
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
end)

-- POST /repos/{owner}/{repo}/issues/{issue_number}/comments
b:rest("post_issue_comment", function(owner, repo_name, issue_number)
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
end)

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
-- OneDev has no external check-status push API; falls back to route_default stub.

-- GET /repos/{owner}/{repo}/commits/{ref}/check-runs
-- Maps to OneDev GET /~api/builds?query="Project" is "owner/repo" "Commit" is "{ref}".
-- OneDev build objects: { id, number, jobName, status, commitHash, refName, project }
b:rest("get_commit_check_runs", function(owner, repo_name, ref)
  local path = owner ~= "" and (owner .. "/" .. repo_name) or repo_name
  local query = "%22Project%22+is+%22" .. path .. "%22+%22Commit%22+is+%22" .. ref .. "%22"
  local count = tonumber(GetParam("per_page")) or 30
  local page = tonumber(GetParam("page")) or 1
  local ok, status, _, body = fetch_json(
    base() .. "/builds?query=" .. query .. "&count=" .. count .. "&offset=" .. ((page - 1) * count)
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
  for _, br in ipairs(builds) do
    local od_status = br.status or "WAITING"
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
      id = br.id or 0,
      node_id = "",
      head_sha = br.commitHash or ref,
      name = br.jobName or tostring(br.number or br.id or 0),
      status = gh_status,
      conclusion = gh_conclusion,
      started_at = nil,
      completed_at = gh_status == "completed" and "" or nil,
      output = {
        title = br.jobName or "",
        summary = br.jobName or "",
        text = "",
        annotations_count = 0,
        annotations_url = "",
      },
      url = "",
      html_url = br.id and (config.base_url .. "/" .. path .. "/~builds/" .. (br.number or br.id))
        or "",
      details_url = "",
    }
  end
  respond_json(200, { total_count = #runs, check_runs = runs })
end)

b:build()
