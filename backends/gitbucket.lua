-- Gitbucket backend handler overrides.
-- Gitbucket exposes a GitHub-compatible API at /api/v3/ — responses can be
-- passed through with no field translation needed.

local base = function()
  return config.base_url .. "/api/v3"
end
local auth = function()
  return make_fetch_opts("bearer")
end
local PAGES = { per_page = "per_page", page = "page" }
local _t = make_backend_transport("bearer", PAGES)
local fetch_json = _t.fetch_json
local proxy_handler = _t.proxy_handler
local proxy_handler_created = _t.proxy_handler_created

local function set_204_or_error(method, url)
  local opts = auth() or {}
  opts.method = method
  proxy_204(nil, pcall(Fetch, url, opts))
end

-- GitBucket commit status state → GitHub check_run status/conclusion mapping.
-- Shared by post_check_runs and get_commit_check_runs.
local gb_to_gh = {
  pending = { status = "in_progress", conclusion = nil },
  success = { status = "completed", conclusion = "success" },
  warning = { status = "completed", conclusion = "neutral" },
}

backend_impl = {
  get_root = function()
    proxy_health_check(pcall(Fetch, base() .. "/rate_limit", auth()))
  end,

  get_rate_limit = proxy_handler(function(data)
    return { rate = data.rate or data }
  end, function()
    return base() .. "/rate_limit"
  end),

  get_repo = proxy_handler(nil, function(o, r)
    return base() .. "/repos/" .. o .. "/" .. r
  end),

  patch_repo = function(owner, repo_name)
    proxy_json(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name, "PATCH", GetBody())
    )
  end,

  delete_repo = function(owner, repo_name)
    local url = base() .. "/repos/" .. owner .. "/" .. repo_name
    local dopts = auth() or {}
    dopts.method = "DELETE"
    proxy_204(nil, pcall(Fetch, url, dopts))
  end,

  get_user_repos = proxy_handler(nil, function()
    return append_page_params(base() .. "/user/repos", PAGES)
  end),

  post_user_repos = function()
    proxy_json_created(nil, fetch_json(base() .. "/user/repos", "POST", GetBody()))
  end,

  get_org_repos = proxy_handler(nil, function(org)
    return append_page_params(base() .. "/orgs/" .. org .. "/repos", PAGES)
  end),

  post_org_repos = function(org)
    proxy_json_created(nil, fetch_json(base() .. "/orgs/" .. org .. "/repos", "POST", GetBody()))
  end,

  get_repo_topics = proxy_handler(nil, function(o, r)
    return base() .. "/repos/" .. o .. "/" .. r .. "/topics"
  end),

  put_repo_topics = function(owner, repo_name)
    proxy_json(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/topics", "PUT", GetBody())
    )
  end,

  get_repo_languages = proxy_handler(nil, function(o, r)
    return base() .. "/repos/" .. o .. "/" .. r .. "/languages"
  end),

  get_repo_contributors = proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/contributors", PAGES)
  end),

  get_repo_tags = proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/tags", PAGES)
  end),

  get_repo_teams = proxy_handler(nil, function(o, r)
    return base() .. "/repos/" .. o .. "/" .. r .. "/teams"
  end),

  -- Branches ------------------------------------------------------------------
  get_repo_branches = proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/branches", PAGES)
  end),

  get_repo_branch = proxy_handler(nil, function(o, r, branch)
    return base() .. "/repos/" .. o .. "/" .. r .. "/branches/" .. branch
  end),

  -- Commits -------------------------------------------------------------------
  get_repo_commits = proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/commits", PAGES)
  end),

  get_repo_commit = proxy_handler(nil, function(o, r, ref)
    return base() .. "/repos/" .. o .. "/" .. r .. "/commits/" .. ref
  end),

  -- Statuses ------------------------------------------------------------------
  get_commit_statuses = proxy_handler(nil, function(o, r, ref)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/statuses/" .. ref, PAGES)
  end),

  get_commit_combined_status = proxy_handler(nil, function(o, r, ref)
    return base() .. "/repos/" .. o .. "/" .. r .. "/commits/" .. ref .. "/status"
  end),

  post_commit_status = function(owner, repo_name, sha)
    proxy_json_created(
      nil,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/statuses/" .. sha,
        "POST",
        GetBody()
      )
    )
  end,

  -- Checks (via GitBucket commit statuses) ------------------------------------
  --
  -- GitBucket exposes a GitHub-compatible commit statuses API at /api/v3/,
  -- so the translation is identical to Gitea: state is "pending", "success",
  -- "failure", or "error".
  --
  -- GitHub → GitBucket state:
  --   queued/in_progress      → pending
  --   completed/success|neutral|skipped → success
  --   completed/failure       → failure
  --   completed/(other)       → error
  --
  -- GitBucket → GitHub:
  --   pending  → status=in_progress, conclusion=nil
  --   success  → status=completed,   conclusion=success
  --   failure  → status=completed,   conclusion=failure
  --   error    → status=completed,   conclusion=failure
  --   warning  → status=completed,   conclusion=neutral

  post_check_runs = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}") or {}
    local sha = req.head_sha or ""
    local status = req.status or "queued"
    local conclusion = req.conclusion
    local gh_conclusion_to_gb = {
      success = "success",
      neutral = "success",
      skipped = "success",
      failure = "failure",
    }
    local gb_state = status == "completed" and (gh_conclusion_to_gb[conclusion] or "error")
      or "pending"
    local function translate(s)
      if not s then
        return {}
      end
      local state = s.state or "pending"
      local mapped = gb_to_gh[state] or { status = "completed", conclusion = "failure" }
      local gh_status, gh_conclusion = mapped.status, mapped.conclusion
      return {
        id = s.id or 0,
        node_id = "",
        head_sha = sha,
        name = s.context or req.name or "",
        status = gh_status,
        conclusion = gh_conclusion,
        started_at = s.created_at or s.updated_at,
        completed_at = gh_status == "completed" and (s.updated_at or s.created_at) or nil,
        output = {
          title = s.description or "",
          summary = s.description or "",
          text = "",
          annotations_count = 0,
          annotations_url = "",
        },
        url = "",
        html_url = s.target_url or "",
        details_url = s.target_url or "",
      }
    end
    proxy_json_created(
      translate,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/statuses/" .. sha,
        "POST",
        EncodeJson({
          state = gb_state,
          target_url = req.details_url or "",
          description = (req.output and req.output.summary) or req.name or "",
          context = req.name or "",
        })
      )
    )
  end,

  get_commit_check_runs = function(owner, repo_name, ref)
    local ok, status, _, body = fetch_json(
      append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/statuses/" .. ref,
        PAGES
      )
    )
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    local statuses = DecodeJson(body) or {}
    local runs = {}
    for i, s in ipairs(statuses) do
      local state = s.state or "pending"
      local mapped = gb_to_gh[state] or { status = "completed", conclusion = "failure" }
      local gh_status, gh_conclusion = mapped.status, mapped.conclusion
      runs[i] = {
        id = s.id or i,
        node_id = "",
        head_sha = ref,
        name = s.context or "",
        status = gh_status,
        conclusion = gh_conclusion,
        started_at = s.created_at or s.updated_at,
        completed_at = gh_status == "completed" and (s.updated_at or s.created_at) or nil,
        output = {
          title = s.description or "",
          summary = s.description or "",
          text = "",
          annotations_count = 0,
          annotations_url = "",
        },
        url = "",
        html_url = s.target_url or "",
        details_url = s.target_url or "",
      }
    end
    respond_json(200, { total_count = #runs, check_runs = runs })
  end,

  -- Check suites have no GitBucket equivalent; all suite endpoints fall back
  -- to the route_defaults stubs defined in .init.lua.

  -- Licenses ------------------------------------------------------------------
  get_licenses = proxy_handler(nil, function()
    return base() .. "/licenses"
  end),

  get_license = proxy_handler(nil, function(license_name)
    return base() .. "/licenses/" .. license_name
  end),

  get_repo_license = proxy_handler(nil, function(o, r)
    return base() .. "/repos/" .. o .. "/" .. r .. "/license"
  end),

  -- Contents ------------------------------------------------------------------
  get_repo_readme = proxy_handler(nil, function(o, r)
    return base() .. "/repos/" .. o .. "/" .. r .. "/readme"
  end),

  get_repo_readme_dir = proxy_handler(nil, function(o, r, dir)
    return base() .. "/repos/" .. o .. "/" .. r .. "/readme/" .. dir
  end),

  get_repo_content = proxy_handler(nil, function(o, r, path)
    return base() .. "/repos/" .. o .. "/" .. r .. "/contents/" .. path
  end),

  put_repo_content = function(owner, repo_name, path)
    proxy_json(
      nil,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/contents/" .. path,
        "PUT",
        GetBody()
      )
    )
  end,

  delete_repo_content = function(owner, repo_name, path)
    proxy_json(
      nil,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/contents/" .. path,
        "DELETE",
        GetBody()
      )
    )
  end,

  get_repo_tarball = function(owner, repo_name, ref)
    SetStatus(302, "Found")
    SetHeader("Location", base() .. "/repos/" .. owner .. "/" .. repo_name .. "/tarball/" .. ref)
    Write("")
  end,

  get_repo_zipball = function(owner, repo_name, ref)
    SetStatus(302, "Found")
    SetHeader("Location", base() .. "/repos/" .. owner .. "/" .. repo_name .. "/zipball/" .. ref)
    Write("")
  end,

  -- Compare -------------------------------------------------------------------
  get_repo_compare = proxy_handler(nil, function(o, r, basehead)
    return base() .. "/repos/" .. o .. "/" .. r .. "/compare/" .. basehead
  end),

  -- Collaborators -------------------------------------------------------------
  get_repo_collaborators = proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/collaborators", PAGES)
  end),

  get_repo_collaborator = function(owner, repo_name, username)
    local ok, status = pcall(
      Fetch,
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/collaborators/" .. username,
      auth()
    )
    if ok and status == 204 then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, { message = "Not a collaborator" })
    else
      respond_json(503, {})
    end
  end,

  put_repo_collaborator = function(owner, repo_name, username)
    proxy_204(
      { 201 },
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/collaborators/" .. username,
        "PUT",
        GetBody()
      )
    )
  end,

  delete_repo_collaborator = function(owner, repo_name, username)
    proxy_204(
      { 200 },
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/collaborators/" .. username,
        "DELETE"
      )
    )
  end,

  get_repo_collaborator_permission = proxy_handler(nil, function(o, r, username)
    return base() .. "/repos/" .. o .. "/" .. r .. "/collaborators/" .. username .. "/permission"
  end),

  -- Forks ---------------------------------------------------------------------
  get_repo_forks = proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/forks", PAGES)
  end),

  post_repo_forks = function(owner, repo_name)
    proxy_json_created(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/forks", "POST", GetBody())
    )
  end,

  -- Releases ------------------------------------------------------------------
  get_repo_releases = proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/releases", PAGES)
  end),

  post_repo_releases = function(owner, repo_name)
    proxy_json_created(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases", "POST", GetBody())
    )
  end,

  get_repo_release_latest = proxy_handler(nil, function(o, r)
    return base() .. "/repos/" .. o .. "/" .. r .. "/releases/latest"
  end),

  get_repo_release_by_tag = proxy_handler(nil, function(o, r, tag)
    return base() .. "/repos/" .. o .. "/" .. r .. "/releases/tags/" .. tag
  end),

  get_repo_release = proxy_handler(nil, function(o, r, id)
    return base() .. "/repos/" .. o .. "/" .. r .. "/releases/" .. id
  end),

  patch_repo_release = function(owner, repo_name, release_id)
    proxy_json(
      nil,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/" .. release_id,
        "PATCH",
        GetBody()
      )
    )
  end,

  delete_repo_release = function(owner, repo_name, release_id)
    proxy_204(
      { 200 },
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/" .. release_id,
        "DELETE"
      )
    )
  end,

  get_repo_release_assets = proxy_handler(nil, function(o, r, id)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/releases/" .. id .. "/assets",
      PAGES
    )
  end),

  post_repo_release_assets = function(owner, repo_name, release_id)
    local url = base()
      .. "/repos/"
      .. owner
      .. "/"
      .. repo_name
      .. "/releases/"
      .. release_id
      .. "/assets"
    local opts = auth() or {}
    opts.method = "POST"
    opts.body = GetBody()
    opts.headers = opts.headers or {}
    opts.headers["Content-Type"] = GetHeader("Content-Type") or "application/octet-stream"
    proxy_json_created(nil, pcall(Fetch, url, opts))
  end,

  get_repo_release_asset = proxy_handler(nil, function(o, r, asset_id)
    return base() .. "/repos/" .. o .. "/" .. r .. "/releases/assets/" .. asset_id
  end),

  patch_repo_release_asset = function(owner, repo_name, asset_id)
    proxy_json(
      nil,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/assets/" .. asset_id,
        "PATCH",
        GetBody()
      )
    )
  end,

  delete_repo_release_asset = function(owner, repo_name, asset_id)
    proxy_204(
      { 200 },
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/assets/" .. asset_id,
        "DELETE"
      )
    )
  end,

  -- Deploy keys ---------------------------------------------------------------
  get_repo_keys = proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/keys", PAGES)
  end),

  post_repo_keys = function(owner, repo_name)
    proxy_json_created(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/keys", "POST", GetBody())
    )
  end,

  get_repo_key = proxy_handler(nil, function(o, r, key_id)
    return base() .. "/repos/" .. o .. "/" .. r .. "/keys/" .. key_id
  end),

  delete_repo_key = function(owner, repo_name, key_id)
    proxy_204(
      { 200 },
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/keys/" .. key_id, "DELETE")
    )
  end,

  -- Webhooks ------------------------------------------------------------------
  get_repo_hooks = proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/hooks", PAGES)
  end),

  post_repo_hooks = function(owner, repo_name)
    proxy_json_created(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks", "POST", GetBody())
    )
  end,

  get_repo_hook = proxy_handler(nil, function(o, r, hook_id)
    return base() .. "/repos/" .. o .. "/" .. r .. "/hooks/" .. hook_id
  end),

  patch_repo_hook = function(owner, repo_name, hook_id)
    proxy_json(
      nil,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id,
        "PATCH",
        GetBody()
      )
    )
  end,

  delete_repo_hook = function(owner, repo_name, hook_id)
    proxy_204(
      { 200 },
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id, "DELETE")
    )
  end,

  get_repo_hook_config = proxy_handler(function(h)
    return h.config or {}
  end, function(o, r, hook_id)
    return base() .. "/repos/" .. o .. "/" .. r .. "/hooks/" .. hook_id
  end),

  patch_repo_hook_config = function(owner, repo_name, hook_id)
    local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id
    local ok, status, _, body = fetch_json(url)
    if not ok or status ~= 200 then
      if ok then
        respond_json(status, {})
      else
        respond_json(503, {})
      end
      return
    end
    local hook = DecodeJson(body) or {}
    local new_cfg = DecodeJson(GetBody() or "{}")
    hook.config = hook.config or {}
    for k, v in pairs(new_cfg) do
      hook.config[k] = v
    end
    proxy_json(function(h)
      return h.config or {}
    end, fetch_json(url, "PATCH", EncodeJson(hook)))
  end,

  post_repo_hook_ping = function(owner, repo_name, hook_id)
    proxy_204(
      { 200 },
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id .. "/pings",
        "POST"
      )
    )
  end,

  post_repo_hook_test = function(owner, repo_name, hook_id)
    proxy_204(
      { 200 },
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id .. "/tests",
        "POST"
      )
    )
  end,

  -- Commit comments -----------------------------------------------------------
  get_repo_comments = proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/comments", PAGES)
  end),

  get_repo_comment = proxy_handler(nil, function(o, r, comment_id)
    return base() .. "/repos/" .. o .. "/" .. r .. "/comments/" .. comment_id
  end),

  patch_repo_comment = function(owner, repo_name, comment_id)
    proxy_json(
      nil,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/comments/" .. comment_id,
        "PATCH",
        GetBody()
      )
    )
  end,

  delete_repo_comment = function(owner, repo_name, comment_id)
    proxy_204(
      { 200 },
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/comments/" .. comment_id,
        "DELETE"
      )
    )
  end,

  get_commit_comments = proxy_handler(nil, function(o, r, sha)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/commits/" .. sha .. "/comments",
      PAGES
    )
  end),

  post_commit_comment = function(owner, repo_name, commit_sha)
    proxy_json_created(
      nil,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/commits/" .. commit_sha .. "/comments",
        "POST",
        GetBody()
      )
    )
  end,

  -- GET /users/{username}/repos + public repos --------------------------------
  get_users_repos = proxy_handler(nil, function(username)
    return append_page_params(base() .. "/users/" .. username .. "/repos", PAGES)
  end),

  get_repositories = proxy_handler(nil, function()
    return append_page_params(base() .. "/repositories", PAGES)
  end),

  -- Users (GitHub-compatible passthrough) -------------------------------------

  get_user = proxy_handler(nil, function()
    return base() .. "/user"
  end),

  patch_user = function()
    proxy_json(nil, fetch_json(base() .. "/user", "PATCH", GetBody()))
  end,

  get_users_username = proxy_handler(nil, function(username)
    return base() .. "/users/" .. username
  end),

  get_users = proxy_handler(nil, function()
    return append_page_params(base() .. "/users", PAGES)
  end),

  get_user_followers = proxy_handler(nil, function()
    return append_page_params(base() .. "/user/followers", PAGES)
  end),

  get_user_following = proxy_handler(nil, function()
    return append_page_params(base() .. "/user/following", PAGES)
  end),

  get_user_is_following = function(username)
    local ok, status = pcall(Fetch, base() .. "/user/following/" .. username, auth())
    if ok and status == 204 then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(404, { message = "Not Following" })
    else
      respond_json(503, {})
    end
  end,

  put_user_following = function(username)
    set_204_or_error("PUT", base() .. "/user/following/" .. username)
  end,

  delete_user_following = function(username)
    set_204_or_error("DELETE", base() .. "/user/following/" .. username)
  end,

  get_users_followers = proxy_handler(nil, function(username)
    return append_page_params(base() .. "/users/" .. username .. "/followers", PAGES)
  end),

  get_users_following = proxy_handler(nil, function(username)
    return append_page_params(base() .. "/users/" .. username .. "/following", PAGES)
  end),

  get_users_is_following = function(username, target)
    local ok, status =
      pcall(Fetch, base() .. "/users/" .. username .. "/following/" .. target, auth())
    if ok and status == 204 then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(404, { message = "Not Following" })
    else
      respond_json(503, {})
    end
  end,

  get_user_emails = proxy_handler(nil, function()
    return base() .. "/user/emails"
  end),

  post_user_emails = function()
    proxy_json_created(nil, fetch_json(base() .. "/user/emails", "POST", GetBody()))
  end,

  delete_user_emails = function()
    local opts = auth() or {}
    opts.method = "DELETE"
    opts.body = GetBody()
    opts.headers = opts.headers or {}
    opts.headers["Content-Type"] = "application/json"
    proxy_204({ 200 }, pcall(Fetch, base() .. "/user/emails", opts))
  end,

  get_user_keys = proxy_handler(nil, function()
    return append_page_params(base() .. "/user/keys", PAGES)
  end),

  post_user_keys = function()
    proxy_json_created(nil, fetch_json(base() .. "/user/keys", "POST", GetBody()))
  end,

  get_user_key = proxy_handler(nil, function(key_id)
    return base() .. "/user/keys/" .. key_id
  end),

  delete_user_key = function(key_id)
    local opts = auth() or {}
    opts.method = "DELETE"
    proxy_204({ 200 }, pcall(Fetch, base() .. "/user/keys/" .. key_id, opts))
  end,

  get_users_keys = proxy_handler(nil, function(username)
    return append_page_params(base() .. "/users/" .. username .. "/keys", PAGES)
  end),

  -- Teams (GitHub-compatible passthrough) -------------------------------------

  get_org_teams = proxy_handler(nil, function(org)
    return append_page_params(base() .. "/orgs/" .. org .. "/teams", PAGES)
  end),

  post_org_teams = function(org)
    proxy_json_created(nil, fetch_json(base() .. "/orgs/" .. org .. "/teams", "POST", GetBody()))
  end,

  get_org_team = proxy_handler(nil, function(org, slug)
    return base() .. "/orgs/" .. org .. "/teams/" .. slug
  end),

  patch_org_team = function(org, slug)
    proxy_json(nil, fetch_json(base() .. "/orgs/" .. org .. "/teams/" .. slug, "PATCH", GetBody()))
  end,

  delete_org_team = function(org, slug)
    proxy_204({ 200 }, fetch_json(base() .. "/orgs/" .. org .. "/teams/" .. slug, "DELETE"))
  end,

  get_org_team_invitations = proxy_handler(nil, function(org, slug)
    return append_page_params(
      base() .. "/orgs/" .. org .. "/teams/" .. slug .. "/invitations",
      PAGES
    )
  end),

  get_org_team_members = proxy_handler(nil, function(org, slug)
    return append_page_params(base() .. "/orgs/" .. org .. "/teams/" .. slug .. "/members", PAGES)
  end),

  get_org_team_membership = proxy_handler(nil, function(org, slug, username)
    return base() .. "/orgs/" .. org .. "/teams/" .. slug .. "/memberships/" .. username
  end),

  put_org_team_membership = function(org, slug, username)
    proxy_json(
      nil,
      fetch_json(
        base() .. "/orgs/" .. org .. "/teams/" .. slug .. "/memberships/" .. username,
        "PUT",
        GetBody()
      )
    )
  end,

  delete_org_team_membership = function(org, slug, username)
    proxy_204(
      { 200 },
      fetch_json(
        base() .. "/orgs/" .. org .. "/teams/" .. slug .. "/memberships/" .. username,
        "DELETE"
      )
    )
  end,

  get_org_team_repos = proxy_handler(nil, function(org, slug)
    return append_page_params(base() .. "/orgs/" .. org .. "/teams/" .. slug .. "/repos", PAGES)
  end),

  get_org_team_repo = proxy_handler(nil, function(org, slug, owner, repo_name)
    return base() .. "/orgs/" .. org .. "/teams/" .. slug .. "/repos/" .. owner .. "/" .. repo_name
  end),

  put_org_team_repo = function(org, slug, owner, repo_name)
    proxy_204(
      { 200 },
      fetch_json(
        base() .. "/orgs/" .. org .. "/teams/" .. slug .. "/repos/" .. owner .. "/" .. repo_name,
        "PUT",
        GetBody()
      )
    )
  end,

  delete_org_team_repo = function(org, slug, owner, repo_name)
    proxy_204(
      { 200 },
      fetch_json(
        base() .. "/orgs/" .. org .. "/teams/" .. slug .. "/repos/" .. owner .. "/" .. repo_name,
        "DELETE"
      )
    )
  end,

  get_org_team_children = proxy_handler(nil, function(org, slug)
    return append_page_params(base() .. "/orgs/" .. org .. "/teams/" .. slug .. "/teams", PAGES)
  end),

  -- Issues (GitHub-compatible passthrough) -------------------------------------

  get_repo_issues = proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/issues", PAGES)
  end),

  post_repo_issues = proxy_handler_created(nil, function(o, r)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues", "POST", GetBody()
  end),

  get_repo_issue = proxy_handler(nil, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n
  end),

  patch_repo_issue = proxy_handler(nil, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n, "PATCH", GetBody()
  end),

  get_repo_issue_comments = proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/issues/comments", PAGES)
  end),

  get_repo_issue_comment = proxy_handler(nil, function(o, r, comment_id)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/comments/" .. comment_id
  end),

  patch_repo_issue_comment = proxy_handler(nil, function(o, r, id)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/comments/" .. id, "PATCH", GetBody()
  end),

  delete_repo_issue_comment = function(owner, repo_name, comment_id)
    proxy_204(
      { 200 },
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/comments/" .. comment_id,
        "DELETE"
      )
    )
  end,

  get_repo_issue_events = proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/issues/events", PAGES)
  end),

  get_issue_comments = proxy_handler(nil, function(o, r, n)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/comments",
      PAGES
    )
  end),

  post_issue_comment = proxy_handler_created(nil, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/comments", "POST", GetBody()
  end),

  get_issue_events = proxy_handler(nil, function(o, r, n)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/events",
      PAGES
    )
  end),

  get_issue_timeline = proxy_handler(nil, function(o, r, n)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/timeline",
      PAGES
    )
  end),

  get_issue_labels = proxy_handler(nil, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/labels"
  end),

  post_issue_labels = proxy_handler(nil, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/labels", "POST", GetBody()
  end),

  put_issue_labels = proxy_handler(nil, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/labels", "PUT", GetBody()
  end),

  delete_issue_labels = function(owner, repo_name, issue_number)
    proxy_204(
      { 200 },
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/" .. issue_number .. "/labels",
        "DELETE"
      )
    )
  end,

  delete_issue_label = function(owner, repo_name, issue_number, label_name)
    proxy_204(
      { 200 },
      fetch_json(
        base()
          .. "/repos/"
          .. owner
          .. "/"
          .. repo_name
          .. "/issues/"
          .. issue_number
          .. "/labels/"
          .. label_name,
        "DELETE"
      )
    )
  end,

  post_issue_assignees = proxy_handler(nil, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/assignees",
      "POST",
      GetBody()
  end),

  delete_issue_assignees = proxy_handler(nil, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/assignees",
      "DELETE",
      GetBody()
  end),

  get_repo_assignees = proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/assignees", PAGES)
  end),

  get_repo_labels = proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/labels", PAGES)
  end),

  post_repo_labels = proxy_handler_created(nil, function(o, r)
    return base() .. "/repos/" .. o .. "/" .. r .. "/labels", "POST", GetBody()
  end),

  get_repo_label = proxy_handler(nil, function(o, r, name)
    return base() .. "/repos/" .. o .. "/" .. r .. "/labels/" .. name
  end),

  patch_repo_label = proxy_handler(nil, function(o, r, name)
    return base() .. "/repos/" .. o .. "/" .. r .. "/labels/" .. name, "PATCH", GetBody()
  end),

  delete_repo_label = function(owner, repo_name, label_name)
    proxy_204(
      { 200 },
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/labels/" .. label_name,
        "DELETE"
      )
    )
  end,

  get_repo_milestones = proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/milestones", PAGES)
  end),

  get_repo_milestone = proxy_handler(nil, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/milestones/" .. n
  end),

  get_repo_milestone_labels = proxy_handler(nil, function(o, r, n)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/milestones/" .. n .. "/labels",
      PAGES
    )
  end),

  -- Legacy team-by-id API (/teams/{team_id}) ------------------------------------

  get_user_teams = proxy_handler(nil, function()
    return append_page_params(base() .. "/user/teams", PAGES)
  end),

  get_team = proxy_handler(nil, function(team_id)
    return base() .. "/teams/" .. team_id
  end),

  patch_team = function(team_id)
    proxy_json(nil, fetch_json(base() .. "/teams/" .. team_id, "PATCH", GetBody()))
  end,

  delete_team = function(team_id)
    proxy_204({ 200 }, fetch_json(base() .. "/teams/" .. team_id, "DELETE"))
  end,

  get_team_invitations = proxy_handler(nil, function(team_id)
    return append_page_params(base() .. "/teams/" .. team_id .. "/invitations", PAGES)
  end),

  get_team_members = proxy_handler(nil, function(team_id)
    return append_page_params(base() .. "/teams/" .. team_id .. "/members", PAGES)
  end),

  get_team_member = function(team_id, username)
    local ok, status =
      pcall(Fetch, base() .. "/teams/" .. team_id .. "/members/" .. username, auth())
    if ok and status == 204 then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(404, { message = "Not Found" })
    else
      respond_json(503, {})
    end
  end,

  put_team_member = function(team_id, username)
    set_204_or_error("PUT", base() .. "/teams/" .. team_id .. "/members/" .. username)
  end,

  delete_team_member = function(team_id, username)
    set_204_or_error("DELETE", base() .. "/teams/" .. team_id .. "/members/" .. username)
  end,

  get_team_membership = proxy_handler(nil, function(team_id, username)
    return base() .. "/teams/" .. team_id .. "/memberships/" .. username
  end),

  put_team_membership = function(team_id, username)
    proxy_json(
      nil,
      fetch_json(base() .. "/teams/" .. team_id .. "/memberships/" .. username, "PUT", GetBody())
    )
  end,

  delete_team_membership = function(team_id, username)
    proxy_204(
      { 200 },
      fetch_json(base() .. "/teams/" .. team_id .. "/memberships/" .. username, "DELETE")
    )
  end,

  get_team_repos = proxy_handler(nil, function(team_id)
    return append_page_params(base() .. "/teams/" .. team_id .. "/repos", PAGES)
  end),

  get_team_repo = proxy_handler(nil, function(team_id, owner, repo_name)
    return base() .. "/teams/" .. team_id .. "/repos/" .. owner .. "/" .. repo_name
  end),

  put_team_repo = function(team_id, owner, repo_name)
    proxy_204(
      { 200 },
      fetch_json(
        base() .. "/teams/" .. team_id .. "/repos/" .. owner .. "/" .. repo_name,
        "PUT",
        GetBody()
      )
    )
  end,

  delete_team_repo = function(team_id, owner, repo_name)
    proxy_204(
      { 200 },
      fetch_json(base() .. "/teams/" .. team_id .. "/repos/" .. owner .. "/" .. repo_name, "DELETE")
    )
  end,

  get_team_children = proxy_handler(nil, function(team_id)
    return append_page_params(base() .. "/teams/" .. team_id .. "/teams", PAGES)
  end),

  -- Pull Requests (GitHub-compatible passthrough) --------------------------------

  get_repo_pulls = proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/pulls", PAGES)
  end),

  post_repo_pulls = function(owner, repo_name)
    proxy_json_created(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/pulls", "POST", GetBody())
    )
  end,

  get_repo_pull = proxy_handler(nil, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/pulls/" .. n
  end),

  patch_repo_pull = function(owner, repo_name, pull_number)
    proxy_json(
      nil,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/pulls/" .. pull_number,
        "PATCH",
        GetBody()
      )
    )
  end,

  get_pull_commits = proxy_handler(nil, function(o, r, n)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/pulls/" .. n .. "/commits",
      PAGES
    )
  end),

  get_pull_files = proxy_handler(nil, function(o, r, n)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/pulls/" .. n .. "/files",
      PAGES
    )
  end),

  get_pull_merge = function(owner, repo_name, pull_number)
    local ok, status = pcall(
      Fetch,
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/pulls/" .. pull_number .. "/merge",
      auth()
    )
    if ok and status == 204 then
      SetStatus(204, "No Content")
    elseif ok and status == 404 then
      respond_json(404, { message = "Pull Request is not merged" })
    elseif ok then
      respond_json(status, {})
    else
      respond_json(503, {})
    end
  end,

  put_pull_merge = function(owner, repo_name, pull_number)
    proxy_204(
      nil,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/pulls/" .. pull_number .. "/merge",
        "PUT",
        GetBody()
      )
    )
  end,

  get_pull_requested_reviewers = proxy_handler(nil, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/pulls/" .. n .. "/requested_reviewers"
  end),

  get_pull_reviews = proxy_handler(nil, function(o, r, n)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/pulls/" .. n .. "/reviews",
      PAGES
    )
  end),

  get_pull_review = proxy_handler(nil, function(o, r, n, review_id)
    return base() .. "/repos/" .. o .. "/" .. r .. "/pulls/" .. n .. "/reviews/" .. review_id
  end),

  get_pull_review_comments = proxy_handler(nil, function(o, r, n, review_id)
    return append_page_params(
      base()
        .. "/repos/"
        .. o
        .. "/"
        .. r
        .. "/pulls/"
        .. n
        .. "/reviews/"
        .. review_id
        .. "/comments",
      PAGES
    )
  end),

  get_pull_comments = proxy_handler(nil, function(o, r, n)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/pulls/" .. n .. "/comments",
      PAGES
    )
  end),

  -- Search -------------------------------------------------------------------
  -- GitBucket's GitHub-compatible API exposes /api/v3/search/{repositories,users}
  -- which return the GitHub search envelope format directly — no translation needed.
  search_repositories = proxy_handler(nil, function()
    local q = GetParam("q") or ""
    return append_page_params(base() .. "/search/repositories?q=" .. q, PAGES)
  end),

  search_users = proxy_handler(nil, function()
    local q = GetParam("q") or ""
    return append_page_params(base() .. "/search/users?q=" .. q, PAGES)
  end),

  -- Git database --------------------------------------------------------------

  get_git_blob = proxy_handler(nil, function(o, r, sha)
    return base() .. "/repos/" .. o .. "/" .. r .. "/git/blobs/" .. sha
  end),

  get_git_commit = proxy_handler(nil, function(o, r, sha)
    return base() .. "/repos/" .. o .. "/" .. r .. "/git/commits/" .. sha
  end),

  list_git_matching_refs = proxy_handler(nil, function(o, r, ref)
    return base() .. "/repos/" .. o .. "/" .. r .. "/git/matching-refs/" .. ref
  end),

  get_git_ref = proxy_handler(nil, function(o, r, ref)
    return base() .. "/repos/" .. o .. "/" .. r .. "/git/ref/" .. ref
  end),

  create_git_ref = function(owner, repo_name)
    proxy_json_created(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/refs", "POST", GetBody())
    )
  end,

  delete_git_ref = function(owner, repo_name, ref)
    set_204_or_error(
      "DELETE",
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/refs/" .. ref
    )
  end,

  get_git_tag = proxy_handler(nil, function(o, r, sha)
    return base() .. "/repos/" .. o .. "/" .. r .. "/git/tags/" .. sha
  end),

  create_git_tag = function(owner, repo_name)
    proxy_json_created(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/tags", "POST", GetBody())
    )
  end,

  get_git_tree = proxy_handler(nil, function(o, r, sha)
    return base() .. "/repos/" .. o .. "/" .. r .. "/git/trees/" .. sha
  end),

  -- Gists (GitHub-compatible passthrough) ------------------------------------
  get_gists = proxy_handler(nil, function()
    return base() .. "/gists"
  end),
  post_gists = function()
    proxy_json_created(nil, fetch_json(base() .. "/gists", "POST", GetBody()))
  end,
  get_gists_public = proxy_handler(nil, function()
    return base() .. "/gists/public"
  end),
  get_gists_starred = proxy_handler(nil, function()
    return base() .. "/gists/starred"
  end),
  get_gist = proxy_handler(nil, function(id)
    return base() .. "/gists/" .. id
  end),
  patch_gist = function(id)
    proxy_json(nil, fetch_json(base() .. "/gists/" .. id, "PATCH", GetBody()))
  end,
  delete_gist = function(id)
    set_204_or_error("DELETE", base() .. "/gists/" .. id)
  end,
  get_gist_comments = proxy_handler(nil, function(id)
    return base() .. "/gists/" .. id .. "/comments"
  end),
  post_gist_comment = function(id)
    proxy_json_created(nil, fetch_json(base() .. "/gists/" .. id .. "/comments", "POST", GetBody()))
  end,
  get_gist_comment = proxy_handler(nil, function(id, cid)
    return base() .. "/gists/" .. id .. "/comments/" .. cid
  end),
  patch_gist_comment = function(id, cid)
    proxy_json(
      nil,
      fetch_json(base() .. "/gists/" .. id .. "/comments/" .. cid, "PATCH", GetBody())
    )
  end,
  delete_gist_comment = function(id, cid)
    set_204_or_error("DELETE", base() .. "/gists/" .. id .. "/comments/" .. cid)
  end,
  get_gist_commits = proxy_handler(nil, function(id)
    return base() .. "/gists/" .. id .. "/commits"
  end),
  get_gist_forks = proxy_handler(nil, function(id)
    return base() .. "/gists/" .. id .. "/forks"
  end),
  get_gist_star = function(id)
    set_204_or_error("GET", base() .. "/gists/" .. id .. "/star")
  end,
  put_gist_star = function(id)
    set_204_or_error("PUT", base() .. "/gists/" .. id .. "/star")
  end,
  delete_gist_star = function(id)
    set_204_or_error("DELETE", base() .. "/gists/" .. id .. "/star")
  end,
  get_gist_revision = proxy_handler(nil, function(id, sha)
    return base() .. "/gists/" .. id .. "/" .. sha
  end),
  get_user_gists = proxy_handler(nil, function(user)
    return base() .. "/users/" .. user .. "/gists"
  end),
}

-- ---------------------------------------------------------------------------
-- GraphQL resolvers
-- ---------------------------------------------------------------------------

-- Local pagination parameters for graphql_cursor_url.
-- GitBucket uses GitHub-compatible per_page / page query parameters.
local GQL_PAGES = { per_page = "per_page", page = "page" }

-- Headers GitBucket may return for the total item count (optional; absent on some endpoints).
local GB_TOTAL_HEADERS = { "X-Total", "X-Total-Count" }

-- Local helper: extract total from GitBucket response headers (nil when absent).
local function gb_total(headers)
  return (headers["X-Total"] and tonumber(headers["X-Total"]))
    or (headers["X-Total-Count"] and tonumber(headers["X-Total-Count"]))
end

-- Local helper: build a paginated Relay Connection from a GitBucket list endpoint.
-- GitBucket may return X-Total / X-Total-Count headers; if absent, the connection
-- builder falls back to the count == per_page heuristic for hasNextPage.
-- For backward pagination (last without before), prefetches total via a per_page=1 request
-- when headers are expected; falls back to heuristic when not available.
local function gb_repo_connection(owner, repo_name, suffix, args, ctx, translate_fn, make_conn)
  local url_base = base() .. "/repos/" .. owner .. "/" .. repo_name .. suffix
  local total
  if args.last and not args.before then
    total = graphql_prefetch_total_from_headers(fetch_json, url_base, GQL_PAGES, GB_TOTAL_HEADERS)
  end
  local url = graphql_cursor_url(url_base, args, GQL_PAGES, total)
  local data, headers, err = graphql_fetch_with_headers(fetch_json, url)
  if not data then
    graphql_error(ctx, err)
    return nil
  end
  total = gb_total(headers) or total
  local nodes = {}
  for _, item in ipairs(data) do
    nodes[#nodes + 1] = translate_fn(item)
  end
  return make_conn(nodes, args, total, ctx)
end

-- Query.repositoryOwner: look up a User or Organization by login.
-- Tries /users/{login} first; falls back to /orgs/{login}.
graphql_resolvers["Query.repositoryOwner"] = function(_parent, args, ctx)
  if not args.login then
    graphql_error(ctx, "repositoryOwner requires a login argument")
    return nil
  end
  local udata, _ = graphql_fetch(fetch_json, base() .. "/users/" .. args.login)
  if udata then
    return graphql_translate_user(udata)
  end
  local odata, _ = graphql_fetch(fetch_json, base() .. "/orgs/" .. args.login)
  if odata then
    return graphql_translate_org(odata)
  end
  return nil
end

-- Query.viewer: resolve the authenticated user via GET /user.
graphql_resolvers["Query.viewer"] = function(_parent, _args, ctx)
  local data = graphql_fetch_or_error(fetch_json, base() .. "/user", ctx, nil)
  if not data then
    return nil
  end
  local u = graphql_translate_user(data)
  u.isViewer = true
  return u
end

-- Query.user: look up a User by login.
graphql_resolvers["Query.user"] = function(_parent, args, ctx)
  if not args.login then
    graphql_error(ctx, "user requires a login argument")
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, base() .. "/users/" .. args.login)
  if not data then
    return nil
  end
  return graphql_translate_user(data)
end

-- Query.organization: look up an Organization by login.
graphql_resolvers["Query.organization"] = function(_parent, args, ctx)
  if not args.login then
    graphql_error(ctx, "organization requires a login argument")
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, base() .. "/orgs/" .. args.login)
  if not data then
    return nil
  end
  return graphql_translate_org(data)
end

-- Query.repository: look up a Repository by owner and name.
graphql_resolvers["Query.repository"] = function(_parent, args, ctx)
  if not args.owner or not args.name then
    graphql_error(ctx, "repository requires owner and name arguments")
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, base() .. "/repos/" .. args.owner .. "/" .. args.name)
  if not data then
    return nil
  end
  return graphql_translate_repo(data)
end

-- node.Repository: fetch a repository by "owner/repo" local ID.
graphql_resolvers["node.Repository"] = function(local_id, _ctx)
  local data, _ = graphql_fetch(fetch_json, base() .. "/repos/" .. local_id)
  if not data then
    return nil
  end
  return graphql_translate_repo(data)
end

-- node.User: fetch a user by login.
graphql_resolvers["node.User"] = function(local_id, _ctx)
  local data, _ = graphql_fetch(fetch_json, base() .. "/users/" .. local_id)
  if not data then
    return nil
  end
  return graphql_translate_user(data)
end

-- node.Organization: fetch an organization by login.
graphql_resolvers["node.Organization"] = function(local_id, _ctx)
  local data, _ = graphql_fetch(fetch_json, base() .. "/orgs/" .. local_id)
  if not data then
    return nil
  end
  return graphql_translate_org(data)
end

-- node.Issue: fetch an issue by "owner/repo/number" local ID.
graphql_resolvers["node.Issue"] = function(local_id, _ctx)
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ =
    graphql_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo .. "/issues/" .. number)
  if not data then
    return nil
  end
  return graphql_translate_issue(data, owner, repo)
end

-- node.PullRequest: fetch a pull request by "owner/repo/number" local ID.
graphql_resolvers["node.PullRequest"] = function(local_id, _ctx)
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ =
    graphql_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo .. "/pulls/" .. number)
  if not data then
    return nil
  end
  return graphql_translate_pr(data, owner, repo)
end

-- node.IssueComment: fetch an issue comment by "owner/repo/comment_id" local ID.
graphql_resolvers["node.IssueComment"] = function(local_id, _ctx)
  local owner, repo, cid = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ = graphql_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo .. "/issues/comments/" .. cid
  )
  if not data then
    return nil
  end
  return graphql_translate_comment(data, owner, repo)
end

-- node.Release: fetch a release by "owner/repo/release_id" local ID.
graphql_resolvers["node.Release"] = function(local_id, _ctx)
  local owner, repo, rid = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ =
    graphql_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo .. "/releases/" .. rid)
  if not data then
    return nil
  end
  return graphql_translate_release(data, owner, repo)
end

-- node.Label: fetch a label by "owner/repo/label_id" local ID.
graphql_resolvers["node.Label"] = function(local_id, _ctx)
  local owner, repo, lid = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ =
    graphql_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo .. "/labels/" .. lid)
  if not data then
    return nil
  end
  return graphql_translate_label(data, owner, repo)
end

-- node.Milestone: fetch a milestone by "owner/repo/number" local ID.
graphql_resolvers["node.Milestone"] = function(local_id, _ctx)
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ = graphql_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo .. "/milestones/" .. number
  )
  if not data then
    return nil
  end
  return graphql_translate_milestone(data, owner, repo)
end

-- node.Commit: fetch a commit by "owner/repo/sha" local ID.
graphql_resolvers["node.Commit"] = function(local_id, _ctx)
  local owner, repo, sha = local_id:match("^([^/]+)/([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  local data, _ =
    graphql_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo .. "/commits/" .. sha)
  if not data then
    return nil
  end
  return graphql_translate_commit(data, owner, repo)
end

-- node.Ref: fetch a branch ref by "owner/repo/refs/heads/..." local ID.
-- GitBucket branch objects are GitHub-compatible (commit.sha already present).
graphql_resolvers["node.Ref"] = function(local_id, _ctx)
  local owner, repo, ref_path = local_id:match("^([^/]+)/([^/]+)/(refs/.+)$")
  if not owner then
    return nil
  end
  local branch = ref_path:match("^refs/heads/(.+)$")
  if not branch then
    return nil
  end
  local data, _ =
    graphql_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo .. "/branches/" .. branch)
  if not data then
    return nil
  end
  local repo_stub = { __typename = "Repository", nameWithOwner = owner .. "/" .. repo }
  return graphql_translate_ref(data, repo_stub)
end

-- node.Team: fetch a team by "org/slug" local ID.
-- GitBucket is GitHub-compatible; /orgs/{org}/teams/{slug} returns the team directly.
graphql_resolvers["node.Team"] = function(local_id, _ctx)
  local org, slug = local_id:match("^([^/]+)/([^/]+)$")
  if not org then
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, base() .. "/orgs/" .. org .. "/teams/" .. slug)
  if not data then
    return nil
  end
  return graphql_translate_team(data, org)
end

-- ---------------------------------------------------------------------------
-- Repository connection sub-resolvers
-- ---------------------------------------------------------------------------

-- Repository.issues: paginated list of issues.
-- GitBucket's issue list includes PRs (like GitHub); filter them out by checking
-- the pull_request field.
graphql_resolvers["Repository.issues"] = function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  local url_base = base() .. "/repos/" .. owner .. "/" .. name .. "/issues"
  local total
  if args.last and not args.before then
    total = graphql_prefetch_total_from_headers(fetch_json, url_base, GQL_PAGES, GB_TOTAL_HEADERS)
  end
  local url = graphql_cursor_url(url_base, args, GQL_PAGES, total)
  local data, headers, err = graphql_fetch_with_headers(fetch_json, url)
  if not data then
    graphql_error(ctx, err)
    return nil
  end
  total = gb_total(headers) or total
  local nodes = {}
  for _, item in ipairs(data) do
    if not item.pull_request then
      nodes[#nodes + 1] = graphql_translate_issue(item, owner, name)
    end
  end
  return graphql_issues_connection(nodes, args, total, ctx)
end

-- Repository.pullRequests: paginated list of pull requests.
graphql_resolvers["Repository.pullRequests"] = function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gb_repo_connection(owner, name, "/pulls", args, ctx, function(p)
    return graphql_translate_pr(p, owner, name)
  end, graphql_prs_connection)
end

-- Repository.releases: paginated list of releases.
graphql_resolvers["Repository.releases"] = function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gb_repo_connection(owner, name, "/releases", args, ctx, function(r)
    return graphql_translate_release(r, owner, name)
  end, function(n, a, t, c)
    return graphql_make_connection("Release", n, a, t, c)
  end)
end

-- Repository.labels: paginated list of labels.
graphql_resolvers["Repository.labels"] = function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gb_repo_connection(owner, name, "/labels", args, ctx, function(l)
    return graphql_translate_label(l, owner, name)
  end, graphql_labels_connection)
end

-- Repository.milestones: paginated list of milestones.
graphql_resolvers["Repository.milestones"] = function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gb_repo_connection(owner, name, "/milestones", args, ctx, function(m)
    return graphql_translate_milestone(m, owner, name)
  end, function(n, a, t, c)
    return graphql_make_connection("Milestone", n, a, t, c)
  end)
end

-- Repository.refs: paginated list of branches as Ref objects.
-- GitBucket branch objects already include commit.sha (GitHub-compatible);
-- no commit.id → commit.sha normalisation needed.
graphql_resolvers["Repository.refs"] = function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gb_repo_connection(owner, name, "/branches", args, ctx, function(b)
    return graphql_translate_ref(b, parent)
  end, graphql_refs_connection)
end

-- Issue.comments: paginated list of comments for a single issue.
graphql_resolvers["Issue.comments"] = function(parent, args, ctx)
  local _, local_id = decode_node_id(parent.id)
  if not local_id then
    return nil
  end
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local url_base = base()
    .. "/repos/"
    .. owner
    .. "/"
    .. repo
    .. "/issues/"
    .. number
    .. "/comments"
  local total
  if args.last and not args.before then
    total = graphql_prefetch_total_from_headers(fetch_json, url_base, GQL_PAGES, GB_TOTAL_HEADERS)
  end
  local url = graphql_cursor_url(url_base, args, GQL_PAGES, total)
  local data, headers, err = graphql_fetch_with_headers(fetch_json, url)
  if not data then
    graphql_error(ctx, err)
    return nil
  end
  total = gb_total(headers) or total
  local nodes = {}
  for _, c in ipairs(data) do
    nodes[#nodes + 1] = graphql_translate_comment(c, owner, repo)
  end
  return graphql_make_connection("IssueComment", nodes, args, total, ctx)
end

-- PullRequest.commits: paginated commit list for a pull request.
graphql_resolvers["PullRequest.commits"] = function(parent, args, ctx)
  local _, local_id = decode_node_id(parent.id)
  if not local_id then
    return nil
  end
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local url_base = base() .. "/repos/" .. owner .. "/" .. repo .. "/pulls/" .. number .. "/commits"
  local total
  if args.last and not args.before then
    total = graphql_prefetch_total_from_headers(fetch_json, url_base, GQL_PAGES, GB_TOTAL_HEADERS)
  end
  local url = graphql_cursor_url(url_base, args, GQL_PAGES, total)
  local data, headers, err = graphql_fetch_with_headers(fetch_json, url)
  if not data then
    graphql_error(ctx, err)
    return nil
  end
  total = gb_total(headers) or total
  -- PullRequest.commits returns PullRequestCommitConnection, whose nodes are
  -- PullRequestCommit objects wrapping bare Commit objects.
  local nodes = {}
  for _, c in ipairs(data) do
    local sha = c.sha or ""
    nodes[#nodes + 1] = {
      __typename = "PullRequestCommit",
      id = encode_node_id("PullRequestCommit", sha),
      commit = graphql_translate_commit(c, owner, repo),
      url = c.html_url,
    }
  end
  return graphql_make_connection("PullRequestCommit", nodes, args, total, ctx)
end

-- PullRequest.reviews: paginated review list for a pull request.
graphql_resolvers["PullRequest.reviews"] = function(parent, args, ctx)
  local _, local_id = decode_node_id(parent.id)
  if not local_id then
    return nil
  end
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local url = graphql_cursor_url(
    base() .. "/repos/" .. owner .. "/" .. repo .. "/pulls/" .. number .. "/reviews",
    args,
    GQL_PAGES
  )
  local data, headers, err = graphql_fetch_with_headers(fetch_json, url)
  if not data then
    graphql_error(ctx, err)
    return nil
  end
  local total = (headers["X-Total"] and tonumber(headers["X-Total"]))
    or (headers["X-Total-Count"] and tonumber(headers["X-Total-Count"]))
  local nodes = {}
  for _, r in ipairs(data) do
    nodes[#nodes + 1] = graphql_translate_review(r, owner, repo)
  end
  return graphql_make_connection("PullRequestReview", nodes, args, total, ctx)
end

-- Repository.collaborators: paginated list of collaborators as Users.
graphql_resolvers["Repository.collaborators"] = function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gb_repo_connection(owner, name, "/collaborators", args, ctx, function(u)
    return graphql_translate_user(u)
  end, function(n, a, t, c)
    return graphql_make_connection("RepositoryCollaborator", n, a, t, c)
  end)
end

-- Repository.defaultBranchRef: enrich the inline stub with full branch data.
-- The parent already carries {__typename="Ref",name="main"} from graphql_translate_repo.
graphql_resolvers["Repository.defaultBranchRef"] = function(parent, _args, _ctx)
  local branch = parent.defaultBranchRef and parent.defaultBranchRef.name
  if not branch then
    return nil
  end
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  local data, _ =
    graphql_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. name .. "/branches/" .. branch)
  if not data then
    return nil
  end
  return graphql_translate_ref(data, parent)
end

-- Repository.languages: fetch language byte-count breakdown as a LanguageConnection.
-- GitBucket returns {"Language": bytes, ...}; we convert to the Relay Connection shape.
graphql_resolvers["Repository.languages"] = function(parent, _args, _ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  local data, _ =
    graphql_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. name .. "/languages")
  if not data then
    return nil
  end
  local nodes, edges = {}, {}
  local total_size = 0
  for lang_name, size in pairs(data) do
    total_size = total_size + size
    local node = {
      __typename = "Language",
      id = encode_node_id("Language", lang_name),
      name = lang_name,
      color = nil,
    }
    nodes[#nodes + 1] = node
    edges[#edges + 1] = { cursor = "", node = node, size = size }
  end
  return {
    __typename = "LanguageConnection",
    totalCount = #nodes,
    totalSize = total_size,
    pageInfo = {
      __typename = "PageInfo",
      hasNextPage = false,
      hasPreviousPage = false,
      startCursor = nil,
      endCursor = nil,
    },
    nodes = nodes,
    edges = edges,
  }
end

-- ---------------------------------------------------------------------------
-- Query.search
-- ---------------------------------------------------------------------------

-- Query.search: map GitHub GraphQL search to GitBucket search endpoints.
-- GitBucket exposes GitHub-compatible /search/{repositories,users} returning
-- the standard {total_count, items} envelope.
-- ISSUE search is not supported (GitBucket has no /search/issues endpoint).
graphql_resolvers["Query.search"] = function(_parent, args, _ctx)
  local query = args.query or ""
  local search_type = args.type or "REPOSITORY"
  local per_page = args.first or 30
  local q = EscapeParam(query)

  local nodes = {}
  local repo_count, user_count, issue_count = 0, 0, 0

  if search_type == "REPOSITORY" then
    local data, _ = graphql_fetch(
      fetch_json,
      base() .. "/search/repositories?q=" .. q .. "&per_page=" .. per_page
    )
    if data and data.items then
      for _, r in ipairs(data.items) do
        nodes[#nodes + 1] = graphql_translate_repo(r)
      end
      repo_count = data.total_count or #nodes
    end
  elseif search_type == "USER" then
    local data, _ =
      graphql_fetch(fetch_json, base() .. "/search/users?q=" .. q .. "&per_page=" .. per_page)
    if data and data.items then
      for _, u in ipairs(data.items) do
        nodes[#nodes + 1] = graphql_translate_user(u)
      end
      user_count = data.total_count or #nodes
    end
  end

  local edges = {}
  for i, node in ipairs(nodes) do
    edges[i] = {
      __typename = "SearchResultItemEdge",
      cursor = graphql_page_to_cursor(1, i),
      node = node,
    }
  end
  local n = #edges
  return {
    __typename = "SearchResultItemConnection",
    nodes = nodes,
    edges = edges,
    pageInfo = {
      __typename = "PageInfo",
      hasNextPage = false,
      hasPreviousPage = false,
      startCursor = n > 0 and edges[1].cursor or nil,
      endCursor = n > 0 and edges[n].cursor or nil,
    },
    repositoryCount = repo_count,
    userCount = user_count,
    issueCount = issue_count,
    codeCount = 0,
    discussionCount = 0,
    wikiCount = 0,
  }
end
