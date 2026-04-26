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

local b = make_backend_builder()
b:rest("get_root", function()
  proxy_health_check(pcall(Fetch, base() .. "/rate_limit", auth()))
end)

b:rest(
  "get_rate_limit",
  proxy_handler(function(data)
    return { rate = data.rate or data }
  end, function()
    return base() .. "/rate_limit"
  end)
)

b:rest(
  "get_repo",
  proxy_handler(nil, function(o, r)
    return base() .. "/repos/" .. o .. "/" .. r
  end)
)

b:rest("patch_repo", function(owner, repo_name)
  proxy_json(nil, fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name, "PATCH", GetBody()))
end)

b:rest("delete_repo", function(owner, repo_name)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name
  local dopts = auth() or {}
  dopts.method = "DELETE"
  proxy_204(nil, pcall(Fetch, url, dopts))
end)

b:rest(
  "get_user_repos",
  proxy_handler(nil, function()
    return append_page_params(base() .. "/user/repos", PAGES)
  end)
)

b:rest("post_user_repos", function()
  proxy_json_created(nil, fetch_json(base() .. "/user/repos", "POST", GetBody()))
end)

b:rest(
  "get_org_repos",
  proxy_handler(nil, function(org)
    return append_page_params(base() .. "/orgs/" .. org .. "/repos", PAGES)
  end)
)

b:rest("post_org_repos", function(org)
  proxy_json_created(nil, fetch_json(base() .. "/orgs/" .. org .. "/repos", "POST", GetBody()))
end)

b:rest(
  "get_repo_topics",
  proxy_handler(nil, function(o, r)
    return base() .. "/repos/" .. o .. "/" .. r .. "/topics"
  end)
)

b:rest("put_repo_topics", function(owner, repo_name)
  proxy_json(
    nil,
    fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/topics", "PUT", GetBody())
  )
end)

b:rest(
  "get_repo_languages",
  proxy_handler(nil, function(o, r)
    return base() .. "/repos/" .. o .. "/" .. r .. "/languages"
  end)
)

b:rest(
  "get_repo_contributors",
  proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/contributors", PAGES)
  end)
)

b:rest(
  "get_repo_tags",
  proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/tags", PAGES)
  end)
)

b:rest(
  "get_repo_teams",
  proxy_handler(nil, function(o, r)
    return base() .. "/repos/" .. o .. "/" .. r .. "/teams"
  end)
)

-- Branches ------------------------------------------------------------------
b:rest(
  "get_repo_branches",
  proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/branches", PAGES)
  end)
)

b:rest(
  "get_repo_branch",
  proxy_handler(nil, function(o, r, branch)
    return base() .. "/repos/" .. o .. "/" .. r .. "/branches/" .. branch
  end)
)

-- Commits -------------------------------------------------------------------
b:rest(
  "get_repo_commits",
  proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/commits", PAGES)
  end)
)

b:rest(
  "get_repo_commit",
  proxy_handler(nil, function(o, r, ref)
    return base() .. "/repos/" .. o .. "/" .. r .. "/commits/" .. ref
  end)
)

-- Statuses ------------------------------------------------------------------
b:rest(
  "get_commit_statuses",
  proxy_handler(nil, function(o, r, ref)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/statuses/" .. ref, PAGES)
  end)
)

b:rest(
  "get_commit_combined_status",
  proxy_handler(nil, function(o, r, ref)
    return base() .. "/repos/" .. o .. "/" .. r .. "/commits/" .. ref .. "/status"
  end)
)

b:rest("post_commit_status", function(owner, repo_name, sha)
  proxy_json_created(
    nil,
    fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/statuses/" .. sha,
      "POST",
      GetBody()
    )
  )
end)

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

b:rest("post_check_runs", function(owner, repo_name)
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
end)

b:rest("get_commit_check_runs", function(owner, repo_name, ref)
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
end)

-- Check suites have no GitBucket equivalent; all suite endpoints fall back
-- to the route_defaults stubs defined in .init.lua.

-- Licenses ------------------------------------------------------------------
b:rest(
  "get_licenses",
  proxy_handler(nil, function()
    return base() .. "/licenses"
  end)
)

b:rest(
  "get_license",
  proxy_handler(nil, function(license_name)
    return base() .. "/licenses/" .. license_name
  end)
)

b:rest(
  "get_repo_license",
  proxy_handler(nil, function(o, r)
    return base() .. "/repos/" .. o .. "/" .. r .. "/license"
  end)
)

-- Contents ------------------------------------------------------------------
b:rest(
  "get_repo_readme",
  proxy_handler(nil, function(o, r)
    return base() .. "/repos/" .. o .. "/" .. r .. "/readme"
  end)
)

b:rest(
  "get_repo_readme_dir",
  proxy_handler(nil, function(o, r, dir)
    return base() .. "/repos/" .. o .. "/" .. r .. "/readme/" .. dir
  end)
)

b:rest(
  "get_repo_content",
  proxy_handler(nil, function(o, r, path)
    return base() .. "/repos/" .. o .. "/" .. r .. "/contents/" .. path
  end)
)

b:rest("put_repo_content", function(owner, repo_name, path)
  proxy_json(
    nil,
    fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/contents/" .. path,
      "PUT",
      GetBody()
    )
  )
end)

b:rest("delete_repo_content", function(owner, repo_name, path)
  proxy_json(
    nil,
    fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/contents/" .. path,
      "DELETE",
      GetBody()
    )
  )
end)

b:rest("get_repo_tarball", function(owner, repo_name, ref)
  SetStatus(302, "Found")
  SetHeader("Location", base() .. "/repos/" .. owner .. "/" .. repo_name .. "/tarball/" .. ref)
  Write("")
end)

b:rest("get_repo_zipball", function(owner, repo_name, ref)
  SetStatus(302, "Found")
  SetHeader("Location", base() .. "/repos/" .. owner .. "/" .. repo_name .. "/zipball/" .. ref)
  Write("")
end)

-- Compare -------------------------------------------------------------------
b:rest(
  "get_repo_compare",
  proxy_handler(nil, function(o, r, basehead)
    return base() .. "/repos/" .. o .. "/" .. r .. "/compare/" .. basehead
  end)
)

-- Collaborators -------------------------------------------------------------
b:rest(
  "get_repo_collaborators",
  proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/collaborators", PAGES)
  end)
)

b:rest("get_repo_collaborator", function(owner, repo_name, username)
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
end)

b:rest("put_repo_collaborator", function(owner, repo_name, username)
  proxy_204(
    { 201 },
    fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/collaborators/" .. username,
      "PUT",
      GetBody()
    )
  )
end)

b:rest("delete_repo_collaborator", function(owner, repo_name, username)
  proxy_204(
    { 200 },
    fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/collaborators/" .. username,
      "DELETE"
    )
  )
end)

b:rest(
  "get_repo_collaborator_permission",
  proxy_handler(nil, function(o, r, username)
    return base() .. "/repos/" .. o .. "/" .. r .. "/collaborators/" .. username .. "/permission"
  end)
)

-- Forks ---------------------------------------------------------------------
b:rest(
  "get_repo_forks",
  proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/forks", PAGES)
  end)
)

b:rest("post_repo_forks", function(owner, repo_name)
  proxy_json_created(
    nil,
    fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/forks", "POST", GetBody())
  )
end)

-- Releases ------------------------------------------------------------------
b:rest(
  "get_repo_releases",
  proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/releases", PAGES)
  end)
)

b:rest("post_repo_releases", function(owner, repo_name)
  proxy_json_created(
    nil,
    fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases", "POST", GetBody())
  )
end)

b:rest(
  "get_repo_release_latest",
  proxy_handler(nil, function(o, r)
    return base() .. "/repos/" .. o .. "/" .. r .. "/releases/latest"
  end)
)

b:rest(
  "get_repo_release_by_tag",
  proxy_handler(nil, function(o, r, tag)
    return base() .. "/repos/" .. o .. "/" .. r .. "/releases/tags/" .. tag
  end)
)

b:rest(
  "get_repo_release",
  proxy_handler(nil, function(o, r, id)
    return base() .. "/repos/" .. o .. "/" .. r .. "/releases/" .. id
  end)
)

b:rest("patch_repo_release", function(owner, repo_name, release_id)
  proxy_json(
    nil,
    fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/" .. release_id,
      "PATCH",
      GetBody()
    )
  )
end)

b:rest("delete_repo_release", function(owner, repo_name, release_id)
  proxy_204(
    { 200 },
    fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/" .. release_id,
      "DELETE"
    )
  )
end)

b:rest(
  "get_repo_release_assets",
  proxy_handler(nil, function(o, r, id)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/releases/" .. id .. "/assets",
      PAGES
    )
  end)
)

b:rest("post_repo_release_assets", function(owner, repo_name, release_id)
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
end)

b:rest(
  "get_repo_release_asset",
  proxy_handler(nil, function(o, r, asset_id)
    return base() .. "/repos/" .. o .. "/" .. r .. "/releases/assets/" .. asset_id
  end)
)

b:rest("patch_repo_release_asset", function(owner, repo_name, asset_id)
  proxy_json(
    nil,
    fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/assets/" .. asset_id,
      "PATCH",
      GetBody()
    )
  )
end)

b:rest("delete_repo_release_asset", function(owner, repo_name, asset_id)
  proxy_204(
    { 200 },
    fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/assets/" .. asset_id,
      "DELETE"
    )
  )
end)

-- Deploy keys ---------------------------------------------------------------
b:rest(
  "get_repo_keys",
  proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/keys", PAGES)
  end)
)

b:rest("post_repo_keys", function(owner, repo_name)
  proxy_json_created(
    nil,
    fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/keys", "POST", GetBody())
  )
end)

b:rest(
  "get_repo_key",
  proxy_handler(nil, function(o, r, key_id)
    return base() .. "/repos/" .. o .. "/" .. r .. "/keys/" .. key_id
  end)
)

b:rest("delete_repo_key", function(owner, repo_name, key_id)
  proxy_204(
    { 200 },
    fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/keys/" .. key_id, "DELETE")
  )
end)

-- Webhooks ------------------------------------------------------------------
b:rest(
  "get_repo_hooks",
  proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/hooks", PAGES)
  end)
)

b:rest("post_repo_hooks", function(owner, repo_name)
  proxy_json_created(
    nil,
    fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks", "POST", GetBody())
  )
end)

b:rest(
  "get_repo_hook",
  proxy_handler(nil, function(o, r, hook_id)
    return base() .. "/repos/" .. o .. "/" .. r .. "/hooks/" .. hook_id
  end)
)

b:rest("patch_repo_hook", function(owner, repo_name, hook_id)
  proxy_json(
    nil,
    fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id,
      "PATCH",
      GetBody()
    )
  )
end)

b:rest("delete_repo_hook", function(owner, repo_name, hook_id)
  proxy_204(
    { 200 },
    fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id, "DELETE")
  )
end)

b:rest(
  "get_repo_hook_config",
  proxy_handler(function(h)
    return h.config or {}
  end, function(o, r, hook_id)
    return base() .. "/repos/" .. o .. "/" .. r .. "/hooks/" .. hook_id
  end)
)

b:rest("patch_repo_hook_config", function(owner, repo_name, hook_id)
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
end)

b:rest("post_repo_hook_ping", function(owner, repo_name, hook_id)
  proxy_204(
    { 200 },
    fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id .. "/pings",
      "POST"
    )
  )
end)

b:rest("post_repo_hook_test", function(owner, repo_name, hook_id)
  proxy_204(
    { 200 },
    fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id .. "/tests",
      "POST"
    )
  )
end)

-- Commit comments -----------------------------------------------------------
b:rest(
  "get_repo_comments",
  proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/comments", PAGES)
  end)
)

b:rest(
  "get_repo_comment",
  proxy_handler(nil, function(o, r, comment_id)
    return base() .. "/repos/" .. o .. "/" .. r .. "/comments/" .. comment_id
  end)
)

b:rest("patch_repo_comment", function(owner, repo_name, comment_id)
  proxy_json(
    nil,
    fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/comments/" .. comment_id,
      "PATCH",
      GetBody()
    )
  )
end)

b:rest("delete_repo_comment", function(owner, repo_name, comment_id)
  proxy_204(
    { 200 },
    fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/comments/" .. comment_id,
      "DELETE"
    )
  )
end)

b:rest(
  "get_commit_comments",
  proxy_handler(nil, function(o, r, sha)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/commits/" .. sha .. "/comments",
      PAGES
    )
  end)
)

b:rest("post_commit_comment", function(owner, repo_name, commit_sha)
  proxy_json_created(
    nil,
    fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/commits/" .. commit_sha .. "/comments",
      "POST",
      GetBody()
    )
  )
end)

-- GET /users/{username}/repos + public repos --------------------------------
b:rest(
  "get_users_repos",
  proxy_handler(nil, function(username)
    return append_page_params(base() .. "/users/" .. username .. "/repos", PAGES)
  end)
)

b:rest(
  "get_repositories",
  proxy_handler(nil, function()
    return append_page_params(base() .. "/repositories", PAGES)
  end)
)

-- Users (GitHub-compatible passthrough) -------------------------------------

b:rest(
  "get_user",
  proxy_handler(nil, function()
    return base() .. "/user"
  end)
)

b:rest("patch_user", function()
  proxy_json(nil, fetch_json(base() .. "/user", "PATCH", GetBody()))
end)

b:rest(
  "get_users_username",
  proxy_handler(nil, function(username)
    return base() .. "/users/" .. username
  end)
)

b:rest(
  "get_users",
  proxy_handler(nil, function()
    return append_page_params(base() .. "/users", PAGES)
  end)
)

b:rest(
  "get_user_followers",
  proxy_handler(nil, function()
    return append_page_params(base() .. "/user/followers", PAGES)
  end)
)

b:rest(
  "get_user_following",
  proxy_handler(nil, function()
    return append_page_params(base() .. "/user/following", PAGES)
  end)
)

b:rest("get_user_is_following", function(username)
  local ok, status = pcall(Fetch, base() .. "/user/following/" .. username, auth())
  if ok and status == 204 then
    SetStatus(204, "No Content")
  elseif ok then
    respond_json(404, { message = "Not Following" })
  else
    respond_json(503, {})
  end
end)

b:rest("put_user_following", function(username)
  set_204_or_error("PUT", base() .. "/user/following/" .. username)
end)

b:rest("delete_user_following", function(username)
  set_204_or_error("DELETE", base() .. "/user/following/" .. username)
end)

b:rest(
  "get_users_followers",
  proxy_handler(nil, function(username)
    return append_page_params(base() .. "/users/" .. username .. "/followers", PAGES)
  end)
)

b:rest(
  "get_users_following",
  proxy_handler(nil, function(username)
    return append_page_params(base() .. "/users/" .. username .. "/following", PAGES)
  end)
)

b:rest("get_users_is_following", function(username, target)
  local ok, status =
    pcall(Fetch, base() .. "/users/" .. username .. "/following/" .. target, auth())
  if ok and status == 204 then
    SetStatus(204, "No Content")
  elseif ok then
    respond_json(404, { message = "Not Following" })
  else
    respond_json(503, {})
  end
end)

b:rest(
  "get_user_emails",
  proxy_handler(nil, function()
    return base() .. "/user/emails"
  end)
)

b:rest("post_user_emails", function()
  proxy_json_created(nil, fetch_json(base() .. "/user/emails", "POST", GetBody()))
end)

b:rest("delete_user_emails", function()
  local opts = auth() or {}
  opts.method = "DELETE"
  opts.body = GetBody()
  opts.headers = opts.headers or {}
  opts.headers["Content-Type"] = "application/json"
  proxy_204({ 200 }, pcall(Fetch, base() .. "/user/emails", opts))
end)

b:rest(
  "get_user_keys",
  proxy_handler(nil, function()
    return append_page_params(base() .. "/user/keys", PAGES)
  end)
)

b:rest("post_user_keys", function()
  proxy_json_created(nil, fetch_json(base() .. "/user/keys", "POST", GetBody()))
end)

b:rest(
  "get_user_key",
  proxy_handler(nil, function(key_id)
    return base() .. "/user/keys/" .. key_id
  end)
)

b:rest("delete_user_key", function(key_id)
  local opts = auth() or {}
  opts.method = "DELETE"
  proxy_204({ 200 }, pcall(Fetch, base() .. "/user/keys/" .. key_id, opts))
end)

b:rest(
  "get_users_keys",
  proxy_handler(nil, function(username)
    return append_page_params(base() .. "/users/" .. username .. "/keys", PAGES)
  end)
)

-- Teams (GitHub-compatible passthrough) -------------------------------------

b:rest(
  "get_org_teams",
  proxy_handler(nil, function(org)
    return append_page_params(base() .. "/orgs/" .. org .. "/teams", PAGES)
  end)
)

b:rest("post_org_teams", function(org)
  proxy_json_created(nil, fetch_json(base() .. "/orgs/" .. org .. "/teams", "POST", GetBody()))
end)

b:rest(
  "get_org_team",
  proxy_handler(nil, function(org, slug)
    return base() .. "/orgs/" .. org .. "/teams/" .. slug
  end)
)

b:rest("patch_org_team", function(org, slug)
  proxy_json(nil, fetch_json(base() .. "/orgs/" .. org .. "/teams/" .. slug, "PATCH", GetBody()))
end)

b:rest("delete_org_team", function(org, slug)
  proxy_204({ 200 }, fetch_json(base() .. "/orgs/" .. org .. "/teams/" .. slug, "DELETE"))
end)

b:rest(
  "get_org_team_invitations",
  proxy_handler(nil, function(org, slug)
    return append_page_params(
      base() .. "/orgs/" .. org .. "/teams/" .. slug .. "/invitations",
      PAGES
    )
  end)
)

b:rest(
  "get_org_team_members",
  proxy_handler(nil, function(org, slug)
    return append_page_params(base() .. "/orgs/" .. org .. "/teams/" .. slug .. "/members", PAGES)
  end)
)

b:rest(
  "get_org_team_membership",
  proxy_handler(nil, function(org, slug, username)
    return base() .. "/orgs/" .. org .. "/teams/" .. slug .. "/memberships/" .. username
  end)
)

b:rest("put_org_team_membership", function(org, slug, username)
  proxy_json(
    nil,
    fetch_json(
      base() .. "/orgs/" .. org .. "/teams/" .. slug .. "/memberships/" .. username,
      "PUT",
      GetBody()
    )
  )
end)

b:rest("delete_org_team_membership", function(org, slug, username)
  proxy_204(
    { 200 },
    fetch_json(
      base() .. "/orgs/" .. org .. "/teams/" .. slug .. "/memberships/" .. username,
      "DELETE"
    )
  )
end)

b:rest(
  "get_org_team_repos",
  proxy_handler(nil, function(org, slug)
    return append_page_params(base() .. "/orgs/" .. org .. "/teams/" .. slug .. "/repos", PAGES)
  end)
)

b:rest(
  "get_org_team_repo",
  proxy_handler(nil, function(org, slug, owner, repo_name)
    return base() .. "/orgs/" .. org .. "/teams/" .. slug .. "/repos/" .. owner .. "/" .. repo_name
  end)
)

b:rest("put_org_team_repo", function(org, slug, owner, repo_name)
  proxy_204(
    { 200 },
    fetch_json(
      base() .. "/orgs/" .. org .. "/teams/" .. slug .. "/repos/" .. owner .. "/" .. repo_name,
      "PUT",
      GetBody()
    )
  )
end)

b:rest("delete_org_team_repo", function(org, slug, owner, repo_name)
  proxy_204(
    { 200 },
    fetch_json(
      base() .. "/orgs/" .. org .. "/teams/" .. slug .. "/repos/" .. owner .. "/" .. repo_name,
      "DELETE"
    )
  )
end)

b:rest(
  "get_org_team_children",
  proxy_handler(nil, function(org, slug)
    return append_page_params(base() .. "/orgs/" .. org .. "/teams/" .. slug .. "/teams", PAGES)
  end)
)

-- Issues (GitHub-compatible passthrough) -------------------------------------

b:rest(
  "get_repo_issues",
  proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/issues", PAGES)
  end)
)

b:rest(
  "post_repo_issues",
  proxy_handler_created(nil, function(o, r)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues", "POST", GetBody()
  end)
)

b:rest(
  "get_repo_issue",
  proxy_handler(nil, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n
  end)
)

b:rest(
  "patch_repo_issue",
  proxy_handler(nil, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n, "PATCH", GetBody()
  end)
)

b:rest(
  "get_repo_issue_comments",
  proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/issues/comments", PAGES)
  end)
)

b:rest(
  "get_repo_issue_comment",
  proxy_handler(nil, function(o, r, comment_id)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/comments/" .. comment_id
  end)
)

b:rest(
  "patch_repo_issue_comment",
  proxy_handler(nil, function(o, r, id)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/comments/" .. id, "PATCH", GetBody()
  end)
)

b:rest("delete_repo_issue_comment", function(owner, repo_name, comment_id)
  proxy_204(
    { 200 },
    fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/comments/" .. comment_id,
      "DELETE"
    )
  )
end)

b:rest(
  "get_repo_issue_events",
  proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/issues/events", PAGES)
  end)
)

b:rest(
  "get_issue_comments",
  proxy_handler(nil, function(o, r, n)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/comments",
      PAGES
    )
  end)
)

b:rest(
  "post_issue_comment",
  proxy_handler_created(nil, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/comments", "POST", GetBody()
  end)
)

b:rest(
  "get_issue_events",
  proxy_handler(nil, function(o, r, n)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/events",
      PAGES
    )
  end)
)

b:rest(
  "get_issue_timeline",
  proxy_handler(nil, function(o, r, n)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/timeline",
      PAGES
    )
  end)
)

b:rest(
  "get_issue_labels",
  proxy_handler(nil, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/labels"
  end)
)

b:rest(
  "post_issue_labels",
  proxy_handler(nil, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/labels", "POST", GetBody()
  end)
)

b:rest(
  "put_issue_labels",
  proxy_handler(nil, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/labels", "PUT", GetBody()
  end)
)

b:rest("delete_issue_labels", function(owner, repo_name, issue_number)
  proxy_204(
    { 200 },
    fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/" .. issue_number .. "/labels",
      "DELETE"
    )
  )
end)

b:rest("delete_issue_label", function(owner, repo_name, issue_number, label_name)
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
end)

b:rest(
  "post_issue_assignees",
  proxy_handler(nil, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/assignees",
      "POST",
      GetBody()
  end)
)

b:rest(
  "delete_issue_assignees",
  proxy_handler(nil, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/assignees",
      "DELETE",
      GetBody()
  end)
)

b:rest(
  "get_repo_assignees",
  proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/assignees", PAGES)
  end)
)

b:rest(
  "get_repo_labels",
  proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/labels", PAGES)
  end)
)

b:rest(
  "post_repo_labels",
  proxy_handler_created(nil, function(o, r)
    return base() .. "/repos/" .. o .. "/" .. r .. "/labels", "POST", GetBody()
  end)
)

b:rest(
  "get_repo_label",
  proxy_handler(nil, function(o, r, name)
    return base() .. "/repos/" .. o .. "/" .. r .. "/labels/" .. name
  end)
)

b:rest(
  "patch_repo_label",
  proxy_handler(nil, function(o, r, name)
    return base() .. "/repos/" .. o .. "/" .. r .. "/labels/" .. name, "PATCH", GetBody()
  end)
)

b:rest("delete_repo_label", function(owner, repo_name, label_name)
  proxy_204(
    { 200 },
    fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/labels/" .. label_name,
      "DELETE"
    )
  )
end)

b:rest(
  "get_repo_milestones",
  proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/milestones", PAGES)
  end)
)

b:rest(
  "get_repo_milestone",
  proxy_handler(nil, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/milestones/" .. n
  end)
)

b:rest(
  "get_repo_milestone_labels",
  proxy_handler(nil, function(o, r, n)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/milestones/" .. n .. "/labels",
      PAGES
    )
  end)
)

-- Legacy team-by-id API (/teams/{team_id}) ------------------------------------

b:rest(
  "get_user_teams",
  proxy_handler(nil, function()
    return append_page_params(base() .. "/user/teams", PAGES)
  end)
)

b:rest(
  "get_team",
  proxy_handler(nil, function(team_id)
    return base() .. "/teams/" .. team_id
  end)
)

b:rest("patch_team", function(team_id)
  proxy_json(nil, fetch_json(base() .. "/teams/" .. team_id, "PATCH", GetBody()))
end)

b:rest("delete_team", function(team_id)
  proxy_204({ 200 }, fetch_json(base() .. "/teams/" .. team_id, "DELETE"))
end)

b:rest(
  "get_team_invitations",
  proxy_handler(nil, function(team_id)
    return append_page_params(base() .. "/teams/" .. team_id .. "/invitations", PAGES)
  end)
)

b:rest(
  "get_team_members",
  proxy_handler(nil, function(team_id)
    return append_page_params(base() .. "/teams/" .. team_id .. "/members", PAGES)
  end)
)

b:rest("get_team_member", function(team_id, username)
  local ok, status = pcall(Fetch, base() .. "/teams/" .. team_id .. "/members/" .. username, auth())
  if ok and status == 204 then
    SetStatus(204, "No Content")
  elseif ok then
    respond_json(404, { message = "Not Found" })
  else
    respond_json(503, {})
  end
end)

b:rest("put_team_member", function(team_id, username)
  set_204_or_error("PUT", base() .. "/teams/" .. team_id .. "/members/" .. username)
end)

b:rest("delete_team_member", function(team_id, username)
  set_204_or_error("DELETE", base() .. "/teams/" .. team_id .. "/members/" .. username)
end)

b:rest(
  "get_team_membership",
  proxy_handler(nil, function(team_id, username)
    return base() .. "/teams/" .. team_id .. "/memberships/" .. username
  end)
)

b:rest("put_team_membership", function(team_id, username)
  proxy_json(
    nil,
    fetch_json(base() .. "/teams/" .. team_id .. "/memberships/" .. username, "PUT", GetBody())
  )
end)

b:rest("delete_team_membership", function(team_id, username)
  proxy_204(
    { 200 },
    fetch_json(base() .. "/teams/" .. team_id .. "/memberships/" .. username, "DELETE")
  )
end)

b:rest(
  "get_team_repos",
  proxy_handler(nil, function(team_id)
    return append_page_params(base() .. "/teams/" .. team_id .. "/repos", PAGES)
  end)
)

b:rest(
  "get_team_repo",
  proxy_handler(nil, function(team_id, owner, repo_name)
    return base() .. "/teams/" .. team_id .. "/repos/" .. owner .. "/" .. repo_name
  end)
)

b:rest("put_team_repo", function(team_id, owner, repo_name)
  proxy_204(
    { 200 },
    fetch_json(
      base() .. "/teams/" .. team_id .. "/repos/" .. owner .. "/" .. repo_name,
      "PUT",
      GetBody()
    )
  )
end)

b:rest("delete_team_repo", function(team_id, owner, repo_name)
  proxy_204(
    { 200 },
    fetch_json(base() .. "/teams/" .. team_id .. "/repos/" .. owner .. "/" .. repo_name, "DELETE")
  )
end)

b:rest(
  "get_team_children",
  proxy_handler(nil, function(team_id)
    return append_page_params(base() .. "/teams/" .. team_id .. "/teams", PAGES)
  end)
)

-- Pull Requests (GitHub-compatible passthrough) --------------------------------

b:rest(
  "get_repo_pulls",
  proxy_handler(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/pulls", PAGES)
  end)
)

b:rest("post_repo_pulls", function(owner, repo_name)
  proxy_json_created(
    nil,
    fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/pulls", "POST", GetBody())
  )
end)

b:rest(
  "get_repo_pull",
  proxy_handler(nil, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/pulls/" .. n
  end)
)

b:rest("patch_repo_pull", function(owner, repo_name, pull_number)
  proxy_json(
    nil,
    fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/pulls/" .. pull_number,
      "PATCH",
      GetBody()
    )
  )
end)

b:rest(
  "get_pull_commits",
  proxy_handler(nil, function(o, r, n)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/pulls/" .. n .. "/commits",
      PAGES
    )
  end)
)

b:rest(
  "get_pull_files",
  proxy_handler(nil, function(o, r, n)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/pulls/" .. n .. "/files",
      PAGES
    )
  end)
)

b:rest("get_pull_merge", function(owner, repo_name, pull_number)
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
end)

b:rest("put_pull_merge", function(owner, repo_name, pull_number)
  proxy_204(
    nil,
    fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/pulls/" .. pull_number .. "/merge",
      "PUT",
      GetBody()
    )
  )
end)

b:rest(
  "get_pull_requested_reviewers",
  proxy_handler(nil, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/pulls/" .. n .. "/requested_reviewers"
  end)
)

b:rest(
  "get_pull_reviews",
  proxy_handler(nil, function(o, r, n)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/pulls/" .. n .. "/reviews",
      PAGES
    )
  end)
)

b:rest(
  "get_pull_review",
  proxy_handler(nil, function(o, r, n, review_id)
    return base() .. "/repos/" .. o .. "/" .. r .. "/pulls/" .. n .. "/reviews/" .. review_id
  end)
)

b:rest(
  "get_pull_review_comments",
  proxy_handler(nil, function(o, r, n, review_id)
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
  end)
)

b:rest(
  "get_pull_comments",
  proxy_handler(nil, function(o, r, n)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/pulls/" .. n .. "/comments",
      PAGES
    )
  end)
)

-- Search -------------------------------------------------------------------
-- GitBucket's GitHub-compatible API exposes /api/v3/search/{repositories,users}
-- which return the GitHub search envelope format directly — no translation needed.
b:rest(
  "search_repositories",
  proxy_handler(nil, function()
    local q = GetParam("q") or ""
    return append_page_params(base() .. "/search/repositories?q=" .. q, PAGES)
  end)
)

b:rest(
  "search_users",
  proxy_handler(nil, function()
    local q = GetParam("q") or ""
    return append_page_params(base() .. "/search/users?q=" .. q, PAGES)
  end)
)

-- Git database --------------------------------------------------------------

b:rest(
  "get_git_blob",
  proxy_handler(nil, function(o, r, sha)
    return base() .. "/repos/" .. o .. "/" .. r .. "/git/blobs/" .. sha
  end)
)

b:rest(
  "get_git_commit",
  proxy_handler(nil, function(o, r, sha)
    return base() .. "/repos/" .. o .. "/" .. r .. "/git/commits/" .. sha
  end)
)

b:rest(
  "list_git_matching_refs",
  proxy_handler(nil, function(o, r, ref)
    return base() .. "/repos/" .. o .. "/" .. r .. "/git/matching-refs/" .. ref
  end)
)

b:rest(
  "get_git_ref",
  proxy_handler(nil, function(o, r, ref)
    return base() .. "/repos/" .. o .. "/" .. r .. "/git/ref/" .. ref
  end)
)

b:rest("create_git_ref", function(owner, repo_name)
  proxy_json_created(
    nil,
    fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/refs", "POST", GetBody())
  )
end)

b:rest("delete_git_ref", function(owner, repo_name, ref)
  set_204_or_error(
    "DELETE",
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/refs/" .. ref
  )
end)

b:rest(
  "get_git_tag",
  proxy_handler(nil, function(o, r, sha)
    return base() .. "/repos/" .. o .. "/" .. r .. "/git/tags/" .. sha
  end)
)

b:rest("create_git_tag", function(owner, repo_name)
  proxy_json_created(
    nil,
    fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/tags", "POST", GetBody())
  )
end)

b:rest(
  "get_git_tree",
  proxy_handler(nil, function(o, r, sha)
    return base() .. "/repos/" .. o .. "/" .. r .. "/git/trees/" .. sha
  end)
)

-- Gists (GitHub-compatible passthrough) ------------------------------------
b:rest(
  "get_gists",
  proxy_handler(nil, function()
    return base() .. "/gists"
  end)
)
b:rest("post_gists", function()
  proxy_json_created(nil, fetch_json(base() .. "/gists", "POST", GetBody()))
end)
b:rest(
  "get_gists_public",
  proxy_handler(nil, function()
    return base() .. "/gists/public"
  end)
)
b:rest(
  "get_gists_starred",
  proxy_handler(nil, function()
    return base() .. "/gists/starred"
  end)
)
b:rest(
  "get_gist",
  proxy_handler(nil, function(id)
    return base() .. "/gists/" .. id
  end)
)
b:rest("patch_gist", function(id)
  proxy_json(nil, fetch_json(base() .. "/gists/" .. id, "PATCH", GetBody()))
end)
b:rest("delete_gist", function(id)
  set_204_or_error("DELETE", base() .. "/gists/" .. id)
end)
b:rest(
  "get_gist_comments",
  proxy_handler(nil, function(id)
    return base() .. "/gists/" .. id .. "/comments"
  end)
)
b:rest("post_gist_comment", function(id)
  proxy_json_created(nil, fetch_json(base() .. "/gists/" .. id .. "/comments", "POST", GetBody()))
end)
b:rest(
  "get_gist_comment",
  proxy_handler(nil, function(id, cid)
    return base() .. "/gists/" .. id .. "/comments/" .. cid
  end)
)
b:rest("patch_gist_comment", function(id, cid)
  proxy_json(nil, fetch_json(base() .. "/gists/" .. id .. "/comments/" .. cid, "PATCH", GetBody()))
end)
b:rest("delete_gist_comment", function(id, cid)
  set_204_or_error("DELETE", base() .. "/gists/" .. id .. "/comments/" .. cid)
end)
b:rest(
  "get_gist_commits",
  proxy_handler(nil, function(id)
    return base() .. "/gists/" .. id .. "/commits"
  end)
)
b:rest(
  "get_gist_forks",
  proxy_handler(nil, function(id)
    return base() .. "/gists/" .. id .. "/forks"
  end)
)
b:rest("get_gist_star", function(id)
  set_204_or_error("GET", base() .. "/gists/" .. id .. "/star")
end)
b:rest("put_gist_star", function(id)
  set_204_or_error("PUT", base() .. "/gists/" .. id .. "/star")
end)
b:rest("delete_gist_star", function(id)
  set_204_or_error("DELETE", base() .. "/gists/" .. id .. "/star")
end)
b:rest(
  "get_gist_revision",
  proxy_handler(nil, function(id, sha)
    return base() .. "/gists/" .. id .. "/" .. sha
  end)
)
b:rest(
  "get_user_gists",
  proxy_handler(nil, function(user)
    return base() .. "/users/" .. user .. "/gists"
  end)
)

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
b:graphql("Query.repositoryOwner", function(_parent, args, ctx)
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
end)

-- Query.viewer: resolve the authenticated user via GET /user.
b:graphql("Query.viewer", function(_parent, _args, ctx)
  local data = graphql_fetch_or_error(fetch_json, base() .. "/user", ctx, nil)
  if not data then
    return nil
  end
  local u = graphql_translate_user(data)
  u.isViewer = true
  return u
end)

-- Query.user: look up a User by login.
b:graphql("Query.user", function(_parent, args, ctx)
  if not args.login then
    graphql_error(ctx, "user requires a login argument")
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, base() .. "/users/" .. args.login)
  if not data then
    return nil
  end
  return graphql_translate_user(data)
end)

-- Query.organization: look up an Organization by login.
b:graphql("Query.organization", function(_parent, args, ctx)
  if not args.login then
    graphql_error(ctx, "organization requires a login argument")
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, base() .. "/orgs/" .. args.login)
  if not data then
    return nil
  end
  return graphql_translate_org(data)
end)

-- Query.repository: look up a Repository by owner and name.
b:graphql("Query.repository", function(_parent, args, ctx)
  if not args.owner or not args.name then
    graphql_error(ctx, "repository requires owner and name arguments")
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, base() .. "/repos/" .. args.owner .. "/" .. args.name)
  if not data then
    return nil
  end
  return graphql_translate_repo(data)
end)

-- node.Repository: fetch a repository by "owner/repo" local ID.
b:graphql("node.Repository", function(local_id, _ctx)
  local data, _ = graphql_fetch(fetch_json, base() .. "/repos/" .. local_id)
  if not data then
    return nil
  end
  return graphql_translate_repo(data)
end)

-- node.User: fetch a user by login.
b:graphql("node.User", function(local_id, _ctx)
  local data, _ = graphql_fetch(fetch_json, base() .. "/users/" .. local_id)
  if not data then
    return nil
  end
  return graphql_translate_user(data)
end)

-- node.Organization: fetch an organization by login.
b:graphql("node.Organization", function(local_id, _ctx)
  local data, _ = graphql_fetch(fetch_json, base() .. "/orgs/" .. local_id)
  if not data then
    return nil
  end
  return graphql_translate_org(data)
end)

-- node.Issue: fetch an issue by "owner/repo/number" local ID.
b:graphql("node.Issue", function(local_id, _ctx)
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
end)

-- node.PullRequest: fetch a pull request by "owner/repo/number" local ID.
b:graphql("node.PullRequest", function(local_id, _ctx)
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
end)

-- node.IssueComment: fetch an issue comment by "owner/repo/comment_id" local ID.
b:graphql("node.IssueComment", function(local_id, _ctx)
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
end)

-- node.Release: fetch a release by "owner/repo/release_id" local ID.
b:graphql("node.Release", function(local_id, _ctx)
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
end)

-- node.Label: fetch a label by "owner/repo/label_id" local ID.
b:graphql("node.Label", function(local_id, _ctx)
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
end)

-- node.Milestone: fetch a milestone by "owner/repo/number" local ID.
b:graphql("node.Milestone", function(local_id, _ctx)
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
end)

-- node.Commit: fetch a commit by "owner/repo/sha" local ID.
b:graphql("node.Commit", function(local_id, _ctx)
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
end)

-- node.Ref: fetch a branch ref by "owner/repo/refs/heads/..." local ID.
-- GitBucket branch objects are GitHub-compatible (commit.sha already present).
b:graphql("node.Ref", function(local_id, _ctx)
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
end)

-- node.Team: fetch a team by "org/slug" local ID.
-- GitBucket is GitHub-compatible; /orgs/{org}/teams/{slug} returns the team directly.
b:graphql("node.Team", function(local_id, _ctx)
  local org, slug = local_id:match("^([^/]+)/([^/]+)$")
  if not org then
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, base() .. "/orgs/" .. org .. "/teams/" .. slug)
  if not data then
    return nil
  end
  return graphql_translate_team(data, org)
end)

-- ---------------------------------------------------------------------------
-- Repository connection sub-resolvers
-- ---------------------------------------------------------------------------

-- Repository.issues: paginated list of issues.
-- GitBucket's issue list includes PRs (like GitHub); filter them out by checking
-- the pull_request field.
b:graphql("Repository.issues", function(parent, args, ctx)
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
end)

-- Repository.pullRequests: paginated list of pull requests.
b:graphql("Repository.pullRequests", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gb_repo_connection(owner, name, "/pulls", args, ctx, function(p)
    return graphql_translate_pr(p, owner, name)
  end, graphql_prs_connection)
end)

-- Repository.releases: paginated list of releases.
b:graphql("Repository.releases", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gb_repo_connection(owner, name, "/releases", args, ctx, function(r)
    return graphql_translate_release(r, owner, name)
  end, function(n, a, t, c)
    return graphql_make_connection("Release", n, a, t, c)
  end)
end)

-- Repository.labels: paginated list of labels.
b:graphql("Repository.labels", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gb_repo_connection(owner, name, "/labels", args, ctx, function(l)
    return graphql_translate_label(l, owner, name)
  end, graphql_labels_connection)
end)

-- Repository.milestones: paginated list of milestones.
b:graphql("Repository.milestones", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gb_repo_connection(owner, name, "/milestones", args, ctx, function(m)
    return graphql_translate_milestone(m, owner, name)
  end, function(n, a, t, c)
    return graphql_make_connection("Milestone", n, a, t, c)
  end)
end)

-- Repository.refs: paginated list of branches as Ref objects.
-- GitBucket branch objects already include commit.sha (GitHub-compatible);
-- no commit.id → commit.sha normalisation needed.
b:graphql("Repository.refs", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gb_repo_connection(owner, name, "/branches", args, ctx, function(br)
    return graphql_translate_ref(br, parent)
  end, graphql_refs_connection)
end)

-- Issue.comments: paginated list of comments for a single issue.
b:graphql("Issue.comments", function(parent, args, ctx)
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
end)

-- PullRequest.commits: paginated commit list for a pull request.
b:graphql("PullRequest.commits", function(parent, args, ctx)
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
end)

-- PullRequest.reviews: paginated review list for a pull request.
b:graphql("PullRequest.reviews", function(parent, args, ctx)
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
end)

-- Repository.collaborators: paginated list of collaborators as Users.
b:graphql("Repository.collaborators", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gb_repo_connection(owner, name, "/collaborators", args, ctx, function(u)
    return graphql_translate_user(u)
  end, function(n, a, t, c)
    return graphql_make_connection("RepositoryCollaborator", n, a, t, c)
  end)
end)

-- Repository.defaultBranchRef: enrich the inline stub with full branch data.
-- The parent already carries {__typename="Ref",name="main"} from graphql_translate_repo.
b:graphql("Repository.defaultBranchRef", function(parent, _args, _ctx)
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
end)

-- Repository.languages: fetch language byte-count breakdown as a LanguageConnection.
-- GitBucket returns {"Language": bytes, ...}; we convert to the Relay Connection shape.
b:graphql("Repository.languages", function(parent, _args, _ctx)
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
end)

-- ---------------------------------------------------------------------------
-- Query.search
-- ---------------------------------------------------------------------------

-- Query.search: map GitHub GraphQL search to GitBucket search endpoints.
-- GitBucket exposes GitHub-compatible /search/{repositories,users} returning
-- the standard {total_count, items} envelope.
-- ISSUE search is not supported (GitBucket has no /search/issues endpoint).
b:graphql("Query.search", function(_parent, args, _ctx)
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
end)

-- Webhook handlers: GitBucket emits GitHub-compatible webhook payloads, so
-- action names and payload structure match GitHub's format exactly.
local GB_ISSUES_ACTIONS = {
  assigned = "assigned",
  closed = "closed",
  deleted = "deleted",
  demilestoned = "demilestoned",
  edited = "edited",
  labeled = "labeled",
  locked = "locked",
  milestoned = "milestoned",
  opened = "opened",
  pinned = "pinned",
  reopened = "reopened",
  transferred = "transferred",
  unassigned = "unassigned",
  unlabeled = "unlabeled",
  unlocked = "unlocked",
  unpinned = "unpinned",
}
local GB_ISSUE_COMMENT_ACTIONS = {
  created = "created",
  deleted = "deleted",
  edited = "edited",
}
local GB_LABEL_ACTIONS = {
  created = "created",
  deleted = "deleted",
  edited = "edited",
}
local GB_MILESTONE_ACTIONS = {
  closed = "closed",
  created = "created",
  deleted = "deleted",
  edited = "edited",
  opened = "opened",
}
local GB_PULL_REQUEST_ACTIONS = {
  assigned = "assigned",
  closed = "closed",
  converted_to_draft = "converted_to_draft",
  edited = "edited",
  labeled = "labeled",
  locked = "locked",
  opened = "opened",
  ready_for_review = "ready_for_review",
  reopened = "reopened",
  review_request_removed = "review_request_removed",
  review_requested = "review_requested",
  synchronize = "synchronize",
  unassigned = "unassigned",
  unlabeled = "unlabeled",
  unlocked = "unlocked",
}

b:webhook("issues", function(payload)
  local raw_action = payload.action or ""
  local action = GB_ISSUES_ACTIONS[raw_action]
  local data = {
    action = action or "unknown",
    issue = payload.issue or {},
    repository = payload.repository or {},
    sender = payload.sender or {},
  }
  if action == "labeled" or action == "unlabeled" then
    data.label = payload.label
  end
  if action == "assigned" or action == "unassigned" then
    data.assignee = payload.assignee
  end
  return make_internal_event({
    event = "issues",
    action = action or "unknown",
    raw_action = action and nil or raw_action,
    provider = "gitbucket",
    raw = payload,
    data = data,
    timestamp = (payload.issue or {}).updated_at or "",
  })
end)

b:webhook("issue_comment", function(payload)
  local raw_action = payload.action or ""
  local action = GB_ISSUE_COMMENT_ACTIONS[raw_action]
  return make_internal_event({
    event = "issue_comment",
    action = action or "unknown",
    raw_action = action and nil or raw_action,
    provider = "gitbucket",
    raw = payload,
    data = {
      action = action or "unknown",
      issue = payload.issue or {},
      comment = payload.comment or {},
      repository = payload.repository or {},
      sender = payload.sender or {},
    },
    timestamp = (payload.comment or {}).updated_at or "",
  })
end)

b:webhook("label", function(payload)
  local raw_action = payload.action or ""
  local action = GB_LABEL_ACTIONS[raw_action]
  return make_internal_event({
    event = "label",
    action = action or "unknown",
    raw_action = action and nil or raw_action,
    provider = "gitbucket",
    raw = payload,
    data = {
      action = action or "unknown",
      label = payload.label or {},
      changes = payload.changes or {},
      repository = payload.repository or {},
      sender = payload.sender or {},
    },
    timestamp = "",
  })
end)

b:webhook("milestone", function(payload)
  local raw_action = payload.action or ""
  local action = GB_MILESTONE_ACTIONS[raw_action]
  return make_internal_event({
    event = "milestone",
    action = action or "unknown",
    raw_action = action and nil or raw_action,
    provider = "gitbucket",
    raw = payload,
    data = {
      action = action or "unknown",
      milestone = payload.milestone or {},
      repository = payload.repository or {},
      sender = payload.sender or {},
    },
    timestamp = (payload.milestone or {}).updated_at or "",
  })
end)

b:webhook("pull_request", function(payload)
  local raw_action = payload.action or ""
  local action = GB_PULL_REQUEST_ACTIONS[raw_action]
  local data = {
    action = action or "unknown",
    number = payload.number,
    pull_request = payload.pull_request or {},
    repository = payload.repository or {},
    sender = payload.sender or {},
  }
  if action == "labeled" or action == "unlabeled" then
    data.label = payload.label
  end
  if action == "review_requested" or action == "review_request_removed" then
    data.requested_reviewer = payload.requested_reviewer
  end
  return make_internal_event({
    event = "pull_request",
    action = action or "unknown",
    raw_action = action and nil or raw_action,
    provider = "gitbucket",
    raw = payload,
    data = data,
    timestamp = (payload.pull_request or {}).updated_at or "",
  })
end)

local GB_PULL_REQUEST_REVIEW_ACTIONS = {
  submitted = "submitted",
  dismissed = "dismissed",
  edited = "edited",
}

b:webhook("pull_request_review", function(payload)
  local raw_action = payload.action or ""
  local action = GB_PULL_REQUEST_REVIEW_ACTIONS[raw_action]
  return make_internal_event({
    event = "pull_request_review",
    action = action or "unknown",
    raw_action = action and nil or raw_action,
    provider = "gitbucket",
    raw = payload,
    data = {
      action = action or "unknown",
      review = payload.review or {},
      pull_request = payload.pull_request or {},
      repository = payload.repository or {},
      sender = payload.sender or {},
    },
    timestamp = (payload.review or {}).submitted_at or "",
  })
end)

-- push: commits pushed to a branch or tag.  GitBucket emits GitHub-compatible
-- push payloads, so the data is passed through with minimal normalization.
-- Key difference from Gitea: the compare URL is in `compare` (not
-- `compare_url`), and `pusher` has `name`/`email` fields, not `login`.
b:webhook("push", function(payload)
  return make_internal_event({
    event = "push",
    action = "push",
    provider = "gitbucket",
    raw = payload,
    data = {
      ref = payload.ref or "",
      before = payload.before or "",
      after = payload.after or "",
      created = payload.created or false,
      deleted = payload.deleted or false,
      forced = payload.forced or false,
      compare = payload.compare or "",
      commits = payload.commits or {},
      head_commit = payload.head_commit,
      pusher = payload.pusher or {},
      repository = payload.repository or {},
      sender = payload.sender or {},
    },
    timestamp = (payload.head_commit or {}).timestamp or "",
  })
end)

-- create: branch or tag created.  GitHub-compatible payload; pass through as-is.
b:webhook("create", function(payload)
  return make_internal_event({
    event = "create",
    action = "create",
    provider = "gitbucket",
    raw = payload,
    data = {
      ref = payload.ref or "",
      ref_type = payload.ref_type or "branch",
      master_branch = payload.master_branch or "",
      description = payload.description,
      pusher_type = payload.pusher_type or "user",
      repository = payload.repository or {},
      sender = payload.sender or {},
    },
    timestamp = "",
  })
end)

-- delete: branch or tag deleted.  Same shape as create.
b:webhook("delete", function(payload)
  return make_internal_event({
    event = "delete",
    action = "delete",
    provider = "gitbucket",
    raw = payload,
    data = {
      ref = payload.ref or "",
      ref_type = payload.ref_type or "branch",
      master_branch = payload.master_branch or "",
      description = payload.description,
      pusher_type = payload.pusher_type or "user",
      repository = payload.repository or {},
      sender = payload.sender or {},
    },
    timestamp = "",
  })
end)

-- release: published, edited, deleted, prereleased.  GitBucket emits
-- GitHub-compatible release payloads; fields are passed through as-is.
local GB_RELEASE_ACTIONS = {
  created = "created",
  published = "published",
  edited = "edited",
  deleted = "deleted",
  prereleased = "prereleased",
  released = "released",
  unpublished = "unpublished",
}

b:webhook("release", function(payload)
  local raw_action = payload.action or ""
  local action = GB_RELEASE_ACTIONS[raw_action]
  local rel = payload.release or {}
  local data = {
    action = action or "unknown",
    release = rel,
    repository = payload.repository or {},
    sender = payload.sender or {},
  }
  if action == "edited" then
    data.changes = payload.changes or {}
  end
  return make_internal_event({
    event = "release",
    action = action or "unknown",
    raw_action = action and nil or raw_action,
    provider = "gitbucket",
    raw = payload,
    data = data,
    timestamp = rel.published_at or rel.created_at or "",
  })
end)

-- fork: repository forked.  GitHub-compatible payload; forkee and repository
-- are passed through as-is.
b:webhook("fork", function(payload)
  return make_internal_event({
    event = "fork",
    action = "fork",
    provider = "gitbucket",
    raw = payload,
    data = {
      forkee = payload.forkee or {},
      repository = payload.repository or {},
      sender = payload.sender or {},
    },
    timestamp = "",
  })
end)

-- deploy_key: SSH deploy key added or removed.
-- GitBucket sends X-GitHub-Event: deploy_key with GitHub-compatible payload.
b:webhook("deploy_key", function(payload)
  local action = payload.action or "unknown"
  local data = {
    action = action,
    key = payload.key or {},
    repository = payload.repository or {},
    sender = payload.sender or {},
  }
  return make_internal_event({
    event = "deploy_key",
    action = action,
    provider = "gitbucket",
    raw = payload,
    data = data,
    timestamp = (payload.key or {}).created_at or "",
  })
end)

-- gollum: wiki page created or edited.
-- GitBucket sends X-GitHub-Event: gollum with GitHub-compatible payload.
-- The pages[] array carries the per-page action; there is no top-level action.
b:webhook("gollum", function(payload)
  local pages = payload.pages or {}
  local first_action = (pages[1] or {}).action or "edited"
  local data = {
    pages = pages,
    repository = payload.repository or {},
    sender = payload.sender or {},
  }
  return make_internal_event({
    event = "gollum",
    action = first_action,
    provider = "gitbucket",
    raw = payload,
    data = data,
    timestamp = "",
  })
end)

-- repository: lifecycle events.  GitBucket emits GitHub-compatible repository
-- payloads for created and deleted actions in newer versions; pass through as-is.
-- Rename/transfer/visibility actions are not emitted by GitBucket.
b:webhook("repository", function(payload)
  local action = payload.action or "unknown"
  local data = {
    action = action,
    repository = payload.repository or {},
    sender = payload.sender or {},
  }
  return make_internal_event({
    event = "repository",
    action = action,
    provider = "gitbucket",
    raw = payload,
    data = data,
    timestamp = "",
  })
end)

b:build()
