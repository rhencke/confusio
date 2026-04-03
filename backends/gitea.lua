-- Gitea backend handler overrides.
-- Loaded by .init.lua when config.backend == "gitea".
-- Only endpoints that behave differently from the default need to be listed here.
-- Also dofile'd by API-compatible backends: forgejo, gogs, codeberg, notabug.

local base = function() return config.base_url .. "/api/v1" end
local auth = function() return make_fetch_opts("token") end

-- Thin wrappers that forward request body and headers for mutating calls.
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

local function translate_repos(repos)
  for i, r in ipairs(repos) do repos[i] = translate_repo(r) end
  return repos
end

backend_impl = {
  -- Health check
  get_root = function()
    local ok, status = pcall(Fetch, base() .. "/version", auth())
    if ok and status == 200 then respond_json(200, "OK", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_emojis = function() respond_json(404, "Not Found", { message = "Not Found" }) end,

  -- GET /repos/{owner}/{repo}
  get_repo = function(owner, repo_name)
    proxy_json(translate_repo, fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name))
  end,

  -- PATCH /repos/{owner}/{repo}
  patch_repo = function(owner, repo_name)
    proxy_json(translate_repo,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name, "PATCH", GetBody()))
  end,

  -- DELETE /repos/{owner}/{repo}
  delete_repo = function(owner, repo_name)
    local url = base() .. "/repos/" .. owner .. "/" .. repo_name
    local dopts = auth() or {}; dopts.method = "DELETE"
    local ok, status = pcall(Fetch, url, dopts)
    if ok and status == 204 then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- GET /user/repos
  get_user_repos = function()
    proxy_json(translate_repos,
      fetch_json(append_page_params(base() .. "/user/repos", { per_page = "limit", page = "page" })))
  end,

  -- POST /user/repos
  post_user_repos = function()
    proxy_json_created(translate_repo, fetch_json(base() .. "/user/repos", "POST", GetBody()))
  end,

  -- GET /orgs/{org}/repos
  get_org_repos = function(org)
    proxy_json(translate_repos,
      fetch_json(append_page_params(base() .. "/orgs/" .. org .. "/repos",
        { per_page = "limit", page = "page" })))
  end,

  -- POST /orgs/{org}/repos
  post_org_repos = function(org)
    proxy_json_created(translate_repo,
      fetch_json(base() .. "/orgs/" .. org .. "/repos", "POST", GetBody()))
  end,

  -- GET /repos/{owner}/{repo}/topics
  get_repo_topics = function(owner, repo_name)
    proxy_json(
      function(t) return { names = t.topics or t.names or {} } end,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/topics"))
  end,

  -- PUT /repos/{owner}/{repo}/topics
  put_repo_topics = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
    proxy_json(
      function(t) return { names = t.topics or t.names or {} } end,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/topics",
        "PUT", EncodeJson({ topics = req.names or {} })))
  end,

  -- GET /repos/{owner}/{repo}/languages
  -- Both Gitea and GitHub return { "Language": bytes } — pass through.
  get_repo_languages = function(owner, repo_name)
    proxy_json(nil, fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/languages"))
  end,

  -- GET /repos/{owner}/{repo}/contributors
  -- Gitea uses "contributions"; GitHub uses "contributions" — same key, pass through.
  get_repo_contributors = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/contributors",
        { per_page = "limit", page = "page" })))
  end,

  -- GET /repos/{owner}/{repo}/tags
  -- Both Gitea and GitHub return [{ name, commit: { sha, url }, ... }] — pass through.
  get_repo_tags = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/tags",
        { per_page = "limit", page = "page" })))
  end,

  -- GET /repos/{owner}/{repo}/teams
  -- Gitea does not expose repo-level team membership in the same way as GitHub.
  get_repo_teams = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,
}
