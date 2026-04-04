-- Bitbucket backend handler overrides.
-- Uses Bitbucket REST API v2 at /2.0/.

local base = function() return config.base_url .. "/2.0" end
local auth = function() return make_fetch_opts("basic") end

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

-- Map a Bitbucket repository object to GitHub format.
local function translate_bb_repo(r)
  if not r then return {} end
  local owner = r.owner or {}
  local main = r.mainbranch or {}
  return {
    id                = 0,
    node_id           = r.uuid or "",
    name              = r.slug or r.name,
    full_name         = r.full_name,
    private           = r.is_private,
    owner             = {
      login      = owner.nickname or owner.display_name or "",
      id         = 0,
      node_id    = owner.uuid or "",
      avatar_url = (owner.links and owner.links.avatar and owner.links.avatar.href) or "",
      url        = "",
      html_url   = (owner.links and owner.links.html and owner.links.html.href) or "",
      type       = owner.type == "team" and "Organization" or "User",
    },
    html_url          = (r.links and r.links.html and r.links.html.href) or "",
    description       = r.description,
    fork              = r.parent ~= nil,
    url               = (r.links and r.links.self and r.links.self.href) or "",
    clone_url         = "",
    homepage          = r.website or "",
    size              = r.size or 0,
    stargazers_count  = 0,
    watchers_count    = 0,
    language          = r.language,
    has_issues        = r.has_issues,
    has_wiki          = r.has_wiki,
    forks_count       = 0,
    archived          = false,
    disabled          = false,
    open_issues_count = 0,
    default_branch    = main.name or "main",
    visibility        = r.is_private and "private" or "public",
    forks             = 0,
    open_issues       = 0,
    watchers          = 0,
    created_at        = r.created_on,
    updated_at        = r.updated_on,
    pushed_at         = r.updated_on,
  }
end

-- Translate GitHub create/update request body to Bitbucket format.
local function translate_bb_req(body_str)
  local req = DecodeJson(body_str or "{}")
  local bb = {}
  if req.name        then bb.name        = req.name end
  if req.description then bb.description = req.description end
  if req.private ~= nil then bb.is_private = req.private end
  if req.homepage    then bb.website     = req.homepage end
  if req.has_issues  ~= nil then bb.has_issues = req.has_issues end
  if req.has_wiki    ~= nil then bb.has_wiki   = req.has_wiki end
  return EncodeJson(bb)
end

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, base() .. "/user", auth())
    if ok and status == 200 then respond_json(200, "OK", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_emojis = function() respond_json(404, "Not Found", { message = "Not Found" }) end,

  get_repo = function(owner, repo_name)
    proxy_json(translate_bb_repo,
      fetch_json(base() .. "/repositories/" .. owner .. "/" .. repo_name))
  end,

  patch_repo = function(owner, repo_name)
    proxy_json(translate_bb_repo,
      fetch_json(base() .. "/repositories/" .. owner .. "/" .. repo_name,
        "PUT", translate_bb_req(GetBody())))
  end,

  delete_repo = function(owner, repo_name)
    local url = base() .. "/repositories/" .. owner .. "/" .. repo_name
    local dopts = auth() or {}; dopts.method = "DELETE"
    local ok, status = pcall(Fetch, url, dopts)
    if ok and status == 204 then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_user_repos = function()
    -- Bitbucket: list repos for authenticated user via /repositories?role=member
    proxy_json(
      function(data)
        local repos = data.values or {}
        for i, r in ipairs(repos) do repos[i] = translate_bb_repo(r) end
        return repos
      end,
      fetch_json(append_page_params(base() .. "/repositories?role=member",
        { per_page = "pagelen", page = "page" })))
  end,

  post_user_repos = function()
    -- Bitbucket requires workspace; use owner from token context — not directly available.
    -- Return 501 for now (no equivalent single endpoint).
    respond_json(501, "Not Implemented",
      { message = "POST /user/repos requires workspace context; use POST /orgs/{workspace}/repos" })
  end,

  get_org_repos = function(workspace)
    proxy_json(
      function(data)
        local repos = data.values or {}
        for i, r in ipairs(repos) do repos[i] = translate_bb_repo(r) end
        return repos
      end,
      fetch_json(append_page_params(base() .. "/repositories/" .. workspace,
        { per_page = "pagelen", page = "page" })))
  end,

  post_org_repos = function(workspace)
    -- Bitbucket: POST /2.0/repositories/{workspace}/{slug}
    local raw = GetBody() or "{}"
    local req = DecodeJson(raw)
    local slug = req.name
    if not slug then
      respond_json(422, "Unprocessable Entity", { message = "name required" }); return
    end
    proxy_json_created(translate_bb_repo,
      fetch_json(base() .. "/repositories/" .. workspace .. "/" .. slug,
        "POST", translate_bb_req(raw)))
  end,

  -- Bitbucket does not have a topics API.
  get_repo_topics = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  put_repo_topics = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  get_repo_languages = function(owner, repo_name)
    -- Bitbucket exposes primary language only via repo object; no language breakdown.
    proxy_json(
      function(r)
        local lang = r.language
        return lang and lang ~= "" and { [lang] = 0 } or {}
      end,
      fetch_json(base() .. "/repositories/" .. owner .. "/" .. repo_name))
  end,

  -- Bitbucket contributors are in /commits; no direct contributors list endpoint.
  get_repo_contributors = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,

  get_repo_tags = function(owner, repo_name)
    -- Bitbucket: { name, target: { hash, ... } }
    -- GitHub: { name, commit: { sha, url } }
    proxy_json(
      function(data)
        local tags = data.values or {}
        for i, t in ipairs(tags) do
          local tgt = t.target or {}
          tags[i] = { name = t.name, commit = { sha = tgt.hash or "", url = "" } }
        end
        return tags
      end,
      fetch_json(append_page_params(
        base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/refs/tags",
        { per_page = "pagelen", page = "page" })))
  end,

  get_repo_teams = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,
}
