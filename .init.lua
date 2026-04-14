-- Config defaults (global: backends/<name>.lua can read at startup)
-- base_url defaults to "" here; each backend sets its own default at load time
-- (after SCRIPTARGS are applied) if the user hasn't provided an explicit value.
config = {
  backend = "",
  base_url = "",
}

-- SCRIPTARGS (positional after --): first arg = backend, second = base_url.
local positional_keys = { "backend", "base_url" }
local pos_idx = 1
for _, a in ipairs(arg or {}) do
  if positional_keys[pos_idx] then
    config[positional_keys[pos_idx]] = a
    pos_idx = pos_idx + 1
  end
end

config.base_url = config.base_url:gsub("/$", "")

-- set_preamble is global: backends/<name>.lua uses it.
-- Sets the HTTP status (with text looked up by code) and Content-Type header.
-- content_type defaults to "application/json; charset=utf-8".
local HTTP_STATUS_TEXT = {
  [200] = "OK",
  [201] = "Created",
  [204] = "No Content",
  [302] = "Found",
  [401] = "Unauthorized",
  [404] = "Not Found",
  [405] = "Method Not Allowed",
  [410] = "Gone",
  [418] = "I'm a Teapot",
  [422] = "Unprocessable Entity",
  [501] = "Not Implemented",
  [503] = "Service Unavailable",
}
function set_preamble(status, content_type)
  if type(status) == "string" then
    content_type = status
    status = 200
  else
    status = status or 200
  end
  SetStatus(status, HTTP_STATUS_TEXT[status] or tostring(status))
  SetHeader("Content-Type", content_type or "application/json; charset=utf-8")
end

-- respond_json is global: backends/<name>.lua uses it.
function respond_json(status, body)
  set_preamble(status)
  Write(EncodeJson(body))
end

-- rewrite_link_header is global: called by proxy_json when page_params are provided.
-- Rewrites each URL in an upstream Link header to point back at confusio.
--
-- upstream_link: raw Link header value from the upstream response (may be nil)
-- mapping: same { per_page = "upstream_name", page = "upstream_name" } as append_page_params
--
-- Returns a GitHub-style Link header value, or nil when there is nothing to emit.
-- Only params present in the reverse mapping survive; unrecognised upstream params are dropped.
function rewrite_link_header(upstream_link, mapping)
  if not upstream_link or upstream_link == "" then
    return nil
  end

  -- Reverse the caller-supplied mapping so we can translate upstream → GitHub param names.
  local reverse = {}
  for gh, up in pairs(mapping) do
    reverse[up] = gh
  end

  local host = GetHeader("Host") or "localhost"
  local proto = GetHeader("X-Forwarded-Proto") or "http"
  local self_base = proto .. "://" .. host .. GetPath()

  local entries = {}
  for url, rel in upstream_link:gmatch('<([^>]+)>%s*;%s*rel="([^"]+)"') do
    local query = url:match("%?(.+)$") or ""
    local params = {}
    for k, v in query:gmatch("([^&=]+)=([^&]+)") do
      local gh = reverse[k]
      if gh then
        params[#params + 1] = gh .. "=" .. v
      end
    end
    local new_url = self_base
    if #params > 0 then
      new_url = new_url .. "?" .. table.concat(params, "&")
    end
    entries[#entries + 1] = "<" .. new_url .. '>; rel="' .. rel .. '"'
  end

  return #entries > 0 and table.concat(entries, ", ") or nil
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
--
-- No Link header is emitted; use proxy_json_paged for paginated list endpoints.
function proxy_json(translate, ok, status, _headers, body)
  if ok and status == 200 then
    local data = DecodeJson(body) or {}
    respond_json(200, translate and translate(data) or data)
  elseif ok then
    respond_json(status, {})
  else
    respond_json(503, {})
  end
end

-- proxy_json_paged: like proxy_json but rewrites the upstream Link header to point at confusio.
-- page_params sits before the fetch result so fetch_json(...) can still be the last argument
-- and Lua expands its multiple return values correctly:
--   proxy_json_paged(translate_fn, PAGES, fetch_json(url))
--   proxy_json_paged(nil,           PAGES, fetch_json(url))
function proxy_json_paged(translate, page_params, ok, status, headers, body)
  if ok and status == 200 then
    local data = DecodeJson(body) or {}
    local link = headers and (headers["Link"] or headers["link"])
    local rewritten = rewrite_link_header(link, page_params)
    -- set_preamble calls SetStatus which clears previously-set headers, so the Link
    -- header must be set AFTER set_preamble, not before.
    set_preamble(200)
    if rewritten then
      SetHeader("Link", rewritten)
    end
    Write(EncodeJson(translate and translate(data) or data))
  elseif ok then
    respond_json(status, {})
  else
    respond_json(503, {})
  end
end

-- Like proxy_json but for create endpoints: upstream may return 200 or 201;
-- confusio always responds 201 Created.
function proxy_json_created(translate, ok, status, _headers, body)
  if ok and (status == 200 or status == 201) then
    local data = DecodeJson(body) or {}
    respond_json(201, translate and translate(data) or data)
  elseif ok then
    respond_json(status, {})
  else
    respond_json(503, {})
  end
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
  if #parts == 0 then
    return url
  end
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
  if not h or h == "" then
    return nil
  end
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
-- proxy_fn defaults to proxy_json; pass proxy_json_created for 201 Created endpoints.
function make_proxy_handler(fetch_fn, proxy_fn)
  proxy_fn = proxy_fn or proxy_json
  return function(xform, url_fn)
    return function(...)
      local args = { ... }
      proxy_fn(type(xform) == "function" and function(r)
        return xform(r, table.unpack(args))
      end or xform, fetch_fn(url_fn(...)))
    end
  end
end

-- translate_repo is global: maps a Gitea-style repo object to GitHub field names.
-- Called by any Gitea-API-compatible backend (gitea, forgejo, gogs, codeberg, notabug).
function translate_repo(r)
  if not r then
    return {}
  end
  local owner = r.owner or {}
  return {
    id = r.id,
    node_id = "",
    name = r.name,
    full_name = r.full_name,
    private = r.private,
    owner = {
      login = owner.login,
      id = owner.id,
      node_id = "",
      avatar_url = owner.avatar_url,
      url = owner.url,
      html_url = owner.html_url,
      type = owner.type or (owner.is_admin and "Admin" or "User"),
    },
    html_url = r.html_url,
    description = r.description,
    fork = r.fork,
    url = r.url,
    git_url = r.ssh_url,
    ssh_url = r.ssh_url,
    clone_url = r.clone_url,
    homepage = r.website,
    size = r.size,
    stargazers_count = r.stars_count,
    watchers_count = r.watchers_count,
    language = r.language,
    has_issues = r.has_issues,
    has_wiki = r.has_wiki,
    forks_count = r.forks_count,
    archived = r.archived,
    disabled = false,
    open_issues_count = r.open_issues_count,
    default_branch = r.default_branch,
    visibility = r.visibility or (r.private and "private" or "public"),
    forks = r.forks_count,
    open_issues = r.open_issues_count,
    watchers = r.watchers_count,
    created_at = r.created,
    updated_at = r.updated,
    pushed_at = r.updated,
    permissions = r.permissions,
  }
end

-- translate_user is global: maps a Gitea-style user object to GitHub field names.
-- Called by any Gitea-API-compatible backend (gitea, forgejo, gogs, codeberg, notabug).
function translate_user(u)
  if not u then
    return {}
  end
  return {
    login = u.login,
    id = u.id,
    node_id = "",
    avatar_url = u.avatar_url,
    html_url = u.html_url,
    type = "User",
    site_admin = u.is_admin or false,
    name = u.full_name,
    email = u.email,
    location = u.location,
    blog = u.website,
    followers = u.followers_count or 0,
    following = u.following_count or 0,
    created_at = u.created,
  }
end

-- translate_migration is global: maps a backend migration object to GitHub field names.
-- The GitHub migration schema: https://docs.github.com/en/rest/migrations
-- Required fields: id, node_id, owner, guid, state, lock_repositories,
--   exclude_metadata, exclude_git_data, exclude_attachments, exclude_releases,
--   exclude_owner_projects, org_metadata_only, repositories, url, created_at, updated_at.
-- Optional fields: archive_url, exclude.
function translate_migration(m)
  if not m then
    return {}
  end
  return {
    id = m.id,
    node_id = m.node_id or "",
    owner = m.owner,
    guid = m.guid or "",
    state = m.state or "pending",
    lock_repositories = m.lock_repositories or false,
    exclude_metadata = m.exclude_metadata or false,
    exclude_git_data = m.exclude_git_data or false,
    exclude_attachments = m.exclude_attachments or false,
    exclude_releases = m.exclude_releases or false,
    exclude_owner_projects = m.exclude_owner_projects or false,
    org_metadata_only = m.org_metadata_only or false,
    repositories = m.repositories or {},
    url = m.url or "",
    created_at = m.created_at or "",
    updated_at = m.updated_at or "",
    archive_url = m.archive_url,
    exclude = m.exclude or {},
  }
end

-- backend_impl is global: set by backends/<name>.lua at startup.
backend_impl = {}
-- backend_allow_anonymous is global: backends that require sign-in set this to false
-- at startup (after checking the provider's API settings). Default: allow.
backend_allow_anonymous = true
if config.backend ~= "" then
  assert(config.backend:match("^[%a][%w_]*$"), "invalid backend name: " .. config.backend)
  dofile("/zip/backends/" .. config.backend .. ".lua")
end

-- Handlers resolved once at startup; backend is fixed for the program's lifetime.
-- Registered routes not implemented by the backend return 404.
local handle = backend_impl

-- Default handler for list endpoints: backends without native support return [].
-- Backends that implement the endpoint override it; others fall back to this default.
local function empty_list()
  set_preamble()
  Write("[]")
end

-- Default handler for search endpoints: backends without native support return an
-- empty but valid GitHub search result envelope.
local function search_empty()
  set_preamble()
  Write('{"total_count":0,"incomplete_results":false,"items":[]}')
end

-- Default handler for GET /rate_limit: no provider has a GitHub-compatible rate
-- limit API, so confusio returns a partial response with just the `rate` key.
-- limit=999999 means "effectively unlimited"; reset is set one hour ahead of now.
local function rate_limit_response()
  local limit = 999999
  local reset = os.time() + 3600
  respond_json(200, {
    rate = { limit = limit, used = 0, remaining = limit, reset = reset },
  })
end

-- Default handlers for interaction-limits: no backend has a native interactions API.
-- GET returns {} (no restrictions in effect).
-- PUT echoes the provided limit back (acknowledged but not enforced).
-- DELETE returns 204 (no restrictions to remove).
local function interaction_limits_empty()
  set_preamble()
  Write("{}")
end

local function interaction_limits_put()
  local body = DecodeJson(GetBody() or "{}") or {}
  respond_json(200, body)
end

local function interaction_limits_delete()
  set_preamble(204)
end

-- Default handlers for migrations: no backend exposes GitHub-compatible migration APIs.
-- POST (start migration) returns 501 Not Implemented.
-- Per-resource endpoints (GET/DELETE on a specific migration) return 404.
-- Source import endpoints were deprecated by GitHub in May 2023; returns 410 Gone.
local function migrations_not_supported()
  respond_json(501, { message = "Migrations are not supported by this backend." })
end

local function migration_not_found()
  respond_json(404, { message = "Not Found" })
end

local function source_import_gone()
  respond_json(410, { message = "Importing via GitHub API is deprecated." })
end

-- Default handler for code-scanning endpoints: no backend has a native code scanning API.
-- Returns 501 Not Implemented with a descriptive message.
local function code_scanning_not_implemented()
  respond_json(501, { message = "Code scanning is not supported by this backend." })
end

-- Default handler for code-scanning list endpoints: returns an empty collection (200).
-- Per-resource endpoints use code_scanning_not_implemented (501) as their default.
local function code_scanning_list_empty()
  respond_json(200, {})
end

-- Default handlers for secret-scanning endpoints: no backend has a native secret scanning API.
-- Returns 501 Not Implemented with a descriptive message.
local function secret_scanning_not_implemented()
  respond_json(501, { message = "Secret scanning is not supported by this backend." })
end

-- Default handler for secret-scanning list endpoints: returns an empty collection (200).
-- Per-resource and mutation endpoints use secret_scanning_not_implemented (501) as their default.
local function secret_scanning_list_empty()
  respond_json(200, {})
end

-- Default handlers for Dependabot endpoints: most backends have no native Dependabot API.
-- Alert list endpoints return empty arrays (200); per-resource and mutation endpoints return 501.
-- Secrets list endpoints use make_empty_collection (defined below) for proper envelope format.
local function dependabot_not_implemented()
  respond_json(501, { message = "Dependabot is not supported by this backend." })
end

local function dependabot_list_empty()
  respond_json(200, {})
end

-- Default handler for Pages endpoints: no backend has a native GitHub Pages API.
-- Returns 501 Not Implemented with a descriptive message.
local function pages_not_implemented()
  respond_json(501, { message = "Pages is not supported by this backend." })
end

-- Default handler for Markdown endpoints: backends that support native markdown
-- rendering override these. Falls back to 501 Not Implemented.
local function markdown_not_implemented()
  respond_json(501, { message = "Markdown rendering is not supported by this backend." })
end

-- Default handlers for Actions endpoints: no backend has a native GitHub Actions-compatible API.
-- List endpoints use make_empty_collection to return a valid GitHub Actions envelope.
-- Per-resource and mutation endpoints return 501 Not Implemented.
local function actions_not_implemented()
  respond_json(501, { message = "Actions is not supported by this backend." })
end

-- Factory for Actions list endpoints: returns a handler that writes
-- {"total_count":0,"<key>":[]}, where key is the GitHub API collection name.
local function make_empty_collection(key)
  return function()
    set_preamble()
    Write('{"total_count":0,"' .. key .. '":[]}')
  end
end

-- Default handler for Git database endpoints: backends that have a native low-level
-- git object API override these. Falls back to 501 Not Implemented.
local function git_not_implemented()
  respond_json(501, { message = "Git database API is not supported by this backend." })
end

-- Default handler for Licenses endpoints: backends that have a native license
-- template API override these. Falls back to 501 Not Implemented.
local function licenses_not_implemented()
  respond_json(501, { message = "Licenses API is not supported by this backend." })
end

-- Default handler for Dependency Graph endpoints: backends that have a native
-- dependency graph API override these. Falls back to 501 Not Implemented.
local function dependency_graph_not_implemented()
  respond_json(501, { message = "Dependency graph is not supported by this backend." })
end

-- Default handlers for Projects endpoints: most backends have no native Projects API.
-- List endpoints return empty arrays (200); per-resource and mutation endpoints return 501.
local function projects_not_implemented()
  respond_json(501, { message = "Projects is not supported by this backend." })
end

local function projects_list_empty()
  respond_json(200, {})
end

-- Default handlers for Gists endpoints: most backends have no native gist API.
-- List endpoints return empty arrays (200); per-resource and mutation endpoints return 501.
local function gists_not_implemented()
  respond_json(501, { message = "Gists are not supported by this backend." })
end

-- Default handlers for Activity endpoints: event feeds, notifications, starring, and watching.
-- List endpoints return empty arrays (200); per-resource and mutation endpoints return 501.
local function activity_not_implemented()
  respond_json(501, { message = "This activity endpoint is not supported by this backend." })
end

local function activity_list_empty()
  set_preamble()
  Write("[]")
end

-- Default handlers for Reactions endpoints (commit comments, issue comments, issues, PR comments, releases).
-- List endpoints return empty arrays (200); create and delete endpoints return 501.
local function reactions_not_implemented()
  respond_json(501, { message = "Reactions are not supported by this backend." })
end

-- Default handlers for GET /zen, GET /octocat, GET /versions, GET /meta.
-- These endpoints are fully self-contained and do not call any backend.
local ZEN_QUOTES = {
  "A good dog does not need to understand the command.",
  "Fetch once; cache twice.",
  "The loyal dog returns what it is given.",
  "Sit. Stay. Commit.",
  "Every good boy deserves a response.",
  "Bark less, ship more.",
  "The dog who chases two rabbits catches neither.",
  "A wagging tail costs nothing.",
  "Treat the happy path as you would a good dog: reward it.",
  "Even the best dog buries things it cannot yet use.",
  "You cannot teach an old dog new protocols.",
  "The dog does not judge the bone.",
  "Roll over. Roll back.",
}
math.randomseed(os.time())
local function zen_response()
  set_preamble("text/plain;charset=utf-8")
  Write(ZEN_QUOTES[math.random(#ZEN_QUOTES)])
end

local function octocat_response()
  set_preamble("application/octocat-stream")
  Write("🐙🐱")
end

local function versions_response()
  set_preamble()
  Write('["2022-11-28"]')
end

-- meta_response returns a minimal but valid GitHub /meta structure.
-- IP range arrays are empty since confusio is not GitHub infrastructure.
local function meta_response()
  set_preamble()
  Write(
    '{"verifiable_password_authentication":false'
      .. ',"ssh_key_fingerprints":{}'
      .. ',"ssh_keys":[]'
      .. ',"hooks":[]'
      .. ',"web":[]'
      .. ',"api":[]'
      .. ',"git":[]'
      .. ',"packages":[]'
      .. ',"pages":[]'
      .. ',"importer":[]'
      .. ',"actions":[]'
      .. ',"dependabot":[]'
      .. ',"github_enterprise_importer":[]'
      .. ',"domains":{"website":[],"codespaces":[],"copilot":[],"packages":[]}}'
  )
end

local function teapot_response()
  set_preamble(418, "text/plain;charset=utf-8")
  Write("I'm a teapot.")
end

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

local function new_node()
  return { static = {}, param = nil, handler = nil }
end
local trie = new_node()
local path_trie = new_node()

local function _trie_insert(t, key)
  local node = t
  for seg in key:gmatch("[^/]+") do
    if seg:sub(1, 1) == "{" then
      node.param = node.param or new_node()
      node = node.param
      -- {param+} is a greedy capture: matches this segment and all remaining segments.
      if seg:sub(-2) == "+}" then
        node.greedy = true
        break
      end
    else
      node.static[seg] = node.static[seg] or new_node()
      node = node.static[seg]
    end
  end
  return node
end

-- route_add("VERB /path", handler_name [, default_fn])
-- e.g. route_add("GET /repos/{owner}/{repo}", "get_repo")
-- When default_fn is given it is used if the backend has no handler for handler_name.
local function route_add(route, handler_name, default_fn)
  local verb, path = route:match("^(%S+)%s+(.+)$")
  local n = _trie_insert(trie, verb .. path)
  n.handler = handler_name
  n.default = default_fn
  _trie_insert(path_trie, path).handler = true
end

-- _trie_walk traverses root over the "/" segments of key.
-- Returns the final node and a table of captured param values,
-- or nil if any segment has no matching edge.
-- Greedy param nodes ({param+}) capture this segment and all remaining segments as one value.
local function _trie_walk(root, key)
  local node = root
  local caps = {}
  local segs = {}
  for seg in key:gmatch("[^/]+") do
    segs[#segs + 1] = seg
  end
  local i = 1
  while i <= #segs do
    local seg = segs[i]
    if node.static[seg] then
      node = node.static[seg]
    elseif node.param then
      node = node.param
      if node.greedy then
        caps[#caps + 1] = table.concat(segs, "/", i)
        return node, caps
      end
      caps[#caps + 1] = seg
    else
      return nil
    end
    i = i + 1
  end
  return node, caps
end

local function route_match(method, path)
  local node, caps = _trie_walk(trie, method .. path)
  if node then
    return node.handler, caps, node.default
  end
  return nil, nil, nil
end

local function path_known(path)
  local node = _trie_walk(path_trie, path)
  return node ~= nil and node.handler == true
end

-- ---------------------------------------------------------------------------
-- Endpoint catalog
--
-- Authoritative source for every registered endpoint. Each entry is:
--   { "METHOD /path", handler_name [, default_fn] }
-- where default_fn is the fallback when no backend implements the handler.
-- Entries without a default omit the third element (nil → 404).
--
-- Entries are organised into named sections. { group = "name" } marker
-- entries separate sections; they carry no route data. The section loop
-- below sets e.group on every real entry and builds the global `endpoints`
-- table, which scripts/dump-endpoints.lua reads to export the catalog.
--
-- Backends override handlers by setting backend_impl.<name>. Parametric
-- captures from {param} segments are passed positionally to the handler.
-- ---------------------------------------------------------------------------

local _ep_catalog = {

  { group = "meta" },
  -- Root
  {
    "GET /",
    "get_root",
    function()
      respond_json(200, {})
    end,
  },

  -- Meta (https://docs.github.com/en/rest/meta)
  { "GET /meta", "get_meta", meta_response },
  { "GET /octocat", "get_octocat", octocat_response },
  { "GET /teapot", "get_teapot", teapot_response },
  { "GET /versions", "get_versions", versions_response },
  { "GET /zen", "get_zen", zen_response },

  -- Emojis
  { "GET /emojis", "get_emojis" },

  { group = "gitignore" },
  -- Gitignore templates (https://docs.github.com/en/rest/gitignore)
  { "GET /gitignore/templates", "get_gitignore_templates" },
  { "GET /gitignore/templates/{name}", "get_gitignore_template" },

  { group = "licenses" },
  -- Licenses (https://docs.github.com/en/rest/licenses)
  { "GET /licenses", "get_licenses", licenses_not_implemented },
  { "GET /licenses/{license}", "get_license", licenses_not_implemented },

  { group = "rate-limit" },
  -- Rate Limits (https://docs.github.com/en/rest/rate-limit)
  { "GET /rate_limit", "get_rate_limit", rate_limit_response },

  { group = "gists" },
  -- Gists (https://docs.github.com/en/rest/gists)
  { "GET /gists", "get_gists", empty_list },
  { "POST /gists", "post_gists", gists_not_implemented },
  { "GET /gists/public", "get_gists_public", empty_list },
  { "GET /gists/starred", "get_gists_starred", empty_list },
  { "GET /gists/{gist_id}", "get_gist", gists_not_implemented },
  { "PATCH /gists/{gist_id}", "patch_gist", gists_not_implemented },
  { "DELETE /gists/{gist_id}", "delete_gist", gists_not_implemented },
  { "GET /gists/{gist_id}/comments", "get_gist_comments", empty_list },
  { "POST /gists/{gist_id}/comments", "post_gist_comment", gists_not_implemented },
  { "GET /gists/{gist_id}/comments/{comment_id}", "get_gist_comment", gists_not_implemented },
  { "PATCH /gists/{gist_id}/comments/{comment_id}", "patch_gist_comment", gists_not_implemented },
  { "DELETE /gists/{gist_id}/comments/{comment_id}", "delete_gist_comment", gists_not_implemented },
  { "GET /gists/{gist_id}/commits", "get_gist_commits", empty_list },
  { "GET /gists/{gist_id}/forks", "get_gist_forks", empty_list },
  { "POST /gists/{gist_id}/forks", "post_gist_fork", gists_not_implemented },
  { "GET /gists/{gist_id}/star", "get_gist_star", gists_not_implemented },
  { "PUT /gists/{gist_id}/star", "put_gist_star", gists_not_implemented },
  { "DELETE /gists/{gist_id}/star", "delete_gist_star", gists_not_implemented },
  { "GET /gists/{gist_id}/{sha}", "get_gist_revision", gists_not_implemented },
  { "GET /users/{username}/gists", "get_user_gists", empty_list },

  { group = "activity" },
  -- Activity (https://docs.github.com/en/rest/activity)
  { "GET /events", "get_events", activity_list_empty },
  { "GET /feeds", "get_feeds", activity_not_implemented },
  { "GET /networks/{owner}/{repo}/events", "get_network_events", activity_list_empty },
  { "GET /notifications", "get_notifications", activity_list_empty },
  { "PUT /notifications", "put_notifications", activity_not_implemented },
  { "GET /notifications/threads/{thread_id}", "get_notification_thread", activity_not_implemented },
  {
    "PATCH /notifications/threads/{thread_id}",
    "patch_notification_thread",
    activity_not_implemented,
  },
  {
    "DELETE /notifications/threads/{thread_id}",
    "delete_notification_thread",
    activity_not_implemented,
  },
  {
    "GET /notifications/threads/{thread_id}/subscription",
    "get_notification_thread_subscription",
    activity_not_implemented,
  },
  {
    "PUT /notifications/threads/{thread_id}/subscription",
    "put_notification_thread_subscription",
    activity_not_implemented,
  },
  {
    "DELETE /notifications/threads/{thread_id}/subscription",
    "delete_notification_thread_subscription",
    activity_not_implemented,
  },
  { "GET /orgs/{org}/events", "get_org_events", activity_list_empty },
  { "GET /repos/{owner}/{repo}/events", "get_repo_events", activity_list_empty },
  { "GET /repos/{owner}/{repo}/notifications", "get_repo_notifications", activity_list_empty },
  { "PUT /repos/{owner}/{repo}/notifications", "put_repo_notifications", activity_not_implemented },
  { "GET /repos/{owner}/{repo}/stargazers", "get_repo_stargazers", activity_list_empty },
  { "GET /repos/{owner}/{repo}/subscribers", "get_repo_subscribers", activity_list_empty },
  { "GET /repos/{owner}/{repo}/subscription", "get_repo_subscription", activity_not_implemented },
  { "PUT /repos/{owner}/{repo}/subscription", "put_repo_subscription", activity_not_implemented },
  {
    "DELETE /repos/{owner}/{repo}/subscription",
    "delete_repo_subscription",
    activity_not_implemented,
  },
  { "GET /user/starred", "get_user_starred", activity_list_empty },
  { "GET /user/starred/{owner}/{repo}", "get_user_starred_repo", activity_not_implemented },
  { "PUT /user/starred/{owner}/{repo}", "put_user_starred_repo", activity_not_implemented },
  { "DELETE /user/starred/{owner}/{repo}", "delete_user_starred_repo", activity_not_implemented },
  { "GET /user/subscriptions", "get_user_subscriptions", activity_list_empty },
  { "GET /users/{username}/events", "get_users_events", activity_list_empty },
  { "GET /users/{username}/events/orgs/{org}", "get_users_org_events", activity_list_empty },
  { "GET /users/{username}/events/public", "get_users_public_events", activity_list_empty },
  { "GET /users/{username}/received_events", "get_users_received_events", activity_list_empty },
  {
    "GET /users/{username}/received_events/public",
    "get_users_received_public_events",
    activity_list_empty,
  },
  { "GET /users/{username}/starred", "get_users_starred", activity_list_empty },
  { "GET /users/{username}/subscriptions", "get_users_subscriptions", activity_list_empty },

  { group = "repos" },
  -- Repos core (https://docs.github.com/en/rest/repos/repos)
  { "GET /repos/{owner}/{repo}", "get_repo" },
  { "PATCH /repos/{owner}/{repo}", "patch_repo" },
  { "DELETE /repos/{owner}/{repo}", "delete_repo" },
  { "GET /user/repos", "get_user_repos" },
  { "POST /user/repos", "post_user_repos" },
  { "GET /orgs/{org}/repos", "get_org_repos" },
  { "POST /orgs/{org}/repos", "post_org_repos" },
  { "GET /users/{username}/repos", "get_users_repos" },
  { "GET /repositories", "get_repositories" },

  -- Topics / languages / contributors / tags / teams
  { "GET /repos/{owner}/{repo}/topics", "get_repo_topics" },
  { "PUT /repos/{owner}/{repo}/topics", "put_repo_topics" },
  { "GET /repos/{owner}/{repo}/languages", "get_repo_languages" },
  { "GET /repos/{owner}/{repo}/contributors", "get_repo_contributors" },
  { "GET /repos/{owner}/{repo}/tags", "get_repo_tags" },
  { "GET /repos/{owner}/{repo}/teams", "get_repo_teams" },

  { group = "repos-ext" },
  -- Branches (https://docs.github.com/en/rest/branches)
  { "GET /repos/{owner}/{repo}/branches", "get_repo_branches" },
  { "GET /repos/{owner}/{repo}/branches/{branch}", "get_repo_branch" },

  -- Commits (https://docs.github.com/en/rest/commits)
  { "GET /repos/{owner}/{repo}/commits", "get_repo_commits" },
  { "GET /repos/{owner}/{repo}/commits/{ref}", "get_repo_commit" },

  -- Commit comments
  { "GET /repos/{owner}/{repo}/comments", "get_repo_comments" },
  { "GET /repos/{owner}/{repo}/comments/{comment_id}", "get_repo_comment" },
  { "PATCH /repos/{owner}/{repo}/comments/{comment_id}", "patch_repo_comment" },
  { "DELETE /repos/{owner}/{repo}/comments/{comment_id}", "delete_repo_comment" },
  { "GET /repos/{owner}/{repo}/commits/{commit_sha}/comments", "get_commit_comments" },
  { "POST /repos/{owner}/{repo}/commits/{commit_sha}/comments", "post_commit_comment" },

  -- Statuses
  { "GET /repos/{owner}/{repo}/commits/{ref}/statuses", "get_commit_statuses" },
  { "GET /repos/{owner}/{repo}/commits/{ref}/status", "get_commit_combined_status" },
  { "POST /repos/{owner}/{repo}/statuses/{sha}", "post_commit_status" },

  -- Contents (https://docs.github.com/en/rest/repos/contents)
  { "GET /repos/{owner}/{repo}/readme", "get_repo_readme" },
  { "GET /repos/{owner}/{repo}/readme/{dir}", "get_repo_readme_dir" },
  { "GET /repos/{owner}/{repo}/contents/{path}", "get_repo_content" },
  { "PUT /repos/{owner}/{repo}/contents/{path}", "put_repo_content" },
  { "DELETE /repos/{owner}/{repo}/contents/{path}", "delete_repo_content" },
  { "GET /repos/{owner}/{repo}/tarball/{ref}", "get_repo_tarball" },
  { "GET /repos/{owner}/{repo}/zipball/{ref}", "get_repo_zipball" },

  { group = "licenses" },
  -- Repo license (https://docs.github.com/en/rest/licenses)
  { "GET /repos/{owner}/{repo}/license", "get_repo_license", licenses_not_implemented },

  { group = "repos-ext" },
  -- Compare
  { "GET /repos/{owner}/{repo}/compare/{basehead}", "get_repo_compare" },

  -- Collaborators (https://docs.github.com/en/rest/collaborators)
  { "GET /repos/{owner}/{repo}/collaborators", "get_repo_collaborators" },
  { "GET /repos/{owner}/{repo}/collaborators/{username}", "get_repo_collaborator" },
  { "PUT /repos/{owner}/{repo}/collaborators/{username}", "put_repo_collaborator" },
  { "DELETE /repos/{owner}/{repo}/collaborators/{username}", "delete_repo_collaborator" },
  {
    "GET /repos/{owner}/{repo}/collaborators/{username}/permission",
    "get_repo_collaborator_permission",
  },

  -- Forks (https://docs.github.com/en/rest/repos/forks)
  { "GET /repos/{owner}/{repo}/forks", "get_repo_forks" },
  { "POST /repos/{owner}/{repo}/forks", "post_repo_forks" },

  -- Merges (https://docs.github.com/en/rest/branches/merging)
  { "POST /repos/{owner}/{repo}/merges", "post_repo_merges" },
  { "POST /repos/{owner}/{repo}/merge-upstream", "post_repo_merge_upstream" },

  { group = "releases" },
  -- Releases (https://docs.github.com/en/rest/releases)
  { "GET /repos/{owner}/{repo}/releases", "get_repo_releases" },
  { "POST /repos/{owner}/{repo}/releases", "post_repo_releases" },
  { "GET /repos/{owner}/{repo}/releases/latest", "get_repo_release_latest" },
  { "GET /repos/{owner}/{repo}/releases/tags/{tag}", "get_repo_release_by_tag" },
  { "GET /repos/{owner}/{repo}/releases/{release_id}", "get_repo_release" },
  { "PATCH /repos/{owner}/{repo}/releases/{release_id}", "patch_repo_release" },
  { "DELETE /repos/{owner}/{repo}/releases/{release_id}", "delete_repo_release" },
  { "GET /repos/{owner}/{repo}/releases/{release_id}/assets", "get_repo_release_assets" },
  { "POST /repos/{owner}/{repo}/releases/{release_id}/assets", "post_repo_release_assets" },
  { "GET /repos/{owner}/{repo}/releases/assets/{asset_id}", "get_repo_release_asset" },
  { "PATCH /repos/{owner}/{repo}/releases/assets/{asset_id}", "patch_repo_release_asset" },
  { "DELETE /repos/{owner}/{repo}/releases/assets/{asset_id}", "delete_repo_release_asset" },

  { group = "repos-ext" },
  -- Deploy keys (https://docs.github.com/en/rest/deploy-keys)
  { "GET /repos/{owner}/{repo}/keys", "get_repo_keys" },
  { "POST /repos/{owner}/{repo}/keys", "post_repo_keys" },
  { "GET /repos/{owner}/{repo}/keys/{key_id}", "get_repo_key" },
  { "DELETE /repos/{owner}/{repo}/keys/{key_id}", "delete_repo_key" },

  -- Webhooks (https://docs.github.com/en/rest/repos/webhooks)
  { "GET /repos/{owner}/{repo}/hooks", "get_repo_hooks" },
  { "POST /repos/{owner}/{repo}/hooks", "post_repo_hooks" },
  { "GET /repos/{owner}/{repo}/hooks/{hook_id}", "get_repo_hook" },
  { "PATCH /repos/{owner}/{repo}/hooks/{hook_id}", "patch_repo_hook" },
  { "DELETE /repos/{owner}/{repo}/hooks/{hook_id}", "delete_repo_hook" },
  { "GET /repos/{owner}/{repo}/hooks/{hook_id}/config", "get_repo_hook_config" },
  { "PATCH /repos/{owner}/{repo}/hooks/{hook_id}/config", "patch_repo_hook_config" },
  { "POST /repos/{owner}/{repo}/hooks/{hook_id}/pings", "post_repo_hook_ping" },
  { "POST /repos/{owner}/{repo}/hooks/{hook_id}/tests", "post_repo_hook_test" },

  -- Statistics (https://docs.github.com/en/rest/metrics/statistics)
  { "GET /repos/{owner}/{repo}/stats/code_frequency", "get_repo_stats_code_frequency" },
  { "GET /repos/{owner}/{repo}/stats/commit_activity", "get_repo_stats_commit_activity" },
  { "GET /repos/{owner}/{repo}/stats/contributors", "get_repo_stats_contributors" },
  { "GET /repos/{owner}/{repo}/stats/participation", "get_repo_stats_participation" },
  { "GET /repos/{owner}/{repo}/stats/punch_card", "get_repo_stats_punch_card" },

  -- Traffic (https://docs.github.com/en/rest/metrics/traffic)
  { "GET /repos/{owner}/{repo}/traffic/clones", "get_repo_traffic_clones" },
  { "GET /repos/{owner}/{repo}/traffic/popular/paths", "get_repo_traffic_paths" },
  { "GET /repos/{owner}/{repo}/traffic/popular/referrers", "get_repo_traffic_referrers" },
  { "GET /repos/{owner}/{repo}/traffic/views", "get_repo_traffic_views" },

  -- Invitations (https://docs.github.com/en/rest/collaborators/invitations)
  { "GET /repos/{owner}/{repo}/invitations", "get_repo_invitations" },
  { "PATCH /repos/{owner}/{repo}/invitations/{invitation_id}", "patch_repo_invitation" },
  { "DELETE /repos/{owner}/{repo}/invitations/{invitation_id}", "delete_repo_invitation" },
  { "GET /user/repository_invitations", "get_user_repo_invitations" },
  { "PATCH /user/repository_invitations/{invitation_id}", "patch_user_repo_invitation" },
  { "DELETE /user/repository_invitations/{invitation_id}", "delete_user_repo_invitation" },

  -- Deployments (https://docs.github.com/en/rest/deployments)
  { "GET /repos/{owner}/{repo}/deployments", "get_repo_deployments" },
  { "POST /repos/{owner}/{repo}/deployments", "post_repo_deployments" },
  { "GET /repos/{owner}/{repo}/deployments/{deployment_id}", "get_repo_deployment" },
  { "DELETE /repos/{owner}/{repo}/deployments/{deployment_id}", "delete_repo_deployment" },
  {
    "GET /repos/{owner}/{repo}/deployments/{deployment_id}/statuses",
    "get_repo_deployment_statuses",
  },
  {
    "POST /repos/{owner}/{repo}/deployments/{deployment_id}/statuses",
    "post_repo_deployment_status",
  },
  {
    "GET /repos/{owner}/{repo}/deployments/{deployment_id}/statuses/{status_id}",
    "get_repo_deployment_status",
  },

  { group = "teams" },
  -- Teams (https://docs.github.com/en/rest/teams)
  { "GET /orgs/{org}/teams", "get_org_teams", empty_list },
  { "POST /orgs/{org}/teams", "post_org_teams" },
  { "GET /orgs/{org}/teams/{team_slug}", "get_org_team" },
  { "PATCH /orgs/{org}/teams/{team_slug}", "patch_org_team" },
  { "DELETE /orgs/{org}/teams/{team_slug}", "delete_org_team" },
  { "GET /orgs/{org}/teams/{team_slug}/invitations", "get_org_team_invitations", empty_list },
  { "GET /orgs/{org}/teams/{team_slug}/members", "get_org_team_members", empty_list },
  { "GET /orgs/{org}/teams/{team_slug}/memberships/{username}", "get_org_team_membership" },
  { "PUT /orgs/{org}/teams/{team_slug}/memberships/{username}", "put_org_team_membership" },
  { "DELETE /orgs/{org}/teams/{team_slug}/memberships/{username}", "delete_org_team_membership" },
  { "GET /orgs/{org}/teams/{team_slug}/repos", "get_org_team_repos", empty_list },
  { "GET /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}", "get_org_team_repo" },
  { "PUT /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}", "put_org_team_repo" },
  { "DELETE /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}", "delete_org_team_repo" },
  { "GET /orgs/{org}/teams/{team_slug}/teams", "get_org_team_children", empty_list },

  -- Legacy team endpoints (team_id-based) — deprecated in favour of slug-based above
  { "GET /user/teams", "get_user_teams", empty_list },
  { "GET /teams/{team_id}", "get_team" },
  { "PATCH /teams/{team_id}", "patch_team" },
  { "DELETE /teams/{team_id}", "delete_team" },
  { "GET /teams/{team_id}/invitations", "get_team_invitations", empty_list },
  { "GET /teams/{team_id}/members", "get_team_members", empty_list },
  { "GET /teams/{team_id}/members/{username}", "get_team_member" },
  { "PUT /teams/{team_id}/members/{username}", "put_team_member" },
  { "DELETE /teams/{team_id}/members/{username}", "delete_team_member" },
  { "GET /teams/{team_id}/memberships/{username}", "get_team_membership" },
  { "PUT /teams/{team_id}/memberships/{username}", "put_team_membership" },
  { "DELETE /teams/{team_id}/memberships/{username}", "delete_team_membership" },
  { "GET /teams/{team_id}/repos", "get_team_repos", empty_list },
  { "GET /teams/{team_id}/repos/{owner}/{repo}", "get_team_repo" },
  { "PUT /teams/{team_id}/repos/{owner}/{repo}", "put_team_repo" },
  { "DELETE /teams/{team_id}/repos/{owner}/{repo}", "delete_team_repo" },
  { "GET /teams/{team_id}/teams", "get_team_children", empty_list },

  { group = "security-advisories" },
  -- Security advisories (https://docs.github.com/en/rest/security-advisories)
  { "GET /advisories", "get_global_advisories", empty_list },
  { "GET /advisories/{ghsa_id}", "get_global_advisory" },
  { "GET /orgs/{org}/security-advisories", "get_org_security_advisories", empty_list },
  { "GET /repos/{owner}/{repo}/security-advisories", "get_repo_security_advisories", empty_list },
  { "POST /repos/{owner}/{repo}/security-advisories", "post_repo_security_advisory" },
  {
    "POST /repos/{owner}/{repo}/security-advisories/reports",
    "post_repo_security_advisory_report",
  },
  { "GET /repos/{owner}/{repo}/security-advisories/{ghsa_id}", "get_repo_security_advisory" },
  { "PATCH /repos/{owner}/{repo}/security-advisories/{ghsa_id}", "patch_repo_security_advisory" },
  {
    "POST /repos/{owner}/{repo}/security-advisories/{ghsa_id}/cve",
    "post_repo_security_advisory_cve",
  },
  {
    "POST /repos/{owner}/{repo}/security-advisories/{ghsa_id}/forks",
    "post_repo_security_advisory_fork",
  },

  { group = "issues" },
  -- Issues (https://docs.github.com/en/rest/issues)
  { "GET /issues", "get_issues", empty_list },
  { "GET /orgs/{org}/issues", "get_org_issues", empty_list },
  { "GET /user/issues", "get_user_issues", empty_list },
  { "GET /repos/{owner}/{repo}/issues", "get_repo_issues", empty_list },
  { "POST /repos/{owner}/{repo}/issues", "post_repo_issues" },
  { "GET /repos/{owner}/{repo}/issues/comments", "get_repo_issue_comments", empty_list },
  { "GET /repos/{owner}/{repo}/issues/comments/{comment_id}", "get_repo_issue_comment" },
  { "PATCH /repos/{owner}/{repo}/issues/comments/{comment_id}", "patch_repo_issue_comment" },
  { "DELETE /repos/{owner}/{repo}/issues/comments/{comment_id}", "delete_repo_issue_comment" },
  { "PUT /repos/{owner}/{repo}/issues/comments/{comment_id}/pin", "put_repo_issue_comment_pin" },
  {
    "DELETE /repos/{owner}/{repo}/issues/comments/{comment_id}/pin",
    "delete_repo_issue_comment_pin",
  },
  { "GET /repos/{owner}/{repo}/issues/events", "get_repo_issue_events", empty_list },
  { "GET /repos/{owner}/{repo}/issues/events/{event_id}", "get_repo_issue_event" },
  { "GET /repos/{owner}/{repo}/issues/{issue_number}", "get_repo_issue" },
  { "PATCH /repos/{owner}/{repo}/issues/{issue_number}", "patch_repo_issue" },
  { "POST /repos/{owner}/{repo}/issues/{issue_number}/assignees", "post_issue_assignees" },
  { "DELETE /repos/{owner}/{repo}/issues/{issue_number}/assignees", "delete_issue_assignees" },
  { "GET /repos/{owner}/{repo}/issues/{issue_number}/assignees/{assignee}", "get_issue_assignee" },
  { "GET /repos/{owner}/{repo}/issues/{issue_number}/comments", "get_issue_comments", empty_list },
  { "POST /repos/{owner}/{repo}/issues/{issue_number}/comments", "post_issue_comment" },
  {
    "GET /repos/{owner}/{repo}/issues/{issue_number}/dependencies/blocked_by",
    "get_issue_deps_blocked_by",
    empty_list,
  },
  {
    "POST /repos/{owner}/{repo}/issues/{issue_number}/dependencies/blocked_by",
    "post_issue_deps_blocked_by",
  },
  {
    "DELETE /repos/{owner}/{repo}/issues/{issue_number}/dependencies/blocked_by/{issue_id}",
    "delete_issue_dep_blocked_by",
  },
  {
    "GET /repos/{owner}/{repo}/issues/{issue_number}/dependencies/blocking",
    "get_issue_deps_blocking",
    empty_list,
  },
  { "GET /repos/{owner}/{repo}/issues/{issue_number}/events", "get_issue_events", empty_list },
  {
    "GET /repos/{owner}/{repo}/issues/{issue_number}/issue-field-values",
    "get_issue_field_values",
    empty_list,
  },
  { "GET /repos/{owner}/{repo}/issues/{issue_number}/labels", "get_issue_labels", empty_list },
  { "POST /repos/{owner}/{repo}/issues/{issue_number}/labels", "post_issue_labels" },
  { "PUT /repos/{owner}/{repo}/issues/{issue_number}/labels", "put_issue_labels" },
  { "DELETE /repos/{owner}/{repo}/issues/{issue_number}/labels", "delete_issue_labels" },
  { "DELETE /repos/{owner}/{repo}/issues/{issue_number}/labels/{name}", "delete_issue_label" },
  { "PUT /repos/{owner}/{repo}/issues/{issue_number}/lock", "put_issue_lock" },
  { "DELETE /repos/{owner}/{repo}/issues/{issue_number}/lock", "delete_issue_lock" },
  { "GET /repos/{owner}/{repo}/issues/{issue_number}/parent", "get_issue_parent" },
  {
    "GET /repos/{owner}/{repo}/issues/{issue_number}/sub_issues",
    "get_issue_sub_issues",
    empty_list,
  },
  { "POST /repos/{owner}/{repo}/issues/{issue_number}/sub_issues", "post_issue_sub_issues" },
  { "DELETE /repos/{owner}/{repo}/issues/{issue_number}/sub_issue", "delete_issue_sub_issue" },
  {
    "PATCH /repos/{owner}/{repo}/issues/{issue_number}/sub_issues/priority",
    "patch_issue_sub_issues_priority",
  },
  { "GET /repos/{owner}/{repo}/issues/{issue_number}/timeline", "get_issue_timeline", empty_list },

  -- Assignees (https://docs.github.com/en/rest/issues/assignees)
  { "GET /repos/{owner}/{repo}/assignees", "get_repo_assignees", empty_list },
  { "GET /repos/{owner}/{repo}/assignees/{assignee}", "get_repo_assignee" },

  -- Labels (https://docs.github.com/en/rest/issues/labels)
  { "GET /repos/{owner}/{repo}/labels", "get_repo_labels", empty_list },
  { "POST /repos/{owner}/{repo}/labels", "post_repo_labels" },
  { "GET /repos/{owner}/{repo}/labels/{name}", "get_repo_label" },
  { "PATCH /repos/{owner}/{repo}/labels/{name}", "patch_repo_label" },
  { "DELETE /repos/{owner}/{repo}/labels/{name}", "delete_repo_label" },

  -- Milestones (https://docs.github.com/en/rest/issues/milestones)
  { "GET /repos/{owner}/{repo}/milestones", "get_repo_milestones", empty_list },
  { "POST /repos/{owner}/{repo}/milestones", "post_repo_milestones" },
  { "GET /repos/{owner}/{repo}/milestones/{milestone_number}", "get_repo_milestone" },
  { "PATCH /repos/{owner}/{repo}/milestones/{milestone_number}", "patch_repo_milestone" },
  { "DELETE /repos/{owner}/{repo}/milestones/{milestone_number}", "delete_repo_milestone" },
  {
    "GET /repos/{owner}/{repo}/milestones/{milestone_number}/labels",
    "get_repo_milestone_labels",
    empty_list,
  },

  -- Issue field values via repository_id (GitHub-specific)
  {
    "POST /repositories/{repository_id}/issues/{issue_number}/issue-field-values",
    "post_repository_issue_field_values",
  },
  {
    "PUT /repositories/{repository_id}/issues/{issue_number}/issue-field-values",
    "put_repository_issue_field_values",
  },
  {
    "DELETE /repositories/{repository_id}/issues/{issue_number}/issue-field-values/{issue_field_id}",
    "delete_repository_issue_field_value",
  },

  { group = "pulls" },
  -- Pull Requests (https://docs.github.com/en/rest/pulls)
  { "GET /repos/{owner}/{repo}/pulls", "get_repo_pulls", empty_list },
  { "POST /repos/{owner}/{repo}/pulls", "post_repo_pulls" },
  { "GET /repos/{owner}/{repo}/pulls/comments", "get_repo_pull_comments", empty_list },
  { "GET /repos/{owner}/{repo}/pulls/comments/{comment_id}", "get_repo_pull_comment" },
  { "PATCH /repos/{owner}/{repo}/pulls/comments/{comment_id}", "patch_repo_pull_comment" },
  { "DELETE /repos/{owner}/{repo}/pulls/comments/{comment_id}", "delete_repo_pull_comment" },
  { "GET /repos/{owner}/{repo}/pulls/{pull_number}", "get_repo_pull" },
  { "PATCH /repos/{owner}/{repo}/pulls/{pull_number}", "patch_repo_pull" },
  { "GET /repos/{owner}/{repo}/pulls/{pull_number}/codespaces", "get_pull_codespaces", empty_list },
  { "GET /repos/{owner}/{repo}/pulls/{pull_number}/comments", "get_pull_comments", empty_list },
  { "POST /repos/{owner}/{repo}/pulls/{pull_number}/comments", "post_pull_comment" },
  {
    "POST /repos/{owner}/{repo}/pulls/{pull_number}/comments/{comment_id}/replies",
    "post_pull_comment_reply",
  },
  { "GET /repos/{owner}/{repo}/pulls/{pull_number}/commits", "get_pull_commits", empty_list },
  { "GET /repos/{owner}/{repo}/pulls/{pull_number}/files", "get_pull_files", empty_list },
  { "GET /repos/{owner}/{repo}/pulls/{pull_number}/merge", "get_pull_merge" },
  { "PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge", "put_pull_merge" },
  {
    "GET /repos/{owner}/{repo}/pulls/{pull_number}/requested_reviewers",
    "get_pull_requested_reviewers",
    empty_list,
  },
  {
    "POST /repos/{owner}/{repo}/pulls/{pull_number}/requested_reviewers",
    "post_pull_requested_reviewers",
  },
  {
    "DELETE /repos/{owner}/{repo}/pulls/{pull_number}/requested_reviewers",
    "delete_pull_requested_reviewers",
  },
  { "GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews", "get_pull_reviews", empty_list },
  { "POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews", "post_pull_review" },
  { "GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}", "get_pull_review" },
  { "PUT /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}", "put_pull_review" },
  { "DELETE /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}", "delete_pull_review" },
  {
    "GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}/comments",
    "get_pull_review_comments",
    empty_list,
  },
  {
    "PUT /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}/dismissals",
    "put_pull_review_dismissal",
  },
  {
    "POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}/events",
    "post_pull_review_event",
  },
  { "POST /repos/{owner}/{repo}/pulls/{pull_number}/update-branch", "post_pull_update_branch" },
  { "GET /repos/{owner}/{repo}/commits/{commit_sha}/pulls", "get_commit_pulls", empty_list },


  -- Reactions (https://docs.github.com/en/rest/reactions)
  { group = "reactions" },
  {
    "GET /repos/{owner}/{repo}/pulls/comments/{comment_id}/reactions",
    "get_repo_pull_comment_reactions",
    empty_list,
  },
  {
    "POST /repos/{owner}/{repo}/pulls/comments/{comment_id}/reactions",
    "post_repo_pull_comment_reaction",
    reactions_not_implemented,
  },
  {
    "DELETE /repos/{owner}/{repo}/pulls/comments/{comment_id}/reactions/{reaction_id}",
    "delete_repo_pull_comment_reaction",
    reactions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/issues/{issue_number}/reactions",
    "get_issue_reactions",
    empty_list,
  },
  {
    "POST /repos/{owner}/{repo}/issues/{issue_number}/reactions",
    "post_issue_reaction",
    reactions_not_implemented,
  },
  {
    "DELETE /repos/{owner}/{repo}/issues/{issue_number}/reactions/{reaction_id}",
    "delete_issue_reaction",
    reactions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/issues/comments/{comment_id}/reactions",
    "get_repo_issue_comment_reactions",
    empty_list,
  },
  {
    "POST /repos/{owner}/{repo}/issues/comments/{comment_id}/reactions",
    "post_repo_issue_comment_reaction",
    reactions_not_implemented,
  },
  {
    "DELETE /repos/{owner}/{repo}/issues/comments/{comment_id}/reactions/{reaction_id}",
    "delete_repo_issue_comment_reaction",
    reactions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/releases/{release_id}/reactions",
    "get_repo_release_reactions",
    empty_list,
  },
  {
    "POST /repos/{owner}/{repo}/releases/{release_id}/reactions",
    "post_repo_release_reaction",
    reactions_not_implemented,
  },
  {
    "DELETE /repos/{owner}/{repo}/releases/{release_id}/reactions/{reaction_id}",
    "delete_repo_release_reaction",
    reactions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/comments/{comment_id}/reactions",
    "get_repo_comment_reactions",
    empty_list,
  },
  {
    "POST /repos/{owner}/{repo}/comments/{comment_id}/reactions",
    "post_repo_comment_reaction",
    reactions_not_implemented,
  },
  {
    "DELETE /repos/{owner}/{repo}/comments/{comment_id}/reactions/{reaction_id}",
    "delete_repo_comment_reaction",
    reactions_not_implemented,
  },
  { group = "users" },
  -- Users (https://docs.github.com/en/rest/users)
  { "GET /user", "get_user" },
  { "PATCH /user", "patch_user" },
  { "GET /user/{account_id}", "get_user_by_id" },
  { "GET /users", "get_users" },
  { "GET /users/{username}", "get_users_username" },
  { "GET /users/{username}/hovercard", "get_users_hovercard" },

  -- Blocking
  { "GET /user/blocks", "get_user_blocks" },
  { "GET /user/blocks/{username}", "get_user_block" },
  { "PUT /user/blocks/{username}", "put_user_block" },
  { "DELETE /user/blocks/{username}", "delete_user_block" },

  -- Emails
  { "GET /user/emails", "get_user_emails" },
  { "POST /user/emails", "post_user_emails" },
  { "DELETE /user/emails", "delete_user_emails" },
  { "PATCH /user/email/visibility", "patch_user_email_visibility" },
  { "GET /user/public_emails", "get_user_public_emails" },

  -- Followers
  { "GET /user/followers", "get_user_followers" },
  { "GET /user/following", "get_user_following" },
  { "GET /user/following/{username}", "get_user_is_following" },
  { "PUT /user/following/{username}", "put_user_following" },
  { "DELETE /user/following/{username}", "delete_user_following" },
  { "GET /users/{username}/followers", "get_users_followers" },
  { "GET /users/{username}/following", "get_users_following" },
  { "GET /users/{username}/following/{target_user}", "get_users_is_following" },

  -- GPG Keys
  { "GET /user/gpg_keys", "get_user_gpg_keys" },
  { "POST /user/gpg_keys", "post_user_gpg_keys" },
  { "GET /user/gpg_keys/{gpg_key_id}", "get_user_gpg_key" },
  { "DELETE /user/gpg_keys/{gpg_key_id}", "delete_user_gpg_key" },
  { "GET /users/{username}/gpg_keys", "get_users_gpg_keys" },

  -- SSH Keys
  { "GET /user/keys", "get_user_keys" },
  { "POST /user/keys", "post_user_keys" },
  { "GET /user/keys/{key_id}", "get_user_key" },
  { "DELETE /user/keys/{key_id}", "delete_user_key" },
  { "GET /users/{username}/keys", "get_users_keys" },

  -- Social Accounts
  { "GET /user/social_accounts", "get_user_social_accounts" },
  { "POST /user/social_accounts", "post_user_social_accounts" },
  { "DELETE /user/social_accounts", "delete_user_social_accounts" },
  { "GET /users/{username}/social_accounts", "get_users_social_accounts" },

  -- SSH Signing Keys
  { "GET /user/ssh_signing_keys", "get_user_ssh_signing_keys" },
  { "POST /user/ssh_signing_keys", "post_user_ssh_signing_keys" },
  { "GET /user/ssh_signing_keys/{ssh_signing_key_id}", "get_user_ssh_signing_key" },
  { "DELETE /user/ssh_signing_keys/{ssh_signing_key_id}", "delete_user_ssh_signing_key" },
  { "GET /users/{username}/ssh_signing_keys", "get_users_ssh_signing_keys" },

  { group = "search" },
  -- Search (https://docs.github.com/en/rest/search)
  { "GET /search/code", "search_code", search_empty },
  { "GET /search/commits", "search_commits", search_empty },
  { "GET /search/issues", "search_issues", search_empty },
  { "GET /search/labels", "search_labels", search_empty },
  { "GET /search/repositories", "search_repositories", search_empty },
  { "GET /search/topics", "search_topics", search_empty },
  { "GET /search/users", "search_users", search_empty },

  { group = "apps" },
  -- Apps (https://docs.github.com/en/rest/apps)
  { "GET /app", "get_app" },
  { "GET /app/hook/config", "get_app_hook_config" },
  { "PATCH /app/hook/config", "patch_app_hook_config" },
  { "GET /app/hook/deliveries", "get_app_hook_deliveries" },
  { "GET /app/hook/deliveries/{delivery_id}", "get_app_hook_delivery" },
  { "POST /app/hook/deliveries/{delivery_id}/attempts", "post_app_hook_delivery_attempt" },
  { "GET /app/installation-requests", "get_app_installation_requests" },
  { "GET /app/installations", "get_app_installations" },
  { "GET /app/installations/{installation_id}", "get_app_installation" },
  { "DELETE /app/installations/{installation_id}", "delete_app_installation" },
  {
    "POST /app/installations/{installation_id}/access_tokens",
    "post_app_installation_access_tokens",
  },
  { "PUT /app/installations/{installation_id}/suspended", "put_app_installation_suspended" },
  { "DELETE /app/installations/{installation_id}/suspended", "delete_app_installation_suspended" },
  { "GET /apps/{app_slug}", "get_apps_app_slug" },
  { "POST /app-manifests/{code}/conversions", "post_app_manifest_conversions" },
  { "GET /installation/repositories", "get_installation_repositories" },
  { "DELETE /installation/token", "delete_installation_token" },
  { "POST /applications/{client_id}/token", "post_applications_token" },
  { "PATCH /applications/{client_id}/token", "patch_applications_token" },
  { "DELETE /applications/{client_id}/token", "delete_applications_token" },
  { "POST /applications/{client_id}/token/scoped", "post_applications_token_scoped" },
  { "DELETE /applications/{client_id}/grant", "delete_applications_grant" },
  { "GET /orgs/{org}/installation", "get_org_installation" },
  { "GET /orgs/{org}/installations", "get_org_installations" },
  { "GET /repos/{owner}/{repo}/installation", "get_repo_installation" },
  { "GET /user/installations", "get_user_installations" },
  {
    "GET /user/installations/{installation_id}/repositories",
    "get_user_installation_repositories",
  },
  {
    "PUT /user/installations/{installation_id}/repositories/{repository_id}",
    "put_user_installation_repository",
  },
  {
    "DELETE /user/installations/{installation_id}/repositories/{repository_id}",
    "delete_user_installation_repository",
  },
  { "GET /users/{username}/installation", "get_users_installation" },

  { group = "checks" },
  -- Checks (https://docs.github.com/en/rest/checks)
  {
    "POST /repos/{owner}/{repo}/check-runs",
    "post_check_runs",
    function(_owner, _repo_name)
      local req = DecodeJson(GetBody() or "{}")
      respond_json(201, {
        id = 0,
        node_id = "",
        head_sha = req.head_sha or "",
        name = req.name or "",
        status = req.status or "queued",
        conclusion = req.conclusion,
        started_at = nil,
        completed_at = nil,
        output = {
          title = (req.output and req.output.title) or "",
          summary = (req.output and req.output.summary) or "",
          text = "",
          annotations_count = 0,
          annotations_url = "",
        },
        url = "",
        html_url = "",
        details_url = req.details_url or "",
      })
    end,
  },
  {
    "GET /repos/{owner}/{repo}/check-runs/{check_run_id}",
    "get_check_run",
    function(_owner, _repo_name, check_run_id)
      respond_json(200, {
        id = tonumber(check_run_id) or 0,
        node_id = "",
        head_sha = "",
        name = "",
        status = "completed",
        conclusion = "success",
        started_at = nil,
        completed_at = nil,
        output = {
          title = "",
          summary = "",
          text = "",
          annotations_count = 0,
          annotations_url = "",
        },
        url = "",
        html_url = "",
        details_url = "",
      })
    end,
  },
  {
    "PATCH /repos/{owner}/{repo}/check-runs/{check_run_id}",
    "patch_check_run",
    function(_owner, _repo_name, check_run_id)
      respond_json(200, {
        id = tonumber(check_run_id) or 0,
        node_id = "",
        head_sha = "",
        name = "",
        status = "completed",
        conclusion = "success",
        started_at = nil,
        completed_at = nil,
        output = {
          title = "",
          summary = "",
          text = "",
          annotations_count = 0,
          annotations_url = "",
        },
        url = "",
        html_url = "",
        details_url = "",
      })
    end,
  },
  {
    "GET /repos/{owner}/{repo}/check-runs/{check_run_id}/annotations",
    "get_check_run_annotations",
    function(_owner, _repo_name, _check_run_id)
      set_preamble()
      Write("[]")
    end,
  },
  {
    "POST /repos/{owner}/{repo}/check-runs/{check_run_id}/rerequest",
    "post_check_run_rerequest",
    function(_owner, _repo_name, _check_run_id)
      respond_json(201, {})
    end,
  },
  {
    "POST /repos/{owner}/{repo}/check-suites",
    "post_check_suites",
    function(owner, repo_name)
      local req = DecodeJson(GetBody() or "{}")
      respond_json(201, {
        id = 0,
        node_id = "",
        head_sha = req.head_sha or "",
        status = "completed",
        conclusion = "success",
        app = { id = 0, slug = "", name = "" },
        repository = { full_name = owner .. "/" .. repo_name },
      })
    end,
  },
  {
    "PATCH /repos/{owner}/{repo}/check-suites/preferences",
    "patch_check_suites_preferences",
    function(_owner, _repo_name) -- luacheck: ignore 212
      local req = DecodeJson(GetBody() or "{}") or {}
      respond_json(200, {
        preferences = req.auto_trigger_checks or {},
      })
    end,
  },
  {
    "GET /repos/{owner}/{repo}/check-suites/{check_suite_id}",
    "get_check_suite",
    function(owner, repo_name, check_suite_id)
      respond_json(200, {
        id = tonumber(check_suite_id) or 0,
        node_id = "",
        head_sha = "",
        status = "completed",
        conclusion = "success",
        app = { id = 0, slug = "", name = "" },
        repository = { full_name = owner .. "/" .. repo_name },
      })
    end,
  },
  {
    "GET /repos/{owner}/{repo}/check-suites/{check_suite_id}/check-runs",
    "get_check_suite_check_runs",
    function(_owner, _repo_name, _check_suite_id)
      respond_json(200, { total_count = 0, check_runs = {} })
    end,
  },
  {
    "POST /repos/{owner}/{repo}/check-suites/{check_suite_id}/rerequest",
    "post_check_suite_rerequest",
    function(_owner, _repo_name, _check_suite_id)
      respond_json(201, {})
    end,
  },
  {
    "GET /repos/{owner}/{repo}/commits/{ref}/check-runs",
    "get_commit_check_runs",
    function(_owner, _repo_name, _ref)
      respond_json(200, { total_count = 0, check_runs = {} })
    end,
  },
  {
    "GET /repos/{owner}/{repo}/commits/{ref}/check-suites",
    "get_commit_check_suites",
    function(_owner, _repo_name, _ref)
      respond_json(200, { total_count = 0, check_suites = {} })
    end,
  },

  { group = "code-scanning" },
  -- Code Scanning (https://docs.github.com/en/rest/code-scanning)
  {
    "GET /orgs/{org}/code-scanning/alerts",
    "list_org_code_scanning_alerts",
    code_scanning_list_empty,
  },
  {
    "GET /repos/{owner}/{repo}/code-scanning/alerts",
    "list_repo_code_scanning_alerts",
    code_scanning_list_empty,
  },
  {
    "GET /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}",
    "get_code_scanning_alert",
    code_scanning_not_implemented,
  },
  {
    "PATCH /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}",
    "update_code_scanning_alert",
    code_scanning_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/autofix",
    "get_code_scanning_autofix",
    code_scanning_not_implemented,
  },
  {
    "POST /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/autofix",
    "create_code_scanning_autofix",
    code_scanning_not_implemented,
  },
  {
    "POST /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/autofix/commits",
    "commit_code_scanning_autofix",
    code_scanning_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/instances",
    "list_code_scanning_alert_instances",
    code_scanning_list_empty,
  },
  {
    "GET /repos/{owner}/{repo}/code-scanning/analyses",
    "list_code_scanning_analyses",
    code_scanning_list_empty,
  },
  {
    "GET /repos/{owner}/{repo}/code-scanning/analyses/{analysis_id}",
    "get_code_scanning_analysis",
    code_scanning_not_implemented,
  },
  {
    "DELETE /repos/{owner}/{repo}/code-scanning/analyses/{analysis_id}",
    "delete_code_scanning_analysis",
    code_scanning_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/code-scanning/codeql/databases",
    "list_codeql_databases",
    code_scanning_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/code-scanning/codeql/databases/{language}",
    "get_codeql_database",
    code_scanning_not_implemented,
  },
  {
    "DELETE /repos/{owner}/{repo}/code-scanning/codeql/databases/{language}",
    "delete_codeql_database",
    code_scanning_not_implemented,
  },
  {
    "POST /repos/{owner}/{repo}/code-scanning/codeql/variant-analyses",
    "create_codeql_variant_analysis",
    code_scanning_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/code-scanning/codeql/variant-analyses/{codeql_variant_analysis_id}",
    "get_codeql_variant_analysis",
    code_scanning_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/code-scanning/codeql/variant-analyses/{codeql_variant_analysis_id}/repos/{repo_owner}/{repo_name}",
    "get_codeql_variant_analysis_repo_task",
    code_scanning_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/code-scanning/default-setup",
    "get_code_scanning_default_setup",
    code_scanning_not_implemented,
  },
  {
    "PATCH /repos/{owner}/{repo}/code-scanning/default-setup",
    "update_code_scanning_default_setup",
    code_scanning_not_implemented,
  },
  {
    "POST /repos/{owner}/{repo}/code-scanning/sarifs",
    "upload_code_scanning_sarif",
    code_scanning_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/code-scanning/sarifs/{sarif_id}",
    "get_code_scanning_sarif",
    code_scanning_not_implemented,
  },

  { group = "secret-scanning" },
  -- Secret Scanning (https://docs.github.com/en/rest/secret-scanning)
  {
    "GET /orgs/{org}/secret-scanning/alerts",
    "list_org_secret_scanning_alerts",
    secret_scanning_list_empty,
  },
  {
    "GET /orgs/{org}/secret-scanning/pattern-configurations",
    "get_org_secret_scanning_pattern_configs",
    secret_scanning_not_implemented,
  },
  {
    "PATCH /orgs/{org}/secret-scanning/pattern-configurations",
    "update_org_secret_scanning_pattern_configs",
    secret_scanning_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/secret-scanning/alerts",
    "list_repo_secret_scanning_alerts",
    secret_scanning_list_empty,
  },
  {
    "GET /repos/{owner}/{repo}/secret-scanning/alerts/{alert_number}",
    "get_secret_scanning_alert",
    secret_scanning_not_implemented,
  },
  {
    "PATCH /repos/{owner}/{repo}/secret-scanning/alerts/{alert_number}",
    "update_secret_scanning_alert",
    secret_scanning_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/secret-scanning/alerts/{alert_number}/locations",
    "list_secret_scanning_alert_locations",
    secret_scanning_list_empty,
  },
  {
    "POST /repos/{owner}/{repo}/secret-scanning/push-protection-bypasses",
    "create_secret_scanning_push_protection_bypass",
    secret_scanning_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/secret-scanning/scan-history",
    "get_secret_scanning_scan_history",
    secret_scanning_not_implemented,
  },

  { group = "dependabot" },
  -- Dependabot (https://docs.github.com/en/rest/dependabot)
  {
    "GET /enterprises/{enterprise}/dependabot/alerts",
    "list_enterprise_dependabot_alerts",
    dependabot_list_empty,
  },
  { "GET /orgs/{org}/dependabot/alerts", "list_org_dependabot_alerts", dependabot_list_empty },
  {
    "GET /orgs/{org}/dependabot/secrets",
    "list_org_dependabot_secrets",
    make_empty_collection("secrets"),
  },
  {
    "GET /orgs/{org}/dependabot/secrets/public-key",
    "get_org_dependabot_public_key",
    dependabot_not_implemented,
  },
  {
    "GET /orgs/{org}/dependabot/secrets/{secret_name}",
    "get_org_dependabot_secret",
    dependabot_not_implemented,
  },
  {
    "PUT /orgs/{org}/dependabot/secrets/{secret_name}",
    "put_org_dependabot_secret",
    dependabot_not_implemented,
  },
  {
    "DELETE /orgs/{org}/dependabot/secrets/{secret_name}",
    "delete_org_dependabot_secret",
    dependabot_not_implemented,
  },
  {
    "GET /orgs/{org}/dependabot/secrets/{secret_name}/repositories",
    "list_org_dependabot_secret_repos",
    make_empty_collection("repositories"),
  },
  {
    "PUT /orgs/{org}/dependabot/secrets/{secret_name}/repositories",
    "put_org_dependabot_secret_repos",
    dependabot_not_implemented,
  },
  {
    "PUT /orgs/{org}/dependabot/secrets/{secret_name}/repositories/{repository_id}",
    "add_org_dependabot_secret_repo",
    dependabot_not_implemented,
  },
  {
    "DELETE /orgs/{org}/dependabot/secrets/{secret_name}/repositories/{repository_id}",
    "remove_org_dependabot_secret_repo",
    dependabot_not_implemented,
  },
  {
    "GET /organizations/{org}/dependabot/repository-access",
    "get_org_dependabot_repo_access",
    dependabot_not_implemented,
  },
  {
    "PATCH /organizations/{org}/dependabot/repository-access",
    "update_org_dependabot_repo_access",
    dependabot_not_implemented,
  },
  {
    "PUT /organizations/{org}/dependabot/repository-access/default-level",
    "set_org_dependabot_repo_access_default_level",
    dependabot_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/dependabot/alerts",
    "list_repo_dependabot_alerts",
    dependabot_list_empty,
  },
  {
    "GET /repos/{owner}/{repo}/dependabot/alerts/{alert_number}",
    "get_repo_dependabot_alert",
    dependabot_not_implemented,
  },
  {
    "PATCH /repos/{owner}/{repo}/dependabot/alerts/{alert_number}",
    "update_repo_dependabot_alert",
    dependabot_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/dependabot/secrets",
    "list_repo_dependabot_secrets",
    make_empty_collection("secrets"),
  },
  {
    "GET /repos/{owner}/{repo}/dependabot/secrets/public-key",
    "get_repo_dependabot_public_key",
    dependabot_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/dependabot/secrets/{secret_name}",
    "get_repo_dependabot_secret",
    dependabot_not_implemented,
  },
  {
    "PUT /repos/{owner}/{repo}/dependabot/secrets/{secret_name}",
    "put_repo_dependabot_secret",
    dependabot_not_implemented,
  },
  {
    "DELETE /repos/{owner}/{repo}/dependabot/secrets/{secret_name}",
    "delete_repo_dependabot_secret",
    dependabot_not_implemented,
  },

  { group = "dependency-graph" },
  -- Dependency Graph (https://docs.github.com/en/rest/dependency-graph)
  {
    "GET /repos/{owner}/{repo}/dependency-graph/compare/{basehead}",
    "get_repo_dependency_graph_compare",
    dependency_graph_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/dependency-graph/sbom",
    "get_repo_dependency_graph_sbom",
    dependency_graph_not_implemented,
  },
  {
    "POST /repos/{owner}/{repo}/dependency-graph/snapshots",
    "post_repo_dependency_graph_snapshots",
    dependency_graph_not_implemented,
  },

  { group = "projects" },
  -- Projects (https://docs.github.com/en/rest/projects)
  { "GET /orgs/{org}/projectsV2", "projects_list_for_org", projects_list_empty },
  {
    "GET /orgs/{org}/projectsV2/{project_number}",
    "projects_get_for_org",
    projects_not_implemented,
  },
  {
    "POST /orgs/{org}/projectsV2/{project_number}/drafts",
    "projects_create_draft_item_for_org",
    projects_not_implemented,
  },
  {
    "GET /orgs/{org}/projectsV2/{project_number}/fields",
    "projects_list_fields_for_org",
    projects_list_empty,
  },
  {
    "POST /orgs/{org}/projectsV2/{project_number}/fields",
    "projects_add_field_for_org",
    projects_not_implemented,
  },
  {
    "GET /orgs/{org}/projectsV2/{project_number}/fields/{field_id}",
    "projects_get_field_for_org",
    projects_not_implemented,
  },
  {
    "GET /orgs/{org}/projectsV2/{project_number}/items",
    "projects_list_items_for_org",
    projects_list_empty,
  },
  {
    "POST /orgs/{org}/projectsV2/{project_number}/items",
    "projects_add_item_for_org",
    projects_not_implemented,
  },
  {
    "GET /orgs/{org}/projectsV2/{project_number}/items/{item_id}",
    "projects_get_item_for_org",
    projects_not_implemented,
  },
  {
    "PATCH /orgs/{org}/projectsV2/{project_number}/items/{item_id}",
    "projects_update_item_for_org",
    projects_not_implemented,
  },
  {
    "DELETE /orgs/{org}/projectsV2/{project_number}/items/{item_id}",
    "projects_delete_item_for_org",
    projects_not_implemented,
  },
  {
    "POST /orgs/{org}/projectsV2/{project_number}/views",
    "projects_create_view_for_org",
    projects_not_implemented,
  },
  {
    "GET /orgs/{org}/projectsV2/{project_number}/views/{view_number}/items",
    "projects_list_view_items_for_org",
    projects_list_empty,
  },
  {
    "POST /user/{user_id}/projectsV2/{project_number}/drafts",
    "projects_create_draft_item_for_user",
    projects_not_implemented,
  },
  {
    "POST /users/{user_id}/projectsV2/{project_number}/views",
    "projects_create_view_for_user",
    projects_not_implemented,
  },
  { "GET /users/{username}/projectsV2", "projects_list_for_user", projects_list_empty },
  {
    "GET /users/{username}/projectsV2/{project_number}",
    "projects_get_for_user",
    projects_not_implemented,
  },
  {
    "GET /users/{username}/projectsV2/{project_number}/fields",
    "projects_list_fields_for_user",
    projects_list_empty,
  },
  {
    "POST /users/{username}/projectsV2/{project_number}/fields",
    "projects_add_field_for_user",
    projects_not_implemented,
  },
  {
    "GET /users/{username}/projectsV2/{project_number}/fields/{field_id}",
    "projects_get_field_for_user",
    projects_not_implemented,
  },
  {
    "GET /users/{username}/projectsV2/{project_number}/items",
    "projects_list_items_for_user",
    projects_list_empty,
  },
  {
    "POST /users/{username}/projectsV2/{project_number}/items",
    "projects_add_item_for_user",
    projects_not_implemented,
  },
  {
    "GET /users/{username}/projectsV2/{project_number}/items/{item_id}",
    "projects_get_item_for_user",
    projects_not_implemented,
  },
  {
    "PATCH /users/{username}/projectsV2/{project_number}/items/{item_id}",
    "projects_update_item_for_user",
    projects_not_implemented,
  },
  {
    "DELETE /users/{username}/projectsV2/{project_number}/items/{item_id}",
    "projects_delete_item_for_user",
    projects_not_implemented,
  },
  {
    "GET /users/{username}/projectsV2/{project_number}/views/{view_number}/items",
    "projects_list_view_items_for_user",
    projects_list_empty,
  },

  { group = "packages" },
  -- Packages (https://docs.github.com/en/rest/packages)
  { "GET /orgs/{org}/packages", "get_org_packages", empty_list },
  { "GET /orgs/{org}/packages/{package_type}/{package_name}", "get_org_package" },
  { "DELETE /orgs/{org}/packages/{package_type}/{package_name}", "delete_org_package" },
  { "POST /orgs/{org}/packages/{package_type}/{package_name}/restore", "restore_org_package" },
  {
    "GET /orgs/{org}/packages/{package_type}/{package_name}/versions",
    "get_org_package_versions",
    empty_list,
  },
  {
    "GET /orgs/{org}/packages/{package_type}/{package_name}/versions/{package_version_id}",
    "get_org_package_version",
  },
  {
    "DELETE /orgs/{org}/packages/{package_type}/{package_name}/versions/{package_version_id}",
    "delete_org_package_version",
  },
  {
    "POST /orgs/{org}/packages/{package_type}/{package_name}/versions/{package_version_id}/restore",
    "restore_org_package_version",
  },
  { "GET /user/packages", "get_user_packages", empty_list },
  { "GET /user/packages/{package_type}/{package_name}", "get_user_package" },
  { "DELETE /user/packages/{package_type}/{package_name}", "delete_user_package" },
  { "POST /user/packages/{package_type}/{package_name}/restore", "restore_user_package" },
  {
    "GET /user/packages/{package_type}/{package_name}/versions",
    "get_user_package_versions",
    empty_list,
  },
  {
    "GET /user/packages/{package_type}/{package_name}/versions/{package_version_id}",
    "get_user_package_version",
  },
  {
    "DELETE /user/packages/{package_type}/{package_name}/versions/{package_version_id}",
    "delete_user_package_version",
  },
  {
    "POST /user/packages/{package_type}/{package_name}/versions/{package_version_id}/restore",
    "restore_user_package_version",
  },
  { "GET /users/{username}/packages", "get_users_packages", empty_list },
  { "GET /users/{username}/packages/{package_type}/{package_name}", "get_users_package" },
  { "DELETE /users/{username}/packages/{package_type}/{package_name}", "delete_users_package" },
  {
    "POST /users/{username}/packages/{package_type}/{package_name}/restore",
    "restore_users_package",
  },
  {
    "GET /users/{username}/packages/{package_type}/{package_name}/versions",
    "get_users_package_versions",
    empty_list,
  },
  {
    "GET /users/{username}/packages/{package_type}/{package_name}/versions/{package_version_id}",
    "get_users_package_version",
  },
  {
    "DELETE /users/{username}/packages/{package_type}/{package_name}/versions/{package_version_id}",
    "delete_users_package_version",
  },
  {
    "POST /users/{username}/packages/{package_type}/{package_name}/versions/{package_version_id}/restore",
    "restore_users_package_version",
  },

  { group = "interactions" },
  -- Interactions (https://docs.github.com/en/rest/interactions)
  { "GET /orgs/{org}/interaction-limits", "get_org_interaction_limits", interaction_limits_empty },
  { "PUT /orgs/{org}/interaction-limits", "put_org_interaction_limits", interaction_limits_put },
  {
    "DELETE /orgs/{org}/interaction-limits",
    "delete_org_interaction_limits",
    interaction_limits_delete,
  },
  {
    "GET /repos/{owner}/{repo}/interaction-limits",
    "get_repo_interaction_limits",
    interaction_limits_empty,
  },
  {
    "PUT /repos/{owner}/{repo}/interaction-limits",
    "put_repo_interaction_limits",
    interaction_limits_put,
  },
  {
    "DELETE /repos/{owner}/{repo}/interaction-limits",
    "delete_repo_interaction_limits",
    interaction_limits_delete,
  },
  { "GET /user/interaction-limits", "get_user_interaction_limits", interaction_limits_empty },
  { "PUT /user/interaction-limits", "put_user_interaction_limits", interaction_limits_put },
  {
    "DELETE /user/interaction-limits",
    "delete_user_interaction_limits",
    interaction_limits_delete,
  },

  { group = "migrations" },
  -- Migrations (https://docs.github.com/en/rest/migrations)
  -- Organization migrations
  { "GET /orgs/{org}/migrations", "get_org_migrations", empty_list },
  { "POST /orgs/{org}/migrations", "post_org_migrations", migrations_not_supported },
  { "GET /orgs/{org}/migrations/{migration_id}", "get_org_migration", migration_not_found },
  {
    "GET /orgs/{org}/migrations/{migration_id}/archive",
    "get_org_migration_archive",
    migration_not_found,
  },
  {
    "DELETE /orgs/{org}/migrations/{migration_id}/archive",
    "delete_org_migration_archive",
    migration_not_found,
  },
  {
    "DELETE /orgs/{org}/migrations/{migration_id}/repos/{repo_name}/lock",
    "delete_org_migration_repo_lock",
    migration_not_found,
  },
  {
    "GET /orgs/{org}/migrations/{migration_id}/repositories",
    "get_org_migration_repos",
    empty_list,
  },

  -- User migrations
  { "GET /user/migrations", "get_user_migrations", empty_list },
  { "POST /user/migrations", "post_user_migrations", migrations_not_supported },
  { "GET /user/migrations/{migration_id}", "get_user_migration", migration_not_found },
  {
    "GET /user/migrations/{migration_id}/archive",
    "get_user_migration_archive",
    migration_not_found,
  },
  {
    "DELETE /user/migrations/{migration_id}/archive",
    "delete_user_migration_archive",
    migration_not_found,
  },
  {
    "DELETE /user/migrations/{migration_id}/repos/{repo_name}/lock",
    "delete_user_migration_repo_lock",
    migration_not_found,
  },
  { "GET /user/migrations/{migration_id}/repositories", "get_user_migration_repos", empty_list },

  { group = "pages" },
  -- Pages (https://docs.github.com/en/rest/pages)
  { "GET /repos/{owner}/{repo}/pages", "get_repo_pages", pages_not_implemented },
  { "POST /repos/{owner}/{repo}/pages", "post_repo_pages", pages_not_implemented },
  { "PUT /repos/{owner}/{repo}/pages", "put_repo_pages", pages_not_implemented },
  { "DELETE /repos/{owner}/{repo}/pages", "delete_repo_pages", pages_not_implemented },
  { "GET /repos/{owner}/{repo}/pages/builds", "get_repo_pages_builds", empty_list },
  { "POST /repos/{owner}/{repo}/pages/builds", "post_repo_pages_builds", pages_not_implemented },
  {
    "GET /repos/{owner}/{repo}/pages/builds/latest",
    "get_repo_pages_build_latest",
    pages_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/pages/builds/{build_id}",
    "get_repo_pages_build",
    pages_not_implemented,
  },
  {
    "POST /repos/{owner}/{repo}/pages/deployments",
    "post_repo_pages_deployments",
    pages_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/pages/deployments/{pages_deployment_id}",
    "get_repo_pages_deployment",
    pages_not_implemented,
  },
  {
    "POST /repos/{owner}/{repo}/pages/deployments/{pages_deployment_id}/cancel",
    "post_repo_pages_deployment_cancel",
    pages_not_implemented,
  },
  { "GET /repos/{owner}/{repo}/pages/health", "get_repo_pages_health", pages_not_implemented },

  -- Source imports (deprecated May 2023 — returns 410 Gone)
  { "GET /repos/{owner}/{repo}/import", "get_repo_import", source_import_gone },
  { "PUT /repos/{owner}/{repo}/import", "put_repo_import", source_import_gone },
  { "PATCH /repos/{owner}/{repo}/import", "patch_repo_import", source_import_gone },
  { "DELETE /repos/{owner}/{repo}/import", "delete_repo_import", source_import_gone },
  { "GET /repos/{owner}/{repo}/import/authors", "get_repo_import_authors", source_import_gone },
  {
    "PATCH /repos/{owner}/{repo}/import/authors/{author_id}",
    "patch_repo_import_author",
    source_import_gone,
  },
  {
    "GET /repos/{owner}/{repo}/import/large_files",
    "get_repo_import_large_files",
    source_import_gone,
  },
  { "PATCH /repos/{owner}/{repo}/import/lfs", "patch_repo_import_lfs", source_import_gone },

  { group = "markdown" },
  -- Markdown (https://docs.github.com/en/rest/markdown)
  { "POST /markdown", "render_markdown", markdown_not_implemented },
  { "POST /markdown/raw", "render_markdown_raw", markdown_not_implemented },

  { group = "actions" },
  -- Actions (https://docs.github.com/en/rest/actions)
  -- Enterprise-level cache limits
  {
    "GET /enterprises/{enterprise}/actions/cache/retention-limit",
    "get_enterprise_actions_cache_retention_limit",
    actions_not_implemented,
  },
  {
    "PUT /enterprises/{enterprise}/actions/cache/retention-limit",
    "put_enterprise_actions_cache_retention_limit",
    actions_not_implemented,
  },
  {
    "GET /enterprises/{enterprise}/actions/cache/storage-limit",
    "get_enterprise_actions_cache_storage_limit",
    actions_not_implemented,
  },
  {
    "PUT /enterprises/{enterprise}/actions/cache/storage-limit",
    "put_enterprise_actions_cache_storage_limit",
    actions_not_implemented,
  },

  -- Enterprise-level OIDC
  {
    "GET /enterprises/{enterprise}/actions/oidc/customization/properties/repo",
    "get_enterprise_actions_oidc_custom_props",
    empty_list,
  },
  {
    "POST /enterprises/{enterprise}/actions/oidc/customization/properties/repo",
    "post_enterprise_actions_oidc_custom_prop",
    actions_not_implemented,
  },
  {
    "DELETE /enterprises/{enterprise}/actions/oidc/customization/properties/repo/{custom_property_name}",
    "delete_enterprise_actions_oidc_custom_prop",
    actions_not_implemented,
  },

  -- Organization-level cache limits (via /organizations/ alias path)
  {
    "GET /organizations/{org}/actions/cache/retention-limit",
    "get_org_actions_cache_retention_limit_v2",
    actions_not_implemented,
  },
  {
    "PUT /organizations/{org}/actions/cache/retention-limit",
    "put_org_actions_cache_retention_limit_v2",
    actions_not_implemented,
  },
  {
    "GET /organizations/{org}/actions/cache/storage-limit",
    "get_org_actions_cache_storage_limit_v2",
    actions_not_implemented,
  },
  {
    "PUT /organizations/{org}/actions/cache/storage-limit",
    "put_org_actions_cache_storage_limit_v2",
    actions_not_implemented,
  },

  -- Organization cache
  { "GET /orgs/{org}/actions/cache/usage", "get_org_actions_cache_usage", actions_not_implemented },
  {
    "GET /orgs/{org}/actions/cache/usage-by-repository",
    "get_org_actions_cache_usage_by_repo",
    actions_not_implemented,
  },

  -- Organization hosted runners
  {
    "GET /orgs/{org}/actions/hosted-runners",
    "get_org_actions_hosted_runners",
    make_empty_collection("runners"),
  },
  {
    "POST /orgs/{org}/actions/hosted-runners",
    "post_org_actions_hosted_runner",
    actions_not_implemented,
  },
  {
    "GET /orgs/{org}/actions/hosted-runners/images/custom",
    "get_org_actions_hosted_runner_custom_images",
    empty_list,
  },
  {
    "GET /orgs/{org}/actions/hosted-runners/images/custom/{image_definition_id}",
    "get_org_actions_hosted_runner_custom_image",
    actions_not_implemented,
  },
  {
    "DELETE /orgs/{org}/actions/hosted-runners/images/custom/{image_definition_id}",
    "delete_org_actions_hosted_runner_custom_image",
    actions_not_implemented,
  },
  {
    "GET /orgs/{org}/actions/hosted-runners/images/custom/{image_definition_id}/versions",
    "get_org_actions_hosted_runner_custom_image_versions",
    empty_list,
  },
  {
    "GET /orgs/{org}/actions/hosted-runners/images/custom/{image_definition_id}/versions/{version}",
    "get_org_actions_hosted_runner_custom_image_version",
    actions_not_implemented,
  },
  {
    "DELETE /orgs/{org}/actions/hosted-runners/images/custom/{image_definition_id}/versions/{version}",
    "delete_org_actions_hosted_runner_custom_image_version",
    actions_not_implemented,
  },
  {
    "GET /orgs/{org}/actions/hosted-runners/images/github-owned",
    "get_org_actions_hosted_runner_github_images",
    empty_list,
  },
  {
    "GET /orgs/{org}/actions/hosted-runners/images/partner",
    "get_org_actions_hosted_runner_partner_images",
    empty_list,
  },
  {
    "GET /orgs/{org}/actions/hosted-runners/limits",
    "get_org_actions_hosted_runner_limits",
    actions_not_implemented,
  },
  {
    "GET /orgs/{org}/actions/hosted-runners/machine-sizes",
    "get_org_actions_hosted_runner_machine_sizes",
    empty_list,
  },
  {
    "GET /orgs/{org}/actions/hosted-runners/platforms",
    "get_org_actions_hosted_runner_platforms",
    empty_list,
  },
  {
    "GET /orgs/{org}/actions/hosted-runners/{hosted_runner_id}",
    "get_org_actions_hosted_runner",
    actions_not_implemented,
  },
  {
    "PATCH /orgs/{org}/actions/hosted-runners/{hosted_runner_id}",
    "patch_org_actions_hosted_runner",
    actions_not_implemented,
  },
  {
    "DELETE /orgs/{org}/actions/hosted-runners/{hosted_runner_id}",
    "delete_org_actions_hosted_runner",
    actions_not_implemented,
  },

  -- Organization OIDC
  {
    "GET /orgs/{org}/actions/oidc/customization/properties/repo",
    "get_org_actions_oidc_custom_props",
    empty_list,
  },
  {
    "POST /orgs/{org}/actions/oidc/customization/properties/repo",
    "post_org_actions_oidc_custom_prop",
    actions_not_implemented,
  },
  {
    "DELETE /orgs/{org}/actions/oidc/customization/properties/repo/{custom_property_name}",
    "delete_org_actions_oidc_custom_prop",
    actions_not_implemented,
  },
  {
    "GET /orgs/{org}/actions/oidc/customization/sub",
    "get_org_actions_oidc_sub",
    actions_not_implemented,
  },
  {
    "PUT /orgs/{org}/actions/oidc/customization/sub",
    "put_org_actions_oidc_sub",
    actions_not_implemented,
  },

  -- Organization permissions
  { "GET /orgs/{org}/actions/permissions", "get_org_actions_permissions", actions_not_implemented },
  { "PUT /orgs/{org}/actions/permissions", "put_org_actions_permissions", actions_not_implemented },
  {
    "GET /orgs/{org}/actions/permissions/artifact-and-log-retention",
    "get_org_actions_artifact_log_retention",
    actions_not_implemented,
  },
  {
    "PUT /orgs/{org}/actions/permissions/artifact-and-log-retention",
    "put_org_actions_artifact_log_retention",
    actions_not_implemented,
  },
  {
    "GET /orgs/{org}/actions/permissions/fork-pr-contributor-approval",
    "get_org_actions_fork_pr_approval",
    actions_not_implemented,
  },
  {
    "PUT /orgs/{org}/actions/permissions/fork-pr-contributor-approval",
    "put_org_actions_fork_pr_approval",
    actions_not_implemented,
  },
  {
    "GET /orgs/{org}/actions/permissions/fork-pr-workflows-private-repos",
    "get_org_actions_fork_pr_private_repos",
    actions_not_implemented,
  },
  {
    "PUT /orgs/{org}/actions/permissions/fork-pr-workflows-private-repos",
    "put_org_actions_fork_pr_private_repos",
    actions_not_implemented,
  },
  { "GET /orgs/{org}/actions/permissions/repositories", "get_org_actions_perm_repos", empty_list },
  {
    "PUT /orgs/{org}/actions/permissions/repositories",
    "put_org_actions_perm_repos",
    actions_not_implemented,
  },
  {
    "PUT /orgs/{org}/actions/permissions/repositories/{repository_id}",
    "put_org_actions_perm_repo",
    actions_not_implemented,
  },
  {
    "DELETE /orgs/{org}/actions/permissions/repositories/{repository_id}",
    "delete_org_actions_perm_repo",
    actions_not_implemented,
  },
  {
    "GET /orgs/{org}/actions/permissions/selected-actions",
    "get_org_actions_selected_actions",
    actions_not_implemented,
  },
  {
    "PUT /orgs/{org}/actions/permissions/selected-actions",
    "put_org_actions_selected_actions",
    actions_not_implemented,
  },
  {
    "GET /orgs/{org}/actions/permissions/self-hosted-runners",
    "get_org_actions_self_hosted_runners_perm",
    actions_not_implemented,
  },
  {
    "PUT /orgs/{org}/actions/permissions/self-hosted-runners",
    "put_org_actions_self_hosted_runners_perm",
    actions_not_implemented,
  },
  {
    "GET /orgs/{org}/actions/permissions/self-hosted-runners/repositories",
    "get_org_actions_self_hosted_runner_repos",
    empty_list,
  },
  {
    "PUT /orgs/{org}/actions/permissions/self-hosted-runners/repositories",
    "put_org_actions_self_hosted_runner_repos",
    actions_not_implemented,
  },
  {
    "PUT /orgs/{org}/actions/permissions/self-hosted-runners/repositories/{repository_id}",
    "put_org_actions_self_hosted_runner_repo",
    actions_not_implemented,
  },
  {
    "DELETE /orgs/{org}/actions/permissions/self-hosted-runners/repositories/{repository_id}",
    "delete_org_actions_self_hosted_runner_repo",
    actions_not_implemented,
  },
  {
    "GET /orgs/{org}/actions/permissions/workflow",
    "get_org_actions_default_workflow_perms",
    actions_not_implemented,
  },
  {
    "PUT /orgs/{org}/actions/permissions/workflow",
    "put_org_actions_default_workflow_perms",
    actions_not_implemented,
  },

  -- Organization runner groups
  {
    "GET /orgs/{org}/actions/runner-groups",
    "get_org_actions_runner_groups",
    make_empty_collection("runner_groups"),
  },
  {
    "POST /orgs/{org}/actions/runner-groups",
    "post_org_actions_runner_group",
    actions_not_implemented,
  },
  {
    "GET /orgs/{org}/actions/runner-groups/{runner_group_id}",
    "get_org_actions_runner_group",
    actions_not_implemented,
  },
  {
    "PATCH /orgs/{org}/actions/runner-groups/{runner_group_id}",
    "patch_org_actions_runner_group",
    actions_not_implemented,
  },
  {
    "DELETE /orgs/{org}/actions/runner-groups/{runner_group_id}",
    "delete_org_actions_runner_group",
    actions_not_implemented,
  },
  {
    "GET /orgs/{org}/actions/runner-groups/{runner_group_id}/hosted-runners",
    "get_org_actions_runner_group_hosted_runners",
    make_empty_collection("runners"),
  },
  {
    "GET /orgs/{org}/actions/runner-groups/{runner_group_id}/repositories",
    "get_org_actions_runner_group_repos",
    empty_list,
  },
  {
    "PUT /orgs/{org}/actions/runner-groups/{runner_group_id}/repositories",
    "put_org_actions_runner_group_repos",
    actions_not_implemented,
  },
  {
    "PUT /orgs/{org}/actions/runner-groups/{runner_group_id}/repositories/{repository_id}",
    "put_org_actions_runner_group_repo",
    actions_not_implemented,
  },
  {
    "DELETE /orgs/{org}/actions/runner-groups/{runner_group_id}/repositories/{repository_id}",
    "delete_org_actions_runner_group_repo",
    actions_not_implemented,
  },
  {
    "GET /orgs/{org}/actions/runner-groups/{runner_group_id}/runners",
    "get_org_actions_runner_group_runners",
    make_empty_collection("runners"),
  },
  {
    "PUT /orgs/{org}/actions/runner-groups/{runner_group_id}/runners",
    "put_org_actions_runner_group_runners",
    actions_not_implemented,
  },
  {
    "PUT /orgs/{org}/actions/runner-groups/{runner_group_id}/runners/{runner_id}",
    "put_org_actions_runner_group_runner",
    actions_not_implemented,
  },
  {
    "DELETE /orgs/{org}/actions/runner-groups/{runner_group_id}/runners/{runner_id}",
    "delete_org_actions_runner_group_runner",
    actions_not_implemented,
  },

  -- Organization runners
  {
    "GET /orgs/{org}/actions/runners",
    "get_org_actions_runners",
    make_empty_collection("runners"),
  },
  { "GET /orgs/{org}/actions/runners/downloads", "get_org_actions_runner_downloads", empty_list },
  {
    "POST /orgs/{org}/actions/runners/generate-jitconfig",
    "post_org_actions_runner_jitconfig",
    actions_not_implemented,
  },
  {
    "POST /orgs/{org}/actions/runners/registration-token",
    "post_org_actions_runner_registration_token",
    actions_not_implemented,
  },
  {
    "POST /orgs/{org}/actions/runners/remove-token",
    "post_org_actions_runner_remove_token",
    actions_not_implemented,
  },
  {
    "GET /orgs/{org}/actions/runners/{runner_id}",
    "get_org_actions_runner",
    actions_not_implemented,
  },
  {
    "DELETE /orgs/{org}/actions/runners/{runner_id}",
    "delete_org_actions_runner",
    actions_not_implemented,
  },
  {
    "GET /orgs/{org}/actions/runners/{runner_id}/labels",
    "get_org_actions_runner_labels",
    empty_list,
  },
  {
    "POST /orgs/{org}/actions/runners/{runner_id}/labels",
    "post_org_actions_runner_labels",
    actions_not_implemented,
  },
  {
    "PUT /orgs/{org}/actions/runners/{runner_id}/labels",
    "put_org_actions_runner_labels",
    actions_not_implemented,
  },
  {
    "DELETE /orgs/{org}/actions/runners/{runner_id}/labels",
    "delete_org_actions_runner_labels",
    actions_not_implemented,
  },
  {
    "DELETE /orgs/{org}/actions/runners/{runner_id}/labels/{name}",
    "delete_org_actions_runner_label",
    actions_not_implemented,
  },

  -- Organization secrets
  {
    "GET /orgs/{org}/actions/secrets",
    "get_org_actions_secrets",
    make_empty_collection("secrets"),
  },
  {
    "GET /orgs/{org}/actions/secrets/public-key",
    "get_org_actions_secrets_public_key",
    actions_not_implemented,
  },
  {
    "GET /orgs/{org}/actions/secrets/{secret_name}",
    "get_org_actions_secret",
    actions_not_implemented,
  },
  {
    "PUT /orgs/{org}/actions/secrets/{secret_name}",
    "put_org_actions_secret",
    actions_not_implemented,
  },
  {
    "DELETE /orgs/{org}/actions/secrets/{secret_name}",
    "delete_org_actions_secret",
    actions_not_implemented,
  },
  {
    "GET /orgs/{org}/actions/secrets/{secret_name}/repositories",
    "get_org_actions_secret_repos",
    empty_list,
  },
  {
    "PUT /orgs/{org}/actions/secrets/{secret_name}/repositories",
    "put_org_actions_secret_repos",
    actions_not_implemented,
  },
  {
    "PUT /orgs/{org}/actions/secrets/{secret_name}/repositories/{repository_id}",
    "put_org_actions_secret_repo",
    actions_not_implemented,
  },
  {
    "DELETE /orgs/{org}/actions/secrets/{secret_name}/repositories/{repository_id}",
    "delete_org_actions_secret_repo",
    actions_not_implemented,
  },

  -- Organization variables
  {
    "GET /orgs/{org}/actions/variables",
    "get_org_actions_variables",
    make_empty_collection("variables"),
  },
  { "POST /orgs/{org}/actions/variables", "post_org_actions_variable", actions_not_implemented },
  {
    "GET /orgs/{org}/actions/variables/{name}",
    "get_org_actions_variable",
    actions_not_implemented,
  },
  {
    "PATCH /orgs/{org}/actions/variables/{name}",
    "patch_org_actions_variable",
    actions_not_implemented,
  },
  {
    "DELETE /orgs/{org}/actions/variables/{name}",
    "delete_org_actions_variable",
    actions_not_implemented,
  },
  {
    "GET /orgs/{org}/actions/variables/{name}/repositories",
    "get_org_actions_variable_repos",
    empty_list,
  },
  {
    "PUT /orgs/{org}/actions/variables/{name}/repositories",
    "put_org_actions_variable_repos",
    actions_not_implemented,
  },
  {
    "PUT /orgs/{org}/actions/variables/{name}/repositories/{repository_id}",
    "put_org_actions_variable_repo",
    actions_not_implemented,
  },
  {
    "DELETE /orgs/{org}/actions/variables/{name}/repositories/{repository_id}",
    "delete_org_actions_variable_repo",
    actions_not_implemented,
  },

  -- Repository artifacts
  {
    "GET /repos/{owner}/{repo}/actions/artifacts",
    "get_repo_actions_artifacts",
    make_empty_collection("artifacts"),
  },
  {
    "GET /repos/{owner}/{repo}/actions/artifacts/{artifact_id}",
    "get_repo_actions_artifact",
    actions_not_implemented,
  },
  {
    "DELETE /repos/{owner}/{repo}/actions/artifacts/{artifact_id}",
    "delete_repo_actions_artifact",
    actions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/actions/artifacts/{artifact_id}/{archive_format}",
    "get_repo_actions_artifact_archive",
    actions_not_implemented,
  },

  -- Repository cache
  {
    "GET /repos/{owner}/{repo}/actions/cache/retention-limit",
    "get_repo_actions_cache_retention_limit",
    actions_not_implemented,
  },
  {
    "PUT /repos/{owner}/{repo}/actions/cache/retention-limit",
    "put_repo_actions_cache_retention_limit",
    actions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/actions/cache/storage-limit",
    "get_repo_actions_cache_storage_limit",
    actions_not_implemented,
  },
  {
    "PUT /repos/{owner}/{repo}/actions/cache/storage-limit",
    "put_repo_actions_cache_storage_limit",
    actions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/actions/cache/usage",
    "get_repo_actions_cache_usage",
    actions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/actions/caches",
    "get_repo_actions_caches",
    make_empty_collection("actions_caches"),
  },
  {
    "DELETE /repos/{owner}/{repo}/actions/caches",
    "delete_repo_actions_caches",
    actions_not_implemented,
  },
  {
    "DELETE /repos/{owner}/{repo}/actions/caches/{cache_id}",
    "delete_repo_actions_cache",
    actions_not_implemented,
  },

  -- Repository jobs
  {
    "GET /repos/{owner}/{repo}/actions/jobs/{job_id}",
    "get_repo_actions_job",
    actions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/actions/jobs/{job_id}/logs",
    "get_repo_actions_job_logs",
    actions_not_implemented,
  },
  {
    "POST /repos/{owner}/{repo}/actions/jobs/{job_id}/rerun",
    "post_repo_actions_job_rerun",
    actions_not_implemented,
  },

  -- Repository OIDC
  {
    "GET /repos/{owner}/{repo}/actions/oidc/customization/sub",
    "get_repo_actions_oidc_sub",
    actions_not_implemented,
  },
  {
    "PUT /repos/{owner}/{repo}/actions/oidc/customization/sub",
    "put_repo_actions_oidc_sub",
    actions_not_implemented,
  },

  -- Repository org secrets/variables (read-only inherited view)
  {
    "GET /repos/{owner}/{repo}/actions/organization-secrets",
    "get_repo_actions_org_secrets",
    make_empty_collection("secrets"),
  },
  {
    "GET /repos/{owner}/{repo}/actions/organization-variables",
    "get_repo_actions_org_variables",
    make_empty_collection("variables"),
  },

  -- Repository permissions
  {
    "GET /repos/{owner}/{repo}/actions/permissions",
    "get_repo_actions_permissions",
    actions_not_implemented,
  },
  {
    "PUT /repos/{owner}/{repo}/actions/permissions",
    "put_repo_actions_permissions",
    actions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/actions/permissions/access",
    "get_repo_actions_access_level",
    actions_not_implemented,
  },
  {
    "PUT /repos/{owner}/{repo}/actions/permissions/access",
    "put_repo_actions_access_level",
    actions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/actions/permissions/artifact-and-log-retention",
    "get_repo_actions_artifact_log_retention",
    actions_not_implemented,
  },
  {
    "PUT /repos/{owner}/{repo}/actions/permissions/artifact-and-log-retention",
    "put_repo_actions_artifact_log_retention",
    actions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/actions/permissions/fork-pr-contributor-approval",
    "get_repo_actions_fork_pr_approval",
    actions_not_implemented,
  },
  {
    "PUT /repos/{owner}/{repo}/actions/permissions/fork-pr-contributor-approval",
    "put_repo_actions_fork_pr_approval",
    actions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/actions/permissions/fork-pr-workflows-private-repos",
    "get_repo_actions_fork_pr_private_repos",
    actions_not_implemented,
  },
  {
    "PUT /repos/{owner}/{repo}/actions/permissions/fork-pr-workflows-private-repos",
    "put_repo_actions_fork_pr_private_repos",
    actions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/actions/permissions/selected-actions",
    "get_repo_actions_selected_actions",
    actions_not_implemented,
  },
  {
    "PUT /repos/{owner}/{repo}/actions/permissions/selected-actions",
    "put_repo_actions_selected_actions",
    actions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/actions/permissions/workflow",
    "get_repo_actions_default_workflow_perms",
    actions_not_implemented,
  },
  {
    "PUT /repos/{owner}/{repo}/actions/permissions/workflow",
    "put_repo_actions_default_workflow_perms",
    actions_not_implemented,
  },

  -- Repository runners
  {
    "GET /repos/{owner}/{repo}/actions/runners",
    "get_repo_actions_runners",
    make_empty_collection("runners"),
  },
  {
    "GET /repos/{owner}/{repo}/actions/runners/downloads",
    "get_repo_actions_runner_downloads",
    empty_list,
  },
  {
    "POST /repos/{owner}/{repo}/actions/runners/generate-jitconfig",
    "post_repo_actions_runner_jitconfig",
    actions_not_implemented,
  },
  {
    "POST /repos/{owner}/{repo}/actions/runners/registration-token",
    "post_repo_actions_runner_registration_token",
    actions_not_implemented,
  },
  {
    "POST /repos/{owner}/{repo}/actions/runners/remove-token",
    "post_repo_actions_runner_remove_token",
    actions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/actions/runners/{runner_id}",
    "get_repo_actions_runner",
    actions_not_implemented,
  },
  {
    "DELETE /repos/{owner}/{repo}/actions/runners/{runner_id}",
    "delete_repo_actions_runner",
    actions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/actions/runners/{runner_id}/labels",
    "get_repo_actions_runner_labels",
    empty_list,
  },
  {
    "POST /repos/{owner}/{repo}/actions/runners/{runner_id}/labels",
    "post_repo_actions_runner_labels",
    actions_not_implemented,
  },
  {
    "PUT /repos/{owner}/{repo}/actions/runners/{runner_id}/labels",
    "put_repo_actions_runner_labels",
    actions_not_implemented,
  },
  {
    "DELETE /repos/{owner}/{repo}/actions/runners/{runner_id}/labels",
    "delete_repo_actions_runner_labels",
    actions_not_implemented,
  },
  {
    "DELETE /repos/{owner}/{repo}/actions/runners/{runner_id}/labels/{name}",
    "delete_repo_actions_runner_label",
    actions_not_implemented,
  },

  -- Repository workflow runs
  {
    "GET /repos/{owner}/{repo}/actions/runs",
    "get_repo_actions_runs",
    make_empty_collection("workflow_runs"),
  },
  {
    "GET /repos/{owner}/{repo}/actions/runs/{run_id}",
    "get_repo_actions_run",
    actions_not_implemented,
  },
  {
    "DELETE /repos/{owner}/{repo}/actions/runs/{run_id}",
    "delete_repo_actions_run",
    actions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/actions/runs/{run_id}/approvals",
    "get_repo_actions_run_approvals",
    empty_list,
  },
  {
    "POST /repos/{owner}/{repo}/actions/runs/{run_id}/approve",
    "post_repo_actions_run_approve",
    actions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/actions/runs/{run_id}/artifacts",
    "get_repo_actions_run_artifacts",
    make_empty_collection("artifacts"),
  },
  {
    "GET /repos/{owner}/{repo}/actions/runs/{run_id}/attempts/{attempt_number}",
    "get_repo_actions_run_attempt",
    actions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/actions/runs/{run_id}/attempts/{attempt_number}/jobs",
    "get_repo_actions_run_attempt_jobs",
    make_empty_collection("jobs"),
  },
  {
    "GET /repos/{owner}/{repo}/actions/runs/{run_id}/attempts/{attempt_number}/logs",
    "get_repo_actions_run_attempt_logs",
    actions_not_implemented,
  },
  {
    "POST /repos/{owner}/{repo}/actions/runs/{run_id}/cancel",
    "post_repo_actions_run_cancel",
    actions_not_implemented,
  },
  {
    "POST /repos/{owner}/{repo}/actions/runs/{run_id}/deployment_protection_rule",
    "post_repo_actions_run_deployment_prot",
    actions_not_implemented,
  },
  {
    "POST /repos/{owner}/{repo}/actions/runs/{run_id}/force-cancel",
    "post_repo_actions_run_force_cancel",
    actions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs",
    "get_repo_actions_run_jobs",
    make_empty_collection("jobs"),
  },
  {
    "GET /repos/{owner}/{repo}/actions/runs/{run_id}/logs",
    "get_repo_actions_run_logs",
    actions_not_implemented,
  },
  {
    "DELETE /repos/{owner}/{repo}/actions/runs/{run_id}/logs",
    "delete_repo_actions_run_logs",
    actions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/actions/runs/{run_id}/pending_deployments",
    "get_repo_actions_run_pending_deployments",
    empty_list,
  },
  {
    "POST /repos/{owner}/{repo}/actions/runs/{run_id}/pending_deployments",
    "post_repo_actions_run_pending_deployments",
    actions_not_implemented,
  },
  {
    "POST /repos/{owner}/{repo}/actions/runs/{run_id}/rerun",
    "post_repo_actions_run_rerun",
    actions_not_implemented,
  },
  {
    "POST /repos/{owner}/{repo}/actions/runs/{run_id}/rerun-failed-jobs",
    "post_repo_actions_run_rerun_failed",
    actions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/actions/runs/{run_id}/timing",
    "get_repo_actions_run_timing",
    actions_not_implemented,
  },

  -- Repository secrets
  {
    "GET /repos/{owner}/{repo}/actions/secrets",
    "get_repo_actions_secrets",
    make_empty_collection("secrets"),
  },
  {
    "GET /repos/{owner}/{repo}/actions/secrets/public-key",
    "get_repo_actions_secrets_public_key",
    actions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/actions/secrets/{secret_name}",
    "get_repo_actions_secret",
    actions_not_implemented,
  },
  {
    "PUT /repos/{owner}/{repo}/actions/secrets/{secret_name}",
    "put_repo_actions_secret",
    actions_not_implemented,
  },
  {
    "DELETE /repos/{owner}/{repo}/actions/secrets/{secret_name}",
    "delete_repo_actions_secret",
    actions_not_implemented,
  },

  -- Repository variables
  {
    "GET /repos/{owner}/{repo}/actions/variables",
    "get_repo_actions_variables",
    make_empty_collection("variables"),
  },
  {
    "POST /repos/{owner}/{repo}/actions/variables",
    "post_repo_actions_variable",
    actions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/actions/variables/{name}",
    "get_repo_actions_variable",
    actions_not_implemented,
  },
  {
    "PATCH /repos/{owner}/{repo}/actions/variables/{name}",
    "patch_repo_actions_variable",
    actions_not_implemented,
  },
  {
    "DELETE /repos/{owner}/{repo}/actions/variables/{name}",
    "delete_repo_actions_variable",
    actions_not_implemented,
  },

  -- Repository workflows
  {
    "GET /repos/{owner}/{repo}/actions/workflows",
    "get_repo_actions_workflows",
    make_empty_collection("workflows"),
  },
  {
    "GET /repos/{owner}/{repo}/actions/workflows/{workflow_id}",
    "get_repo_actions_workflow",
    actions_not_implemented,
  },
  {
    "PUT /repos/{owner}/{repo}/actions/workflows/{workflow_id}/disable",
    "put_repo_actions_workflow_disable",
    actions_not_implemented,
  },
  {
    "POST /repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches",
    "post_repo_actions_workflow_dispatch",
    actions_not_implemented,
  },
  {
    "PUT /repos/{owner}/{repo}/actions/workflows/{workflow_id}/enable",
    "put_repo_actions_workflow_enable",
    actions_not_implemented,
  },
  {
    "GET /repos/{owner}/{repo}/actions/workflows/{workflow_id}/runs",
    "get_repo_actions_workflow_runs",
    make_empty_collection("workflow_runs"),
  },
  {
    "GET /repos/{owner}/{repo}/actions/workflows/{workflow_id}/timing",
    "get_repo_actions_workflow_timing",
    actions_not_implemented,
  },

  { group = "git" },
  -- Git database (https://docs.github.com/en/rest/git)
  -- Blobs
  { "POST /repos/{owner}/{repo}/git/blobs", "create_git_blob", git_not_implemented },
  { "GET /repos/{owner}/{repo}/git/blobs/{file_sha}", "get_git_blob", git_not_implemented },

  -- Commits
  { "POST /repos/{owner}/{repo}/git/commits", "create_git_commit", git_not_implemented },
  { "GET /repos/{owner}/{repo}/git/commits/{commit_sha}", "get_git_commit", git_not_implemented },

  -- Refs
  {
    "GET /repos/{owner}/{repo}/git/matching-refs/{ref+}",
    "list_git_matching_refs",
    git_not_implemented,
  },
  { "GET /repos/{owner}/{repo}/git/ref/{ref+}", "get_git_ref", git_not_implemented },
  { "POST /repos/{owner}/{repo}/git/refs", "create_git_ref", git_not_implemented },
  { "PATCH /repos/{owner}/{repo}/git/refs/{ref+}", "update_git_ref", git_not_implemented },
  { "DELETE /repos/{owner}/{repo}/git/refs/{ref+}", "delete_git_ref", git_not_implemented },

  -- Tags
  { "POST /repos/{owner}/{repo}/git/tags", "create_git_tag", git_not_implemented },
  { "GET /repos/{owner}/{repo}/git/tags/{tag_sha}", "get_git_tag", git_not_implemented },

  -- Trees
  { "POST /repos/{owner}/{repo}/git/trees", "create_git_tree", git_not_implemented },
  { "GET /repos/{owner}/{repo}/git/trees/{tree_sha}", "get_git_tree", git_not_implemented },
}
-- Build the global `endpoints` table (consumed by scripts/dump-endpoints.lua)
-- and register routes. Marker entries { group = "name" } set the current
-- group; real entries get e.group set and are added to `endpoints`.
endpoints = {}
local _group = ""
for _, e in ipairs(_ep_catalog) do
  if not e[1] then
    _group = e.group
  else
    e.group = _group
    endpoints[#endpoints + 1] = e
    route_add(e[1], e[2], e[3])
  end
end
function OnHttpRequest()
  if not backend_allow_anonymous and not GetHeader("Authorization") then
    respond_json(401, { message = "This instance requires authentication." })
    return
  end
  local ep, caps, default_fn = route_match(GetMethod(), GetPath())
  if ep then
    local fn = handle[ep] or default_fn
    if fn then
      fn(table.unpack(caps))
    else
      respond_json(404, { message = "Not Found" })
    end
  elseif path_known(GetPath()) then
    respond_json(405, { message = "Method Not Allowed" })
  else
    respond_json(404, { message = "Not Found" })
  end
end
