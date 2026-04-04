-- Harness Code backend handler overrides.
-- Uses Harness Code (Gitness) REST API via /gateway/code/api/v1/.
-- repo_ref is owner/repo URL-encoded as owner%2Frepo.

local base = function() return config.base_url .. "/gateway/code/api/v1" end
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

local function repo_ref(owner, repo_name)
  return owner .. "%2F" .. repo_name
end

-- Map a Harness Code repository object to GitHub format.
local function translate_harness_repo(r)
  if not r then return {} end
  local path = r.path or ""
  -- path is like "space/reponame"; split on last /
  local owner_part, name_part = path:match("^(.+)/([^/]+)$")
  if not owner_part then owner_part = ""; name_part = path end
  return {
    id                = r.id or 0,
    node_id           = "",
    name              = name_part,
    full_name         = path,
    private           = not r.is_public,
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
    fork              = r.fork_id ~= nil and r.fork_id > 0,
    url               = "",
    clone_url         = r.git_url or "",
    homepage          = "",
    size              = r.size or 0,
    stargazers_count  = r.num_stars or 0,
    watchers_count    = 0,
    language          = nil,
    has_issues        = true,
    has_wiki          = false,
    forks_count       = r.num_forks or 0,
    archived          = false,
    disabled          = false,
    open_issues_count = 0,
    default_branch    = r.default_branch or "main",
    visibility        = r.is_public and "public" or "private",
    forks             = r.num_forks or 0,
    open_issues       = 0,
    watchers          = 0,
    created_at        = r.created and tostring(r.created) or nil,
    updated_at        = r.updated and tostring(r.updated) or nil,
    pushed_at         = r.updated and tostring(r.updated) or nil,
  }
end

-- Translate GitHub create/update request body to Harness Code format.
local function translate_harness_req(body_str)
  local req = DecodeJson(body_str or "{}")
  local h = {}
  if req.name          then h.identifier   = req.name end
  if req.description   then h.description  = req.description end
  if req.private ~= nil then h.is_public   = not req.private end
  if req.default_branch then h.default_branch = req.default_branch end
  return EncodeJson(h)
end

local function translate_harness_repos(repos)
  repos = repos or {}
  for i, r in ipairs(repos) do repos[i] = translate_harness_repo(r) end
  return repos
end

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, base(), auth())
    if ok and status == 200 then respond_json(200, "OK", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_emojis = function() respond_json(404, "Not Found", { message = "Not Found" }) end,

  get_repo = function(owner, repo_name)
    proxy_json(translate_harness_repo,
      fetch_json(base() .. "/repos/" .. repo_ref(owner, repo_name)))
  end,

  patch_repo = function(owner, repo_name)
    proxy_json(translate_harness_repo,
      fetch_json(base() .. "/repos/" .. repo_ref(owner, repo_name),
        "PATCH", translate_harness_req(GetBody())))
  end,

  delete_repo = function(owner, repo_name)
    local url = base() .. "/repos/" .. repo_ref(owner, repo_name)
    local dopts = auth() or {}; dopts.method = "DELETE"
    local ok, status = pcall(Fetch, url, dopts)
    if ok and (status == 204 or status == 200) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_user_repos = function()
    proxy_json(translate_harness_repos,
      fetch_json(append_page_params(base() .. "/repos",
        { per_page = "limit", page = "page" })))
  end,

  post_user_repos = function()
    proxy_json_created(translate_harness_repo,
      fetch_json(base() .. "/repos", "POST", translate_harness_req(GetBody())))
  end,

  get_org_repos = function(space)
    proxy_json(translate_harness_repos,
      fetch_json(append_page_params(base() .. "/spaces/" .. space .. "/repos",
        { per_page = "limit", page = "page" })))
  end,

  post_org_repos = function(space)
    local req = DecodeJson(GetBody() or "{}")
    req.parent_ref = space
    proxy_json_created(translate_harness_repo,
      fetch_json(base() .. "/repos", "POST", EncodeJson(req)))
  end,

  -- Harness Code has no topics API.
  get_repo_topics = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  put_repo_topics = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  -- Harness Code has no language detection API.
  get_repo_languages = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  -- Harness Code has no contributors endpoint.
  get_repo_contributors = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  get_repo_tags = function(owner, repo_name)
    proxy_json(
      function(tags)
        tags = tags or {}
        for i, t in ipairs(tags) do
          tags[i] = { name = t.name, commit = { sha = (t.sha or t.target or ""), url = "" } }
        end
        return tags
      end,
      fetch_json(append_page_params(
        base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/tags",
        { per_page = "limit", page = "page" })))
  end,

  get_repo_teams = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,
}
