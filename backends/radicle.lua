-- Radicle backend handler overrides.
-- Uses Radicle HTTP API at /api/v1/.
-- Radicle repos are identified by their RID (Radicle ID), e.g. rad:z3gqcJUoA1n9HaHKufZs1.
-- GitHub {owner}/{repo} maps to: owner = node DID (ignored), repo = RID.

local base = function() return config.base_url .. "/api/v1" end
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

-- Map a Radicle repository object to GitHub format.
local function translate_radicle_repo(r)
  if not r then return {} end
  -- Radicle project payload is under payloads["xyz.radicle.project"]
  local proj = (r.payloads and r.payloads["xyz.radicle.project"]) or {}
  local delegates = r.delegates or {}
  local owner_did = delegates[1] and delegates[1].id or ""
  -- DID looks like "did:key:z6Mk..."; extract the key part as login
  local login = owner_did:match("did:key:(.+)$") or owner_did
  return {
    id                = 0,
    node_id           = r.rid or "",
    name              = proj.name or r.rid or "",
    full_name         = (login ~= "" and (login .. "/") or "") .. (proj.name or r.rid or ""),
    private           = r.private or false,
    owner             = {
      login      = login,
      id         = 0,
      node_id    = owner_did,
      avatar_url = "",
      url        = "",
      html_url   = "",
      type       = "User",
    },
    html_url          = config.base_url .. "/repos/" .. (r.rid or ""),
    description       = proj.description,
    fork              = false,
    url               = "",
    clone_url         = r.rid and ("rad://" .. r.rid) or "",
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
    default_branch    = proj.defaultBranch or "main",
    visibility        = (r.private or false) and "private" or "public",
    forks             = 0,
    open_issues       = 0,
    watchers          = 0,
    created_at        = nil,
    updated_at        = nil,
    pushed_at         = nil,
  }
end

-- Translate GitHub create request body to Radicle format.
local function translate_radicle_req(body_str)
  local req = DecodeJson(body_str or "{}")
  local r = {}
  if req.name        then r.name        = req.name end
  if req.description then r.description = req.description end
  if req.private ~= nil then r.private  = req.private end
  if req.default_branch then r.defaultBranch = req.default_branch end
  return EncodeJson(r)
end

local function translate_radicle_repos(repos)
  repos = repos or {}
  for i, r in ipairs(repos) do repos[i] = translate_radicle_repo(r) end
  return repos
end

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, base(), auth())
    if ok and status == 200 then respond_json(200, "OK", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_emojis = function() respond_json(404, "Not Found", { message = "Not Found" }) end,

  -- GET /repos/{owner}/{rid} — owner is ignored; repo = RID
  get_repo = function(_, rid)
    proxy_json(translate_radicle_repo, fetch_json(base() .. "/repos/" .. rid))
  end,

  patch_repo = function(_, rid)
    proxy_json(translate_radicle_repo,
      fetch_json(base() .. "/repos/" .. rid, "PATCH", translate_radicle_req(GetBody())))
  end,

  -- Radicle has no delete endpoint
  delete_repo = function()
    respond_json(405, "Method Not Allowed",
      { message = "Radicle does not support repository deletion" })
  end,

  get_user_repos = function()
    -- Radicle: list repos seeded/hosted locally
    proxy_json(translate_radicle_repos,
      fetch_json(append_page_params(base() .. "/repos?show=local",
        { per_page = "perPage", page = "page" })))
  end,

  post_user_repos = function()
    proxy_json_created(translate_radicle_repo,
      fetch_json(base() .. "/repos", "POST", translate_radicle_req(GetBody())))
  end,

  -- Radicle has no org concept
  get_org_repos = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  post_org_repos = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  -- Radicle has no topics API
  get_repo_topics = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  put_repo_topics = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  -- Radicle has no language detection
  get_repo_languages = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  -- Radicle has no contributors endpoint
  get_repo_contributors = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  get_repo_tags = function(_, rid)
    -- Radicle returns [{ name, oid }] or [{ ref, oid }]
    proxy_json(
      function(tags)
        tags = tags or {}
        local result = {}
        for _, t in ipairs(tags) do
          result[#result + 1] = {
            name   = t.name or t.ref or "",
            commit = { sha = t.oid or t.target or "", url = "" },
          }
        end
        return result
      end,
      fetch_json(base() .. "/repos/" .. rid .. "/tags"))
  end,

  get_repo_teams = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,
}
