-- GitLab backend handler overrides.
-- GitLab identifies projects by URL-encoded "namespace/path" as the project ID.

local base = function() return config.base_url .. "/api/v4" end
local auth = function() return make_fetch_opts("bearer") end

-- Encode owner/repo as GitLab project ID (URL-encoded "owner/repo").
local function project_id(owner, repo_name)
  -- Replace / with %2F and percent-encode other special chars.
  -- owner and repo_name come from the URL path so they contain no slashes.
  return owner .. "%2F" .. repo_name
end

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

-- Map a GitLab project object to GitHub repo format.
local function translate_gl_repo(p)
  if not p then return {} end
  local ns = p.namespace or {}
  local owner = {
    login      = ns.path or ns.name or "",
    id         = ns.id or 0,
    node_id    = "",
    avatar_url = ns.avatar_url or "",
    url        = "",
    html_url   = ns.web_url or "",
    type       = ns.kind == "group" and "Organization" or "User",
  }
  return {
    id                = p.id,
    node_id           = "",
    name              = p.path,
    full_name         = p.path_with_namespace,
    private           = p.visibility == "private",
    owner             = owner,
    html_url          = p.web_url,
    description       = p.description,
    fork              = (p.forked_from_project ~= nil),
    url               = p.web_url,
    ssh_url           = p.ssh_url_to_repo,
    clone_url         = p.http_url_to_repo,
    homepage          = p.web_url,
    size              = p.statistics and p.statistics.repository_size or 0,
    stargazers_count  = p.star_count or 0,
    watchers_count    = p.star_count or 0,
    language          = nil,
    has_issues        = p.issues_enabled,
    has_wiki          = p.wiki_enabled,
    forks_count       = p.forks_count or 0,
    archived          = p.archived,
    disabled          = false,
    open_issues_count = p.open_issues_count or 0,
    default_branch    = p.default_branch,
    visibility        = p.visibility or "public",
    forks             = p.forks_count or 0,
    open_issues       = p.open_issues_count or 0,
    watchers          = p.star_count or 0,
    created_at        = p.created_at,
    updated_at        = p.last_activity_at,
    pushed_at         = p.last_activity_at,
  }
end

-- Translate a GitLab create/update request body from GitHub format to GitLab.
local function translate_gl_req(body_str)
  local req = DecodeJson(body_str or "{}")
  local gl = {}
  if req.name        then gl.name        = req.name end
  if req.description then gl.description = req.description end
  if req.private ~= nil then
    gl.visibility = req.private and "private" or "public"
  end
  if req.homepage    then gl.web_url     = req.homepage end
  if req.has_issues  ~= nil then gl.issues_enabled = req.has_issues end
  if req.has_wiki    ~= nil then gl.wiki_enabled   = req.has_wiki end
  return EncodeJson(gl)
end

local function translate_gl_projects(projects)
  for i, p in ipairs(projects) do projects[i] = translate_gl_repo(p) end
  return projects
end

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, base() .. "/version", auth())
    if ok and status == 200 then respond_json(200, "OK", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_emojis = function() respond_json(404, "Not Found", { message = "Not Found" }) end,

  get_repo = function(owner, repo_name)
    proxy_json(translate_gl_repo,
      fetch_json(base() .. "/projects/" .. project_id(owner, repo_name)))
  end,

  patch_repo = function(owner, repo_name)
    proxy_json(translate_gl_repo,
      fetch_json(base() .. "/projects/" .. project_id(owner, repo_name),
        "PUT", translate_gl_req(GetBody())))
  end,

  delete_repo = function(owner, repo_name)
    local url = base() .. "/projects/" .. project_id(owner, repo_name)
    local dopts = auth() or {}; dopts.method = "DELETE"
    local ok, status = pcall(Fetch, url, dopts)
    -- GitLab returns 202 Accepted for async deletion
    if ok and (status == 202 or status == 204) then SetStatus(204, "No Content")
    elseif ok then respond_json(status, "Error", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,

  get_user_repos = function()
    -- GitLab: list projects owned by the authenticated user
    proxy_json(translate_gl_projects,
      fetch_json(append_page_params(base() .. "/projects?owned=true&membership=true",
        { per_page = "per_page", page = "page" })))
  end,

  post_user_repos = function()
    proxy_json_created(translate_gl_repo,
      fetch_json(base() .. "/projects", "POST", translate_gl_req(GetBody())))
  end,

  get_org_repos = function(org)
    -- GitLab: list projects in a group
    proxy_json(translate_gl_projects,
      fetch_json(append_page_params(base() .. "/groups/" .. org .. "/projects",
        { per_page = "per_page", page = "page" })))
  end,

  post_org_repos = function(org)
    local gl_req = translate_gl_req(GetBody())
    local gl = DecodeJson(gl_req)
    gl.namespace_id = org
    proxy_json_created(translate_gl_repo,
      fetch_json(base() .. "/projects", "POST", EncodeJson(gl)))
  end,

  get_repo_topics = function(owner, repo_name)
    proxy_json(
      function(p) return { names = p.topics or {} } end,
      fetch_json(base() .. "/projects/" .. project_id(owner, repo_name)))
  end,

  put_repo_topics = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
    proxy_json(
      function(p) return { names = p.topics or {} } end,
      fetch_json(base() .. "/projects/" .. project_id(owner, repo_name),
        "PUT", EncodeJson({ topics = req.names or {} })))
  end,

  get_repo_languages = function(owner, repo_name)
    -- GitLab returns { "Ruby": 66.69, "JavaScript": ... } (percentages, not bytes)
    -- GitHub returns { "Ruby": 12345 } (bytes). We pass through as-is — values differ.
    proxy_json(nil,
      fetch_json(base() .. "/projects/" .. project_id(owner, repo_name) .. "/languages"))
  end,

  get_repo_contributors = function(owner, repo_name)
    -- GitLab contributors are under /repository/contributors
    -- GitLab: [{ name, email, commits, additions, deletions }]
    -- GitHub: [{ login, contributions, ... }]
    proxy_json(
      function(contribs)
        for i, c in ipairs(contribs) do
          contribs[i] = { login = c.name, contributions = c.commits }
        end
        return contribs
      end,
      fetch_json(append_page_params(
        base() .. "/projects/" .. project_id(owner, repo_name) .. "/repository/contributors",
        { per_page = "per_page", page = "page" })))
  end,

  get_repo_tags = function(owner, repo_name)
    -- GitLab: [{ name, commit: { id, ... }, ... }]
    -- GitHub: [{ name, commit: { sha, url }, ... }]
    proxy_json(
      function(tags)
        for i, t in ipairs(tags) do
          local c = t.commit or {}
          tags[i] = { name = t.name, commit = { sha = c.id, url = "" } }
        end
        return tags
      end,
      fetch_json(append_page_params(
        base() .. "/projects/" .. project_id(owner, repo_name) .. "/repository/tags",
        { per_page = "per_page", page = "page" })))
  end,

  -- GitLab does not have a direct equivalent of GitHub's /teams endpoint for repos.
  get_repo_teams = function()
    respond_json(404, "Not Found", { message = "Not Found" })
  end,
}
