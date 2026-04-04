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

  -- Branches ------------------------------------------------------------------
  -- Radicle: GET /api/v1/repos/{rid}/branches → [{ name, head }]

  get_repo_branches = function(_, rid)
    proxy_json(
      function(branches)
        branches = branches or {}
        local result = {}
        for _, b in ipairs(branches) do
          result[#result + 1] = {
            name      = b.name or "",
            commit    = { sha = b.head or "", url = "" },
            protected = false,
          }
        end
        return result
      end,
      fetch_json(base() .. "/repos/" .. rid .. "/branches"))
  end,

  get_repo_branch = function(_, rid, branch)
    -- Fetch all branches and find the named one.
    proxy_json(
      function(branches)
        for _, b in ipairs(branches or {}) do
          if b.name == branch then
            return { name = b.name, commit = { sha = b.head or "", url = "" }, protected = false }
          end
        end
        return {}
      end,
      fetch_json(base() .. "/repos/" .. rid .. "/branches"))
  end,

  -- Commits -------------------------------------------------------------------
  -- Radicle: GET /api/v1/repos/{rid}/commits?branch={branch}

  get_repo_commits = function(_, rid)
    local branch = GetParam("sha") or ""
    local url = base() .. "/repos/" .. rid .. "/commits"
    if branch ~= "" then url = url .. "?branch=" .. branch end
    proxy_json(
      function(commits)
        commits = commits or {}
        local result = {}
        for _, c in ipairs(commits) do
          local author = c.author or {}
          result[#result + 1] = {
            sha    = c.id or "",
            commit = {
              message   = c.message or "",
              author    = { name = author.name or "", email = author.email or "", date = "" },
              committer = { name = author.name or "", email = author.email or "", date = "" },
            },
            author    = { login = author.name or "", id = 0, avatar_url = "" },
            committer = { login = author.name or "", id = 0, avatar_url = "" },
          }
        end
        return result
      end,
      fetch_json(url))
  end,

  get_repo_commit = function(_, rid, ref)
    proxy_json(
      function(c)
        if not c then return {} end
        local author = c.author or {}
        return {
          sha    = c.id or "",
          commit = {
            message   = c.message or "",
            author    = { name = author.name or "", email = author.email or "", date = "" },
            committer = { name = author.name or "", email = author.email or "", date = "" },
          },
        }
      end,
      fetch_json(base() .. "/repos/" .. rid .. "/commits/" .. ref))
  end,

  -- Contents ------------------------------------------------------------------
  -- Radicle: GET /api/v1/repos/{rid}/blob/{commit}/{path} — raw bytes

  get_repo_readme = function(_, rid)
    local ref = GetParam("ref") or "HEAD"
    local candidates = { "README.md", "README", "readme.md", "README.rst" }
    for _, fname in ipairs(candidates) do
      local ok, status, _, body = fetch_json(
        base() .. "/repos/" .. rid .. "/blob/" .. ref .. "/" .. fname)
      if ok and status == 200 then
        respond_json(200, "OK", {
          type     = "file", name = fname, path = fname, sha = "",
          size     = #body, encoding = "base64", content = EncodeBase64(body),
        })
        return
      end
    end
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  get_repo_content = function(_, rid, path)
    local ref = GetParam("ref") or "HEAD"
    local ok, status, _, body = fetch_json(
      base() .. "/repos/" .. rid .. "/blob/" .. ref .. "/" .. path)
    if ok and status == 200 then
      respond_json(200, "OK", {
        type     = "file",
        name     = path:match("[^/]+$") or path,
        path     = path,
        sha      = "",
        size     = #body,
        encoding = "base64",
        content  = EncodeBase64(body),
      })
    elseif ok then respond_json(status, "Error", { message = "Error" })
    else respond_json(503, "Service Unavailable", {}) end
  end,

  -- Users' repos --------------------------------------------------------------

  get_users_repos = function(username)
    -- Radicle: list repos seeded by a specific node/delegate
    proxy_json(translate_radicle_repos,
      fetch_json(append_page_params(
        base() .. "/repos?show=all&delegate=" .. username,
        { per_page = "perPage", page = "page" })))
  end,

  get_repositories = function()
    proxy_json(translate_radicle_repos,
      fetch_json(append_page_params(base() .. "/repos?show=all",
        { per_page = "perPage", page = "page" })))
  end,

}
