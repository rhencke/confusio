-- Config defaults (global: backends/<name>.lua can read at startup)
config = {
  backend  = "",
  base_url = "https://gitea.com",
}

-- Config keys accepted by both .confusio.lua and SCRIPTARGS.
local CONFIG_KEYS = { "backend", "base_url" }

-- Load .confusio.lua if present.
if pcall(dofile, ".confusio.lua") then
  if type(confusio) == "table" then
    for k, v in pairs(confusio) do
      if config[k] ~= nil then config[k] = v end
    end
  end
  confusio = nil
end

-- SCRIPTARGS (key=value after --) override config file.
for _, a in ipairs(arg or {}) do
  local k, v = a:match("^([%w_]+)=(.+)$")
  if k and config[k] ~= nil then config[k] = v end
end

config.base_url = config.base_url:gsub("/$", "")

-- respond_json is global: backends/<name>.lua uses it.
function respond_json(status, reason, body)
  SetStatus(status, reason)
  SetHeader("Content-Type", "application/json; charset=utf-8")
  Write(EncodeJson(body))
end

-- proxy_json and proxy_json_created are globals: backends/<name>.lua uses them
-- as the standard upstream-proxy response pattern.
--
-- translate: optional function applied to the decoded response body on success
-- ok, status, headers, body: the four return values from pcall(Fetch,...) or fetch_json(...)
--
-- translate is first so that fetch_json(...) can be the last argument and Lua
-- expands its multiple return values correctly into ok/status/headers/body:
--   proxy_json(translate_fn, fetch_json(url))
--   proxy_json(nil, fetch_json(url))   -- passthrough, no translation
function proxy_json(translate, ok, status, headers, body)
  if ok and status == 200 then
    local data = DecodeJson(body) or {}
    local link = headers and (headers["Link"] or headers["link"])
    if link then SetHeader("Link", link) end
    respond_json(200, "OK", translate and translate(data) or data)
  elseif ok then respond_json(status, "Error", {})
  else respond_json(503, "Service Unavailable", {}) end
end

-- Like proxy_json but for create endpoints: upstream may return 200 or 201;
-- confusio always responds 201 Created.
function proxy_json_created(translate, ok, status, headers, body)
  if ok and (status == 200 or status == 201) then
    local data = DecodeJson(body) or {}
    respond_json(201, "Created", translate and translate(data) or data)
  elseif ok then respond_json(status, "Error", {})
  else respond_json(503, "Service Unavailable", {}) end
end

-- append_page_params appends translated pagination params to url.
-- mapping: { per_page = "upstream_name", page = "upstream_name" }
--   Omit the page key for providers that only support limit (e.g. Sourcehut).
-- Reads per_page and page from the incoming GitHub-style request query string.
-- Returns url unchanged if neither applicable param is present in the request.
function append_page_params(url, mapping)
  local sep = url:find("?") and "&" or "?"
  local parts = {}
  local pp = GetParam("per_page")
  local pg = GetParam("page")
  if pp and pp ~= "" and mapping.per_page then
    parts[#parts + 1] = mapping.per_page .. "=" .. pp
  end
  if pg and pg ~= "" and mapping.page then
    parts[#parts + 1] = mapping.page .. "=" .. pg
  end
  if #parts == 0 then return url end
  return url .. sep .. table.concat(parts, "&")
end

-- make_fetch_opts is global: backends/<name>.lua uses it to forward auth.
--
-- Returns a Fetch options table with the correct Authorization header for the
-- target provider, or nil when no Authorization header is present on the
-- incoming request. The raw token value passes through verbatim; only the
-- scheme wrapper changes.
--
-- scheme: "token" | "bearer" | "basic-colon" | "basic"
--   "token"       → Authorization: token <tok>
--   "bearer"      → Authorization: Bearer <tok>
--   "basic-colon" → Authorization: Basic base64(:tok)  (Azure DevOps — empty username)
--   "basic"       → Authorization: Basic base64(tok)   (client passes user:pass as tok)
function make_fetch_opts(scheme)
  local h = GetHeader("Authorization")
  if not h or h == "" then return nil end
  local tok = h:match("^[Tt]oken%s+(.+)$") or h:match("^[Bb]earer%s+(.+)$") or h
  local hdr
  if scheme == "token" then
    hdr = "token " .. tok
  elseif scheme == "bearer" then
    hdr = "Bearer " .. tok
  elseif scheme == "basic-colon" then
    hdr = "Basic " .. EncodeBase64(":" .. tok)
  elseif scheme == "basic" then
    hdr = "Basic " .. EncodeBase64(tok)
  end
  return { headers = { ["Authorization"] = hdr } }
end

-- make_proxy_handler is global: returns a proxy_handler bound to a backend's fetch_json.
-- Each backend calls: local proxy_handler = make_proxy_handler(fetch_json)
--
-- The returned proxy_handler(xform, url_fn) builds a handler function that fetches
-- url_fn(...) and passes the decoded response through xform (plus handler args).
-- xform receives (response_body, ...handler_args) so closures over handler args are not
-- needed. Named translate functions that only take the response body work as-is
-- (extra args are silently ignored by Lua).
function make_proxy_handler(fetch_fn)
  return function(xform, url_fn)
    return function(...)
      local args = {...}
      proxy_json(
        type(xform) == "function" and function(r) return xform(r, table.unpack(args)) end or xform,
        fetch_fn(url_fn(...)))
    end
  end
end

-- translate_repo is global: maps a Gitea-style repo object to GitHub field names.
-- Called by any Gitea-API-compatible backend (gitea, forgejo, gogs, codeberg, notabug).
function translate_repo(r)
  if not r then return {} end
  local owner = r.owner or {}
  return {
    id               = r.id,
    node_id          = "",
    name             = r.name,
    full_name        = r.full_name,
    private          = r.private,
    owner            = {
      login      = owner.login,
      id         = owner.id,
      node_id    = "",
      avatar_url = owner.avatar_url,
      url        = owner.url,
      html_url   = owner.html_url,
      type       = owner.type or (owner.is_admin and "Admin" or "User"),
    },
    html_url          = r.html_url,
    description       = r.description,
    fork              = r.fork,
    url               = r.url,
    git_url           = r.ssh_url,
    ssh_url           = r.ssh_url,
    clone_url         = r.clone_url,
    homepage          = r.website,
    size              = r.size,
    stargazers_count  = r.stars_count,
    watchers_count    = r.watchers_count,
    language          = r.language,
    has_issues        = r.has_issues,
    has_wiki          = r.has_wiki,
    forks_count       = r.forks_count,
    archived          = r.archived,
    disabled          = false,
    open_issues_count = r.open_issues_count,
    default_branch    = r.default_branch,
    visibility        = r.visibility or (r.private and "private" or "public"),
    forks             = r.forks_count,
    open_issues       = r.open_issues_count,
    watchers          = r.watchers_count,
    created_at        = r.created,
    updated_at        = r.updated,
    pushed_at         = r.updated,
    permissions       = r.permissions,
  }
end

-- translate_user is global: maps a Gitea-style user object to GitHub field names.
-- Called by any Gitea-API-compatible backend (gitea, forgejo, gogs, codeberg, notabug).
function translate_user(u)
  if not u then return {} end
  return {
    login      = u.login,
    id         = u.id,
    node_id    = "",
    avatar_url = u.avatar_url,
    html_url   = u.html_url,
    type       = "User",
    site_admin = u.is_admin or false,
    name       = u.full_name,
    email      = u.email,
    location   = u.location,
    blog       = u.website,
    followers  = u.followers_count or 0,
    following  = u.following_count or 0,
    created_at = u.created,
  }
end

-- backend_impl is global: set by backends/<name>.lua at startup.
backend_impl = {}
if config.backend ~= "" then
  assert(config.backend:match("^[%a][%w_]*$"),
    "invalid backend name: " .. config.backend)
  dofile("/zip/backends/" .. config.backend .. ".lua")
end

-- Health check default: return 200 if no backend configured.
-- Each backend overrides get_root to probe its upstream.
if not backend_impl.get_root then
  backend_impl.get_root = function() respond_json(200, "OK", {}) end
end

-- Teams list defaults: backends without a native teams concept return empty arrays.
-- Individual-item and mutating endpoints fall through to 404 (nil handler).
local function teams_empty()
  SetStatus(200, "OK")
  SetHeader("Content-Type", "application/json; charset=utf-8")
  Write("[]")
end
for _, ep in ipairs({
  "get_org_teams", "get_org_team_invitations",
  "get_org_team_members", "get_org_team_repos", "get_org_team_children",
  -- Legacy team-by-id list endpoints
  "get_user_teams",
  "get_team_invitations", "get_team_members", "get_team_repos", "get_team_children",
}) do
  if not backend_impl[ep] then backend_impl[ep] = teams_empty end
end

-- Security advisory defaults: most providers have no native equivalent.
-- List endpoints return [] (no advisories); individual/mutating endpoints → 404 (nil handler).
local function security_advisories_empty()
  SetStatus(200, "OK")
  SetHeader("Content-Type", "application/json; charset=utf-8")
  Write("[]")
end
for _, ep in ipairs({
  "get_global_advisories",
  "get_org_security_advisories",
  "get_repo_security_advisories",
}) do
  if not backend_impl[ep] then backend_impl[ep] = security_advisories_empty end
end

-- Handlers resolved once at startup; backend is fixed for the program's lifetime.
-- Registered routes not implemented by the backend return 404.
local handle = backend_impl

-- ---------------------------------------------------------------------------
-- Segment-based radix trie router
--
-- Each node: { static = {[segment]→node}, param = node|nil, handler = name|nil }
--
-- Routes are registered as "VERB /path" strings. The verb becomes the first
-- static segment in the trie so each verb+path combination has its own handler.
-- Static edges are preferred over param edges at each node, so /repos/search
-- beats /repos/{owner} when both are registered.
--
-- A second path-only trie tracks which paths are known at all; when a verb+path
-- lookup misses but the path is known, OnHttpRequest returns 405 rather than
-- 404. Unknown paths return JSON 404 directly; Route() is no longer called.
-- ---------------------------------------------------------------------------

local function new_node() return { static = {}, param = nil, handler = nil } end
local trie      = new_node()
local path_trie = new_node()

local function _trie_insert(t, key)
  local node = t
  for seg in key:gmatch("[^/]+") do
    if seg:sub(1, 1) == "{" then
      node.param = node.param or new_node()
      node = node.param
    else
      node.static[seg] = node.static[seg] or new_node()
      node = node.static[seg]
    end
  end
  return node
end

-- route_add("VERB /path", handler_name)
-- e.g. route_add("GET /repos/{owner}/{repo}", "get_repo")
local function route_add(route, handler_name)
  local verb, path = route:match("^(%S+)%s+(.+)$")
  _trie_insert(trie, verb .. path).handler = handler_name
  _trie_insert(path_trie, path).handler = true
end

-- _trie_walk traverses root over the "/" segments of key.
-- Returns the final node and a table of captured param values,
-- or nil if any segment has no matching edge.
local function _trie_walk(root, key)
  local node = root
  local caps = {}
  for seg in key:gmatch("[^/]+") do
    if node.static[seg] then
      node = node.static[seg]
    elseif node.param then
      caps[#caps + 1] = seg
      node = node.param
    else
      return nil
    end
  end
  return node, caps
end

local function route_match(method, path)
  local node, caps = _trie_walk(trie, method .. path)
  if node then return node.handler, caps end
  return nil, nil
end

local function path_known(path)
  local node = _trie_walk(path_trie, path)
  return node ~= nil and node.handler == true
end

-- ---------------------------------------------------------------------------
-- Route registry
--
-- Each entry: { "VERB /path", handler_name }.
-- The HTTP method is part of the route string; each verb+path gets its own
-- named handler in defaults (and optionally an override in backends/<name>.lua).
-- Parametric captures are passed positionally to the handler:
--   get_repo = function(owner, repo) ... end
-- ---------------------------------------------------------------------------

local routes = {
  -- Root
  ["GET /"]                                                                    = "get_root",
  -- Emojis
  ["GET /emojis"]                                                              = "get_emojis",

  -- Repos core (https://docs.github.com/en/rest/repos/repos)
  ["GET /repos/{owner}/{repo}"]                                                = "get_repo",
  ["PATCH /repos/{owner}/{repo}"]                                              = "patch_repo",
  ["DELETE /repos/{owner}/{repo}"]                                             = "delete_repo",
  ["GET /user/repos"]                                                          = "get_user_repos",
  ["POST /user/repos"]                                                         = "post_user_repos",
  ["GET /orgs/{org}/repos"]                                                    = "get_org_repos",
  ["POST /orgs/{org}/repos"]                                                   = "post_org_repos",
  ["GET /users/{username}/repos"]                                              = "get_users_repos",
  ["GET /repositories"]                                                        = "get_repositories",

  -- Topics / languages / contributors / tags / teams
  ["GET /repos/{owner}/{repo}/topics"]                                         = "get_repo_topics",
  ["PUT /repos/{owner}/{repo}/topics"]                                         = "put_repo_topics",
  ["GET /repos/{owner}/{repo}/languages"]                                      = "get_repo_languages",
  ["GET /repos/{owner}/{repo}/contributors"]                                   = "get_repo_contributors",
  ["GET /repos/{owner}/{repo}/tags"]                                           = "get_repo_tags",
  ["GET /repos/{owner}/{repo}/teams"]                                          = "get_repo_teams",

  -- Branches (https://docs.github.com/en/rest/branches)
  ["GET /repos/{owner}/{repo}/branches"]                                       = "get_repo_branches",
  ["GET /repos/{owner}/{repo}/branches/{branch}"]                              = "get_repo_branch",

  -- Commits (https://docs.github.com/en/rest/commits)
  ["GET /repos/{owner}/{repo}/commits"]                                        = "get_repo_commits",
  ["GET /repos/{owner}/{repo}/commits/{ref}"]                                  = "get_repo_commit",

  -- Commit comments
  ["GET /repos/{owner}/{repo}/comments"]                                       = "get_repo_comments",
  ["GET /repos/{owner}/{repo}/comments/{comment_id}"]                          = "get_repo_comment",
  ["PATCH /repos/{owner}/{repo}/comments/{comment_id}"]                        = "patch_repo_comment",
  ["DELETE /repos/{owner}/{repo}/comments/{comment_id}"]                       = "delete_repo_comment",
  ["GET /repos/{owner}/{repo}/commits/{commit_sha}/comments"]                  = "get_commit_comments",
  ["POST /repos/{owner}/{repo}/commits/{commit_sha}/comments"]                 = "post_commit_comment",

  -- Statuses
  ["GET /repos/{owner}/{repo}/commits/{ref}/statuses"]                         = "get_commit_statuses",
  ["GET /repos/{owner}/{repo}/commits/{ref}/status"]                           = "get_commit_combined_status",
  ["POST /repos/{owner}/{repo}/statuses/{sha}"]                                = "post_commit_status",

  -- Contents (https://docs.github.com/en/rest/repos/contents)
  ["GET /repos/{owner}/{repo}/readme"]                                         = "get_repo_readme",
  ["GET /repos/{owner}/{repo}/readme/{dir}"]                                   = "get_repo_readme_dir",
  ["GET /repos/{owner}/{repo}/contents/{path}"]                                = "get_repo_content",
  ["PUT /repos/{owner}/{repo}/contents/{path}"]                                = "put_repo_content",
  ["DELETE /repos/{owner}/{repo}/contents/{path}"]                             = "delete_repo_content",
  ["GET /repos/{owner}/{repo}/tarball/{ref}"]                                  = "get_repo_tarball",
  ["GET /repos/{owner}/{repo}/zipball/{ref}"]                                  = "get_repo_zipball",

  -- Compare
  ["GET /repos/{owner}/{repo}/compare/{basehead}"]                             = "get_repo_compare",

  -- Collaborators (https://docs.github.com/en/rest/collaborators)
  ["GET /repos/{owner}/{repo}/collaborators"]                                  = "get_repo_collaborators",
  ["GET /repos/{owner}/{repo}/collaborators/{username}"]                       = "get_repo_collaborator",
  ["PUT /repos/{owner}/{repo}/collaborators/{username}"]                       = "put_repo_collaborator",
  ["DELETE /repos/{owner}/{repo}/collaborators/{username}"]                    = "delete_repo_collaborator",
  ["GET /repos/{owner}/{repo}/collaborators/{username}/permission"]            = "get_repo_collaborator_permission",

  -- Forks (https://docs.github.com/en/rest/repos/forks)
  ["GET /repos/{owner}/{repo}/forks"]                                          = "get_repo_forks",
  ["POST /repos/{owner}/{repo}/forks"]                                         = "post_repo_forks",

  -- Merges (https://docs.github.com/en/rest/branches/merging)
  ["POST /repos/{owner}/{repo}/merges"]                                        = "post_repo_merges",
  ["POST /repos/{owner}/{repo}/merge-upstream"]                                = "post_repo_merge_upstream",

  -- Releases (https://docs.github.com/en/rest/releases)
  ["GET /repos/{owner}/{repo}/releases"]                                       = "get_repo_releases",
  ["POST /repos/{owner}/{repo}/releases"]                                      = "post_repo_releases",
  ["GET /repos/{owner}/{repo}/releases/latest"]                                = "get_repo_release_latest",
  ["GET /repos/{owner}/{repo}/releases/tags/{tag}"]                            = "get_repo_release_by_tag",
  ["GET /repos/{owner}/{repo}/releases/{release_id}"]                          = "get_repo_release",
  ["PATCH /repos/{owner}/{repo}/releases/{release_id}"]                        = "patch_repo_release",
  ["DELETE /repos/{owner}/{repo}/releases/{release_id}"]                       = "delete_repo_release",
  ["GET /repos/{owner}/{repo}/releases/{release_id}/assets"]                   = "get_repo_release_assets",
  ["POST /repos/{owner}/{repo}/releases/{release_id}/assets"]                  = "post_repo_release_assets",
  ["GET /repos/{owner}/{repo}/releases/assets/{asset_id}"]                     = "get_repo_release_asset",
  ["PATCH /repos/{owner}/{repo}/releases/assets/{asset_id}"]                   = "patch_repo_release_asset",
  ["DELETE /repos/{owner}/{repo}/releases/assets/{asset_id}"]                  = "delete_repo_release_asset",

  -- Deploy keys (https://docs.github.com/en/rest/deploy-keys)
  ["GET /repos/{owner}/{repo}/keys"]                                           = "get_repo_keys",
  ["POST /repos/{owner}/{repo}/keys"]                                          = "post_repo_keys",
  ["GET /repos/{owner}/{repo}/keys/{key_id}"]                                  = "get_repo_key",
  ["DELETE /repos/{owner}/{repo}/keys/{key_id}"]                               = "delete_repo_key",

  -- Webhooks (https://docs.github.com/en/rest/repos/webhooks)
  ["GET /repos/{owner}/{repo}/hooks"]                                          = "get_repo_hooks",
  ["POST /repos/{owner}/{repo}/hooks"]                                         = "post_repo_hooks",
  ["GET /repos/{owner}/{repo}/hooks/{hook_id}"]                                = "get_repo_hook",
  ["PATCH /repos/{owner}/{repo}/hooks/{hook_id}"]                              = "patch_repo_hook",
  ["DELETE /repos/{owner}/{repo}/hooks/{hook_id}"]                             = "delete_repo_hook",
  ["GET /repos/{owner}/{repo}/hooks/{hook_id}/config"]                         = "get_repo_hook_config",
  ["PATCH /repos/{owner}/{repo}/hooks/{hook_id}/config"]                       = "patch_repo_hook_config",
  ["POST /repos/{owner}/{repo}/hooks/{hook_id}/pings"]                         = "post_repo_hook_ping",
  ["POST /repos/{owner}/{repo}/hooks/{hook_id}/tests"]                         = "post_repo_hook_test",

  -- Statistics (https://docs.github.com/en/rest/metrics/statistics)
  ["GET /repos/{owner}/{repo}/stats/code_frequency"]                           = "get_repo_stats_code_frequency",
  ["GET /repos/{owner}/{repo}/stats/commit_activity"]                          = "get_repo_stats_commit_activity",
  ["GET /repos/{owner}/{repo}/stats/contributors"]                             = "get_repo_stats_contributors",
  ["GET /repos/{owner}/{repo}/stats/participation"]                            = "get_repo_stats_participation",
  ["GET /repos/{owner}/{repo}/stats/punch_card"]                               = "get_repo_stats_punch_card",

  -- Traffic (https://docs.github.com/en/rest/metrics/traffic)
  ["GET /repos/{owner}/{repo}/traffic/clones"]                                 = "get_repo_traffic_clones",
  ["GET /repos/{owner}/{repo}/traffic/popular/paths"]                          = "get_repo_traffic_paths",
  ["GET /repos/{owner}/{repo}/traffic/popular/referrers"]                      = "get_repo_traffic_referrers",
  ["GET /repos/{owner}/{repo}/traffic/views"]                                  = "get_repo_traffic_views",

  -- Invitations (https://docs.github.com/en/rest/collaborators/invitations)
  ["GET /repos/{owner}/{repo}/invitations"]                                    = "get_repo_invitations",
  ["PATCH /repos/{owner}/{repo}/invitations/{invitation_id}"]                  = "patch_repo_invitation",
  ["DELETE /repos/{owner}/{repo}/invitations/{invitation_id}"]                 = "delete_repo_invitation",
  ["GET /user/repository_invitations"]                                         = "get_user_repo_invitations",
  ["PATCH /user/repository_invitations/{invitation_id}"]                       = "patch_user_repo_invitation",
  ["DELETE /user/repository_invitations/{invitation_id}"]                      = "delete_user_repo_invitation",

  -- Deployments (https://docs.github.com/en/rest/deployments)
  ["GET /repos/{owner}/{repo}/deployments"]                                    = "get_repo_deployments",
  ["POST /repos/{owner}/{repo}/deployments"]                                   = "post_repo_deployments",
  ["GET /repos/{owner}/{repo}/deployments/{deployment_id}"]                    = "get_repo_deployment",
  ["DELETE /repos/{owner}/{repo}/deployments/{deployment_id}"]                 = "delete_repo_deployment",
  ["GET /repos/{owner}/{repo}/deployments/{deployment_id}/statuses"]           = "get_repo_deployment_statuses",
  ["POST /repos/{owner}/{repo}/deployments/{deployment_id}/statuses"]          = "post_repo_deployment_status",
  ["GET /repos/{owner}/{repo}/deployments/{deployment_id}/statuses/{status_id}"] = "get_repo_deployment_status",

  -- Teams (https://docs.github.com/en/rest/teams)
  ["GET /orgs/{org}/teams"]                                                       = "get_org_teams",
  ["POST /orgs/{org}/teams"]                                                      = "post_org_teams",
  ["GET /orgs/{org}/teams/{team_slug}"]                                           = "get_org_team",
  ["PATCH /orgs/{org}/teams/{team_slug}"]                                         = "patch_org_team",
  ["DELETE /orgs/{org}/teams/{team_slug}"]                                        = "delete_org_team",
  ["GET /orgs/{org}/teams/{team_slug}/invitations"]                               = "get_org_team_invitations",
  ["GET /orgs/{org}/teams/{team_slug}/members"]                                   = "get_org_team_members",
  ["GET /orgs/{org}/teams/{team_slug}/memberships/{username}"]                    = "get_org_team_membership",
  ["PUT /orgs/{org}/teams/{team_slug}/memberships/{username}"]                    = "put_org_team_membership",
  ["DELETE /orgs/{org}/teams/{team_slug}/memberships/{username}"]                 = "delete_org_team_membership",
  ["GET /orgs/{org}/teams/{team_slug}/repos"]                                     = "get_org_team_repos",
  ["GET /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}"]                      = "get_org_team_repo",
  ["PUT /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}"]                      = "put_org_team_repo",
  ["DELETE /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}"]                   = "delete_org_team_repo",
  ["GET /orgs/{org}/teams/{team_slug}/teams"]                                     = "get_org_team_children",

  -- Legacy team endpoints (team_id-based) — deprecated in favour of slug-based above
  ["GET /user/teams"]                                                              = "get_user_teams",
  ["GET /teams/{team_id}"]                                                         = "get_team",
  ["PATCH /teams/{team_id}"]                                                       = "patch_team",
  ["DELETE /teams/{team_id}"]                                                      = "delete_team",
  ["GET /teams/{team_id}/invitations"]                                             = "get_team_invitations",
  ["GET /teams/{team_id}/members"]                                                 = "get_team_members",
  ["GET /teams/{team_id}/members/{username}"]                                      = "get_team_member",
  ["PUT /teams/{team_id}/members/{username}"]                                      = "put_team_member",
  ["DELETE /teams/{team_id}/members/{username}"]                                   = "delete_team_member",
  ["GET /teams/{team_id}/memberships/{username}"]                                  = "get_team_membership",
  ["PUT /teams/{team_id}/memberships/{username}"]                                  = "put_team_membership",
  ["DELETE /teams/{team_id}/memberships/{username}"]                               = "delete_team_membership",
  ["GET /teams/{team_id}/repos"]                                                   = "get_team_repos",
  ["GET /teams/{team_id}/repos/{owner}/{repo}"]                                    = "get_team_repo",
  ["PUT /teams/{team_id}/repos/{owner}/{repo}"]                                    = "put_team_repo",
  ["DELETE /teams/{team_id}/repos/{owner}/{repo}"]                                 = "delete_team_repo",
  ["GET /teams/{team_id}/teams"]                                                   = "get_team_children",

  -- Security advisories (https://docs.github.com/en/rest/security-advisories)
  ["GET /advisories"]                                                              = "get_global_advisories",
  ["GET /advisories/{ghsa_id}"]                                                   = "get_global_advisory",
  ["GET /orgs/{org}/security-advisories"]                                          = "get_org_security_advisories",
  ["GET /repos/{owner}/{repo}/security-advisories"]                                = "get_repo_security_advisories",
  ["POST /repos/{owner}/{repo}/security-advisories"]                               = "post_repo_security_advisory",
  ["POST /repos/{owner}/{repo}/security-advisories/reports"]                       = "post_repo_security_advisory_report",
  ["GET /repos/{owner}/{repo}/security-advisories/{ghsa_id}"]                      = "get_repo_security_advisory",
  ["PATCH /repos/{owner}/{repo}/security-advisories/{ghsa_id}"]                    = "patch_repo_security_advisory",
  ["POST /repos/{owner}/{repo}/security-advisories/{ghsa_id}/cve"]                 = "post_repo_security_advisory_cve",
  ["POST /repos/{owner}/{repo}/security-advisories/{ghsa_id}/forks"]               = "post_repo_security_advisory_fork",

  -- Users (https://docs.github.com/en/rest/users)
  ["GET /user"]                                                                    = "get_user",
  ["PATCH /user"]                                                                  = "patch_user",
  ["GET /user/{account_id}"]                                                       = "get_user_by_id",
  ["GET /users"]                                                                   = "get_users",
  ["GET /users/{username}"]                                                        = "get_users_username",
  ["GET /users/{username}/hovercard"]                                              = "get_users_hovercard",

  -- Blocking
  ["GET /user/blocks"]                                                             = "get_user_blocks",
  ["GET /user/blocks/{username}"]                                                  = "get_user_block",
  ["PUT /user/blocks/{username}"]                                                  = "put_user_block",
  ["DELETE /user/blocks/{username}"]                                               = "delete_user_block",

  -- Emails
  ["GET /user/emails"]                                                             = "get_user_emails",
  ["POST /user/emails"]                                                            = "post_user_emails",
  ["DELETE /user/emails"]                                                          = "delete_user_emails",
  ["PATCH /user/email/visibility"]                                                 = "patch_user_email_visibility",
  ["GET /user/public_emails"]                                                      = "get_user_public_emails",

  -- Followers
  ["GET /user/followers"]                                                          = "get_user_followers",
  ["GET /user/following"]                                                          = "get_user_following",
  ["GET /user/following/{username}"]                                               = "get_user_is_following",
  ["PUT /user/following/{username}"]                                               = "put_user_following",
  ["DELETE /user/following/{username}"]                                            = "delete_user_following",
  ["GET /users/{username}/followers"]                                              = "get_users_followers",
  ["GET /users/{username}/following"]                                              = "get_users_following",
  ["GET /users/{username}/following/{target_user}"]                                = "get_users_is_following",

  -- GPG Keys
  ["GET /user/gpg_keys"]                                                           = "get_user_gpg_keys",
  ["POST /user/gpg_keys"]                                                          = "post_user_gpg_keys",
  ["GET /user/gpg_keys/{gpg_key_id}"]                                              = "get_user_gpg_key",
  ["DELETE /user/gpg_keys/{gpg_key_id}"]                                           = "delete_user_gpg_key",
  ["GET /users/{username}/gpg_keys"]                                               = "get_users_gpg_keys",

  -- SSH Keys
  ["GET /user/keys"]                                                               = "get_user_keys",
  ["POST /user/keys"]                                                              = "post_user_keys",
  ["GET /user/keys/{key_id}"]                                                      = "get_user_key",
  ["DELETE /user/keys/{key_id}"]                                                   = "delete_user_key",
  ["GET /users/{username}/keys"]                                                   = "get_users_keys",

  -- Social Accounts
  ["GET /user/social_accounts"]                                                    = "get_user_social_accounts",
  ["POST /user/social_accounts"]                                                   = "post_user_social_accounts",
  ["DELETE /user/social_accounts"]                                                 = "delete_user_social_accounts",
  ["GET /users/{username}/social_accounts"]                                        = "get_users_social_accounts",

  -- SSH Signing Keys
  ["GET /user/ssh_signing_keys"]                                                   = "get_user_ssh_signing_keys",
  ["POST /user/ssh_signing_keys"]                                                  = "post_user_ssh_signing_keys",
  ["GET /user/ssh_signing_keys/{ssh_signing_key_id}"]                              = "get_user_ssh_signing_key",
  ["DELETE /user/ssh_signing_keys/{ssh_signing_key_id}"]                           = "delete_user_ssh_signing_key",
  ["GET /users/{username}/ssh_signing_keys"]                                       = "get_users_ssh_signing_keys",
}
for spec, name in pairs(routes) do route_add(spec, name) end

function OnHttpRequest()
  local ep, caps = route_match(GetMethod(), GetPath())
  if ep then
    local fn = handle[ep]
    if fn then fn(table.unpack(caps))
    else respond_json(404, "Not Found", { message = "Not Found" }) end
  elseif path_known(GetPath()) then
    respond_json(405, "Method Not Allowed", { message = "Method Not Allowed" })
  else
    respond_json(404, "Not Found", { message = "Not Found" })
  end
end
