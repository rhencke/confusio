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
        { per_page = "limit", page = "page" })))
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
        { per_page = "limit", page = "page" })))
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
        { per_page = "limit", page = "page" })))
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
        { per_page = "limit", page = "page" })))
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
        { per_page = "limit", page = "page" })))
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
        { per_page = "limit", page = "page" })))
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
        { per_page = "limit", page = "page" })))
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
        { per_page = "limit", page = "page" })))
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
        { per_page = "limit", page = "page" })))
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
        { per_page = "limit", page = "page" })))
  end,

  -- GET /repositories (public repos list) — use Gitea's repo search
  get_repositories = function()
    proxy_json(
      function(data) return translate_repos(data.data or {}) end,
      fetch_json(append_page_params(
        base() .. "/repos/search",
        { per_page = "limit", page = "page" })))
  end,

  -- Commit comments -----------------------------------------------------------

  -- GET /repos/{owner}/{repo}/comments
  get_repo_comments = function(owner, repo_name)
    proxy_json(nil,
      fetch_json(append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/comments",
        { per_page = "limit", page = "page" })))
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
        { per_page = "limit", page = "page" })))
  end,

  -- POST /repos/{owner}/{repo}/commits/{commit_sha}/comments
  post_commit_comment = function(owner, repo_name, commit_sha)
    proxy_json_created(nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name ..
        "/git/commits/" .. commit_sha .. "/notes", "POST", GetBody()))
  end,

}
