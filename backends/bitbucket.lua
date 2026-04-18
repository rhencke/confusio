-- Bitbucket backend handler overrides.
-- Uses Bitbucket REST API v2 at /2.0/.
if config.base_url == "" then
  config.base_url = "https://api.bitbucket.org"
end

local base = function()
  return config.base_url .. "/2.0"
end
local auth = function()
  return make_fetch_opts("basic")
end
local PAGES = { per_page = "pagelen", page = "page" }
local _t = make_backend_transport("basic", PAGES)
local fetch_json = _t.fetch_json
local proxy_handler = _t.proxy_handler

-- Map a Bitbucket repository object to GitHub format.
local function translate_bb_repo(r)
  if not r then
    return {}
  end
  local owner = r.owner or {}
  local main = r.mainbranch or {}
  return {
    id = 0,
    node_id = r.uuid or "",
    name = r.slug or r.name,
    full_name = r.full_name,
    private = r.is_private,
    owner = {
      login = owner.nickname or owner.display_name or "",
      id = 0,
      node_id = owner.uuid or "",
      avatar_url = (owner.links and owner.links.avatar and owner.links.avatar.href) or "",
      url = "",
      html_url = (owner.links and owner.links.html and owner.links.html.href) or "",
      type = owner.type == "team" and "Organization" or "User",
    },
    html_url = (r.links and r.links.html and r.links.html.href) or "",
    description = r.description,
    fork = r.parent ~= nil,
    url = (r.links and r.links.self and r.links.self.href) or "",
    clone_url = "",
    homepage = r.website or "",
    size = r.size or 0,
    stargazers_count = 0,
    watchers_count = 0,
    language = r.language,
    has_issues = r.has_issues,
    has_wiki = r.has_wiki,
    forks_count = 0,
    archived = false,
    disabled = false,
    open_issues_count = 0,
    default_branch = main.name or "main",
    visibility = r.is_private and "private" or "public",
    forks = 0,
    open_issues = 0,
    watchers = 0,
    created_at = r.created_on,
    updated_at = r.updated_on,
    pushed_at = r.updated_on,
  }
end

-- Translate GitHub create/update request body to Bitbucket format.
-- Map a Bitbucket user object to GitHub format.
local function translate_bb_user(u)
  if not u then
    return {}
  end
  local links = u.links or {}
  return {
    login = u.nickname or u.display_name or "",
    id = 0,
    node_id = u.account_id or "",
    avatar_url = (links.avatar and links.avatar.href) or "",
    html_url = (links.html and links.html.href) or "",
    type = "User",
    site_admin = false,
    name = u.display_name,
  }
end

-- Map a Bitbucket workspace object to GitHub user format (used for user search).
local function translate_bb_workspace(w)
  if not w then
    return {}
  end
  local links = w.links or {}
  return {
    login = w.slug or "",
    id = 0,
    node_id = w.uuid or "",
    avatar_url = (links.avatar and links.avatar.href) or "",
    html_url = (links.html and links.html.href) or "",
    type = "User",
    site_admin = false,
    name = w.name,
  }
end

-- Proxy a Bitbucket paginated response {"values":[...],"size":N,...} to the
-- GitHub search envelope {"total_count":N,"incomplete_results":false,"items":[...]}.
local function proxy_search_bb(translate_item, url)
  local ok, status, _, body = fetch_json(url)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local raw = DecodeJson(body) or {}
  local items = {}
  for i, item in ipairs(raw.values or {}) do
    items[i] = translate_item(item)
  end
  set_preamble()
  Write(
    '{"total_count":'
      .. #items
      .. ',"incomplete_results":false,"items":'
      .. (#items > 0 and EncodeJson(items) or "[]")
      .. "}"
  )
end

local function translate_bb_req(body_str)
  local req = DecodeJson(body_str or "{}")
  local bb = {}
  if req.name then
    bb.name = req.name
  end
  if req.description then
    bb.description = req.description
  end
  if req.private ~= nil then
    bb.is_private = req.private
  end
  if req.homepage then
    bb.website = req.homepage
  end
  if req.has_issues ~= nil then
    bb.has_issues = req.has_issues
  end
  if req.has_wiki ~= nil then
    bb.has_wiki = req.has_wiki
  end
  return EncodeJson(bb)
end

local function translate_bb_commit(c)
  if not c then
    return {}
  end
  local author = c.author or {}
  local user = author.user or {}
  local parents = {}
  for _, p in ipairs(c.parents or {}) do
    parents[#parents + 1] = { sha = p.hash or "" }
  end
  return {
    sha = c.hash or "",
    commit = {
      message = c.message or "",
      author = {
        name = user.display_name or author.raw or "",
        email = "",
        date = c.date or "",
      },
      committer = {
        name = user.display_name or author.raw or "",
        email = "",
        date = c.date or "",
      },
    },
    author = { login = user.nickname or "", id = 0 },
    committer = { login = user.nickname or "", id = 0 },
    parents = parents,
  }
end

local BB_TO_GITHUB_STATE = { SUCCESSFUL = "success", FAILED = "failure", INPROGRESS = "pending" }
local function bb_state_to_github(state)
  return BB_TO_GITHUB_STATE[state] or "error"
end

local GITHUB_TO_BB_STATE = { success = "SUCCESSFUL", failure = "FAILED", pending = "INPROGRESS" }
local function github_state_to_bb(state)
  return GITHUB_TO_BB_STATE[state] or "FAILED"
end

local function translate_bb_status(s)
  return {
    state = bb_state_to_github(s.state),
    context = s.key or "",
    description = s.description or "",
    target_url = s.url or "",
    created_at = s.created_on or "",
    updated_at = s.updated_on or "",
  }
end

local function translate_bb_key(k)
  return {
    id = k.id or 0,
    key = k.key or "",
    title = k.label or "",
    read_only = true,
    verified = true,
    created_at = k.created_on or "",
  }
end

local function translate_bb_hook(h)
  local events = {}
  for _, e in ipairs(h.events or {}) do
    -- "repo:push" → "push", "pullrequest:created" → "pull_request"
    events[#events + 1] = (e:match(":(.+)$") or e):gsub("_", ".")
  end
  return {
    id = h.uuid and h.uuid:gsub("[{}]", "") or "",
    config = { url = h.url or "", content_type = "json" },
    events = events,
    active = h.active ~= false,
  }
end

-- Map a Bitbucket pull request branch ref to GitHub format.
local function translate_bb_pr_branch(ref)
  if not ref then
    return {}
  end
  local branch = ref.branch or {}
  local commit = ref.commit or {}
  local repo = ref.repository or {}
  return {
    label = repo.full_name and (repo.full_name .. ":" .. (branch.name or ""))
      or (branch.name or ""),
    ref = branch.name or "",
    sha = commit.hash or "",
  }
end

-- Map a Bitbucket pull request object to GitHub format.
local function translate_bb_pull(pr)
  if not pr then
    return {}
  end
  local state = pr.state
  local is_merged = state == "MERGED"
  local gh_state = state == "OPEN" and "open" or "closed"
  local merge_commit = pr.merge_commit or {}
  -- Find merged_by from participant with role AUTHOR only if merged; Bitbucket
  -- doesn't expose a dedicated merged_by field, so use closed_by if present.
  local closed_by = pr.closed_by
  return {
    id = pr.id or 0,
    node_id = "",
    number = pr.id or 0,
    state = gh_state,
    locked = false,
    title = pr.title or "",
    body = pr.description or "",
    user = translate_bb_user(pr.author),
    head = translate_bb_pr_branch(pr.source),
    base = translate_bb_pr_branch(pr.destination),
    draft = false,
    created_at = pr.created_on or "",
    updated_at = pr.updated_on or "",
    closed_at = (not is_merged and gh_state == "closed") and (pr.updated_on or "") or nil,
    merged_at = is_merged and (pr.updated_on or "") or nil,
    merge_commit_sha = merge_commit.hash or nil,
    merged_by = (is_merged and closed_by) and translate_bb_user(closed_by) or nil,
    html_url = (pr.links and pr.links.html and pr.links.html.href) or "",
    url = (pr.links and pr.links.self and pr.links.self.href) or "",
    diff_url = (pr.links and pr.links.diff and pr.links.diff.href) or "",
    patch_url = "",
    mergeable = state == "OPEN" or nil,
    comments = 0,
    review_comments = 0,
    commits = 0,
    additions = 0,
    deletions = 0,
    changed_files = 0,
    participants = nil,
  }
end

local function translate_bb_pulls(data)
  local prs = data.values or {}
  for i, pr in ipairs(prs) do
    prs[i] = translate_bb_pull(pr)
  end
  return prs
end

-- Map a Bitbucket diffstat entry to GitHub file format.
local function translate_bb_diffstat_file(f)
  if not f then
    return {}
  end
  local status = f.status or "modified"
  -- Bitbucket statuses: "added", "removed", "modified", "renamed"
  local new_file = f.new or {}
  local old_file = f.old or {}
  return {
    sha = "",
    filename = new_file.path or old_file.path or "",
    status = status,
    additions = f.lines_added or 0,
    deletions = f.lines_removed or 0,
    changes = (f.lines_added or 0) + (f.lines_removed or 0),
    patch = "",
  }
end

-- Map a Bitbucket PR comment (with inline position) to GitHub review comment format.
local function translate_bb_pr_comment(c)
  if not c then
    return {}
  end
  local content = (c.content or {}).raw or ""
  local inline = c.inline or {}
  return {
    id = c.id or 0,
    node_id = "",
    path = inline.path or "",
    position = inline.to or inline.from,
    original_position = inline.from,
    commit_id = "",
    original_commit_id = "",
    diff_hunk = "",
    body = content,
    user = translate_bb_user(c.user or c.author),
    created_at = c.created_on or "",
    updated_at = c.updated_on or "",
    html_url = (c.links and c.links.html and c.links.html.href) or "",
    pull_request_url = "",
    url = "",
  }
end

-- Map Bitbucket PR participants with REVIEWER role to GitHub reviews format.
local function translate_bb_participants_to_reviews(participants)
  local result = {}
  local idx = 0
  for _, p in ipairs(participants or {}) do
    if p.role == "REVIEWER" and p.approved then
      idx = idx + 1
      result[idx] = {
        id = idx,
        node_id = "",
        user = translate_bb_user(p.user),
        body = "",
        state = "APPROVED",
        submitted_at = p.participated_on or "",
        html_url = "",
        pull_request_url = "",
      }
    end
  end
  return result
end

-- Translate a Bitbucket issue to GitHub format.
-- Bitbucket states: "open", "resolved", "wontfix", "invalid", "duplicate", "on hold", "closed"
local function translate_bb_issue(i)
  if not i then
    return {}
  end
  local content = (i.content or {}).raw or ""
  local state = (i.state == "open") and "open" or "closed"
  local reporter = translate_bb_user(i.reporter)
  local assignees = {}
  if i.assignee then
    assignees[1] = translate_bb_user(i.assignee)
  end
  local ms = nil
  if i.milestone and i.milestone.name then
    ms = {
      id = i.milestone.id or 0,
      number = i.milestone.id or 0,
      title = i.milestone.name,
      state = "open",
      created_at = "",
      updated_at = "",
    }
  end
  return {
    id = i.id or 0,
    number = i.id or 0,
    title = i.title or "",
    body = content,
    state = state,
    user = reporter,
    assignees = assignees,
    labels = {},
    milestone = ms,
    created_at = i.created_on or "",
    updated_at = i.updated_on or "",
    closed_at = nil,
    html_url = (i.links and i.links.html and i.links.html.href) or "",
  }
end

-- Translate a Bitbucket issue comment to GitHub format.
local function translate_bb_issue_comment(c)
  if not c then
    return {}
  end
  local content = (c.content or {}).raw or ""
  return {
    id = c.id or 0,
    body = content,
    user = translate_bb_user(c.author),
    created_at = c.created_on or "",
    updated_at = c.updated_on or "",
    html_url = (c.links and c.links.html and c.links.html.href) or "",
  }
end

-- Translate a Bitbucket milestone to GitHub format.
-- Bitbucket milestone: { id, name, resource_uri }
local function translate_bb_milestone(m)
  if not m then
    return {}
  end
  return {
    id = m.id or 0,
    number = m.id or 0,
    title = m.name or "",
    state = "open",
    created_at = "",
    updated_at = "",
  }
end

local function translate_bb_issues(data)
  local issues = data.values or {}
  for i, iss in ipairs(issues) do
    issues[i] = translate_bb_issue(iss)
  end
  return issues
end
local function translate_bb_issue_comments_list(data)
  local comments = data.values or {}
  for i, c in ipairs(comments) do
    comments[i] = translate_bb_issue_comment(c)
  end
  return comments
end
local function translate_bb_milestones(data)
  local ms = data.values or {}
  for i, m in ipairs(ms) do
    ms[i] = translate_bb_milestone(m)
  end
  return ms
end

local function translate_bb_hook_req(body_str)
  local req = DecodeJson(body_str or "{}")
  local bb_events = {}
  for _, e in ipairs(req.events or {}) do
    bb_events[#bb_events + 1] = "repo:" .. e
  end
  return EncodeJson({
    description = (req.config and req.config.url) or req.url or "",
    url = (req.config and req.config.url) or req.url or "",
    active = req.active ~= false,
    events = #bb_events > 0 and bb_events or { "repo:push" },
  })
end

local function translate_bb_ref(r)
  local ref_type = r.type == "tag" and "tags" or "heads"
  local sha = (r.target and r.target.hash) or ""
  return {
    ref = "refs/" .. ref_type .. "/" .. (r.name or ""),
    node_id = "",
    url = "",
    object = { type = "commit", sha = sha, url = "" },
  }
end

-- Gist helpers ---------------------------------------------------------------

-- Translate a Bitbucket snippet object to GitHub gist format.
-- Files include only metadata (raw_url, size); content is not eagerly fetched.
-- gist.id encodes "workspace~encoded_id" for round-trip decoding.
local function translate_bb_snippet(s)
  if not s then
    return {}
  end
  local owner = s.owner or {}
  local ws = owner.nickname or owner.display_name or ""
  local files = {}
  for name, f in pairs(s.files or {}) do
    files[name] = {
      filename = name,
      type = f.mimetype or "text/plain",
      language = nil,
      raw_url = (f.links and f.links.self and f.links.self.href) or "",
      size = f.size or 0,
      truncated = false,
    }
  end
  return {
    id = ws .. "~" .. tostring(s.id or ""),
    node_id = "",
    url = "",
    html_url = (s.links and s.links.html and s.links.html.href) or "",
    files = files,
    public = not (s.is_private or false),
    created_at = s.created_on or "",
    updated_at = s.updated_on or "",
    description = s.title or "",
    comments = 0,
    user = nil,
    owner = {
      login = ws,
      id = 0,
      node_id = owner.uuid or "",
      avatar_url = (owner.links and owner.links.avatar and owner.links.avatar.href) or "",
      url = "",
      html_url = "",
      type = "User",
    },
    truncated = false,
  }
end

-- Translate a paginated Bitbucket snippet list to a GitHub gist array.
local function translate_bb_snippets(data)
  local result = {}
  for i, s in ipairs(data.values or {}) do
    result[i] = translate_bb_snippet(s)
  end
  return result
end

-- Translate a Bitbucket snippet comment to GitHub gist comment format.
local function translate_bb_snippet_comment(c)
  if not c then
    return {}
  end
  local author = c.author or {}
  local content = c.content or {}
  return {
    id = c.id or 0,
    node_id = "",
    url = "",
    body = content.raw or "",
    user = {
      login = author.nickname or author.display_name or "",
      id = 0,
      node_id = author.uuid or "",
      avatar_url = (author.links and author.links.avatar and author.links.avatar.href) or "",
      url = "",
      html_url = "",
      type = "User",
    },
    created_at = c.created_on or "",
    updated_at = c.updated_on or "",
  }
end

-- Translate a paginated Bitbucket snippet comment list.
local function translate_bb_snippet_comments(data)
  local result = {}
  for i, c in ipairs(data.values or {}) do
    result[i] = translate_bb_snippet_comment(c)
  end
  return result
end

-- Translate a paginated Bitbucket snippet commit list to GitHub gist commit format.
local function translate_bb_snippet_commits(data)
  local result = {}
  for i, c in ipairs(data.values or {}) do
    local author = c.author or {}
    local user = author.user or {}
    result[i] = {
      url = "",
      version = c.hash or "",
      user = {
        login = user.nickname or user.display_name or "",
        id = 0,
        node_id = user.uuid or "",
        avatar_url = (user.links and user.links.avatar and user.links.avatar.href) or "",
        url = "",
        html_url = "",
        type = "User",
      },
      committed_at = c.date or "",
      change_status = { total = 0, additions = 0, deletions = 0 },
    }
  end
  return result
end

-- Decode a GitHub gist ID (from a confusio response) back to Bitbucket workspace
-- and encoded_id.  Returns nil, nil if gist_id is not in "workspace~encoded_id" form.
local function gist_id_split(gist_id)
  return gist_id:match("^([^~]+)~(.+)$")
end

-- Build the Bitbucket snippets base URL for a split gist_id, or respond 404
-- and return nil if gist_id is malformed.
local function snippet_url(gist_id)
  local ws, eid = gist_id_split(gist_id)
  if not ws then
    respond_json(404, { message = "Not Found" })
    return nil
  end
  return base() .. "/snippets/" .. ws .. "/" .. eid
end

local b = make_backend_builder()
b:rest("get_root", function()
  proxy_health_check(pcall(Fetch, base() .. "/user", auth()))
end)

b:rest(
  "get_repo",
  proxy_handler(translate_bb_repo, function(o, r)
    return base() .. "/repositories/" .. o .. "/" .. r
  end)
)

b:rest("patch_repo", function(owner, repo_name)
  proxy_json(
    translate_bb_repo,
    fetch_json(
      base() .. "/repositories/" .. owner .. "/" .. repo_name,
      "PUT",
      translate_bb_req(GetBody())
    )
  )
end)

b:rest("delete_repo", function(owner, repo_name)
  local url = base() .. "/repositories/" .. owner .. "/" .. repo_name
  local dopts = auth() or {}
  dopts.method = "DELETE"
  proxy_204(nil, pcall(Fetch, url, dopts))
end)

b:rest("get_user_repos", function()
  -- Bitbucket: list repos for authenticated user via /repositories?role=member
  proxy_json(function(data)
    local repos = data.values or {}
    for i, r in ipairs(repos) do
      repos[i] = translate_bb_repo(r)
    end
    return repos
  end, fetch_json(append_page_params(base() .. "/repositories?role=member", PAGES)))
end)

b:rest("post_user_repos", function()
  -- Bitbucket requires workspace; no equivalent single endpoint.
  respond_json(
    501,
    "Not Implemented",
    { message = "POST /user/repos requires workspace context; use POST /orgs/{workspace}/repos" }
  )
end)

b:rest("get_org_repos", function(workspace)
  proxy_json(function(data)
    local repos = data.values or {}
    for i, r in ipairs(repos) do
      repos[i] = translate_bb_repo(r)
    end
    return repos
  end, fetch_json(append_page_params(base() .. "/repositories/" .. workspace, PAGES)))
end)

b:rest("post_org_repos", function(workspace)
  local raw = GetBody() or "{}"
  local req = DecodeJson(raw)
  local slug = req.name
  if not slug then
    respond_json(422, { message = "name required" })
    return
  end
  proxy_json_created(
    translate_bb_repo,
    fetch_json(
      base() .. "/repositories/" .. workspace .. "/" .. slug,
      "POST",
      translate_bb_req(raw)
    )
  )
end)

-- GET /users/{username}/repos
b:rest("get_users_repos", function(username)
  proxy_json(function(data)
    local repos = data.values or {}
    for i, r in ipairs(repos) do
      repos[i] = translate_bb_repo(r)
    end
    return repos
  end, fetch_json(append_page_params(base() .. "/repositories/" .. username, PAGES)))
end)

-- GET /repositories (public)
b:rest("get_repositories", function()
  proxy_json(function(data)
    local repos = data.values or {}
    for i, r in ipairs(repos) do
      repos[i] = translate_bb_repo(r)
    end
    return repos
  end, fetch_json(append_page_params(base() .. "/repositories", PAGES)))
end)

b:rest("get_repo_languages", function(owner, repo_name)
  -- Bitbucket exposes primary language only via repo object; no language breakdown.
  proxy_json(function(r)
    local lang = r.language
    return lang and lang ~= "" and { [lang] = 0 } or {}
  end, fetch_json(base() .. "/repositories/" .. owner .. "/" .. repo_name))
end)

b:rest("get_repo_tags", function(owner, repo_name)
  proxy_json(
    function(data)
      local tags = data.values or {}
      for i, t in ipairs(tags) do
        local tgt = t.target or {}
        tags[i] = { name = t.name, commit = { sha = tgt.hash or "", url = "" } }
      end
      return tags
    end,
    fetch_json(
      append_page_params(
        base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/refs/tags",
        PAGES
      )
    )
  )
end)

-- Branches ------------------------------------------------------------------

b:rest("get_repo_branches", function(owner, repo_name)
  proxy_json(
    function(data)
      local branches = data.values or {}
      for i, br in ipairs(branches) do
        branches[i] = {
          name = br.name,
          commit = { sha = (br.target and br.target.hash) or "", url = "" },
          protected = false,
        }
      end
      return branches
    end,
    fetch_json(
      append_page_params(
        base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/refs/branches",
        PAGES
      )
    )
  )
end)

b:rest("get_repo_branch", function(owner, repo_name, branch)
  proxy_json(
    function(br)
      return {
        name = br.name,
        commit = { sha = (br.target and br.target.hash) or "", url = "" },
        protected = false,
      }
    end,
    fetch_json(
      base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/refs/branches/" .. branch
    )
  )
end)

-- Commits -------------------------------------------------------------------

b:rest("get_repo_commits", function(owner, repo_name)
  proxy_json(
    function(data)
      local commits = data.values or {}
      for i, c in ipairs(commits) do
        commits[i] = translate_bb_commit(c)
      end
      return commits
    end,
    fetch_json(
      append_page_params(
        base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/commits",
        PAGES
      )
    )
  )
end)

b:rest(
  "get_repo_commit",
  proxy_handler(translate_bb_commit, function(o, r, sha)
    return base() .. "/repositories/" .. o .. "/" .. r .. "/commit/" .. sha
  end)
)

-- Commit statuses -----------------------------------------------------------

b:rest("get_commit_statuses", function(owner, repo_name, sha)
  proxy_json(
    function(data)
      local statuses = data.values or {}
      for i, s in ipairs(statuses) do
        statuses[i] = translate_bb_status(s)
      end
      return statuses
    end,
    fetch_json(
      append_page_params(
        base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/commit/" .. sha .. "/statuses",
        PAGES
      )
    )
  )
end)

b:rest("get_commit_combined_status", function(owner, repo_name, sha)
  proxy_json(
    function(data)
      local statuses = data.values or {}
      local combined = "success"
      for _, s in ipairs(statuses) do
        local g = bb_state_to_github(s.state)
        if g == "failure" or g == "error" then
          combined = g
          break
        elseif g == "pending" then
          combined = "pending"
        end
      end
      local out = {}
      for i, s in ipairs(statuses) do
        out[i] = translate_bb_status(s)
      end
      return { state = combined, statuses = out, total_count = #out }
    end,
    fetch_json(
      base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/commit/" .. sha .. "/statuses"
    )
  )
end)

b:rest("post_commit_status", function(owner, repo_name, sha)
  local req = DecodeJson(GetBody() or "{}")
  local bb = {
    state = github_state_to_bb(req.state or ""),
    key = req.context or "default",
    url = req.target_url or "",
    name = req.context or "default",
    description = req.description or "",
  }
  proxy_json(
    translate_bb_status,
    fetch_json(
      base()
        .. "/repositories/"
        .. owner
        .. "/"
        .. repo_name
        .. "/commit/"
        .. sha
        .. "/statuses/build",
      "POST",
      EncodeJson(bb)
    )
  )
end)

-- Contents ------------------------------------------------------------------

b:rest("get_repo_readme", function(owner, repo_name)
  local repo_url = base() .. "/repositories/" .. owner .. "/" .. repo_name
  local ok, status, _, body = fetch_json(repo_url)
  if not ok or status ~= 200 then
    respond_json(404, {})
    return
  end
  local repo = DecodeJson(body or "{}")
  local ref = (repo.mainbranch and repo.mainbranch.name) or "HEAD"
  for _, name in ipairs({ "README.md", "README", "readme.md", "Readme.md" }) do
    local ok2, status2, _, body2 = fetch_json(repo_url .. "/src/" .. ref .. "/" .. name)
    if ok2 and status2 == 200 then
      respond_json(200, {
        type = "file",
        encoding = "base64",
        content = EncodeBase64(body2 or ""),
        name = name,
        path = name,
        sha = "",
        size = #(body2 or ""),
      })
      return
    end
  end
  respond_json(404, { message = "README not found" })
end)

b:rest("get_repo_content", function(owner, repo_name, path)
  local ref = GetParam("ref") or "HEAD"
  local ok, status, _, body = fetch_json(
    base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/src/" .. ref .. "/" .. path
  )
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  -- Detect directory listing (JSON with "values") vs raw file content
  local parsed = (body and body:sub(1, 1) == "{") and DecodeJson(body) or nil
  if parsed and parsed.values then
    local out = {}
    for _, e in ipairs(parsed.values or {}) do
      out[#out + 1] = {
        type = e.type == "commit_directory" and "dir" or "file",
        name = e.path and e.path:match("[^/]+$") or "",
        path = e.path or "",
        sha = "",
        size = e.size or 0,
      }
    end
    respond_json(200, out)
  else
    respond_json(200, {
      type = "file",
      encoding = "base64",
      content = EncodeBase64(body or ""),
      name = path:match("[^/]+$") or path,
      path = path,
      sha = "",
      size = #(body or ""),
    })
  end
end)

-- GET /repos/{owner}/{repo}/license
-- Bitbucket has no license template API; fetch the LICENSE file via src endpoint.
b:rest("get_repo_license", function(owner, repo_name)
  local repo_url = base() .. "/repositories/" .. owner .. "/" .. repo_name
  local ok, status, _, body = fetch_json(repo_url)
  if not ok or status ~= 200 then
    respond_json(404, {})
    return
  end
  local repo = DecodeJson(body or "{}")
  local ref = (repo.mainbranch and repo.mainbranch.name) or "HEAD"
  for _, name in ipairs({ "LICENSE", "LICENSE.md", "LICENSE.txt", "COPYING" }) do
    local ok2, status2, _, body2 = fetch_json(repo_url .. "/src/" .. ref .. "/" .. name)
    if ok2 and status2 == 200 then
      respond_json(200, {
        type = "file",
        encoding = "base64",
        content = EncodeBase64(body2 or ""),
        name = name,
        path = name,
        sha = "",
        size = #(body2 or ""),
        license = nil,
      })
      return
    end
  end
  respond_json(404, { message = "License file not found" })
end)

-- Forks ---------------------------------------------------------------------

b:rest("get_repo_forks", function(owner, repo_name)
  proxy_json(
    function(data)
      local forks = data.values or {}
      for i, r in ipairs(forks) do
        forks[i] = translate_bb_repo(r)
      end
      return forks
    end,
    fetch_json(
      append_page_params(base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/forks", PAGES)
    )
  )
end)

b:rest("post_repo_forks", function(owner, repo_name)
  local req = DecodeJson(GetBody() or "{}")
  local bb = {}
  if req.organization then
    bb.workspace = req.organization
  end
  if req.name then
    bb.name = req.name
  end
  proxy_json_created(
    translate_bb_repo,
    fetch_json(
      base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/forks",
      "POST",
      EncodeJson(bb)
    )
  )
end)

-- Deploy keys ---------------------------------------------------------------

b:rest("get_repo_keys", function(owner, repo_name)
  proxy_json(
    function(data)
      local keys = data.values or {}
      for i, k in ipairs(keys) do
        keys[i] = translate_bb_key(k)
      end
      return keys
    end,
    fetch_json(
      append_page_params(
        base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/deploy-keys",
        PAGES
      )
    )
  )
end)

b:rest("post_repo_keys", function(owner, repo_name)
  local req = DecodeJson(GetBody() or "{}")
  local bb = { key = req.key or "", label = req.title or "" }
  proxy_json_created(
    translate_bb_key,
    fetch_json(
      base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/deploy-keys",
      "POST",
      EncodeJson(bb)
    )
  )
end)

b:rest(
  "get_repo_key",
  proxy_handler(translate_bb_key, function(o, r, key_id)
    return base() .. "/repositories/" .. o .. "/" .. r .. "/deploy-keys/" .. key_id
  end)
)

b:rest("delete_repo_key", function(owner, repo_name, key_id)
  local url = base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/deploy-keys/" .. key_id
  local dopts = auth() or {}
  dopts.method = "DELETE"
  proxy_204({ 200 }, pcall(Fetch, url, dopts))
end)

-- Webhooks ------------------------------------------------------------------

b:rest("get_repo_hooks", function(owner, repo_name)
  proxy_json(
    function(data)
      local hooks = data.values or {}
      for i, h in ipairs(hooks) do
        hooks[i] = translate_bb_hook(h)
      end
      return hooks
    end,
    fetch_json(
      append_page_params(base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/hooks", PAGES)
    )
  )
end)

b:rest("post_repo_hooks", function(owner, repo_name)
  proxy_json_created(
    translate_bb_hook,
    fetch_json(
      base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/hooks",
      "POST",
      translate_bb_hook_req(GetBody())
    )
  )
end)

b:rest("get_repo_hook", function(owner, repo_name, hook_id)
  proxy_json(
    translate_bb_hook,
    fetch_json(
      base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/hooks/{" .. hook_id .. "}"
    )
  )
end)

b:rest("patch_repo_hook", function(owner, repo_name, hook_id)
  proxy_json(
    translate_bb_hook,
    fetch_json(
      base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/hooks/{" .. hook_id .. "}",
      "PUT",
      translate_bb_hook_req(GetBody())
    )
  )
end)

b:rest("delete_repo_hook", function(owner, repo_name, hook_id)
  local url = base()
    .. "/repositories/"
    .. owner
    .. "/"
    .. repo_name
    .. "/hooks/{"
    .. hook_id
    .. "}"
  local dopts = auth() or {}
  dopts.method = "DELETE"
  proxy_204({ 200 }, pcall(Fetch, url, dopts))
end)

-- Users ---------------------------------------------------------------------

-- GET /user
b:rest(
  "get_user",
  proxy_handler(translate_bb_user, function()
    return base() .. "/user"
  end)
)

-- GET /users/{username}
b:rest(
  "get_users_username",
  proxy_handler(translate_bb_user, function(username)
    return base() .. "/users/" .. username
  end)
)

-- Issues --------------------------------------------------------------------

b:rest(
  "get_repo_issues",
  proxy_handler(translate_bb_issues, function(o, r)
    return append_page_params(base() .. "/repositories/" .. o .. "/" .. r .. "/issues", PAGES)
  end)
)

b:rest(
  "get_repo_issue",
  proxy_handler(translate_bb_issue, function(o, r, n)
    return base() .. "/repositories/" .. o .. "/" .. r .. "/issues/" .. n
  end)
)

b:rest(
  "get_issue_comments",
  proxy_handler(translate_bb_issue_comments_list, function(o, r, n)
    return append_page_params(
      base() .. "/repositories/" .. o .. "/" .. r .. "/issues/" .. n .. "/comments",
      PAGES
    )
  end)
)

b:rest(
  "get_repo_milestones",
  proxy_handler(translate_bb_milestones, function(o, r)
    return base() .. "/repositories/" .. o .. "/" .. r .. "/milestones"
  end)
)

-- Pull Requests ---------------------------------------------------------------

-- GET /repos/{owner}/{repo}/pulls
b:rest(
  "get_repo_pulls",
  proxy_handler(translate_bb_pulls, function(o, r)
    return append_page_params(base() .. "/repositories/" .. o .. "/" .. r .. "/pullrequests", PAGES)
  end)
)

-- POST /repos/{owner}/{repo}/pulls
b:rest("post_repo_pulls", function(owner, repo_name)
  local req = DecodeJson(GetBody() or "{}")
  local bb = {}
  if req.title then
    bb.title = req.title
  end
  if req.body then
    bb.description = req.body
  end
  if req.head then
    bb.source = { branch = { name = req.head } }
  end
  if req.base then
    bb.destination = { branch = { name = req.base } }
  end
  proxy_json_created(
    translate_bb_pull,
    fetch_json(
      base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/pullrequests",
      "POST",
      EncodeJson(bb)
    )
  )
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}
b:rest(
  "get_repo_pull",
  proxy_handler(translate_bb_pull, function(o, r, n)
    return base() .. "/repositories/" .. o .. "/" .. r .. "/pullrequests/" .. n
  end)
)

-- PATCH /repos/{owner}/{repo}/pulls/{pull_number}
-- Bitbucket uses PUT for updates.
b:rest("patch_repo_pull", function(owner, repo_name, pull_number)
  local req = DecodeJson(GetBody() or "{}")
  local bb = {}
  if req.title then
    bb.title = req.title
  end
  if req.body then
    bb.description = req.body
  end
  -- Bitbucket can close a PR via status but there's no simple state field in PUT.
  proxy_json(
    translate_bb_pull,
    fetch_json(
      base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/pullrequests/" .. pull_number,
      "PUT",
      EncodeJson(bb)
    )
  )
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/commits
b:rest(
  "get_pull_commits",
  proxy_handler(function(data)
    local commits = data.values or {}
    for i, c in ipairs(commits) do
      commits[i] = translate_bb_commit(c)
    end
    return commits
  end, function(o, r, n)
    return append_page_params(
      base() .. "/repositories/" .. o .. "/" .. r .. "/pullrequests/" .. n .. "/commits",
      PAGES
    )
  end)
)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/files
-- Bitbucket uses /diffstat for file-level change stats.
b:rest(
  "get_pull_files",
  proxy_handler(function(data)
    local files = data.values or {}
    for i, f in ipairs(files) do
      files[i] = translate_bb_diffstat_file(f)
    end
    return files
  end, function(o, r, n)
    return append_page_params(
      base() .. "/repositories/" .. o .. "/" .. r .. "/pullrequests/" .. n .. "/diffstat",
      PAGES
    )
  end)
)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/merge
-- Returns 204 if PR state is MERGED, 404 otherwise.
b:rest("get_pull_merge", function(owner, repo_name, pull_number)
  local ok, status, _, body = fetch_json(
    base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/pullrequests/" .. pull_number
  )
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local pr = DecodeJson(body) or {}
  if pr.state == "MERGED" then
    SetStatus(204, "No Content")
  else
    respond_json(404, { message = "Pull Request is not merged" })
  end
end)

-- PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge
-- Bitbucket uses POST for merging.
b:rest("put_pull_merge", function(owner, repo_name, pull_number)
  local req = DecodeJson(GetBody() or "{}")
  local bb = {}
  if req.merge_method then
    bb.merge_strategy = req.merge_method
  end
  if req.commit_message then
    bb.message = req.commit_message
  end
  local ok, status = fetch_json(
    base()
      .. "/repositories/"
      .. owner
      .. "/"
      .. repo_name
      .. "/pullrequests/"
      .. pull_number
      .. "/merge",
    "POST",
    EncodeJson(bb)
  )
  proxy_204({ 200 }, ok, status)
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/requested_reviewers
-- Bitbucket: participants with role=REVIEWER and not yet approved.
b:rest("get_pull_requested_reviewers", function(owner, repo_name, pull_number)
  local ok, status, _, body = fetch_json(
    base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/pullrequests/" .. pull_number
  )
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local pr = DecodeJson(body) or {}
  local users = {}
  for _, p in ipairs(pr.participants or {}) do
    if p.role == "REVIEWER" and not p.approved then
      users[#users + 1] = translate_bb_user(p.user)
    end
  end
  respond_json(200, { users = users, teams = {} })
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews
-- Bitbucket: participants with role=REVIEWER and approved=true → APPROVED reviews.
b:rest("get_pull_reviews", function(owner, repo_name, pull_number)
  local ok, status, _, body = fetch_json(
    base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/pullrequests/" .. pull_number
  )
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local pr = DecodeJson(body) or {}
  respond_json(200, translate_bb_participants_to_reviews(pr.participants))
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}
b:rest("get_pull_review", function(owner, repo_name, pull_number, review_id)
  local ok, status, _, body = fetch_json(
    base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/pullrequests/" .. pull_number
  )
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local pr = DecodeJson(body) or {}
  local reviews = translate_bb_participants_to_reviews(pr.participants)
  local rid = tonumber(review_id)
  if rid and reviews[rid] then
    respond_json(200, reviews[rid])
  else
    respond_json(404, { message = "Not Found" })
  end
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}/comments
-- Bitbucket has no per-review inline comments; return all inline PR comments.
b:rest("get_pull_review_comments", function(owner, repo_name, pull_number)
  local ok, status, _, body = fetch_json(
    append_page_params(
      base()
        .. "/repositories/"
        .. owner
        .. "/"
        .. repo_name
        .. "/pullrequests/"
        .. pull_number
        .. "/comments",
      PAGES
    )
  )
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local data = DecodeJson(body) or {}
  local result = {}
  for _, c in ipairs(data.values or {}) do
    if c.inline then
      result[#result + 1] = translate_bb_pr_comment(c)
    end
  end
  respond_json(200, result)
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/comments
-- Bitbucket inline PR comments (those with an "inline" field).
b:rest("get_pull_comments", function(owner, repo_name, pull_number)
  local ok, status, _, body = fetch_json(
    append_page_params(
      base()
        .. "/repositories/"
        .. owner
        .. "/"
        .. repo_name
        .. "/pullrequests/"
        .. pull_number
        .. "/comments",
      PAGES
    )
  )
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local data = DecodeJson(body) or {}
  local result = {}
  for _, c in ipairs(data.values or {}) do
    if c.inline then
      result[#result + 1] = translate_bb_pr_comment(c)
    end
  end
  respond_json(200, result)
end)

-- Search -----------------------------------------------------------------------

-- GET /search/repositories — maps to Bitbucket GET /repositories?q=name~"<q>"
b:rest("search_repositories", function()
  local q = GetParam("q") or ""
  proxy_search_bb(
    translate_bb_repo,
    append_page_params(base() .. '/repositories?q=name~"' .. q .. '"', PAGES)
  )
end)

-- GET /search/users — maps to Bitbucket GET /workspaces?q=slug~"<q>"
b:rest("search_users", function()
  local q = GetParam("q") or ""
  proxy_search_bb(
    translate_bb_workspace,
    append_page_params(base() .. '/workspaces?q=slug~"' .. q .. '"', PAGES)
  )
end)

-- Checks (via Bitbucket commit statuses) ----------------------------------------
--
-- GitHub Check Runs map onto Bitbucket commit build statuses.  Bitbucket has
-- no concept of a check run independent of a commit SHA, so:
--   • POST check-runs → POST /repositories/{w}/{r}/commit/{sha}/statuses/build
--   • GET check-runs/{id} → minimal stub (no reverse lookup by ID)
--   • PATCH check-runs/{id} → minimal stub
--   • GET commits/{ref}/check-runs → commit statuses list
--   • Check Suites have no Bitbucket equivalent; all suite endpoints are stubs.
--   • Annotations are always empty.
--
-- Status mapping (GitHub → Bitbucket):
--   queued/in_progress     → INPROGRESS
--   completed/success      → SUCCESSFUL
--   completed/failure      → FAILED
--   completed/neutral      → SUCCESSFUL
--   completed/skipped      → SUCCESSFUL
--   completed/(other)      → FAILED
--
-- Status mapping (Bitbucket → GitHub):
--   INPROGRESS  → status=in_progress, conclusion=null
--   SUCCESSFUL  → status=completed,   conclusion=success
--   FAILED      → status=completed,   conclusion=failure
--   STOPPED     → status=completed,   conclusion=cancelled
--   other       → status=completed,   conclusion=failure

b:rest("post_check_runs", function(owner, repo_name)
  local req = DecodeJson(GetBody() or "{}")
  local sha = req.head_sha or ""
  local status = req.status or "queued"
  local conclusion = req.conclusion
  local gh_conclusion_to_bb = {
    success = "SUCCESSFUL",
    neutral = "SUCCESSFUL",
    skipped = "SUCCESSFUL",
    cancelled = "STOPPED",
  }
  local bb_state = status == "completed" and (gh_conclusion_to_bb[conclusion] or "FAILED")
    or "INPROGRESS"
  local bb_to_gh = {
    INPROGRESS = { status = "in_progress", conclusion = nil },
    SUCCESSFUL = { status = "completed", conclusion = "success" },
    FAILED = { status = "completed", conclusion = "failure" },
    STOPPED = { status = "completed", conclusion = "cancelled" },
  }
  local bb_body = EncodeJson({
    state = bb_state,
    key = req.name or "",
    url = req.details_url or "",
    name = req.name or "",
    description = (req.output and req.output.summary) or req.name or "",
  })
  local function translate(s)
    if not s then
      return {}
    end
    local mapped = bb_to_gh[s.state] or { status = "completed", conclusion = "failure" }
    return {
      id = 0,
      node_id = "",
      head_sha = sha,
      name = s.key or s.name or "",
      status = mapped.status,
      conclusion = mapped.conclusion,
      started_at = s.created_on,
      completed_at = mapped.status == "completed" and s.updated_on or nil,
      output = {
        title = s.description or "",
        summary = s.description or "",
        text = "",
        annotations_count = 0,
        annotations_url = "",
      },
      url = "",
      html_url = s.url or "",
      details_url = s.url or "",
    }
  end
  proxy_json_created(
    translate,
    fetch_json(
      base()
        .. "/repositories/"
        .. owner
        .. "/"
        .. repo_name
        .. "/commit/"
        .. sha
        .. "/statuses/build",
      "POST",
      bb_body
    )
  )
end)

-- GET /repos/{owner}/{repo}/commits/{ref}/check-runs
-- Uses Bitbucket commit statuses.
b:rest("get_commit_check_runs", function(owner, repo_name, ref)
  local ok, status, _, body = fetch_json(
    base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/commit/" .. ref .. "/statuses"
  )
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local data = DecodeJson(body) or {}
  local bb_to_gh = {
    INPROGRESS = { status = "in_progress", conclusion = nil },
    SUCCESSFUL = { status = "completed", conclusion = "success" },
    FAILED = { status = "completed", conclusion = "failure" },
    STOPPED = { status = "completed", conclusion = "cancelled" },
  }
  local runs = {}
  for i, s in ipairs(data.values or {}) do
    local mapped = bb_to_gh[s.state] or { status = "completed", conclusion = "failure" }
    runs[i] = {
      id = i,
      node_id = "",
      head_sha = ref,
      name = s.key or s.name or "",
      status = mapped.status,
      conclusion = mapped.conclusion,
      started_at = s.created_on,
      completed_at = mapped.status == "completed" and s.updated_on or nil,
      output = {
        title = s.description or "",
        summary = s.description or "",
        text = "",
        annotations_count = 0,
        annotations_url = "",
      },
      url = "",
      html_url = s.url or "",
      details_url = s.url or "",
    }
  end
  respond_json(200, { total_count = #runs, check_runs = runs })
end)

-- Check suites have no Bitbucket equivalent; all suite endpoints fall back
-- to the route_defaults stubs defined in .init.lua.

-- Git database (refs only; blobs/commits/tags/trees have no Bitbucket equivalent) ----

b:rest("list_git_matching_refs", function(owner, repo_name, ref)
  local kind, prefix
  if ref:sub(1, 6) == "heads/" then
    kind = "branches"
    prefix = ref:sub(7)
  elseif ref:sub(1, 5) == "tags/" then
    kind = "tags"
    prefix = ref:sub(6)
  else
    kind = nil
    prefix = ref
  end
  local endpoint = kind and ("/refs/" .. kind) or "/refs"
  local url = append_page_params(
    base()
      .. "/repositories/"
      .. owner
      .. "/"
      .. repo_name
      .. endpoint
      .. '?q=name~"'
      .. prefix
      .. '"',
    PAGES
  )
  proxy_json(function(data)
    local refs = data.values or {}
    for i, r in ipairs(refs) do
      refs[i] = translate_bb_ref(r)
    end
    return refs
  end, fetch_json(url))
end)

b:rest("get_git_ref", function(owner, repo_name, ref)
  local kind, name
  if ref:sub(1, 6) == "heads/" then
    kind = "branches"
    name = ref:sub(7)
  elseif ref:sub(1, 5) == "tags/" then
    kind = "tags"
    name = ref:sub(6)
  else
    respond_json(422, { message = "Invalid ref format" })
    return
  end
  proxy_json(
    translate_bb_ref,
    fetch_json(
      base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/refs/" .. kind .. "/" .. name
    )
  )
end)

b:rest("create_git_ref", function(owner, repo_name)
  local req = DecodeJson(GetBody() or "{}")
  local full_ref = req.ref or ""
  local sha = req.sha or ""
  local kind, name
  if full_ref:sub(1, 11) == "refs/heads/" then
    kind = "branches"
    name = full_ref:sub(12)
  elseif full_ref:sub(1, 10) == "refs/tags/" then
    kind = "tags"
    name = full_ref:sub(11)
  else
    respond_json(422, { message = "Invalid ref format" })
    return
  end
  proxy_json_created(
    translate_bb_ref,
    fetch_json(
      base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/refs/" .. kind,
      "POST",
      EncodeJson({ name = name, target = { hash = sha } })
    )
  )
end)

b:rest("delete_git_ref", function(owner, repo_name, ref)
  local kind, name
  if ref:sub(1, 6) == "heads/" then
    kind = "branches"
    name = ref:sub(7)
  elseif ref:sub(1, 5) == "tags/" then
    kind = "tags"
    name = ref:sub(6)
  else
    respond_json(422, { message = "Invalid ref format" })
    return
  end
  local url = base()
    .. "/repositories/"
    .. owner
    .. "/"
    .. repo_name
    .. "/refs/"
    .. kind
    .. "/"
    .. name
  local dopts = auth() or {}
  dopts.method = "DELETE"
  proxy_204({ 200 }, pcall(Fetch, url, dopts))
end)

-- Activity (Bitbucket Watchers) ---------------------------------------------
--
-- Bitbucket has no events feed, notifications, or star concept for repos.
-- Watchers (GET /2.0/repositories/{owner}/{repo}/watchers) map to both
-- stargazers and subscribers (Bitbucket does not distinguish the two).

b:rest("get_repo_stargazers", function(owner, repo_name)
  proxy_json(
    function(data)
      local users = data.values or {}
      for i, u in ipairs(users) do
        users[i] = translate_bb_user(u)
      end
      return users
    end,
    fetch_json(
      append_page_params(
        base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/watchers",
        PAGES
      )
    )
  )
end)

b:rest("get_repo_subscribers", function(owner, repo_name)
  proxy_json(
    function(data)
      local users = data.values or {}
      for i, u in ipairs(users) do
        users[i] = translate_bb_user(u)
      end
      return users
    end,
    fetch_json(
      append_page_params(
        base() .. "/repositories/" .. owner .. "/" .. repo_name .. "/watchers",
        PAGES
      )
    )
  )
end)

-- Gists (Bitbucket Snippets) -----------------------------------------------
--
-- GitHub gist IDs are encoded as "workspace~encoded_id" so that per-gist
-- operations can reconstruct the Bitbucket URL without extra lookups.
-- e.g. gist_id = "octocat~pHANT4" → /2.0/snippets/octocat/pHANT4

b:rest("get_gists", function()
  proxy_json_list(
    translate_bb_snippets,
    fetch_json(append_page_params(base() .. "/snippets?role=owner", PAGES))
  )
end)

b:rest("get_gists_public", function()
  proxy_json_list(
    translate_bb_snippets,
    fetch_json(append_page_params(base() .. "/snippets", PAGES))
  )
end)

b:rest("post_gists", function()
  local req = DecodeJson(GetBody() or "{}") or {}
  local files = {}
  for name, f in pairs(req.files or {}) do
    if f then
      files[name] = { content = f.content or "" }
    end
  end
  local bb_body = EncodeJson({
    title = req.description or "",
    is_private = not (req.public == true or req.public == "true"),
    files = files,
  })
  proxy_json_created(translate_bb_snippet, fetch_json(base() .. "/snippets", "POST", bb_body))
end)

b:rest("get_gist", function(gist_id)
  local url = snippet_url(gist_id)
  if url then
    proxy_json(translate_bb_snippet, fetch_json(url))
  end
end)

b:rest("patch_gist", function(gist_id)
  local url = snippet_url(gist_id)
  if not url then
    return
  end
  local req = DecodeJson(GetBody() or "{}") or {}
  local bb_body = {}
  if req.description ~= nil then
    bb_body.title = req.description
  end
  if req.files ~= nil then
    local files = {}
    for name, f in pairs(req.files) do
      files[name] = f and { content = f.content or "" } or {}
    end
    bb_body.files = files
  end
  proxy_json(translate_bb_snippet, fetch_json(url, "PUT", EncodeJson(bb_body)))
end)

b:rest("delete_gist", function(gist_id)
  local url = snippet_url(gist_id)
  if not url then
    return
  end
  local dopts = auth() or {}
  dopts.method = "DELETE"
  proxy_204(nil, pcall(Fetch, url, dopts))
end)

b:rest("get_gist_comments", function(gist_id)
  local url = snippet_url(gist_id)
  if url then
    proxy_json_list(
      translate_bb_snippet_comments,
      fetch_json(append_page_params(url .. "/comments", PAGES))
    )
  end
end)

b:rest("post_gist_comment", function(gist_id)
  local url = snippet_url(gist_id)
  if not url then
    return
  end
  local req = DecodeJson(GetBody() or "{}") or {}
  proxy_json_created(
    translate_bb_snippet_comment,
    fetch_json(url .. "/comments", "POST", EncodeJson({ content = { raw = req.body or "" } }))
  )
end)

b:rest("get_gist_comment", function(gist_id, comment_id)
  local url = snippet_url(gist_id)
  if url then
    proxy_json(translate_bb_snippet_comment, fetch_json(url .. "/comments/" .. comment_id))
  end
end)

b:rest("patch_gist_comment", function(gist_id, comment_id)
  local url = snippet_url(gist_id)
  if not url then
    return
  end
  local req = DecodeJson(GetBody() or "{}") or {}
  proxy_json(
    translate_bb_snippet_comment,
    fetch_json(
      url .. "/comments/" .. comment_id,
      "PUT",
      EncodeJson({ content = { raw = req.body or "" } })
    )
  )
end)

b:rest("delete_gist_comment", function(gist_id, comment_id)
  local url = snippet_url(gist_id)
  if not url then
    return
  end
  local dopts = auth() or {}
  dopts.method = "DELETE"
  proxy_204(nil, pcall(Fetch, url .. "/comments/" .. comment_id, dopts))
end)

b:rest("get_gist_commits", function(gist_id)
  local url = snippet_url(gist_id)
  if url then
    proxy_json_list(
      translate_bb_snippet_commits,
      fetch_json(append_page_params(url .. "/commits", PAGES))
    )
  end
end)

b:rest("get_gist_forks", function(gist_id)
  local url = snippet_url(gist_id)
  if url then
    proxy_json_list(translate_bb_snippets, fetch_json(append_page_params(url .. "/forks", PAGES)))
  end
end)

b:rest("get_gist_star", function(gist_id)
  local url = snippet_url(gist_id)
  if not url then
    return
  end
  local ok, status = fetch_json(url .. "/watch")
  if ok and (status == 200 or status == 204) then
    set_preamble(204)
  elseif ok and status == 404 then
    respond_json(404, {})
  elseif ok then
    respond_json(status, {})
  else
    respond_json(503, {})
  end
end)

b:rest("put_gist_star", function(gist_id)
  local url = snippet_url(gist_id)
  if not url then
    return
  end
  local wopts = auth() or {}
  wopts.method = "PUT"
  proxy_204({ 200 }, pcall(Fetch, url .. "/watch", wopts))
end)

b:rest("delete_gist_star", function(gist_id)
  local url = snippet_url(gist_id)
  if not url then
    return
  end
  local wopts = auth() or {}
  wopts.method = "DELETE"
  proxy_204(nil, pcall(Fetch, url .. "/watch", wopts))
end)

b:rest("get_gist_revision", function(gist_id, sha)
  local url = snippet_url(gist_id)
  if url then
    proxy_json(translate_bb_snippet, fetch_json(url .. "/" .. sha))
  end
end)

b:rest("get_user_gists", function(username)
  proxy_json_list(
    translate_bb_snippets,
    fetch_json(append_page_params(base() .. "/snippets/" .. username, PAGES))
  )
end)

-- ---------------------------------------------------------------------------
-- GraphQL resolvers
-- ---------------------------------------------------------------------------

-- Local pagination parameters for graphql_cursor_url.
-- Bitbucket uses pagelen / page query parameters (not per_page).
local GQL_PAGES = { per_page = "pagelen", page = "page" }

-- Local helper: extract total from a Bitbucket paginated response body.
local function bb_total(data)
  return data.size and tonumber(data.size) or nil
end

-- Local helper: build a paginated Relay Connection from a Bitbucket list endpoint.
-- Bitbucket wraps paginated responses in {"values":[...],"size":N,"pagelen":30,"page":1}.
-- The total count comes from the response body's "size" field (not HTTP headers).
-- For backward pagination (last without before), prefetches total via a pagelen=1 request.
local function bb_repo_connection(owner, repo_name, suffix, args, ctx, translate_fn, make_conn)
  local url_base = base() .. "/repositories/" .. owner .. "/" .. repo_name .. suffix
  local total
  if args.last and not args.before then
    local count_url = graphql_cursor_url(url_base, { first = 1 }, GQL_PAGES)
    local pdata, _, _ = graphql_fetch_with_headers(fetch_json, count_url)
    if pdata then
      total = bb_total(pdata)
    end
  end
  local url = graphql_cursor_url(url_base, args, GQL_PAGES, total)
  local data, _, err = graphql_fetch_with_headers(fetch_json, url)
  if not data then
    graphql_error(ctx, err)
    return nil
  end
  total = bb_total(data) or total
  local nodes = {}
  for _, item in ipairs(data.values or {}) do
    nodes[#nodes + 1] = translate_fn(item)
  end
  return make_conn(nodes, args, total, ctx)
end

-- Query.repositoryOwner: look up a User or Organization (workspace) by login.
-- Tries /users/{login} first; falls back to /workspaces/{login}.
b:graphql("Query.repositoryOwner", function(_parent, args, ctx)
  if not args.login then
    graphql_error(ctx, "repositoryOwner requires a login argument")
    return nil
  end
  local udata, _ = graphql_fetch(fetch_json, base() .. "/users/" .. args.login)
  if udata then
    return graphql_translate_user(translate_bb_user(udata))
  end
  local wdata, _ = graphql_fetch(fetch_json, base() .. "/workspaces/" .. args.login)
  if wdata then
    return graphql_translate_org(translate_bb_workspace(wdata))
  end
  return nil
end)

-- Query.viewer: resolve the authenticated user via GET /user.
b:graphql("Query.viewer", function(_parent, _args, ctx)
  local data = graphql_fetch_or_error(fetch_json, base() .. "/user", ctx, nil)
  if not data then
    return nil
  end
  local u = graphql_translate_user(translate_bb_user(data))
  u.isViewer = true
  return u
end)

-- Query.user: look up a User by login.
b:graphql("Query.user", function(_parent, args, ctx)
  if not args.login then
    graphql_error(ctx, "user requires a login argument")
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, base() .. "/users/" .. args.login)
  if not data then
    return nil
  end
  return graphql_translate_user(translate_bb_user(data))
end)

-- Query.organization: look up a Bitbucket workspace as an Organization.
b:graphql("Query.organization", function(_parent, args, ctx)
  if not args.login then
    graphql_error(ctx, "organization requires a login argument")
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, base() .. "/workspaces/" .. args.login)
  if not data then
    return nil
  end
  return graphql_translate_org(translate_bb_workspace(data))
end)

-- Query.repository: look up a Repository by owner and name.
b:graphql("Query.repository", function(_parent, args, ctx)
  if not args.owner or not args.name then
    graphql_error(ctx, "repository requires owner and name arguments")
    return nil
  end
  local data, _ =
    graphql_fetch(fetch_json, base() .. "/repositories/" .. args.owner .. "/" .. args.name)
  if not data then
    return nil
  end
  return graphql_translate_repo(translate_bb_repo(data))
end)

-- node.Repository: fetch a repository by "owner/repo" local ID.
b:graphql("node.Repository", function(local_id, _ctx)
  local data, _ = graphql_fetch(fetch_json, base() .. "/repositories/" .. local_id)
  if not data then
    return nil
  end
  return graphql_translate_repo(translate_bb_repo(data))
end)

-- node.User: fetch a user by login.
b:graphql("node.User", function(local_id, _ctx)
  local data, _ = graphql_fetch(fetch_json, base() .. "/users/" .. local_id)
  if not data then
    return nil
  end
  return graphql_translate_user(translate_bb_user(data))
end)

-- node.Organization: fetch a workspace by slug.
b:graphql("node.Organization", function(local_id, _ctx)
  local data, _ = graphql_fetch(fetch_json, base() .. "/workspaces/" .. local_id)
  if not data then
    return nil
  end
  return graphql_translate_org(translate_bb_workspace(data))
end)

-- node.Issue: fetch an issue by "owner/repo/number" local ID.
b:graphql("node.Issue", function(local_id, _ctx)
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ = graphql_fetch(
    fetch_json,
    base() .. "/repositories/" .. owner .. "/" .. repo .. "/issues/" .. number
  )
  if not data then
    return nil
  end
  return graphql_translate_issue(translate_bb_issue(data), owner, repo)
end)

-- node.PullRequest: fetch a pull request by "owner/repo/number" local ID.
b:graphql("node.PullRequest", function(local_id, _ctx)
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ = graphql_fetch(
    fetch_json,
    base() .. "/repositories/" .. owner .. "/" .. repo .. "/pullrequests/" .. number
  )
  if not data then
    return nil
  end
  return graphql_translate_pr(translate_bb_pull(data), owner, repo)
end)

-- ---------------------------------------------------------------------------
-- Repository connection sub-resolvers
-- ---------------------------------------------------------------------------

-- Repository.issues: paginated list of issues.
b:graphql("Repository.issues", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return bb_repo_connection(owner, name, "/issues", args, ctx, function(i)
    return graphql_translate_issue(translate_bb_issue(i), owner, name)
  end, graphql_issues_connection)
end)

-- Repository.pullRequests: paginated list of pull requests.
b:graphql("Repository.pullRequests", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return bb_repo_connection(owner, name, "/pullrequests", args, ctx, function(p)
    return graphql_translate_pr(translate_bb_pull(p), owner, name)
  end, graphql_prs_connection)
end)

-- Repository.milestones: paginated list of milestones.
b:graphql("Repository.milestones", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return bb_repo_connection(owner, name, "/milestones", args, ctx, function(m)
    return graphql_translate_milestone(translate_bb_milestone(m), owner, name)
  end, function(n, a, t, c)
    return graphql_make_connection("Milestone", n, a, t, c)
  end)
end)

-- Repository.refs: paginated list of branches as Ref objects.
-- Bitbucket branch objects use target.hash for the SHA; we normalise to commit.sha
-- before passing to graphql_translate_ref.
b:graphql("Repository.refs", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return bb_repo_connection(owner, name, "/refs/branches", args, ctx, function(br)
    -- Normalise Bitbucket branch shape to the {name, commit={sha}} expected by
    -- graphql_translate_ref.
    if br.target and not br.commit then
      br.commit = { sha = br.target.hash }
    end
    return graphql_translate_ref(br, parent)
  end, graphql_refs_connection)
end)

-- Repository.defaultBranchRef: enrich the inline stub with full branch data.
-- The parent already carries {__typename="Ref",name="main"} from graphql_translate_repo.
b:graphql("Repository.defaultBranchRef", function(parent, _args, _ctx)
  local branch = parent.defaultBranchRef and parent.defaultBranchRef.name
  if not branch then
    return nil
  end
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  local data, _ = graphql_fetch(
    fetch_json,
    base() .. "/repositories/" .. owner .. "/" .. name .. "/refs/branches/" .. branch
  )
  if not data then
    return nil
  end
  if data.target and not data.commit then
    data.commit = { sha = data.target.hash }
  end
  return graphql_translate_ref(data, parent)
end)

-- Repository.languages: fetch primary language as a LanguageConnection.
-- Bitbucket exposes only the primary language via the repo object; no byte-count breakdown.
-- Returns a single-entry connection when the repo has a language, empty otherwise.
b:graphql("Repository.languages", function(parent, _args, _ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, base() .. "/repositories/" .. owner .. "/" .. name)
  if not data then
    return nil
  end
  local lang = data.language
  local nodes, edges = {}, {}
  local total_size = 0
  if lang and lang ~= "" then
    local node = {
      __typename = "Language",
      id = encode_node_id("Language", lang),
      name = lang,
      color = nil,
    }
    nodes[1] = node
    edges[1] = { cursor = "", node = node, size = 0 }
  end
  return {
    __typename = "LanguageConnection",
    totalCount = #nodes,
    totalSize = total_size,
    pageInfo = {
      __typename = "PageInfo",
      hasNextPage = false,
      hasPreviousPage = false,
      startCursor = nil,
      endCursor = nil,
    },
    nodes = nodes,
    edges = edges,
  }
end)

-- Issue.comments: paginated list of comments for a single issue.
b:graphql("Issue.comments", function(parent, args, ctx)
  local _, local_id = decode_node_id(parent.id)
  if not local_id then
    return nil
  end
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local url_base = base()
    .. "/repositories/"
    .. owner
    .. "/"
    .. repo
    .. "/issues/"
    .. number
    .. "/comments"
  local total
  if args.last and not args.before then
    local count_url = graphql_cursor_url(url_base, { first = 1 }, GQL_PAGES)
    local pdata, _, _ = graphql_fetch_with_headers(fetch_json, count_url)
    if pdata then
      total = bb_total(pdata)
    end
  end
  local url = graphql_cursor_url(url_base, args, GQL_PAGES, total)
  local data, _, err = graphql_fetch_with_headers(fetch_json, url)
  if not data then
    graphql_error(ctx, err)
    return nil
  end
  total = bb_total(data) or total
  local nodes = {}
  for _, c in ipairs(data.values or {}) do
    nodes[#nodes + 1] = graphql_translate_comment(translate_bb_issue_comment(c), owner, repo)
  end
  return graphql_make_connection("IssueComment", nodes, args, total, ctx)
end)

-- PullRequest.commits: paginated commit list for a pull request.
b:graphql("PullRequest.commits", function(parent, args, ctx)
  local _, local_id = decode_node_id(parent.id)
  if not local_id then
    return nil
  end
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local url_base = base()
    .. "/repositories/"
    .. owner
    .. "/"
    .. repo
    .. "/pullrequests/"
    .. number
    .. "/commits"
  local total
  if args.last and not args.before then
    local count_url = graphql_cursor_url(url_base, { first = 1 }, GQL_PAGES)
    local pdata, _, _ = graphql_fetch_with_headers(fetch_json, count_url)
    if pdata then
      total = bb_total(pdata)
    end
  end
  local url = graphql_cursor_url(url_base, args, GQL_PAGES, total)
  local data, _, err = graphql_fetch_with_headers(fetch_json, url)
  if not data then
    graphql_error(ctx, err)
    return nil
  end
  total = bb_total(data) or total
  local nodes = {}
  for _, c in ipairs(data.values or {}) do
    local translated = translate_bb_commit(c)
    local sha = translated.sha or ""
    nodes[#nodes + 1] = {
      __typename = "PullRequestCommit",
      id = encode_node_id("PullRequestCommit", sha),
      commit = graphql_translate_commit(translated, owner, repo),
      url = translated.html_url,
    }
  end
  return graphql_make_connection("PullRequestCommit", nodes, args, total, ctx)
end)

-- PullRequest.reviews: paginated review list for a pull request.
-- Bitbucket has no dedicated reviews endpoint; reviews are synthesized from
-- PR participants with role=REVIEWER and approved=true.
b:graphql("PullRequest.reviews", function(parent, args, ctx)
  local _, local_id = decode_node_id(parent.id)
  if not local_id then
    return nil
  end
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ = graphql_fetch(
    fetch_json,
    base() .. "/repositories/" .. owner .. "/" .. repo .. "/pullrequests/" .. number
  )
  if not data then
    return nil
  end
  -- Reuse the existing REST translator to convert participants to review objects.
  local reviews = translate_bb_participants_to_reviews(data.participants)
  local nodes = {}
  for _, r in ipairs(reviews) do
    nodes[#nodes + 1] = graphql_translate_review(r, owner, repo)
  end
  return graphql_make_connection("PullRequestReview", nodes, args, #nodes, ctx)
end)

-- ---------------------------------------------------------------------------
-- Query.search
-- ---------------------------------------------------------------------------

-- Query.search: map GitHub GraphQL search to Bitbucket search endpoints.
-- Supports REPOSITORY (via /repositories?q=name~"...") and USER
-- (via /workspaces?q=slug~"..."). ISSUE search is not supported.
b:graphql("Query.search", function(_parent, args, _ctx)
  local query = args.query or ""
  local search_type = args.type or "REPOSITORY"
  local per_page = args.first or 30
  local q = EscapeParam(query)

  local nodes = {}
  local repo_count, user_count, issue_count = 0, 0, 0

  if search_type == "REPOSITORY" then
    local data, _ =
      graphql_fetch(fetch_json, base() .. '/repositories?q=name~"' .. q .. '"&pagelen=' .. per_page)
    if data and data.values then
      for _, r in ipairs(data.values) do
        nodes[#nodes + 1] = graphql_translate_repo(translate_bb_repo(r))
      end
      repo_count = data.size or #nodes
    end
  elseif search_type == "USER" then
    local data, _ =
      graphql_fetch(fetch_json, base() .. '/workspaces?q=slug~"' .. q .. '"&pagelen=' .. per_page)
    if data and data.values then
      for _, w in ipairs(data.values) do
        nodes[#nodes + 1] = graphql_translate_user(translate_bb_workspace(w))
      end
      user_count = data.size or #nodes
    end
  end

  local edges = {}
  for i, node in ipairs(nodes) do
    edges[i] = {
      __typename = "SearchResultItemEdge",
      cursor = graphql_page_to_cursor(1, i),
      node = node,
    }
  end
  local n = #edges
  return {
    __typename = "SearchResultItemConnection",
    nodes = nodes,
    edges = edges,
    pageInfo = {
      __typename = "PageInfo",
      hasNextPage = false,
      hasPreviousPage = false,
      startCursor = n > 0 and edges[1].cursor or nil,
      endCursor = n > 0 and edges[n].cursor or nil,
    },
    repositoryCount = repo_count,
    userCount = user_count,
    issueCount = issue_count,
    codeCount = 0,
    discussionCount = 0,
    wikiCount = 0,
  }
end)

b:build()
