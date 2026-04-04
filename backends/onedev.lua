-- OneDev backend handler overrides.
-- Uses OneDev REST API at /~api/.
-- Projects are addressed by integer ID; owner/repo maps via path query.

local base = function() return config.base_url .. "/~api" end
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

-- Resolve owner/repo to a OneDev project ID by querying by path.
local function resolve_project_id(owner, repo_name)
  local path = owner ~= "" and (owner .. "/" .. repo_name) or repo_name
  -- OneDev query language: "Path" is "owner/repo"
  local query = "%22Path%22+is+%22" .. path .. "%22"
  local ok, status, _, body = fetch_json(base() .. "/projects?query=" .. query .. "&count=1")
  if not ok or status ~= 200 then return nil end
  local projects = DecodeJson(body) or {}
  return projects[1] and projects[1].id
end

-- Map a OneDev project object to GitHub format.
local function translate_onedev_repo(r)
  if not r then return {} end
  local path = r.path or r.name or ""
  local owner_part, name_part = path:match("^(.+)/([^/]+)$")
  if not owner_part then owner_part = ""; name_part = path end
  return {
    id                = r.id or 0,
    node_id           = "",
    name              = name_part,
    full_name         = path,
    private           = not (r.public or false),
    owner             = {
      login      = owner_part,
      id         = 0,
      node_id    = "",
      avatar_url = "",
      url        = "",
      html_url   = "",
      type       = "User",
    },
    html_url          = config.base_url .. "/" .. path,
    description       = r.description,
    fork              = r.forkedFrom ~= nil,
    url               = "",
    clone_url         = "",
    homepage          = "",
    size              = 0,
    stargazers_count  = 0,
    watchers_count    = 0,
    language          = nil,
    has_issues        = true,
    has_wiki          = false,
    forks_count       = 0,
    archived          = false,
    disabled          = false,
    open_issues_count = 0,
    default_branch    = r.defaultBranch or "main",
    visibility        = (r.public or false) and "public" or "private",
    forks             = 0,
    open_issues       = 0,
    watchers          = 0,
    created_at        = nil,
    updated_at        = nil,
    pushed_at         = nil,
  }
end

-- Translate GitHub create/update request body to OneDev format.
local function translate_onedev_req(body_str)
  local req = DecodeJson(body_str or "{}")
  local od = {}
  if req.name        then od.name        = req.name end
  if req.description then od.description = req.description end
  if req.private ~= nil then od.public   = not req.private end
  return EncodeJson(od)
end

local function translate_onedev_repos(repos)
  repos = repos or {}
  for i, r in ipairs(repos) do repos[i] = translate_onedev_repo(r) end
  return repos
end

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, base() .. "/server-version", auth())
    if ok and status == 200 then respond_json(200, "OK", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_repo = function(owner, repo_name)
    local id = resolve_project_id(owner, repo_name)
    if not id then respond_json(404, "Not Found", { message = "Not Found" }); return end
    proxy_json(translate_onedev_repo, fetch_json(base() .. "/projects/" .. id))
  end,

  patch_repo = function(owner, repo_name)
    local id = resolve_project_id(owner, repo_name)
    if not id then respond_json(404, "Not Found", { message = "Not Found" }); return end
    proxy_json(translate_onedev_repo,
      fetch_json(base() .. "/projects/" .. id, "PATCH", translate_onedev_req(GetBody())))
  end,

  delete_repo = function(owner, repo_name)
    local id = resolve_project_id(owner, repo_name)
    if not id then respond_json(404, "Not Found", { message = "Not Found" }); return end
    local dopts = auth() or {}; dopts.method = "DELETE"
    local ok, status = pcall(Fetch, base() .. "/projects/" .. id, dopts)
    if ok and (status == 200 or status == 204) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_user_repos = function()
    -- OneDev uses offset-based pagination: count=N, offset=(page-1)*N
    local count = tonumber(GetParam("per_page")) or 30
    local page  = tonumber(GetParam("page")) or 1
    proxy_json(translate_onedev_repos,
      fetch_json(base() .. "/projects?count=" .. count .. "&offset=" .. ((page-1)*count)))
  end,

  post_user_repos = function()
    proxy_json_created(translate_onedev_repo,
      fetch_json(base() .. "/projects", "POST", translate_onedev_req(GetBody())))
  end,

  get_org_repos = function(org)
    -- OneDev groups/orgs map to parent projects; query by parent path.
    -- OneDev uses offset-based pagination: count=N, offset=(page-1)*N
    local query = "%22Parent%22+is+%22" .. org .. "%22"
    local count = tonumber(GetParam("per_page")) or 30
    local page  = tonumber(GetParam("page")) or 1
    proxy_json(translate_onedev_repos,
      fetch_json(base() .. "/projects?query=" .. query
        .. "&count=" .. count .. "&offset=" .. ((page-1)*count)))
  end,

  post_org_repos = function(org)
    local req = DecodeJson(GetBody() or "{}")
    local od = {
      name        = req.name,
      description = req.description or "",
      public      = not (req.private or false),
      parent      = { path = org },
    }
    proxy_json_created(translate_onedev_repo,
      fetch_json(base() .. "/projects", "POST", EncodeJson(od)))
  end,

  get_repo_tags = function(owner, repo_name)
    local id = resolve_project_id(owner, repo_name)
    if not id then respond_json(404, "Not Found", { message = "Not Found" }); return end
    -- OneDev returns [{ name, commitHash }]
    proxy_json(
      function(tags)
        tags = tags or {}
        local result = {}
        for _, t in ipairs(tags) do
          result[#result + 1] = { name = t.name or "", commit = { sha = t.commitHash or "", url = "" } }
        end
        return result
      end,
      fetch_json(base() .. "/projects/" .. id .. "/tags"))
  end,

}
