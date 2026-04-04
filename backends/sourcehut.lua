-- Sourcehut backend handler overrides.
-- Uses git.sr.ht REST API at /api/~{username}/repos/{name}.

local base = function() return config.base_url .. "/api" end
local auth = function() return make_fetch_opts("token") end

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

-- Map a Sourcehut repository object to GitHub format.
local function translate_srht_repo(r)
  if not r then return {} end
  local owner = r.owner or {}
  local canonical = owner.canonical_name or ""
  -- canonical_name is like "~username", strip the tilde for login
  local login = canonical:sub(1, 1) == "~" and canonical:sub(2) or canonical
  local vis = r.visibility or "public"
  return {
    id                = r.id or 0,
    node_id           = "",
    name              = r.name,
    full_name         = login .. "/" .. (r.name or ""),
    private           = vis == "private",
    owner             = {
      login      = login,
      id         = 0,
      node_id    = "",
      avatar_url = "",
      url        = "",
      html_url   = config.base_url .. "/" .. canonical,
      type       = "User",
    },
    html_url          = config.base_url .. "/" .. canonical .. "/" .. (r.name or ""),
    description       = r.description,
    fork              = false,
    url               = "",
    clone_url         = "",
    homepage          = "",
    size              = 0,
    stargazers_count  = 0,
    watchers_count    = 0,
    language          = nil,
    has_issues        = false,
    has_wiki          = false,
    forks_count       = 0,
    archived          = false,
    disabled          = false,
    open_issues_count = 0,
    default_branch    = r.HEAD and r.HEAD.name or "main",
    visibility        = vis == "private" and "private" or "public",
    forks             = 0,
    open_issues       = 0,
    watchers          = 0,
    created_at        = r.created,
    updated_at        = r.updated,
    pushed_at         = r.updated,
  }
end

-- Translate GitHub create/update request body to Sourcehut format.
local function translate_srht_req(body_str)
  local req = DecodeJson(body_str or "{}")
  local sr = {}
  if req.name        then sr.name        = req.name end
  if req.description then sr.description = req.description end
  if req.private ~= nil then
    sr.visibility = req.private and "private" or "public"
  end
  return EncodeJson(sr)
end

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, config.base_url .. "/api/version", auth())
    if ok and status == 200 then respond_json(200, "OK", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_emojis = function() respond_json(404, "Not Found", { message = "Not Found" }) end,

  get_repo = function(owner, repo_name)
    proxy_json(translate_srht_repo,
      fetch_json(base() .. "/~" .. owner .. "/repos/" .. repo_name))
  end,

  patch_repo = function(owner, repo_name)
    -- Sourcehut uses PUT for updates
    proxy_json(translate_srht_repo,
      fetch_json(base() .. "/~" .. owner .. "/repos/" .. repo_name,
        "PUT", translate_srht_req(GetBody())))
  end,

  delete_repo = function(owner, repo_name)
    local url = base() .. "/~" .. owner .. "/repos/" .. repo_name
    local dopts = auth() or {}; dopts.method = "DELETE"
    local ok, status = pcall(Fetch, url, dopts)
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_user_repos = function()
    -- Sourcehut: need to know the authenticated user. Use /api/user first.
    local ok, status, _, ubody = fetch_json(config.base_url .. "/api/user")
    if not ok or status ~= 200 then respond_json(503, "Service Unavailable", {}); return end
    local user = DecodeJson(ubody)
    local canonical = user.canonical_name or ("~" .. (user.name or ""))
    proxy_json(
      function(data)
        local repos = data.results or {}
        for i, r in ipairs(repos) do repos[i] = translate_srht_repo(r) end
        return repos
      end,
      -- Sourcehut uses cursor-based pagination; only limit is supported for page size
      fetch_json(append_page_params(base() .. "/" .. canonical .. "/repos",
        { per_page = "limit" })))
  end,

  post_user_repos = function()
    -- Sourcehut: create via POST /api/~{user}/repos — need user context
    local ok, status, _, ubody = fetch_json(config.base_url .. "/api/user")
    if not ok or status ~= 200 then respond_json(503, "Service Unavailable", {}); return end
    local user = DecodeJson(ubody)
    local canonical = user.canonical_name or ("~" .. (user.name or ""))
    proxy_json_created(translate_srht_repo,
      fetch_json(base() .. "/" .. canonical .. "/repos", "POST", translate_srht_req(GetBody())))
  end,

  -- Sourcehut has no concept of organizations; individual users own repos.
  get_org_repos = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  post_org_repos = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  -- Sourcehut has no topics API.
  get_repo_topics = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  put_repo_topics = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  -- Sourcehut has no language detection API.
  get_repo_languages = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  -- Sourcehut has no contributors endpoint.
  get_repo_contributors = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  get_repo_tags = function(owner, repo_name)
    -- Sourcehut /refs returns { results: [...] } with name and target fields
    -- Filter to tags only (refs starting with "refs/tags/")
    proxy_json(
      function(data)
        local tags = {}
        for _, ref in ipairs(data.results or {}) do
          local tag_name = ref.name and ref.name:match("^refs/tags/(.+)")
          if tag_name then
            tags[#tags + 1] = { name = tag_name, commit = { sha = ref.target or "", url = "" } }
          end
        end
        return tags
      end,
      fetch_json(base() .. "/~" .. owner .. "/repos/" .. repo_name .. "/refs"))
  end,

  get_repo_teams = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,
}
