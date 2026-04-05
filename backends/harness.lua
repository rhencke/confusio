-- Harness Code backend handler overrides.
-- Uses Harness Code (Gitness) REST API via /gateway/code/api/v1/.
-- repo_ref is owner/repo URL-encoded as owner%2Frepo.
if config.base_url == "" then
  config.base_url = "https://app.harness.io"
end

local base = function()
  return config.base_url .. "/gateway/code/api/v1"
end
local auth = function()
  return make_fetch_opts("bearer")
end
local PAGES = { per_page = "limit", page = "page" }

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
  if not r then
    return {}
  end
  local path = r.path or ""
  -- path is like "space/reponame"; split on last /
  local owner_part, name_part = path:match("^(.+)/([^/]+)$")
  if not owner_part then
    owner_part = ""
    name_part = path
  end
  return {
    id = r.id or 0,
    node_id = "",
    name = name_part,
    full_name = path,
    private = not r.is_public,
    owner = {
      login = owner_part,
      id = 0,
      node_id = "",
      avatar_url = "",
      url = "",
      html_url = "",
      type = "User",
    },
    html_url = config.base_url .. "/" .. path,
    description = r.description,
    fork = r.fork_id ~= nil and r.fork_id > 0,
    url = "",
    clone_url = r.git_url or "",
    homepage = "",
    size = r.size or 0,
    stargazers_count = r.num_stars or 0,
    watchers_count = 0,
    language = nil,
    has_issues = true,
    has_wiki = false,
    forks_count = r.num_forks or 0,
    archived = false,
    disabled = false,
    open_issues_count = 0,
    default_branch = r.default_branch or "main",
    visibility = r.is_public and "public" or "private",
    forks = r.num_forks or 0,
    open_issues = 0,
    watchers = 0,
    created_at = r.created and tostring(r.created) or nil,
    updated_at = r.updated and tostring(r.updated) or nil,
    pushed_at = r.updated and tostring(r.updated) or nil,
  }
end

-- Translate GitHub create/update request body to Harness Code format.
local function translate_harness_req(body_str)
  local req = DecodeJson(body_str or "{}")
  local h = {}
  if req.name then
    h.identifier = req.name
  end
  if req.description then
    h.description = req.description
  end
  if req.private ~= nil then
    h.is_public = not req.private
  end
  if req.default_branch then
    h.default_branch = req.default_branch
  end
  return EncodeJson(h)
end

local function translate_harness_repos(repos)
  repos = repos or {}
  for i, r in ipairs(repos) do
    repos[i] = translate_harness_repo(r)
  end
  return repos
end

-- Translate a Harness branch object to GitHub format.
-- Harness: { name, sha, is_default }
local function translate_harness_branch(b)
  if not b then
    return {}
  end
  return {
    name = b.name,
    commit = { sha = b.sha or "", url = "" },
    protected = false,
  }
end

-- Translate a Harness commit to GitHub format.
-- Harness: { sha, message, author: { identity: { name, email }, when }, committer: {...}, parent_shas }
local function translate_harness_commit(c)
  if not c then
    return {}
  end
  local author = c.author or {}
  local ident = author.identity or {}
  local committer = c.committer or {}
  local cident = committer.identity or {}
  return {
    sha = c.sha or "",
    commit = {
      message = c.message or "",
      author = { name = ident.name or "", email = ident.email or "", date = author.when or "" },
      committer = {
        name = cident.name or "",
        email = cident.email or "",
        date = committer.when or "",
      },
    },
    author = { login = ident.name or "", id = 0, avatar_url = "" },
    committer = { login = cident.name or "", id = 0, avatar_url = "" },
  }
end

-- Translate a Harness deploy key to GitHub format.
-- Harness: { id, identifier, public_key, created, usage }
local function translate_harness_key(k)
  if not k then
    return {}
  end
  return {
    id = k.id or 0,
    key = k.public_key or "",
    title = k.identifier or "",
    verified = true,
    created_at = k.created and tostring(k.created) or nil,
    url = "",
    read_only = k.usage == "read",
  }
end

-- Translate a Harness webhook to GitHub format.
-- Harness: { id, identifier, url, enabled, triggers: [...] }
local function translate_harness_hook(h)
  if not h then
    return {}
  end
  return {
    id = h.id or 0,
    name = "web",
    active = h.enabled or false,
    events = h.triggers or {},
    config = { url = h.url or "", content_type = "json" },
    created_at = h.created and tostring(h.created) or nil,
    updated_at = h.updated and tostring(h.updated) or nil,
  }
end

-- Translate GitHub webhook request to Harness format.
local proxy_handler = make_proxy_handler(fetch_json)

local function translate_harness_hook_req(body_str)
  local req = DecodeJson(body_str or "{}")
  local cfg = req.config or {}
  return EncodeJson({
    identifier = req.name or "web",
    url = cfg.url or "",
    enabled = req.active ~= false,
    triggers = req.events or {},
  })
end

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, base(), auth())
    if ok and status == 200 then
      respond_json(200, "OK", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  get_repo = proxy_handler(translate_harness_repo, function(owner, repo_name)
    return base() .. "/repos/" .. repo_ref(owner, repo_name)
  end),

  patch_repo = function(owner, repo_name)
    proxy_json(
      translate_harness_repo,
      fetch_json(
        base() .. "/repos/" .. repo_ref(owner, repo_name),
        "PATCH",
        translate_harness_req(GetBody())
      )
    )
  end,

  delete_repo = function(owner, repo_name)
    local url = base() .. "/repos/" .. repo_ref(owner, repo_name)
    local dopts = auth() or {}
    dopts.method = "DELETE"
    local ok, status = pcall(Fetch, url, dopts)
    if ok and (status == 204 or status == 200) then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  get_user_repos = proxy_handler(translate_harness_repos, function()
    return append_page_params(base() .. "/repos", PAGES)
  end),

  post_user_repos = function()
    proxy_json_created(
      translate_harness_repo,
      fetch_json(base() .. "/repos", "POST", translate_harness_req(GetBody()))
    )
  end,

  get_org_repos = proxy_handler(translate_harness_repos, function(space)
    return append_page_params(base() .. "/spaces/" .. space .. "/repos", PAGES)
  end),

  post_org_repos = function(space)
    local req = DecodeJson(GetBody() or "{}")
    req.parent_ref = space
    proxy_json_created(
      translate_harness_repo,
      fetch_json(base() .. "/repos", "POST", EncodeJson(req))
    )
  end,

  -- GET /repos/{owner}/{repo}/tags
  get_repo_tags = function(owner, repo_name)
    proxy_json(
      function(tags)
        tags = tags or {}
        for i, t in ipairs(tags) do
          tags[i] = { name = t.name, commit = { sha = t.sha or t.target or "", url = "" } }
        end
        return tags
      end,
      fetch_json(
        append_page_params(base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/tags", PAGES)
      )
    )
  end,

  -- Branches ------------------------------------------------------------------

  get_repo_branches = function(owner, repo_name)
    proxy_json(
      function(branches)
        branches = branches or {}
        for i, b in ipairs(branches) do
          branches[i] = translate_harness_branch(b)
        end
        return branches
      end,
      fetch_json(
        append_page_params(base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/branches", PAGES)
      )
    )
  end,

  get_repo_branch = proxy_handler(translate_harness_branch, function(owner, repo_name, branch)
    return base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/branches/" .. branch
  end),

  -- Commits -------------------------------------------------------------------

  get_repo_commits = function(owner, repo_name)
    local ref = GetParam("sha") or ""
    local url = base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/commits"
    if ref ~= "" then
      url = url .. "?git_ref=" .. ref
    end
    url = append_page_params(url, PAGES)
    proxy_json(function(commits)
      commits = commits or {}
      for i, c in ipairs(commits) do
        commits[i] = translate_harness_commit(c)
      end
      return commits
    end, fetch_json(url))
  end,

  get_repo_commit = proxy_handler(translate_harness_commit, function(owner, repo_name, ref)
    return base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/commits/" .. ref
  end),

  -- Statuses ------------------------------------------------------------------
  -- Harness uses /check/commits/{sha} for CI results.

  get_commit_statuses = proxy_handler(nil, function(owner, repo_name, ref)
    return base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/check/commits/" .. ref
  end),

  get_commit_combined_status = proxy_handler(nil, function(owner, repo_name, ref)
    return base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/check/commits/" .. ref
  end),

  post_commit_status = function(owner, repo_name, sha)
    proxy_json_created(
      nil,
      fetch_json(
        base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/check/commits/" .. sha,
        "POST",
        GetBody()
      )
    )
  end,

  -- Contents ------------------------------------------------------------------
  -- Harness content API returns the same shape as GitHub (type, name, path, sha, encoding, content).

  get_repo_readme = function(owner, repo_name)
    -- Harness has no dedicated readme endpoint; fetch root contents and find README.
    local ref = GetParam("ref") or ""
    local url = base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/content/README.md"
    if ref ~= "" then
      url = url .. "?git_ref=" .. ref
    end
    proxy_json(nil, fetch_json(url))
  end,

  get_repo_content = function(owner, repo_name, path)
    local ref = GetParam("ref") or ""
    local url = base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/content/" .. path
    if ref ~= "" then
      url = url .. "?git_ref=" .. ref
    end
    proxy_json(function(data)
      -- Directory listing: Harness returns { type="dir", entries=[...] }; GitHub expects array.
      if data and data.type == "dir" then
        return data.entries or {}
      end
      return data or {}
    end, fetch_json(url))
  end,

  put_repo_content = function(owner, repo_name, path)
    proxy_json(
      nil,
      fetch_json(
        base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/content/" .. path,
        "PUT",
        GetBody()
      )
    )
  end,

  delete_repo_content = function(owner, repo_name, path)
    proxy_json(
      nil,
      fetch_json(
        base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/content/" .. path,
        "DELETE",
        GetBody()
      )
    )
  end,

  -- Forks ---------------------------------------------------------------------

  get_repo_forks = proxy_handler(translate_harness_repos, function(owner, repo_name)
    return append_page_params(base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/forks", PAGES)
  end),

  post_repo_forks = function(owner, repo_name)
    proxy_json_created(
      translate_harness_repo,
      fetch_json(base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/fork", "POST", GetBody())
    )
  end,

  -- Deploy keys ---------------------------------------------------------------

  get_repo_keys = function(owner, repo_name)
    proxy_json(
      function(keys)
        keys = keys or {}
        for i, k in ipairs(keys) do
          keys[i] = translate_harness_key(k)
        end
        return keys
      end,
      fetch_json(
        append_page_params(base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/keys", PAGES)
      )
    )
  end,

  post_repo_keys = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
    local h = {
      identifier = req.title or "",
      public_key = req.key or "",
      usage = req.read_only and "read" or "readwrite",
    }
    proxy_json_created(
      translate_harness_key,
      fetch_json(
        base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/keys",
        "POST",
        EncodeJson(h)
      )
    )
  end,

  get_repo_key = proxy_handler(translate_harness_key, function(owner, repo_name, key_id)
    return base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/keys/" .. key_id
  end),

  delete_repo_key = function(owner, repo_name, key_id)
    local ok, status =
      fetch_json(base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/keys/" .. key_id, "DELETE")
    if ok and (status == 204 or status == 200) then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- Webhooks ------------------------------------------------------------------

  get_repo_hooks = function(owner, repo_name)
    proxy_json(
      function(hooks)
        hooks = hooks or {}
        for i, h in ipairs(hooks) do
          hooks[i] = translate_harness_hook(h)
        end
        return hooks
      end,
      fetch_json(
        append_page_params(base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/webhooks", PAGES)
      )
    )
  end,

  post_repo_hooks = function(owner, repo_name)
    proxy_json_created(
      translate_harness_hook,
      fetch_json(
        base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/webhooks",
        "POST",
        translate_harness_hook_req(GetBody())
      )
    )
  end,

  get_repo_hook = proxy_handler(translate_harness_hook, function(owner, repo_name, hook_id)
    return base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/webhooks/" .. hook_id
  end),

  patch_repo_hook = function(owner, repo_name, hook_id)
    proxy_json(
      translate_harness_hook,
      fetch_json(
        base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/webhooks/" .. hook_id,
        "PATCH",
        translate_harness_hook_req(GetBody())
      )
    )
  end,

  delete_repo_hook = function(owner, repo_name, hook_id)
    local ok, status = fetch_json(
      base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/webhooks/" .. hook_id,
      "DELETE"
    )
    if ok and (status == 204 or status == 200) then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- Hook config ---------------------------------------------------------------

  get_repo_hook_config = function(owner, repo_name, hook_id)
    proxy_json(function(h)
      return (translate_harness_hook(h)).config or {}
    end, fetch_json(
      base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/webhooks/" .. hook_id
    ))
  end,

  patch_repo_hook_config = function(owner, repo_name, hook_id)
    local url = base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/webhooks/" .. hook_id
    local ok, status, _, body = fetch_json(url)
    if not ok or status ~= 200 then
      if ok then
        respond_json(status, "Error", {})
      else
        respond_json(503, "Service Unavailable", {})
      end
      return
    end
    local hook = DecodeJson(body) or {}
    local new_cfg = DecodeJson(GetBody() or "{}")
    if new_cfg.url then
      hook.url = new_cfg.url
    end
    proxy_json(function(h)
      return (translate_harness_hook(h)).config or {}
    end, fetch_json(url, "PATCH", EncodeJson(hook)))
  end,

  post_repo_hook_test = function(owner, repo_name, hook_id)
    local ok, status = fetch_json(
      base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/webhooks/" .. hook_id .. "/test",
      "POST"
    )
    if ok and (status == 204 or status == 200) then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, "Error", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- Languages -----------------------------------------------------------------

  get_repo_languages = proxy_handler(nil, function(owner, repo_name)
    return base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/languages"
  end),

  -- Archive -------------------------------------------------------------------

  get_repo_tarball = function(owner, repo_name, ref)
    SetStatus(302, "Found")
    SetHeader(
      "Location",
      base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/archive?format=tar.gz&git_ref=" .. ref
    )
    Write("")
  end,

  get_repo_zipball = function(owner, repo_name, ref)
    SetStatus(302, "Found")
    SetHeader(
      "Location",
      base() .. "/repos/" .. repo_ref(owner, repo_name) .. "/archive?format=zip&git_ref=" .. ref
    )
    Write("")
  end,

  -- Users' repos --------------------------------------------------------------

  get_users_repos = proxy_handler(translate_harness_repos, function(username)
    return append_page_params(base() .. "/spaces/" .. username .. "/repos", PAGES)
  end),

  -- Users ---------------------------------------------------------------------

  -- GET /user
  get_user = function()
    proxy_json(function(u)
      if not u then
        return {}
      end
      return {
        login = u.uid or "",
        id = u.id or 0,
        node_id = "",
        avatar_url = u.url or "",
        html_url = "",
        type = "User",
        site_admin = u.admin or false,
        name = u.display_name or "",
        email = u.email or "",
      }
    end, fetch_json(base() .. "/user"))
  end,

  -- PATCH /user
  patch_user = function()
    proxy_json(function(u)
      if not u then
        return {}
      end
      return {
        login = u.uid or "",
        id = u.id or 0,
        node_id = "",
        avatar_url = u.url or "",
        html_url = "",
        type = "User",
        site_admin = u.admin or false,
        name = u.display_name or "",
        email = u.email or "",
      }
    end, fetch_json(base() .. "/user", "PATCH", GetBody()))
  end,
}
