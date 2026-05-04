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

local function bb_link(obj, rel)
  return (obj.links and obj.links[rel] and obj.links[rel].href) or ""
end

-- Map a Bitbucket repository object to GitHub format.
local function bb_repo_owner(r)
  local owner = r.owner or {}
  return {
    login = owner.nickname or owner.display_name or "",
    id = 0,
    node_id = owner.uuid or "",
    avatar_url = bb_link(owner, "avatar"),
    url = "",
    html_url = bb_link(owner, "html"),
    type = owner.type == "team" and "Organization" or "User",
  }
end

local translate_bb_repo = make_translator({
  node_id = field("uuid", { default = "" }),
  name = computed(function(r)
    return r.slug or r.name
  end),
  private = "is_private",
  owner = computed(bb_repo_owner),
  html_url = computed(function(r)
    return bb_link(r, "html")
  end),
  fork = computed(function(r)
    return r.parent ~= nil
  end),
  url = computed(function(r)
    return bb_link(r, "self")
  end),
  homepage = field("website", { default = "" }),
  default_branch = computed(function(r)
    local main = r.mainbranch or {}
    return main.name or "main"
  end),
  visibility = computed(function(r)
    return r.is_private and "private" or "public"
  end),
  created_at = "created_on",
  updated_at = "updated_on",
  pushed_at = "updated_on",
  copy_fields("full_name", "description", "language", "has_issues"),
  copy_fields("has_wiki"),
  const_fields(0, "id", "stargazers_count", "watchers_count", "forks_count"),
  const_fields(0, "open_issues_count", "forks", "open_issues", "watchers"),
  const_fields("", "clone_url"),
  const_fields(false, "archived", "disabled"),
  default_fields(0, "size"),
})

-- Translate GitHub create/update request body to Bitbucket format.
-- Map a Bitbucket user object to GitHub format.
local translate_bb_user = make_translator({
  login = computed(function(u)
    return u.nickname or u.display_name or ""
  end),
  node_id = field("account_id", { default = "" }),
  avatar_url = computed(function(u)
    return bb_link(u, "avatar")
  end),
  html_url = computed(function(u)
    return bb_link(u, "html")
  end),
  name = "display_name",
  const_fields(0, "id"),
  const_fields("User", "type"),
  const_fields(false, "site_admin"),
})

-- Map a Bitbucket workspace object to GitHub user format (used for user search).
local translate_bb_workspace = make_translator({
  login = field("slug", { default = "" }),
  node_id = field("uuid", { default = "" }),
  avatar_url = computed(function(w)
    return bb_link(w, "avatar")
  end),
  html_url = computed(function(w)
    return bb_link(w, "html")
  end),
  copy_fields("name"),
  const_fields(0, "id"),
  const_fields("User", "type"),
  const_fields(false, "site_admin"),
})

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

local function bb_req_from_github(body_str)
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

local function bb_commit_author(c)
  local author = c.author or {}
  local user = author.user or {}
  return {
    name = user.display_name or author.raw or "",
    email = "",
    date = c.date or "",
  }
end

local function bb_commit_user(c)
  local author = c.author or {}
  local user = author.user or {}
  return { login = user.nickname or "", id = 0 }
end

local function bb_commit_parents(c)
  local parents = {}
  for _, p in ipairs(c.parents or {}) do
    parents[#parents + 1] = { sha = p.hash or "" }
  end
  return parents
end

local translate_bb_commit = make_translator({
  sha = field("hash", { default = "" }),
  commit = computed(function(c)
    return {
      message = c.message or "",
      author = bb_commit_author(c),
      committer = bb_commit_author(c),
    }
  end),
  author = computed(bb_commit_user),
  committer = computed(bb_commit_user),
  parents = computed(bb_commit_parents),
})

local BB_TO_GITHUB_STATE = { SUCCESSFUL = "success", FAILED = "failure", INPROGRESS = "pending" }
local function bb_state_to_github(state)
  return BB_TO_GITHUB_STATE[state] or "error"
end

local GITHUB_TO_BB_STATE = { success = "SUCCESSFUL", failure = "FAILED", pending = "INPROGRESS" }
local function github_state_to_bb(state)
  return GITHUB_TO_BB_STATE[state] or "FAILED"
end

local function bb_lower(value)
  return tostring(value or ""):lower()
end

local translate_bb_status = make_translator({
  state = computed(function(s)
    return bb_state_to_github(s.state)
  end),
  context = field("key", { default = "" }),
  target_url = field("url", { default = "" }),
  created_at = field("created_on", { default = "" }),
  updated_at = field("updated_on", { default = "" }),
  default_fields("", "description"),
})

local translate_bb_key = make_translator({
  title = field("label", { default = "" }),
  created_at = field("created_on", { default = "" }),
  const_fields(true, "read_only", "verified"),
  default_fields(0, "id"),
  default_fields("", "key"),
})

local function bb_hook_events(h)
  local events = {}
  for _, e in ipairs(h.events or {}) do
    -- "repo:push" -> "push", "pullrequest:created" -> "pull_request"
    events[#events + 1] = (e:match(":(.+)$") or e):gsub("_", ".")
  end
  return events
end

local translate_bb_hook = make_translator({
  id = computed(function(h)
    return h.uuid and h.uuid:gsub("[{}]", "") or ""
  end),
  config = computed(function(h)
    return { url = h.url or "", content_type = "json" }
  end),
  events = computed(bb_hook_events),
  active = computed(function(h)
    return h.active ~= false
  end),
})

-- Map a Bitbucket pull request branch ref to GitHub format.
local translate_bb_pr_branch = make_translator({
  label = computed(function(ref)
    local branch = ref.branch or {}
    local repo = ref.repository or {}
    return repo.full_name and (repo.full_name .. ":" .. (branch.name or "")) or (branch.name or "")
  end),
  ref = computed(function(ref)
    return (ref.branch or {}).name or ""
  end),
  sha = computed(function(ref)
    return (ref.commit or {}).hash or ""
  end),
})

-- Map a Bitbucket pull request object to GitHub format.
local function bb_pull_state(pr)
  return pr.state == "OPEN" and "open" or "closed"
end

local translate_bb_pull = make_translator({
  number = field("id", { default = 0 }),
  state = computed(bb_pull_state),
  body = field("description", { default = "" }),
  user = nested(translate_bb_user, "author"),
  head = nested(translate_bb_pr_branch, "source"),
  base = nested(translate_bb_pr_branch, "destination"),
  created_at = field("created_on", { default = "" }),
  updated_at = field("updated_on", { default = "" }),
  closed_at = computed(function(pr)
    return pr.state ~= "MERGED" and bb_pull_state(pr) == "closed" and (pr.updated_on or "") or nil
  end),
  merged_at = computed(function(pr)
    return pr.state == "MERGED" and (pr.updated_on or "") or nil
  end),
  merge_commit_sha = computed(function(pr)
    return (pr.merge_commit or {}).hash or nil
  end),
  merged_by = computed(function(pr)
    return pr.state == "MERGED" and pr.closed_by and translate_bb_user(pr.closed_by) or nil
  end),
  html_url = computed(function(pr)
    return bb_link(pr, "html")
  end),
  url = computed(function(pr)
    return bb_link(pr, "self")
  end),
  diff_url = computed(function(pr)
    return bb_link(pr, "diff")
  end),
  mergeable = computed(function(pr)
    return pr.state == "OPEN" or nil
  end),
  const_fields("", "node_id", "patch_url"),
  const_fields(false, "locked", "draft"),
  const_fields(0, "comments", "review_comments", "commits", "additions"),
  const_fields(0, "deletions", "changed_files"),
  const_fields(nil, "participants"),
  default_fields(0, "id"),
  default_fields("", "title"),
})

local function bb_values(translator, data)
  return translate_list(translator, (data or {}).values)
end

-- Map a Bitbucket diffstat entry to GitHub file format.
local function bb_diffstat_filename(f)
  local new_file = f.new or {}
  local old_file = f.old or {}
  return new_file.path or old_file.path or ""
end

local translate_bb_diffstat_file = make_translator({
  filename = computed(bb_diffstat_filename),
  additions = field("lines_added", { default = 0 }),
  deletions = field("lines_removed", { default = 0 }),
  changes = computed(function(f)
    return (f.lines_added or 0) + (f.lines_removed or 0)
  end),
  const_fields("", "sha", "patch"),
  default_fields("modified", "status"),
})

-- Map a Bitbucket PR comment (with inline position) to GitHub review comment format.
local function bb_comment_body(c)
  return (c.content or {}).raw or ""
end

local function bb_inline_position(c, key)
  local inline = c.inline or {}
  return inline[key]
end

local translate_bb_pr_comment = make_translator({
  path = computed(function(c)
    return bb_inline_position(c, "path") or ""
  end),
  position = computed(function(c)
    return bb_inline_position(c, "to") or bb_inline_position(c, "from")
  end),
  original_position = computed(function(c)
    return bb_inline_position(c, "from")
  end),
  body = computed(bb_comment_body),
  user = computed(function(c)
    return translate_bb_user(c.user or c.author)
  end),
  created_at = field("created_on", { default = "" }),
  updated_at = field("updated_on", { default = "" }),
  html_url = computed(function(c)
    return bb_link(c, "html")
  end),
  const_fields("", "node_id", "commit_id", "original_commit_id", "diff_hunk"),
  const_fields("", "pull_request_url", "url"),
  default_fields(0, "id"),
})

local translate_bb_participant_review = make_translator({
  id = computed(function(_p, idx)
    return idx
  end),
  user = nested(translate_bb_user),
  submitted_at = field("participated_on", { default = "" }),
  const_fields("", "node_id", "body", "html_url", "pull_request_url"),
  const_fields("APPROVED", "state"),
})

-- Map Bitbucket PR participants with REVIEWER role to GitHub reviews format.
local function bb_participants_to_reviews(participants)
  local result = {}
  local idx = 0
  for _, p in ipairs(participants or {}) do
    if p.role == "REVIEWER" and p.approved then
      idx = idx + 1
      result[idx] = translate_bb_participant_review(p, idx)
    end
  end
  return result
end

-- Translate a Bitbucket issue to GitHub format.
-- Bitbucket states: "open", "resolved", "wontfix", "invalid", "duplicate", "on hold", "closed"
local function bb_issue_assignees(i)
  local assignees = {}
  if i.assignee then
    assignees[1] = translate_bb_user(i.assignee)
  end
  return assignees
end

local function bb_issue_milestone(i)
  if i.milestone and i.milestone.name then
    return {
      id = i.milestone.id or 0,
      number = i.milestone.id or 0,
      title = i.milestone.name,
      state = "open",
      created_at = "",
      updated_at = "",
    }
  end
  return nil
end

local translate_bb_issue = make_translator({
  number = field("id", { default = 0 }),
  body = computed(bb_comment_body),
  state = computed(function(i)
    return i.state == "open" and "open" or "closed"
  end),
  user = nested(translate_bb_user, "reporter"),
  assignees = computed(bb_issue_assignees),
  labels = computed(function()
    return {}
  end),
  milestone = computed(bb_issue_milestone),
  created_at = field("created_on", { default = "" }),
  updated_at = field("updated_on", { default = "" }),
  html_url = computed(function(i)
    return bb_link(i, "html")
  end),
  const_fields(nil, "closed_at"),
  default_fields(0, "id"),
  default_fields("", "title"),
})

-- Translate a Bitbucket issue comment to GitHub format.
local translate_bb_issue_comment = make_translator({
  body = computed(bb_comment_body),
  user = nested(translate_bb_user, "author"),
  created_at = field("created_on", { default = "" }),
  updated_at = field("updated_on", { default = "" }),
  html_url = computed(function(c)
    return bb_link(c, "html")
  end),
  default_fields(0, "id"),
})

local function bb_commit_comment_sha(c)
  local links = c.links or {}
  local function extract(href)
    if href then
      local sha = href:match("/commits/([0-9a-fA-F]+)")
        or href:match("/commit/([0-9a-fA-F]+)")
        or href:match("[?&]at=([0-9a-fA-F]+)")
      return sha
    end
    return nil
  end
  return extract((links.commit or {}).href)
    or extract((links.code or {}).href)
    or extract((links.html or {}).href)
    or extract((links.self or {}).href)
    or ""
end

local translate_bb_commit_comment = make_translator({
  body = computed(bb_comment_body),
  commit_id = computed(function(c)
    return c.commit_id or bb_commit_comment_sha(c)
  end),
  path = computed(function(c)
    return bb_inline_position(c, "path")
  end),
  position = computed(function(c)
    return bb_inline_position(c, "to") or bb_inline_position(c, "from")
  end),
  line = computed(function(c)
    return bb_inline_position(c, "to") or bb_inline_position(c, "from")
  end),
  user = computed(function(c)
    return translate_bb_user(c.user or c.author)
  end),
  html_url = computed(function(c)
    return bb_link(c, "html")
  end),
  created_at = field("created_on", { default = "" }),
  updated_at = computed(function(c)
    return c.updated_on or c.created_on or ""
  end),
  default_fields(0, "id"),
})

-- Translate a Bitbucket milestone to GitHub format.
-- Bitbucket milestone: { id, name, resource_uri }
local translate_bb_milestone = make_translator({
  number = field("id", { default = 0 }),
  title = field("name", { default = "" }),
  const_fields("open", "state"),
  const_fields("", "created_at", "updated_at"),
  default_fields(0, "id"),
})

local function bb_hook_req_from_github(body_str)
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

local translate_bb_ref = make_translator({
  ref = computed(function(r)
    local ref_type = r.type == "tag" and "tags" or "heads"
    return "refs/" .. ref_type .. "/" .. (r.name or "")
  end),
  object = computed(function(r)
    local sha = (r.target and r.target.hash) or ""
    return { type = "commit", sha = sha, url = "" }
  end),
  const_fields("", "node_id", "url"),
})

-- Gist helpers ---------------------------------------------------------------

-- Translate a Bitbucket snippet object to GitHub gist format.
-- Files include only metadata (raw_url, size); content is not eagerly fetched.
-- gist.id encodes "workspace~encoded_id" for round-trip decoding.
local function bb_snippet_owner(s)
  local owner = s.owner or {}
  local ws = owner.nickname or owner.display_name or ""
  return ws, owner
end

local function bb_snippet_files(s)
  local files = {}
  for name, f in pairs(s.files or {}) do
    files[name] = {
      filename = name,
      type = f.mimetype or "text/plain",
      language = nil,
      raw_url = bb_link(f, "self"),
      size = f.size or 0,
      truncated = false,
    }
  end
  return files
end

local translate_bb_snippet = make_translator({
  id = computed(function(s)
    local ws = bb_snippet_owner(s)
    return ws .. "~" .. tostring(s.id or "")
  end),
  html_url = computed(function(s)
    return bb_link(s, "html")
  end),
  files = computed(bb_snippet_files),
  public = computed(function(s)
    return not (s.is_private or false)
  end),
  created_at = field("created_on", { default = "" }),
  updated_at = field("updated_on", { default = "" }),
  description = field("title", { default = "" }),
  owner = computed(function(s)
    local ws, owner = bb_snippet_owner(s)
    return {
      login = ws,
      id = 0,
      node_id = owner.uuid or "",
      avatar_url = bb_link(owner, "avatar"),
      url = "",
      html_url = "",
      type = "User",
    }
  end),
  const_fields("", "node_id", "url"),
  const_fields(0, "comments"),
  const_fields(nil, "user"),
  const_fields(false, "truncated"),
})

-- Translate a Bitbucket snippet comment to GitHub gist comment format.
local translate_bb_snippet_comment = make_translator({
  body = computed(bb_comment_body),
  user = computed(function(c)
    local author = c.author or {}
    return {
      login = author.nickname or author.display_name or "",
      id = 0,
      node_id = author.uuid or "",
      avatar_url = bb_link(author, "avatar"),
      url = "",
      html_url = "",
      type = "User",
    }
  end),
  created_at = field("created_on", { default = "" }),
  updated_at = field("updated_on", { default = "" }),
  const_fields("", "node_id", "url"),
  default_fields(0, "id"),
})

local translate_bb_snippet_commit = make_translator({
  version = field("hash", { default = "" }),
  user = computed(function(c)
    local author = c.author or {}
    local user = author.user or {}
    return {
      login = user.nickname or user.display_name or "",
      id = 0,
      node_id = user.uuid or "",
      avatar_url = bb_link(user, "avatar"),
      url = "",
      html_url = "",
      type = "User",
    }
  end),
  committed_at = field("date", { default = "" }),
  change_status = computed(function()
    return { total = 0, additions = 0, deletions = 0 }
  end),
  const_fields("", "url"),
})

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
      bb_req_from_github(GetBody())
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
      bb_req_from_github(raw)
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
      bb_hook_req_from_github(GetBody())
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
      bb_hook_req_from_github(GetBody())
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
  proxy_handler(function(data)
    return bb_values(translate_bb_issue, data)
  end, function(o, r)
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
  proxy_handler(function(data)
    return bb_values(translate_bb_issue_comment, data)
  end, function(o, r, n)
    return append_page_params(
      base() .. "/repositories/" .. o .. "/" .. r .. "/issues/" .. n .. "/comments",
      PAGES
    )
  end)
)

b:rest(
  "get_repo_milestones",
  proxy_handler(function(data)
    return bb_values(translate_bb_milestone, data)
  end, function(o, r)
    return base() .. "/repositories/" .. o .. "/" .. r .. "/milestones"
  end)
)

-- Pull Requests ---------------------------------------------------------------

-- GET /repos/{owner}/{repo}/pulls
b:rest(
  "get_repo_pulls",
  proxy_handler(function(data)
    return bb_values(translate_bb_pull, data)
  end, function(o, r)
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
  respond_json(200, bb_participants_to_reviews(pr.participants))
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
  local reviews = bb_participants_to_reviews(pr.participants)
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
  proxy_json_list(function(data)
    return bb_values(translate_bb_snippet, data)
  end, fetch_json(append_page_params(base() .. "/snippets?role=owner", PAGES)))
end)

b:rest("get_gists_public", function()
  proxy_json_list(function(data)
    return bb_values(translate_bb_snippet, data)
  end, fetch_json(append_page_params(base() .. "/snippets", PAGES)))
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
    proxy_json_list(function(data)
      return bb_values(translate_bb_snippet_comment, data)
    end, fetch_json(append_page_params(url .. "/comments", PAGES)))
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
    proxy_json_list(function(data)
      return bb_values(translate_bb_snippet_commit, data)
    end, fetch_json(append_page_params(url .. "/commits", PAGES)))
  end
end)

b:rest("get_gist_forks", function(gist_id)
  local url = snippet_url(gist_id)
  if url then
    proxy_json_list(function(data)
      return bb_values(translate_bb_snippet, data)
    end, fetch_json(append_page_params(url .. "/forks", PAGES)))
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
  proxy_json_list(function(data)
    return bb_values(translate_bb_snippet, data)
  end, fetch_json(append_page_params(base() .. "/snippets/" .. username, PAGES)))
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
  local reviews = bb_participants_to_reviews(data.participants)
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

-- Webhook handlers: Bitbucket Cloud uses X-Event-Key header.
-- Event keys relevant to the issues family:
--   issue:created         → issues / opened
--   issue:updated         → issues / edited | closed | reopened (derived from changes.status)
--   issue:comment_created → issue_comment / created
--
-- Bitbucket Cloud states: "open", "resolved", "wontfix", "invalid", "duplicate",
-- "on hold", "closed".  Any state other than "open" maps to the closed family.

-- Derive a canonical issues action from an issue:updated payload.
local function bb_issue_updated_action(payload)
  local changes = payload.changes or {}
  local status = changes.status or {}
  local new_status = status.new
  local old_status = status.old
  if new_status then
    if new_status == "open" and old_status and old_status ~= "open" then
      return "reopened"
    elseif new_status ~= "open" and old_status == "open" then
      return "closed"
    end
  end
  return "edited"
end

b:webhook("issue:created", function(payload)
  return make_internal_event({
    event = "issues",
    action = "opened",
    provider = "bitbucket",
    raw = payload,
    data = {
      action = "opened",
      issue = translate_bb_issue(payload.issue or {}),
      repository = translate_bb_repo(payload.repository or {}),
      sender = translate_bb_user(payload.actor or {}),
    },
    timestamp = (payload.issue or {}).created_on or "",
  })
end)

b:webhook("issue:updated", function(payload)
  local action = bb_issue_updated_action(payload)
  return make_internal_event({
    event = "issues",
    action = action,
    provider = "bitbucket",
    raw = payload,
    data = {
      action = action,
      issue = translate_bb_issue(payload.issue or {}),
      repository = translate_bb_repo(payload.repository or {}),
      sender = translate_bb_user(payload.actor or {}),
    },
    timestamp = (payload.issue or {}).updated_on or "",
  })
end)

b:webhook("issue:comment_created", function(payload)
  return make_internal_event({
    event = "issue_comment",
    action = "created",
    provider = "bitbucket",
    raw = payload,
    data = {
      action = "created",
      issue = translate_bb_issue(payload.issue or {}),
      comment = translate_bb_issue_comment(payload.comment or {}),
      repository = translate_bb_repo(payload.repository or {}),
      sender = translate_bb_user(payload.actor or {}),
    },
    timestamp = (payload.comment or {}).created_on or "",
  })
end)

-- repo:commit_comment_created: commit comment created.
-- Bitbucket Cloud sends only created events for commit comments.
b:webhook("repo:commit_comment_created", function(payload)
  return make_internal_event({
    event = "commit_comment",
    action = "created",
    provider = "bitbucket",
    raw = payload,
    data = {
      action = "created",
      comment = translate_bb_commit_comment(payload.comment or {}),
      repository = translate_bb_repo(payload.repository or {}),
      sender = translate_bb_user(payload.actor or {}),
    },
    timestamp = (payload.comment or {}).created_on or "",
  })
end)

-- pull_request: opened, synchronize, closed.
-- Registered for X-Event-Key: pullrequest:created, :updated, :fulfilled, :rejected.
-- Bitbucket Cloud does not expose separate events for edited or reopen; all
-- non-lifecycle changes (new commits, title edits, and PR reopens from DECLINED)
-- arrive as pullrequest:updated, which confusio maps to synchronize.
local function bb_pr_event(payload, action)
  local raw_pr = payload.pullrequest or {}
  return make_internal_event({
    event = "pull_request",
    action = action,
    provider = "bitbucket",
    raw = payload,
    data = {
      action = action,
      number = raw_pr.id,
      pull_request = translate_bb_pull(raw_pr),
      repository = translate_bb_repo(payload.repository or {}),
      sender = translate_bb_user(payload.actor or {}),
    },
    timestamp = raw_pr.updated_on or "",
  })
end

b:webhook("pullrequest:created", function(payload)
  return bb_pr_event(payload, "opened")
end)

b:webhook("pullrequest:updated", function(payload)
  return bb_pr_event(payload, "synchronize")
end)

b:webhook("pullrequest:fulfilled", function(payload)
  -- fulfilled = merged
  return bb_pr_event(payload, "closed")
end)

b:webhook("pullrequest:rejected", function(payload)
  -- rejected = declined
  return bb_pr_event(payload, "closed")
end)

-- pull_request_review events.
-- pullrequest:approved                 → submitted / APPROVED
-- pullrequest:changes_request_created  → submitted / CHANGES_REQUESTED
-- pullrequest:unapproved               → dismissed / DISMISSED
-- pullrequest:changes_request_removed  → dismissed / DISMISSED
local function bb_review_event(payload, detail_key, action, state)
  local detail = payload[detail_key] or {}
  local reviewer = detail.user or payload.actor or {}
  local raw_pr = payload.pullrequest or {}
  local review = {
    id = 0,
    node_id = "",
    user = translate_bb_user(reviewer),
    body = "",
    state = state,
    submitted_at = detail.date or "",
    html_url = "",
    pull_request_url = "",
  }
  return make_internal_event({
    event = "pull_request_review",
    action = action,
    provider = "bitbucket",
    raw = payload,
    data = {
      action = action,
      review = review,
      pull_request = translate_bb_pull(raw_pr),
      repository = translate_bb_repo(payload.repository or {}),
      sender = translate_bb_user(payload.actor or {}),
    },
    timestamp = detail.date or raw_pr.updated_on or "",
  })
end

b:webhook("pullrequest:approved", function(payload)
  return bb_review_event(payload, "approval", "submitted", "APPROVED")
end)

b:webhook("pullrequest:changes_request_created", function(payload)
  return bb_review_event(payload, "changes_request", "submitted", "CHANGES_REQUESTED")
end)

b:webhook("pullrequest:unapproved", function(payload)
  return bb_review_event(payload, "approval", "dismissed", "DISMISSED")
end)

b:webhook("pullrequest:changes_request_removed", function(payload)
  return bb_review_event(payload, "changes_request", "dismissed", "DISMISSED")
end)

local function bb_pr_comment_event(payload, action)
  local comment = payload.comment or {}
  return make_internal_event({
    event = "pull_request_review_comment",
    action = action,
    provider = "bitbucket",
    raw = payload,
    data = {
      action = action,
      comment = translate_bb_pr_comment(comment),
      pull_request = translate_bb_pull(payload.pullrequest or {}),
      repository = translate_bb_repo(payload.repository or {}),
      sender = translate_bb_user(payload.actor or {}),
    },
    timestamp = comment.updated_on or comment.created_on or "",
  })
end

b:webhook("pullrequest:comment_created", function(payload)
  return bb_pr_comment_event(payload, "created")
end)

b:webhook("pullrequest:comment_updated", function(payload)
  return bb_pr_comment_event(payload, "edited")
end)

b:webhook("pullrequest:comment_deleted", function(payload)
  return bb_pr_comment_event(payload, "deleted")
end)

local function bb_otel_attr_value(value)
  value = value or {}
  if value.stringValue ~= nil then
    return value.stringValue
  elseif value.intValue ~= nil then
    return tonumber(value.intValue) or value.intValue
  elseif value.doubleValue ~= nil then
    return tonumber(value.doubleValue) or value.doubleValue
  elseif value.boolValue ~= nil then
    return value.boolValue
  end
  return nil
end

local function bb_otel_attrs(span)
  local attrs = {}
  for _, attr in ipairs((span or {}).attributes or {}) do
    if attr.key then
      attrs[attr.key] = bb_otel_attr_value(attr.value)
    end
  end
  return attrs
end

local function bb_otel_spans(payload)
  local spans = {}
  for _, resource_span in ipairs((payload or {}).resourceSpans or {}) do
    for _, scope_span in ipairs(resource_span.scopeSpans or {}) do
      for _, span in ipairs(scope_span.spans or {}) do
        spans[#spans + 1] = span
      end
    end
  end
  return spans
end

local function bb_otel_span_time(ns)
  if ns == nil or ns == "" then
    return ""
  end
  ns = tostring(ns)
  local seconds
  if #ns >= 10 then
    seconds = tonumber(ns:sub(1, #ns - 9))
  else
    seconds = math.floor(tonumber(ns) or 0)
  end
  if not seconds or seconds <= 0 then
    return ""
  end
  return os.date("!%Y-%m-%dT%H:%M:%SZ", seconds)
end

local function bb_first_nonempty(first, second)
  if first ~= nil and first ~= "" then
    return first
  end
  return second or ""
end

local function bb_otel_repo(attrs, payload)
  if payload.repository then
    return translate_bb_repo(payload.repository)
  end
  local full_name = attrs["pipeline.repository.full_name"] or attrs["repository.full_name"] or ""
  local owner_login, repo_name = full_name:match("^([^/]+)/(.+)$")
  repo_name = repo_name or full_name
  local owner = {
    login = owner_login or "",
    id = 0,
    node_id = "",
    avatar_url = "",
    html_url = "",
    type = "User",
  }
  return {
    id = 0,
    node_id = attrs["pipeline.repository.uuid"] or "",
    name = repo_name or "",
    full_name = full_name,
    private = false,
    owner = owner,
    html_url = "",
    description = "",
    fork = false,
    url = "",
    default_branch = attrs["pipeline.target.ref_name"] or "",
  }
end

local function bb_otel_sender(payload)
  return translate_bb_user(payload.actor or {})
end

local function bb_pipeline_result_to_conclusion(result)
  result = bb_lower(result)
  if
    result == "successful"
    or result == "success"
    or result == "complete"
    or result == "completed"
  then
    return "success"
  elseif result == "failed" or result == "failure" or result == "error" then
    return "failure"
  elseif result == "stopped" or result == "cancelled" or result == "canceled" then
    return "cancelled"
  elseif result == "skipped" then
    return "skipped"
  end
  return nil
end

local function bb_pipeline_action_status(state, result)
  local conclusion = bb_pipeline_result_to_conclusion(result)
  local state_l = bb_lower(state)
  if conclusion or state_l == "complete" or state_l == "completed" then
    return "completed", "completed", conclusion or "success"
  elseif state_l == "running" or state_l == "building" or state_l == "in_progress" then
    return "in_progress", "in_progress", nil
  end
  return "requested", "queued", nil
end

local function bb_otel_find_span(payload, names)
  for _, span in ipairs(bb_otel_spans(payload)) do
    if names[span.name or ""] then
      return span, bb_otel_attrs(span)
    end
  end
  return nil, nil
end

local function bb_otel_workflow_run_event(payload)
  local span, attrs = bb_otel_find_span(payload, { ["bbc.pipeline_run"] = true })
  if not span then
    return nil
  end
  local action, status, conclusion = bb_pipeline_action_status(
    attrs["pipeline.state.name"],
    attrs["pipeline.state.result.name"] or attrs["pipeline_run.state.result.name"]
  )
  local sender = bb_otel_sender(payload)
  local workflow_name = attrs["pipeline.name"] or "Bitbucket Pipelines"
  local workflow_run = {
    id = attrs["pipeline_run.uuid"] or span.spanId or "",
    node_id = span.spanId or "",
    name = workflow_name,
    head_branch = attrs["pipeline.target.ref_name"] or "",
    head_sha = attrs["pipeline.target.commit.hash"] or attrs["commit.hash"] or "",
    run_number = attrs["pipeline_run.run_number"] or attrs["pipeline.build_number"] or 0,
    event = bb_lower(attrs["pipeline.trigger.name"]) ~= "" and bb_lower(
      attrs["pipeline.trigger.name"]
    ) or "push",
    display_title = attrs["pipeline.name"] or workflow_name,
    status = status,
    conclusion = conclusion,
    workflow_id = attrs["pipeline.uuid"] or "",
    url = attrs["pipeline_run.url"] or "",
    html_url = attrs["pipeline_run.url"] or "",
    pull_requests = {},
    created_at = bb_otel_span_time(span.startTimeUnixNano),
    updated_at = bb_otel_span_time(span.endTimeUnixNano),
    run_attempt = 1,
    referenced_workflows = {},
    actor = sender,
    triggering_actor = sender,
  }
  local workflow = {
    id = attrs["pipeline.uuid"] or "",
    name = workflow_name,
    path = "bitbucket-pipelines.yml",
    state = "active",
    url = "",
    html_url = "",
    badge_url = "",
    created_at = "",
    updated_at = "",
  }
  return make_internal_event({
    event = "workflow_run",
    action = action,
    provider = "bitbucket",
    raw = payload,
    data = {
      action = action,
      workflow_run = workflow_run,
      workflow = workflow,
      repository = bb_otel_repo(attrs, payload),
      sender = sender,
    },
    timestamp = bb_first_nonempty(
      bb_otel_span_time(span.endTimeUnixNano),
      bb_otel_span_time(span.startTimeUnixNano)
    ),
  })
end

local BB_PIPELINE_JOB_SPANS = {
  ["bbc.step"] = true,
  ["bbc.pipeline_step"] = true,
  ["bbc.command"] = true,
  ["bbc.step.command"] = true,
  ["bbc.pipeline_container"] = true,
  ["bbc.pipeline_log"] = true,
}

local function bb_otel_workflow_job_event(payload)
  local span, attrs = bb_otel_find_span(payload, BB_PIPELINE_JOB_SPANS)
  if not span then
    return nil
  end
  local raw_result = attrs["step.state.result.name"] or attrs["command.state.result.name"]
  local raw_state = attrs["step.state.name"] or attrs["command.state.name"]
  local action, status, conclusion = bb_pipeline_action_status(raw_state, raw_result)
  local name = attrs["step.step_name"]
    or attrs["step.name"]
    or attrs["command.command"]
    or attrs["container.name"]
    or span.name
    or ""
  local job = {
    id = attrs["step.uuid"] or attrs["command.command_id"] or span.spanId or "",
    run_id = attrs["pipeline_run.uuid"] or "",
    run_url = attrs["pipeline_run.url"] or "",
    run_attempt = 1,
    node_id = span.spanId or "",
    head_sha = attrs["pipeline.target.commit.hash"] or attrs["commit.hash"] or "",
    url = attrs["step.url"] or attrs["pipeline_run.url"] or "",
    html_url = attrs["step.url"] or attrs["pipeline_run.url"] or "",
    status = status,
    conclusion = conclusion,
    started_at = bb_otel_span_time(span.startTimeUnixNano),
    completed_at = status == "completed" and bb_otel_span_time(span.endTimeUnixNano) or nil,
    name = name,
    steps = {},
    check_run_url = "",
    labels = attrs["step.instance_type"] and { attrs["step.instance_type"] } or {},
    runner_id = nil,
    runner_name = nil,
    runner_group_id = nil,
    runner_group_name = nil,
    workflow_name = attrs["pipeline.name"] or "Bitbucket Pipelines",
    head_branch = attrs["pipeline.target.ref_name"] or "",
  }
  return make_internal_event({
    event = "workflow_job",
    action = action,
    provider = "bitbucket",
    raw = payload,
    data = {
      action = action,
      workflow_job = job,
      repository = bb_otel_repo(attrs, payload),
      sender = bb_otel_sender(payload),
    },
    timestamp = bb_first_nonempty(
      bb_otel_span_time(span.endTimeUnixNano),
      bb_otel_span_time(span.startTimeUnixNano)
    ),
  })
end

b:webhook("pipeline:span_created", function(payload)
  local event = bb_otel_workflow_run_event(payload) or bb_otel_workflow_job_event(payload)
  if not event then
    return nil, "No Bitbucket pipeline span found"
  end
  return event
end)

-- Commit status events: repo:commit_status_created, repo:commit_status_updated.
-- Bitbucket Cloud emits these when an external CI system posts a build result
-- against a commit.  Both event types carry the same payload shape and map to
-- the GitHub status event.  The translated state (success/failure/pending/error)
-- is promoted to the action slot so consumers can filter by state without
-- inspecting the payload body.
-- The commit SHA is embedded in the links.commit.href URL; extract it from there.
local function bb_commit_status_event(payload)
  local cs = payload.commit_status or {}
  local state = bb_state_to_github(cs.state or "")
  local commit_href = ((cs.links or {}).commit or {}).href or ""
  local sha = commit_href:match("/commit/([0-9a-fA-F]+)$") or ""
  local repo = payload.repository or {}
  local data = {
    id = 0,
    sha = sha,
    name = repo.full_name or repo.slug or "",
    target_url = cs.url,
    context = cs.key or "",
    description = cs.description or "",
    state = state,
    commit = nil,
    branches = {},
    created_at = cs.created_on or "",
    updated_at = cs.updated_on or "",
    repository = translate_bb_repo(repo),
    sender = translate_bb_user(payload.actor or {}),
  }
  return make_internal_event({
    event = "status",
    action = state,
    provider = "bitbucket",
    raw = payload,
    data = data,
    timestamp = cs.updated_on or cs.created_on or "",
  })
end

b:webhook("repo:commit_status_created", function(payload)
  return bb_commit_status_event(payload)
end)

b:webhook("repo:commit_status_updated", function(payload)
  return bb_commit_status_event(payload)
end)

-- repo:push: branch or tag push (including creation and deletion).
--
-- Bitbucket Cloud has no separate create/delete webhook events for branches
-- or tags; all ref operations arrive as `repo:push` with `change.created` or
-- `change.closed` set to true.  Confusio routes these to the appropriate
-- GitHub event type:
--   change.created == true → GitHub create event
--   change.closed  == true → GitHub delete event
--   otherwise              → GitHub push event
--
-- When a single push updates multiple refs, only the first change is processed.
-- The full `payload.push.changes` array remains available in `raw`.
b:webhook("repo:push", function(payload)
  local changes = (payload.push or {}).changes or {}
  local change = changes[1] or {}
  local new_ref = change.new or {}
  local old_ref = change.old or {}
  local repo = payload.repository or {}
  local actor = payload.actor or {}
  local sender = translate_bb_user(actor)
  local repository = translate_bb_repo(repo)
  local ref_type = new_ref.type or old_ref.type or "branch"
  local ref_name = new_ref.name or old_ref.name or ""
  local full_ref = (ref_type == "tag") and ("refs/tags/" .. ref_name) or ("refs/heads/" .. ref_name)

  if change.created then
    -- Branch or tag created — emit GitHub create event.
    return make_internal_event({
      event = "create",
      action = "create",
      provider = "bitbucket",
      raw = payload,
      data = {
        ref = ref_name,
        ref_type = ref_type,
        master_branch = (repo.mainbranch or {}).name or "",
        description = repo.description,
        pusher_type = "user",
        repository = repository,
        sender = sender,
      },
      timestamp = "",
    })
  end

  if change.closed then
    -- Branch or tag deleted — emit GitHub delete event.
    return make_internal_event({
      event = "delete",
      action = "delete",
      provider = "bitbucket",
      raw = payload,
      data = {
        ref = ref_name,
        ref_type = ref_type,
        master_branch = (repo.mainbranch or {}).name or "",
        description = repo.description,
        pusher_type = "user",
        repository = repository,
        sender = sender,
      },
      timestamp = "",
    })
  end

  -- Regular push — emit GitHub push event.
  local ZERO_SHA = "0000000000000000000000000000000000000000"
  local before = (old_ref.target or {}).hash or ZERO_SHA
  local after = (new_ref.target or {}).hash or ZERO_SHA
  local push_commits = {}
  for _, c in ipairs(change.commits or {}) do
    push_commits[#push_commits + 1] = translate_bb_commit(c)
  end
  local head_commit = #push_commits > 0 and push_commits[1] or nil
  local compare = ((change.links or {}).html or {}).href or ""
  return make_internal_event({
    event = "push",
    action = "push",
    provider = "bitbucket",
    raw = payload,
    data = {
      ref = full_ref,
      before = before,
      after = after,
      created = false,
      deleted = false,
      forced = change.forced or false,
      compare = compare,
      commits = push_commits,
      head_commit = head_commit,
      pusher = {
        name = actor.nickname or actor.display_name or "",
        email = "",
      },
      repository = repository,
      sender = sender,
    },
    timestamp = (new_ref.target or {}).date or "",
  })
end)

-- repo:created / repo:deleted: repository lifecycle events.
-- Bitbucket Cloud sends these when a repository is created or deleted.
-- No rename or transfer events are emitted by Bitbucket Cloud; those actions
-- do not fire repository-lifecycle webhooks.
local function bb_repo_lifecycle_handler(action)
  return function(payload)
    return make_internal_event({
      event = "repository",
      action = action,
      provider = "bitbucket",
      raw = payload,
      data = {
        action = action,
        repository = translate_bb_repo(payload.repository or {}),
        sender = translate_bb_user(payload.actor or {}),
      },
      timestamp = "",
    })
  end
end

b:webhook("repo:created", bb_repo_lifecycle_handler("created"))
b:webhook("repo:deleted", bb_repo_lifecycle_handler("deleted"))

-- repo:fork: repository forked.  Bitbucket Cloud fires this event when a user
-- forks a repository.  The `fork` key holds the newly-created fork; the
-- `repository` key is the upstream source.
b:webhook("repo:fork", function(payload)
  return make_internal_event({
    event = "fork",
    action = "fork",
    provider = "bitbucket",
    raw = payload,
    data = {
      forkee = translate_bb_repo(payload.fork or {}),
      repository = translate_bb_repo(payload.repository or {}),
      sender = translate_bb_user(payload.actor or {}),
    },
    timestamp = "",
  })
end)

local BB_ACTIONLESS_NORMALIZED_EVENTS = {
  create = true,
  delete = true,
  fork = true,
  push = true,
}

local BB_NORMALIZED_WEBHOOK_EVENTS = {
  "issues",
  "issue_comment",
  "commit_comment",
  "pull_request",
  "pull_request_review",
  "pull_request_review_comment",
  "status",
  "workflow_run",
  "workflow_job",
  "push",
  "create",
  "delete",
  "repository",
  "fork",
}

local function bb_normalized_payload_without_envelope_fields(data)
  local payload = {}
  for k, v in pairs(data or {}) do
    if k ~= "sender" and k ~= "repository" then
      payload[k] = v
    end
  end
  return payload
end

local function translate_bb_normalized_webhook(internal_event, fields)
  local data = internal_event.data or {}
  fields = fields or {}
  return make_normalized_webhook_envelope(internal_event, {
    id = fields.id,
    type = fields.type
      or (
        BB_ACTIONLESS_NORMALIZED_EVENTS[internal_event.event]
          and normalized_webhook_event_type(internal_event.event, "")
        or normalized_webhook_event_type(internal_event.event, internal_event.action)
      ),
    occurred_at = fields.occurred_at,
    actor = fields.actor or data.sender,
    repository = fields.repository or data.repository,
    payload = fields.payload or bb_normalized_payload_without_envelope_fields(data),
  })
end

local function translate_bb_github_webhook(internal_event, fields)
  return github_webhook_payload(internal_event, fields)
end

for _, event in ipairs(BB_NORMALIZED_WEBHOOK_EVENTS) do
  b:webhook_translator(event, translate_bb_normalized_webhook)
  b:webhook_github_translator(event, translate_bb_github_webhook)
end

b:build()
