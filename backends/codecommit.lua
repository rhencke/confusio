-- AWS CodeCommit backend handler overrides.
-- Uses AWS CodeCommit REST API v1.
-- CodeCommit has no owner/org concept; the GitHub {owner} segment must always
-- be "codecommit". All repos are scoped to an AWS account.
if config.base_url == "" then
  config.base_url = "https://codecommit.us-east-1.amazonaws.com"
end

local base = function()
  return config.base_url .. "/v1"
end

local auth = function()
  return make_fetch_opts("basic")
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

-- Translate a CodeCommit repositoryMetadata (or summary) object to GitHub format.
local function translate_repo(r)
  if not r then
    return {}
  end
  local name = r.repositoryName or ""
  return {
    id = 0,
    node_id = r.repositoryId or "",
    name = name,
    full_name = name,
    private = true,
    owner = {
      login = r.accountId or "",
      id = 0,
      node_id = "",
      avatar_url = "",
      url = "",
      html_url = "",
      type = "Organization",
    },
    html_url = r.cloneUrlHttp or "",
    description = r.repositoryDescription,
    fork = false,
    url = "",
    clone_url = r.cloneUrlHttp or "",
    homepage = "",
    size = 0,
    stargazers_count = 0,
    watchers_count = 0,
    language = nil,
    has_issues = false,
    has_wiki = false,
    forks_count = 0,
    archived = false,
    disabled = false,
    open_issues_count = 0,
    default_branch = r.defaultBranch or "main",
    visibility = "private",
    forks = 0,
    open_issues = 0,
    watchers = 0,
    created_at = r.creationDate and tostring(r.creationDate) or nil,
    updated_at = r.lastModifiedDate and tostring(r.lastModifiedDate) or nil,
    pushed_at = r.lastModifiedDate and tostring(r.lastModifiedDate) or nil,
  }
end

-- Fetch one page of repository summaries from /v1/repos.
-- max_results: optional integer to pass as maxResults to CodeCommit.
-- Returns repos list, incomplete (bool), and status code.
local function list_repos_page(max_results)
  local url = base() .. "/repos"
  if max_results then
    url = url .. "?maxResults=" .. max_results
  end
  local ok, status, _, body = fetch_json(url)
  if not ok then
    return nil, false, 503
  end
  if status ~= 200 then
    return nil, false, status
  end
  local data = DecodeJson(body) or {}
  local incomplete = data.nextToken ~= nil and data.nextToken ~= ""
  return data.repositories or {}, incomplete, 200
end

-- Error if the caller requested page > 1 (CodeCommit uses cursor-based pagination;
-- arbitrary page offsets are not supported).
local function check_page()
  local page = tonumber(GetParam("page") or "1") or 1
  if page > 1 then
    respond_json(422, {
      message = "CodeCommit uses cursor-based pagination; only page=1 is supported",
    })
    return false
  end
  return true
end

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, base() .. "/repos", auth())
    if ok and status == 200 then
      respond_json(200, {})
    else
      respond_json(503, {})
    end
  end,

  -- GET /repos/{owner}/{repo}: owner must be "codecommit".
  -- CodeCommit returns 400 (RepositoryDoesNotExistException) for unknown repos;
  -- map that to 404 for GitHub compatibility.
  get_repo = function(owner, repo_name)
    if owner ~= "codecommit" then
      respond_json(404, { message = "Not Found" })
      return
    end
    local ok, status, _, body = fetch_json(base() .. "/repos/" .. repo_name)
    if not ok then
      respond_json(503, {})
      return
    end
    if status == 400 then
      local err = DecodeJson(body) or {}
      if (err["__type"] or ""):find("DoesNotExist") then
        respond_json(404, { message = "Not Found" })
        return
      end
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    local data = DecodeJson(body) or {}
    local r = data.repositoryMetadata
    if not r then
      respond_json(404, { message = "Not Found" })
      return
    end
    respond_json(200, translate_repo(r))
  end,

  get_repositories = function()
    if not check_page() then
      return
    end
    local per_page = tonumber(GetParam("per_page") or "") or nil
    local repos, _, status = list_repos_page(per_page)
    if not repos then
      respond_json(status, {})
      return
    end
    local result = {}
    for _, r in ipairs(repos) do
      result[#result + 1] = translate_repo(r)
    end
    respond_json(200, result)
  end,

  -- GET /repos/{owner}/{repo}/branches: owner must be "codecommit".
  get_repo_branches = function(owner, repo_name)
    if owner ~= "codecommit" then
      respond_json(404, { message = "Not Found" })
      return
    end
    local ok, status, _, body = fetch_json(base() .. "/repos/" .. repo_name .. "/branches")
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    local data = DecodeJson(body) or {}
    local result = {}
    for _, branch_name in ipairs(data.branches or {}) do
      result[#result + 1] = {
        name = branch_name,
        commit = { sha = "", url = "" },
        protected = false,
      }
    end
    respond_json(200, result)
  end,

  search_repositories = function()
    if not check_page() then
      return
    end
    local q = (GetParam("q") or ""):lower()
    local per_page = tonumber(GetParam("per_page") or "") or nil
    local repos, incomplete, status = list_repos_page(per_page)
    if not repos then
      respond_json(status, {})
      return
    end
    local items = {}
    for _, r in ipairs(repos) do
      local name = (r.repositoryName or ""):lower()
      if q == "" or name:find(q, 1, true) then
        items[#items + 1] = translate_repo(r)
      end
    end
    respond_json(200, { total_count = #items, incomplete_results = incomplete, items = items })
  end,

  -- Checks — CodeCommit has no CI build system; all check endpoints are stubs -

  -- POST /repos/{owner}/{repo}/check-runs
  post_check_runs = function(_owner, _repo_name)
    local req = DecodeJson(GetBody() or "{}")
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
        title = (req.output and req.output.title) or "",
        summary = (req.output and req.output.summary) or "",
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
  get_check_run_annotations = function(_owner, _repo_name, _check_run_id)
    set_preamble()
    Write("[]")
  end,

  -- POST /repos/{owner}/{repo}/check-runs/{check_run_id}/rerequest
  post_check_run_rerequest = function(_owner, _repo_name, _check_run_id)
    respond_json(201, {})
  end,

  -- GET /repos/{owner}/{repo}/commits/{ref}/check-runs
  -- CodeCommit has no CI build system; always return empty.
  get_commit_check_runs = function(_owner, _repo_name, _ref)
    respond_json(200, { total_count = 0, check_runs = {} })
  end,

  -- Check Suites — no CodeCommit equivalent; all are stubs -------------------

  -- POST /repos/{owner}/{repo}/check-suites
  post_check_suites = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
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
}

-- Code scanning: CodeCommit has no native code scanning API.
-- List endpoints return empty collections; per-resource endpoints return 501.
local _b = backend_impl

_b.list_org_code_scanning_alerts = function(_org)
  respond_json(200, {})
end

_b.list_repo_code_scanning_alerts = function(_owner, _repo)
  respond_json(200, {})
end

_b.list_code_scanning_alert_instances = function(_owner, _repo, _alert_number)
  respond_json(200, {})
end

_b.list_code_scanning_analyses = function(_owner, _repo)
  respond_json(200, {})
end
