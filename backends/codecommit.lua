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

-- Fetch all repository summaries from /v1/repos, following nextToken pagination.
-- Returns a list of summary objects or nil + status code on failure.
local function list_all_repos()
  local result = {}
  local token = nil
  while true do
    local url = base() .. "/repos"
    if token then
      url = url .. "?nextToken=" .. token
    end
    local ok, status, _, body = fetch_json(url)
    if not ok then
      return nil, 503
    end
    if status ~= 200 then
      return nil, status
    end
    local data = DecodeJson(body) or {}
    for _, r in ipairs(data.repositories or {}) do
      result[#result + 1] = r
    end
    if not data.nextToken or data.nextToken == "" then
      break
    end
    token = data.nextToken
  end
  return result, 200
end

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, base() .. "/repos", auth())
    if ok and status == 200 then
      respond_json(200, "OK", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- GET /repos/{owner}/{repo}: owner must be "codecommit".
  -- CodeCommit returns 400 (RepositoryDoesNotExistException) for unknown repos;
  -- map that to 404 for GitHub compatibility.
  get_repo = function(owner, repo_name)
    if owner ~= "codecommit" then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    local ok, status, _, body = fetch_json(base() .. "/repos/" .. repo_name)
    if not ok then
      respond_json(503, "Service Unavailable", {})
      return
    end
    if status == 400 then
      local err = DecodeJson(body) or {}
      if (err["__type"] or ""):find("DoesNotExist") then
        respond_json(404, "Not Found", { message = "Not Found" })
        return
      end
    end
    if status ~= 200 then
      respond_json(status, "Error", {})
      return
    end
    local data = DecodeJson(body) or {}
    local r = data.repositoryMetadata
    if not r then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    respond_json(200, "OK", translate_repo(r))
  end,

  get_repositories = function()
    local repos, status = list_all_repos()
    if not repos then
      respond_json(status, "Error", {})
      return
    end
    local result = {}
    for _, r in ipairs(repos) do
      result[#result + 1] = translate_repo(r)
    end
    respond_json(200, "OK", result)
  end,

  -- GET /repos/{owner}/{repo}/branches: owner must be "codecommit".
  get_repo_branches = function(owner, repo_name)
    if owner ~= "codecommit" then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    local ok, status, _, body = fetch_json(base() .. "/repos/" .. repo_name .. "/branches")
    if not ok then
      respond_json(503, "Service Unavailable", {})
      return
    end
    if status ~= 200 then
      respond_json(status, "Error", {})
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
    respond_json(200, "OK", result)
  end,

  search_repositories = function()
    local q = (GetParam("q") or ""):lower()
    local repos, status = list_all_repos()
    if not repos then
      respond_json(status, "Error", {})
      return
    end
    local items = {}
    for _, r in ipairs(repos) do
      local name = (r.repositoryName or ""):lower()
      if q == "" or name:find(q, 1, true) then
        items[#items + 1] = translate_repo(r)
      end
    end
    respond_json(200, "OK", { total_count = #items, incomplete_results = false, items = items })
  end,
}
