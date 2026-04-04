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

local function set_204_or_error(method, url)
  local opts = auth() or {}; opts.method = method
  local ok, status = pcall(Fetch, url, opts)
  if ok and status == 204 then SetStatus(204, "No Content")
  elseif ok then respond_json(status, "Error", {})
  else respond_json(503, "Service Unavailable", {}) end
end

local proxy_handler = make_proxy_handler(fetch_json)

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, base() .. "/rate_limit", auth())
    if ok and status == 200 then respond_json(200, "OK", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_repo = proxy_handler(nil, function(o, r) return base().."/repos/"..o.."/"..r end),

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

  get_user_repos = proxy_handler(nil, function()
    return append_page_params(base().."/user/repos", {per_page="per_page",page="page"})
  end),

  post_user_repos = function()
    proxy_json_created(nil, fetch_json(base() .. "/user/repos", "POST", GetBody()))
  end,

  get_org_repos = proxy_handler(nil, function(org)
    return append_page_params(base().."/orgs/"..org.."/repos", {per_page="per_page",page="page"})
  end),

  post_org_repos = function(org)
    proxy_json_created(nil, fetch_json(base() .. "/orgs/" .. org .. "/repos", "POST", GetBody()))
  end,

  get_repo_topics = proxy_handler(nil, function(o, r)
    return base().."/repos/"..o.."/"..r.."/topics"
  end),

  put_repo_topics = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/topics",
        "PUT", GetBody()))
  end,

  get_repo_languages = proxy_handler(nil, function(o, r)
    return base().."/repos/"..o.."/"..r.."/languages"
  end),

  get_repo_contributors = proxy_handler(nil, function(o, r)
    return append_page_params(base().."/repos/"..o.."/"..r.."/contributors",
      {per_page="per_page",page="page"})
  end),

  get_repo_tags = proxy_handler(nil, function(o, r)
    return append_page_params(base().."/repos/"..o.."/"..r.."/tags",
      {per_page="per_page",page="page"})
  end),

  get_repo_teams = proxy_handler(nil, function(o, r)
    return base().."/repos/"..o.."/"..r.."/teams"
  end),

  -- Branches ------------------------------------------------------------------
  get_repo_branches = proxy_handler(nil, function(o, r)
    return append_page_params(base().."/repos/"..o.."/"..r.."/branches",
      {per_page="per_page",page="page"})
  end),

  get_repo_branch = proxy_handler(nil, function(o, r, branch)
    return base().."/repos/"..o.."/"..r.."/branches/"..branch
  end),

  -- Commits -------------------------------------------------------------------
  get_repo_commits = proxy_handler(nil, function(o, r)
    return append_page_params(base().."/repos/"..o.."/"..r.."/commits",
      {per_page="per_page",page="page"})
  end),

  get_repo_commit = proxy_handler(nil, function(o, r, ref)
    return base().."/repos/"..o.."/"..r.."/commits/"..ref
  end),

  -- Statuses ------------------------------------------------------------------
  get_commit_statuses = proxy_handler(nil, function(o, r, ref)
    return append_page_params(base().."/repos/"..o.."/"..r.."/statuses/"..ref,
      {per_page="per_page",page="page"})
  end),

  get_commit_combined_status = proxy_handler(nil, function(o, r, ref)
    return base().."/repos/"..o.."/"..r.."/commits/"..ref.."/status"
  end),

  post_commit_status = function(owner, repo_name, sha)
    proxy_json_created(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/statuses/" .. sha, "POST", GetBody()))
  end,

  -- Contents ------------------------------------------------------------------
  get_repo_readme = proxy_handler(nil, function(o, r)
    return base().."/repos/"..o.."/"..r.."/readme"
  end),

  get_repo_readme_dir = proxy_handler(nil, function(o, r, dir)
    return base().."/repos/"..o.."/"..r.."/readme/"..dir
  end),

  get_repo_content = proxy_handler(nil, function(o, r, path)
    return base().."/repos/"..o.."/"..r.."/contents/"..path
  end),

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
  get_repo_compare = proxy_handler(nil, function(o, r, basehead)
    return base().."/repos/"..o.."/"..r.."/compare/"..basehead
  end),

  -- Collaborators -------------------------------------------------------------
  get_repo_collaborators = proxy_handler(nil, function(o, r)
    return append_page_params(base().."/repos/"..o.."/"..r.."/collaborators",
      {per_page="per_page",page="page"})
  end),

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

  get_repo_collaborator_permission = proxy_handler(nil, function(o, r, username)
    return base().."/repos/"..o.."/"..r.."/collaborators/"..username.."/permission"
  end),

  -- Forks ---------------------------------------------------------------------
  get_repo_forks = proxy_handler(nil, function(o, r)
    return append_page_params(base().."/repos/"..o.."/"..r.."/forks",
      {per_page="per_page",page="page"})
  end),

  post_repo_forks = function(owner, repo_name)
    proxy_json_created(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/forks", "POST", GetBody()))
  end,

  -- Releases ------------------------------------------------------------------
  get_repo_releases = proxy_handler(nil, function(o, r)
    return append_page_params(base().."/repos/"..o.."/"..r.."/releases",
      {per_page="per_page",page="page"})
  end),

  post_repo_releases = function(owner, repo_name)
    proxy_json_created(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/releases", "POST", GetBody()))
  end,

  get_repo_release_latest = proxy_handler(nil, function(o, r)
    return base().."/repos/"..o.."/"..r.."/releases/latest"
  end),

  get_repo_release_by_tag = proxy_handler(nil, function(o, r, tag)
    return base().."/repos/"..o.."/"..r.."/releases/tags/"..tag
  end),

  get_repo_release = proxy_handler(nil, function(o, r, id)
    return base().."/repos/"..o.."/"..r.."/releases/"..id
  end),

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

  get_repo_release_assets = proxy_handler(nil, function(o, r, id)
    return append_page_params(base().."/repos/"..o.."/"..r.."/releases/"..id.."/assets",
      {per_page="per_page",page="page"})
  end),

  get_repo_release_asset = proxy_handler(nil, function(o, r, asset_id)
    return base().."/repos/"..o.."/"..r.."/releases/assets/"..asset_id
  end),

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
  get_repo_keys = proxy_handler(nil, function(o, r)
    return append_page_params(base().."/repos/"..o.."/"..r.."/keys",
      {per_page="per_page",page="page"})
  end),

  post_repo_keys = function(owner, repo_name)
    proxy_json_created(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/keys", "POST", GetBody()))
  end,

  get_repo_key = proxy_handler(nil, function(o, r, key_id)
    return base().."/repos/"..o.."/"..r.."/keys/"..key_id
  end),

  delete_repo_key = function(owner, repo_name, key_id)
    local ok, status = fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/keys/" .. key_id, "DELETE")
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- Webhooks ------------------------------------------------------------------
  get_repo_hooks = proxy_handler(nil, function(o, r)
    return append_page_params(base().."/repos/"..o.."/"..r.."/hooks",
      {per_page="per_page",page="page"})
  end),

  post_repo_hooks = function(owner, repo_name)
    proxy_json_created(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/hooks", "POST", GetBody()))
  end,

  get_repo_hook = proxy_handler(nil, function(o, r, hook_id)
    return base().."/repos/"..o.."/"..r.."/hooks/"..hook_id
  end),

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

  get_repo_hook_config = proxy_handler(
    function(h) return h.config or {} end,
    function(o, r, hook_id) return base().."/repos/"..o.."/"..r.."/hooks/"..hook_id end),

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
  get_repo_comments = proxy_handler(nil, function(o, r)
    return append_page_params(base().."/repos/"..o.."/"..r.."/comments",
      {per_page="per_page",page="page"})
  end),

  get_repo_comment = proxy_handler(nil, function(o, r, comment_id)
    return base().."/repos/"..o.."/"..r.."/comments/"..comment_id
  end),

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

  get_commit_comments = proxy_handler(nil, function(o, r, sha)
    return append_page_params(base().."/repos/"..o.."/"..r.."/commits/"..sha.."/comments",
      {per_page="per_page",page="page"})
  end),

  post_commit_comment = function(owner, repo_name, commit_sha)
    proxy_json_created(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/commits/" .. commit_sha .. "/comments", "POST", GetBody()))
  end,

  -- GET /users/{username}/repos + public repos --------------------------------
  get_users_repos = proxy_handler(nil, function(username)
    return append_page_params(base().."/users/"..username.."/repos",
      {per_page="per_page",page="page"})
  end),

  get_repositories = proxy_handler(nil, function()
    return append_page_params(base().."/repositories", {per_page="per_page",page="page"})
  end),

  -- Users (GitHub-compatible passthrough) -------------------------------------

  get_user = proxy_handler(nil, function() return base().."/user" end),

  patch_user = function()
    proxy_json(nil, fetch_json(base() .. "/user", "PATCH", GetBody()))
  end,

  get_users_username = proxy_handler(nil, function(username)
    return base().."/users/"..username
  end),

  get_users = proxy_handler(nil, function()
    return append_page_params(base().."/users", {per_page="per_page",page="page"})
  end),

  get_user_followers = proxy_handler(nil, function()
    return append_page_params(base().."/user/followers", {per_page="per_page",page="page"})
  end),

  get_user_following = proxy_handler(nil, function()
    return append_page_params(base().."/user/following", {per_page="per_page",page="page"})
  end),

  get_user_is_following = function(username)
    local ok, status = pcall(Fetch, base() .. "/user/following/" .. username, auth())
    if ok and status == 204 then SetStatus(204, "No Content")
    elseif ok then respond_json(404, "Not Found", { message = "Not Following" })
    else respond_json(503, "Service Unavailable", {}) end
  end,

  put_user_following = function(username)
    set_204_or_error("PUT", base() .. "/user/following/" .. username)
  end,

  delete_user_following = function(username)
    set_204_or_error("DELETE", base() .. "/user/following/" .. username)
  end,

  get_users_followers = proxy_handler(nil, function(username)
    return append_page_params(base().."/users/"..username.."/followers",
      {per_page="per_page",page="page"})
  end),

  get_users_following = proxy_handler(nil, function(username)
    return append_page_params(base().."/users/"..username.."/following",
      {per_page="per_page",page="page"})
  end),

  get_users_is_following = function(username, target)
    local ok, status = pcall(Fetch,
      base() .. "/users/" .. username .. "/following/" .. target, auth())
    if ok and status == 204 then SetStatus(204, "No Content")
    elseif ok then respond_json(404, "Not Found", { message = "Not Following" })
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_user_emails = proxy_handler(nil, function() return base().."/user/emails" end),

  post_user_emails = function()
    proxy_json_created(nil, fetch_json(base() .. "/user/emails", "POST", GetBody()))
  end,

  delete_user_emails = function()
    local opts = auth() or {}
    opts.method = "DELETE"; opts.body = GetBody()
    opts.headers = opts.headers or {}
    opts.headers["Content-Type"] = "application/json"
    local ok, status = pcall(Fetch, base() .. "/user/emails", opts)
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_user_keys = proxy_handler(nil, function()
    return append_page_params(base().."/user/keys", {per_page="per_page",page="page"})
  end),

  post_user_keys = function()
    proxy_json_created(nil, fetch_json(base() .. "/user/keys", "POST", GetBody()))
  end,

  get_user_key = proxy_handler(nil, function(key_id) return base().."/user/keys/"..key_id end),

  delete_user_key = function(key_id)
    local opts = auth() or {}; opts.method = "DELETE"
    local ok, status = pcall(Fetch, base() .. "/user/keys/" .. key_id, opts)
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_users_keys = proxy_handler(nil, function(username)
    return append_page_params(base().."/users/"..username.."/keys",
      {per_page="per_page",page="page"})
  end),

  -- Teams (GitHub-compatible passthrough) -------------------------------------

  get_org_teams = proxy_handler(nil, function(org)
    return append_page_params(base().."/orgs/"..org.."/teams",
      {per_page="per_page",page="page"})
  end),

  post_org_teams = function(org)
    proxy_json_created(nil, fetch_json(base().."/orgs/"..org.."/teams", "POST", GetBody()))
  end,

  get_org_team = proxy_handler(nil, function(org, slug)
    return base().."/orgs/"..org.."/teams/"..slug
  end),

  patch_org_team = function(org, slug)
    proxy_json(nil, fetch_json(base().."/orgs/"..org.."/teams/"..slug, "PATCH", GetBody()))
  end,

  delete_org_team = function(org, slug)
    local ok, status = fetch_json(base().."/orgs/"..org.."/teams/"..slug, "DELETE")
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_org_team_invitations = proxy_handler(nil, function(org, slug)
    return append_page_params(base().."/orgs/"..org.."/teams/"..slug.."/invitations",
      {per_page="per_page",page="page"})
  end),

  get_org_team_members = proxy_handler(nil, function(org, slug)
    return append_page_params(base().."/orgs/"..org.."/teams/"..slug.."/members",
      {per_page="per_page",page="page"})
  end),

  get_org_team_membership = proxy_handler(nil, function(org, slug, username)
    return base().."/orgs/"..org.."/teams/"..slug.."/memberships/"..username
  end),

  put_org_team_membership = function(org, slug, username)
    proxy_json(nil,
      fetch_json(base().."/orgs/"..org.."/teams/"..slug.."/memberships/"..username,
        "PUT", GetBody()))
  end,

  delete_org_team_membership = function(org, slug, username)
    local ok, status = fetch_json(
      base().."/orgs/"..org.."/teams/"..slug.."/memberships/"..username, "DELETE")
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_org_team_repos = proxy_handler(nil, function(org, slug)
    return append_page_params(base().."/orgs/"..org.."/teams/"..slug.."/repos",
      {per_page="per_page",page="page"})
  end),

  get_org_team_repo = proxy_handler(nil, function(org, slug, owner, repo_name)
    return base().."/orgs/"..org.."/teams/"..slug.."/repos/"..owner.."/"..repo_name
  end),

  put_org_team_repo = function(org, slug, owner, repo_name)
    local ok, status = fetch_json(
      base().."/orgs/"..org.."/teams/"..slug.."/repos/"..owner.."/"..repo_name,
      "PUT", GetBody())
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  delete_org_team_repo = function(org, slug, owner, repo_name)
    local ok, status = fetch_json(
      base().."/orgs/"..org.."/teams/"..slug.."/repos/"..owner.."/"..repo_name, "DELETE")
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_org_team_children = proxy_handler(nil, function(org, slug)
    return append_page_params(base().."/orgs/"..org.."/teams/"..slug.."/teams",
      {per_page="per_page",page="page"})
  end),

  -- Legacy team-by-id API (/teams/{team_id}) ------------------------------------

  get_user_teams = proxy_handler(nil, function()
    return append_page_params(base().."/user/teams", {per_page="per_page",page="page"})
  end),

  get_team = proxy_handler(nil, function(team_id)
    return base().."/teams/"..team_id
  end),

  patch_team = function(team_id)
    proxy_json(nil, fetch_json(base().."/teams/"..team_id, "PATCH", GetBody()))
  end,

  delete_team = function(team_id)
    local ok, status = fetch_json(base().."/teams/"..team_id, "DELETE")
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_team_invitations = proxy_handler(nil, function(team_id)
    return append_page_params(base().."/teams/"..team_id.."/invitations",
      {per_page="per_page",page="page"})
  end),

  get_team_members = proxy_handler(nil, function(team_id)
    return append_page_params(base().."/teams/"..team_id.."/members",
      {per_page="per_page",page="page"})
  end),

  get_team_member = function(team_id, username)
    local ok, status = pcall(Fetch,
      base().."/teams/"..team_id.."/members/"..username, auth())
    if ok and status == 204 then SetStatus(204, "No Content")
    elseif ok then respond_json(404, "Not Found", { message = "Not Found" })
    else respond_json(503, "Service Unavailable", {}) end
  end,

  put_team_member = function(team_id, username)
    set_204_or_error("PUT", base().."/teams/"..team_id.."/members/"..username)
  end,

  delete_team_member = function(team_id, username)
    set_204_or_error("DELETE", base().."/teams/"..team_id.."/members/"..username)
  end,

  get_team_membership = proxy_handler(nil, function(team_id, username)
    return base().."/teams/"..team_id.."/memberships/"..username
  end),

  put_team_membership = function(team_id, username)
    proxy_json(nil,
      fetch_json(base().."/teams/"..team_id.."/memberships/"..username,
        "PUT", GetBody()))
  end,

  delete_team_membership = function(team_id, username)
    local ok, status = fetch_json(
      base().."/teams/"..team_id.."/memberships/"..username, "DELETE")
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_team_repos = proxy_handler(nil, function(team_id)
    return append_page_params(base().."/teams/"..team_id.."/repos",
      {per_page="per_page",page="page"})
  end),

  get_team_repo = proxy_handler(nil, function(team_id, owner, repo_name)
    return base().."/teams/"..team_id.."/repos/"..owner.."/"..repo_name
  end),

  put_team_repo = function(team_id, owner, repo_name)
    local ok, status = fetch_json(
      base().."/teams/"..team_id.."/repos/"..owner.."/"..repo_name,
      "PUT", GetBody())
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  delete_team_repo = function(team_id, owner, repo_name)
    local ok, status = fetch_json(
      base().."/teams/"..team_id.."/repos/"..owner.."/"..repo_name, "DELETE")
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_team_children = proxy_handler(nil, function(team_id)
    return append_page_params(base().."/teams/"..team_id.."/teams",
      {per_page="per_page",page="page"})
  end),
}
