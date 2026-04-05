-- Gitea backend handler overrides.
-- Loaded by .init.lua when config.backend == "gitea".
-- Only endpoints that behave differently from the default need to be listed here.
-- Also dofile'd by API-compatible backends: forgejo, gogs, codeberg, notabug.
if config.base_url == "" then config.base_url = "https://gitea.com" end

local base = function() return config.base_url .. "/api/v1" end
local auth = function() return make_fetch_opts("token") end
local PAGES = { per_page = "limit", page = "page" }

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

local function translate_users(users)
  for i, u in ipairs(users) do users[i] = translate_user(u) end
  return users
end

local function set_204_or_error(method, url)
  local opts = auth() or {}; opts.method = method
  local ok, status = pcall(Fetch, url, opts)
  if ok and status == 204 then SetStatus(204, "No Content")
  elseif ok then respond_json(status, "Error", {})
  else respond_json(503, "Service Unavailable", {}) end
end

local function proxy_users_follow_list(username, rel)
  proxy_json(translate_users,
    fetch_json(append_page_params(base() .. "/users/" .. username .. "/" .. rel,
      PAGES)))
end

-- Returns a handler function: defers fetch_json(url_fn(...)) to request time.
-- xform receives (response_body, ...handler_args) so closures over handler args are not needed.
-- Named translate functions that only take the response body work as-is (extra args ignored).
local proxy_handler = make_proxy_handler(fetch_json)

local function filter_verified_emails(emails)
  local out = {}
  for _, e in ipairs(emails or {}) do
    if e.verified then out[#out + 1] = e end
  end
  return out
end

-- Map a Gitea team object to GitHub format.
local function translate_gitea_team(t)
  if not t then return {} end
  local slug = (t.name or ""):lower():gsub("[^%w%-]", "-")
  return {
    id                   = t.id,
    node_id              = "",
    name                 = t.name,
    slug                 = slug,
    description          = t.description or "",
    privacy              = "closed",
    notification_setting = "notifications_enabled",
    permission           = t.permission == "owner" and "admin" or (t.permission or "pull"),
    members_url          = "",
    repositories_url     = "",
    parent               = nil,
  }
end

-- Look up a Gitea team ID by org and slug.  Gitea uses numeric IDs; the slug
-- is matched against the lowercased-and-slugified team name.
local function gitea_find_team_id(org, slug)
  local ok, status, _, body = fetch_json(base() .. "/orgs/" .. org .. "/teams?limit=50")
  if not ok or status ~= 200 then return nil end
  for _, t in ipairs(DecodeJson(body) or {}) do
    local ts = (t.name or ""):lower():gsub("[^%w%-]", "-")
    if ts == slug then return t.id end
  end
  return nil
end

backend_impl = {
  -- Health check
  get_root = function()
    local ok, status = pcall(Fetch, base() .. "/version", auth())
    if ok and status == 200 then respond_json(200, "OK", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

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
      fetch_json(append_page_params(base() .. "/user/repos", PAGES)))
  end,

  -- POST /user/repos
  post_user_repos = function()
    proxy_json_created(translate_repo, fetch_json(base() .. "/user/repos", "POST", GetBody()))
  end,

  -- GET /orgs/{org}/repos
  get_org_repos = function(org)
    proxy_json(translate_repos,
      fetch_json(append_page_params(base() .. "/orgs/" .. org .. "/repos",
        PAGES)))
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
        PAGES)))
  end,

  -- GET /repos/{owner}/{repo}/tags
  -- Both Gitea and GitHub return [{ name, commit: { sha, url }, ... }] — pass through.
  get_repo_tags = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/tags",
        PAGES)))
  end,

  -- Branches ------------------------------------------------------------------

  -- Gitea branch objects use commit.id instead of GitHub's commit.sha.
  -- GET /repos/{owner}/{repo}/branches
  get_repo_branches = function(owner, repo_name)
    local function tr_branches(branches)
      for _, b in ipairs(branches or {}) do
        if b.commit then b.commit.sha = b.commit.id end
      end
      return branches or {}
    end
    proxy_json(tr_branches,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/branches",
        PAGES)))
  end,

  -- GET /repos/{owner}/{repo}/branches/{branch}
  get_repo_branch = function(owner, repo_name, branch)
    proxy_json(
      function(b)
        if b and b.commit then b.commit.sha = b.commit.id end
        return b or {}
      end,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/branches/" .. branch))
  end,

  -- Commits -------------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/commits
  get_repo_commits = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/commits",
        PAGES)))
  end,

  -- GET /repos/{owner}/{repo}/commits/{ref}
  get_repo_commit = function(owner, repo_name, ref)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/commits/" .. ref))
  end,

  -- Statuses ------------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/commits/{ref}/statuses
  get_commit_statuses = function(owner, repo_name, ref)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/statuses/" .. ref,
        PAGES)))
  end,

  -- GET /repos/{owner}/{repo}/commits/{ref}/status  (combined)
  get_commit_combined_status = function(owner, repo_name, ref)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/commits/" .. ref .. "/statuses"))
  end,

  -- POST /repos/{owner}/{repo}/statuses/{sha}
  post_commit_status = function(owner, repo_name, sha)
    proxy_json_created(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/statuses/" .. sha,
        "POST", GetBody()))
  end,

  -- Contents ------------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/readme
  get_repo_readme = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/readme"))
  end,

  -- GET /repos/{owner}/{repo}/readme/{dir}
  get_repo_readme_dir = function(owner, repo_name, dir)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/readme/" .. dir))
  end,

  -- GET /repos/{owner}/{repo}/contents/{path}
  get_repo_content = function(owner, repo_name, path)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/contents/" .. path))
  end,

  -- PUT /repos/{owner}/{repo}/contents/{path}
  put_repo_content = function(owner, repo_name, path)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/contents/" .. path,
        "PUT", GetBody()))
  end,

  -- DELETE /repos/{owner}/{repo}/contents/{path}
  delete_repo_content = function(owner, repo_name, path)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/contents/" .. path,
        "DELETE", GetBody()))
  end,

  -- GET /repos/{owner}/{repo}/tarball/{ref} — redirect to Gitea's archive URL
  get_repo_tarball = function(owner, repo_name, ref)
    SetStatus(302, "Found")
    SetHeader("Location",
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/archive/" .. ref .. ".tar.gz")
    Write("")
  end,

  -- GET /repos/{owner}/{repo}/zipball/{ref} — redirect to Gitea's archive URL
  get_repo_zipball = function(owner, repo_name, ref)
    SetStatus(302, "Found")
    SetHeader("Location",
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/archive/" .. ref .. ".zip")
    Write("")
  end,

  -- Compare -------------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/compare/{basehead}
  -- Gitea uses /{owner}/{repo}/compare/{base}...{head} (3 dots) in UI, but
  -- the API endpoint uses {base}...{head} or {base}..{head} in the basehead param.
  get_repo_compare = function(owner, repo_name, basehead)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/compare/" .. basehead))
  end,

  -- Collaborators -------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/collaborators
  get_repo_collaborators = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/collaborators",
        PAGES)))
  end,

  -- GET /repos/{owner}/{repo}/collaborators/{username} — 204 if collaborator, 404 if not
  get_repo_collaborator = function(owner, repo_name, username)
    local ok, status = pcall(Fetch,
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/collaborators/" .. username,
      auth())
    if ok and status == 204 then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Not Found", { message = "Not a collaborator" })
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- PUT /repos/{owner}/{repo}/collaborators/{username}
  put_repo_collaborator = function(owner, repo_name, username)
    local ok, status = fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/collaborators/" .. username,
      "PUT", GetBody())
    if ok and (status == 204 or status == 201) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- DELETE /repos/{owner}/{repo}/collaborators/{username}
  delete_repo_collaborator = function(owner, repo_name, username)
    local ok, status = fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/collaborators/" .. username,
      "DELETE")
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- GET /repos/{owner}/{repo}/collaborators/{username}/permission
  get_repo_collaborator_permission = function(owner, repo_name, username)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/collaborators/" .. username .. "/permission"))
  end,

  -- Forks ---------------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/forks
  get_repo_forks = function(owner, repo_name)
    proxy_json(translate_repos,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/forks",
        PAGES)))
  end,

  -- POST /repos/{owner}/{repo}/forks
  post_repo_forks = function(owner, repo_name)
    proxy_json_created(translate_repo,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/forks",
        "POST", GetBody()))
  end,

  -- Releases ------------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/releases
  get_repo_releases = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases",
        PAGES)))
  end,

  -- POST /repos/{owner}/{repo}/releases
  post_repo_releases = function(owner, repo_name)
    proxy_json_created(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases",
        "POST", GetBody()))
  end,

  -- GET /repos/{owner}/{repo}/releases/latest
  get_repo_release_latest = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/latest"))
  end,

  -- GET /repos/{owner}/{repo}/releases/tags/{tag}
  get_repo_release_by_tag = function(owner, repo_name, tag)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/tags/" .. tag))
  end,

  -- GET /repos/{owner}/{repo}/releases/{release_id}
  get_repo_release = function(owner, repo_name, release_id)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/" .. release_id))
  end,

  -- PATCH /repos/{owner}/{repo}/releases/{release_id}
  patch_repo_release = function(owner, repo_name, release_id)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/" .. release_id,
        "PATCH", GetBody()))
  end,

  -- DELETE /repos/{owner}/{repo}/releases/{release_id}
  delete_repo_release = function(owner, repo_name, release_id)
    local ok, status = fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/" .. release_id, "DELETE")
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- GET /repos/{owner}/{repo}/releases/{release_id}/assets
  get_repo_release_assets = function(owner, repo_name, release_id)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/" .. release_id .. "/assets",
        PAGES)))
  end,

  -- POST /repos/{owner}/{repo}/releases/{release_id}/assets — multipart; pass through
  post_repo_release_assets = function(owner, repo_name, release_id)
    -- Gitea uses the same multipart upload path; proxy the entire request.
    -- The Content-Type header (multipart/form-data) must be forwarded.
    local url = base() .. "/repos/" .. owner .. "/" .. repo_name ..
      "/releases/" .. release_id .. "/assets"
    local opts = auth() or {}
    opts.method = "POST"
    opts.body = GetBody()
    opts.headers = opts.headers or {}
    opts.headers["Content-Type"] = GetHeader("Content-Type") or "application/octet-stream"
    proxy_json_created(nil, pcall(Fetch, url, opts))
  end,

  -- GET /repos/{owner}/{repo}/releases/assets/{asset_id}
  get_repo_release_asset = function(owner, repo_name, asset_id)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/releases/assets/" .. asset_id))
  end,

  -- PATCH /repos/{owner}/{repo}/releases/assets/{asset_id}
  patch_repo_release_asset = function(owner, repo_name, asset_id)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/releases/assets/" .. asset_id, "PATCH", GetBody()))
  end,

  -- DELETE /repos/{owner}/{repo}/releases/assets/{asset_id}
  delete_repo_release_asset = function(owner, repo_name, asset_id)
    local ok, status = fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name ..
      "/releases/assets/" .. asset_id, "DELETE")
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- Deploy keys ---------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/keys
  get_repo_keys = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/keys",
        PAGES)))
  end,

  -- POST /repos/{owner}/{repo}/keys
  post_repo_keys = function(owner, repo_name)
    proxy_json_created(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/keys",
        "POST", GetBody()))
  end,

  -- GET /repos/{owner}/{repo}/keys/{key_id}
  get_repo_key = function(owner, repo_name, key_id)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/keys/" .. key_id))
  end,

  -- DELETE /repos/{owner}/{repo}/keys/{key_id}
  delete_repo_key = function(owner, repo_name, key_id)
    local ok, status = fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/keys/" .. key_id, "DELETE")
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- Webhooks ------------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/hooks
  get_repo_hooks = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks",
        PAGES)))
  end,

  -- POST /repos/{owner}/{repo}/hooks
  post_repo_hooks = function(owner, repo_name)
    proxy_json_created(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks",
        "POST", GetBody()))
  end,

  -- GET /repos/{owner}/{repo}/hooks/{hook_id}
  get_repo_hook = function(owner, repo_name, hook_id)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id))
  end,

  -- PATCH /repos/{owner}/{repo}/hooks/{hook_id}
  patch_repo_hook = function(owner, repo_name, hook_id)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id,
        "PATCH", GetBody()))
  end,

  -- DELETE /repos/{owner}/{repo}/hooks/{hook_id}
  delete_repo_hook = function(owner, repo_name, hook_id)
    local ok, status = fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id, "DELETE")
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- GET /repos/{owner}/{repo}/hooks/{hook_id}/config
  -- Gitea stores config inline in the hook object; extract the config sub-object.
  get_repo_hook_config = function(owner, repo_name, hook_id)
    proxy_json(
      function(hook) return hook.config or {} end,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id))
  end,

  -- PATCH /repos/{owner}/{repo}/hooks/{hook_id}/config
  -- Gitea has no separate config endpoint; merge into a full PATCH.
  patch_repo_hook_config = function(owner, repo_name, hook_id)
    local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id
    -- Fetch current hook, merge new config, write back.
    local ok, status, _, body = fetch_json(url)
    if not ok or status ~= 200 then
      if ok then respond_json(status, "Error", {}) else respond_json(503, "Service Unavailable", {}) end
      return
    end
    local hook = DecodeJson(body) or {}
    local new_config = DecodeJson(GetBody() or "{}")
    hook.config = hook.config or {}
    for k, v in pairs(new_config) do hook.config[k] = v end
    proxy_json(
      function(h) return h.config or {} end,
      fetch_json(url, "PATCH", EncodeJson(hook)))
  end,

  -- POST /repos/{owner}/{repo}/hooks/{hook_id}/tests
  post_repo_hook_test = function(owner, repo_name, hook_id)
    local ok, status = fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id .. "/tests", "POST")
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- Users' repos --------------------------------------------------------------

  -- GET /users/{username}/repos
  get_users_repos = function(username)
    proxy_json(translate_repos,
      fetch_json(append_page_params(
        base() .. "/users/" .. username .. "/repos",
        PAGES)))
  end,

  -- GET /repositories (public repos list) — use Gitea's repo search
  get_repositories = function()
    proxy_json(
      function(data) return translate_repos(data.data or {}) end,
      fetch_json(append_page_params(
        base() .. "/repos/search",
        PAGES)))
  end,

  -- Commit comments -----------------------------------------------------------

  -- GET /repos/{owner}/{repo}/comments
  get_repo_comments = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/comments",
        PAGES)))
  end,

  -- GET /repos/{owner}/{repo}/comments/{comment_id}
  get_repo_comment = function(owner, repo_name, comment_id)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/comments/" .. comment_id))
  end,

  -- PATCH /repos/{owner}/{repo}/comments/{comment_id}
  patch_repo_comment = function(owner, repo_name, comment_id)
    proxy_json(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/comments/" .. comment_id,
        "PATCH", GetBody()))
  end,

  -- DELETE /repos/{owner}/{repo}/comments/{comment_id}
  delete_repo_comment = function(owner, repo_name, comment_id)
    local ok, status = fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/comments/" .. comment_id, "DELETE")
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- GET /repos/{owner}/{repo}/commits/{commit_sha}/comments
  get_commit_comments = function(owner, repo_name, commit_sha)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/commits/" .. commit_sha .. "/notes",
        PAGES)))
  end,

  -- POST /repos/{owner}/{repo}/commits/{commit_sha}/comments
  post_commit_comment = function(owner, repo_name, commit_sha)
    proxy_json_created(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/git/commits/" .. commit_sha .. "/notes", "POST", GetBody()))
  end,

  -- Users ---------------------------------------------------------------------

  -- GET /user
  get_user = proxy_handler(translate_user, function() return base() .. "/user" end),

  -- PATCH /user
  patch_user = function()
    proxy_json(translate_user, fetch_json(base() .. "/user/settings", "PATCH", GetBody()))
  end,

  -- GET /users/{username}
  get_users_username = proxy_handler(translate_user, function(u) return base() .. "/users/" .. u end),

  -- GET /users
  get_users = proxy_handler(translate_users, function()
    return append_page_params(base() .. "/admin/users", PAGES)
  end),

  -- GET /user/followers
  get_user_followers = proxy_handler(translate_users, function()
    return append_page_params(base() .. "/user/followers", PAGES)
  end),

  -- GET /user/following
  get_user_following = proxy_handler(translate_users, function()
    return append_page_params(base() .. "/user/following", PAGES)
  end),

  -- GET /user/following/{username} — 204 if following, 404 if not
  get_user_is_following = function(username)
    local ok, status = pcall(Fetch, base() .. "/user/following/" .. username, auth())
    if ok and status == 204 then SetStatus(204, "No Content")
    elseif ok then respond_json(404, "Not Found", { message = "Not Following" })
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- PUT /user/following/{username}
  put_user_following = function(username)
    set_204_or_error("PUT", base() .. "/user/following/" .. username)
  end,

  -- DELETE /user/following/{username}
  delete_user_following = function(username)
    set_204_or_error("DELETE", base() .. "/user/following/" .. username)
  end,

  -- GET /users/{username}/followers
  get_users_followers = function(username) proxy_users_follow_list(username, "followers") end,

  -- GET /users/{username}/following
  get_users_following = function(username) proxy_users_follow_list(username, "following") end,

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
  get_user_key = proxy_handler(nil, function(id) return base() .. "/user/keys/" .. id end),

  -- DELETE /user/keys/{key_id}
  delete_user_key = function(key_id)
    local ok, status = fetch_json(base() .. "/user/keys/" .. key_id, "DELETE")
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- GET /users/{username}/keys
  get_users_keys = proxy_handler(nil, function(u)
    return append_page_params(base() .. "/users/" .. u .. "/keys", PAGES)
  end),

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
  get_user_gpg_key = proxy_handler(nil, function(id) return base() .. "/user/gpg_keys/" .. id end),

  -- DELETE /user/gpg_keys/{gpg_key_id}
  delete_user_gpg_key = function(gpg_key_id)
    local ok, status = fetch_json(base() .. "/user/gpg_keys/" .. gpg_key_id, "DELETE")
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- GET /users/{username}/gpg_keys
  get_users_gpg_keys = proxy_handler(nil, function(u)
    return append_page_params(base() .. "/users/" .. u .. "/gpg_keys", PAGES)
  end),

  -- Emails --------------------------------------------------------------------

  -- GET /user/emails
  get_user_emails = proxy_handler(nil, function() return base() .. "/user/emails" end),

  -- POST /user/emails
  post_user_emails = function()
    proxy_json_created(nil, fetch_json(base() .. "/user/emails", "POST", GetBody()))
  end,

  -- DELETE /user/emails
  delete_user_emails = function()
    local opts = auth() or {}
    opts.method = "DELETE"
    opts.body = GetBody()
    opts.headers = opts.headers or {}
    opts.headers["Content-Type"] = "application/json"
    local ok, status = pcall(Fetch, base() .. "/user/emails", opts)
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- GET /user/public_emails — Gitea has no separate endpoint; filter verified from /user/emails
  get_user_public_emails = proxy_handler(filter_verified_emails, function() return base() .. "/user/emails" end),

  -- Teams ---------------------------------------------------------------------
  -- Gitea teams use numeric IDs, not slugs.  find_team_id lists all teams for
  -- the org and matches by lowercased, slugified name.

  -- GET /orgs/{org}/teams
  get_org_teams = function(org)
    proxy_json(
      function(teams)
        for i, t in ipairs(teams) do teams[i] = translate_gitea_team(t) end
        return teams
      end,
      fetch_json(append_page_params(base() .. "/orgs/" .. org .. "/teams",
        PAGES)))
  end,

  -- POST /orgs/{org}/teams
  post_org_teams = function(org)
    local req = DecodeJson(GetBody() or "{}")
    local body = {
      name        = req.name,
      description = req.description,
      permission  = req.permission == "admin" and "owner" or (req.permission or "read"),
      units       = { "repo.code", "repo.issues", "repo.pulls", "repo.releases" },
      includes_all_repositories = false,
    }
    proxy_json_created(translate_gitea_team,
      fetch_json(base() .. "/orgs/" .. org .. "/teams", "POST", EncodeJson(body)))
  end,

  -- GET /orgs/{org}/teams/{team_slug}
  get_org_team = function(org, slug)
    local id = gitea_find_team_id(org, slug)
    if not id then respond_json(404, "Not Found", { message = "Not Found" }); return end
    proxy_json(translate_gitea_team, fetch_json(base() .. "/teams/" .. id))
  end,

  -- PATCH /orgs/{org}/teams/{team_slug}
  patch_org_team = function(org, slug)
    local id = gitea_find_team_id(org, slug)
    if not id then respond_json(404, "Not Found", { message = "Not Found" }); return end
    local req = DecodeJson(GetBody() or "{}")
    local body = {}
    if req.name        then body.name        = req.name end
    if req.description then body.description = req.description end
    if req.permission  then
      body.permission = req.permission == "admin" and "owner" or req.permission
    end
    proxy_json(translate_gitea_team,
      fetch_json(base() .. "/teams/" .. id, "PATCH", EncodeJson(body)))
  end,

  -- DELETE /orgs/{org}/teams/{team_slug}
  delete_org_team = function(org, slug)
    local id = gitea_find_team_id(org, slug)
    if not id then respond_json(404, "Not Found", { message = "Not Found" }); return end
    local opts = auth() or {}; opts.method = "DELETE"
    local ok, status = pcall(Fetch, base() .. "/teams/" .. id, opts)
    if ok and status == 204 then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- GET /orgs/{org}/teams/{team_slug}/invitations — Gitea has no invitations
  get_org_team_invitations = function()
    SetStatus(200, "OK")
    SetHeader("Content-Type", "application/json; charset=utf-8")
    Write("[]")
  end,

  -- GET /orgs/{org}/teams/{team_slug}/members
  get_org_team_members = function(org, slug)
    local id = gitea_find_team_id(org, slug)
    if not id then respond_json(404, "Not Found", { message = "Not Found" }); return end
    proxy_json(translate_users,
      fetch_json(append_page_params(base() .. "/teams/" .. id .. "/members",
        PAGES)))
  end,

  -- GET /orgs/{org}/teams/{team_slug}/memberships/{username}
  get_org_team_membership = function(org, slug, username)
    local id = gitea_find_team_id(org, slug)
    if not id then respond_json(404, "Not Found", { message = "Not Found" }); return end
    local ok, status = pcall(Fetch,
      base() .. "/teams/" .. id .. "/members/" .. username, auth())
    if ok and status == 204 then
      respond_json(200, "OK", { url = "", role = "member", state = "active" })
    elseif ok then respond_json(404, "Not Found", { message = "Not Found" })
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- PUT /orgs/{org}/teams/{team_slug}/memberships/{username}
  put_org_team_membership = function(org, slug, username)
    local id = gitea_find_team_id(org, slug)
    if not id then respond_json(404, "Not Found", { message = "Not Found" }); return end
    local opts = auth() or {}; opts.method = "PUT"
    local ok, status = pcall(Fetch, base() .. "/teams/" .. id .. "/members/" .. username, opts)
    if ok and (status == 204 or status == 200) then
      respond_json(200, "OK", { url = "", role = "member", state = "active" })
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- DELETE /orgs/{org}/teams/{team_slug}/memberships/{username}
  delete_org_team_membership = function(org, slug, username)
    local id = gitea_find_team_id(org, slug)
    if not id then respond_json(404, "Not Found", { message = "Not Found" }); return end
    local opts = auth() or {}; opts.method = "DELETE"
    local ok, status = pcall(Fetch,
      base() .. "/teams/" .. id .. "/members/" .. username, opts)
    if ok and status == 204 then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- GET /orgs/{org}/teams/{team_slug}/repos
  get_org_team_repos = function(org, slug)
    local id = gitea_find_team_id(org, slug)
    if not id then respond_json(404, "Not Found", { message = "Not Found" }); return end
    proxy_json(
      function(repos)
        for i, r in ipairs(repos) do repos[i] = translate_repo(r) end
        return repos
      end,
      fetch_json(append_page_params(base() .. "/teams/" .. id .. "/repos",
        PAGES)))
  end,

  -- GET /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}
  get_org_team_repo = function(org, slug, owner, repo_name)
    local id = gitea_find_team_id(org, slug)
    if not id then respond_json(404, "Not Found", { message = "Not Found" }); return end
    local ok, status, _, body = fetch_json(
      base() .. "/teams/" .. id .. "/repos/" .. owner .. "/" .. repo_name)
    if ok and (status == 204 or status == 200) then
      local r = (status == 200 and DecodeJson(body)) or {}
      respond_json(200, "OK", translate_repo(r))
    elseif ok then respond_json(404, "Not Found", { message = "Not Found" })
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- PUT /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}
  put_org_team_repo = function(org, slug, owner, repo_name)
    local id = gitea_find_team_id(org, slug)
    if not id then respond_json(404, "Not Found", { message = "Not Found" }); return end
    local opts = auth() or {}; opts.method = "PUT"
    local ok, status = pcall(Fetch,
      base() .. "/teams/" .. id .. "/repos/" .. owner .. "/" .. repo_name, opts)
    if ok and status == 204 then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- DELETE /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}
  delete_org_team_repo = function(org, slug, owner, repo_name)
    local id = gitea_find_team_id(org, slug)
    if not id then respond_json(404, "Not Found", { message = "Not Found" }); return end
    local opts = auth() or {}; opts.method = "DELETE"
    local ok, status = pcall(Fetch,
      base() .. "/teams/" .. id .. "/repos/" .. owner .. "/" .. repo_name, opts)
    if ok and status == 204 then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- GET /orgs/{org}/teams/{team_slug}/teams — Gitea has no nested teams
  get_org_team_children = function()
    SetStatus(200, "OK")
    SetHeader("Content-Type", "application/json; charset=utf-8")
    Write("[]")
  end,

  -- Legacy team-by-id endpoints (GitHub /teams/{team_id} → Gitea /teams/{id}).
  -- No slug lookup needed — the caller already provides the numeric ID.

  -- GET /user/teams
  get_user_teams = function()
    proxy_json(
      function(teams)
        for i, t in ipairs(teams) do teams[i] = translate_gitea_team(t) end
        return teams
      end,
      fetch_json(append_page_params(base() .. "/user/teams",
        PAGES)))
  end,

  -- GET /teams/{team_id}
  get_team = function(team_id)
    proxy_json(translate_gitea_team, fetch_json(base() .. "/teams/" .. team_id))
  end,

  -- PATCH /teams/{team_id}
  patch_team = function(team_id)
    local req = DecodeJson(GetBody() or "{}")
    local body = {}
    if req.name        then body.name        = req.name end
    if req.description then body.description = req.description end
    if req.permission  then
      body.permission = req.permission == "admin" and "owner" or req.permission
    end
    proxy_json(translate_gitea_team,
      fetch_json(base() .. "/teams/" .. team_id, "PATCH", EncodeJson(body)))
  end,

  -- DELETE /teams/{team_id}
  delete_team = function(team_id)
    set_204_or_error("DELETE", base() .. "/teams/" .. team_id)
  end,

  -- GET /teams/{team_id}/members
  get_team_members = function(team_id)
    proxy_json(translate_users,
      fetch_json(append_page_params(base() .. "/teams/" .. team_id .. "/members",
        PAGES)))
  end,

  -- GET /teams/{team_id}/members/{username} — deprecated legacy endpoint
  get_team_member = function(team_id, username)
    local ok, status = pcall(Fetch,
      base() .. "/teams/" .. team_id .. "/members/" .. username, auth())
    if ok and status == 204 then SetStatus(204, "No Content")
    elseif ok then respond_json(404, "Not Found", { message = "Not Found" })
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- PUT /teams/{team_id}/members/{username} — deprecated legacy endpoint
  put_team_member = function(team_id, username)
    local opts = auth() or {}; opts.method = "PUT"
    local ok, status = pcall(Fetch,
      base() .. "/teams/" .. team_id .. "/members/" .. username, opts)
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- DELETE /teams/{team_id}/members/{username} — deprecated legacy endpoint
  delete_team_member = function(team_id, username)
    set_204_or_error("DELETE", base() .. "/teams/" .. team_id .. "/members/" .. username)
  end,

  -- GET /teams/{team_id}/memberships/{username}
  get_team_membership = function(team_id, username)
    local ok, status = pcall(Fetch,
      base() .. "/teams/" .. team_id .. "/members/" .. username, auth())
    if ok and status == 204 then
      respond_json(200, "OK", { url = "", role = "member", state = "active" })
    elseif ok then respond_json(404, "Not Found", { message = "Not Found" })
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- PUT /teams/{team_id}/memberships/{username}
  put_team_membership = function(team_id, username)
    local opts = auth() or {}; opts.method = "PUT"
    local ok, status = pcall(Fetch,
      base() .. "/teams/" .. team_id .. "/members/" .. username, opts)
    if ok and (status == 204 or status == 200) then
      respond_json(200, "OK", { url = "", role = "member", state = "active" })
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- DELETE /teams/{team_id}/memberships/{username}
  delete_team_membership = function(team_id, username)
    set_204_or_error("DELETE", base() .. "/teams/" .. team_id .. "/members/" .. username)
  end,

  -- GET /teams/{team_id}/repos
  get_team_repos = function(team_id)
    proxy_json(
      function(repos)
        for i, r in ipairs(repos) do repos[i] = translate_repo(r) end
        return repos
      end,
      fetch_json(append_page_params(base() .. "/teams/" .. team_id .. "/repos",
        PAGES)))
  end,

  -- GET /teams/{team_id}/repos/{owner}/{repo}
  get_team_repo = function(team_id, owner, repo_name)
    local ok, status, _, body = fetch_json(
      base() .. "/teams/" .. team_id .. "/repos/" .. owner .. "/" .. repo_name)
    if ok and (status == 204 or status == 200) then
      local r = (status == 200 and DecodeJson(body)) or {}
      respond_json(200, "OK", translate_repo(r))
    elseif ok then respond_json(404, "Not Found", { message = "Not Found" })
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- PUT /teams/{team_id}/repos/{owner}/{repo}
  put_team_repo = function(team_id, owner, repo_name)
    local opts = auth() or {}; opts.method = "PUT"
    local ok, status = pcall(Fetch,
      base() .. "/teams/" .. team_id .. "/repos/" .. owner .. "/" .. repo_name, opts)
    if ok and status == 204 then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- DELETE /teams/{team_id}/repos/{owner}/{repo}
  delete_team_repo = function(team_id, owner, repo_name)
    set_204_or_error("DELETE",
      base() .. "/teams/" .. team_id .. "/repos/" .. owner .. "/" .. repo_name)
  end,

}
