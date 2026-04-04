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

  -- Branches ------------------------------------------------------------------
  get_repo_branches = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/branches",
        { per_page = "per_page", page = "page" })))
  end,

  get_repo_branch = function(owner, repo_name, branch)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/branches/" .. branch))
  end,

  -- Commits -------------------------------------------------------------------
  get_repo_commits = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/commits",
        { per_page = "per_page", page = "page" })))
  end,

  get_repo_commit = function(owner, repo_name, ref)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/commits/" .. ref))
  end,

  -- Statuses ------------------------------------------------------------------
  get_commit_statuses = function(owner, repo_name, ref)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/statuses/" .. ref,
        { per_page = "per_page", page = "page" })))
  end,

  get_commit_combined_status = function(owner, repo_name, ref)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/commits/" .. ref .. "/status"))
  end,

  post_commit_status = function(owner, repo_name, sha)
    proxy_json_created(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/statuses/" .. sha, "POST", GetBody()))
  end,

  -- Contents ------------------------------------------------------------------
  get_repo_readme = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/readme"))
  end,

  get_repo_readme_dir = function(owner, repo_name, dir)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/readme/" .. dir))
  end,

  get_repo_content = function(owner, repo_name, path)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/contents/" .. path))
  end,

  put_repo_content = function(owner, repo_name, path)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/contents/" .. path, "PUT", GetBody()))
  end,

  delete_repo_content = function(owner, repo_name, path)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/contents/" .. path, "DELETE", GetBody()))
  end,

  get_repo_tarball = function(owner, repo_name, ref)
    SetStatus(302, "Found")
    SetHeader("Location",
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/tarball/" .. ref)
    Write("")
  end,

  get_repo_zipball = function(owner, repo_name, ref)
    SetStatus(302, "Found")
    SetHeader("Location",
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/zipball/" .. ref)
    Write("")
  end,

  -- Compare -------------------------------------------------------------------
  get_repo_compare = function(owner, repo_name, basehead)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/compare/" .. basehead))
  end,

  -- Collaborators -------------------------------------------------------------
  get_repo_collaborators = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/collaborators",
        { per_page = "per_page", page = "page" })))
  end,

  get_repo_collaborator = function(owner, repo_name, username)
    local ok, status = pcall(Fetch,
      base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/collaborators/" .. username, auth())
    if ok and status == 204 then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Not Found", { message = "Not a collaborator" })
    else respond_json(503, "Service Unavailable", {}) end
  end,

  put_repo_collaborator = function(owner, repo_name, username)
    local ok, status = fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/collaborators/" .. username, "PUT", GetBody())
    if ok and (status == 204 or status == 201) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  delete_repo_collaborator = function(owner, repo_name, username)
    local ok, status = fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/collaborators/" .. username, "DELETE")
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_repo_collaborator_permission = function(owner, repo_name, username)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/collaborators/" .. username .. "/permission"))
  end,

  -- Forks ---------------------------------------------------------------------
  get_repo_forks = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/forks",
        { per_page = "per_page", page = "page" })))
  end,

  post_repo_forks = function(owner, repo_name)
    proxy_json_created(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/forks", "POST", GetBody()))
  end,

  -- Releases ------------------------------------------------------------------
  get_repo_releases = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases",
        { per_page = "per_page", page = "page" })))
  end,

  post_repo_releases = function(owner, repo_name)
    proxy_json_created(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/releases", "POST", GetBody()))
  end,

  get_repo_release_latest = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/latest"))
  end,

  get_repo_release_by_tag = function(owner, repo_name, tag)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/releases/tags/" .. tag))
  end,

  get_repo_release = function(owner, repo_name, release_id)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/releases/" .. release_id))
  end,

  patch_repo_release = function(owner, repo_name, release_id)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/releases/" .. release_id, "PATCH", GetBody()))
  end,

  delete_repo_release = function(owner, repo_name, release_id)
    local ok, status = fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/releases/" .. release_id, "DELETE")
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_repo_release_assets = function(owner, repo_name, release_id)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name ..
          "/releases/" .. release_id .. "/assets",
        { per_page = "per_page", page = "page" })))
  end,

  get_repo_release_asset = function(owner, repo_name, asset_id)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/releases/assets/" .. asset_id))
  end,

  patch_repo_release_asset = function(owner, repo_name, asset_id)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/releases/assets/" .. asset_id, "PATCH", GetBody()))
  end,

  delete_repo_release_asset = function(owner, repo_name, asset_id)
    local ok, status = fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/releases/assets/" .. asset_id, "DELETE")
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- Deploy keys ---------------------------------------------------------------
  get_repo_keys = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/keys",
        { per_page = "per_page", page = "page" })))
  end,

  post_repo_keys = function(owner, repo_name)
    proxy_json_created(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/keys", "POST", GetBody()))
  end,

  get_repo_key = function(owner, repo_name, key_id)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/keys/" .. key_id))
  end,

  delete_repo_key = function(owner, repo_name, key_id)
    local ok, status = fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/keys/" .. key_id, "DELETE")
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- Webhooks ------------------------------------------------------------------
  get_repo_hooks = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks",
        { per_page = "per_page", page = "page" })))
  end,

  post_repo_hooks = function(owner, repo_name)
    proxy_json_created(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/hooks", "POST", GetBody()))
  end,

  get_repo_hook = function(owner, repo_name, hook_id)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/hooks/" .. hook_id))
  end,

  patch_repo_hook = function(owner, repo_name, hook_id)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/hooks/" .. hook_id, "PATCH", GetBody()))
  end,

  delete_repo_hook = function(owner, repo_name, hook_id)
    local ok, status = fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/hooks/" .. hook_id, "DELETE")
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_repo_hook_config = function(owner, repo_name, hook_id)
    proxy_json(
      function(h) return h.config or {} end,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/hooks/" .. hook_id))
  end,

  patch_repo_hook_config = function(owner, repo_name, hook_id)
    local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id
    local ok, status, _, body = fetch_json(url)
    if not ok or status ~= 200 then
      if ok then respond_json(status, "Error", {}) else respond_json(503, "Service Unavailable", {}) end
      return
    end
    local hook = DecodeJson(body) or {}
    local new_cfg = DecodeJson(GetBody() or "{}")
    hook.config = hook.config or {}
    for k, v in pairs(new_cfg) do hook.config[k] = v end
    proxy_json(function(h) return h.config or {} end, fetch_json(url, "PATCH", EncodeJson(hook)))
  end,

  post_repo_hook_ping = function(owner, repo_name, hook_id)
    local ok, status = fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/hooks/" .. hook_id .. "/pings", "POST")
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  post_repo_hook_test = function(owner, repo_name, hook_id)
    local ok, status = fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/hooks/" .. hook_id .. "/tests", "POST")
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- Commit comments -----------------------------------------------------------
  get_repo_comments = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/comments",
        { per_page = "per_page", page = "page" })))
  end,

  get_repo_comment = function(owner, repo_name, comment_id)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/comments/" .. comment_id))
  end,

  patch_repo_comment = function(owner, repo_name, comment_id)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/comments/" .. comment_id, "PATCH", GetBody()))
  end,

  delete_repo_comment = function(owner, repo_name, comment_id)
    local ok, status = fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/comments/" .. comment_id, "DELETE")
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_commit_comments = function(owner, repo_name, commit_sha)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name ..
          "/commits/" .. commit_sha .. "/comments",
        { per_page = "per_page", page = "page" })))
  end,

  post_commit_comment = function(owner, repo_name, commit_sha)
    proxy_json_created(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/commits/" .. commit_sha .. "/comments", "POST", GetBody()))
  end,

  -- GET /users/{username}/repos + public repos --------------------------------
  get_users_repos = function(username)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/users/" .. username .. "/repos",
        { per_page = "per_page", page = "page" })))
  end,

  get_repositories = function()
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repositories",
        { per_page = "per_page", page = "page" })))
  end,
}
