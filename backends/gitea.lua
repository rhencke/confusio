-- Gitea backend handler overrides.
-- Loaded by .init.lua when config.backend == "gitea", and by load_family_backend
-- for API-compatible family members (forgejo, codeberg, gogs, notabug).
-- Only endpoints that behave differently from the default need to be listed here.
if config.base_url == "" then
  config.base_url = "https://gitea.com"
end

local base = function()
  return config.base_url .. "/api/v1"
end
local auth = function()
  return make_fetch_opts("token")
end
local PAGES = { per_page = "limit", page = "page" }
local _t = make_backend_transport("token", PAGES)
local fetch_json = _t.fetch_json
local proxy_handler = _t.proxy_handler
local proxy_handler_created = _t.proxy_handler_created
local proxy_handler_paged = _t.proxy_handler_paged

-- Check if this Gitea instance allows anonymous access.
-- Sets the global backend_allow_anonymous so OnHttpRequest can gate unauthenticated requests.
do
  local ok, status, _, body = pcall(Fetch, base() .. "/settings/api", nil)
  if ok and status == 200 then
    local settings = DecodeJson(body) or {}
    backend_allow_anonymous = settings.require_signin_view ~= true
  end
end

local function translate_repos(repos)
  return translate_list(translate_repo, repos)
end

local function translate_users(users)
  return translate_list(translate_user, users)
end

local function set_204_or_error(method, url)
  local opts = auth() or {}
  opts.method = method
  proxy_204(nil, pcall(Fetch, url, opts))
end

local function proxy_users_follow_list(username, rel)
  proxy_json_paged(
    translate_users,
    PAGES,
    fetch_json(append_page_params(base() .. "/users/" .. username .. "/" .. rel, PAGES))
  )
end

-- Proxy a Gitea search response {"data":[...],"ok":true} to the GitHub search
-- envelope {"total_count":N,"incomplete_results":false,"items":[...]}.
-- translate_item is applied to each element of data[].
local function proxy_search(translate_item, url)
  proxy_search_envelope(translate_item, "data", fetch_json(url))
end

local function filter_verified_emails(emails)
  local out = {}
  for _, e in ipairs(emails or {}) do
    if e.verified then
      out[#out + 1] = e
    end
  end
  return out
end

-- Map a Gitea team object to GitHub format.
local function translate_gitea_team(t)
  if not t then
    return {}
  end
  local slug = (t.name or ""):lower():gsub("[^%w%-]", "-")
  return {
    id = t.id,
    node_id = "",
    name = t.name,
    slug = slug,
    description = t.description or "",
    privacy = "closed",
    notification_setting = "notifications_enabled",
    permission = t.permission == "owner" and "admin" or (t.permission or "pull"),
    members_url = "",
    repositories_url = "",
    parent = nil,
  }
end

-- Map a Gitea label object to GitHub format.
-- Gitea color includes a '#' prefix; GitHub does not.
local function translate_gitea_label(l)
  if not l then
    return {}
  end
  return {
    id = l.id,
    node_id = "",
    url = l.url or "",
    name = l.name,
    color = (l.color or ""):gsub("^#", ""),
    description = l.description or "",
    default = false,
  }
end

-- Map a Gitea milestone object to GitHub format.
local function translate_gitea_milestone(m)
  if not m then
    return nil
  end
  return {
    id = m.id,
    node_id = "",
    number = m.id,
    title = m.title,
    description = m.description or "",
    state = m.state or "open",
    open_issues = m.open_issues or 0,
    closed_issues = m.closed_issues or 0,
    created_at = m.created_at,
    updated_at = m.updated_at,
    closed_at = m.closed_at,
    due_on = m.due_on,
  }
end

-- Map a Gitea issue object to GitHub format.
-- Gitea timestamps use "created"/"updated"/"closed"; GitHub uses "_at" suffix.
local function translate_gitea_issue(i)
  if not i then
    return {}
  end
  local labels, assignees = {}, {}
  for _, l in ipairs(i.labels or {}) do
    labels[#labels + 1] = translate_gitea_label(l)
  end
  for _, u in ipairs(i.assignees or {}) do
    assignees[#assignees + 1] = translate_user(u)
  end
  return {
    id = i.id,
    node_id = "",
    number = i.number,
    title = i.title,
    body = i.body,
    state = i.state,
    user = translate_user(i.user),
    assignees = assignees,
    labels = labels,
    milestone = i.milestone and translate_gitea_milestone(i.milestone) or nil,
    comments = i.comments,
    created_at = i.created,
    updated_at = i.updated,
    closed_at = i.closed,
    html_url = i.html_url or "",
    url = i.url or "",
    pull_request = i.pull_request and { url = "", html_url = "", diff_url = "", patch_url = "" }
      or nil,
  }
end

-- Map a Gitea issue comment object to GitHub format.
local function translate_gitea_issue_comment(c)
  if not c then
    return {}
  end
  return {
    id = c.id,
    node_id = "",
    url = c.url or "",
    html_url = c.html_url or "",
    body = c.body,
    user = translate_user(c.user),
    created_at = c.created,
    updated_at = c.updated,
  }
end

local function translate_gitea_issues(issues)
  return translate_list(translate_gitea_issue, issues)
end
local function translate_gitea_issue_comments(comments)
  return translate_list(translate_gitea_issue_comment, comments)
end
local function translate_gitea_labels(labels)
  return translate_list(translate_gitea_label, labels)
end
local function translate_gitea_milestones(milestones)
  return translate_list(translate_gitea_milestone, milestones)
end

-- GitHub reaction content types and their integer codes.
-- Gitea reactions have no native ID; we synthesize one from user_id and content code
-- so callers can round-trip DELETE /reactions/{reaction_id} → Gitea DELETE with body.
local REACTION_CONTENT_CODE = {
  ["+1"] = 1,
  ["-1"] = 2,
  laugh = 3,
  confused = 4,
  heart = 5,
  hooray = 6,
  rocket = 7,
  eyes = 8,
}
local REACTION_BY_CODE = { "+1", "-1", "laugh", "confused", "heart", "hooray", "rocket", "eyes" }

-- Translate a single Gitea reaction to GitHub format.
-- Synthesized ID = user_id * 10 + content_code (1-8), collision-free per user.
local function translate_gitea_reaction(r)
  if not r then
    return {}
  end
  local user = translate_user(r.user or {})
  local content = r.reaction or ""
  local code = REACTION_CONTENT_CODE[content] or 0
  return {
    id = (user.id or 0) * 10 + code,
    node_id = "",
    user = user,
    content = content,
    created_at = r.created_at or "2020-01-01T00:00:00Z",
  }
end

local function translate_gitea_reactions(reactions)
  return translate_list(translate_gitea_reaction, reactions)
end

-- Map a Gitea pull request branch reference to GitHub format.
local function translate_gitea_pr_branch(b)
  if not b then
    return {}
  end
  return {
    label = b.label or b.ref or "",
    ref = b.ref or "",
    sha = b.sha or "",
    repo = b.repo and translate_repo(b.repo) or nil,
  }
end

-- Map a Gitea pull request object to GitHub format.
-- Gitea timestamps: "created"/"updated"/"closed"/"merged" (no _at suffix).
local function translate_gitea_pull(pr)
  if not pr then
    return {}
  end
  return {
    id = pr.id,
    node_id = "",
    number = pr.number,
    state = pr.state,
    locked = false,
    title = pr.title,
    body = pr.body,
    user = translate_user(pr.user),
    head = translate_gitea_pr_branch(pr.head),
    base = translate_gitea_pr_branch(pr.base),
    draft = pr.draft or false,
    created_at = pr.created,
    updated_at = pr.updated,
    closed_at = pr.closed,
    merged_at = pr.merged,
    merge_commit_sha = pr.merge_commit_sha,
    merged_by = pr.merged_by and translate_user(pr.merged_by) or nil,
    diff_url = pr.diff_url or "",
    patch_url = pr.patch_url or "",
    html_url = pr.html_url or "",
    url = pr.url or "",
    mergeable = pr.mergeable,
    comments = pr.comments,
    review_comments = pr.review_comments,
    additions = pr.additions,
    deletions = pr.deletions,
    changed_files = pr.changed_files,
  }
end

local function translate_gitea_pulls(prs)
  return translate_list(translate_gitea_pull, prs)
end

-- Map a Gitea pull request review to GitHub format.
-- Gitea type/state: APPROVED, REJECT/REQUEST_CHANGES→CHANGES_REQUESTED, COMMENT, UNKNOWN→COMMENT.
local function translate_gitea_review(r)
  if not r then
    return {}
  end
  local state = r.state or r.type or "COMMENT"
  if state == "REJECT" or state == "REQUEST_CHANGES" then
    state = "CHANGES_REQUESTED"
  elseif state ~= "APPROVED" and state ~= "DISMISSED" then
    state = "COMMENT"
  end
  return {
    id = r.id,
    node_id = "",
    user = translate_user(r.user),
    body = r.body or "",
    state = state,
    submitted_at = r.submitted_at,
    html_url = "",
    pull_request_url = "",
  }
end

local function translate_gitea_reviews(reviews)
  return translate_list(translate_gitea_review, reviews)
end

-- Map a Gitea inline review comment to GitHub format.
local function translate_gitea_review_comment(c)
  if not c then
    return {}
  end
  return {
    id = c.id,
    node_id = "",
    path = c.path or "",
    position = c.line,
    original_position = c.original_line,
    commit_id = c.commit_id or "",
    original_commit_id = c.original_commit_id or "",
    diff_hunk = c.diff_hunk or "",
    body = c.body or "",
    user = translate_user(c.user),
    created_at = c.created_at or c.created,
    updated_at = c.updated_at or c.updated,
    html_url = "",
    pull_request_url = "",
    url = "",
  }
end

local function translate_gitea_review_comments(comments)
  return translate_list(translate_gitea_review_comment, comments)
end

-- Look up a Gitea label ID by name within a repo.
local function gitea_find_label_id(owner, repo_name, label_name)
  local ok, status, _, body =
    fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/labels?limit=50")
  if not ok or status ~= 200 then
    return nil
  end
  for _, l in ipairs(DecodeJson(body) or {}) do
    if l.name == label_name then
      return l.id
    end
  end
  return nil
end

-- Look up a Gitea team ID by org and slug.  Gitea uses numeric IDs; the slug
-- is matched against the lowercased-and-slugified team name.
local function gitea_find_team_id(org, slug)
  local ok, status, _, body = fetch_json(base() .. "/orgs/" .. org .. "/teams?limit=50")
  if not ok or status ~= 200 then
    return nil
  end
  for _, t in ipairs(DecodeJson(body) or {}) do
    local ts = (t.name or ""):lower():gsub("[^%w%-]", "-")
    if ts == slug then
      return t.id
    end
  end
  return nil
end

-- Checks (via Gitea commit statuses) ------------------------------------------
--
-- GitHub Check Runs map onto Gitea commit statuses.  Gitea does not have a
-- concept of a check run independent of a commit SHA, so:
--   • create/list/list-by-ref work natively.
--   • GET/PATCH by check_run_id fall back to the default stub.
--   • Check Suites have no Gitea equivalent; post_check_suites is overridden,
--     all other suite endpoints fall back to defaults.
--   • Annotations fall back to the default empty-array handler.
--
-- Status mapping (GitHub → Gitea):
--   queued            → pending
--   in_progress       → pending
--   completed/success → success
--   completed/failure → failure
--   completed/neutral → success
--   completed/skipped → success
--   completed/(other) → error
--
-- Status mapping (Gitea → GitHub):
--   pending → status=in_progress, conclusion=null
--   success → status=completed,   conclusion=success
--   failure → status=completed,   conclusion=failure
--   error   → status=completed,   conclusion=failure
--   warning → status=completed,   conclusion=neutral

-- Translate a Gitea commit status object to a GitHub check run object.
-- id is taken from the Gitea status.id field (used as check_run_id).
local function translate_gitea_status_to_check_run(s)
  if not s then
    return {}
  end
  local gitea_state = s.state or "pending"
  local gitea_to_gh = {
    pending = { status = "in_progress", conclusion = nil },
    success = { status = "completed", conclusion = "success" },
    failure = { status = "completed", conclusion = "failure" },
    warning = { status = "completed", conclusion = "neutral" },
  }
  local mapped = gitea_to_gh[gitea_state] or { status = "completed", conclusion = "failure" }
  local gh_status, gh_conclusion = mapped.status, mapped.conclusion
  return {
    id = s.id,
    node_id = "",
    head_sha = s.context or "",
    name = s.context or "",
    status = gh_status,
    conclusion = gh_conclusion,
    started_at = s.created or s.updated,
    completed_at = gh_status == "completed" and (s.updated or s.created) or nil,
    output = {
      title = s.description or "",
      summary = s.description or "",
      text = "",
      annotations_count = 0,
      annotations_url = "",
    },
    url = s.url or "",
    html_url = s.url or "",
    details_url = s.target_url or "",
  }
end

-- Translate a list of Gitea statuses to GitHub check runs.
local function translate_gitea_statuses_to_check_runs(statuses)
  return translate_list(translate_gitea_status_to_check_run, statuses)
end

-- Map a GitHub check run request body to a Gitea commit status body.
local function gh_check_run_to_gitea_status(req)
  local status = req.status or "queued"
  local conclusion = req.conclusion
  local gh_conclusion_to_gitea = {
    success = "success",
    neutral = "success",
    skipped = "success",
    failure = "failure",
  }
  local gitea_state = status == "completed" and (gh_conclusion_to_gitea[conclusion] or "error")
    or "pending"
  return EncodeJson({
    state = gitea_state,
    target_url = req.details_url or "",
    description = (req.output and req.output.summary) or req.name or "",
    context = req.name or "",
  })
end

-- Packages --------------------------------------------------------------------

-- Map a Gitea package entry to a GitHub Package object.
-- version_count overrides the default of 1 when the caller has aggregated versions.
local function translate_gitea_package(p, version_count)
  if not p then
    return {}
  end
  return {
    id = p.id,
    name = p.name or "",
    package_type = p.type or "",
    url = "",
    html_url = p.html_url or "",
    version_count = version_count or 1,
    visibility = "public",
    owner = p.owner and translate_user(p.owner) or nil,
    repository = p.repository and translate_repo(p.repository) or nil,
    created_at = p.created_at,
    updated_at = p.created_at,
  }
end

-- Map a Gitea package entry to a GitHub PackageVersion object.
local function translate_gitea_package_version(p)
  if not p then
    return {}
  end
  return {
    id = p.id,
    name = p.version or "",
    url = "",
    package_html_url = "",
    html_url = p.html_url or "",
    license = "",
    description = "",
    created_at = p.created_at,
    updated_at = p.created_at,
    deleted_at = nil,
    metadata = { package_type = p.type or "" },
  }
end

-- Resolve the authenticated user's login name for /user/packages endpoints.
local function resolve_user_login()
  local ok, status, _, body = fetch_json(base() .. "/user")
  if ok and status == 200 then
    return (DecodeJson(body) or {}).login
  end
  return nil
end

-- List packages for an owner, translating each entry to a GitHub Package object.
local function pkg_list(owner)
  local pkg_type = GetParam("package_type") or ""
  local url = base() .. "/packages/" .. owner
  if pkg_type ~= "" then
    url = url .. "?type=" .. pkg_type
  end
  url = append_page_params(url, PAGES)
  proxy_json_paged(function(entries)
    local pkgs = {}
    for i, p in ipairs(entries) do
      pkgs[i] = translate_gitea_package(p)
    end
    return pkgs
  end, PAGES, fetch_json(url))
end

-- Get a single package by listing versions and aggregating.
local function pkg_get(owner, pkg_type, pkg_name)
  local url = base()
    .. "/packages/"
    .. owner
    .. "?type="
    .. pkg_type
    .. "&q="
    .. pkg_name
    .. "&limit=50"
  local ok, status, _, body = fetch_json(url)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local entries = {}
  for _, p in ipairs(DecodeJson(body) or {}) do
    if p.name == pkg_name then
      entries[#entries + 1] = p
    end
  end
  if #entries == 0 then
    respond_json(404, { message = "Not Found" })
    return
  end
  respond_json(200, translate_gitea_package(entries[1], #entries))
end

-- Delete all versions of a package.
local function pkg_delete(owner, pkg_type, pkg_name)
  local url = base()
    .. "/packages/"
    .. owner
    .. "?type="
    .. pkg_type
    .. "&q="
    .. pkg_name
    .. "&limit=50"
  local ok, status, _, body = fetch_json(url)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local found = false
  for _, p in ipairs(DecodeJson(body) or {}) do
    if p.name == pkg_name then
      found = true
      fetch_json(
        base() .. "/packages/" .. owner .. "/" .. pkg_type .. "/" .. pkg_name .. "/" .. p.version,
        "DELETE"
      )
    end
  end
  if not found then
    respond_json(404, { message = "Not Found" })
    return
  end
  set_preamble(204)
end

-- List versions of a specific package.
local function pkg_versions(owner, pkg_type, pkg_name)
  local url = base() .. "/packages/" .. owner .. "?type=" .. pkg_type .. "&q=" .. pkg_name
  url = append_page_params(url, PAGES)
  proxy_json_paged(function(entries)
    local versions = {}
    for _, p in ipairs(entries) do
      if p.name == pkg_name then
        versions[#versions + 1] = translate_gitea_package_version(p)
      end
    end
    return versions
  end, PAGES, fetch_json(url))
end

-- Get a single package version by ID.
local function pkg_get_version(owner, pkg_type, pkg_name, version_id)
  local url = base()
    .. "/packages/"
    .. owner
    .. "?type="
    .. pkg_type
    .. "&q="
    .. pkg_name
    .. "&limit=50"
  local ok, status, _, body = fetch_json(url)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local vid = tonumber(version_id)
  for _, p in ipairs(DecodeJson(body) or {}) do
    if p.id == vid and p.name == pkg_name then
      respond_json(200, translate_gitea_package_version(p))
      return
    end
  end
  respond_json(404, { message = "Not Found" })
end

-- Delete a single package version by ID.
local function pkg_delete_version(owner, pkg_type, pkg_name, version_id)
  local url = base()
    .. "/packages/"
    .. owner
    .. "?type="
    .. pkg_type
    .. "&q="
    .. pkg_name
    .. "&limit=50"
  local ok, status, _, body = fetch_json(url)
  if not ok then
    respond_json(503, {})
    return
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local vid = tonumber(version_id)
  for _, p in ipairs(DecodeJson(body) or {}) do
    if p.id == vid and p.name == pkg_name then
      set_204_or_error(
        "DELETE",
        base() .. "/packages/" .. owner .. "/" .. pkg_type .. "/" .. pkg_name .. "/" .. p.version
      )
      return
    end
  end
  respond_json(404, { message = "Not Found" })
end

-- Translate a Gitea Actions secret to GitHub format.
local function translate_gitea_actions_secret(s)
  return { name = s.name, created_at = s.created_at, updated_at = s.updated_at }
end

-- Translate a Gitea Actions variable to GitHub format.
local function translate_gitea_actions_variable(v)
  return { name = v.name, value = v.value, created_at = v.created_at, updated_at = v.updated_at }
end

-- Translate a Gitea Actions runner to GitHub format.
local function translate_gitea_actions_runner(r)
  return {
    id = r.id,
    name = r.name,
    os = r.os,
    status = r.status,
    busy = r.busy or false,
    labels = r.labels or {},
  }
end

-- Proxy a Gitea Actions list (plain JSON array) → GitHub envelope {total_count, key: [...]}.
local function proxy_actions_list(key, translate_fn, url)
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
  for i, item in ipairs(raw) do
    items[i] = translate_fn(item)
  end
  set_preamble()
  Write(
    '{"total_count":'
      .. #items
      .. ',"'
      .. key
      .. '":'
      .. (#items > 0 and EncodeJson(items) or "[]")
      .. "}"
  )
end

-- Given a synthesized GitHub reaction_id, extract the content string or nil.
-- Gitea DELETE reactions takes a JSON body {"content":"..."} rather than an ID.
local function reaction_content_from_id(reaction_id)
  local code = tonumber(reaction_id) and (tonumber(reaction_id) % 10) or nil
  return code and REACTION_BY_CODE[code] or nil
end

-- DELETE a Gitea reaction by URL and synthesized reaction_id.
-- Sends {"content":"..."} body; returns 204 on success.
local function delete_gitea_reaction(url, reaction_id)
  local content = reaction_content_from_id(reaction_id)
  if not content then
    respond_json(404, { message = "Not Found" })
    return
  end
  proxy_204({ 200 }, fetch_json(url, "DELETE", '{"content":"' .. content .. '"}'))
end

backend_impl = {
  -- Health check
  get_root = function()
    proxy_health_check(pcall(Fetch, base() .. "/version", auth()))
  end,

  get_rate_limit = proxy_handler(function(data)
    return { rate = data.rate or data }
  end, function()
    return base() .. "/rate_limit"
  end),

  -- GET /gitignore/templates
  get_gitignore_templates = function()
    proxy_json(nil, fetch_json(base() .. "/gitignores"))
  end,

  -- GET /gitignore/templates/{name}
  get_gitignore_template = function(name)
    proxy_json(nil, fetch_json(base() .. "/gitignores/" .. name))
  end,

  -- GET /licenses
  get_licenses = function()
    proxy_json(nil, fetch_json(base() .. "/licenses"))
  end,

  -- GET /licenses/{license}
  get_license = function(license_name)
    proxy_json(nil, fetch_json(base() .. "/licenses/" .. license_name))
  end,

  -- GET /repos/{owner}/{repo}/license
  -- Gitea has no dedicated endpoint; combine contents/LICENSE with repo license metadata.
  get_repo_license = function(owner, repo_name)
    local ok, status, _, body =
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/contents/LICENSE")
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    local content = DecodeJson(body) or {}
    local rok, rstatus, _, rbody = fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name)
    if rok and rstatus == 200 then
      content.license = (DecodeJson(rbody) or {}).license
    end
    respond_json(200, content)
  end,

  -- GET /repos/{owner}/{repo}
  get_repo = function(owner, repo_name)
    proxy_json(translate_repo, fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name))
  end,

  -- PATCH /repos/{owner}/{repo}
  patch_repo = function(owner, repo_name)
    proxy_json(
      translate_repo,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name, "PATCH", GetBody())
    )
  end,

  -- DELETE /repos/{owner}/{repo}
  delete_repo = function(owner, repo_name)
    local url = base() .. "/repos/" .. owner .. "/" .. repo_name
    local dopts = auth() or {}
    dopts.method = "DELETE"
    proxy_204(nil, pcall(Fetch, url, dopts))
  end,

  -- GET /user/repos
  get_user_repos = function()
    proxy_json_paged(
      translate_repos,
      PAGES,
      fetch_json(append_page_params(base() .. "/user/repos", PAGES))
    )
  end,

  -- POST /user/repos
  post_user_repos = function()
    proxy_json_created(translate_repo, fetch_json(base() .. "/user/repos", "POST", GetBody()))
  end,

  -- GET /orgs/{org}/repos
  get_org_repos = function(org)
    proxy_json_paged(
      translate_repos,
      PAGES,
      fetch_json(append_page_params(base() .. "/orgs/" .. org .. "/repos", PAGES))
    )
  end,

  -- POST /orgs/{org}/repos
  post_org_repos = function(org)
    proxy_json_created(
      translate_repo,
      fetch_json(base() .. "/orgs/" .. org .. "/repos", "POST", GetBody())
    )
  end,

  -- GET /repos/{owner}/{repo}/topics
  get_repo_topics = function(owner, repo_name)
    proxy_json(function(t)
      return { names = t.topics or t.names or {} }
    end, fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/topics"))
  end,

  -- PUT /repos/{owner}/{repo}/topics
  put_repo_topics = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}")
    proxy_json(
      function(t)
        return { names = t.topics or t.names or {} }
      end,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/topics",
        "PUT",
        EncodeJson({ topics = req.names or {} })
      )
    )
  end,

  -- GET /repos/{owner}/{repo}/languages
  -- Both Gitea and GitHub return { "Language": bytes } — pass through.
  get_repo_languages = function(owner, repo_name)
    proxy_json(nil, fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/languages"))
  end,

  -- GET /repos/{owner}/{repo}/contributors
  -- Gitea uses "contributions"; GitHub uses "contributions" — same key, pass through.
  get_repo_contributors = function(owner, repo_name)
    proxy_json_paged(
      nil,
      PAGES,
      fetch_json(
        append_page_params(
          base() .. "/repos/" .. owner .. "/" .. repo_name .. "/contributors",
          PAGES
        )
      )
    )
  end,

  -- GET /repos/{owner}/{repo}/tags
  -- Both Gitea and GitHub return [{ name, commit: { sha, url }, ... }] — pass through.
  get_repo_tags = function(owner, repo_name)
    proxy_json_paged(
      nil,
      PAGES,
      fetch_json(
        append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/tags", PAGES)
      )
    )
  end,

  -- Branches ------------------------------------------------------------------

  -- Gitea branch objects use commit.id instead of GitHub's commit.sha.
  -- GET /repos/{owner}/{repo}/branches
  get_repo_branches = function(owner, repo_name)
    local function tr_branches(branches)
      for _, b in ipairs(branches or {}) do
        if b.commit then
          b.commit.sha = b.commit.id
        end
      end
      return branches or {}
    end
    proxy_json_paged(
      tr_branches,
      PAGES,
      fetch_json(
        append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/branches", PAGES)
      )
    )
  end,

  -- GET /repos/{owner}/{repo}/branches/{branch}
  get_repo_branch = function(owner, repo_name, branch)
    proxy_json(function(b)
      if b and b.commit then
        b.commit.sha = b.commit.id
      end
      return b or {}
    end, fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/branches/" .. branch))
  end,

  -- Commits -------------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/commits
  get_repo_commits = function(owner, repo_name)
    proxy_json_paged(
      nil,
      PAGES,
      fetch_json(
        append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/commits", PAGES)
      )
    )
  end,

  -- GET /repos/{owner}/{repo}/commits/{ref}
  get_repo_commit = function(owner, repo_name, ref)
    proxy_json(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/commits/" .. ref)
    )
  end,

  -- Statuses ------------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/commits/{ref}/statuses
  get_commit_statuses = function(owner, repo_name, ref)
    proxy_json_paged(
      nil,
      PAGES,
      fetch_json(
        append_page_params(
          base() .. "/repos/" .. owner .. "/" .. repo_name .. "/statuses/" .. ref,
          PAGES
        )
      )
    )
  end,

  -- GET /repos/{owner}/{repo}/commits/{ref}/status  (combined)
  get_commit_combined_status = function(owner, repo_name, ref)
    proxy_json(
      nil,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/commits/" .. ref .. "/statuses"
      )
    )
  end,

  -- POST /repos/{owner}/{repo}/statuses/{sha}
  post_commit_status = function(owner, repo_name, sha)
    proxy_json_created(
      nil,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/statuses/" .. sha,
        "POST",
        GetBody()
      )
    )
  end,

  -- Contents ------------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/readme
  get_repo_readme = function(owner, repo_name)
    proxy_json(nil, fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/readme"))
  end,

  -- GET /repos/{owner}/{repo}/readme/{dir}
  get_repo_readme_dir = function(owner, repo_name, dir)
    proxy_json(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/readme/" .. dir)
    )
  end,

  -- GET /repos/{owner}/{repo}/contents/{path}
  get_repo_content = function(owner, repo_name, path)
    proxy_json(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/contents/" .. path)
    )
  end,

  -- PUT /repos/{owner}/{repo}/contents/{path}
  put_repo_content = function(owner, repo_name, path)
    proxy_json(
      nil,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/contents/" .. path,
        "PUT",
        GetBody()
      )
    )
  end,

  -- DELETE /repos/{owner}/{repo}/contents/{path}
  delete_repo_content = function(owner, repo_name, path)
    proxy_json(
      nil,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/contents/" .. path,
        "DELETE",
        GetBody()
      )
    )
  end,

  -- GET /repos/{owner}/{repo}/tarball/{ref} — redirect to Gitea's archive URL
  get_repo_tarball = function(owner, repo_name, ref)
    SetStatus(302, "Found")
    SetHeader(
      "Location",
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/archive/" .. ref .. ".tar.gz"
    )
    Write("")
  end,

  -- GET /repos/{owner}/{repo}/zipball/{ref} — redirect to Gitea's archive URL
  get_repo_zipball = function(owner, repo_name, ref)
    SetStatus(302, "Found")
    SetHeader(
      "Location",
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/archive/" .. ref .. ".zip"
    )
    Write("")
  end,

  -- Compare -------------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/compare/{basehead}
  -- Gitea uses /{owner}/{repo}/compare/{base}...{head} (3 dots) in UI, but
  -- the API endpoint uses {base}...{head} or {base}..{head} in the basehead param.
  get_repo_compare = function(owner, repo_name, basehead)
    proxy_json(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/compare/" .. basehead)
    )
  end,

  -- Collaborators -------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/collaborators
  get_repo_collaborators = function(owner, repo_name)
    proxy_json_paged(
      nil,
      PAGES,
      fetch_json(
        append_page_params(
          base() .. "/repos/" .. owner .. "/" .. repo_name .. "/collaborators",
          PAGES
        )
      )
    )
  end,

  -- GET /repos/{owner}/{repo}/collaborators/{username} — 204 if collaborator, 404 if not
  get_repo_collaborator = function(owner, repo_name, username)
    local ok, status = pcall(
      Fetch,
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/collaborators/" .. username,
      auth()
    )
    if ok and status == 204 then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(status, { message = "Not a collaborator" })
    else
      respond_json(503, {})
    end
  end,

  -- PUT /repos/{owner}/{repo}/collaborators/{username}
  put_repo_collaborator = function(owner, repo_name, username)
    proxy_204(
      { 201 },
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/collaborators/" .. username,
        "PUT",
        GetBody()
      )
    )
  end,

  -- DELETE /repos/{owner}/{repo}/collaborators/{username}
  delete_repo_collaborator = function(owner, repo_name, username)
    proxy_204(
      { 200 },
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/collaborators/" .. username,
        "DELETE"
      )
    )
  end,

  -- GET /repos/{owner}/{repo}/collaborators/{username}/permission
  get_repo_collaborator_permission = function(owner, repo_name, username)
    proxy_json(
      nil,
      fetch_json(
        base()
          .. "/repos/"
          .. owner
          .. "/"
          .. repo_name
          .. "/collaborators/"
          .. username
          .. "/permission"
      )
    )
  end,

  -- Forks ---------------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/forks
  get_repo_forks = function(owner, repo_name)
    proxy_json_paged(
      translate_repos,
      PAGES,
      fetch_json(
        append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/forks", PAGES)
      )
    )
  end,

  -- POST /repos/{owner}/{repo}/forks
  post_repo_forks = function(owner, repo_name)
    proxy_json_created(
      translate_repo,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/forks", "POST", GetBody())
    )
  end,

  -- Releases ------------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/releases
  get_repo_releases = function(owner, repo_name)
    proxy_json_paged(
      nil,
      PAGES,
      fetch_json(
        append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases", PAGES)
      )
    )
  end,

  -- POST /repos/{owner}/{repo}/releases
  post_repo_releases = function(owner, repo_name)
    proxy_json_created(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases", "POST", GetBody())
    )
  end,

  -- GET /repos/{owner}/{repo}/releases/latest
  get_repo_release_latest = function(owner, repo_name)
    proxy_json(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/latest")
    )
  end,

  -- GET /repos/{owner}/{repo}/releases/tags/{tag}
  get_repo_release_by_tag = function(owner, repo_name, tag)
    proxy_json(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/tags/" .. tag)
    )
  end,

  -- GET /repos/{owner}/{repo}/releases/{release_id}
  get_repo_release = function(owner, repo_name, release_id)
    proxy_json(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/" .. release_id)
    )
  end,

  -- PATCH /repos/{owner}/{repo}/releases/{release_id}
  patch_repo_release = function(owner, repo_name, release_id)
    proxy_json(
      nil,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/" .. release_id,
        "PATCH",
        GetBody()
      )
    )
  end,

  -- DELETE /repos/{owner}/{repo}/releases/{release_id}
  delete_repo_release = function(owner, repo_name, release_id)
    proxy_204(
      { 200 },
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/" .. release_id,
        "DELETE"
      )
    )
  end,

  -- GET /repos/{owner}/{repo}/releases/{release_id}/assets
  get_repo_release_assets = function(owner, repo_name, release_id)
    proxy_json_paged(
      nil,
      PAGES,
      fetch_json(
        append_page_params(
          base()
            .. "/repos/"
            .. owner
            .. "/"
            .. repo_name
            .. "/releases/"
            .. release_id
            .. "/assets",
          PAGES
        )
      )
    )
  end,

  -- POST /repos/{owner}/{repo}/releases/{release_id}/assets — multipart; pass through
  post_repo_release_assets = function(owner, repo_name, release_id)
    -- Gitea uses the same multipart upload path; proxy the entire request.
    -- The Content-Type header (multipart/form-data) must be forwarded.
    local url = base()
      .. "/repos/"
      .. owner
      .. "/"
      .. repo_name
      .. "/releases/"
      .. release_id
      .. "/assets"
    local opts = auth() or {}
    opts.method = "POST"
    opts.body = GetBody()
    opts.headers = opts.headers or {}
    opts.headers["Content-Type"] = GetHeader("Content-Type") or "application/octet-stream"
    proxy_json_created(nil, pcall(Fetch, url, opts))
  end,

  -- GET /repos/{owner}/{repo}/releases/assets/{asset_id}
  get_repo_release_asset = function(owner, repo_name, asset_id)
    proxy_json(
      nil,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/assets/" .. asset_id
      )
    )
  end,

  -- PATCH /repos/{owner}/{repo}/releases/assets/{asset_id}
  patch_repo_release_asset = function(owner, repo_name, asset_id)
    proxy_json(
      nil,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/assets/" .. asset_id,
        "PATCH",
        GetBody()
      )
    )
  end,

  -- DELETE /repos/{owner}/{repo}/releases/assets/{asset_id}
  delete_repo_release_asset = function(owner, repo_name, asset_id)
    proxy_204(
      { 200 },
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/assets/" .. asset_id,
        "DELETE"
      )
    )
  end,

  -- Deploy keys ---------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/keys
  get_repo_keys = function(owner, repo_name)
    proxy_json_paged(
      nil,
      PAGES,
      fetch_json(
        append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/keys", PAGES)
      )
    )
  end,

  -- POST /repos/{owner}/{repo}/keys
  post_repo_keys = function(owner, repo_name)
    proxy_json_created(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/keys", "POST", GetBody())
    )
  end,

  -- GET /repos/{owner}/{repo}/keys/{key_id}
  get_repo_key = function(owner, repo_name, key_id)
    proxy_json(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/keys/" .. key_id)
    )
  end,

  -- DELETE /repos/{owner}/{repo}/keys/{key_id}
  delete_repo_key = function(owner, repo_name, key_id)
    proxy_204(
      { 200 },
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/keys/" .. key_id, "DELETE")
    )
  end,

  -- Webhooks ------------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/hooks
  get_repo_hooks = function(owner, repo_name)
    proxy_json_paged(
      nil,
      PAGES,
      fetch_json(
        append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks", PAGES)
      )
    )
  end,

  -- POST /repos/{owner}/{repo}/hooks
  post_repo_hooks = function(owner, repo_name)
    proxy_json_created(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks", "POST", GetBody())
    )
  end,

  -- GET /repos/{owner}/{repo}/hooks/{hook_id}
  get_repo_hook = function(owner, repo_name, hook_id)
    proxy_json(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id)
    )
  end,

  -- PATCH /repos/{owner}/{repo}/hooks/{hook_id}
  patch_repo_hook = function(owner, repo_name, hook_id)
    proxy_json(
      nil,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id,
        "PATCH",
        GetBody()
      )
    )
  end,

  -- DELETE /repos/{owner}/{repo}/hooks/{hook_id}
  delete_repo_hook = function(owner, repo_name, hook_id)
    proxy_204(
      { 200 },
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id, "DELETE")
    )
  end,

  -- GET /repos/{owner}/{repo}/hooks/{hook_id}/config
  -- Gitea stores config inline in the hook object; extract the config sub-object.
  get_repo_hook_config = function(owner, repo_name, hook_id)
    proxy_json(function(hook)
      return hook.config or {}
    end, fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id))
  end,

  -- PATCH /repos/{owner}/{repo}/hooks/{hook_id}/config
  -- Gitea has no separate config endpoint; merge into a full PATCH.
  patch_repo_hook_config = function(owner, repo_name, hook_id)
    local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id
    -- Fetch current hook, merge new config, write back.
    local ok, status, _, body = fetch_json(url)
    if not ok or status ~= 200 then
      if ok then
        respond_json(status, {})
      else
        respond_json(503, {})
      end
      return
    end
    local hook = DecodeJson(body) or {}
    local new_config = DecodeJson(GetBody() or "{}")
    hook.config = hook.config or {}
    for k, v in pairs(new_config) do
      hook.config[k] = v
    end
    proxy_json(function(h)
      return h.config or {}
    end, fetch_json(url, "PATCH", EncodeJson(hook)))
  end,

  -- POST /repos/{owner}/{repo}/hooks/{hook_id}/tests
  post_repo_hook_test = function(owner, repo_name, hook_id)
    proxy_204(
      { 200 },
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id .. "/tests",
        "POST"
      )
    )
  end,

  -- Users' repos --------------------------------------------------------------

  -- GET /users/{username}/repos
  get_users_repos = function(username)
    proxy_json_paged(
      translate_repos,
      PAGES,
      fetch_json(append_page_params(base() .. "/users/" .. username .. "/repos", PAGES))
    )
  end,

  -- GET /repositories (public repos list) — use Gitea's repo search
  get_repositories = function()
    proxy_json_paged(function(data)
      return translate_repos(data.data or {})
    end, PAGES, fetch_json(append_page_params(base() .. "/repos/search", PAGES)))
  end,

  -- Commit comments -----------------------------------------------------------

  -- GET /repos/{owner}/{repo}/comments
  get_repo_comments = function(owner, repo_name)
    proxy_json_paged(
      nil,
      PAGES,
      fetch_json(
        append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/comments", PAGES)
      )
    )
  end,

  -- GET /repos/{owner}/{repo}/comments/{comment_id}
  get_repo_comment = function(owner, repo_name, comment_id)
    proxy_json(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/comments/" .. comment_id)
    )
  end,

  -- PATCH /repos/{owner}/{repo}/comments/{comment_id}
  patch_repo_comment = function(owner, repo_name, comment_id)
    proxy_json(
      nil,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/comments/" .. comment_id,
        "PATCH",
        GetBody()
      )
    )
  end,

  -- DELETE /repos/{owner}/{repo}/comments/{comment_id}
  delete_repo_comment = function(owner, repo_name, comment_id)
    proxy_204(
      { 200 },
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/comments/" .. comment_id,
        "DELETE"
      )
    )
  end,

  -- GET /repos/{owner}/{repo}/commits/{commit_sha}/comments
  get_commit_comments = function(owner, repo_name, commit_sha)
    proxy_json_paged(
      nil,
      PAGES,
      fetch_json(
        append_page_params(
          base()
            .. "/repos/"
            .. owner
            .. "/"
            .. repo_name
            .. "/git/commits/"
            .. commit_sha
            .. "/notes",
          PAGES
        )
      )
    )
  end,

  -- POST /repos/{owner}/{repo}/commits/{commit_sha}/comments
  post_commit_comment = function(owner, repo_name, commit_sha)
    proxy_json_created(
      nil,
      fetch_json(
        base()
          .. "/repos/"
          .. owner
          .. "/"
          .. repo_name
          .. "/git/commits/"
          .. commit_sha
          .. "/notes",
        "POST",
        GetBody()
      )
    )
  end,

  -- Users ---------------------------------------------------------------------

  -- GET /user
  get_user = proxy_handler(translate_user, function()
    return base() .. "/user"
  end),

  -- PATCH /user
  patch_user = function()
    proxy_json(translate_user, fetch_json(base() .. "/user/settings", "PATCH", GetBody()))
  end,

  -- GET /users/{username}
  get_users_username = proxy_handler(translate_user, function(u)
    return base() .. "/users/" .. u
  end),

  -- GET /users
  get_users = proxy_handler_paged(translate_users, function()
    return append_page_params(base() .. "/admin/users", PAGES)
  end),

  -- GET /user/followers
  get_user_followers = proxy_handler_paged(translate_users, function()
    return append_page_params(base() .. "/user/followers", PAGES)
  end),

  -- GET /user/following
  get_user_following = proxy_handler_paged(translate_users, function()
    return append_page_params(base() .. "/user/following", PAGES)
  end),

  -- GET /user/following/{username} — 204 if following, 404 if not
  get_user_is_following = function(username)
    local ok, status = pcall(Fetch, base() .. "/user/following/" .. username, auth())
    if ok and status == 204 then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(404, { message = "Not Following" })
    else
      respond_json(503, {})
    end
  end,

  -- PUT /user/following/{username}
  put_user_following = function(username)
    set_204_or_error("PUT", base() .. "/user/following/" .. username)
  end,

  -- DELETE /user/following/{username}
  delete_user_following = function(username)
    set_204_or_error("DELETE", base() .. "/user/following/" .. username)
  end,

  -- GET /users/{username}/followers
  get_users_followers = function(username)
    proxy_users_follow_list(username, "followers")
  end,

  -- GET /users/{username}/following
  get_users_following = function(username)
    proxy_users_follow_list(username, "following")
  end,

  -- SSH Keys ------------------------------------------------------------------

  -- GET /user/keys
  get_user_keys = proxy_handler_paged(nil, function()
    return append_page_params(base() .. "/user/keys", PAGES)
  end),

  -- POST /user/keys
  post_user_keys = function()
    proxy_json_created(nil, fetch_json(base() .. "/user/keys", "POST", GetBody()))
  end,

  -- GET /user/keys/{key_id}
  get_user_key = proxy_handler(nil, function(id)
    return base() .. "/user/keys/" .. id
  end),

  -- DELETE /user/keys/{key_id}
  delete_user_key = function(key_id)
    proxy_204({ 200 }, fetch_json(base() .. "/user/keys/" .. key_id, "DELETE"))
  end,

  -- GET /users/{username}/keys
  get_users_keys = proxy_handler_paged(nil, function(u)
    return append_page_params(base() .. "/users/" .. u .. "/keys", PAGES)
  end),

  -- GPG Keys ------------------------------------------------------------------

  -- GET /user/gpg_keys
  get_user_gpg_keys = proxy_handler_paged(nil, function()
    return append_page_params(base() .. "/user/gpg_keys", PAGES)
  end),

  -- POST /user/gpg_keys
  post_user_gpg_keys = function()
    proxy_json_created(nil, fetch_json(base() .. "/user/gpg_keys", "POST", GetBody()))
  end,

  -- GET /user/gpg_keys/{gpg_key_id}
  get_user_gpg_key = proxy_handler(nil, function(id)
    return base() .. "/user/gpg_keys/" .. id
  end),

  -- DELETE /user/gpg_keys/{gpg_key_id}
  delete_user_gpg_key = function(gpg_key_id)
    proxy_204({ 200 }, fetch_json(base() .. "/user/gpg_keys/" .. gpg_key_id, "DELETE"))
  end,

  -- GET /users/{username}/gpg_keys
  get_users_gpg_keys = proxy_handler_paged(nil, function(u)
    return append_page_params(base() .. "/users/" .. u .. "/gpg_keys", PAGES)
  end),

  -- Emails --------------------------------------------------------------------

  -- GET /user/emails
  get_user_emails = proxy_handler(nil, function()
    return base() .. "/user/emails"
  end),

  -- POST /user/emails
  post_user_emails = function()
    proxy_json_created(nil, fetch_json(base() .. "/user/emails", "POST", GetBody()))
  end,

  -- DELETE /user/emails
  delete_user_emails = function()
    local opts = auth() or {}
    opts.method = "DELETE"
    opts.body = GetBody()
    opts.headers = opts.headers or {}
    opts.headers["Content-Type"] = "application/json"
    proxy_204({ 200 }, pcall(Fetch, base() .. "/user/emails", opts))
  end,

  -- GET /user/public_emails — Gitea has no separate endpoint; filter verified from /user/emails
  get_user_public_emails = proxy_handler(filter_verified_emails, function()
    return base() .. "/user/emails"
  end),

  -- Teams ---------------------------------------------------------------------
  -- Gitea teams use numeric IDs, not slugs.  find_team_id lists all teams for
  -- the org and matches by lowercased, slugified name.

  -- GET /orgs/{org}/teams
  get_org_teams = function(org)
    proxy_json_paged(function(teams)
      for i, t in ipairs(teams) do
        teams[i] = translate_gitea_team(t)
      end
      return teams
    end, PAGES, fetch_json(append_page_params(base() .. "/orgs/" .. org .. "/teams", PAGES)))
  end,

  -- POST /orgs/{org}/teams
  post_org_teams = function(org)
    local req = DecodeJson(GetBody() or "{}")
    local body = {
      name = req.name,
      description = req.description,
      permission = req.permission == "admin" and "owner" or (req.permission or "read"),
      units = { "repo.code", "repo.issues", "repo.pulls", "repo.releases" },
      includes_all_repositories = false,
    }
    proxy_json_created(
      translate_gitea_team,
      fetch_json(base() .. "/orgs/" .. org .. "/teams", "POST", EncodeJson(body))
    )
  end,

  -- GET /orgs/{org}/teams/{team_slug}
  get_org_team = function(org, slug)
    local id = gitea_find_team_id(org, slug)
    if not id then
      respond_json(404, { message = "Not Found" })
      return
    end
    proxy_json(translate_gitea_team, fetch_json(base() .. "/teams/" .. id))
  end,

  -- PATCH /orgs/{org}/teams/{team_slug}
  patch_org_team = function(org, slug)
    local id = gitea_find_team_id(org, slug)
    if not id then
      respond_json(404, { message = "Not Found" })
      return
    end
    local req = DecodeJson(GetBody() or "{}")
    local body = {}
    if req.name then
      body.name = req.name
    end
    if req.description then
      body.description = req.description
    end
    if req.permission then
      body.permission = req.permission == "admin" and "owner" or req.permission
    end
    proxy_json(
      translate_gitea_team,
      fetch_json(base() .. "/teams/" .. id, "PATCH", EncodeJson(body))
    )
  end,

  -- DELETE /orgs/{org}/teams/{team_slug}
  delete_org_team = function(org, slug)
    local id = gitea_find_team_id(org, slug)
    if not id then
      respond_json(404, { message = "Not Found" })
      return
    end
    local opts = auth() or {}
    opts.method = "DELETE"
    proxy_204(nil, pcall(Fetch, base() .. "/teams/" .. id, opts))
  end,

  -- GET /orgs/{org}/teams/{team_slug}/members
  get_org_team_members = function(org, slug)
    local id = gitea_find_team_id(org, slug)
    if not id then
      respond_json(404, { message = "Not Found" })
      return
    end
    proxy_json_paged(
      translate_users,
      PAGES,
      fetch_json(append_page_params(base() .. "/teams/" .. id .. "/members", PAGES))
    )
  end,

  -- GET /orgs/{org}/teams/{team_slug}/memberships/{username}
  get_org_team_membership = function(org, slug, username)
    local id = gitea_find_team_id(org, slug)
    if not id then
      respond_json(404, { message = "Not Found" })
      return
    end
    local ok, status = pcall(Fetch, base() .. "/teams/" .. id .. "/members/" .. username, auth())
    if ok and status == 204 then
      respond_json(200, { url = "", role = "member", state = "active" })
    elseif ok then
      respond_json(404, { message = "Not Found" })
    else
      respond_json(503, {})
    end
  end,

  -- PUT /orgs/{org}/teams/{team_slug}/memberships/{username}
  put_org_team_membership = function(org, slug, username)
    local id = gitea_find_team_id(org, slug)
    if not id then
      respond_json(404, { message = "Not Found" })
      return
    end
    local opts = auth() or {}
    opts.method = "PUT"
    local ok, status = pcall(Fetch, base() .. "/teams/" .. id .. "/members/" .. username, opts)
    if ok and (status == 204 or status == 200) then
      respond_json(200, { url = "", role = "member", state = "active" })
    elseif ok then
      respond_json(status, {})
    else
      respond_json(503, {})
    end
  end,

  -- DELETE /orgs/{org}/teams/{team_slug}/memberships/{username}
  delete_org_team_membership = function(org, slug, username)
    local id = gitea_find_team_id(org, slug)
    if not id then
      respond_json(404, { message = "Not Found" })
      return
    end
    local opts = auth() or {}
    opts.method = "DELETE"
    proxy_204(nil, pcall(Fetch, base() .. "/teams/" .. id .. "/members/" .. username, opts))
  end,

  -- GET /orgs/{org}/teams/{team_slug}/repos
  get_org_team_repos = function(org, slug)
    local id = gitea_find_team_id(org, slug)
    if not id then
      respond_json(404, { message = "Not Found" })
      return
    end
    proxy_json_paged(function(repos)
      for i, r in ipairs(repos) do
        repos[i] = translate_repo(r)
      end
      return repos
    end, PAGES, fetch_json(append_page_params(base() .. "/teams/" .. id .. "/repos", PAGES)))
  end,

  -- GET /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}
  get_org_team_repo = function(org, slug, owner, repo_name)
    local id = gitea_find_team_id(org, slug)
    if not id then
      respond_json(404, { message = "Not Found" })
      return
    end
    local ok, status, _, body =
      fetch_json(base() .. "/teams/" .. id .. "/repos/" .. owner .. "/" .. repo_name)
    if ok and (status == 204 or status == 200) then
      local r = (status == 200 and DecodeJson(body)) or {}
      respond_json(200, translate_repo(r))
    elseif ok then
      respond_json(404, { message = "Not Found" })
    else
      respond_json(503, {})
    end
  end,

  -- PUT /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}
  put_org_team_repo = function(org, slug, owner, repo_name)
    local id = gitea_find_team_id(org, slug)
    if not id then
      respond_json(404, { message = "Not Found" })
      return
    end
    local opts = auth() or {}
    opts.method = "PUT"
    proxy_204(
      nil,
      pcall(Fetch, base() .. "/teams/" .. id .. "/repos/" .. owner .. "/" .. repo_name, opts)
    )
  end,

  -- DELETE /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}
  delete_org_team_repo = function(org, slug, owner, repo_name)
    local id = gitea_find_team_id(org, slug)
    if not id then
      respond_json(404, { message = "Not Found" })
      return
    end
    local opts = auth() or {}
    opts.method = "DELETE"
    proxy_204(
      nil,
      pcall(Fetch, base() .. "/teams/" .. id .. "/repos/" .. owner .. "/" .. repo_name, opts)
    )
  end,

  -- Issues -------------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/issues
  get_repo_issues = proxy_handler_paged(translate_gitea_issues, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/issues", PAGES)
  end),

  -- POST /repos/{owner}/{repo}/issues
  post_repo_issues = proxy_handler_created(translate_gitea_issue, function(o, r)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues", "POST", GetBody()
  end),

  -- GET /repos/{owner}/{repo}/issues/{issue_number}
  get_repo_issue = proxy_handler(translate_gitea_issue, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n
  end),

  -- PATCH /repos/{owner}/{repo}/issues/{issue_number}
  patch_repo_issue = proxy_handler(translate_gitea_issue, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n, "PATCH", GetBody()
  end),

  -- GET /repos/{owner}/{repo}/issues/comments  (all issue comments in repo)
  get_repo_issue_comments = proxy_handler_paged(translate_gitea_issue_comments, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/issues/comments", PAGES)
  end),

  -- GET /repos/{owner}/{repo}/issues/comments/{comment_id}
  get_repo_issue_comment = proxy_handler(translate_gitea_issue_comment, function(o, r, id)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/comments/" .. id
  end),

  -- PATCH /repos/{owner}/{repo}/issues/comments/{comment_id}
  patch_repo_issue_comment = proxy_handler(translate_gitea_issue_comment, function(o, r, id)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/comments/" .. id, "PATCH", GetBody()
  end),

  -- DELETE /repos/{owner}/{repo}/issues/comments/{comment_id}
  delete_repo_issue_comment = function(owner, repo_name, comment_id)
    proxy_204(
      { 200 },
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/comments/" .. comment_id,
        "DELETE"
      )
    )
  end,

  -- GET /repos/{owner}/{repo}/issues/comments/{comment_id}/reactions
  get_repo_issue_comment_reactions = proxy_handler_paged(
    translate_gitea_reactions,
    function(o, r, id)
      return append_page_params(
        base() .. "/repos/" .. o .. "/" .. r .. "/issues/comments/" .. id .. "/reactions",
        PAGES
      )
    end
  ),

  -- POST /repos/{owner}/{repo}/issues/comments/{comment_id}/reactions
  post_repo_issue_comment_reaction = proxy_handler_created(
    translate_gitea_reaction,
    function(o, r, id)
      return base() .. "/repos/" .. o .. "/" .. r .. "/issues/comments/" .. id .. "/reactions",
        "POST",
        GetBody()
    end
  ),

  -- DELETE /repos/{owner}/{repo}/issues/comments/{comment_id}/reactions/{reaction_id}
  delete_repo_issue_comment_reaction = function(owner, repo_name, comment_id, reaction_id)
    delete_gitea_reaction(
      base()
        .. "/repos/"
        .. owner
        .. "/"
        .. repo_name
        .. "/issues/comments/"
        .. comment_id
        .. "/reactions",
      reaction_id
    )
  end,

  -- GET /repos/{owner}/{repo}/issues/events  (all issue events in repo)
  get_repo_issue_events = proxy_handler_paged(nil, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/issues/events", PAGES)
  end),

  -- GET /repos/{owner}/{repo}/issues/events/{event_id}
  get_repo_issue_event = proxy_handler(nil, function(o, r, id)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/events/" .. id
  end),

  -- GET /repos/{owner}/{repo}/issues/{issue_number}/comments
  get_issue_comments = proxy_handler_paged(translate_gitea_issue_comments, function(o, r, n)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/comments",
      PAGES
    )
  end),

  -- POST /repos/{owner}/{repo}/issues/{issue_number}/comments
  post_issue_comment = proxy_handler_created(translate_gitea_issue_comment, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/comments", "POST", GetBody()
  end),

  -- GET /repos/{owner}/{repo}/issues/{issue_number}/events
  get_issue_events = proxy_handler_paged(nil, function(o, r, n)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/events",
      PAGES
    )
  end),

  -- GET /repos/{owner}/{repo}/issues/{issue_number}/timeline
  get_issue_timeline = proxy_handler_paged(nil, function(o, r, n)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/timeline",
      PAGES
    )
  end),

  -- GET /repos/{owner}/{repo}/issues/{issue_number}/reactions
  get_issue_reactions = proxy_handler_paged(translate_gitea_reactions, function(o, r, n)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/reactions",
      PAGES
    )
  end),

  -- POST /repos/{owner}/{repo}/issues/{issue_number}/reactions
  post_issue_reaction = proxy_handler_created(translate_gitea_reaction, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/reactions",
      "POST",
      GetBody()
  end),

  -- DELETE /repos/{owner}/{repo}/issues/{issue_number}/reactions/{reaction_id}
  delete_issue_reaction = function(owner, repo_name, issue_number, reaction_id)
    delete_gitea_reaction(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/" .. issue_number .. "/reactions",
      reaction_id
    )
  end,

  -- GET /repos/{owner}/{repo}/issues/{issue_number}/labels
  get_issue_labels = proxy_handler(translate_gitea_labels, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/labels"
  end),

  -- POST /repos/{owner}/{repo}/issues/{issue_number}/labels
  -- GitHub body: { labels: ["name1", ...] }; Gitea body: { labels: [id1, ...] }
  -- Look up each name to find its ID.
  post_issue_labels = function(owner, repo_name, issue_number)
    local req = DecodeJson(GetBody() or "{}")
    local ids = {}
    for _, name in ipairs(req.labels or {}) do
      local id = gitea_find_label_id(owner, repo_name, name)
      if id then
        ids[#ids + 1] = id
      end
    end
    proxy_json(
      translate_gitea_labels,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/" .. issue_number .. "/labels",
        "POST",
        EncodeJson({ labels = ids })
      )
    )
  end,

  -- PUT /repos/{owner}/{repo}/issues/{issue_number}/labels  (replace all)
  put_issue_labels = function(owner, repo_name, issue_number)
    local req = DecodeJson(GetBody() or "{}")
    local ids = {}
    for _, name in ipairs(req.labels or {}) do
      local id = gitea_find_label_id(owner, repo_name, name)
      if id then
        ids[#ids + 1] = id
      end
    end
    proxy_json(
      translate_gitea_labels,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/" .. issue_number .. "/labels",
        "PUT",
        EncodeJson({ labels = ids })
      )
    )
  end,

  -- DELETE /repos/{owner}/{repo}/issues/{issue_number}/labels  (remove all)
  delete_issue_labels = function(owner, repo_name, issue_number)
    proxy_204(
      { 200 },
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/" .. issue_number .. "/labels",
        "DELETE"
      )
    )
  end,

  -- DELETE /repos/{owner}/{repo}/issues/{issue_number}/labels/{name}
  -- GitHub uses the label name; Gitea uses the numeric label ID.
  delete_issue_label = function(owner, repo_name, issue_number, label_name)
    local id = gitea_find_label_id(owner, repo_name, label_name)
    if not id then
      respond_json(404, { message = "Label not found" })
      return
    end
    proxy_204(
      { 200 },
      fetch_json(
        base()
          .. "/repos/"
          .. owner
          .. "/"
          .. repo_name
          .. "/issues/"
          .. issue_number
          .. "/labels/"
          .. id,
        "DELETE"
      )
    )
  end,

  -- PUT /repos/{owner}/{repo}/issues/{issue_number}/lock
  put_issue_lock = function(owner, repo_name, issue_number)
    local opts = auth() or {}
    opts.method = "PUT"
    opts.body = GetBody()
    opts.headers = opts.headers or {}
    opts.headers["Content-Type"] = "application/json"
    proxy_204(
      nil,
      pcall(
        Fetch,
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/" .. issue_number .. "/lock",
        opts
      )
    )
  end,

  -- DELETE /repos/{owner}/{repo}/issues/{issue_number}/lock
  delete_issue_lock = function(owner, repo_name, issue_number)
    set_204_or_error(
      "DELETE",
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/" .. issue_number .. "/lock"
    )
  end,

  -- POST /repos/{owner}/{repo}/issues/{issue_number}/assignees
  post_issue_assignees = proxy_handler(translate_gitea_issue, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/assignees",
      "POST",
      GetBody()
  end),

  -- DELETE /repos/{owner}/{repo}/issues/{issue_number}/assignees
  delete_issue_assignees = proxy_handler(translate_gitea_issue, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/issues/" .. n .. "/assignees",
      "DELETE",
      GetBody()
  end),

  -- GET /repos/{owner}/{repo}/issues/{issue_number}/assignees/{assignee}
  -- Gitea has no direct endpoint; check the issue's assignees list.
  get_issue_assignee = function(owner, repo_name, issue_number, assignee)
    local ok, status, _, body =
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/" .. issue_number)
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    local issue = DecodeJson(body) or {}
    for _, u in ipairs(issue.assignees or {}) do
      if u.login == assignee then
        SetStatus(204, "No Content")
        return
      end
    end
    respond_json(404, { message = "Not an assignee" })
  end,

  -- Assignees -----------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/assignees  (users eligible for assignment)
  get_repo_assignees = proxy_handler_paged(translate_users, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/assignees", PAGES)
  end),

  -- Labels (repo-level) -------------------------------------------------------

  -- GET /repos/{owner}/{repo}/labels
  get_repo_labels = proxy_handler_paged(translate_gitea_labels, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/labels", PAGES)
  end),

  -- POST /repos/{owner}/{repo}/labels
  post_repo_labels = proxy_handler_created(translate_gitea_label, function(o, r)
    return base() .. "/repos/" .. o .. "/" .. r .. "/labels", "POST", GetBody()
  end),

  -- GET /repos/{owner}/{repo}/labels/{name}
  -- GitHub uses label name in the URL; Gitea uses numeric ID.
  get_repo_label = function(owner, repo_name, label_name)
    local id = gitea_find_label_id(owner, repo_name, label_name)
    if not id then
      respond_json(404, { message = "Label not found" })
      return
    end
    proxy_json(
      translate_gitea_label,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/labels/" .. id)
    )
  end,

  -- PATCH /repos/{owner}/{repo}/labels/{name}
  patch_repo_label = function(owner, repo_name, label_name)
    local id = gitea_find_label_id(owner, repo_name, label_name)
    if not id then
      respond_json(404, { message = "Label not found" })
      return
    end
    proxy_json(
      translate_gitea_label,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/labels/" .. id,
        "PATCH",
        GetBody()
      )
    )
  end,

  -- DELETE /repos/{owner}/{repo}/labels/{name}
  delete_repo_label = function(owner, repo_name, label_name)
    local id = gitea_find_label_id(owner, repo_name, label_name)
    if not id then
      respond_json(404, { message = "Label not found" })
      return
    end
    proxy_204(
      { 200 },
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/labels/" .. id, "DELETE")
    )
  end,

  -- Milestones ----------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/milestones
  get_repo_milestones = proxy_handler_paged(translate_gitea_milestones, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/milestones", PAGES)
  end),

  -- POST /repos/{owner}/{repo}/milestones
  post_repo_milestones = proxy_handler_created(translate_gitea_milestone, function(o, r)
    return base() .. "/repos/" .. o .. "/" .. r .. "/milestones", "POST", GetBody()
  end),

  -- GET /repos/{owner}/{repo}/milestones/{milestone_number}
  get_repo_milestone = proxy_handler(translate_gitea_milestone, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/milestones/" .. n
  end),

  -- PATCH /repos/{owner}/{repo}/milestones/{milestone_number}
  patch_repo_milestone = proxy_handler(translate_gitea_milestone, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/milestones/" .. n, "PATCH", GetBody()
  end),

  -- DELETE /repos/{owner}/{repo}/milestones/{milestone_number}
  delete_repo_milestone = function(owner, repo_name, milestone_number)
    proxy_204(
      { 200 },
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/milestones/" .. milestone_number,
        "DELETE"
      )
    )
  end,

  -- GET /repos/{owner}/{repo}/milestones/{milestone_number}/labels
  get_repo_milestone_labels = proxy_handler(translate_gitea_labels, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/milestones/" .. n .. "/labels"
  end),

  -- Legacy team-by-id endpoints (GitHub /teams/{team_id} → Gitea /teams/{id}).
  -- No slug lookup needed — the caller already provides the numeric ID.

  -- GET /user/teams
  get_user_teams = function()
    proxy_json_paged(function(teams)
      for i, t in ipairs(teams) do
        teams[i] = translate_gitea_team(t)
      end
      return teams
    end, PAGES, fetch_json(append_page_params(base() .. "/user/teams", PAGES)))
  end,

  -- GET /teams/{team_id}
  get_team = function(team_id)
    proxy_json(translate_gitea_team, fetch_json(base() .. "/teams/" .. team_id))
  end,

  -- PATCH /teams/{team_id}
  patch_team = function(team_id)
    local req = DecodeJson(GetBody() or "{}")
    local body = {}
    if req.name then
      body.name = req.name
    end
    if req.description then
      body.description = req.description
    end
    if req.permission then
      body.permission = req.permission == "admin" and "owner" or req.permission
    end
    proxy_json(
      translate_gitea_team,
      fetch_json(base() .. "/teams/" .. team_id, "PATCH", EncodeJson(body))
    )
  end,

  -- DELETE /teams/{team_id}
  delete_team = function(team_id)
    set_204_or_error("DELETE", base() .. "/teams/" .. team_id)
  end,

  -- GET /teams/{team_id}/members
  get_team_members = function(team_id)
    proxy_json_paged(
      translate_users,
      PAGES,
      fetch_json(append_page_params(base() .. "/teams/" .. team_id .. "/members", PAGES))
    )
  end,

  -- GET /teams/{team_id}/members/{username} — deprecated legacy endpoint
  get_team_member = function(team_id, username)
    local ok, status =
      pcall(Fetch, base() .. "/teams/" .. team_id .. "/members/" .. username, auth())
    if ok and status == 204 then
      SetStatus(204, "No Content")
    elseif ok then
      respond_json(404, { message = "Not Found" })
    else
      respond_json(503, {})
    end
  end,

  -- PUT /teams/{team_id}/members/{username} — deprecated legacy endpoint
  put_team_member = function(team_id, username)
    local opts = auth() or {}
    opts.method = "PUT"
    proxy_204(
      { 200 },
      pcall(Fetch, base() .. "/teams/" .. team_id .. "/members/" .. username, opts)
    )
  end,

  -- DELETE /teams/{team_id}/members/{username} — deprecated legacy endpoint
  delete_team_member = function(team_id, username)
    set_204_or_error("DELETE", base() .. "/teams/" .. team_id .. "/members/" .. username)
  end,

  -- GET /teams/{team_id}/memberships/{username}
  get_team_membership = function(team_id, username)
    local ok, status =
      pcall(Fetch, base() .. "/teams/" .. team_id .. "/members/" .. username, auth())
    if ok and status == 204 then
      respond_json(200, { url = "", role = "member", state = "active" })
    elseif ok then
      respond_json(404, { message = "Not Found" })
    else
      respond_json(503, {})
    end
  end,

  -- PUT /teams/{team_id}/memberships/{username}
  put_team_membership = function(team_id, username)
    local opts = auth() or {}
    opts.method = "PUT"
    local ok, status = pcall(Fetch, base() .. "/teams/" .. team_id .. "/members/" .. username, opts)
    if ok and (status == 204 or status == 200) then
      respond_json(200, { url = "", role = "member", state = "active" })
    elseif ok then
      respond_json(status, {})
    else
      respond_json(503, {})
    end
  end,

  -- DELETE /teams/{team_id}/memberships/{username}
  delete_team_membership = function(team_id, username)
    set_204_or_error("DELETE", base() .. "/teams/" .. team_id .. "/members/" .. username)
  end,

  -- GET /teams/{team_id}/repos
  get_team_repos = function(team_id)
    proxy_json_paged(function(repos)
      for i, r in ipairs(repos) do
        repos[i] = translate_repo(r)
      end
      return repos
    end, PAGES, fetch_json(
      append_page_params(base() .. "/teams/" .. team_id .. "/repos", PAGES)
    ))
  end,

  -- GET /teams/{team_id}/repos/{owner}/{repo}
  get_team_repo = function(team_id, owner, repo_name)
    local ok, status, _, body =
      fetch_json(base() .. "/teams/" .. team_id .. "/repos/" .. owner .. "/" .. repo_name)
    if ok and (status == 204 or status == 200) then
      local r = (status == 200 and DecodeJson(body)) or {}
      respond_json(200, translate_repo(r))
    elseif ok then
      respond_json(404, { message = "Not Found" })
    else
      respond_json(503, {})
    end
  end,

  -- PUT /teams/{team_id}/repos/{owner}/{repo}
  put_team_repo = function(team_id, owner, repo_name)
    local opts = auth() or {}
    opts.method = "PUT"
    proxy_204(
      nil,
      pcall(Fetch, base() .. "/teams/" .. team_id .. "/repos/" .. owner .. "/" .. repo_name, opts)
    )
  end,

  -- DELETE /teams/{team_id}/repos/{owner}/{repo}
  delete_team_repo = function(team_id, owner, repo_name)
    set_204_or_error(
      "DELETE",
      base() .. "/teams/" .. team_id .. "/repos/" .. owner .. "/" .. repo_name
    )
  end,

  -- Pull Requests ---------------------------------------------------------------

  -- GET /repos/{owner}/{repo}/pulls
  get_repo_pulls = proxy_handler_paged(translate_gitea_pulls, function(o, r)
    return append_page_params(base() .. "/repos/" .. o .. "/" .. r .. "/pulls", PAGES)
  end),

  -- POST /repos/{owner}/{repo}/pulls
  post_repo_pulls = proxy_handler_created(translate_gitea_pull, function(o, r)
    return base() .. "/repos/" .. o .. "/" .. r .. "/pulls", "POST", GetBody()
  end),

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}
  get_repo_pull = proxy_handler(translate_gitea_pull, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/pulls/" .. n
  end),

  -- PATCH /repos/{owner}/{repo}/pulls/{pull_number}
  patch_repo_pull = proxy_handler(translate_gitea_pull, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/pulls/" .. n, "PATCH", GetBody()
  end),

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/commits
  get_pull_commits = proxy_handler_paged(nil, function(o, r, n)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/pulls/" .. n .. "/commits",
      PAGES
    )
  end),

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/files
  get_pull_files = proxy_handler_paged(nil, function(o, r, n)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/pulls/" .. n .. "/files",
      PAGES
    )
  end),

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/merge
  -- Gitea returns 204 if merged, 404 if not — same semantics as GitHub.
  get_pull_merge = function(owner, repo_name, pull_number)
    local ok, status = fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/pulls/" .. pull_number .. "/merge"
    )
    if ok and status == 204 then
      SetStatus(204, "No Content")
    elseif ok and status == 404 then
      respond_json(404, { message = "Pull Request is not merged" })
    elseif ok then
      respond_json(status, {})
    else
      respond_json(503, {})
    end
  end,

  -- PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge
  -- GitHub uses PUT; Gitea uses POST.
  put_pull_merge = function(owner, repo_name, pull_number)
    proxy_204(
      nil,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/pulls/" .. pull_number .. "/merge",
        "POST",
        GetBody()
      )
    )
  end,

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/requested_reviewers
  get_pull_requested_reviewers = proxy_handler(nil, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/pulls/" .. n .. "/requested_reviewers"
  end),

  -- POST /repos/{owner}/{repo}/pulls/{pull_number}/requested_reviewers
  post_pull_requested_reviewers = proxy_handler(nil, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/pulls/" .. n .. "/requested_reviewers",
      "POST",
      GetBody()
  end),

  -- DELETE /repos/{owner}/{repo}/pulls/{pull_number}/requested_reviewers
  delete_pull_requested_reviewers = function(owner, repo_name, pull_number)
    proxy_204(
      { 200 },
      fetch_json(
        base()
          .. "/repos/"
          .. owner
          .. "/"
          .. repo_name
          .. "/pulls/"
          .. pull_number
          .. "/requested_reviewers",
        "DELETE",
        GetBody()
      )
    )
  end,

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews
  get_pull_reviews = proxy_handler_paged(translate_gitea_reviews, function(o, r, n)
    return append_page_params(
      base() .. "/repos/" .. o .. "/" .. r .. "/pulls/" .. n .. "/reviews",
      PAGES
    )
  end),

  -- POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews
  post_pull_review = proxy_handler_created(translate_gitea_review, function(o, r, n)
    return base() .. "/repos/" .. o .. "/" .. r .. "/pulls/" .. n .. "/reviews", "POST", GetBody()
  end),

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}
  get_pull_review = proxy_handler(translate_gitea_review, function(o, r, n, id)
    return base() .. "/repos/" .. o .. "/" .. r .. "/pulls/" .. n .. "/reviews/" .. id
  end),

  -- DELETE /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}
  delete_pull_review = function(owner, repo_name, pull_number, review_id)
    proxy_204(
      { 200 },
      fetch_json(
        base()
          .. "/repos/"
          .. owner
          .. "/"
          .. repo_name
          .. "/pulls/"
          .. pull_number
          .. "/reviews/"
          .. review_id,
        "DELETE"
      )
    )
  end,

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}/comments
  get_pull_review_comments = proxy_handler(translate_gitea_review_comments, function(o, r, n, id)
    return base()
      .. "/repos/"
      .. o
      .. "/"
      .. r
      .. "/pulls/"
      .. n
      .. "/reviews/"
      .. id
      .. "/comments"
  end),

  -- PUT /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}/dismissals
  -- GitHub uses PUT; Gitea uses POST.
  put_pull_review_dismissal = function(owner, repo_name, pull_number, review_id)
    proxy_json(
      translate_gitea_review,
      fetch_json(
        base()
          .. "/repos/"
          .. owner
          .. "/"
          .. repo_name
          .. "/pulls/"
          .. pull_number
          .. "/reviews/"
          .. review_id
          .. "/dismissals",
        "POST",
        GetBody()
      )
    )
  end,

  -- GET /repos/{owner}/{repo}/pulls/{pull_number}/comments
  -- Aggregates inline review comments across all reviews for the PR.
  get_pull_comments = function(owner, repo_name, pull_number)
    local ok, status, _, body = fetch_json(
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/pulls/" .. pull_number .. "/reviews"
    )
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    local reviews = DecodeJson(body) or {}
    local all_comments = {}
    for _, rev in ipairs(reviews) do
      local cok, cstatus, _, cbody = fetch_json(
        base()
          .. "/repos/"
          .. owner
          .. "/"
          .. repo_name
          .. "/pulls/"
          .. pull_number
          .. "/reviews/"
          .. rev.id
          .. "/comments"
      )
      if cok and cstatus == 200 then
        for _, c in ipairs(DecodeJson(cbody) or {}) do
          all_comments[#all_comments + 1] = translate_gitea_review_comment(c)
        end
      end
    end
    respond_json(200, all_comments)
  end,

  -- Checks (via Gitea commit statuses) ------------------------------------------

  -- POST /repos/{owner}/{repo}/check-runs
  -- Maps to Gitea POST /api/v1/repos/{owner}/{repo}/statuses/{sha}.
  post_check_runs = function(owner, repo_name)
    local req = DecodeJson(GetBody() or "{}") or {}
    local sha = req.head_sha or ""
    local gitea_body = gh_check_run_to_gitea_status(req)
    proxy_json_created(
      translate_gitea_status_to_check_run,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/statuses/" .. sha,
        "POST",
        gitea_body
      )
    )
  end,

  -- GET /repos/{owner}/{repo}/commits/{ref}/check-runs
  -- Maps to Gitea GET /api/v1/repos/{owner}/{repo}/statuses/{ref}.
  get_commit_check_runs = function(owner, repo_name, ref)
    local ok, status, _, body = fetch_json(
      append_page_params(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/statuses/" .. ref,
        PAGES
      )
    )
    if ok and status == 200 then
      local statuses = DecodeJson(body) or {}
      local runs = translate_gitea_statuses_to_check_runs(statuses)
      respond_json(200, {
        total_count = #runs,
        check_runs = runs,
      })
    elseif ok then
      respond_json(status, {})
    else
      respond_json(503, {})
    end
  end,

  -- Check Suites — no Gitea equivalent; all are stubs --------------------

  -- POST /repos/{owner}/{repo}/check-suites
  post_check_suites = function(owner, repo_name)
    respond_json(201, {
      id = 1,
      node_id = "",
      head_sha = "",
      status = "completed",
      conclusion = "success",
      app = { id = 0, slug = "", name = "" },
      repository = { full_name = owner .. "/" .. repo_name },
    })
  end,

  -- Search -----------------------------------------------------------------------

  -- GET /search/repositories — maps to Gitea GET /repos/search
  search_repositories = function()
    local q = GetParam("q") or ""
    proxy_search(translate_repo, append_page_params(base() .. "/repos/search?q=" .. q, PAGES))
  end,

  -- GET /search/users — maps to Gitea GET /users/search
  search_users = function()
    local q = GetParam("q") or ""
    proxy_search(translate_user, append_page_params(base() .. "/users/search?q=" .. q, PAGES))
  end,

  -- Packages (org) ---------------------------------------------------------------

  get_org_packages = function(org)
    pkg_list(org)
  end,
  get_org_package = function(org, pkg_type, pkg_name)
    pkg_get(org, pkg_type, pkg_name)
  end,
  delete_org_package = function(org, pkg_type, pkg_name)
    pkg_delete(org, pkg_type, pkg_name)
  end,
  get_org_package_versions = function(org, pkg_type, pkg_name)
    pkg_versions(org, pkg_type, pkg_name)
  end,
  get_org_package_version = function(org, pkg_type, pkg_name, version_id)
    pkg_get_version(org, pkg_type, pkg_name, version_id)
  end,
  delete_org_package_version = function(org, pkg_type, pkg_name, version_id)
    pkg_delete_version(org, pkg_type, pkg_name, version_id)
  end,

  -- Packages (authenticated user) ------------------------------------------------

  get_user_packages = function()
    local login = resolve_user_login()
    if not login then
      respond_json(401, { message = "Requires authentication" })
      return
    end
    pkg_list(login)
  end,
  get_user_package = function(pkg_type, pkg_name)
    local login = resolve_user_login()
    if not login then
      respond_json(401, { message = "Requires authentication" })
      return
    end
    pkg_get(login, pkg_type, pkg_name)
  end,
  delete_user_package = function(pkg_type, pkg_name)
    local login = resolve_user_login()
    if not login then
      respond_json(401, { message = "Requires authentication" })
      return
    end
    pkg_delete(login, pkg_type, pkg_name)
  end,
  get_user_package_versions = function(pkg_type, pkg_name)
    local login = resolve_user_login()
    if not login then
      respond_json(401, { message = "Requires authentication" })
      return
    end
    pkg_versions(login, pkg_type, pkg_name)
  end,
  get_user_package_version = function(pkg_type, pkg_name, version_id)
    local login = resolve_user_login()
    if not login then
      respond_json(401, { message = "Requires authentication" })
      return
    end
    pkg_get_version(login, pkg_type, pkg_name, version_id)
  end,
  delete_user_package_version = function(pkg_type, pkg_name, version_id)
    local login = resolve_user_login()
    if not login then
      respond_json(401, { message = "Requires authentication" })
      return
    end
    pkg_delete_version(login, pkg_type, pkg_name, version_id)
  end,

  -- Pages (https://docs.github.com/en/rest/pages) ---------------------------------
  -- Gitea has no native GitHub Pages API.  We synthesize a minimal GET response
  -- by checking whether the repo has a "gh-pages" branch.  Write, build, and
  -- deployment endpoints have no Gitea equivalent and fall back to the default
  -- pages_not_implemented (501) handler.

  get_repo_pages = function(owner, repo_name)
    local ok, status, _, _ =
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/branches/gh-pages")
    if not ok then
      respond_json(503, {})
      return
    end
    if status ~= 200 then
      respond_json(status, {})
      return
    end
    respond_json(200, {
      url = "",
      status = "built",
      cname = nil,
      custom_404 = false,
      html_url = config.base_url .. "/" .. owner .. "/" .. repo_name,
      source = { branch = "gh-pages", path = "/" },
      public = true,
      https_enforced = false,
      build_type = "legacy",
    })
  end,

  -- Packages (public user) -------------------------------------------------------

  get_users_packages = function(username)
    pkg_list(username)
  end,
  get_users_package = function(username, pkg_type, pkg_name)
    pkg_get(username, pkg_type, pkg_name)
  end,
  delete_users_package = function(username, pkg_type, pkg_name)
    pkg_delete(username, pkg_type, pkg_name)
  end,
  get_users_package_versions = function(username, pkg_type, pkg_name)
    pkg_versions(username, pkg_type, pkg_name)
  end,
  get_users_package_version = function(username, pkg_type, pkg_name, version_id)
    pkg_get_version(username, pkg_type, pkg_name, version_id)
  end,
  delete_users_package_version = function(username, pkg_type, pkg_name, version_id)
    pkg_delete_version(username, pkg_type, pkg_name, version_id)
  end,

  -- Markdown -------------------------------------------------------------------

  -- POST /markdown → POST /api/v1/markdown
  -- Gitea accepts the same JSON body as GitHub and returns rendered HTML.
  render_markdown = function()
    local opts = auth() or {}
    opts.method = "POST"
    opts.body = GetBody()
    opts.headers = opts.headers or {}
    opts.headers["Content-Type"] = GetHeader("Content-Type") or "application/json"
    local ok, status, headers, body = pcall(Fetch, base() .. "/markdown", opts)
    if not ok then
      respond_json(503, {})
      return
    end
    local ct = (headers and (headers["Content-Type"] or headers["content-type"])) or "text/html"
    set_preamble(status, ct)
    Write(body or "")
  end,

  -- POST /markdown/raw → POST /api/v1/markdown/raw
  -- Gitea accepts raw markdown text and returns rendered HTML.
  render_markdown_raw = function()
    local opts = auth() or {}
    opts.method = "POST"
    opts.body = GetBody()
    opts.headers = opts.headers or {}
    opts.headers["Content-Type"] = "text/plain"
    local ok, status, headers, body = pcall(Fetch, base() .. "/markdown/raw", opts)
    if not ok then
      respond_json(503, {})
      return
    end
    local ct = (headers and (headers["Content-Type"] or headers["content-type"])) or "text/html"
    set_preamble(status, ct)
    Write(body or "")
  end,

  -- Actions ------------------------------------------------------------------
  -- Gitea natively supports secrets, variables, and runners (repo + org level).
  -- Workflow runs, artifacts, caches, jobs, OIDC, and permissions use defaults.
  --
  -- Secrets: list/get/delete only. GitHub encrypts secrets with NaCl before
  -- sending; Gitea stores plaintext. The wire formats are incompatible, so
  -- create/update (PUT) falls back to the default 501 handler.

  get_repo_actions_secrets = function(owner, repo)
    proxy_actions_list(
      "secrets",
      translate_gitea_actions_secret,
      base() .. "/repos/" .. owner .. "/" .. repo .. "/actions/secrets"
    )
  end,
  get_repo_actions_secret = function(owner, repo, secret_name)
    proxy_json(
      translate_gitea_actions_secret,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo .. "/actions/secrets/" .. secret_name)
    )
  end,
  delete_repo_actions_secret = function(owner, repo, secret_name)
    set_204_or_error(
      "DELETE",
      base() .. "/repos/" .. owner .. "/" .. repo .. "/actions/secrets/" .. secret_name
    )
  end,

  get_org_actions_secrets = function(org)
    proxy_actions_list(
      "secrets",
      translate_gitea_actions_secret,
      base() .. "/orgs/" .. org .. "/actions/secrets"
    )
  end,
  get_org_actions_secret = function(org, secret_name)
    proxy_json(
      translate_gitea_actions_secret,
      fetch_json(base() .. "/orgs/" .. org .. "/actions/secrets/" .. secret_name)
    )
  end,
  delete_org_actions_secret = function(org, secret_name)
    set_204_or_error("DELETE", base() .. "/orgs/" .. org .. "/actions/secrets/" .. secret_name)
  end,

  -- Variables: full CRUD. Gitea uses PUT for updates; GitHub uses PATCH.
  get_repo_actions_variables = function(owner, repo)
    proxy_actions_list(
      "variables",
      translate_gitea_actions_variable,
      base() .. "/repos/" .. owner .. "/" .. repo .. "/actions/variables"
    )
  end,
  get_repo_actions_variable = function(owner, repo, name)
    proxy_json(
      translate_gitea_actions_variable,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo .. "/actions/variables/" .. name)
    )
  end,
  post_repo_actions_variable = function(owner, repo)
    proxy_json_created(
      translate_gitea_actions_variable,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo .. "/actions/variables",
        "POST",
        GetBody()
      )
    )
  end,
  patch_repo_actions_variable = function(owner, repo, name)
    proxy_204(
      nil,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo .. "/actions/variables/" .. name,
        "PUT",
        GetBody()
      )
    )
  end,
  delete_repo_actions_variable = function(owner, repo, name)
    set_204_or_error(
      "DELETE",
      base() .. "/repos/" .. owner .. "/" .. repo .. "/actions/variables/" .. name
    )
  end,

  get_org_actions_variables = function(org)
    proxy_actions_list(
      "variables",
      translate_gitea_actions_variable,
      base() .. "/orgs/" .. org .. "/actions/variables"
    )
  end,
  get_org_actions_variable = function(org, name)
    proxy_json(
      translate_gitea_actions_variable,
      fetch_json(base() .. "/orgs/" .. org .. "/actions/variables/" .. name)
    )
  end,
  post_org_actions_variable = function(org)
    proxy_json_created(
      translate_gitea_actions_variable,
      fetch_json(base() .. "/orgs/" .. org .. "/actions/variables", "POST", GetBody())
    )
  end,
  patch_org_actions_variable = function(org, name)
    proxy_204(
      nil,
      fetch_json(base() .. "/orgs/" .. org .. "/actions/variables/" .. name, "PUT", GetBody())
    )
  end,
  delete_org_actions_variable = function(org, name)
    set_204_or_error("DELETE", base() .. "/orgs/" .. org .. "/actions/variables/" .. name)
  end,

  -- Runners: list only (individual runner operations not proxied).
  get_repo_actions_runners = function(owner, repo)
    proxy_actions_list(
      "runners",
      translate_gitea_actions_runner,
      base() .. "/repos/" .. owner .. "/" .. repo .. "/actions/runners"
    )
  end,
  get_org_actions_runners = function(org)
    proxy_actions_list(
      "runners",
      translate_gitea_actions_runner,
      base() .. "/orgs/" .. org .. "/actions/runners"
    )
  end,

  -- Git database (https://docs.github.com/en/rest/git) -----------------------

  -- GET /repos/{owner}/{repo}/git/blobs/{file_sha}
  get_git_blob = function(owner, repo_name, file_sha)
    proxy_json(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/blobs/" .. file_sha)
    )
  end,

  -- GET /repos/{owner}/{repo}/git/commits/{commit_sha}
  get_git_commit = function(owner, repo_name, commit_sha)
    proxy_json(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/commits/" .. commit_sha)
    )
  end,

  -- GET /repos/{owner}/{repo}/git/matching-refs/{ref}
  -- Gitea: GET /repos/{owner}/{repo}/git/refs/{ref} returns an array.
  list_git_matching_refs = function(owner, repo_name, ref)
    proxy_json(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/refs/" .. ref)
    )
  end,

  -- GET /repos/{owner}/{repo}/git/ref/{ref}
  -- GitHub returns a single ref object; Gitea returns an array — take the first element.
  get_git_ref = function(owner, repo_name, ref)
    proxy_json(function(arr)
      if type(arr) == "table" and arr[1] then
        return arr[1]
      end
      return arr
    end, fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/refs/" .. ref))
  end,

  -- POST /repos/{owner}/{repo}/git/refs
  create_git_ref = function(owner, repo_name)
    proxy_json_created(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/refs", "POST", GetBody())
    )
  end,

  -- DELETE /repos/{owner}/{repo}/git/refs/{ref}
  delete_git_ref = function(owner, repo_name, ref)
    set_204_or_error(
      "DELETE",
      base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/refs/" .. ref
    )
  end,

  -- GET /repos/{owner}/{repo}/git/tags/{tag_sha}
  get_git_tag = function(owner, repo_name, tag_sha)
    proxy_json(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/tags/" .. tag_sha)
    )
  end,

  -- POST /repos/{owner}/{repo}/git/tags
  create_git_tag = function(owner, repo_name)
    proxy_json_created(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/tags", "POST", GetBody())
    )
  end,

  -- GET /repos/{owner}/{repo}/git/trees/{tree_sha}
  get_git_tree = function(owner, repo_name, tree_sha)
    proxy_json(
      nil,
      fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/trees/" .. tree_sha)
    )
  end,

  -- Activity (https://docs.github.com/en/rest/activity)
  -- Gitea supports starring, watching, and subscription endpoints.
  -- Events feeds and notifications have no Gitea equivalent.

  get_repo_stargazers = function(owner, repo_name)
    proxy_json_paged(
      translate_users,
      PAGES,
      fetch_json(
        append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/stargazers", PAGES)
      )
    )
  end,

  get_repo_subscribers = function(owner, repo_name)
    proxy_json_paged(
      translate_users,
      PAGES,
      fetch_json(
        append_page_params(
          base() .. "/repos/" .. owner .. "/" .. repo_name .. "/subscribers",
          PAGES
        )
      )
    )
  end,

  get_repo_subscription = function(owner, repo_name)
    proxy_json(nil, fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/subscription"))
  end,

  put_repo_subscription = function(owner, repo_name)
    proxy_json(
      nil,
      fetch_json(
        base() .. "/repos/" .. owner .. "/" .. repo_name .. "/subscription",
        "PUT",
        GetBody()
      )
    )
  end,

  delete_repo_subscription = function(owner, repo_name)
    set_204_or_error("DELETE", base() .. "/repos/" .. owner .. "/" .. repo_name .. "/subscription")
  end,

  get_user_starred = function()
    proxy_json_paged(
      translate_repos,
      PAGES,
      fetch_json(append_page_params(base() .. "/user/starred", PAGES))
    )
  end,

  get_user_starred_repo = function(owner, repo_name)
    local ok, status = fetch_json(base() .. "/user/starred/" .. owner .. "/" .. repo_name)
    if ok and status == 204 then
      SetStatus(204, "No Content")
    elseif ok and status == 404 then
      respond_json(404, { message = "Not Found" })
    elseif ok then
      respond_json(status, {})
    else
      respond_json(503, {})
    end
  end,

  put_user_starred_repo = function(owner, repo_name)
    set_204_or_error("PUT", base() .. "/user/starred/" .. owner .. "/" .. repo_name)
  end,

  delete_user_starred_repo = function(owner, repo_name)
    set_204_or_error("DELETE", base() .. "/user/starred/" .. owner .. "/" .. repo_name)
  end,

  get_user_subscriptions = function()
    proxy_json_paged(
      translate_repos,
      PAGES,
      fetch_json(append_page_params(base() .. "/user/subscriptions", PAGES))
    )
  end,

  get_users_starred = function(username)
    proxy_json_paged(
      translate_repos,
      PAGES,
      fetch_json(append_page_params(base() .. "/users/" .. username .. "/starred", PAGES))
    )
  end,

  get_users_subscriptions = function(username)
    proxy_json_paged(
      translate_repos,
      PAGES,
      fetch_json(append_page_params(base() .. "/users/" .. username .. "/subscriptions", PAGES))
    )
  end,
}

-- ---------------------------------------------------------------------------
-- GraphQL resolvers
-- ---------------------------------------------------------------------------

-- Query.repositoryOwner: look up a User or Organization by login.
-- Tries /users/{login} first; falls back to /orgs/{login}.
-- Returns a RepositoryOwner (User or Organization) or nil when not found.
graphql_resolvers["Query.repositoryOwner"] = function(_parent, args, ctx)
  if not args.login then
    graphql_error(ctx, "repositoryOwner requires a login argument")
    return nil
  end
  local udata, _ = graphql_fetch(fetch_json, base() .. "/users/" .. args.login)
  if udata then
    return graphql_translate_user(translate_user(udata))
  end
  local odata, _ = graphql_fetch(fetch_json, base() .. "/orgs/" .. args.login)
  if odata then
    return graphql_translate_org(odata)
  end
  return nil -- not found; null is valid per spec
end

-- Query.viewer: resolve the authenticated user via GET /user.
-- If the token is absent or rejected, graphql_fetch_or_error records a
-- FORBIDDEN error and returns nil.
graphql_resolvers["Query.viewer"] = function(_parent, _args, ctx)
  local data = graphql_fetch_or_error(fetch_json, base() .. "/user", ctx, nil)
  if not data then
    return nil
  end
  local u = graphql_translate_user(translate_user(data))
  u.isViewer = true
  return u
end

-- node.Repository: fetch a repository by "owner/repo" local ID.
graphql_resolvers["node.Repository"] = function(local_id, _ctx)
  local data, _ = graphql_fetch(fetch_json, base() .. "/repos/" .. local_id)
  if not data then
    return nil
  end
  return graphql_translate_repo(translate_repo(data))
end

-- node.User: fetch a user by login.
graphql_resolvers["node.User"] = function(local_id, _ctx)
  local data, _ = graphql_fetch(fetch_json, base() .. "/users/" .. local_id)
  if not data then
    return nil
  end
  return graphql_translate_user(translate_user(data))
end

-- node.Organization: fetch an organization by login.
graphql_resolvers["node.Organization"] = function(local_id, _ctx)
  local data, _ = graphql_fetch(fetch_json, base() .. "/orgs/" .. local_id)
  if not data then
    return nil
  end
  return graphql_translate_org(data)
end

-- node.Issue: fetch an issue by "owner/repo/number" local ID.
graphql_resolvers["node.Issue"] = function(local_id, _ctx)
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ =
    graphql_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo .. "/issues/" .. number)
  if not data then
    return nil
  end
  return graphql_translate_issue(translate_gitea_issue(data), owner, repo)
end

-- node.PullRequest: fetch a pull request by "owner/repo/number" local ID.
graphql_resolvers["node.PullRequest"] = function(local_id, _ctx)
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ =
    graphql_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo .. "/pulls/" .. number)
  if not data then
    return nil
  end
  return graphql_translate_pr(translate_gitea_pull(data), owner, repo)
end

-- node.IssueComment: fetch an issue comment by "owner/repo/comment_id" local ID.
graphql_resolvers["node.IssueComment"] = function(local_id, _ctx)
  local owner, repo, cid = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ = graphql_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo .. "/issues/comments/" .. cid
  )
  if not data then
    return nil
  end
  return graphql_translate_comment(translate_gitea_issue_comment(data), owner, repo)
end

-- Query.user: look up a User by login.
-- Returns nil (and no error) when the user does not exist.
graphql_resolvers["Query.user"] = function(_parent, args, ctx)
  if not args.login then
    graphql_error(ctx, "user requires a login argument")
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, base() .. "/users/" .. args.login)
  if not data then
    return nil
  end
  return graphql_translate_user(translate_user(data))
end

-- Query.organization: look up an Organization by login.
-- Returns nil (and no error) when the organization does not exist.
graphql_resolvers["Query.organization"] = function(_parent, args, ctx)
  if not args.login then
    graphql_error(ctx, "organization requires a login argument")
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, base() .. "/orgs/" .. args.login)
  if not data then
    return nil
  end
  return graphql_translate_org(data)
end

-- Query.repository: look up a Repository by owner login and repo name.
-- Returns nil (and no error) when the repository does not exist.
graphql_resolvers["Query.repository"] = function(_parent, args, ctx)
  if not args.owner or not args.name then
    graphql_error(ctx, "repository requires owner and name arguments")
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, base() .. "/repos/" .. args.owner .. "/" .. args.name)
  if not data then
    return nil
  end
  return graphql_translate_repo(translate_repo(data))
end

-- node.Release: fetch a release by "owner/repo/release_id" local ID.
graphql_resolvers["node.Release"] = function(local_id, _ctx)
  local owner, repo, rid = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ =
    graphql_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo .. "/releases/" .. rid)
  if not data then
    return nil
  end
  return graphql_translate_release(data, owner, repo)
end

-- node.Label: fetch a label by "owner/repo/label_id" local ID.
graphql_resolvers["node.Label"] = function(local_id, _ctx)
  local owner, repo, lid = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ =
    graphql_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo .. "/labels/" .. lid)
  if not data then
    return nil
  end
  return graphql_translate_label(translate_gitea_label(data), owner, repo)
end

-- ---------------------------------------------------------------------------
-- Repository connection sub-resolvers
-- ---------------------------------------------------------------------------
-- Local pagination parameters for graphql_cursor_url (Gitea uses limit / page).
local GITEA_PAGES = { per_page = "limit", page = "page" }
-- Headers Gitea uses for the total item count.
local GITEA_TOTAL_HEADERS = { "X-Total", "X-Total-Count" }

-- Local helper: extract total from Gitea response headers.
local function gitea_total(headers)
  return (headers["X-Total"] and tonumber(headers["X-Total"]))
    or (headers["X-Total-Count"] and tonumber(headers["X-Total-Count"]))
end

-- Local helper: build a paginated Relay Connection from a Gitea list endpoint.
-- For backward pagination (last without before), prefetches total via a limit=1 request
-- so graphql_cursor_url can seek the correct last page on the subsequent full fetch.
local function gitea_repo_connection(owner, repo, suffix, args, ctx, translate_fn, make_conn)
  local url_base = base() .. "/repos/" .. owner .. "/" .. repo .. suffix
  local total
  if args.last and not args.before then
    total = graphql_prefetch_total_from_headers(fetch_json, url_base, GITEA_PAGES, GITEA_TOTAL_HEADERS)
  end
  local url = graphql_cursor_url(url_base, args, GITEA_PAGES, total)
  local data, headers, err = graphql_fetch_with_headers(fetch_json, url)
  if not data then
    graphql_error(ctx, err)
    return nil
  end
  total = gitea_total(headers) or total
  local nodes = {}
  for _, item in ipairs(data) do
    nodes[#nodes + 1] = translate_fn(item)
  end
  return make_conn(nodes, args, total, ctx)
end

-- Repository.issues: paginated list of issues (excluding pull requests).
-- Passes type=issues so Gitea omits PRs from the response.
graphql_resolvers["Repository.issues"] = function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitea_repo_connection(owner, name, "/issues?type=issues", args, ctx, function(i)
    return graphql_translate_issue(translate_gitea_issue(i), owner, name)
  end, graphql_issues_connection)
end

-- Repository.pullRequests: paginated list of pull requests.
graphql_resolvers["Repository.pullRequests"] = function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitea_repo_connection(owner, name, "/pulls", args, ctx, function(p)
    return graphql_translate_pr(translate_gitea_pull(p), owner, name)
  end, graphql_prs_connection)
end

-- Repository.releases: paginated list of releases.
-- Gitea release objects are already GitHub-REST-compatible; no intermediate translator needed.
graphql_resolvers["Repository.releases"] = function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitea_repo_connection(owner, name, "/releases", args, ctx, function(r)
    return graphql_translate_release(r, owner, name)
  end, function(n, a, t, c)
    return graphql_make_connection("Release", n, a, t, c)
  end)
end

-- Repository.labels: paginated list of labels.
graphql_resolvers["Repository.labels"] = function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitea_repo_connection(owner, name, "/labels", args, ctx, function(l)
    return graphql_translate_label(translate_gitea_label(l), owner, name)
  end, graphql_labels_connection)
end

-- Repository.milestones: paginated list of milestones.
graphql_resolvers["Repository.milestones"] = function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitea_repo_connection(owner, name, "/milestones", args, ctx, function(m)
    return graphql_translate_milestone(translate_gitea_milestone(m), owner, name)
  end, function(n, a, t, c)
    return graphql_make_connection("Milestone", n, a, t, c)
  end)
end

-- Repository.refs: paginated list of branches as Ref objects.
-- Gitea branch objects use commit.id for the SHA; we normalise to commit.sha before
-- passing to graphql_translate_ref (which uses r.commit.sha).
graphql_resolvers["Repository.refs"] = function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitea_repo_connection(owner, name, "/branches", args, ctx, function(b)
    if b.commit then
      b.commit.sha = b.commit.id
    end
    return graphql_translate_ref(b, parent)
  end, graphql_refs_connection)
end

-- Issue.comments: paginated list of comments for a single issue.
-- Decodes the Issue node ID to extract owner/repo/number, then fetches
-- /api/v1/repos/{owner}/{repo}/issues/{number}/comments.
graphql_resolvers["Issue.comments"] = function(parent, args, ctx)
  local _, local_id = decode_node_id(parent.id)
  if not local_id then
    return nil
  end
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local url_base = base() .. "/repos/" .. owner .. "/" .. repo .. "/issues/" .. number .. "/comments"
  local total
  if args.last and not args.before then
    total = graphql_prefetch_total_from_headers(fetch_json, url_base, GITEA_PAGES, GITEA_TOTAL_HEADERS)
  end
  local url = graphql_cursor_url(url_base, args, GITEA_PAGES, total)
  local data, headers, err = graphql_fetch_with_headers(fetch_json, url)
  if not data then
    graphql_error(ctx, err)
    return nil
  end
  total = gitea_total(headers) or total
  local nodes = {}
  for _, c in ipairs(data) do
    nodes[#nodes + 1] = graphql_translate_comment(translate_gitea_issue_comment(c), owner, repo)
  end
  return graphql_make_connection("IssueComment", nodes, args, total, ctx)
end

-- PullRequest.commits: paginated commit list for a pull request.
-- Decodes the PullRequest node ID (PullRequest:owner/repo/number) for coordinates,
-- then fetches /api/v1/repos/{owner}/{repo}/pulls/{number}/commits.
graphql_resolvers["PullRequest.commits"] = function(parent, args, ctx)
  local _, local_id = decode_node_id(parent.id)
  if not local_id then
    return nil
  end
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local url_base = base() .. "/repos/" .. owner .. "/" .. repo .. "/pulls/" .. number .. "/commits"
  local total
  if args.last and not args.before then
    total = graphql_prefetch_total_from_headers(fetch_json, url_base, GITEA_PAGES, GITEA_TOTAL_HEADERS)
  end
  local url = graphql_cursor_url(url_base, args, GITEA_PAGES, total)
  local data, headers, err = graphql_fetch_with_headers(fetch_json, url)
  if not data then
    graphql_error(ctx, err)
    return nil
  end
  total = gitea_total(headers) or total
  -- PullRequest.commits returns PullRequestCommitConnection, whose nodes are
  -- PullRequestCommit objects (not bare Commit objects).  Each PullRequestCommit
  -- wraps the Commit so clients can query commits { nodes { commit { oid } } }.
  local nodes = {}
  for _, c in ipairs(data) do
    local sha = c.sha or (c.commit and c.commit.id) or ""
    nodes[#nodes + 1] = {
      __typename = "PullRequestCommit",
      id = encode_node_id("PullRequestCommit", sha),
      commit = graphql_translate_commit(c),
      url = c.html_url,
    }
  end
  return graphql_make_connection("PullRequestCommit", nodes, args, total, ctx)
end

-- PullRequest.reviews: paginated review list for a pull request.
graphql_resolvers["PullRequest.reviews"] = function(parent, args, ctx)
  local _, local_id = decode_node_id(parent.id)
  if not local_id then
    return nil
  end
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local url_base = base() .. "/repos/" .. owner .. "/" .. repo .. "/pulls/" .. number .. "/reviews"
  local total
  if args.last and not args.before then
    total = graphql_prefetch_total_from_headers(fetch_json, url_base, GITEA_PAGES, GITEA_TOTAL_HEADERS)
  end
  local url = graphql_cursor_url(url_base, args, GITEA_PAGES, total)
  local data, headers, err = graphql_fetch_with_headers(fetch_json, url)
  if not data then
    graphql_error(ctx, err)
    return nil
  end
  total = gitea_total(headers) or total
  local nodes = {}
  for _, r in ipairs(data) do
    nodes[#nodes + 1] = graphql_translate_review(translate_gitea_review(r), owner, repo)
  end
  return graphql_make_connection("PullRequestReview", nodes, args, total, ctx)
end

-- Repository.collaborators: paginated list of collaborators as Users.
graphql_resolvers["Repository.collaborators"] = function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitea_repo_connection(owner, name, "/collaborators", args, ctx, function(u)
    return graphql_translate_user(translate_user(u))
  end, function(n, a, t, c)
    return graphql_make_connection("RepositoryCollaborator", n, a, t, c)
  end)
end

-- Repository.defaultBranchRef: enrich the inline stub with full branch data.
-- The parent already carries {__typename="Ref",name="main"} from graphql_translate_repo.
-- This resolver makes a second call to get the commit SHA.
-- Gitea branch objects use commit.id for the SHA; we normalise to commit.sha before
-- passing to graphql_translate_ref.
graphql_resolvers["Repository.defaultBranchRef"] = function(parent, _args, _ctx)
  local branch = parent.defaultBranchRef and parent.defaultBranchRef.name
  if not branch then
    return nil
  end
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  local data, _ =
    graphql_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. name .. "/branches/" .. branch)
  if not data then
    return nil
  end
  if data.commit then
    data.commit.sha = data.commit.id
  end
  return graphql_translate_ref(data, parent)
end

-- Repository.languages: fetch language byte-count breakdown as a LanguageConnection.
-- Gitea returns {"Language": bytes, ...}; we convert to the Relay Connection shape.
-- Language colours are not available from Gitea's API; color is always nil.
graphql_resolvers["Repository.languages"] = function(parent, _args, _ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  local data, _ =
    graphql_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. name .. "/languages")
  if not data then
    return nil
  end
  local nodes, edges = {}, {}
  local total_size = 0
  for lang_name, size in pairs(data) do
    total_size = total_size + size
    local node = {
      __typename = "Language",
      id = encode_node_id("Language", lang_name),
      name = lang_name,
      color = nil,
    }
    nodes[#nodes + 1] = node
    edges[#edges + 1] = { cursor = "", node = node, size = size }
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
end

-- ---------------------------------------------------------------------------
-- Query.search
-- ---------------------------------------------------------------------------

-- search_fetch: fetch a Gitea search endpoint and return the item array.
-- Gitea repo/user search wraps results in {"data":[...]}: pass container="data".
-- Gitea issue search returns a plain array: pass container=nil.
local function search_fetch(url, container)
  local data, _, err = graphql_fetch_with_headers(fetch_json, url)
  if not data then
    return nil, err
  end
  if container then
    return type(data[container]) == "table" and data[container] or {}, nil
  end
  return type(data) == "table" and data or {}, nil
end

-- Query.search: map GitHub GraphQL search to Gitea search endpoints.
-- Supports REPOSITORY, USER, and ISSUE types; all others return empty.
graphql_resolvers["Query.search"] = function(_parent, args, ctx)
  local query = args.query or ""
  local search_type = args.type or "REPOSITORY"
  local per_page = args.first or 30
  local q = EscapeParam(query)

  local nodes = {}
  local repo_count, user_count, issue_count = 0, 0, 0

  if search_type == "REPOSITORY" then
    local list, err =
      search_fetch(base() .. "/repos/search?q=" .. q .. "&limit=" .. per_page, "data")
    if not list then
      graphql_error(ctx, err)
    else
      for _, r in ipairs(list) do
        nodes[#nodes + 1] = graphql_translate_repo(translate_repo(r))
      end
      repo_count = #nodes
    end
  elseif search_type == "USER" then
    local list, err =
      search_fetch(base() .. "/users/search?q=" .. q .. "&limit=" .. per_page, "data")
    if not list then
      graphql_error(ctx, err)
    else
      for _, u in ipairs(list) do
        nodes[#nodes + 1] = graphql_translate_user(translate_user(u))
      end
      user_count = #nodes
    end
  elseif search_type == "ISSUE" then
    local list, err = search_fetch(
      base() .. "/repos/issues/search?q=" .. q .. "&type=issues&limit=" .. per_page,
      nil
    )
    if not list then
      graphql_error(ctx, err)
    else
      for _, i in ipairs(list) do
        nodes[#nodes + 1] = graphql_translate_issue(translate_gitea_issue(i))
      end
      issue_count = #nodes
    end
  end

  local edges = {}
  for _, node in ipairs(nodes) do
    edges[#edges + 1] = {
      __typename = "SearchResultItemEdge",
      cursor = graphql_page_to_cursor(1),
      node = node,
    }
  end
  return {
    __typename = "SearchResultItemConnection",
    nodes = nodes,
    edges = edges,
    pageInfo = {
      __typename = "PageInfo",
      hasNextPage = false,
      hasPreviousPage = false,
      startCursor = #nodes > 0 and graphql_page_to_cursor(1) or nil,
      endCursor = #nodes > 0 and graphql_page_to_cursor(1) or nil,
    },
    repositoryCount = repo_count,
    userCount = user_count,
    issueCount = issue_count,
    codeCount = 0,
    discussionCount = 0,
    wikiCount = 0,
  }
end

-- ---------------------------------------------------------------------------
-- GraphQL mutation resolvers
-- ---------------------------------------------------------------------------

-- Mutation.createRepository: create a new repository for the authenticated user or an org.
-- Input fields: name (required), description, visibility, initializeWithReadme, ownerId.
-- If ownerId decodes to an Organization, uses POST /orgs/{org}/repos; otherwise /user/repos.
graphql_resolvers["Mutation.createRepository"] = function(_parent, args, ctx)
  local input = args and args.input
  if not input or not input.name then
    return graphql_error(ctx, "createRepository requires input.name", nil, "BAD_USER_INPUT")
  end
  local cmid = get_client_mutation_id(args)
  local path
  if input.ownerId then
    local t, lid = decode_node_id(input.ownerId)
    if t == "Organization" then
      path = base() .. "/orgs/" .. lid .. "/repos"
    end
  end
  path = path or (base() .. "/user/repos")
  local body = EncodeJson({
    name = input.name,
    description = input.description,
    private = input.visibility == "PRIVATE",
    auto_init = input.initializeWithReadme,
  })
  local data = graphql_fetch_or_error(fetch_json, path, ctx, nil, "POST", body)
  if not data then
    return nil
  end
  return {
    repository = graphql_translate_repo(translate_repo(data)),
    clientMutationId = cmid,
  }
end

-- Mutation.updateRepository: update metadata for an existing repository.
-- Input fields: repositoryId (required, Repository node ID), name, description,
--   visibility, hasIssuesEnabled, hasWikiEnabled, homepageUrl.
-- Sends PATCH /repos/{owner}/{repo} with only the supplied fields.
graphql_resolvers["Mutation.updateRepository"] = function(_parent, args, ctx)
  local input = args and args.input
  if not input or not input.repositoryId then
    return graphql_error(ctx, "updateRepository requires input.repositoryId", nil, "BAD_USER_INPUT")
  end
  local cmid = get_client_mutation_id(args)
  local t, lid = decode_node_id(input.repositoryId)
  if t ~= "Repository" then
    return graphql_error(ctx, "updateRepository: invalid repositoryId", nil, "BAD_USER_INPUT")
  end
  local owner, repo = lid:match("^([^/]+)/(.+)$")
  if not owner then
    return graphql_error(ctx, "updateRepository: malformed repositoryId", nil, "BAD_USER_INPUT")
  end
  local path = base() .. "/repos/" .. owner .. "/" .. repo
  -- Map visibility enum to Gitea's boolean private field; nil if not supplied.
  local is_private = input.visibility and (input.visibility == "PRIVATE") or nil
  local body = EncodeJson({
    name = input.name,
    description = input.description,
    private = is_private,
    has_issues = input.hasIssuesEnabled,
    has_wiki = input.hasWikiEnabled,
    website = input.homepageUrl,
  })
  local data = graphql_fetch_or_error(fetch_json, path, ctx, nil, "PATCH", body)
  if not data then
    return nil
  end
  return {
    repository = graphql_translate_repo(translate_repo(data)),
    clientMutationId = cmid,
  }
end

-- Mutation.deleteRepository: permanently delete a repository.
-- Input fields: repositoryId (required, Repository node ID).
-- Sends DELETE /repos/{owner}/{repo} and expects 204 No Content.
-- The payload only contains the optional clientMutationId (no body to translate).
graphql_resolvers["Mutation.deleteRepository"] = function(_parent, args, ctx)
  local input = args and args.input
  if not input or not input.repositoryId then
    return graphql_error(ctx, "deleteRepository requires input.repositoryId", nil, "BAD_USER_INPUT")
  end
  local cmid = get_client_mutation_id(args)
  local t, lid = decode_node_id(input.repositoryId)
  if t ~= "Repository" then
    return graphql_error(ctx, "deleteRepository: invalid repositoryId", nil, "BAD_USER_INPUT")
  end
  local owner, repo = lid:match("^([^/]+)/(.+)$")
  if not owner then
    return graphql_error(ctx, "deleteRepository: malformed repositoryId", nil, "BAD_USER_INPUT")
  end
  local path = base() .. "/repos/" .. owner .. "/" .. repo
  -- DELETE /repos/{owner}/{repo} returns 204 No Content on success — no JSON body to decode.
  local ok, status = fetch_json(path, "DELETE")
  if not ok then
    graphql_error(ctx, "network error deleting repository", nil, "INTERNAL_ERROR")
    return nil
  end
  if status == 401 or status == 403 then
    graphql_error(ctx, "not authorized to delete repository", nil, "FORBIDDEN")
    return nil
  end
  if status == 404 then
    graphql_error(ctx, "repository not found", nil, "NOT_FOUND")
    return nil
  end
  if status ~= 204 then
    graphql_error(
      ctx,
      "upstream error " .. tostring(status) .. " deleting repository",
      nil,
      "INTERNAL_ERROR"
    )
    return nil
  end
  return { clientMutationId = cmid }
end

-- ---------------------------------------------------------------------------
-- Issue mutations
-- ---------------------------------------------------------------------------

-- Mutation.createIssue: create a new issue in a repository.
-- Input fields: repositoryId (required, Repository node ID), title (required),
--   body, labelIds (array of Label node IDs), assigneeIds (array of User node IDs),
--   milestoneId (Milestone node ID).
-- Sends POST /repos/{owner}/{repo}/issues and returns the created issue.
graphql_resolvers["Mutation.createIssue"] = function(_parent, args, ctx)
  local input = args and args.input
  if not input or not input.repositoryId then
    return graphql_error(ctx, "createIssue requires input.repositoryId", nil, "BAD_USER_INPUT")
  end
  if not input.title then
    return graphql_error(ctx, "createIssue requires input.title", nil, "BAD_USER_INPUT")
  end
  local cmid = get_client_mutation_id(args)
  local t, lid = decode_node_id(input.repositoryId)
  if t ~= "Repository" then
    return graphql_error(ctx, "createIssue: invalid repositoryId", nil, "BAD_USER_INPUT")
  end
  local owner, repo = lid:match("^([^/]+)/(.+)$")
  if not owner then
    return graphql_error(ctx, "createIssue: malformed repositoryId", nil, "BAD_USER_INPUT")
  end
  -- Decode labelIds → integer label IDs (Gitea accepts numeric IDs).
  local labels = {}
  for _, lid_encoded in ipairs(input.labelIds or {}) do
    local lt, llid = decode_node_id(lid_encoded)
    if lt == "Label" then
      local _, _, label_id = llid:match("^([^/]+)/([^/]+)/(.+)$")
      if label_id then
        labels[#labels + 1] = tonumber(label_id)
      end
    end
  end
  -- Decode assigneeIds → logins.
  local assignees = {}
  for _, aid_encoded in ipairs(input.assigneeIds or {}) do
    local at, alid = decode_node_id(aid_encoded)
    if at == "User" then
      assignees[#assignees + 1] = alid
    end
  end
  -- Decode milestoneId → integer milestone number.
  local milestone_id
  if input.milestoneId then
    local mt, mlid = decode_node_id(input.milestoneId)
    if mt == "Milestone" then
      local _, _, mnum = mlid:match("^([^/]+)/([^/]+)/(.+)$")
      if mnum then
        milestone_id = tonumber(mnum)
      end
    end
  end
  local path = base() .. "/repos/" .. owner .. "/" .. repo .. "/issues"
  local body = EncodeJson({
    title = input.title,
    body = input.body,
    labels = #labels > 0 and labels or nil,
    assignees = #assignees > 0 and assignees or nil,
    milestone = milestone_id,
  })
  local data = graphql_fetch_or_error(fetch_json, path, ctx, nil, "POST", body)
  if not data then
    return nil
  end
  return {
    issue = graphql_translate_issue(translate_gitea_issue(data), owner, repo),
    clientMutationId = cmid,
  }
end

-- Mutation.updateIssue: update the title, body, and/or state of an issue.
-- Input fields: id (required, Issue node ID), title, body, state (OPEN or CLOSED).
-- Sends PATCH /repos/{owner}/{repo}/issues/{number}.
graphql_resolvers["Mutation.updateIssue"] = function(_parent, args, ctx)
  local input = args and args.input
  if not input or not input.id then
    return graphql_error(ctx, "updateIssue requires input.id", nil, "BAD_USER_INPUT")
  end
  local cmid = get_client_mutation_id(args)
  local t, lid = decode_node_id(input.id)
  if t ~= "Issue" then
    return graphql_error(ctx, "updateIssue: invalid id", nil, "BAD_USER_INPUT")
  end
  local owner, repo, number = lid:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return graphql_error(ctx, "updateIssue: malformed id", nil, "BAD_USER_INPUT")
  end
  -- Map GitHub state enum to Gitea REST state string.
  local state
  if input.state == "CLOSED" then
    state = "closed"
  elseif input.state == "OPEN" then
    state = "open"
  end
  local path = base() .. "/repos/" .. owner .. "/" .. repo .. "/issues/" .. number
  local body = EncodeJson({ title = input.title, body = input.body, state = state })
  local data = graphql_fetch_or_error(fetch_json, path, ctx, nil, "PATCH", body)
  if not data then
    return nil
  end
  return {
    issue = graphql_translate_issue(translate_gitea_issue(data), owner, repo),
    clientMutationId = cmid,
  }
end

-- Mutation.closeIssue: close an open issue.
-- Input fields: issueId (required, Issue node ID).
-- Sends PATCH /repos/{owner}/{repo}/issues/{number} with state=closed.
graphql_resolvers["Mutation.closeIssue"] = function(_parent, args, ctx)
  local input = args and args.input
  if not input or not input.issueId then
    return graphql_error(ctx, "closeIssue requires input.issueId", nil, "BAD_USER_INPUT")
  end
  local cmid = get_client_mutation_id(args)
  local t, lid = decode_node_id(input.issueId)
  if t ~= "Issue" then
    return graphql_error(ctx, "closeIssue: invalid issueId", nil, "BAD_USER_INPUT")
  end
  local owner, repo, number = lid:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return graphql_error(ctx, "closeIssue: malformed issueId", nil, "BAD_USER_INPUT")
  end
  local path = base() .. "/repos/" .. owner .. "/" .. repo .. "/issues/" .. number
  local data =
    graphql_fetch_or_error(fetch_json, path, ctx, nil, "PATCH", EncodeJson({ state = "closed" }))
  if not data then
    return nil
  end
  return {
    issue = graphql_translate_issue(translate_gitea_issue(data), owner, repo),
    clientMutationId = cmid,
  }
end

-- Mutation.reopenIssue: reopen a closed issue.
-- Input fields: issueId (required, Issue node ID).
-- Sends PATCH /repos/{owner}/{repo}/issues/{number} with state=open.
graphql_resolvers["Mutation.reopenIssue"] = function(_parent, args, ctx)
  local input = args and args.input
  if not input or not input.issueId then
    return graphql_error(ctx, "reopenIssue requires input.issueId", nil, "BAD_USER_INPUT")
  end
  local cmid = get_client_mutation_id(args)
  local t, lid = decode_node_id(input.issueId)
  if t ~= "Issue" then
    return graphql_error(ctx, "reopenIssue: invalid issueId", nil, "BAD_USER_INPUT")
  end
  local owner, repo, number = lid:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return graphql_error(ctx, "reopenIssue: malformed issueId", nil, "BAD_USER_INPUT")
  end
  local path = base() .. "/repos/" .. owner .. "/" .. repo .. "/issues/" .. number
  local data =
    graphql_fetch_or_error(fetch_json, path, ctx, nil, "PATCH", EncodeJson({ state = "open" }))
  if not data then
    return nil
  end
  return {
    issue = graphql_translate_issue(translate_gitea_issue(data), owner, repo),
    clientMutationId = cmid,
  }
end

-- Mutation.createPullRequest: open a new pull request in a repository.
-- Input fields: repositoryId (required, Repository node ID), title (required),
--   body, headRefName (required, source branch), baseRefName (required, target branch).
-- Sends POST /repos/{owner}/{repo}/pulls and returns the created pull request.
graphql_resolvers["Mutation.createPullRequest"] = function(_parent, args, ctx)
  local input = args and args.input
  if not input or not input.repositoryId then
    return graphql_error(
      ctx,
      "createPullRequest requires input.repositoryId",
      nil,
      "BAD_USER_INPUT"
    )
  end
  if not input.title then
    return graphql_error(ctx, "createPullRequest requires input.title", nil, "BAD_USER_INPUT")
  end
  if not input.headRefName then
    return graphql_error(ctx, "createPullRequest requires input.headRefName", nil, "BAD_USER_INPUT")
  end
  if not input.baseRefName then
    return graphql_error(ctx, "createPullRequest requires input.baseRefName", nil, "BAD_USER_INPUT")
  end
  local cmid = get_client_mutation_id(args)
  local t, lid = decode_node_id(input.repositoryId)
  if t ~= "Repository" then
    return graphql_error(ctx, "createPullRequest: invalid repositoryId", nil, "BAD_USER_INPUT")
  end
  local owner, repo = lid:match("^([^/]+)/(.+)$")
  if not owner then
    return graphql_error(ctx, "createPullRequest: malformed repositoryId", nil, "BAD_USER_INPUT")
  end
  local path = base() .. "/repos/" .. owner .. "/" .. repo .. "/pulls"
  local body = EncodeJson({
    title = input.title,
    body = input.body,
    head = input.headRefName,
    base = input.baseRefName,
  })
  local data = graphql_fetch_or_error(fetch_json, path, ctx, nil, "POST", body)
  if not data then
    return nil
  end
  return {
    pullRequest = graphql_translate_pr(translate_gitea_pull(data), owner, repo),
    clientMutationId = cmid,
  }
end

-- Mutation.updatePullRequest: update the title, body, and/or base branch of a pull request.
-- Input fields: pullRequestId (required, PullRequest node ID), title, body, baseRefName.
-- Sends PATCH /repos/{owner}/{repo}/pulls/{number}.
graphql_resolvers["Mutation.updatePullRequest"] = function(_parent, args, ctx)
  local input = args and args.input
  if not input or not input.pullRequestId then
    return graphql_error(
      ctx,
      "updatePullRequest requires input.pullRequestId",
      nil,
      "BAD_USER_INPUT"
    )
  end
  local cmid = get_client_mutation_id(args)
  local t, lid = decode_node_id(input.pullRequestId)
  if t ~= "PullRequest" then
    return graphql_error(ctx, "updatePullRequest: invalid pullRequestId", nil, "BAD_USER_INPUT")
  end
  local owner, repo, number = lid:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return graphql_error(ctx, "updatePullRequest: malformed pullRequestId", nil, "BAD_USER_INPUT")
  end
  local path = base() .. "/repos/" .. owner .. "/" .. repo .. "/pulls/" .. number
  local body = EncodeJson({ title = input.title, body = input.body, base = input.baseRefName })
  local data = graphql_fetch_or_error(fetch_json, path, ctx, nil, "PATCH", body)
  if not data then
    return nil
  end
  return {
    pullRequest = graphql_translate_pr(translate_gitea_pull(data), owner, repo),
    clientMutationId = cmid,
  }
end

-- Mutation.closePullRequest: close an open pull request.
-- Input fields: pullRequestId (required, PullRequest node ID).
-- Sends PATCH /repos/{owner}/{repo}/pulls/{number} with state=closed.
graphql_resolvers["Mutation.closePullRequest"] = function(_parent, args, ctx)
  local input = args and args.input
  if not input or not input.pullRequestId then
    return graphql_error(
      ctx,
      "closePullRequest requires input.pullRequestId",
      nil,
      "BAD_USER_INPUT"
    )
  end
  local cmid = get_client_mutation_id(args)
  local t, lid = decode_node_id(input.pullRequestId)
  if t ~= "PullRequest" then
    return graphql_error(ctx, "closePullRequest: invalid pullRequestId", nil, "BAD_USER_INPUT")
  end
  local owner, repo, number = lid:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return graphql_error(ctx, "closePullRequest: malformed pullRequestId", nil, "BAD_USER_INPUT")
  end
  local path = base() .. "/repos/" .. owner .. "/" .. repo .. "/pulls/" .. number
  local data =
    graphql_fetch_or_error(fetch_json, path, ctx, nil, "PATCH", EncodeJson({ state = "closed" }))
  if not data then
    return nil
  end
  return {
    pullRequest = graphql_translate_pr(translate_gitea_pull(data), owner, repo),
    clientMutationId = cmid,
  }
end

-- Mutation.reopenPullRequest: reopen a closed pull request.
-- Input fields: pullRequestId (required, PullRequest node ID).
-- Sends PATCH /repos/{owner}/{repo}/pulls/{number} with state=open.
graphql_resolvers["Mutation.reopenPullRequest"] = function(_parent, args, ctx)
  local input = args and args.input
  if not input or not input.pullRequestId then
    return graphql_error(
      ctx,
      "reopenPullRequest requires input.pullRequestId",
      nil,
      "BAD_USER_INPUT"
    )
  end
  local cmid = get_client_mutation_id(args)
  local t, lid = decode_node_id(input.pullRequestId)
  if t ~= "PullRequest" then
    return graphql_error(ctx, "reopenPullRequest: invalid pullRequestId", nil, "BAD_USER_INPUT")
  end
  local owner, repo, number = lid:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return graphql_error(ctx, "reopenPullRequest: malformed pullRequestId", nil, "BAD_USER_INPUT")
  end
  local path = base() .. "/repos/" .. owner .. "/" .. repo .. "/pulls/" .. number
  local data =
    graphql_fetch_or_error(fetch_json, path, ctx, nil, "PATCH", EncodeJson({ state = "open" }))
  if not data then
    return nil
  end
  return {
    pullRequest = graphql_translate_pr(translate_gitea_pull(data), owner, repo),
    clientMutationId = cmid,
  }
end

-- Mutation.mergePullRequest: merge an open pull request.
-- Input fields: pullRequestId (required, PullRequest node ID), mergeMethod
--   (MERGE/SQUASH/REBASE; defaults to MERGE), commitHeadline, commitBody.
-- Sends POST /repos/{owner}/{repo}/pulls/{number}/merge (Gitea uses POST; GitHub uses PUT).
-- The merge endpoint returns 204 No Content, so the PR is re-fetched to populate the payload.
graphql_resolvers["Mutation.mergePullRequest"] = function(_parent, args, ctx)
  local input = args and args.input
  if not input or not input.pullRequestId then
    return graphql_error(
      ctx,
      "mergePullRequest requires input.pullRequestId",
      nil,
      "BAD_USER_INPUT"
    )
  end
  local cmid = get_client_mutation_id(args)
  local t, lid = decode_node_id(input.pullRequestId)
  if t ~= "PullRequest" then
    return graphql_error(ctx, "mergePullRequest: invalid pullRequestId", nil, "BAD_USER_INPUT")
  end
  local owner, repo, number = lid:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return graphql_error(ctx, "mergePullRequest: malformed pullRequestId", nil, "BAD_USER_INPUT")
  end
  -- Map GitHub mergeMethod enum to Gitea's Do field string.
  local method_map = { MERGE = "merge", SQUASH = "squash", REBASE = "rebase" }
  local do_method = method_map[input.mergeMethod or "MERGE"] or "merge"
  local merge_path = base() .. "/repos/" .. owner .. "/" .. repo .. "/pulls/" .. number .. "/merge"
  local merge_body = EncodeJson({
    Do = do_method,
    MergeTitleField = input.commitHeadline,
    MergeMessageField = input.commitBody,
  })
  -- POST to Gitea's merge endpoint; it returns 204 No Content on success.
  local ok, status = fetch_json(merge_path, "POST", merge_body)
  if not ok then
    graphql_error(ctx, "network error merging pull request", nil, "INTERNAL_ERROR")
    return nil
  end
  if status == 401 or status == 403 then
    graphql_error(ctx, "not authorized to merge pull request", nil, "FORBIDDEN")
    return nil
  end
  if status == 404 then
    graphql_error(ctx, "pull request not found", nil, "NOT_FOUND")
    return nil
  end
  if status == 405 then
    graphql_error(ctx, "pull request is not mergeable", nil, "UNPROCESSABLE")
    return nil
  end
  if status ~= 204 then
    graphql_error(
      ctx,
      "upstream error " .. tostring(status) .. " merging pull request",
      nil,
      "INTERNAL_ERROR"
    )
    return nil
  end
  -- Re-fetch the PR to return in the payload (merge returns 204, no body).
  local pr_path = base() .. "/repos/" .. owner .. "/" .. repo .. "/pulls/" .. number
  local pr_data = graphql_fetch_or_error(fetch_json, pr_path, ctx, nil)
  if not pr_data then
    return nil
  end
  return {
    pullRequest = graphql_translate_pr(translate_gitea_pull(pr_data), owner, repo),
    clientMutationId = cmid,
  }
end

-- ---------------------------------------------------------------------------
-- Comment mutations
-- ---------------------------------------------------------------------------

-- Mutation.addComment: add a comment to an issue or pull request.
-- Input fields: subjectId (required, Issue or PullRequest node ID), body (required).
-- Sends POST /repos/{owner}/{repo}/issues/{number}/comments.
-- Both Issue and PullRequest node IDs route to the /issues/{n}/comments path — Gitea
-- uses the issues endpoint for PR comments too.
-- The payload returns commentEdge (containing the new IssueComment) and clientMutationId.
graphql_resolvers["Mutation.addComment"] = function(_parent, args, ctx)
  local input = args and args.input
  if not input or not input.subjectId then
    return graphql_error(ctx, "addComment requires input.subjectId", nil, "BAD_USER_INPUT")
  end
  if not input.body then
    return graphql_error(ctx, "addComment requires input.body", nil, "BAD_USER_INPUT")
  end
  local cmid = get_client_mutation_id(args)
  local t, lid = decode_node_id(input.subjectId)
  local owner, repo, number
  if t == "Issue" or t == "PullRequest" then
    owner, repo, number = lid:match("^([^/]+)/([^/]+)/(%d+)$")
  end
  if not owner then
    return graphql_error(ctx, "addComment requires a valid issue or PR id", nil, "BAD_USER_INPUT")
  end
  local path = base() .. "/repos/" .. owner .. "/" .. repo .. "/issues/" .. number .. "/comments"
  local body = EncodeJson({ body = input.body })
  local data = graphql_fetch_or_error(fetch_json, path, ctx, nil, "POST", body)
  if not data then
    return nil
  end
  local comment = graphql_translate_comment(translate_gitea_issue_comment(data), owner, repo)
  return {
    commentEdge = {
      __typename = "IssueCommentEdge",
      cursor = graphql_page_to_cursor(1),
      node = comment,
    },
    clientMutationId = cmid,
  }
end

-- Mutation.updateIssueComment: update the body of an existing issue comment.
-- Input fields: id (required, IssueComment node ID), body (required).
-- Sends PATCH /repos/{owner}/{repo}/issues/comments/{comment_id}.
graphql_resolvers["Mutation.updateIssueComment"] = function(_parent, args, ctx)
  local input = args and args.input
  if not input or not input.id then
    return graphql_error(ctx, "updateIssueComment requires input.id", nil, "BAD_USER_INPUT")
  end
  if not input.body then
    return graphql_error(ctx, "updateIssueComment requires input.body", nil, "BAD_USER_INPUT")
  end
  local cmid = get_client_mutation_id(args)
  local t, lid = decode_node_id(input.id)
  if t ~= "IssueComment" then
    return graphql_error(ctx, "updateIssueComment: invalid id", nil, "BAD_USER_INPUT")
  end
  local owner, repo, cid = lid:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return graphql_error(ctx, "updateIssueComment: malformed id", nil, "BAD_USER_INPUT")
  end
  local path = base() .. "/repos/" .. owner .. "/" .. repo .. "/issues/comments/" .. cid
  local body = EncodeJson({ body = input.body })
  local data = graphql_fetch_or_error(fetch_json, path, ctx, nil, "PATCH", body)
  if not data then
    return nil
  end
  return {
    issueComment = graphql_translate_comment(translate_gitea_issue_comment(data), owner, repo),
    clientMutationId = cmid,
  }
end

-- Mutation.deleteIssueComment: delete an issue comment.
-- Input fields: id (required, IssueComment node ID).
-- Sends DELETE /repos/{owner}/{repo}/issues/comments/{comment_id}.
-- Returns 204 No Content on success; the payload only contains the optional clientMutationId.
graphql_resolvers["Mutation.deleteIssueComment"] = function(_parent, args, ctx)
  local input = args and args.input
  if not input or not input.id then
    return graphql_error(ctx, "deleteIssueComment requires input.id", nil, "BAD_USER_INPUT")
  end
  local cmid = get_client_mutation_id(args)
  local t, lid = decode_node_id(input.id)
  if t ~= "IssueComment" then
    return graphql_error(ctx, "deleteIssueComment: invalid id", nil, "BAD_USER_INPUT")
  end
  local owner, repo, cid = lid:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return graphql_error(ctx, "deleteIssueComment: malformed id", nil, "BAD_USER_INPUT")
  end
  local path = base() .. "/repos/" .. owner .. "/" .. repo .. "/issues/comments/" .. cid
  -- DELETE returns 204 No Content on success — no JSON body to decode.
  local ok, status = fetch_json(path, "DELETE")
  if not ok then
    graphql_error(ctx, "network error deleting issue comment", nil, "INTERNAL_ERROR")
    return nil
  end
  if status == 401 or status == 403 then
    graphql_error(ctx, "not authorized to delete issue comment", nil, "FORBIDDEN")
    return nil
  end
  if status == 404 then
    graphql_error(ctx, "issue comment not found", nil, "NOT_FOUND")
    return nil
  end
  if status ~= 204 then
    graphql_error(
      ctx,
      "upstream error " .. tostring(status) .. " deleting issue comment",
      nil,
      "INTERNAL_ERROR"
    )
    return nil
  end
  return { clientMutationId = cmid }
end

graphql_resolvers["Mutation.addStar"] = function(_parent, args, ctx)
  local input = args and args.input
  if not input or not input.starrableId then
    return graphql_error(ctx, "addStar requires input.starrableId", nil, "BAD_USER_INPUT")
  end
  local cmid = get_client_mutation_id(args)
  local t, lid = decode_node_id(input.starrableId)
  if t ~= "Repository" then
    return graphql_error(ctx, "addStar: invalid starrableId", nil, "BAD_USER_INPUT")
  end
  local owner, repo = lid:match("^([^/]+)/(.+)$")
  if not owner then
    return graphql_error(ctx, "addStar: malformed starrableId", nil, "BAD_USER_INPUT")
  end
  local star_path = base() .. "/user/starred/" .. owner .. "/" .. repo
  -- PUT returns 204 No Content on success.
  local ok, status = fetch_json(star_path, "PUT")
  if not ok then
    graphql_error(ctx, "network error starring repository", nil, "INTERNAL_ERROR")
    return nil
  end
  if status == 401 or status == 403 then
    graphql_error(ctx, "not authorized to star repository", nil, "FORBIDDEN")
    return nil
  end
  if status == 404 then
    graphql_error(ctx, "repository not found", nil, "NOT_FOUND")
    return nil
  end
  if status ~= 204 then
    graphql_error(
      ctx,
      "upstream error " .. tostring(status) .. " starring repository",
      nil,
      "INTERNAL_ERROR"
    )
    return nil
  end
  -- Re-fetch the repository to return in the payload (star returns 204, no body).
  local repo_path = base() .. "/repos/" .. owner .. "/" .. repo
  local repo_data = graphql_fetch_or_error(fetch_json, repo_path, ctx, nil)
  if not repo_data then
    return nil
  end
  return {
    starrable = graphql_translate_repo(translate_repo(repo_data)),
    clientMutationId = cmid,
  }
end

graphql_resolvers["Mutation.removeStar"] = function(_parent, args, ctx)
  local input = args and args.input
  if not input or not input.starrableId then
    return graphql_error(ctx, "removeStar requires input.starrableId", nil, "BAD_USER_INPUT")
  end
  local cmid = get_client_mutation_id(args)
  local t, lid = decode_node_id(input.starrableId)
  if t ~= "Repository" then
    return graphql_error(ctx, "removeStar: invalid starrableId", nil, "BAD_USER_INPUT")
  end
  local owner, repo = lid:match("^([^/]+)/(.+)$")
  if not owner then
    return graphql_error(ctx, "removeStar: malformed starrableId", nil, "BAD_USER_INPUT")
  end
  local star_path = base() .. "/user/starred/" .. owner .. "/" .. repo
  -- DELETE returns 204 No Content on success.
  local ok, status = fetch_json(star_path, "DELETE")
  if not ok then
    graphql_error(ctx, "network error unstarring repository", nil, "INTERNAL_ERROR")
    return nil
  end
  if status == 401 or status == 403 then
    graphql_error(ctx, "not authorized to unstar repository", nil, "FORBIDDEN")
    return nil
  end
  if status == 404 then
    graphql_error(ctx, "repository not found", nil, "NOT_FOUND")
    return nil
  end
  if status ~= 204 then
    graphql_error(
      ctx,
      "upstream error " .. tostring(status) .. " unstarring repository",
      nil,
      "INTERNAL_ERROR"
    )
    return nil
  end
  -- Re-fetch the repository to return in the payload (unstar returns 204, no body).
  local repo_path = base() .. "/repos/" .. owner .. "/" .. repo
  local repo_data = graphql_fetch_or_error(fetch_json, repo_path, ctx, nil)
  if not repo_data then
    return nil
  end
  return {
    starrable = graphql_translate_repo(translate_repo(repo_data)),
    clientMutationId = cmid,
  }
end

graphql_resolvers["Mutation.updateSubscription"] = function(_parent, args, ctx)
  local input = args and args.input
  if not input or not input.subscribableId then
    return graphql_error(
      ctx,
      "updateSubscription requires input.subscribableId",
      nil,
      "BAD_USER_INPUT"
    )
  end
  if not input.state then
    return graphql_error(ctx, "updateSubscription requires input.state", nil, "BAD_USER_INPUT")
  end
  local cmid = get_client_mutation_id(args)
  local t, lid = decode_node_id(input.subscribableId)
  if t ~= "Repository" then
    return graphql_error(ctx, "updateSubscription: invalid subscribableId", nil, "BAD_USER_INPUT")
  end
  local owner, repo = lid:match("^([^/]+)/(.+)$")
  if not owner then
    return graphql_error(ctx, "updateSubscription: malformed subscribableId", nil, "BAD_USER_INPUT")
  end
  local sub_path = base() .. "/repos/" .. owner .. "/" .. repo .. "/subscription"
  local ok, status
  if input.state == "UNSUBSCRIBED" then
    -- Unsubscribe uses DELETE, which returns 204 No Content.
    ok, status = fetch_json(sub_path, "DELETE")
  else
    -- SUBSCRIBED and IGNORED both use PUT with a JSON body; returns 200.
    local body = EncodeJson({
      subscribed = input.state == "SUBSCRIBED",
      ignored = input.state == "IGNORED",
    })
    ok, status = fetch_json(sub_path, "PUT", body)
  end
  if not ok then
    graphql_error(ctx, "network error updating subscription", nil, "INTERNAL_ERROR")
    return nil
  end
  if status == 401 or status == 403 then
    graphql_error(ctx, "not authorized to update subscription", nil, "FORBIDDEN")
    return nil
  end
  if status == 404 then
    graphql_error(ctx, "repository not found", nil, "NOT_FOUND")
    return nil
  end
  local expected_status = input.state == "UNSUBSCRIBED" and 204 or 200
  if status ~= expected_status then
    graphql_error(
      ctx,
      "upstream error " .. tostring(status) .. " updating subscription",
      nil,
      "INTERNAL_ERROR"
    )
    return nil
  end
  -- Re-fetch the repository to return in the payload.
  local repo_path = base() .. "/repos/" .. owner .. "/" .. repo
  local repo_data = graphql_fetch_or_error(fetch_json, repo_path, ctx, nil)
  if not repo_data then
    return nil
  end
  return {
    subscribable = graphql_translate_repo(translate_repo(repo_data)),
    clientMutationId = cmid,
  }
end

graphql_resolvers["Mutation.createLabel"] = function(_parent, args, ctx)
  local input = args and args.input
  if not input or not input.repositoryId then
    return graphql_error(ctx, "createLabel requires input.repositoryId", nil, "BAD_USER_INPUT")
  end
  if not input.name then
    return graphql_error(ctx, "createLabel requires input.name", nil, "BAD_USER_INPUT")
  end
  if not input.color then
    return graphql_error(ctx, "createLabel requires input.color", nil, "BAD_USER_INPUT")
  end
  local cmid = get_client_mutation_id(args)
  local t, lid = decode_node_id(input.repositoryId)
  if t ~= "Repository" then
    return graphql_error(ctx, "createLabel: invalid repositoryId", nil, "BAD_USER_INPUT")
  end
  local owner, repo = lid:match("^([^/]+)/(.+)$")
  if not owner then
    return graphql_error(ctx, "createLabel: malformed repositoryId", nil, "BAD_USER_INPUT")
  end
  local path = base() .. "/repos/" .. owner .. "/" .. repo .. "/labels"
  -- GitHub sends color without '#'; Gitea expects '#' prefix.
  local body = EncodeJson({
    name = input.name,
    color = "#" .. input.color,
    description = input.description,
  })
  local data = graphql_fetch_or_error(fetch_json, path, ctx, nil, "POST", body)
  if not data then
    return nil
  end
  return {
    label = graphql_translate_label(translate_gitea_label(data), owner, repo),
    clientMutationId = cmid,
  }
end

graphql_resolvers["Mutation.addLabelsToLabelable"] = function(_parent, args, ctx)
  local input = args and args.input
  if not input or not input.labelableId then
    return graphql_error(
      ctx,
      "addLabelsToLabelable requires input.labelableId",
      nil,
      "BAD_USER_INPUT"
    )
  end
  if not input.labelIds or #input.labelIds == 0 then
    return graphql_error(ctx, "addLabelsToLabelable requires input.labelIds", nil, "BAD_USER_INPUT")
  end
  local cmid = get_client_mutation_id(args)
  local t, lid = decode_node_id(input.labelableId)
  if t ~= "Issue" and t ~= "PullRequest" then
    return graphql_error(ctx, "addLabelsToLabelable: invalid labelableId", nil, "BAD_USER_INPUT")
  end
  local owner, repo, number = lid:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return graphql_error(ctx, "addLabelsToLabelable: malformed labelableId", nil, "BAD_USER_INPUT")
  end
  -- Decode each Label node ID and extract the Gitea integer label ID.
  local label_ids = {}
  for _, label_node_id in ipairs(input.labelIds) do
    local lt, llid = decode_node_id(label_node_id)
    if lt ~= "Label" then
      return graphql_error(ctx, "addLabelsToLabelable: invalid labelId", nil, "BAD_USER_INPUT")
    end
    -- Label local_id is "owner/repo/integer_id"
    local label_id = llid:match("/(%d+)$")
    if not label_id then
      return graphql_error(ctx, "addLabelsToLabelable: malformed labelId", nil, "BAD_USER_INPUT")
    end
    label_ids[#label_ids + 1] = tonumber(label_id)
  end
  -- Both issues and PRs share the /issues/{n}/labels endpoint in Gitea.
  local labels_path = base()
    .. "/repos/"
    .. owner
    .. "/"
    .. repo
    .. "/issues/"
    .. number
    .. "/labels"
  local body = EncodeJson({ labels = label_ids })
  -- POST returns 200 with the updated label list; we discard it and re-fetch the full item.
  local labels_ok = graphql_fetch_or_error(fetch_json, labels_path, ctx, nil, "POST", body)
  if labels_ok == nil then
    return nil
  end
  -- Re-fetch the issue or PR to populate the labelable payload field.
  local item_data
  if t == "PullRequest" then
    local pr_path = base() .. "/repos/" .. owner .. "/" .. repo .. "/pulls/" .. number
    local pr_data = graphql_fetch_or_error(fetch_json, pr_path, ctx, nil)
    if not pr_data then
      return nil
    end
    item_data = graphql_translate_pr(translate_gitea_pull(pr_data), owner, repo)
  else
    local issue_path = base() .. "/repos/" .. owner .. "/" .. repo .. "/issues/" .. number
    local issue_data = graphql_fetch_or_error(fetch_json, issue_path, ctx, nil)
    if not issue_data then
      return nil
    end
    item_data = graphql_translate_issue(translate_gitea_issue(issue_data), owner, repo)
  end
  return {
    labelable = item_data,
    clientMutationId = cmid,
  }
end
