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
local fetch_json = make_backend_transport("basic").fetch_json

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

local b = make_backend_builder()
b:rest("get_root", function()
  proxy_health_check(pcall(Fetch, base() .. "/repos", auth()))
end)

-- GET /repos/{owner}/{repo}: owner must be "codecommit".
-- CodeCommit returns 400 (RepositoryDoesNotExistException) for unknown repos;
-- map that to 404 for GitHub compatibility.
b:rest("get_repo", function(owner, repo_name)
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
end)

b:rest("get_repositories", function()
  if not check_page() then
    return
  end
  local per_page = tonumber(GetParam("per_page") or "") or nil
  local repos, _, status = list_repos_page(per_page)
  if not repos then
    respond_json(status, {})
    return
  end
  respond_json(200, translate_list(translate_repo, repos))
end)

-- GET /repos/{owner}/{repo}/branches: owner must be "codecommit".
b:rest("get_repo_branches", function(owner, repo_name)
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
end)

b:rest("search_repositories", function()
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
end)

b:build()
