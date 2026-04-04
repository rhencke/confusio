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

-- backend_impl is global: set by backends/<name>.lua at startup.
backend_impl = {}
if config.backend ~= "" then
  assert(config.backend:match("^[%a][%w_]*$"),
    "invalid backend name: " .. config.backend)
  dofile("/zip/backends/" .. config.backend .. ".lua")
end

-- not_implemented is a default handler body used for endpoints whose provider
-- support is not yet wired up.
local function not_implemented()
  respond_json(501, "Not Implemented", { message = "Not Implemented" })
end

-- Default handlers. Add an entry here for every route registered below.
-- Override in backends/<name>.lua only when the backend behaves differently.
local defaults = {
  get_root              = function() respond_json(200, "OK", {}) end,
  get_emojis            = function() respond_json(200, "OK", {}) end,
  get_repo              = not_implemented,
  patch_repo            = not_implemented,
  delete_repo           = not_implemented,
  get_user_repos        = not_implemented,
  post_user_repos       = not_implemented,
  get_org_repos         = not_implemented,
  post_org_repos        = not_implemented,
  get_repo_topics       = not_implemented,
  put_repo_topics       = not_implemented,
  get_repo_languages    = not_implemented,
  get_repo_contributors = not_implemented,
  get_repo_tags         = not_implemented,
  get_repo_teams        = not_implemented,
}

-- Resolve handlers once at startup: backend overrides shadow defaults via __index.
-- The backend is fixed for the program's lifetime — no per-request dispatch needed.
local handle = setmetatable(backend_impl, { __index = defaults })

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
-- falling through to Redbean's default routing.
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
  { "GET /",                                            "get_root"              },
  -- Emojis
  { "GET /emojis",                                      "get_emojis"            },
  -- Repos API (https://docs.github.com/en/rest/repos/repos)
  { "GET /repos/{owner}/{repo}",                        "get_repo"              },
  { "PATCH /repos/{owner}/{repo}",                      "patch_repo"            },
  { "DELETE /repos/{owner}/{repo}",                     "delete_repo"           },
  { "GET /user/repos",                                  "get_user_repos"        },
  { "POST /user/repos",                                 "post_user_repos"       },
  { "GET /orgs/{org}/repos",                            "get_org_repos"         },
  { "POST /orgs/{org}/repos",                           "post_org_repos"        },
  { "GET /repos/{owner}/{repo}/topics",                 "get_repo_topics"       },
  { "PUT /repos/{owner}/{repo}/topics",                 "put_repo_topics"       },
  { "GET /repos/{owner}/{repo}/languages",              "get_repo_languages"    },
  { "GET /repos/{owner}/{repo}/contributors",           "get_repo_contributors" },
  { "GET /repos/{owner}/{repo}/tags",                   "get_repo_tags"         },
  { "GET /repos/{owner}/{repo}/teams",                  "get_repo_teams"        },
}
for _, r in ipairs(routes) do route_add(r[1], r[2]) end

function OnHttpRequest()
  local ep, caps = route_match(GetMethod(), GetPath())
  if ep then
    handle[ep](table.unpack(caps))
  elseif path_known(GetPath()) then
    respond_json(405, "Method Not Allowed", { message = "Method Not Allowed" })
  else
    Route()
  end
end
