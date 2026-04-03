-- Gitbucket backend handler overrides.
-- Gitbucket exposes a GitHub-compatible API at /api/v3/ — responses can be
-- passed through with no field translation needed.

local base = function() return config.base_url .. "/api/v3" end
local auth = function() return make_fetch_opts("bearer") end

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

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, base() .. "/rate_limit", auth())
    if ok and status == 200 then respond_json(200, "OK", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_emojis = function() respond_json(404, "Not Found", { message = "Not Found" }) end,

  get_repo = function(owner, repo_name)
    proxy_json(nil, fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name))
  end,

  patch_repo = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name, "PATCH", GetBody()))
  end,

  delete_repo = function(owner, repo_name)
    local url = base() .. "/repos/" .. owner .. "/" .. repo_name
    local dopts = auth() or {}; dopts.method = "DELETE"
    local ok, status = pcall(Fetch, url, dopts)
    if ok and status == 204 then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_user_repos = function()
    proxy_json(nil,
      fetch_json(append_page_params(base() .. "/user/repos",
        { per_page = "per_page", page = "page" })))
  end,

  post_user_repos = function()
    proxy_json_created(nil, fetch_json(base() .. "/user/repos", "POST", GetBody()))
  end,

  get_org_repos = function(org)
    proxy_json(nil,
      fetch_json(append_page_params(base() .. "/orgs/" .. org .. "/repos",
        { per_page = "per_page", page = "page" })))
  end,

  post_org_repos = function(org)
    proxy_json_created(nil, fetch_json(base() .. "/orgs/" .. org .. "/repos", "POST", GetBody()))
  end,

  get_repo_topics = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/topics"))
  end,

  put_repo_topics = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/topics",
        "PUT", GetBody()))
  end,

  get_repo_languages = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/languages"))
  end,

  get_repo_contributors = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/contributors",
        { per_page = "per_page", page = "page" })))
  end,

  get_repo_tags = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/tags",
        { per_page = "per_page", page = "page" })))
  end,

  get_repo_teams = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/teams"))
  end,
}
