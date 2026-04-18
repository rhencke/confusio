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

-- Check if this Gitea instance allows anonymous access.
-- Stored in _allow_anon; committed to app context via b:set_allow_anonymous() at the end.
local _allow_anon = true -- default
do
  local ok, status, _, body = pcall(Fetch, base() .. "/settings/api", nil)
  if ok and status == 200 then
    local settings = DecodeJson(body) or {}
    _allow_anon = settings.require_signin_view ~= true
  end
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

local function translate_gitea_labels(labels)
  return translate_list(translate_gitea_label, labels)
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

-- Normalise a Gitea branch object to GitHub shape.
-- Gitea uses commit.id for the SHA; GitHub uses commit.sha.
-- Mutates the input table in place (safe — callers own the decoded object).
local function translate_gitea_branch(br)
  if not br then
    return {}
  end
  if br.commit then
    br.commit.sha = br.commit.id
  end
  return br
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

-- ---------------------------------------------------------------------------
-- Packages capability module
-- ---------------------------------------------------------------------------
-- Owns fetch + translate for packages and package versions (org, user, and
-- public-user scopes).  Gitea's package API uses query-parameter filtering;
-- there is no direct lookup by name+type, so get/delete/version operations
-- list candidates and filter client-side.
-- All operations return (data, nil) on success or (nil, err) on failure.
-- Paged list operations return (items, headers, nil) or (nil, nil, err).

local packages_cap = {}

-- resolve_user_login: fetch the authenticated user's login for /user/packages.
-- Returns the login string or nil if unauthenticated / network failure.
packages_cap.resolve_user_login = function()
  local ok, status, _, body = fetch_json(base() .. "/user")
  if ok and status == 200 then
    return (DecodeJson(body) or {}).login
  end
  return nil
end

-- list: paginated list of packages for an owner.
-- pkg_type: optional GitHub package_type filter string ("" = all types).
packages_cap.list = function(owner, pkg_type)
  local url = base() .. "/packages/" .. owner
  if pkg_type and pkg_type ~= "" then
    url = url .. "?type=" .. pkg_type
  end
  url = append_page_params(url, PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gitea_package, items), hdrs, nil
end

-- get: fetch a single package by owner, type, and name.
-- Gitea has no direct lookup; this lists candidates and aggregates versions.
packages_cap.get = function(owner, pkg_type, pkg_name)
  local url = base()
    .. "/packages/"
    .. owner
    .. "?type="
    .. pkg_type
    .. "&q="
    .. pkg_name
    .. "&limit=50"
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  local entries = {}
  for _, p in ipairs(raw) do
    if p.name == pkg_name then
      entries[#entries + 1] = p
    end
  end
  if #entries == 0 then
    return nil, cap_err(404, "package not found")
  end
  return translate_gitea_package(entries[1], #entries), nil
end

-- delete: delete all versions of a package.
-- Returns (true, nil) on success or (nil, err) on failure.
packages_cap.delete = function(owner, pkg_type, pkg_name)
  local url = base()
    .. "/packages/"
    .. owner
    .. "?type="
    .. pkg_type
    .. "&q="
    .. pkg_name
    .. "&limit=50"
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  local found = false
  for _, p in ipairs(raw) do
    if p.name == pkg_name then
      found = true
      fetch_json(
        base() .. "/packages/" .. owner .. "/" .. pkg_type .. "/" .. pkg_name .. "/" .. p.version,
        "DELETE"
      )
    end
  end
  if not found then
    return nil, cap_err(404, "package not found")
  end
  return true, nil
end

-- list_versions: paginated list of versions for a specific package.
-- Filters client-side to the named package (Gitea query may return
-- partial-match results for q=pkg_name).
packages_cap.list_versions = function(owner, pkg_type, pkg_name)
  local url = base() .. "/packages/" .. owner .. "?type=" .. pkg_type .. "&q=" .. pkg_name
  url = append_page_params(url, PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  local versions = {}
  for _, p in ipairs(items) do
    if p.name == pkg_name then
      versions[#versions + 1] = translate_gitea_package_version(p)
    end
  end
  return versions, hdrs, nil
end

-- get_version: fetch a single package version by numeric ID.
packages_cap.get_version = function(owner, pkg_type, pkg_name, version_id)
  local url = base()
    .. "/packages/"
    .. owner
    .. "?type="
    .. pkg_type
    .. "&q="
    .. pkg_name
    .. "&limit=50"
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  local vid = tonumber(version_id)
  for _, p in ipairs(raw) do
    if p.id == vid and p.name == pkg_name then
      return translate_gitea_package_version(p), nil
    end
  end
  return nil, cap_err(404, "package version not found")
end

-- delete_version: delete a single package version by numeric ID.
-- Returns (true, nil) on success or (nil, err) on failure.
packages_cap.delete_version = function(owner, pkg_type, pkg_name, version_id)
  local url = base()
    .. "/packages/"
    .. owner
    .. "?type="
    .. pkg_type
    .. "&q="
    .. pkg_name
    .. "&limit=50"
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  local vid = tonumber(version_id)
  for _, p in ipairs(raw) do
    if p.id == vid and p.name == pkg_name then
      local del_url = base()
        .. "/packages/"
        .. owner
        .. "/"
        .. pkg_type
        .. "/"
        .. pkg_name
        .. "/"
        .. p.version
      local ok2, status2 = fetch_json(del_url, "DELETE")
      if not ok2 then
        return nil, cap_err(0, "network error deleting package version")
      end
      if status2 ~= 204 then
        return nil,
          cap_err(status2, "upstream error " .. tostring(status2) .. " deleting package version")
      end
      return true, nil
    end
  end
  return nil, cap_err(404, "package version not found")
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

-- ---------------------------------------------------------------------------
-- Actions capability module
-- ---------------------------------------------------------------------------
-- Owns fetch + translate for actions secrets, variables, and runners.
-- REST handlers call into this table for all actions-related operations.
-- All operations return (data, nil) on success or (nil, err) on failure.
-- List operations return (items, nil) where items is the translated array
-- (Gitea actions lists are plain JSON arrays without Link pagination headers).

local actions_cap = {}

-- list_repo_secrets: fetch all repo-level secrets as a translated array.
actions_cap.list_repo_secrets = function(owner, repo_name)
  local raw, err =
    cap_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo_name .. "/actions/secrets")
  if not raw then
    return nil, err
  end
  return translate_list(translate_gitea_actions_secret, raw), nil
end

-- get_repo_secret: fetch a single repo-level secret.
actions_cap.get_repo_secret = function(owner, repo_name, secret_name)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/actions/secrets/" .. secret_name
  )
  if not raw then
    return nil, err
  end
  return translate_gitea_actions_secret(raw), nil
end

-- delete_repo_secret: delete a repo-level secret.
actions_cap.delete_repo_secret = function(owner, repo_name, secret_name)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/actions/secrets/" .. secret_name
  local ok, status = fetch_json(url, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error deleting repo secret")
  end
  if status == 401 or status == 403 then
    return nil, cap_err(status, "not authorized to delete repo secret")
  end
  if status == 404 then
    return nil, cap_err(status, "repo secret not found")
  end
  if status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting repo secret")
  end
  return true, nil
end

-- list_org_secrets: fetch all org-level secrets as a translated array.
actions_cap.list_org_secrets = function(org)
  local raw, err = cap_fetch(fetch_json, base() .. "/orgs/" .. org .. "/actions/secrets")
  if not raw then
    return nil, err
  end
  return translate_list(translate_gitea_actions_secret, raw), nil
end

-- get_org_secret: fetch a single org-level secret.
actions_cap.get_org_secret = function(org, secret_name)
  local raw, err =
    cap_fetch(fetch_json, base() .. "/orgs/" .. org .. "/actions/secrets/" .. secret_name)
  if not raw then
    return nil, err
  end
  return translate_gitea_actions_secret(raw), nil
end

-- delete_org_secret: delete an org-level secret.
actions_cap.delete_org_secret = function(org, secret_name)
  local url = base() .. "/orgs/" .. org .. "/actions/secrets/" .. secret_name
  local ok, status = fetch_json(url, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error deleting org secret")
  end
  if status == 401 or status == 403 then
    return nil, cap_err(status, "not authorized to delete org secret")
  end
  if status == 404 then
    return nil, cap_err(status, "org secret not found")
  end
  if status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting org secret")
  end
  return true, nil
end

-- list_repo_variables: fetch all repo-level variables as a translated array.
actions_cap.list_repo_variables = function(owner, repo_name)
  local raw, err =
    cap_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo_name .. "/actions/variables")
  if not raw then
    return nil, err
  end
  return translate_list(translate_gitea_actions_variable, raw), nil
end

-- get_repo_variable: fetch a single repo-level variable.
actions_cap.get_repo_variable = function(owner, repo_name, var_name)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/actions/variables/" .. var_name
  )
  if not raw then
    return nil, err
  end
  return translate_gitea_actions_variable(raw), nil
end

-- create_repo_variable: create a repo-level variable.
actions_cap.create_repo_variable = function(owner, repo_name, body)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/actions/variables",
    "POST",
    body
  )
  if not raw then
    return nil, err
  end
  return translate_gitea_actions_variable(raw), nil
end

-- update_repo_variable: update a repo-level variable (Gitea uses PUT).
actions_cap.update_repo_variable = function(owner, repo_name, var_name, body)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/actions/variables/" .. var_name
  local ok, status = fetch_json(url, "PUT", body)
  if not ok then
    return nil, cap_err(0, "network error updating repo variable")
  end
  if status == 401 or status == 403 then
    return nil, cap_err(status, "not authorized to update repo variable")
  end
  if status == 404 then
    return nil, cap_err(status, "repo variable not found")
  end
  if status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " updating repo variable")
  end
  return true, nil
end

-- delete_repo_variable: delete a repo-level variable.
actions_cap.delete_repo_variable = function(owner, repo_name, var_name)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/actions/variables/" .. var_name
  local ok, status = fetch_json(url, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error deleting repo variable")
  end
  if status == 401 or status == 403 then
    return nil, cap_err(status, "not authorized to delete repo variable")
  end
  if status == 404 then
    return nil, cap_err(status, "repo variable not found")
  end
  if status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting repo variable")
  end
  return true, nil
end

-- list_org_variables: fetch all org-level variables as a translated array.
actions_cap.list_org_variables = function(org)
  local raw, err = cap_fetch(fetch_json, base() .. "/orgs/" .. org .. "/actions/variables")
  if not raw then
    return nil, err
  end
  return translate_list(translate_gitea_actions_variable, raw), nil
end

-- get_org_variable: fetch a single org-level variable.
actions_cap.get_org_variable = function(org, var_name)
  local raw, err =
    cap_fetch(fetch_json, base() .. "/orgs/" .. org .. "/actions/variables/" .. var_name)
  if not raw then
    return nil, err
  end
  return translate_gitea_actions_variable(raw), nil
end

-- create_org_variable: create an org-level variable.
actions_cap.create_org_variable = function(org, body)
  local raw, err =
    cap_fetch(fetch_json, base() .. "/orgs/" .. org .. "/actions/variables", "POST", body)
  if not raw then
    return nil, err
  end
  return translate_gitea_actions_variable(raw), nil
end

-- update_org_variable: update an org-level variable (Gitea uses PUT).
actions_cap.update_org_variable = function(org, var_name, body)
  local url = base() .. "/orgs/" .. org .. "/actions/variables/" .. var_name
  local ok, status = fetch_json(url, "PUT", body)
  if not ok then
    return nil, cap_err(0, "network error updating org variable")
  end
  if status == 401 or status == 403 then
    return nil, cap_err(status, "not authorized to update org variable")
  end
  if status == 404 then
    return nil, cap_err(status, "org variable not found")
  end
  if status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " updating org variable")
  end
  return true, nil
end

-- delete_org_variable: delete an org-level variable.
actions_cap.delete_org_variable = function(org, var_name)
  local url = base() .. "/orgs/" .. org .. "/actions/variables/" .. var_name
  local ok, status = fetch_json(url, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error deleting org variable")
  end
  if status == 401 or status == 403 then
    return nil, cap_err(status, "not authorized to delete org variable")
  end
  if status == 404 then
    return nil, cap_err(status, "org variable not found")
  end
  if status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting org variable")
  end
  return true, nil
end

-- list_repo_runners: fetch all repo-level runners as a translated array.
actions_cap.list_repo_runners = function(owner, repo_name)
  local raw, err =
    cap_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo_name .. "/actions/runners")
  if not raw then
    return nil, err
  end
  return translate_list(translate_gitea_actions_runner, raw), nil
end

-- list_org_runners: fetch all org-level runners as a translated array.
actions_cap.list_org_runners = function(org)
  local raw, err = cap_fetch(fetch_json, base() .. "/orgs/" .. org .. "/actions/runners")
  if not raw then
    return nil, err
  end
  return translate_list(translate_gitea_actions_runner, raw), nil
end

-- actions_rest_list: write the GitHub envelope for a list operation.
-- items is the translated array; key is "secrets", "variables", or "runners".
local function actions_rest_list(items, err, key)
  if not items then
    if err.status == 0 then
      respond_json(503, {})
    else
      respond_json(err.status, {})
    end
    return
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

local b = make_backend_builder()

-- ---------------------------------------------------------------------------
-- Repository capability module
-- ---------------------------------------------------------------------------
-- Owns fetch + translate_repo for all repository operations.
-- REST handlers and GraphQL resolvers both call into this table rather than
-- duplicating the URL construction, error mapping, and translation logic.
-- All operations return (data, nil) on success or (nil, err) on failure.
-- Paged list operations return (items, headers, nil) or (nil, nil, err).

local repos = {}

-- get: fetch a single repository.
repos.get = function(owner, repo_name)
  local raw, err = cap_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo_name)
  if not raw then
    return nil, err
  end
  return translate_repo(raw), nil
end

-- update: apply a partial update via PATCH.
-- body: JSON-encoded string of fields to change.
repos.update = function(owner, repo_name, body)
  local raw, err =
    cap_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo_name, "PATCH", body)
  if not raw then
    return nil, err
  end
  return translate_repo(raw), nil
end

-- delete: permanently remove a repository.
-- Returns (true, nil) on 204 success or (nil, err) on failure.
repos.delete = function(owner, repo_name)
  local ok, status = fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error deleting " .. owner .. "/" .. repo_name)
  end
  if status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting repository")
  end
  return true, nil
end

-- list_user: paginated list of repos for the authenticated user.
repos.list_user = function()
  local url = append_page_params(base() .. "/user/repos", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_repo, items), hdrs, nil
end

-- create_user: create a repository under the authenticated user.
repos.create_user = function(body)
  local raw, err = cap_fetch(fetch_json, base() .. "/user/repos", "POST", body)
  if not raw then
    return nil, err
  end
  return translate_repo(raw), nil
end

-- list_org: paginated list of repos for an organization.
repos.list_org = function(org)
  local url = append_page_params(base() .. "/orgs/" .. org .. "/repos", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_repo, items), hdrs, nil
end

-- create_org: create a repository inside an organization.
repos.create_org = function(org, body)
  local raw, err = cap_fetch(fetch_json, base() .. "/orgs/" .. org .. "/repos", "POST", body)
  if not raw then
    return nil, err
  end
  return translate_repo(raw), nil
end

-- list_by_user: paginated list of public repos for a specific user.
repos.list_by_user = function(username)
  local url = append_page_params(base() .. "/users/" .. username .. "/repos", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_repo, items), hdrs, nil
end

-- list_all: paginated public repos list using Gitea's repo search endpoint.
-- Gitea wraps results in {"data": [...], "ok": true}; items are extracted from .data.
repos.list_all = function()
  local url = append_page_params(base() .. "/repos/search", PAGES)
  local raw, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not raw then
    return nil, nil, err
  end
  return translate_list(translate_repo, raw.data or {}), hdrs, nil
end

-- ---------------------------------------------------------------------------
-- Users capability module
-- ---------------------------------------------------------------------------
-- Shared fetch+translate operations for user resources.
-- Operations return (data, nil) on success or (nil, err) on failure.
-- Paged list operations return (items, headers, nil) or (nil, nil, err).

local users = {}

-- get: fetch a single user by username.
-- Returns the GitHub REST user shape (translate_user applied).
users.get = function(username)
  local raw, err = cap_fetch(fetch_json, base() .. "/users/" .. username)
  if not raw then
    return nil, err
  end
  return translate_user(raw), nil
end

-- get_authenticated: fetch the currently authenticated user.
users.get_authenticated = function()
  local raw, err = cap_fetch(fetch_json, base() .. "/user")
  if not raw then
    return nil, err
  end
  return translate_user(raw), nil
end

-- update_authenticated: patch the currently authenticated user.
-- body: JSON-encoded string of fields to change.
-- Gitea uses PATCH /user/settings rather than PATCH /user.
users.update_authenticated = function(body)
  local raw, err = cap_fetch(fetch_json, base() .. "/user/settings", "PATCH", body)
  if not raw then
    return nil, err
  end
  return translate_user(raw), nil
end

-- list_all: paginated list of all users (Gitea admin endpoint).
users.list_all = function()
  local url = append_page_params(base() .. "/admin/users", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_user, items), hdrs, nil
end

-- list_followers: paginated list of the authenticated user's followers.
users.list_followers = function()
  local url = append_page_params(base() .. "/user/followers", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_user, items), hdrs, nil
end

-- list_following: paginated list of users the authenticated user follows.
users.list_following = function()
  local url = append_page_params(base() .. "/user/following", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_user, items), hdrs, nil
end

-- list_user_followers: paginated list of followers for a specific user.
users.list_user_followers = function(username)
  local url = append_page_params(base() .. "/users/" .. username .. "/followers", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_user, items), hdrs, nil
end

-- list_user_following: paginated list of users that a specific user follows.
users.list_user_following = function(username)
  local url = append_page_params(base() .. "/users/" .. username .. "/following", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_user, items), hdrs, nil
end

-- is_following: check whether the authenticated user follows username.
-- Returns (true, nil) if following, or (nil, err) otherwise.
-- err.status == 404 means not following; err.status == 0 means network error.
users.is_following = function(username)
  local ok, status = pcall(Fetch, base() .. "/user/following/" .. username, auth())
  if not ok then
    return nil, cap_err(0, "network error checking following status")
  end
  if status == 204 then
    return true, nil
  end
  return nil, cap_err(status, "not following " .. username)
end

-- follow: follow the given user.
-- Returns (true, nil) on success or (nil, err) on failure.
users.follow = function(username)
  local ok, status = fetch_json(base() .. "/user/following/" .. username, "PUT")
  if not ok then
    return nil, cap_err(0, "network error following " .. username)
  end
  if status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " following " .. username)
  end
  return true, nil
end

-- unfollow: unfollow the given user.
-- Returns (true, nil) on success or (nil, err) on failure.
users.unfollow = function(username)
  local ok, status = fetch_json(base() .. "/user/following/" .. username, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error unfollowing " .. username)
  end
  if status ~= 204 then
    return nil,
      cap_err(status, "upstream error " .. tostring(status) .. " unfollowing " .. username)
  end
  return true, nil
end

-- ---------------------------------------------------------------------------
-- Orgs capability module
-- ---------------------------------------------------------------------------
-- Shared fetch operations for organization resources.
-- Returns (data, nil) on success or (nil, err) on failure.
-- Note: there is no REST translate_org; consumers apply graphql_translate_org
-- themselves.  The raw Gitea org shape is returned as-is.

local orgs = {}

-- get: fetch a single organization by login.
orgs.get = function(login)
  local raw, err = cap_fetch(fetch_json, base() .. "/orgs/" .. login)
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- ---------------------------------------------------------------------------
-- Issues capability module
-- ---------------------------------------------------------------------------
-- Shared fetch+translate operations for issue resources.
-- Operations return (data, nil) on success or (nil, err) on failure.
-- Paged list operations return (items, headers, nil) or (nil, nil, err).
-- The GitHub REST shape is returned by all operations (translate_gitea_issue
-- applied).  GraphQL resolvers apply graphql_translate_issue on top.

local issues_cap = {}

-- get: fetch a single issue by number.
issues_cap.get = function(owner, repo_name, number)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/" .. number
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  return translate_gitea_issue(raw), nil
end

-- list: paginated list of issues for a repository.
issues_cap.list = function(owner, repo_name)
  local url =
    append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gitea_issue, items), hdrs, nil
end

-- create: create a new issue in a repository.
-- body: JSON-encoded string with title, body, labels, assignees, milestone.
issues_cap.create = function(owner, repo_name, body)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues"
  local raw, err = cap_fetch(fetch_json, url, "POST", body)
  if not raw then
    return nil, err
  end
  return translate_gitea_issue(raw), nil
end

-- update: apply a partial update to an existing issue.
-- body: JSON-encoded string of fields to change (title, body, state, etc.)
issues_cap.update = function(owner, repo_name, number, body)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/" .. number
  local raw, err = cap_fetch(fetch_json, url, "PATCH", body)
  if not raw then
    return nil, err
  end
  return translate_gitea_issue(raw), nil
end

-- list_labels: fetch all labels on an issue.
-- Returns (labels_array, nil) on success or (nil, err) on failure.
issues_cap.list_labels = function(owner, repo_name, number)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/" .. number .. "/labels"
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  return translate_gitea_labels(raw), nil
end

-- add_labels: add labels to an issue (POST).
-- label_names: array of label name strings; each is resolved to a Gitea numeric ID.
-- Returns (labels_array, nil) on success or (nil, err) on failure.
issues_cap.add_labels = function(owner, repo_name, number, label_names)
  local ids = {}
  for _, name in ipairs(label_names or {}) do
    local id = gitea_find_label_id(owner, repo_name, name)
    if id then
      ids[#ids + 1] = id
    end
  end
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/" .. number .. "/labels"
  local raw, err = cap_fetch(fetch_json, url, "POST", EncodeJson({ labels = ids }))
  if not raw then
    return nil, err
  end
  return translate_gitea_labels(raw), nil
end

-- set_labels: replace all labels on an issue (PUT).
-- label_names: array of label name strings; each is resolved to a Gitea numeric ID.
-- Returns (labels_array, nil) on success or (nil, err) on failure.
issues_cap.set_labels = function(owner, repo_name, number, label_names)
  local ids = {}
  for _, name in ipairs(label_names or {}) do
    local id = gitea_find_label_id(owner, repo_name, name)
    if id then
      ids[#ids + 1] = id
    end
  end
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/" .. number .. "/labels"
  local raw, err = cap_fetch(fetch_json, url, "PUT", EncodeJson({ labels = ids }))
  if not raw then
    return nil, err
  end
  return translate_gitea_labels(raw), nil
end

-- remove_labels: remove all labels from an issue (DELETE, no body).
-- Gitea returns 200 on success; normalised to (true, nil) for cap_rest_204.
-- Returns (true, nil) on success or (nil, err) on failure.
issues_cap.remove_labels = function(owner, repo_name, number)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/" .. number .. "/labels"
  local ok, status = fetch_json(url, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error removing labels from issue")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " removing labels")
  end
  return true, nil
end

-- remove_label: remove a single named label from an issue.
-- GitHub uses the label name in the URL; Gitea uses the numeric ID — resolved here.
-- Returns (true, nil) on success or (nil, err) on failure.
issues_cap.remove_label = function(owner, repo_name, number, label_name)
  local id = gitea_find_label_id(owner, repo_name, label_name)
  if not id then
    return nil, cap_err(404, "Label not found")
  end
  local url = base()
    .. "/repos/"
    .. owner
    .. "/"
    .. repo_name
    .. "/issues/"
    .. number
    .. "/labels/"
    .. id
  local ok, status = fetch_json(url, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error removing label from issue")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " removing label")
  end
  return true, nil
end

-- lock: lock an issue (PUT /lock).
-- body: JSON-encoded lock reason (forwarded verbatim to Gitea).
-- Requires a full Fetch call because PUT with a body needs Content-Type to be set.
-- Returns (true, nil) on success or (nil, err) on failure.
issues_cap.lock = function(owner, repo_name, number, body)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/" .. number .. "/lock"
  local opts = auth() or {}
  opts.method = "PUT"
  opts.body = body
  opts.headers = opts.headers or {}
  opts.headers["Content-Type"] = "application/json"
  local ok, status = pcall(Fetch, url, opts)
  if not ok then
    return nil, cap_err(0, "network error locking issue")
  end
  if status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " locking issue")
  end
  return true, nil
end

-- unlock: unlock an issue (DELETE /lock).
-- Returns (true, nil) on success or (nil, err) on failure.
issues_cap.unlock = function(owner, repo_name, number)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/" .. number .. "/lock"
  local ok, status = fetch_json(url, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error unlocking issue")
  end
  if status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " unlocking issue")
  end
  return true, nil
end

-- add_assignees: add assignees to an issue (POST /assignees).
-- body: JSON-encoded body with assignees array (forwarded to Gitea).
-- Returns (updated_issue, nil) on success or (nil, err) on failure.
issues_cap.add_assignees = function(owner, repo_name, number, body)
  local url = base()
    .. "/repos/"
    .. owner
    .. "/"
    .. repo_name
    .. "/issues/"
    .. number
    .. "/assignees"
  local raw, err = cap_fetch(fetch_json, url, "POST", body)
  if not raw then
    return nil, err
  end
  return translate_gitea_issue(raw), nil
end

-- remove_assignees: remove assignees from an issue (DELETE /assignees with body).
-- body: JSON-encoded body with assignees array (forwarded to Gitea).
-- Returns (updated_issue, nil) on success or (nil, err) on failure.
issues_cap.remove_assignees = function(owner, repo_name, number, body)
  local url = base()
    .. "/repos/"
    .. owner
    .. "/"
    .. repo_name
    .. "/issues/"
    .. number
    .. "/assignees"
  local raw, err = cap_fetch(fetch_json, url, "DELETE", body)
  if not raw then
    return nil, err
  end
  return translate_gitea_issue(raw), nil
end

-- check_assignee: check whether a user is currently assigned to an issue.
-- Gitea has no direct endpoint; we fetch the issue and scan its assignees list.
-- Returns (true, nil) if assigned, or (nil, err) if not (err.status == 404).
issues_cap.check_assignee = function(owner, repo_name, number, assignee)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/" .. number
  local issue, err = cap_fetch(fetch_json, url)
  if not issue then
    return nil, err
  end
  for _, u in ipairs(issue.assignees or {}) do
    if u.login == assignee then
      return true, nil
    end
  end
  return nil, cap_err(404, "Not an assignee")
end

-- list_assignees: paginated list of users eligible to be assigned to issues in a repo.
-- Returns (users_array, headers, nil) or (nil, nil, err).
issues_cap.list_assignees = function(owner, repo_name)
  local url =
    append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/assignees", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_user, items), hdrs, nil
end

-- ---------------------------------------------------------------------------
-- Pull requests capability module
-- ---------------------------------------------------------------------------
-- Shared fetch+translate operations for pull request resources.
-- Operations return (data, nil) on success or (nil, err) on failure.
-- Paged list operations return (items, headers, nil) or (nil, nil, err).
-- The GitHub REST shape is returned by all operations (translate_gitea_pull
-- applied).  GraphQL resolvers apply graphql_translate_pr on top.

local pulls_cap = {}

-- get: fetch a single pull request by number.
pulls_cap.get = function(owner, repo_name, number)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/pulls/" .. number
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  return translate_gitea_pull(raw), nil
end

-- list: paginated list of pull requests for a repository.
pulls_cap.list = function(owner, repo_name)
  local url =
    append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/pulls", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gitea_pull, items), hdrs, nil
end

-- create: open a new pull request in a repository.
-- body: JSON-encoded string with title, body, head, base.
pulls_cap.create = function(owner, repo_name, body)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/pulls"
  local raw, err = cap_fetch(fetch_json, url, "POST", body)
  if not raw then
    return nil, err
  end
  return translate_gitea_pull(raw), nil
end

-- update: apply a partial update to an existing pull request.
-- body: JSON-encoded string of fields to change (title, body, state, base, etc.)
pulls_cap.update = function(owner, repo_name, number, body)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/pulls/" .. number
  local raw, err = cap_fetch(fetch_json, url, "PATCH", body)
  if not raw then
    return nil, err
  end
  return translate_gitea_pull(raw), nil
end

-- merge: merge an open pull request.
-- body: JSON-encoded merge options (Do, MergeTitleField, MergeMessageField).
-- Gitea returns 204 No Content on success — no JSON body.
-- Returns (true, nil) on success or (nil, err) on failure.
pulls_cap.merge = function(owner, repo_name, number, body)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/pulls/" .. number .. "/merge"
  local ok, status = fetch_json(url, "POST", body)
  if not ok then
    return nil, cap_err(0, "network error merging pull request")
  end
  if status == 401 or status == 403 then
    return nil, cap_err(status, "not authorized to merge pull request")
  end
  if status == 404 then
    return nil, cap_err(status, "pull request not found")
  end
  if status == 405 then
    return nil, cap_err(status, "pull request is not mergeable")
  end
  if status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " merging pull request")
  end
  return true, nil
end

-- ---------------------------------------------------------------------------
-- Labels capability module
-- ---------------------------------------------------------------------------
-- Shared fetch+translate operations for label resources.
-- Operations return (data, nil) on success or (nil, err) on failure.
-- Paged list operations return (items, headers, nil) or (nil, nil, err).
-- The GitHub REST shape is returned by all operations (translate_gitea_label
-- applied).  GraphQL resolvers apply graphql_translate_label on top.

local labels_cap = {}

-- get: fetch a single label by numeric ID.
labels_cap.get = function(owner, repo_name, label_id)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/labels/" .. label_id
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  return translate_gitea_label(raw), nil
end

-- list: paginated list of labels for a repository.
labels_cap.list = function(owner, repo_name)
  local url =
    append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/labels", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gitea_label, items), hdrs, nil
end

-- create: create a new label in a repository.
-- body: JSON-encoded string with name, color, description.
labels_cap.create = function(owner, repo_name, body)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/labels"
  local raw, err = cap_fetch(fetch_json, url, "POST", body)
  if not raw then
    return nil, err
  end
  return translate_gitea_label(raw), nil
end

-- update: apply a partial update to an existing label.
-- body: JSON-encoded string of fields to change (name, color, description).
labels_cap.update = function(owner, repo_name, label_id, body)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/labels/" .. label_id
  local raw, err = cap_fetch(fetch_json, url, "PATCH", body)
  if not raw then
    return nil, err
  end
  return translate_gitea_label(raw), nil
end

-- delete: remove a label by numeric ID.
-- Returns (true, nil) on success or (nil, err) on failure.
labels_cap.delete = function(owner, repo_name, label_id)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/labels/" .. label_id
  local ok, status = fetch_json(url, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error deleting label")
  end
  if status == 401 or status == 403 then
    return nil, cap_err(status, "not authorized to delete label")
  end
  if status == 404 then
    return nil, cap_err(status, "label not found")
  end
  if status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting label")
  end
  return true, nil
end

-- ---------------------------------------------------------------------------
-- Milestones capability module
-- ---------------------------------------------------------------------------
-- Shared fetch+translate operations for milestone resources.
-- Operations return (data, nil) on success or (nil, err) on failure.
-- Paged list operations return (items, headers, nil) or (nil, nil, err).
-- The GitHub REST shape is returned by all operations (translate_gitea_milestone
-- applied).  GraphQL resolvers apply graphql_translate_milestone on top.

local milestones_cap = {}

-- get: fetch a single milestone by number.
milestones_cap.get = function(owner, repo_name, number)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/milestones/" .. number
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  return translate_gitea_milestone(raw), nil
end

-- list: paginated list of milestones for a repository.
milestones_cap.list = function(owner, repo_name)
  local url =
    append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/milestones", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gitea_milestone, items), hdrs, nil
end

-- create: create a new milestone in a repository.
-- body: JSON-encoded string with title, description, due_on.
milestones_cap.create = function(owner, repo_name, body)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/milestones"
  local raw, err = cap_fetch(fetch_json, url, "POST", body)
  if not raw then
    return nil, err
  end
  return translate_gitea_milestone(raw), nil
end

-- update: apply a partial update to an existing milestone.
-- body: JSON-encoded string of fields to change (title, description, state, due_on).
milestones_cap.update = function(owner, repo_name, number, body)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/milestones/" .. number
  local raw, err = cap_fetch(fetch_json, url, "PATCH", body)
  if not raw then
    return nil, err
  end
  return translate_gitea_milestone(raw), nil
end

-- delete: remove a milestone by number.
-- Returns (true, nil) on success or (nil, err) on failure.
milestones_cap.delete = function(owner, repo_name, number)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/milestones/" .. number
  local ok, status = fetch_json(url, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error deleting milestone")
  end
  if status == 401 or status == 403 then
    return nil, cap_err(status, "not authorized to delete milestone")
  end
  if status == 404 then
    return nil, cap_err(status, "milestone not found")
  end
  if status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting milestone")
  end
  return true, nil
end

-- list_labels: fetch all labels for a milestone.
-- Returns (labels_array, nil) on success or (nil, err) on failure.
milestones_cap.list_labels = function(owner, repo_name, number)
  local url = base()
    .. "/repos/"
    .. owner
    .. "/"
    .. repo_name
    .. "/milestones/"
    .. number
    .. "/labels"
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  return translate_gitea_labels(raw), nil
end

-- ---------------------------------------------------------------------------
-- Comments capability module
-- ---------------------------------------------------------------------------
-- Shared fetch+translate operations for issue comment resources.
-- Operations return (data, nil) on success or (nil, err) on failure.
-- Paged list operations return (items, headers, nil) or (nil, nil, err).
-- The GitHub REST shape is returned by all operations
-- (translate_gitea_issue_comment applied).  GraphQL resolvers apply
-- graphql_translate_comment on top.

local comments_cap = {}

-- get: fetch a single issue comment by repo-scoped comment ID.
comments_cap.get = function(owner, repo_name, comment_id)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/comments/" .. comment_id
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  return translate_gitea_issue_comment(raw), nil
end

-- list_repo: paginated list of all issue comments in a repository.
comments_cap.list_repo = function(owner, repo_name)
  local url = append_page_params(
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/comments",
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gitea_issue_comment, items), hdrs, nil
end

-- list_issue: paginated list of comments on a specific issue.
comments_cap.list_issue = function(owner, repo_name, number)
  local url = append_page_params(
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/" .. number .. "/comments",
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gitea_issue_comment, items), hdrs, nil
end

-- create: post a new comment on an issue.
-- body: JSON-encoded string with body field.
comments_cap.create = function(owner, repo_name, number, body)
  local url = base()
    .. "/repos/"
    .. owner
    .. "/"
    .. repo_name
    .. "/issues/"
    .. number
    .. "/comments"
  local raw, err = cap_fetch(fetch_json, url, "POST", body)
  if not raw then
    return nil, err
  end
  return translate_gitea_issue_comment(raw), nil
end

-- update: edit an existing issue comment.
-- body: JSON-encoded string with body field.
comments_cap.update = function(owner, repo_name, comment_id, body)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/comments/" .. comment_id
  local raw, err = cap_fetch(fetch_json, url, "PATCH", body)
  if not raw then
    return nil, err
  end
  return translate_gitea_issue_comment(raw), nil
end

-- delete: remove an issue comment by ID.
-- Returns (true, nil) on success or (nil, err) on failure.
comments_cap.delete = function(owner, repo_name, comment_id)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/comments/" .. comment_id
  local ok, status = fetch_json(url, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error deleting issue comment")
  end
  if status == 401 or status == 403 then
    return nil, cap_err(status, "not authorized to delete issue comment")
  end
  if status == 404 then
    return nil, cap_err(status, "issue comment not found")
  end
  if status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting issue comment")
  end
  return true, nil
end

-- ---------------------------------------------------------------------------
-- Branches capability module
-- ---------------------------------------------------------------------------
-- Shared fetch+translate operations for branch resources.
-- Gitea branch objects use commit.id for the SHA; translate_gitea_branch
-- normalises to commit.sha before returning.
-- Operations return (data, nil) on success or (nil, err) on failure.
-- Paged list operations return (items, headers, nil) or (nil, nil, err).

local branches = {}

-- list: paginated list of branches for a repository.
branches.list = function(owner, repo_name)
  local url =
    append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/branches", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gitea_branch, items), hdrs, nil
end

-- get: fetch a single branch by name.
branches.get = function(owner, repo_name, branch)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/branches/" .. branch
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  return translate_gitea_branch(raw), nil
end

-- ---------------------------------------------------------------------------
-- Repo metadata capability module
-- ---------------------------------------------------------------------------
-- Shared fetch operations for repository metadata: topics, languages,
-- contributors, and tags.  These resources pass through with minimal or no
-- translation because Gitea and GitHub shapes are already compatible.
-- Single-item operations return (data, nil) or (nil, err).
-- Paged list operations return (items, headers, nil) or (nil, nil, err).

local repo_metadata = {}

-- get_topics: fetch the topic list for a repository.
-- Returns { names = {...} } to match the GitHub REST shape.
repo_metadata.get_topics = function(owner, repo_name)
  local raw, err =
    cap_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo_name .. "/topics")
  if not raw then
    return nil, err
  end
  return { names = raw.topics or raw.names or {} }, nil
end

-- put_topics: replace the topic list for a repository.
-- body: JSON-encoded string with a "names" array (GitHub REST input shape).
-- Gitea expects { topics: [...] }; the response is translated back to { names: [...] }.
repo_metadata.put_topics = function(owner, repo_name, body)
  local req = DecodeJson(body or "{}")
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/topics",
    "PUT",
    EncodeJson({ topics = req.names or {} })
  )
  if not raw then
    return nil, err
  end
  return { names = raw.topics or raw.names or {} }, nil
end

-- get_languages: fetch the language breakdown for a repository.
-- Both Gitea and GitHub return { "Language": bytes } — pass through.
repo_metadata.get_languages = function(owner, repo_name)
  local raw, err =
    cap_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo_name .. "/languages")
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- list_contributors: paginated list of contributors for a repository.
-- Gitea and GitHub use the same "contributions" key — pass through.
repo_metadata.list_contributors = function(owner, repo_name)
  local url =
    append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/contributors", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return items, hdrs, nil
end

-- list_tags: paginated list of tags for a repository.
-- Both Gitea and GitHub return [{ name, commit: { sha, url }, ... }] — pass through.
repo_metadata.list_tags = function(owner, repo_name)
  local url = append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/tags", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return items, hdrs, nil
end

-- ---------------------------------------------------------------------------
-- Commits capability module
-- ---------------------------------------------------------------------------
-- Shared fetch operations for commit resources and commit statuses.
-- Gitea and GitHub shapes are compatible for all commit endpoints — no
-- translation is applied; raw upstream objects are returned.
-- Single-item operations return (data, nil) or (nil, err).
-- Paged list operations return (items, headers, nil) or (nil, nil, err).

local commits_cap = {}

-- list: paginated list of commits for a repository.
commits_cap.list = function(owner, repo_name)
  local url =
    append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/commits", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return items, hdrs, nil
end

-- get: fetch a single commit by ref or SHA.
-- Uses Gitea's /git/commits/{ref} endpoint; shape is compatible with GitHub.
commits_cap.get = function(owner, repo_name, ref)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/commits/" .. ref
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- list_statuses: paginated list of commit statuses for a ref.
-- Both Gitea and GitHub return the same status shape — pass through.
commits_cap.list_statuses = function(owner, repo_name, ref)
  local url = append_page_params(
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/statuses/" .. ref,
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return items, hdrs, nil
end

-- get_combined_status: fetch the combined status summary for a ref.
-- Gitea endpoint: GET /repos/{owner}/{repo}/commits/{ref}/statuses.
commits_cap.get_combined_status = function(owner, repo_name, ref)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/commits/" .. ref .. "/statuses"
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- create_status: create a commit status for a SHA.
-- body: JSON-encoded string with state, target_url, description, context.
-- Returns the newly created status object (201 Created shape).
commits_cap.create_status = function(owner, repo_name, sha, body)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/statuses/" .. sha,
    "POST",
    body
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- ---------------------------------------------------------------------------
-- Contents capability module
-- ---------------------------------------------------------------------------
-- Shared fetch operations for repository file contents and diffs.
-- Gitea and GitHub shapes are compatible for all content endpoints — no
-- translation is applied; raw upstream objects are returned.
-- Single-item operations return (data, nil) or (nil, err).
-- Note: put() always returns 200 via cap_rest_respond even when Gitea
-- returns 201 for new-file creation; the response body is still correct.

local contents = {}

-- get_readme: fetch the default README for a repository.
contents.get_readme = function(owner, repo_name)
  local raw, err =
    cap_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo_name .. "/readme")
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- get_readme_dir: fetch the README for a specific directory path.
contents.get_readme_dir = function(owner, repo_name, dir)
  local raw, err =
    cap_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo_name .. "/readme/" .. dir)
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- get: fetch file or directory contents at a path (optionally at a ref).
contents.get = function(owner, repo_name, path)
  local raw, err =
    cap_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo_name .. "/contents/" .. path)
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- put: create or update a file at a path.
-- body: JSON-encoded string with message, content (base64), and optional sha.
-- Gitea returns 201 for creates and 200 for updates; this operation always
-- responds 200 via cap_rest_respond (body is correct in both cases).
contents.put = function(owner, repo_name, path, body)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/contents/" .. path,
    "PUT",
    body
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- delete: delete a file at a path.
-- body: JSON-encoded string with message and sha of the file to delete.
-- Gitea returns 200 with commit information — pass through.
contents.delete = function(owner, repo_name, path, body)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/contents/" .. path,
    "DELETE",
    body
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- compare: fetch the diff between two commits, tags, or branches.
-- basehead: "{base}...{head}" or "{base}..{head}" — passed through to Gitea.
contents.compare = function(owner, repo_name, basehead)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/compare/" .. basehead
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- ---------------------------------------------------------------------------
-- Collaborators capability module
-- ---------------------------------------------------------------------------
-- Shared fetch operations for repository collaborator management.
-- Gitea collaborator endpoints use 201 (add) and 200 (remove) as success
-- codes; these are normalised to (true, nil) / (nil, err) here so REST
-- handlers can use cap_rest_204.
-- Single-item / mutation operations return (data/true, nil) or (nil, err).
-- Paged list operations return (items, headers, nil) or (nil, nil, err).

local collaborators = {}

-- list: paginated list of collaborators for a repository.
-- Gitea and GitHub user shapes are compatible — pass through.
collaborators.list = function(owner, repo_name)
  local url =
    append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/collaborators", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return items, hdrs, nil
end

-- check: test whether a username is a collaborator on a repository.
-- Returns (true, nil) if the user is a collaborator (Gitea 204),
-- or (nil, err) otherwise.
collaborators.check = function(owner, repo_name, username)
  local ok, status = pcall(
    Fetch,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/collaborators/" .. username,
    auth()
  )
  if not ok then
    return nil, cap_err(0, "network error checking collaborator")
  end
  if status == 204 then
    return true, nil
  end
  return nil, cap_err(status, "not a collaborator")
end

-- add: add a user as a collaborator on a repository.
-- body: JSON-encoded string with permission level.
-- Gitea returns 201 on success; normalised to (true, nil).
collaborators.add = function(owner, repo_name, username, body)
  local ok, status = fetch_json(
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/collaborators/" .. username,
    "PUT",
    body
  )
  if not ok then
    return nil, cap_err(0, "network error adding collaborator")
  end
  if status ~= 201 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " adding collaborator")
  end
  return true, nil
end

-- remove: remove a collaborator from a repository.
-- Gitea returns 200 on success; normalised to (true, nil).
collaborators.remove = function(owner, repo_name, username)
  local ok, status = fetch_json(
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/collaborators/" .. username,
    "DELETE"
  )
  if not ok then
    return nil, cap_err(0, "network error removing collaborator")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " removing collaborator")
  end
  return true, nil
end

-- get_permission: fetch the permission level of a collaborator.
-- Both Gitea and GitHub return the same permission shape — pass through.
collaborators.get_permission = function(owner, repo_name, username)
  local raw, err = cap_fetch(
    fetch_json,
    base()
      .. "/repos/"
      .. owner
      .. "/"
      .. repo_name
      .. "/collaborators/"
      .. username
      .. "/permission"
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- ---------------------------------------------------------------------------
-- Forks capability module
-- ---------------------------------------------------------------------------
-- Shared fetch+translate operations for repository fork resources.
-- translate_repo is applied to normalise Gitea repo objects to GitHub shape.
-- Paged list operations return (items, headers, nil) or (nil, nil, err).
-- Single-item operations return (data, nil) or (nil, err).

local forks = {}

-- list: paginated list of forks for a repository.
forks.list = function(owner, repo_name)
  local url =
    append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/forks", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_repo, items), hdrs, nil
end

-- create: fork a repository into the authenticated user's account (or an org).
-- body: JSON-encoded string with optional organization name.
forks.create = function(owner, repo_name, body)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/forks",
    "POST",
    body
  )
  if not raw then
    return nil, err
  end
  return translate_repo(raw), nil
end

-- ---------------------------------------------------------------------------
-- Commit comments capability module
-- ---------------------------------------------------------------------------
-- Shared fetch operations for commit-level code comments (not issue comments;
-- those live in comments_cap).
-- Gitea uses /repos/{o}/{r}/comments/{id} for repo-wide comment CRUD and
-- /repos/{o}/{r}/git/commits/{sha}/notes for per-commit listing/creation.
-- All operations pass through without translation — Gitea and GitHub shapes
-- are already compatible.
-- Single-item operations return (data/true, nil) or (nil, err).
-- Paged list operations return (items, headers, nil) or (nil, nil, err).

local commit_comments = {}

-- list_repo: paginated list of all commit comments in a repository.
commit_comments.list_repo = function(owner, repo_name)
  local url =
    append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/comments", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return items, hdrs, nil
end

-- get: fetch a single commit comment by ID.
commit_comments.get = function(owner, repo_name, comment_id)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/comments/" .. comment_id
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- update: apply a partial update to an existing commit comment.
-- body: JSON-encoded string with updated body text.
commit_comments.update = function(owner, repo_name, comment_id, body)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/comments/" .. comment_id,
    "PATCH",
    body
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- delete: delete a commit comment.
-- Gitea returns 200; normalised to (true, nil) for cap_rest_204.
commit_comments.delete = function(owner, repo_name, comment_id)
  local ok, status = fetch_json(
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/comments/" .. comment_id,
    "DELETE"
  )
  if not ok then
    return nil, cap_err(0, "network error deleting commit comment")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting commit comment")
  end
  return true, nil
end

-- list_commit: paginated list of comments for a specific commit SHA.
-- Gitea maps commit comments to /git/commits/{sha}/notes.
commit_comments.list_commit = function(owner, repo_name, commit_sha)
  local url = append_page_params(
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/commits/" .. commit_sha .. "/notes",
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return items, hdrs, nil
end

-- create: create a new comment on a specific commit.
-- body: JSON-encoded string with body text.
-- Gitea maps commit comments to /git/commits/{sha}/notes.
commit_comments.create = function(owner, repo_name, commit_sha, body)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/commits/" .. commit_sha .. "/notes",
    "POST",
    body
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- ---------------------------------------------------------------------------
-- Releases capability module
-- ---------------------------------------------------------------------------
-- Shared fetch operations for releases and release assets.
-- Gitea and GitHub release shapes are compatible — no translation applied.
-- Single-item operations return (data/true, nil) or (nil, err).
-- Paged list operations return (items, headers, nil) or (nil, nil, err).
-- delete and delete_asset normalise Gitea's 200 to (true, nil) for cap_rest_204.
-- upload_asset forwards the incoming Content-Type for multipart uploads;
-- it cannot use cap_fetch because it requires custom opts construction.

local releases = {}

-- list: paginated list of releases for a repository.
releases.list = function(owner, repo_name)
  local url =
    append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return items, hdrs, nil
end

-- create: create a new release.
releases.create = function(owner, repo_name, body)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases",
    "POST",
    body
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- get_latest: fetch the latest published release.
releases.get_latest = function(owner, repo_name)
  local raw, err =
    cap_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/latest")
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- get_by_tag: fetch a release by its tag name.
releases.get_by_tag = function(owner, repo_name, tag)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/tags/" .. tag
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- get: fetch a release by numeric ID.
releases.get = function(owner, repo_name, release_id)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/" .. release_id
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- update: apply a partial update to a release.
-- body: JSON-encoded string of fields to change.
releases.update = function(owner, repo_name, release_id, body)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/" .. release_id,
    "PATCH",
    body
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- delete: delete a release.
-- Gitea returns 200; normalised to (true, nil) for cap_rest_204.
releases.delete = function(owner, repo_name, release_id)
  local ok, status = fetch_json(
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/" .. release_id,
    "DELETE"
  )
  if not ok then
    return nil, cap_err(0, "network error deleting release")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting release")
  end
  return true, nil
end

-- list_assets: paginated list of assets attached to a release.
releases.list_assets = function(owner, repo_name, release_id)
  local url = append_page_params(
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/" .. release_id .. "/assets",
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return items, hdrs, nil
end

-- upload_asset: upload a new binary asset to a release via multipart upload.
-- content_type: the Content-Type of the uploaded file (forwarded from the client).
-- Uses pcall(Fetch) directly because it requires custom Content-Type forwarding
-- that cannot go through the standard fetch_json helper.
releases.upload_asset = function(owner, repo_name, release_id, body, content_type)
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
  opts.body = body
  opts.headers = opts.headers or {}
  opts.headers["Content-Type"] = content_type or "application/octet-stream"
  local ok, status, _, raw_body = pcall(Fetch, url, opts)
  if not ok then
    return nil, cap_err(0, "network error uploading release asset")
  end
  if status ~= 201 and status ~= 200 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " uploading release asset")
  end
  return DecodeJson(raw_body) or {}, nil
end

-- get_asset: fetch a single release asset by numeric ID.
releases.get_asset = function(owner, repo_name, asset_id)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/assets/" .. asset_id
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- update_asset: apply a partial update to a release asset.
-- body: JSON-encoded string with updated name or label.
releases.update_asset = function(owner, repo_name, asset_id, body)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/assets/" .. asset_id,
    "PATCH",
    body
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- delete_asset: delete a release asset.
-- Gitea returns 200; normalised to (true, nil) for cap_rest_204.
releases.delete_asset = function(owner, repo_name, asset_id)
  local ok, status = fetch_json(
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/releases/assets/" .. asset_id,
    "DELETE"
  )
  if not ok then
    return nil, cap_err(0, "network error deleting release asset")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting release asset")
  end
  return true, nil
end

-- ---------------------------------------------------------------------------
-- Meta capability module
-- ---------------------------------------------------------------------------
-- Health check, rate limit, gitignore templates, licenses, and repo-level
-- license / pages endpoints.  These either pass Gitea data through unchanged
-- or synthesise a minimal GitHub-shaped response.

local meta_cap = {}

-- health_check: probe the Gitea version endpoint.
-- Returns ({}, nil) on success (caller writes 200 {}) or (nil, err) on failure.
meta_cap.health_check = function()
  local ok, status = pcall(Fetch, base() .. "/version", auth())
  if not ok then
    return nil, cap_err(0, "network error during health check")
  end
  if status ~= 200 then
    return nil, cap_err(status, "upstream health check failed with status " .. tostring(status))
  end
  return {}, nil
end

-- get_rate_limit: fetch Gitea rate-limit data and wrap in GitHub's envelope.
-- Returns ({rate = ...}, nil) on success or (nil, err) on failure.
meta_cap.get_rate_limit = function()
  local raw, err = cap_fetch(fetch_json, base() .. "/rate_limit")
  if not raw then
    return nil, err
  end
  return { rate = raw.rate or raw }, nil
end

-- list_gitignore_templates: fetch all available gitignore template names.
meta_cap.list_gitignore_templates = function()
  return cap_fetch(fetch_json, base() .. "/gitignores")
end

-- get_gitignore_template: fetch a single gitignore template by name.
meta_cap.get_gitignore_template = function(name)
  return cap_fetch(fetch_json, base() .. "/gitignores/" .. name)
end

-- list_licenses: fetch all available SPDX license templates.
meta_cap.list_licenses = function()
  return cap_fetch(fetch_json, base() .. "/licenses")
end

-- get_license: fetch a single license template by SPDX key.
meta_cap.get_license = function(name)
  return cap_fetch(fetch_json, base() .. "/licenses/" .. name)
end

-- get_repo_license: synthesise a GitHub-style license response for a repository.
-- Gitea has no dedicated endpoint; we combine GET /contents/LICENSE with the repo
-- object (which carries a .license field) using two upstream fetches.
meta_cap.get_repo_license = function(owner, repo_name)
  local ok, status, _, body =
    fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/contents/LICENSE")
  if not ok then
    return nil, cap_err(0, "network error fetching repo license")
  end
  if status ~= 200 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " fetching repo license")
  end
  local content = DecodeJson(body) or {}
  local rok, rstatus, _, rbody = fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name)
  if rok and rstatus == 200 then
    content.license = (DecodeJson(rbody) or {}).license
  end
  return content, nil
end

-- get_repo_pages: synthesise a GitHub Pages response by checking for a gh-pages branch.
-- Returns a minimal Pages object when the branch exists, or (nil, err) otherwise.
meta_cap.get_repo_pages = function(owner, repo_name)
  local ok, status =
    fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/branches/gh-pages")
  if not ok then
    return nil, cap_err(0, "network error checking gh-pages branch")
  end
  if status ~= 200 then
    return nil,
      cap_err(status, "upstream error " .. tostring(status) .. " checking gh-pages branch")
  end
  return {
    url = "",
    status = "built",
    cname = nil,
    custom_404 = false,
    html_url = config.base_url .. "/" .. owner .. "/" .. repo_name,
    source = { branch = "gh-pages", path = "/" },
    public = true,
    https_enforced = false,
    build_type = "legacy",
  },
    nil
end

-- Health check
b:rest("get_root", function()
  local data, err = meta_cap.health_check()
  cap_rest_respond(data, err)
end)

b:rest("get_rate_limit", function()
  local data, err = meta_cap.get_rate_limit()
  cap_rest_respond(data, err)
end)

-- GET /gitignore/templates
b:rest("get_gitignore_templates", function()
  local data, err = meta_cap.list_gitignore_templates()
  cap_rest_respond(data, err)
end)

-- GET /gitignore/templates/{name}
b:rest("get_gitignore_template", function(name)
  local data, err = meta_cap.get_gitignore_template(name)
  cap_rest_respond(data, err)
end)

-- GET /licenses
b:rest("get_licenses", function()
  local data, err = meta_cap.list_licenses()
  cap_rest_respond(data, err)
end)

-- GET /licenses/{license}
b:rest("get_license", function(license_name)
  local data, err = meta_cap.get_license(license_name)
  cap_rest_respond(data, err)
end)

-- GET /repos/{owner}/{repo}/license
-- Gitea has no dedicated endpoint; combine contents/LICENSE with repo license metadata.
b:rest("get_repo_license", function(owner, repo_name)
  local data, err = meta_cap.get_repo_license(owner, repo_name)
  cap_rest_respond(data, err)
end)

-- GET /repos/{owner}/{repo}
b:rest("get_repo", function(owner, repo_name)
  local data, err = repos.get(owner, repo_name)
  cap_rest_respond(data, err)
end)

-- PATCH /repos/{owner}/{repo}
b:rest("patch_repo", function(owner, repo_name)
  local data, err = repos.update(owner, repo_name, GetBody())
  cap_rest_respond(data, err)
end)

-- DELETE /repos/{owner}/{repo}
b:rest("delete_repo", function(owner, repo_name)
  local ok, err = repos.delete(owner, repo_name)
  cap_rest_204(ok, err)
end)

-- GET /user/repos
b:rest("get_user_repos", function()
  local items, hdrs, err = repos.list_user()
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- POST /user/repos
b:rest("post_user_repos", function()
  local data, err = repos.create_user(GetBody())
  cap_rest_created(data, err)
end)

-- GET /orgs/{org}/repos
b:rest("get_org_repos", function(org)
  local items, hdrs, err = repos.list_org(org)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- POST /orgs/{org}/repos
b:rest("post_org_repos", function(org)
  local data, err = repos.create_org(org, GetBody())
  cap_rest_created(data, err)
end)

-- GET /repos/{owner}/{repo}/topics
b:rest("get_repo_topics", function(owner, repo_name)
  local data, err = repo_metadata.get_topics(owner, repo_name)
  cap_rest_respond(data, err)
end)

-- PUT /repos/{owner}/{repo}/topics
b:rest("put_repo_topics", function(owner, repo_name)
  local data, err = repo_metadata.put_topics(owner, repo_name, GetBody())
  cap_rest_respond(data, err)
end)

-- GET /repos/{owner}/{repo}/languages
b:rest("get_repo_languages", function(owner, repo_name)
  local data, err = repo_metadata.get_languages(owner, repo_name)
  cap_rest_respond(data, err)
end)

-- GET /repos/{owner}/{repo}/contributors
b:rest("get_repo_contributors", function(owner, repo_name)
  local items, hdrs, err = repo_metadata.list_contributors(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- GET /repos/{owner}/{repo}/tags
b:rest("get_repo_tags", function(owner, repo_name)
  local items, hdrs, err = repo_metadata.list_tags(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- Branches ------------------------------------------------------------------

-- GET /repos/{owner}/{repo}/branches
b:rest("get_repo_branches", function(owner, repo_name)
  local items, hdrs, err = branches.list(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- GET /repos/{owner}/{repo}/branches/{branch}
b:rest("get_repo_branch", function(owner, repo_name, branch)
  local data, err = branches.get(owner, repo_name, branch)
  cap_rest_respond(data, err)
end)

-- Commits -------------------------------------------------------------------

-- GET /repos/{owner}/{repo}/commits
b:rest("get_repo_commits", function(owner, repo_name)
  local items, hdrs, err = commits_cap.list(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- GET /repos/{owner}/{repo}/commits/{ref}
b:rest("get_repo_commit", function(owner, repo_name, ref)
  local data, err = commits_cap.get(owner, repo_name, ref)
  cap_rest_respond(data, err)
end)

-- Statuses ------------------------------------------------------------------

-- GET /repos/{owner}/{repo}/commits/{ref}/statuses
b:rest("get_commit_statuses", function(owner, repo_name, ref)
  local items, hdrs, err = commits_cap.list_statuses(owner, repo_name, ref)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- GET /repos/{owner}/{repo}/commits/{ref}/status  (combined)
b:rest("get_commit_combined_status", function(owner, repo_name, ref)
  local data, err = commits_cap.get_combined_status(owner, repo_name, ref)
  cap_rest_respond(data, err)
end)

-- POST /repos/{owner}/{repo}/statuses/{sha}
b:rest("post_commit_status", function(owner, repo_name, sha)
  local data, err = commits_cap.create_status(owner, repo_name, sha, GetBody())
  cap_rest_created(data, err)
end)

-- Contents ------------------------------------------------------------------

-- GET /repos/{owner}/{repo}/readme
b:rest("get_repo_readme", function(owner, repo_name)
  local data, err = contents.get_readme(owner, repo_name)
  cap_rest_respond(data, err)
end)

-- GET /repos/{owner}/{repo}/readme/{dir}
b:rest("get_repo_readme_dir", function(owner, repo_name, dir)
  local data, err = contents.get_readme_dir(owner, repo_name, dir)
  cap_rest_respond(data, err)
end)

-- GET /repos/{owner}/{repo}/contents/{path}
b:rest("get_repo_content", function(owner, repo_name, path)
  local data, err = contents.get(owner, repo_name, path)
  cap_rest_respond(data, err)
end)

-- PUT /repos/{owner}/{repo}/contents/{path}
b:rest("put_repo_content", function(owner, repo_name, path)
  local data, err = contents.put(owner, repo_name, path, GetBody())
  cap_rest_respond(data, err)
end)

-- DELETE /repos/{owner}/{repo}/contents/{path}
b:rest("delete_repo_content", function(owner, repo_name, path)
  local data, err = contents.delete(owner, repo_name, path, GetBody())
  cap_rest_respond(data, err)
end)

-- GET /repos/{owner}/{repo}/tarball/{ref} — redirect to Gitea's archive URL
b:rest("get_repo_tarball", function(owner, repo_name, ref)
  SetStatus(302, "Found")
  SetHeader(
    "Location",
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/archive/" .. ref .. ".tar.gz"
  )
  Write("")
end)

-- GET /repos/{owner}/{repo}/zipball/{ref} — redirect to Gitea's archive URL
b:rest("get_repo_zipball", function(owner, repo_name, ref)
  SetStatus(302, "Found")
  SetHeader(
    "Location",
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/archive/" .. ref .. ".zip"
  )
  Write("")
end)

-- Compare -------------------------------------------------------------------

-- GET /repos/{owner}/{repo}/compare/{basehead}
b:rest("get_repo_compare", function(owner, repo_name, basehead)
  local data, err = contents.compare(owner, repo_name, basehead)
  cap_rest_respond(data, err)
end)

-- Collaborators -------------------------------------------------------------

-- GET /repos/{owner}/{repo}/collaborators
b:rest("get_repo_collaborators", function(owner, repo_name)
  local items, hdrs, err = collaborators.list(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- GET /repos/{owner}/{repo}/collaborators/{username} — 204 if collaborator, 404 if not
b:rest("get_repo_collaborator", function(owner, repo_name, username)
  local ok, err = collaborators.check(owner, repo_name, username)
  if ok then
    SetStatus(204, "No Content")
  elseif err.status == 0 then
    respond_json(503, {})
  else
    respond_json(err.status, { message = "Not a collaborator" })
  end
end)

-- PUT /repos/{owner}/{repo}/collaborators/{username}
b:rest("put_repo_collaborator", function(owner, repo_name, username)
  local ok, err = collaborators.add(owner, repo_name, username, GetBody())
  cap_rest_204(ok, err)
end)

-- DELETE /repos/{owner}/{repo}/collaborators/{username}
b:rest("delete_repo_collaborator", function(owner, repo_name, username)
  local ok, err = collaborators.remove(owner, repo_name, username)
  cap_rest_204(ok, err)
end)

-- GET /repos/{owner}/{repo}/collaborators/{username}/permission
b:rest("get_repo_collaborator_permission", function(owner, repo_name, username)
  local data, err = collaborators.get_permission(owner, repo_name, username)
  cap_rest_respond(data, err)
end)

-- Forks ---------------------------------------------------------------------

-- GET /repos/{owner}/{repo}/forks
b:rest("get_repo_forks", function(owner, repo_name)
  local items, hdrs, err = forks.list(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- POST /repos/{owner}/{repo}/forks
b:rest("post_repo_forks", function(owner, repo_name)
  local data, err = forks.create(owner, repo_name, GetBody())
  cap_rest_created(data, err)
end)

-- Releases ------------------------------------------------------------------

-- GET /repos/{owner}/{repo}/releases
b:rest("get_repo_releases", function(owner, repo_name)
  cap_rest_paged(releases.list(owner, repo_name))
end)

-- POST /repos/{owner}/{repo}/releases
b:rest("post_repo_releases", function(owner, repo_name)
  cap_rest_created(releases.create(owner, repo_name, GetBody()))
end)

-- GET /repos/{owner}/{repo}/releases/latest
b:rest("get_repo_release_latest", function(owner, repo_name)
  cap_rest_respond(releases.get_latest(owner, repo_name))
end)

-- GET /repos/{owner}/{repo}/releases/tags/{tag}
b:rest("get_repo_release_by_tag", function(owner, repo_name, tag)
  cap_rest_respond(releases.get_by_tag(owner, repo_name, tag))
end)

-- GET /repos/{owner}/{repo}/releases/{release_id}
b:rest("get_repo_release", function(owner, repo_name, release_id)
  cap_rest_respond(releases.get(owner, repo_name, release_id))
end)

-- PATCH /repos/{owner}/{repo}/releases/{release_id}
b:rest("patch_repo_release", function(owner, repo_name, release_id)
  cap_rest_respond(releases.update(owner, repo_name, release_id, GetBody()))
end)

-- DELETE /repos/{owner}/{repo}/releases/{release_id}
b:rest("delete_repo_release", function(owner, repo_name, release_id)
  cap_rest_204(releases.delete(owner, repo_name, release_id))
end)

-- GET /repos/{owner}/{repo}/releases/{release_id}/assets
b:rest("get_repo_release_assets", function(owner, repo_name, release_id)
  cap_rest_paged(releases.list_assets(owner, repo_name, release_id))
end)

-- POST /repos/{owner}/{repo}/releases/{release_id}/assets — multipart; pass through
b:rest("post_repo_release_assets", function(owner, repo_name, release_id)
  -- Gitea uses the same multipart upload path; Content-Type must be forwarded.
  local content_type = GetHeader("Content-Type") or "application/octet-stream"
  cap_rest_created(releases.upload_asset(owner, repo_name, release_id, GetBody(), content_type))
end)

-- GET /repos/{owner}/{repo}/releases/assets/{asset_id}
b:rest("get_repo_release_asset", function(owner, repo_name, asset_id)
  cap_rest_respond(releases.get_asset(owner, repo_name, asset_id))
end)

-- PATCH /repos/{owner}/{repo}/releases/assets/{asset_id}
b:rest("patch_repo_release_asset", function(owner, repo_name, asset_id)
  cap_rest_respond(releases.update_asset(owner, repo_name, asset_id, GetBody()))
end)

-- DELETE /repos/{owner}/{repo}/releases/assets/{asset_id}
b:rest("delete_repo_release_asset", function(owner, repo_name, asset_id)
  cap_rest_204(releases.delete_asset(owner, repo_name, asset_id))
end)

-- Deploy keys ---------------------------------------------------------------

local deploy_keys = {}

deploy_keys.list = function(owner, repo_name)
  local url = append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/keys", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return items, hdrs, nil
end

deploy_keys.create = function(owner, repo_name, body)
  local raw, err =
    cap_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo_name .. "/keys", "POST", body)
  if not raw then
    return nil, err
  end
  return raw, nil
end

deploy_keys.get = function(owner, repo_name, key_id)
  local raw, err =
    cap_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo_name .. "/keys/" .. key_id)
  if not raw then
    return nil, err
  end
  return raw, nil
end

deploy_keys.delete = function(owner, repo_name, key_id)
  local ok, status =
    fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/keys/" .. key_id, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error deleting deploy key")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting deploy key")
  end
  return true, nil
end

-- GET /repos/{owner}/{repo}/keys
b:rest("get_repo_keys", function(owner, repo_name)
  cap_rest_paged(deploy_keys.list(owner, repo_name))
end)

-- POST /repos/{owner}/{repo}/keys
b:rest("post_repo_keys", function(owner, repo_name)
  cap_rest_created(deploy_keys.create(owner, repo_name, GetBody()))
end)

-- GET /repos/{owner}/{repo}/keys/{key_id}
b:rest("get_repo_key", function(owner, repo_name, key_id)
  cap_rest_respond(deploy_keys.get(owner, repo_name, key_id))
end)

-- DELETE /repos/{owner}/{repo}/keys/{key_id}
b:rest("delete_repo_key", function(owner, repo_name, key_id)
  cap_rest_204(deploy_keys.delete(owner, repo_name, key_id))
end)

-- Webhooks ------------------------------------------------------------------

local webhooks = {}

webhooks.list = function(owner, repo_name)
  local url =
    append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return items, hdrs, nil
end

webhooks.create = function(owner, repo_name, body)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks",
    "POST",
    body
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

webhooks.get = function(owner, repo_name, hook_id)
  local raw, err =
    cap_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id)
  if not raw then
    return nil, err
  end
  return raw, nil
end

webhooks.update = function(owner, repo_name, hook_id, body)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id,
    "PATCH",
    body
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

webhooks.delete = function(owner, repo_name, hook_id)
  local ok, status =
    fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error deleting webhook")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting webhook")
  end
  return true, nil
end

-- Gitea stores config inline in the hook object; extract the config sub-object.
webhooks.get_config = function(owner, repo_name, hook_id)
  local raw, err =
    cap_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id)
  if not raw then
    return nil, err
  end
  return raw.config or {}, nil
end

-- Gitea has no separate config endpoint; merge new_config into a full PATCH.
webhooks.update_config = function(owner, repo_name, hook_id, new_config)
  local url = base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id
  local hook, err = cap_fetch(fetch_json, url)
  if not hook then
    return nil, err
  end
  hook.config = hook.config or {}
  for k, v in pairs(new_config) do
    hook.config[k] = v
  end
  local updated, err2 = cap_fetch(fetch_json, url, "PATCH", EncodeJson(hook))
  if not updated then
    return nil, err2
  end
  return updated.config or {}, nil
end

webhooks.test = function(owner, repo_name, hook_id)
  local ok, status = fetch_json(
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/hooks/" .. hook_id .. "/tests",
    "POST"
  )
  if not ok then
    return nil, cap_err(0, "network error testing webhook")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " testing webhook")
  end
  return true, nil
end

-- GET /repos/{owner}/{repo}/hooks
b:rest("get_repo_hooks", function(owner, repo_name)
  cap_rest_paged(webhooks.list(owner, repo_name))
end)

-- POST /repos/{owner}/{repo}/hooks
b:rest("post_repo_hooks", function(owner, repo_name)
  cap_rest_created(webhooks.create(owner, repo_name, GetBody()))
end)

-- GET /repos/{owner}/{repo}/hooks/{hook_id}
b:rest("get_repo_hook", function(owner, repo_name, hook_id)
  cap_rest_respond(webhooks.get(owner, repo_name, hook_id))
end)

-- PATCH /repos/{owner}/{repo}/hooks/{hook_id}
b:rest("patch_repo_hook", function(owner, repo_name, hook_id)
  cap_rest_respond(webhooks.update(owner, repo_name, hook_id, GetBody()))
end)

-- DELETE /repos/{owner}/{repo}/hooks/{hook_id}
b:rest("delete_repo_hook", function(owner, repo_name, hook_id)
  cap_rest_204(webhooks.delete(owner, repo_name, hook_id))
end)

-- GET /repos/{owner}/{repo}/hooks/{hook_id}/config
b:rest("get_repo_hook_config", function(owner, repo_name, hook_id)
  cap_rest_respond(webhooks.get_config(owner, repo_name, hook_id))
end)

-- PATCH /repos/{owner}/{repo}/hooks/{hook_id}/config
b:rest("patch_repo_hook_config", function(owner, repo_name, hook_id)
  local new_config = DecodeJson(GetBody() or "{}") or {}
  cap_rest_respond(webhooks.update_config(owner, repo_name, hook_id, new_config))
end)

-- POST /repos/{owner}/{repo}/hooks/{hook_id}/tests
b:rest("post_repo_hook_test", function(owner, repo_name, hook_id)
  cap_rest_204(webhooks.test(owner, repo_name, hook_id))
end)

-- Users' repos --------------------------------------------------------------

-- GET /users/{username}/repos
b:rest("get_users_repos", function(username)
  local items, hdrs, err = repos.list_by_user(username)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- GET /repositories (public repos list) — use Gitea's repo search
b:rest("get_repositories", function()
  local items, hdrs, err = repos.list_all()
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- Commit comments -----------------------------------------------------------

-- GET /repos/{owner}/{repo}/comments
b:rest("get_repo_comments", function(owner, repo_name)
  local items, hdrs, err = commit_comments.list_repo(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- GET /repos/{owner}/{repo}/comments/{comment_id}
b:rest("get_repo_comment", function(owner, repo_name, comment_id)
  local data, err = commit_comments.get(owner, repo_name, comment_id)
  cap_rest_respond(data, err)
end)

-- PATCH /repos/{owner}/{repo}/comments/{comment_id}
b:rest("patch_repo_comment", function(owner, repo_name, comment_id)
  local data, err = commit_comments.update(owner, repo_name, comment_id, GetBody())
  cap_rest_respond(data, err)
end)

-- DELETE /repos/{owner}/{repo}/comments/{comment_id}
b:rest("delete_repo_comment", function(owner, repo_name, comment_id)
  local ok, err = commit_comments.delete(owner, repo_name, comment_id)
  cap_rest_204(ok, err)
end)

-- GET /repos/{owner}/{repo}/commits/{commit_sha}/comments
b:rest("get_commit_comments", function(owner, repo_name, commit_sha)
  local items, hdrs, err = commit_comments.list_commit(owner, repo_name, commit_sha)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- POST /repos/{owner}/{repo}/commits/{commit_sha}/comments
b:rest("post_commit_comment", function(owner, repo_name, commit_sha)
  local data, err = commit_comments.create(owner, repo_name, commit_sha, GetBody())
  cap_rest_created(data, err)
end)

-- Users ---------------------------------------------------------------------

-- GET /user
b:rest("get_user", function()
  local data, err = users.get_authenticated()
  cap_rest_respond(data, err)
end)

-- PATCH /user
b:rest("patch_user", function()
  local data, err = users.update_authenticated(GetBody())
  cap_rest_respond(data, err)
end)

-- GET /users/{username}
b:rest("get_users_username", function(username)
  local data, err = users.get(username)
  cap_rest_respond(data, err)
end)

-- GET /users
b:rest("get_users", function()
  local items, hdrs, err = users.list_all()
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- GET /user/followers
b:rest("get_user_followers", function()
  local items, hdrs, err = users.list_followers()
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- GET /user/following
b:rest("get_user_following", function()
  local items, hdrs, err = users.list_following()
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- GET /user/following/{username} — 204 if following, 404 if not
b:rest("get_user_is_following", function(username)
  local ok, err = users.is_following(username)
  if err and err.status == 0 then
    respond_json(503, {})
  elseif ok then
    SetStatus(204, "No Content")
  else
    respond_json(404, { message = "Not Following" })
  end
end)

-- PUT /user/following/{username}
b:rest("put_user_following", function(username)
  local ok, err = users.follow(username)
  cap_rest_204(ok, err)
end)

-- DELETE /user/following/{username}
b:rest("delete_user_following", function(username)
  local ok, err = users.unfollow(username)
  cap_rest_204(ok, err)
end)

-- GET /users/{username}/followers
b:rest("get_users_followers", function(username)
  local items, hdrs, err = users.list_user_followers(username)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- GET /users/{username}/following
b:rest("get_users_following", function(username)
  local items, hdrs, err = users.list_user_following(username)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- SSH Keys ------------------------------------------------------------------

local ssh_keys = {}

ssh_keys.list = function()
  local url = append_page_params(base() .. "/user/keys", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return items, hdrs, nil
end

ssh_keys.create = function(body)
  local raw, err = cap_fetch(fetch_json, base() .. "/user/keys", "POST", body)
  if not raw then
    return nil, err
  end
  return raw, nil
end

ssh_keys.get = function(key_id)
  local raw, err = cap_fetch(fetch_json, base() .. "/user/keys/" .. key_id)
  if not raw then
    return nil, err
  end
  return raw, nil
end

ssh_keys.delete = function(key_id)
  local ok, status = fetch_json(base() .. "/user/keys/" .. key_id, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error deleting SSH key")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting SSH key")
  end
  return true, nil
end

ssh_keys.list_user = function(username)
  local url = append_page_params(base() .. "/users/" .. username .. "/keys", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return items, hdrs, nil
end

-- GET /user/keys
b:rest("get_user_keys", function()
  cap_rest_paged(ssh_keys.list())
end)

-- POST /user/keys
b:rest("post_user_keys", function()
  cap_rest_created(ssh_keys.create(GetBody()))
end)

-- GET /user/keys/{key_id}
b:rest("get_user_key", function(key_id)
  cap_rest_respond(ssh_keys.get(key_id))
end)

-- DELETE /user/keys/{key_id}
b:rest("delete_user_key", function(key_id)
  cap_rest_204(ssh_keys.delete(key_id))
end)

-- GET /users/{username}/keys
b:rest("get_users_keys", function(username)
  cap_rest_paged(ssh_keys.list_user(username))
end)

-- GPG Keys ------------------------------------------------------------------

local gpg_keys = {}

gpg_keys.list = function()
  local url = append_page_params(base() .. "/user/gpg_keys", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return items, hdrs, nil
end

gpg_keys.create = function(body)
  local raw, err = cap_fetch(fetch_json, base() .. "/user/gpg_keys", "POST", body)
  if not raw then
    return nil, err
  end
  return raw, nil
end

gpg_keys.get = function(gpg_key_id)
  local raw, err = cap_fetch(fetch_json, base() .. "/user/gpg_keys/" .. gpg_key_id)
  if not raw then
    return nil, err
  end
  return raw, nil
end

gpg_keys.delete = function(gpg_key_id)
  local ok, status = fetch_json(base() .. "/user/gpg_keys/" .. gpg_key_id, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error deleting GPG key")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting GPG key")
  end
  return true, nil
end

gpg_keys.list_user = function(username)
  local url = append_page_params(base() .. "/users/" .. username .. "/gpg_keys", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return items, hdrs, nil
end

-- GET /user/gpg_keys
b:rest("get_user_gpg_keys", function()
  cap_rest_paged(gpg_keys.list())
end)

-- POST /user/gpg_keys
b:rest("post_user_gpg_keys", function()
  cap_rest_created(gpg_keys.create(GetBody()))
end)

-- GET /user/gpg_keys/{gpg_key_id}
b:rest("get_user_gpg_key", function(gpg_key_id)
  cap_rest_respond(gpg_keys.get(gpg_key_id))
end)

-- DELETE /user/gpg_keys/{gpg_key_id}
b:rest("delete_user_gpg_key", function(gpg_key_id)
  cap_rest_204(gpg_keys.delete(gpg_key_id))
end)

-- GET /users/{username}/gpg_keys
b:rest("get_users_gpg_keys", function(username)
  cap_rest_paged(gpg_keys.list_user(username))
end)

-- Emails --------------------------------------------------------------------

local user_emails = {}

user_emails.list = function()
  local raw, err = cap_fetch(fetch_json, base() .. "/user/emails")
  if not raw then
    return nil, err
  end
  return raw, nil
end

user_emails.add = function(body)
  local raw, err = cap_fetch(fetch_json, base() .. "/user/emails", "POST", body)
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- DELETE with a body requires a full Fetch call; Gitea returns 200 on success.
user_emails.delete = function(body)
  local opts = auth() or {}
  opts.method = "DELETE"
  opts.body = body
  opts.headers = opts.headers or {}
  opts.headers["Content-Type"] = "application/json"
  local ok, status = pcall(Fetch, base() .. "/user/emails", opts)
  if not ok then
    return nil, cap_err(0, "network error deleting user emails")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting user emails")
  end
  return true, nil
end

-- Gitea has no separate public-emails endpoint; filter verified from /user/emails.
user_emails.list_public = function()
  local raw, err = cap_fetch(fetch_json, base() .. "/user/emails")
  if not raw then
    return nil, err
  end
  return filter_verified_emails(raw), nil
end

-- GET /user/emails
b:rest("get_user_emails", function()
  cap_rest_respond(user_emails.list())
end)

-- POST /user/emails
b:rest("post_user_emails", function()
  cap_rest_created(user_emails.add(GetBody()))
end)

-- DELETE /user/emails
b:rest("delete_user_emails", function()
  cap_rest_204(user_emails.delete(GetBody()))
end)

-- GET /user/public_emails — Gitea has no separate endpoint; filter verified from /user/emails
b:rest("get_user_public_emails", function()
  cap_rest_respond(user_emails.list_public())
end)

-- Teams ---------------------------------------------------------------------
-- Gitea teams use numeric IDs, not slugs.  find_team_id lists all teams for
-- the org and matches by lowercased, slugified name.

local teams = {}

-- Internal: resolve slug to numeric ID; returns (id, nil) or (nil, cap_err).
local function team_id_of(org, slug)
  local id = gitea_find_team_id(org, slug)
  if not id then
    return nil, cap_err(404, "Not Found")
  end
  return id, nil
end

-- Internal: build the permission-normalised Gitea team body from a GitHub request.
local function gitea_team_body(req)
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
  return body
end

-- Org-level (slug-based) ----------------------------------------------------

teams.list_org = function(org)
  local url = append_page_params(base() .. "/orgs/" .. org .. "/teams", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gitea_team, items), hdrs, nil
end

teams.create = function(org, body)
  local req = DecodeJson(body or "{}") or {}
  local gitea_body = {
    name = req.name,
    description = req.description,
    permission = req.permission == "admin" and "owner" or (req.permission or "read"),
    units = { "repo.code", "repo.issues", "repo.pulls", "repo.releases" },
    includes_all_repositories = false,
  }
  local raw, err =
    cap_fetch(fetch_json, base() .. "/orgs/" .. org .. "/teams", "POST", EncodeJson(gitea_body))
  if not raw then
    return nil, err
  end
  return translate_gitea_team(raw), nil
end

teams.get_by_slug = function(org, slug)
  local id, err = team_id_of(org, slug)
  if not id then
    return nil, err
  end
  local raw, e = cap_fetch(fetch_json, base() .. "/teams/" .. id)
  if not raw then
    return nil, e
  end
  return translate_gitea_team(raw), nil
end

teams.update_by_slug = function(org, slug, body)
  local id, err = team_id_of(org, slug)
  if not id then
    return nil, err
  end
  local req = DecodeJson(body or "{}") or {}
  local raw, e =
    cap_fetch(fetch_json, base() .. "/teams/" .. id, "PATCH", EncodeJson(gitea_team_body(req)))
  if not raw then
    return nil, e
  end
  return translate_gitea_team(raw), nil
end

teams.delete_by_slug = function(org, slug)
  local id, err = team_id_of(org, slug)
  if not id then
    return nil, err
  end
  local ok, status = fetch_json(base() .. "/teams/" .. id, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error deleting team")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting team")
  end
  return true, nil
end

teams.list_members_by_slug = function(org, slug)
  local id, err = team_id_of(org, slug)
  if not id then
    return nil, nil, err
  end
  local url = append_page_params(base() .. "/teams/" .. id .. "/members", PAGES)
  local items, hdrs, e = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, e
  end
  return translate_list(translate_user, items), hdrs, nil
end

-- Returns ({url,role,state}, nil) on 204 or (nil, err) otherwise.
teams.get_membership_by_slug = function(org, slug, username)
  local id, err = team_id_of(org, slug)
  if not id then
    return nil, err
  end
  local ok, status = fetch_json(base() .. "/teams/" .. id .. "/members/" .. username)
  if not ok then
    return nil, cap_err(0, "network error checking membership")
  end
  if status == 204 then
    return { url = "", role = "member", state = "active" }, nil
  end
  return nil, cap_err(404, "Not Found")
end

-- Adds a member; returns ({url,role,state}, nil) on 200/204.
teams.add_membership_by_slug = function(org, slug, username)
  local id, err = team_id_of(org, slug)
  if not id then
    return nil, err
  end
  local ok, status = fetch_json(base() .. "/teams/" .. id .. "/members/" .. username, "PUT")
  if not ok then
    return nil, cap_err(0, "network error adding membership")
  end
  if status == 200 or status == 204 then
    return { url = "", role = "member", state = "active" }, nil
  end
  return nil, cap_err(status, "upstream error " .. tostring(status) .. " adding membership")
end

teams.delete_membership_by_slug = function(org, slug, username)
  local id, err = team_id_of(org, slug)
  if not id then
    return nil, err
  end
  local ok, status = fetch_json(base() .. "/teams/" .. id .. "/members/" .. username, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error deleting membership")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting membership")
  end
  return true, nil
end

teams.list_repos_by_slug = function(org, slug)
  local id, err = team_id_of(org, slug)
  if not id then
    return nil, nil, err
  end
  local url = append_page_params(base() .. "/teams/" .. id .. "/repos", PAGES)
  local items, hdrs, e = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, e
  end
  return translate_list(translate_repo, items), hdrs, nil
end

teams.get_repo_by_slug = function(org, slug, owner, repo_name)
  local id, err = team_id_of(org, slug)
  if not id then
    return nil, err
  end
  return teams.get_repo(id, owner, repo_name)
end

teams.add_repo_by_slug = function(org, slug, owner, repo_name)
  local id, err = team_id_of(org, slug)
  if not id then
    return nil, err
  end
  return teams.add_repo(id, owner, repo_name)
end

teams.delete_repo_by_slug = function(org, slug, owner, repo_name)
  local id, err = team_id_of(org, slug)
  if not id then
    return nil, err
  end
  return teams.delete_repo(id, owner, repo_name)
end

-- Legacy by-ID operations ---------------------------------------------------

teams.list_user = function()
  local url = append_page_params(base() .. "/user/teams", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gitea_team, items), hdrs, nil
end

teams.get = function(team_id)
  local raw, err = cap_fetch(fetch_json, base() .. "/teams/" .. team_id)
  if not raw then
    return nil, err
  end
  return translate_gitea_team(raw), nil
end

teams.update = function(team_id, body)
  local req = DecodeJson(body or "{}") or {}
  local raw, err =
    cap_fetch(fetch_json, base() .. "/teams/" .. team_id, "PATCH", EncodeJson(gitea_team_body(req)))
  if not raw then
    return nil, err
  end
  return translate_gitea_team(raw), nil
end

teams.delete = function(team_id)
  local ok, status = fetch_json(base() .. "/teams/" .. team_id, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error deleting team")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting team")
  end
  return true, nil
end

teams.list_members = function(team_id)
  local url = append_page_params(base() .. "/teams/" .. team_id .. "/members", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_user, items), hdrs, nil
end

-- Returns (true, nil) if member, (false, nil) if not, (nil, err) on network error.
teams.is_member = function(team_id, username)
  local ok, status = fetch_json(base() .. "/teams/" .. team_id .. "/members/" .. username)
  if not ok then
    return nil, cap_err(0, "network error checking team membership")
  end
  if status == 204 then
    return true, nil
  end
  return false, nil
end

teams.add_member = function(team_id, username)
  local ok, status = fetch_json(base() .. "/teams/" .. team_id .. "/members/" .. username, "PUT")
  if not ok then
    return nil, cap_err(0, "network error adding team member")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " adding team member")
  end
  return true, nil
end

teams.delete_member = function(team_id, username)
  local ok, status = fetch_json(base() .. "/teams/" .. team_id .. "/members/" .. username, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error deleting team member")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting team member")
  end
  return true, nil
end

teams.get_membership = function(team_id, username)
  local ok, status = fetch_json(base() .. "/teams/" .. team_id .. "/members/" .. username)
  if not ok then
    return nil, cap_err(0, "network error checking team membership")
  end
  if status == 204 then
    return { url = "", role = "member", state = "active" }, nil
  end
  return nil, cap_err(404, "Not Found")
end

teams.add_membership = function(team_id, username)
  local ok, status = fetch_json(base() .. "/teams/" .. team_id .. "/members/" .. username, "PUT")
  if not ok then
    return nil, cap_err(0, "network error adding team membership")
  end
  if status == 200 or status == 204 then
    return { url = "", role = "member", state = "active" }, nil
  end
  return nil, cap_err(status, "upstream error " .. tostring(status) .. " adding team membership")
end

teams.delete_membership = function(team_id, username)
  local ok, status = fetch_json(base() .. "/teams/" .. team_id .. "/members/" .. username, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error deleting team membership")
  end
  if status ~= 200 and status ~= 204 then
    return nil,
      cap_err(status, "upstream error " .. tostring(status) .. " deleting team membership")
  end
  return true, nil
end

teams.list_repos = function(team_id)
  local url = append_page_params(base() .. "/teams/" .. team_id .. "/repos", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_repo, items), hdrs, nil
end

-- Returns (translated_repo, nil) on 200/204 or (nil, err) otherwise.
teams.get_repo = function(team_id, owner, repo_name)
  local ok, status, _, body =
    fetch_json(base() .. "/teams/" .. team_id .. "/repos/" .. owner .. "/" .. repo_name)
  if not ok then
    return nil, cap_err(0, "network error getting team repo")
  end
  if status == 200 then
    return translate_repo(DecodeJson(body) or {}), nil
  end
  if status == 204 then
    return translate_repo({}), nil
  end
  return nil, cap_err(404, "Not Found")
end

teams.add_repo = function(team_id, owner, repo_name)
  local ok, status =
    fetch_json(base() .. "/teams/" .. team_id .. "/repos/" .. owner .. "/" .. repo_name, "PUT")
  if not ok then
    return nil, cap_err(0, "network error adding repo to team")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " adding repo to team")
  end
  return true, nil
end

teams.delete_repo = function(team_id, owner, repo_name)
  local ok, status =
    fetch_json(base() .. "/teams/" .. team_id .. "/repos/" .. owner .. "/" .. repo_name, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error removing repo from team")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " removing repo from team")
  end
  return true, nil
end

-- GET /orgs/{org}/teams
b:rest("get_org_teams", function(org)
  cap_rest_paged(teams.list_org(org))
end)

-- POST /orgs/{org}/teams
b:rest("post_org_teams", function(org)
  cap_rest_created(teams.create(org, GetBody()))
end)

-- GET /orgs/{org}/teams/{team_slug}
b:rest("get_org_team", function(org, slug)
  cap_rest_respond(teams.get_by_slug(org, slug))
end)

-- PATCH /orgs/{org}/teams/{team_slug}
b:rest("patch_org_team", function(org, slug)
  cap_rest_respond(teams.update_by_slug(org, slug, GetBody()))
end)

-- DELETE /orgs/{org}/teams/{team_slug}
b:rest("delete_org_team", function(org, slug)
  cap_rest_204(teams.delete_by_slug(org, slug))
end)

-- GET /orgs/{org}/teams/{team_slug}/members
b:rest("get_org_team_members", function(org, slug)
  cap_rest_paged(teams.list_members_by_slug(org, slug))
end)

-- GET /orgs/{org}/teams/{team_slug}/memberships/{username}
b:rest("get_org_team_membership", function(org, slug, username)
  cap_rest_respond(teams.get_membership_by_slug(org, slug, username))
end)

-- PUT /orgs/{org}/teams/{team_slug}/memberships/{username}
b:rest("put_org_team_membership", function(org, slug, username)
  cap_rest_respond(teams.add_membership_by_slug(org, slug, username))
end)

-- DELETE /orgs/{org}/teams/{team_slug}/memberships/{username}
b:rest("delete_org_team_membership", function(org, slug, username)
  cap_rest_204(teams.delete_membership_by_slug(org, slug, username))
end)

-- GET /orgs/{org}/teams/{team_slug}/repos
b:rest("get_org_team_repos", function(org, slug)
  cap_rest_paged(teams.list_repos_by_slug(org, slug))
end)

-- GET /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}
b:rest("get_org_team_repo", function(org, slug, owner, repo_name)
  cap_rest_respond(teams.get_repo_by_slug(org, slug, owner, repo_name))
end)

-- PUT /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}
b:rest("put_org_team_repo", function(org, slug, owner, repo_name)
  cap_rest_204(teams.add_repo_by_slug(org, slug, owner, repo_name))
end)

-- DELETE /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}
b:rest("delete_org_team_repo", function(org, slug, owner, repo_name)
  cap_rest_204(teams.delete_repo_by_slug(org, slug, owner, repo_name))
end)

-- Issues -------------------------------------------------------------------

-- GET /repos/{owner}/{repo}/issues
b:rest("get_repo_issues", function(owner, repo_name)
  local items, hdrs, err = issues_cap.list(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- POST /repos/{owner}/{repo}/issues
b:rest("post_repo_issues", function(owner, repo_name)
  local data, err = issues_cap.create(owner, repo_name, GetBody())
  cap_rest_created(data, err)
end)

-- GET /repos/{owner}/{repo}/issues/{issue_number}
b:rest("get_repo_issue", function(owner, repo_name, number)
  local data, err = issues_cap.get(owner, repo_name, number)
  cap_rest_respond(data, err)
end)

-- PATCH /repos/{owner}/{repo}/issues/{issue_number}
b:rest("patch_repo_issue", function(owner, repo_name, number)
  local data, err = issues_cap.update(owner, repo_name, number, GetBody())
  cap_rest_respond(data, err)
end)

-- GET /repos/{owner}/{repo}/issues/comments  (all issue comments in repo)
b:rest("get_repo_issue_comments", function(owner, repo_name)
  local items, hdrs, err = comments_cap.list_repo(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- GET /repos/{owner}/{repo}/issues/comments/{comment_id}
b:rest("get_repo_issue_comment", function(owner, repo_name, comment_id)
  local data, err = comments_cap.get(owner, repo_name, comment_id)
  cap_rest_respond(data, err)
end)

-- PATCH /repos/{owner}/{repo}/issues/comments/{comment_id}
b:rest("patch_repo_issue_comment", function(owner, repo_name, comment_id)
  local data, err = comments_cap.update(owner, repo_name, comment_id, GetBody())
  cap_rest_respond(data, err)
end)

-- DELETE /repos/{owner}/{repo}/issues/comments/{comment_id}
b:rest("delete_repo_issue_comment", function(owner, repo_name, comment_id)
  local ok, err = comments_cap.delete(owner, repo_name, comment_id)
  cap_rest_204(ok, err)
end)

-- Reactions ------------------------------------------------------------------

-- Internal: delete a reaction by synthesized ID; returns (true, nil) or (nil, err).
local function cap_delete_reaction(url, reaction_id)
  local content = reaction_content_from_id(reaction_id)
  if not content then
    return nil, cap_err(404, "Not Found")
  end
  local ok, status = fetch_json(url, "DELETE", '{"content":"' .. content .. '"}')
  if not ok then
    return nil, cap_err(0, "network error deleting reaction")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting reaction")
  end
  return true, nil
end

local reactions_cap = {}

reactions_cap.list_comment = function(owner, repo_name, comment_id)
  local url = append_page_params(
    base()
      .. "/repos/"
      .. owner
      .. "/"
      .. repo_name
      .. "/issues/comments/"
      .. comment_id
      .. "/reactions",
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gitea_reaction, items), hdrs, nil
end

reactions_cap.create_comment = function(owner, repo_name, comment_id, body)
  local raw, err = cap_fetch(
    fetch_json,
    base()
      .. "/repos/"
      .. owner
      .. "/"
      .. repo_name
      .. "/issues/comments/"
      .. comment_id
      .. "/reactions",
    "POST",
    body
  )
  if not raw then
    return nil, err
  end
  return translate_gitea_reaction(raw), nil
end

reactions_cap.delete_comment = function(owner, repo_name, comment_id, reaction_id)
  return cap_delete_reaction(
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
end

reactions_cap.list_issue = function(owner, repo_name, issue_number)
  local url = append_page_params(
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/" .. issue_number .. "/reactions",
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gitea_reaction, items), hdrs, nil
end

reactions_cap.create_issue = function(owner, repo_name, issue_number, body)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/" .. issue_number .. "/reactions",
    "POST",
    body
  )
  if not raw then
    return nil, err
  end
  return translate_gitea_reaction(raw), nil
end

reactions_cap.delete_issue = function(owner, repo_name, issue_number, reaction_id)
  return cap_delete_reaction(
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/" .. issue_number .. "/reactions",
    reaction_id
  )
end

-- Issue events and timeline --------------------------------------------------

local issue_events_cap = {}

issue_events_cap.list_repo = function(owner, repo_name)
  local url =
    append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/events", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return items, hdrs, nil
end

issue_events_cap.get = function(owner, repo_name, event_id)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/events/" .. event_id
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

issue_events_cap.list_issue = function(owner, repo_name, issue_number)
  local url = append_page_params(
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/" .. issue_number .. "/events",
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return items, hdrs, nil
end

issue_events_cap.list_timeline = function(owner, repo_name, issue_number)
  local url = append_page_params(
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/issues/" .. issue_number .. "/timeline",
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return items, hdrs, nil
end

-- GET /repos/{owner}/{repo}/issues/comments/{comment_id}/reactions
b:rest("get_repo_issue_comment_reactions", function(owner, repo_name, comment_id)
  cap_rest_paged(reactions_cap.list_comment(owner, repo_name, comment_id))
end)

-- POST /repos/{owner}/{repo}/issues/comments/{comment_id}/reactions
b:rest("post_repo_issue_comment_reaction", function(owner, repo_name, comment_id)
  cap_rest_created(reactions_cap.create_comment(owner, repo_name, comment_id, GetBody()))
end)

-- DELETE /repos/{owner}/{repo}/issues/comments/{comment_id}/reactions/{reaction_id}
b:rest("delete_repo_issue_comment_reaction", function(owner, repo_name, comment_id, reaction_id)
  cap_rest_204(reactions_cap.delete_comment(owner, repo_name, comment_id, reaction_id))
end)

-- GET /repos/{owner}/{repo}/issues/events  (all issue events in repo)
b:rest("get_repo_issue_events", function(owner, repo_name)
  cap_rest_paged(issue_events_cap.list_repo(owner, repo_name))
end)

-- GET /repos/{owner}/{repo}/issues/events/{event_id}
b:rest("get_repo_issue_event", function(owner, repo_name, event_id)
  cap_rest_respond(issue_events_cap.get(owner, repo_name, event_id))
end)

-- GET /repos/{owner}/{repo}/issues/{issue_number}/comments
b:rest("get_issue_comments", function(owner, repo_name, issue_number)
  local items, hdrs, err = comments_cap.list_issue(owner, repo_name, issue_number)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- POST /repos/{owner}/{repo}/issues/{issue_number}/comments
b:rest("post_issue_comment", function(owner, repo_name, issue_number)
  local data, err = comments_cap.create(owner, repo_name, issue_number, GetBody())
  cap_rest_created(data, err)
end)

-- GET /repos/{owner}/{repo}/issues/{issue_number}/events
b:rest("get_issue_events", function(owner, repo_name, issue_number)
  cap_rest_paged(issue_events_cap.list_issue(owner, repo_name, issue_number))
end)

-- GET /repos/{owner}/{repo}/issues/{issue_number}/timeline
b:rest("get_issue_timeline", function(owner, repo_name, issue_number)
  cap_rest_paged(issue_events_cap.list_timeline(owner, repo_name, issue_number))
end)

-- GET /repos/{owner}/{repo}/issues/{issue_number}/reactions
b:rest("get_issue_reactions", function(owner, repo_name, issue_number)
  cap_rest_paged(reactions_cap.list_issue(owner, repo_name, issue_number))
end)

-- POST /repos/{owner}/{repo}/issues/{issue_number}/reactions
b:rest("post_issue_reaction", function(owner, repo_name, issue_number)
  cap_rest_created(reactions_cap.create_issue(owner, repo_name, issue_number, GetBody()))
end)

-- DELETE /repos/{owner}/{repo}/issues/{issue_number}/reactions/{reaction_id}
b:rest("delete_issue_reaction", function(owner, repo_name, issue_number, reaction_id)
  cap_rest_204(reactions_cap.delete_issue(owner, repo_name, issue_number, reaction_id))
end)

-- GET /repos/{owner}/{repo}/issues/{issue_number}/labels
b:rest("get_issue_labels", function(owner, repo_name, issue_number)
  local data, err = issues_cap.list_labels(owner, repo_name, issue_number)
  cap_rest_respond(data, err)
end)

-- POST /repos/{owner}/{repo}/issues/{issue_number}/labels
-- GitHub body: { labels: ["name1", ...] }; Gitea body: { labels: [id1, ...] }
-- Look up each name to find its ID.
b:rest("post_issue_labels", function(owner, repo_name, issue_number)
  local req = DecodeJson(GetBody() or "{}")
  local data, err = issues_cap.add_labels(owner, repo_name, issue_number, req.labels)
  cap_rest_respond(data, err)
end)

-- PUT /repos/{owner}/{repo}/issues/{issue_number}/labels  (replace all)
b:rest("put_issue_labels", function(owner, repo_name, issue_number)
  local req = DecodeJson(GetBody() or "{}")
  local data, err = issues_cap.set_labels(owner, repo_name, issue_number, req.labels)
  cap_rest_respond(data, err)
end)

-- DELETE /repos/{owner}/{repo}/issues/{issue_number}/labels  (remove all)
b:rest("delete_issue_labels", function(owner, repo_name, issue_number)
  local ok, err = issues_cap.remove_labels(owner, repo_name, issue_number)
  cap_rest_204(ok, err)
end)

-- DELETE /repos/{owner}/{repo}/issues/{issue_number}/labels/{name}
-- GitHub uses the label name; Gitea uses the numeric label ID.
b:rest("delete_issue_label", function(owner, repo_name, issue_number, label_name)
  local ok, err = issues_cap.remove_label(owner, repo_name, issue_number, label_name)
  cap_rest_204(ok, err)
end)

-- PUT /repos/{owner}/{repo}/issues/{issue_number}/lock
b:rest("put_issue_lock", function(owner, repo_name, issue_number)
  local ok, err = issues_cap.lock(owner, repo_name, issue_number, GetBody())
  cap_rest_204(ok, err)
end)

-- DELETE /repos/{owner}/{repo}/issues/{issue_number}/lock
b:rest("delete_issue_lock", function(owner, repo_name, issue_number)
  local ok, err = issues_cap.unlock(owner, repo_name, issue_number)
  cap_rest_204(ok, err)
end)

-- POST /repos/{owner}/{repo}/issues/{issue_number}/assignees
b:rest("post_issue_assignees", function(owner, repo_name, issue_number)
  local data, err = issues_cap.add_assignees(owner, repo_name, issue_number, GetBody())
  cap_rest_respond(data, err)
end)

-- DELETE /repos/{owner}/{repo}/issues/{issue_number}/assignees
b:rest("delete_issue_assignees", function(owner, repo_name, issue_number)
  local data, err = issues_cap.remove_assignees(owner, repo_name, issue_number, GetBody())
  cap_rest_respond(data, err)
end)

-- GET /repos/{owner}/{repo}/issues/{issue_number}/assignees/{assignee}
-- Gitea has no direct endpoint; check the issue's assignees list.
b:rest("get_issue_assignee", function(owner, repo_name, issue_number, assignee)
  local ok, err = issues_cap.check_assignee(owner, repo_name, issue_number, assignee)
  if err and err.status == 0 then
    respond_json(503, {})
  elseif ok then
    SetStatus(204, "No Content")
  else
    respond_json(404, { message = "Not an assignee" })
  end
end)

-- Assignees -----------------------------------------------------------------

-- GET /repos/{owner}/{repo}/assignees  (users eligible for assignment)
b:rest("get_repo_assignees", function(owner, repo_name)
  local items, hdrs, err = issues_cap.list_assignees(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- Labels (repo-level) -------------------------------------------------------

-- GET /repos/{owner}/{repo}/labels
b:rest("get_repo_labels", function(owner, repo_name)
  local items, hdrs, err = labels_cap.list(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- POST /repos/{owner}/{repo}/labels
b:rest("post_repo_labels", function(owner, repo_name)
  local data, err = labels_cap.create(owner, repo_name, GetBody())
  cap_rest_created(data, err)
end)

-- GET /repos/{owner}/{repo}/labels/{name}
-- GitHub uses label name in the URL; Gitea uses numeric ID.
b:rest("get_repo_label", function(owner, repo_name, label_name)
  local id = gitea_find_label_id(owner, repo_name, label_name)
  if not id then
    respond_json(404, { message = "Label not found" })
    return
  end
  local data, err = labels_cap.get(owner, repo_name, id)
  cap_rest_respond(data, err)
end)

-- PATCH /repos/{owner}/{repo}/labels/{name}
b:rest("patch_repo_label", function(owner, repo_name, label_name)
  local id = gitea_find_label_id(owner, repo_name, label_name)
  if not id then
    respond_json(404, { message = "Label not found" })
    return
  end
  local data, err = labels_cap.update(owner, repo_name, id, GetBody())
  cap_rest_respond(data, err)
end)

-- DELETE /repos/{owner}/{repo}/labels/{name}
b:rest("delete_repo_label", function(owner, repo_name, label_name)
  local id = gitea_find_label_id(owner, repo_name, label_name)
  if not id then
    respond_json(404, { message = "Label not found" })
    return
  end
  local ok, err = labels_cap.delete(owner, repo_name, id)
  cap_rest_204(ok, err)
end)

-- Milestones ----------------------------------------------------------------

-- GET /repos/{owner}/{repo}/milestones
b:rest("get_repo_milestones", function(owner, repo_name)
  local items, hdrs, err = milestones_cap.list(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- POST /repos/{owner}/{repo}/milestones
b:rest("post_repo_milestones", function(owner, repo_name)
  local data, err = milestones_cap.create(owner, repo_name, GetBody())
  cap_rest_created(data, err)
end)

-- GET /repos/{owner}/{repo}/milestones/{milestone_number}
b:rest("get_repo_milestone", function(owner, repo_name, milestone_number)
  local data, err = milestones_cap.get(owner, repo_name, milestone_number)
  cap_rest_respond(data, err)
end)

-- PATCH /repos/{owner}/{repo}/milestones/{milestone_number}
b:rest("patch_repo_milestone", function(owner, repo_name, milestone_number)
  local data, err = milestones_cap.update(owner, repo_name, milestone_number, GetBody())
  cap_rest_respond(data, err)
end)

-- DELETE /repos/{owner}/{repo}/milestones/{milestone_number}
b:rest("delete_repo_milestone", function(owner, repo_name, milestone_number)
  local ok, err = milestones_cap.delete(owner, repo_name, milestone_number)
  cap_rest_204(ok, err)
end)

-- GET /repos/{owner}/{repo}/milestones/{milestone_number}/labels
b:rest("get_repo_milestone_labels", function(owner, repo_name, milestone_number)
  local data, err = milestones_cap.list_labels(owner, repo_name, milestone_number)
  cap_rest_respond(data, err)
end)

-- Legacy team-by-id endpoints (GitHub /teams/{team_id} → Gitea /teams/{id}).
-- No slug lookup needed — the caller already provides the numeric ID.

-- GET /user/teams
b:rest("get_user_teams", function()
  cap_rest_paged(teams.list_user())
end)

-- GET /teams/{team_id}
b:rest("get_team", function(team_id)
  cap_rest_respond(teams.get(team_id))
end)

-- PATCH /teams/{team_id}
b:rest("patch_team", function(team_id)
  cap_rest_respond(teams.update(team_id, GetBody()))
end)

-- DELETE /teams/{team_id}
b:rest("delete_team", function(team_id)
  cap_rest_204(teams.delete(team_id))
end)

-- GET /teams/{team_id}/members
b:rest("get_team_members", function(team_id)
  cap_rest_paged(teams.list_members(team_id))
end)

-- GET /teams/{team_id}/members/{username} — deprecated legacy endpoint
b:rest("get_team_member", function(team_id, username)
  local is_member, err = teams.is_member(team_id, username)
  if err then
    cap_rest_respond(nil, err)
  elseif is_member then
    SetStatus(204, "No Content")
  else
    respond_json(404, { message = "Not Found" })
  end
end)

-- PUT /teams/{team_id}/members/{username} — deprecated legacy endpoint
b:rest("put_team_member", function(team_id, username)
  cap_rest_204(teams.add_member(team_id, username))
end)

-- DELETE /teams/{team_id}/members/{username} — deprecated legacy endpoint
b:rest("delete_team_member", function(team_id, username)
  cap_rest_204(teams.delete_member(team_id, username))
end)

-- GET /teams/{team_id}/memberships/{username}
b:rest("get_team_membership", function(team_id, username)
  cap_rest_respond(teams.get_membership(team_id, username))
end)

-- PUT /teams/{team_id}/memberships/{username}
b:rest("put_team_membership", function(team_id, username)
  cap_rest_respond(teams.add_membership(team_id, username))
end)

-- DELETE /teams/{team_id}/memberships/{username}
b:rest("delete_team_membership", function(team_id, username)
  cap_rest_204(teams.delete_membership(team_id, username))
end)

-- GET /teams/{team_id}/repos
b:rest("get_team_repos", function(team_id)
  cap_rest_paged(teams.list_repos(team_id))
end)

-- GET /teams/{team_id}/repos/{owner}/{repo}
b:rest("get_team_repo", function(team_id, owner, repo_name)
  cap_rest_respond(teams.get_repo(team_id, owner, repo_name))
end)

-- PUT /teams/{team_id}/repos/{owner}/{repo}
b:rest("put_team_repo", function(team_id, owner, repo_name)
  cap_rest_204(teams.add_repo(team_id, owner, repo_name))
end)

-- DELETE /teams/{team_id}/repos/{owner}/{repo}
b:rest("delete_team_repo", function(team_id, owner, repo_name)
  cap_rest_204(teams.delete_repo(team_id, owner, repo_name))
end)

-- Pull Requests ---------------------------------------------------------------

-- GET /repos/{owner}/{repo}/pulls
b:rest("get_repo_pulls", function(owner, repo_name)
  local items, hdrs, err = pulls_cap.list(owner, repo_name)
  cap_rest_paged(items, hdrs, err, PAGES)
end)

-- POST /repos/{owner}/{repo}/pulls
b:rest("post_repo_pulls", function(owner, repo_name)
  local data, err = pulls_cap.create(owner, repo_name, GetBody())
  cap_rest_created(data, err)
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}
b:rest("get_repo_pull", function(owner, repo_name, number)
  local data, err = pulls_cap.get(owner, repo_name, number)
  cap_rest_respond(data, err)
end)

-- PATCH /repos/{owner}/{repo}/pulls/{pull_number}
b:rest("patch_repo_pull", function(owner, repo_name, number)
  local data, err = pulls_cap.update(owner, repo_name, number, GetBody())
  cap_rest_respond(data, err)
end)

-- PR sub-resources (commits, files, merge, reviewers, reviews) ---------------

local pr_subs = {}

pr_subs.list_commits = function(owner, repo_name, pull_number)
  local url = append_page_params(
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/pulls/" .. pull_number .. "/commits",
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return items, hdrs, nil
end

pr_subs.list_files = function(owner, repo_name, pull_number)
  local url = append_page_params(
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/pulls/" .. pull_number .. "/files",
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return items, hdrs, nil
end

-- Gitea returns 204 if merged, 404 if not — same semantics as GitHub.
-- Returns (true, nil) if merged, (false, nil) if not, (nil, err) on error.
pr_subs.check_merged = function(owner, repo_name, pull_number)
  local ok, status = fetch_json(
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/pulls/" .. pull_number .. "/merge"
  )
  if not ok then
    return nil, cap_err(0, "network error checking merge status")
  end
  if status == 204 then
    return true, nil
  end
  if status == 404 then
    return false, nil
  end
  return nil, cap_err(status, "upstream error " .. tostring(status))
end

-- GitHub uses PUT; Gitea uses POST.
pr_subs.merge = function(owner, repo_name, pull_number, body)
  local ok, status = fetch_json(
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/pulls/" .. pull_number .. "/merge",
    "POST",
    body
  )
  if not ok then
    return nil, cap_err(0, "network error merging PR")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " merging PR")
  end
  return true, nil
end

pr_subs.get_requested_reviewers = function(owner, repo_name, pull_number)
  local raw, err = cap_fetch(
    fetch_json,
    base()
      .. "/repos/"
      .. owner
      .. "/"
      .. repo_name
      .. "/pulls/"
      .. pull_number
      .. "/requested_reviewers"
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

pr_subs.add_requested_reviewers = function(owner, repo_name, pull_number, body)
  local raw, err = cap_fetch(
    fetch_json,
    base()
      .. "/repos/"
      .. owner
      .. "/"
      .. repo_name
      .. "/pulls/"
      .. pull_number
      .. "/requested_reviewers",
    "POST",
    body
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

pr_subs.delete_requested_reviewers = function(owner, repo_name, pull_number, body)
  local ok, status = fetch_json(
    base()
      .. "/repos/"
      .. owner
      .. "/"
      .. repo_name
      .. "/pulls/"
      .. pull_number
      .. "/requested_reviewers",
    "DELETE",
    body
  )
  if not ok then
    return nil, cap_err(0, "network error deleting requested reviewers")
  end
  if status ~= 200 and status ~= 204 then
    return nil,
      cap_err(status, "upstream error " .. tostring(status) .. " deleting requested reviewers")
  end
  return true, nil
end

pr_subs.list_reviews = function(owner, repo_name, pull_number)
  local url = append_page_params(
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/pulls/" .. pull_number .. "/reviews",
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_gitea_review, items), hdrs, nil
end

pr_subs.create_review = function(owner, repo_name, pull_number, body)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/pulls/" .. pull_number .. "/reviews",
    "POST",
    body
  )
  if not raw then
    return nil, err
  end
  return translate_gitea_review(raw), nil
end

pr_subs.get_review = function(owner, repo_name, pull_number, review_id)
  local raw, err = cap_fetch(
    fetch_json,
    base()
      .. "/repos/"
      .. owner
      .. "/"
      .. repo_name
      .. "/pulls/"
      .. pull_number
      .. "/reviews/"
      .. review_id
  )
  if not raw then
    return nil, err
  end
  return translate_gitea_review(raw), nil
end

pr_subs.delete_review = function(owner, repo_name, pull_number, review_id)
  local ok, status = fetch_json(
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
  if not ok then
    return nil, cap_err(0, "network error deleting review")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting review")
  end
  return true, nil
end

pr_subs.list_review_comments = function(owner, repo_name, pull_number, review_id)
  local raw, err = cap_fetch(
    fetch_json,
    base()
      .. "/repos/"
      .. owner
      .. "/"
      .. repo_name
      .. "/pulls/"
      .. pull_number
      .. "/reviews/"
      .. review_id
      .. "/comments"
  )
  if not raw then
    return nil, err
  end
  return translate_list(translate_gitea_review_comment, raw), nil
end

-- GitHub uses PUT; Gitea uses POST for dismissal.
pr_subs.dismiss_review = function(owner, repo_name, pull_number, review_id, body)
  local raw, err = cap_fetch(
    fetch_json,
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
    body
  )
  if not raw then
    return nil, err
  end
  return translate_gitea_review(raw), nil
end

-- Aggregates inline review comments across all reviews for the PR.
pr_subs.list_comments = function(owner, repo_name, pull_number)
  local ok, status, _, body = fetch_json(
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/pulls/" .. pull_number .. "/reviews"
  )
  if not ok then
    return nil, cap_err(0, "network error listing PR review comments")
  end
  if status ~= 200 then
    return nil, cap_err(status, "upstream error " .. tostring(status))
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
  return all_comments, nil
end

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/commits
b:rest("get_pull_commits", function(owner, repo_name, pull_number)
  cap_rest_paged(pr_subs.list_commits(owner, repo_name, pull_number))
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/files
b:rest("get_pull_files", function(owner, repo_name, pull_number)
  cap_rest_paged(pr_subs.list_files(owner, repo_name, pull_number))
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/merge
-- Gitea returns 204 if merged, 404 if not — same semantics as GitHub.
b:rest("get_pull_merge", function(owner, repo_name, pull_number)
  local merged, err = pr_subs.check_merged(owner, repo_name, pull_number)
  if err then
    respond_json(err.status == 0 and 503 or err.status, {})
    return
  end
  if merged then
    SetStatus(204, "No Content")
  else
    respond_json(404, { message = "Pull Request is not merged" })
  end
end)

-- PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge  (GitHub PUT → Gitea POST)
b:rest("put_pull_merge", function(owner, repo_name, pull_number)
  cap_rest_204(pr_subs.merge(owner, repo_name, pull_number, GetBody()))
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/requested_reviewers
b:rest("get_pull_requested_reviewers", function(owner, repo_name, pull_number)
  cap_rest_respond(pr_subs.get_requested_reviewers(owner, repo_name, pull_number))
end)

-- POST /repos/{owner}/{repo}/pulls/{pull_number}/requested_reviewers
b:rest("post_pull_requested_reviewers", function(owner, repo_name, pull_number)
  cap_rest_respond(pr_subs.add_requested_reviewers(owner, repo_name, pull_number, GetBody()))
end)

-- DELETE /repos/{owner}/{repo}/pulls/{pull_number}/requested_reviewers
b:rest("delete_pull_requested_reviewers", function(owner, repo_name, pull_number)
  cap_rest_204(pr_subs.delete_requested_reviewers(owner, repo_name, pull_number, GetBody()))
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews
b:rest("get_pull_reviews", function(owner, repo_name, pull_number)
  cap_rest_paged(pr_subs.list_reviews(owner, repo_name, pull_number))
end)

-- POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews
b:rest("post_pull_review", function(owner, repo_name, pull_number)
  cap_rest_created(pr_subs.create_review(owner, repo_name, pull_number, GetBody()))
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}
b:rest("get_pull_review", function(owner, repo_name, pull_number, review_id)
  cap_rest_respond(pr_subs.get_review(owner, repo_name, pull_number, review_id))
end)

-- DELETE /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}
b:rest("delete_pull_review", function(owner, repo_name, pull_number, review_id)
  cap_rest_204(pr_subs.delete_review(owner, repo_name, pull_number, review_id))
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}/comments
b:rest("get_pull_review_comments", function(owner, repo_name, pull_number, review_id)
  cap_rest_respond(pr_subs.list_review_comments(owner, repo_name, pull_number, review_id))
end)

-- PUT /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}/dismissals
-- GitHub uses PUT; Gitea uses POST.
b:rest("put_pull_review_dismissal", function(owner, repo_name, pull_number, review_id)
  cap_rest_respond(pr_subs.dismiss_review(owner, repo_name, pull_number, review_id, GetBody()))
end)

-- GET /repos/{owner}/{repo}/pulls/{pull_number}/comments
-- Aggregates inline review comments across all reviews for the PR.
b:rest("get_pull_comments", function(owner, repo_name, pull_number)
  cap_rest_respond(pr_subs.list_comments(owner, repo_name, pull_number))
end)

-- Checks (via Gitea commit statuses) ------------------------------------------

local checks = {}

-- Maps a GitHub check-run create request to a Gitea status, returning the created check-run.
checks.create_run = function(owner, repo_name, body)
  local req = DecodeJson(body or "{}") or {}
  local sha = req.head_sha or ""
  local gitea_body = gh_check_run_to_gitea_status(req)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/statuses/" .. sha,
    "POST",
    gitea_body
  )
  if not raw then
    return nil, err
  end
  return translate_gitea_status_to_check_run(raw), nil
end

-- Returns {total_count, check_runs=[...]} from Gitea statuses.
checks.list_commit = function(owner, repo_name, ref)
  local url = append_page_params(
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/statuses/" .. ref,
    PAGES
  )
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  local runs = translate_list(translate_gitea_status_to_check_run, items)
  return runs, hdrs, nil
end

-- POST /repos/{owner}/{repo}/check-runs
-- Maps to Gitea POST /api/v1/repos/{owner}/{repo}/statuses/{sha}.
b:rest("post_check_runs", function(owner, repo_name)
  cap_rest_created(checks.create_run(owner, repo_name, GetBody()))
end)

-- GET /repos/{owner}/{repo}/commits/{ref}/check-runs
-- Maps to Gitea GET /api/v1/repos/{owner}/{repo}/statuses/{ref}.
b:rest("get_commit_check_runs", function(owner, repo_name, ref)
  local runs, _, err = checks.list_commit(owner, repo_name, ref)
  if err then
    respond_json(err.status == 0 and 503 or err.status, {})
    return
  end
  respond_json(200, { total_count = #runs, check_runs = runs })
end)

-- Check Suites — no Gitea equivalent; all are stubs --------------------

-- POST /repos/{owner}/{repo}/check-suites
b:rest("post_check_suites", function(owner, repo_name)
  respond_json(201, {
    id = 1,
    node_id = "",
    head_sha = "",
    status = "completed",
    conclusion = "success",
    app = { id = 0, slug = "", name = "" },
    repository = { full_name = owner .. "/" .. repo_name },
  })
end)

-- ---------------------------------------------------------------------------
-- Search capability module
-- ---------------------------------------------------------------------------
-- Wraps Gitea's repo/user search endpoints.  Gitea wraps results in
-- {"data":[...],"ok":true}; each operation extracts and translates the array.
-- Operations return (items_array, nil) on success or (nil, err) on failure.

local search_cap = {}

-- repos: search for repositories matching a query string.
-- Returns (translated_repo_array, nil) or (nil, err).
search_cap.repos = function(q)
  local url = append_page_params(base() .. "/repos/search?q=" .. q, PAGES)
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  return translate_list(translate_repo, raw.data or {}), nil
end

-- users: search for users matching a query string.
-- Returns (translated_user_array, nil) or (nil, err).
search_cap.users = function(q)
  local url = append_page_params(base() .. "/users/search?q=" .. q, PAGES)
  local raw, err = cap_fetch(fetch_json, url)
  if not raw then
    return nil, err
  end
  return translate_list(translate_user, raw.data or {}), nil
end

-- search_rest_respond: write a GitHub search envelope from a translated items array.
-- Mirrors the proxy_search_envelope shape: {total_count, incomplete_results, items}.
-- Uses string concatenation for "items" so that an empty Lua table {} is written
-- as "[]" (JSON array) rather than "{}" (JSON object) which EncodeJson would produce.
local function search_rest_respond(items, err)
  if not items then
    respond_json(err.status == 0 and 503 or err.status, {})
    return
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

-- Search -----------------------------------------------------------------------

-- GET /search/repositories — maps to Gitea GET /repos/search
b:rest("search_repositories", function()
  search_rest_respond(search_cap.repos(GetParam("q") or ""))
end)

-- GET /search/users — maps to Gitea GET /users/search
b:rest("search_users", function()
  search_rest_respond(search_cap.users(GetParam("q") or ""))
end)

-- Packages (org) ---------------------------------------------------------------

b:rest("get_org_packages", function(org)
  cap_rest_paged(packages_cap.list(org, GetParam("package_type") or ""))
end)

b:rest("get_org_package", function(org, pkg_type, pkg_name)
  cap_rest_respond(packages_cap.get(org, pkg_type, pkg_name))
end)

b:rest("delete_org_package", function(org, pkg_type, pkg_name)
  cap_rest_204(packages_cap.delete(org, pkg_type, pkg_name))
end)

b:rest("get_org_package_versions", function(org, pkg_type, pkg_name)
  cap_rest_paged(packages_cap.list_versions(org, pkg_type, pkg_name))
end)

b:rest("get_org_package_version", function(org, pkg_type, pkg_name, version_id)
  cap_rest_respond(packages_cap.get_version(org, pkg_type, pkg_name, version_id))
end)

b:rest("delete_org_package_version", function(org, pkg_type, pkg_name, version_id)
  cap_rest_204(packages_cap.delete_version(org, pkg_type, pkg_name, version_id))
end)

-- Packages (authenticated user) ------------------------------------------------

b:rest("get_user_packages", function()
  local login = packages_cap.resolve_user_login()
  if not login then
    respond_json(401, { message = "Requires authentication" })
    return
  end
  cap_rest_paged(packages_cap.list(login, GetParam("package_type") or ""))
end)

b:rest("get_user_package", function(pkg_type, pkg_name)
  local login = packages_cap.resolve_user_login()
  if not login then
    respond_json(401, { message = "Requires authentication" })
    return
  end
  cap_rest_respond(packages_cap.get(login, pkg_type, pkg_name))
end)

b:rest("delete_user_package", function(pkg_type, pkg_name)
  local login = packages_cap.resolve_user_login()
  if not login then
    respond_json(401, { message = "Requires authentication" })
    return
  end
  cap_rest_204(packages_cap.delete(login, pkg_type, pkg_name))
end)

b:rest("get_user_package_versions", function(pkg_type, pkg_name)
  local login = packages_cap.resolve_user_login()
  if not login then
    respond_json(401, { message = "Requires authentication" })
    return
  end
  cap_rest_paged(packages_cap.list_versions(login, pkg_type, pkg_name))
end)

b:rest("get_user_package_version", function(pkg_type, pkg_name, version_id)
  local login = packages_cap.resolve_user_login()
  if not login then
    respond_json(401, { message = "Requires authentication" })
    return
  end
  cap_rest_respond(packages_cap.get_version(login, pkg_type, pkg_name, version_id))
end)

b:rest("delete_user_package_version", function(pkg_type, pkg_name, version_id)
  local login = packages_cap.resolve_user_login()
  if not login then
    respond_json(401, { message = "Requires authentication" })
    return
  end
  cap_rest_204(packages_cap.delete_version(login, pkg_type, pkg_name, version_id))
end)

-- Pages (https://docs.github.com/en/rest/pages) ---------------------------------
-- Gitea has no native GitHub Pages API.  We synthesize a minimal GET response
-- by checking whether the repo has a "gh-pages" branch.  Write, build, and
-- deployment endpoints have no Gitea equivalent and fall back to the default
-- pages_not_implemented (501) handler.

b:rest("get_repo_pages", function(owner, repo_name)
  local data, err = meta_cap.get_repo_pages(owner, repo_name)
  cap_rest_respond(data, err)
end)

-- Packages (public user) -------------------------------------------------------

b:rest("get_users_packages", function(username)
  cap_rest_paged(packages_cap.list(username, GetParam("package_type") or ""))
end)

b:rest("get_users_package", function(username, pkg_type, pkg_name)
  cap_rest_respond(packages_cap.get(username, pkg_type, pkg_name))
end)

b:rest("delete_users_package", function(username, pkg_type, pkg_name)
  cap_rest_204(packages_cap.delete(username, pkg_type, pkg_name))
end)

b:rest("get_users_package_versions", function(username, pkg_type, pkg_name)
  cap_rest_paged(packages_cap.list_versions(username, pkg_type, pkg_name))
end)

b:rest("get_users_package_version", function(username, pkg_type, pkg_name, version_id)
  cap_rest_respond(packages_cap.get_version(username, pkg_type, pkg_name, version_id))
end)

b:rest("delete_users_package_version", function(username, pkg_type, pkg_name, version_id)
  cap_rest_204(packages_cap.delete_version(username, pkg_type, pkg_name, version_id))
end)

-- ---------------------------------------------------------------------------
-- Markdown capability module
-- ---------------------------------------------------------------------------
-- Wraps Gitea's markdown rendering endpoints.
-- Both return HTML rather than JSON; the REST handlers write the response directly.
-- Operations return ({body=string, content_type=string}, nil) on success
-- or (nil, err) on failure.

local markdown_cap = {}

-- render: render markdown using the JSON API (same body shape as GitHub).
-- content_type: the Content-Type to send upstream (forwarded from the client).
-- body: the raw request body (JSON-encoded markdown options).
markdown_cap.render = function(content_type, body)
  local opts = auth() or {}
  opts.method = "POST"
  opts.body = body
  opts.headers = opts.headers or {}
  opts.headers["Content-Type"] = content_type
  local ok, status, headers, resp_body = pcall(Fetch, base() .. "/markdown", opts)
  if not ok then
    return nil, cap_err(0, "network error rendering markdown")
  end
  if status < 200 or status >= 300 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " rendering markdown")
  end
  local ct = (headers and (headers["Content-Type"] or headers["content-type"])) or "text/html"
  return { body = resp_body or "", content_type = ct }, nil
end

-- render_raw: render a raw markdown text body.
-- body: plain text markdown content.
markdown_cap.render_raw = function(body)
  local opts = auth() or {}
  opts.method = "POST"
  opts.body = body
  opts.headers = opts.headers or {}
  opts.headers["Content-Type"] = "text/plain"
  local ok, status, headers, resp_body = pcall(Fetch, base() .. "/markdown/raw", opts)
  if not ok then
    return nil, cap_err(0, "network error rendering raw markdown")
  end
  if status < 200 or status >= 300 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " rendering markdown")
  end
  local ct = (headers and (headers["Content-Type"] or headers["content-type"])) or "text/html"
  return { body = resp_body or "", content_type = ct }, nil
end

-- Markdown -------------------------------------------------------------------

-- POST /markdown → POST /api/v1/markdown
-- Gitea accepts the same JSON body as GitHub and returns rendered HTML.
b:rest("render_markdown", function()
  local data, err = markdown_cap.render(GetHeader("Content-Type") or "application/json", GetBody())
  if not data then
    respond_json(err.status == 0 and 503 or err.status, {})
    return
  end
  set_preamble(200, data.content_type)
  Write(data.body)
end)

-- POST /markdown/raw → POST /api/v1/markdown/raw
-- Gitea accepts raw markdown text and returns rendered HTML.
b:rest("render_markdown_raw", function()
  local data, err = markdown_cap.render_raw(GetBody())
  if not data then
    respond_json(err.status == 0 and 503 or err.status, {})
    return
  end
  set_preamble(200, data.content_type)
  Write(data.body)
end)

-- Actions ------------------------------------------------------------------
-- Gitea natively supports secrets, variables, and runners (repo + org level).
-- Workflow runs, artifacts, caches, jobs, OIDC, and permissions use defaults.
--
-- Secrets: list/get/delete only. GitHub encrypts secrets with NaCl before
-- sending; Gitea stores plaintext. The wire formats are incompatible, so
-- create/update (PUT) falls back to the default 501 handler.

b:rest("get_repo_actions_secrets", function(owner, repo)
  local items, err = actions_cap.list_repo_secrets(owner, repo)
  actions_rest_list(items, err, "secrets")
end)

b:rest("get_repo_actions_secret", function(owner, repo, secret_name)
  cap_rest_respond(actions_cap.get_repo_secret(owner, repo, secret_name))
end)

b:rest("delete_repo_actions_secret", function(owner, repo, secret_name)
  cap_rest_204(actions_cap.delete_repo_secret(owner, repo, secret_name))
end)

b:rest("get_org_actions_secrets", function(org)
  local items, err = actions_cap.list_org_secrets(org)
  actions_rest_list(items, err, "secrets")
end)

b:rest("get_org_actions_secret", function(org, secret_name)
  cap_rest_respond(actions_cap.get_org_secret(org, secret_name))
end)

b:rest("delete_org_actions_secret", function(org, secret_name)
  cap_rest_204(actions_cap.delete_org_secret(org, secret_name))
end)

-- Variables: full CRUD. Gitea uses PUT for updates; GitHub uses PATCH.
b:rest("get_repo_actions_variables", function(owner, repo)
  local items, err = actions_cap.list_repo_variables(owner, repo)
  actions_rest_list(items, err, "variables")
end)

b:rest("get_repo_actions_variable", function(owner, repo, name)
  cap_rest_respond(actions_cap.get_repo_variable(owner, repo, name))
end)

b:rest("post_repo_actions_variable", function(owner, repo)
  cap_rest_created(actions_cap.create_repo_variable(owner, repo, GetBody()))
end)

b:rest("patch_repo_actions_variable", function(owner, repo, name)
  cap_rest_204(actions_cap.update_repo_variable(owner, repo, name, GetBody()))
end)

b:rest("delete_repo_actions_variable", function(owner, repo, name)
  cap_rest_204(actions_cap.delete_repo_variable(owner, repo, name))
end)

b:rest("get_org_actions_variables", function(org)
  local items, err = actions_cap.list_org_variables(org)
  actions_rest_list(items, err, "variables")
end)

b:rest("get_org_actions_variable", function(org, name)
  cap_rest_respond(actions_cap.get_org_variable(org, name))
end)

b:rest("post_org_actions_variable", function(org)
  cap_rest_created(actions_cap.create_org_variable(org, GetBody()))
end)

b:rest("patch_org_actions_variable", function(org, name)
  cap_rest_204(actions_cap.update_org_variable(org, name, GetBody()))
end)

b:rest("delete_org_actions_variable", function(org, name)
  cap_rest_204(actions_cap.delete_org_variable(org, name))
end)

-- Runners: list only (individual runner operations not proxied).
b:rest("get_repo_actions_runners", function(owner, repo)
  local items, err = actions_cap.list_repo_runners(owner, repo)
  actions_rest_list(items, err, "runners")
end)

b:rest("get_org_actions_runners", function(org)
  local items, err = actions_cap.list_org_runners(org)
  actions_rest_list(items, err, "runners")
end)

-- Git database (https://docs.github.com/en/rest/git) -----------------------

local git_db = {}

git_db.get_blob = function(owner, repo_name, file_sha)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/blobs/" .. file_sha
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

git_db.get_commit = function(owner, repo_name, commit_sha)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/commits/" .. commit_sha
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- Gitea GET /git/refs/{ref} returns an array — same as GitHub matching-refs.
git_db.list_matching_refs = function(owner, repo_name, ref)
  local raw, err =
    cap_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/refs/" .. ref)
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- GitHub returns a single ref; Gitea returns an array — take the first element.
git_db.get_ref = function(owner, repo_name, ref)
  local raw, err =
    cap_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/refs/" .. ref)
  if not raw then
    return nil, err
  end
  if type(raw) == "table" and raw[1] then
    return raw[1], nil
  end
  return raw, nil
end

git_db.create_ref = function(owner, repo_name, body)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/refs",
    "POST",
    body
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

git_db.delete_ref = function(owner, repo_name, ref)
  local ok, status =
    fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/refs/" .. ref, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error deleting git ref")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting git ref")
  end
  return true, nil
end

git_db.get_tag = function(owner, repo_name, tag_sha)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/tags/" .. tag_sha
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

git_db.create_tag = function(owner, repo_name, body)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/tags",
    "POST",
    body
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

git_db.get_tree = function(owner, repo_name, tree_sha)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/git/trees/" .. tree_sha
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

-- GET /repos/{owner}/{repo}/git/blobs/{file_sha}
b:rest("get_git_blob", function(owner, repo_name, file_sha)
  cap_rest_respond(git_db.get_blob(owner, repo_name, file_sha))
end)

-- GET /repos/{owner}/{repo}/git/commits/{commit_sha}
b:rest("get_git_commit", function(owner, repo_name, commit_sha)
  cap_rest_respond(git_db.get_commit(owner, repo_name, commit_sha))
end)

-- GET /repos/{owner}/{repo}/git/matching-refs/{ref}
-- Gitea: GET /repos/{owner}/{repo}/git/refs/{ref} returns an array.
b:rest("list_git_matching_refs", function(owner, repo_name, ref)
  cap_rest_respond(git_db.list_matching_refs(owner, repo_name, ref))
end)

-- GET /repos/{owner}/{repo}/git/ref/{ref}
-- GitHub returns a single ref object; Gitea returns an array — take the first element.
b:rest("get_git_ref", function(owner, repo_name, ref)
  cap_rest_respond(git_db.get_ref(owner, repo_name, ref))
end)

-- POST /repos/{owner}/{repo}/git/refs
b:rest("create_git_ref", function(owner, repo_name)
  cap_rest_created(git_db.create_ref(owner, repo_name, GetBody()))
end)

-- DELETE /repos/{owner}/{repo}/git/refs/{ref}
b:rest("delete_git_ref", function(owner, repo_name, ref)
  cap_rest_204(git_db.delete_ref(owner, repo_name, ref))
end)

-- GET /repos/{owner}/{repo}/git/tags/{tag_sha}
b:rest("get_git_tag", function(owner, repo_name, tag_sha)
  cap_rest_respond(git_db.get_tag(owner, repo_name, tag_sha))
end)

-- POST /repos/{owner}/{repo}/git/tags
b:rest("create_git_tag", function(owner, repo_name)
  cap_rest_created(git_db.create_tag(owner, repo_name, GetBody()))
end)

-- GET /repos/{owner}/{repo}/git/trees/{tree_sha}
b:rest("get_git_tree", function(owner, repo_name, tree_sha)
  cap_rest_respond(git_db.get_tree(owner, repo_name, tree_sha))
end)

-- Activity (https://docs.github.com/en/rest/activity)
-- Gitea supports starring, watching, and subscription endpoints.
-- Events feeds and notifications have no Gitea equivalent.

local activity = {}

activity.list_stargazers = function(owner, repo_name)
  local url =
    append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/stargazers", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_user, items), hdrs, nil
end

activity.list_subscribers = function(owner, repo_name)
  local url =
    append_page_params(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/subscribers", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_user, items), hdrs, nil
end

activity.get_subscription = function(owner, repo_name)
  local raw, err =
    cap_fetch(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo_name .. "/subscription")
  if not raw then
    return nil, err
  end
  return raw, nil
end

activity.set_subscription = function(owner, repo_name, body)
  local raw, err = cap_fetch(
    fetch_json,
    base() .. "/repos/" .. owner .. "/" .. repo_name .. "/subscription",
    "PUT",
    body
  )
  if not raw then
    return nil, err
  end
  return raw, nil
end

activity.delete_subscription = function(owner, repo_name)
  local ok, status =
    fetch_json(base() .. "/repos/" .. owner .. "/" .. repo_name .. "/subscription", "DELETE")
  if not ok then
    return nil, cap_err(0, "network error deleting subscription")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " deleting subscription")
  end
  return true, nil
end

activity.list_starred = function()
  local url = append_page_params(base() .. "/user/starred", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_repo, items), hdrs, nil
end

-- Returns (true, nil) if starred, (false, nil) if not, (nil, err) on error.
activity.check_starred = function(owner, repo_name)
  local ok, status = fetch_json(base() .. "/user/starred/" .. owner .. "/" .. repo_name)
  if not ok then
    return nil, cap_err(0, "network error checking star status")
  end
  if status == 204 then
    return true, nil
  end
  if status == 404 then
    return false, nil
  end
  return nil, cap_err(status, "upstream error " .. tostring(status))
end

activity.star = function(owner, repo_name)
  local ok, status = fetch_json(base() .. "/user/starred/" .. owner .. "/" .. repo_name, "PUT")
  if not ok then
    return nil, cap_err(0, "network error starring repository")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " starring repository")
  end
  return true, nil
end

activity.unstar = function(owner, repo_name)
  local ok, status = fetch_json(base() .. "/user/starred/" .. owner .. "/" .. repo_name, "DELETE")
  if not ok then
    return nil, cap_err(0, "network error unstarring repository")
  end
  if status ~= 200 and status ~= 204 then
    return nil, cap_err(status, "upstream error " .. tostring(status) .. " unstarring repository")
  end
  return true, nil
end

activity.list_subscriptions = function()
  local url = append_page_params(base() .. "/user/subscriptions", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_repo, items), hdrs, nil
end

activity.list_user_starred = function(username)
  local url = append_page_params(base() .. "/users/" .. username .. "/starred", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_repo, items), hdrs, nil
end

activity.list_user_subscriptions = function(username)
  local url = append_page_params(base() .. "/users/" .. username .. "/subscriptions", PAGES)
  local items, hdrs, err = cap_fetch_paged(fetch_json, url)
  if not items then
    return nil, nil, err
  end
  return translate_list(translate_repo, items), hdrs, nil
end

b:rest("get_repo_stargazers", function(owner, repo_name)
  cap_rest_paged(activity.list_stargazers(owner, repo_name))
end)

b:rest("get_repo_subscribers", function(owner, repo_name)
  cap_rest_paged(activity.list_subscribers(owner, repo_name))
end)

b:rest("get_repo_subscription", function(owner, repo_name)
  cap_rest_respond(activity.get_subscription(owner, repo_name))
end)

b:rest("put_repo_subscription", function(owner, repo_name)
  cap_rest_respond(activity.set_subscription(owner, repo_name, GetBody()))
end)

b:rest("delete_repo_subscription", function(owner, repo_name)
  cap_rest_204(activity.delete_subscription(owner, repo_name))
end)

b:rest("get_user_starred", function()
  cap_rest_paged(activity.list_starred())
end)

-- GET /user/starred/{owner}/{repo} — 204 if starred, 404 if not.
b:rest("get_user_starred_repo", function(owner, repo_name)
  local starred, err = activity.check_starred(owner, repo_name)
  if err then
    respond_json(err.status == 0 and 503 or err.status, {})
    return
  end
  if starred then
    SetStatus(204, "No Content")
  else
    respond_json(404, { message = "Not Found" })
  end
end)

b:rest("put_user_starred_repo", function(owner, repo_name)
  cap_rest_204(activity.star(owner, repo_name))
end)

b:rest("delete_user_starred_repo", function(owner, repo_name)
  cap_rest_204(activity.unstar(owner, repo_name))
end)

b:rest("get_user_subscriptions", function()
  cap_rest_paged(activity.list_subscriptions())
end)

b:rest("get_users_starred", function(username)
  cap_rest_paged(activity.list_user_starred(username))
end)

b:rest("get_users_subscriptions", function(username)
  cap_rest_paged(activity.list_user_subscriptions(username))
end)

-- ---------------------------------------------------------------------------
-- GraphQL resolvers
-- ---------------------------------------------------------------------------

-- Query.repositoryOwner: look up a User or Organization by login.
-- Tries /users/{login} first; falls back to /orgs/{login}.
-- Returns a RepositoryOwner (User or Organization) or nil when not found.
b:graphql("Query.repositoryOwner", function(_parent, args, ctx)
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
end)

-- Query.viewer: resolve the authenticated user via GET /user.
-- If the token is absent or rejected, graphql_fetch_or_error records a
-- FORBIDDEN error and returns nil.
b:graphql("Query.viewer", function(_parent, _args, ctx)
  local data = graphql_fetch_or_error(fetch_json, base() .. "/user", ctx, nil)
  if not data then
    return nil
  end
  local u = graphql_translate_user(translate_user(data))
  u.isViewer = true
  return u
end)

-- node.Repository: fetch a repository by "owner/repo" local ID.
b:graphql("node.Repository", function(local_id, _ctx)
  local owner, repo_name = local_id:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  local data, _ = repos.get(owner, repo_name)
  if not data then
    return nil
  end
  return graphql_translate_repo(data)
end)

-- node.User: fetch a user by login.
b:graphql("node.User", function(local_id, _ctx)
  local data, _ = users.get(local_id)
  if not data then
    return nil
  end
  return graphql_translate_user(data)
end)

-- node.Organization: fetch an organization by login.
b:graphql("node.Organization", function(local_id, _ctx)
  local data, _ = orgs.get(local_id)
  if not data then
    return nil
  end
  return graphql_translate_org(data)
end)

-- node.Issue: fetch an issue by "owner/repo/number" local ID.
b:graphql("node.Issue", function(local_id, _ctx)
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ = issues_cap.get(owner, repo, number)
  if not data then
    return nil
  end
  return graphql_translate_issue(data, owner, repo)
end)

-- node.PullRequest: fetch a pull request by "owner/repo/number" local ID.
b:graphql("node.PullRequest", function(local_id, _ctx)
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ = pulls_cap.get(owner, repo, number)
  if not data then
    return nil
  end
  return graphql_translate_pr(data, owner, repo)
end)

-- node.IssueComment: fetch an issue comment by "owner/repo/comment_id" local ID.
b:graphql("node.IssueComment", function(local_id, _ctx)
  local owner, repo, cid = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ = comments_cap.get(owner, repo, cid)
  if not data then
    return nil
  end
  return graphql_translate_comment(data, owner, repo)
end)

-- Query.user: look up a User by login.
-- Returns nil (and no error) when the user does not exist.
b:graphql("Query.user", function(_parent, args, ctx)
  if not args.login then
    graphql_error(ctx, "user requires a login argument")
    return nil
  end
  local data, _ = users.get(args.login)
  if not data then
    return nil
  end
  return graphql_translate_user(data)
end)

-- Query.organization: look up an Organization by login.
-- Returns nil (and no error) when the organization does not exist.
b:graphql("Query.organization", function(_parent, args, ctx)
  if not args.login then
    graphql_error(ctx, "organization requires a login argument")
    return nil
  end
  local data, _ = orgs.get(args.login)
  if not data then
    return nil
  end
  return graphql_translate_org(data)
end)

-- Query.repository: look up a Repository by owner login and repo name.
-- Returns nil (and no error) when the repository does not exist.
b:graphql("Query.repository", function(_parent, args, ctx)
  if not args.owner or not args.name then
    graphql_error(ctx, "repository requires owner and name arguments")
    return nil
  end
  local data, _ = repos.get(args.owner, args.name)
  if not data then
    return nil
  end
  return graphql_translate_repo(data)
end)

-- node.Release: fetch a release by "owner/repo/release_id" local ID.
b:graphql("node.Release", function(local_id, _ctx)
  local owner, repo, rid = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ = releases.get(owner, repo, rid)
  if not data then
    return nil
  end
  return graphql_translate_release(data, owner, repo)
end)

-- node.Label: fetch a label by "owner/repo/label_id" local ID.
b:graphql("node.Label", function(local_id, _ctx)
  local owner, repo, lid = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ = labels_cap.get(owner, repo, lid)
  if not data then
    return nil
  end
  return graphql_translate_label(data, owner, repo)
end)

-- node.Milestone: fetch a milestone by "owner/repo/number" local ID.
b:graphql("node.Milestone", function(local_id, _ctx)
  local owner, repo, number = local_id:match("^([^/]+)/([^/]+)/(%d+)$")
  if not owner then
    return nil
  end
  local data, _ = milestones_cap.get(owner, repo, number)
  if not data then
    return nil
  end
  return graphql_translate_milestone(data, owner, repo)
end)

-- node.Commit: fetch a commit by "owner/repo/sha" local ID.
-- Uses commits_cap.get which owns the fetch + error mapping.
b:graphql("node.Commit", function(local_id, _ctx)
  local owner, repo, sha = local_id:match("^([^/]+)/([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  local data, _ = commits_cap.get(owner, repo, sha)
  if not data then
    return nil
  end
  return graphql_translate_commit(data, owner, repo)
end)

-- node.Ref: fetch a branch ref by "owner/repo/refs/heads/..." local ID.
-- Uses branches.get which normalises commit.sha via translate_gitea_branch.
b:graphql("node.Ref", function(local_id, _ctx)
  local owner, repo, ref_path = local_id:match("^([^/]+)/([^/]+)/(refs/.+)$")
  if not owner then
    return nil
  end
  local branch = ref_path:match("^refs/heads/(.+)$")
  if not branch then
    return nil
  end
  local data, _ = branches.get(owner, repo, branch)
  if not data then
    return nil
  end
  local repo_stub = { __typename = "Repository", nameWithOwner = owner .. "/" .. repo }
  return graphql_translate_ref(data, repo_stub)
end)

-- node.Team: fetch a team by "org/slug" local ID.
-- Gitea teams use numeric IDs; resolve slug → ID via gitea_find_team_id, then fetch /teams/{id}.
b:graphql("node.Team", function(local_id, _ctx)
  local org, slug = local_id:match("^([^/]+)/([^/]+)$")
  if not org then
    return nil
  end
  local id = gitea_find_team_id(org, slug)
  if not id then
    return nil
  end
  local data, _ = graphql_fetch(fetch_json, base() .. "/teams/" .. id)
  if not data then
    return nil
  end
  return graphql_translate_team(translate_gitea_team(data), org)
end)

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
    total =
      graphql_prefetch_total_from_headers(fetch_json, url_base, GITEA_PAGES, GITEA_TOTAL_HEADERS)
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
b:graphql("Repository.issues", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitea_repo_connection(owner, name, "/issues?type=issues", args, ctx, function(i)
    return graphql_translate_issue(translate_gitea_issue(i), owner, name)
  end, graphql_issues_connection)
end)

-- Repository.pullRequests: paginated list of pull requests.
b:graphql("Repository.pullRequests", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitea_repo_connection(owner, name, "/pulls", args, ctx, function(p)
    return graphql_translate_pr(translate_gitea_pull(p), owner, name)
  end, graphql_prs_connection)
end)

-- Repository.releases: paginated list of releases.
-- Gitea release objects are already GitHub-REST-compatible; no intermediate translator needed.
b:graphql("Repository.releases", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitea_repo_connection(owner, name, "/releases", args, ctx, function(r)
    return graphql_translate_release(r, owner, name)
  end, function(n, a, t, c)
    return graphql_make_connection("Release", n, a, t, c)
  end)
end)

-- Repository.labels: paginated list of labels.
b:graphql("Repository.labels", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitea_repo_connection(owner, name, "/labels", args, ctx, function(l)
    return graphql_translate_label(translate_gitea_label(l), owner, name)
  end, graphql_labels_connection)
end)

-- Repository.milestones: paginated list of milestones.
b:graphql("Repository.milestones", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitea_repo_connection(owner, name, "/milestones", args, ctx, function(m)
    return graphql_translate_milestone(translate_gitea_milestone(m), owner, name)
  end, function(n, a, t, c)
    return graphql_make_connection("Milestone", n, a, t, c)
  end)
end)

-- Repository.refs: paginated list of branches as Ref objects.
-- gitea_repo_connection fetches items inline (intentionally not capability-backed
-- to avoid O(n) per-item fetches).  translate_gitea_branch normalises commit.sha.
b:graphql("Repository.refs", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitea_repo_connection(owner, name, "/branches", args, ctx, function(br)
    return graphql_translate_ref(translate_gitea_branch(br), parent)
  end, graphql_refs_connection)
end)

-- Issue.comments: paginated list of comments for a single issue.
-- Decodes the Issue node ID to extract owner/repo/number, then fetches
-- /api/v1/repos/{owner}/{repo}/issues/{number}/comments.
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
    .. "/repos/"
    .. owner
    .. "/"
    .. repo
    .. "/issues/"
    .. number
    .. "/comments"
  local total
  if args.last and not args.before then
    total =
      graphql_prefetch_total_from_headers(fetch_json, url_base, GITEA_PAGES, GITEA_TOTAL_HEADERS)
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
end)

-- PullRequest.commits: paginated commit list for a pull request.
-- Decodes the PullRequest node ID (PullRequest:owner/repo/number) for coordinates,
-- then fetches /api/v1/repos/{owner}/{repo}/pulls/{number}/commits.
b:graphql("PullRequest.commits", function(parent, args, ctx)
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
    total =
      graphql_prefetch_total_from_headers(fetch_json, url_base, GITEA_PAGES, GITEA_TOTAL_HEADERS)
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
      commit = graphql_translate_commit(c, owner, repo),
      url = c.html_url,
    }
  end
  return graphql_make_connection("PullRequestCommit", nodes, args, total, ctx)
end)

-- PullRequest.reviews: paginated review list for a pull request.
b:graphql("PullRequest.reviews", function(parent, args, ctx)
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
    total =
      graphql_prefetch_total_from_headers(fetch_json, url_base, GITEA_PAGES, GITEA_TOTAL_HEADERS)
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
end)

-- Repository.collaborators: paginated list of collaborators as Users.
b:graphql("Repository.collaborators", function(parent, args, ctx)
  local owner, name = parent.nameWithOwner:match("^([^/]+)/(.+)$")
  if not owner then
    return nil
  end
  return gitea_repo_connection(owner, name, "/collaborators", args, ctx, function(u)
    return graphql_translate_user(translate_user(u))
  end, function(n, a, t, c)
    return graphql_make_connection("RepositoryCollaborator", n, a, t, c)
  end)
end)

-- Repository.defaultBranchRef: enrich the inline stub with full branch data.
-- The parent already carries {__typename="Ref",name="main"} from graphql_translate_repo.
-- This resolver makes a second call to get the commit SHA.
-- Gitea branch objects use commit.id for the SHA; we normalise to commit.sha before
-- passing to graphql_translate_ref.
b:graphql("Repository.defaultBranchRef", function(parent, _args, _ctx)
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
end)

-- Repository.languages: fetch language byte-count breakdown as a LanguageConnection.
-- Gitea returns {"Language": bytes, ...}; we convert to the Relay Connection shape.
-- Language colours are not available from Gitea's API; color is always nil.
b:graphql("Repository.languages", function(parent, _args, _ctx)
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
end)

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
b:graphql("Query.search", function(_parent, args, ctx)
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

-- ---------------------------------------------------------------------------
-- GraphQL mutation resolvers
-- ---------------------------------------------------------------------------

-- Mutation.createRepository: create a new repository for the authenticated user or an org.
-- Input fields: name (required), description, visibility, initializeWithReadme, ownerId.
-- If ownerId decodes to an Organization, uses POST /orgs/{org}/repos; otherwise /user/repos.
b:graphql("Mutation.createRepository", function(_parent, args, ctx)
  local input = args and args.input
  if not input or not input.name then
    return graphql_error(ctx, "createRepository requires input.name", nil, "BAD_USER_INPUT")
  end
  local cmid = get_client_mutation_id(args)
  local body = EncodeJson({
    name = input.name,
    description = input.description,
    private = input.visibility == "PRIVATE",
    auto_init = input.initializeWithReadme,
  })
  local data, err
  if input.ownerId then
    local t, lid = decode_node_id(input.ownerId)
    if t == "Organization" then
      data, err = repos.create_org(lid, body)
    else
      data, err = repos.create_user(body)
    end
  else
    data, err = repos.create_user(body)
  end
  if not data then
    graphql_error(ctx, err and err.message or "error creating repository")
    return nil
  end
  return {
    repository = graphql_translate_repo(data),
    clientMutationId = cmid,
  }
end)

-- Mutation.updateRepository: update metadata for an existing repository.
-- Input fields: repositoryId (required, Repository node ID), name, description,
--   visibility, hasIssuesEnabled, hasWikiEnabled, homepageUrl.
-- Sends PATCH /repos/{owner}/{repo} with only the supplied fields.
b:graphql("Mutation.updateRepository", function(_parent, args, ctx)
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
  local data, err = repos.update(owner, repo, body)
  if not data then
    graphql_error(ctx, err and err.message or "error updating repository")
    return nil
  end
  return {
    repository = graphql_translate_repo(data),
    clientMutationId = cmid,
  }
end)

-- Mutation.deleteRepository: permanently delete a repository.
-- Input fields: repositoryId (required, Repository node ID).
-- Sends DELETE /repos/{owner}/{repo} and expects 204 No Content.
-- The payload only contains the optional clientMutationId (no body to translate).
b:graphql("Mutation.deleteRepository", function(_parent, args, ctx)
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
  local ok, err = repos.delete(owner, repo)
  if not ok then
    if err.status == 0 then
      graphql_error(ctx, "network error deleting repository", nil, "INTERNAL_ERROR")
    elseif err.status == 401 or err.status == 403 then
      graphql_error(ctx, "not authorized to delete repository", nil, "FORBIDDEN")
    elseif err.status == 404 then
      graphql_error(ctx, "repository not found", nil, "NOT_FOUND")
    else
      graphql_error(
        ctx,
        "upstream error " .. tostring(err.status) .. " deleting repository",
        nil,
        "INTERNAL_ERROR"
      )
    end
    return nil
  end
  return { clientMutationId = cmid }
end)

-- ---------------------------------------------------------------------------
-- Issue mutations
-- ---------------------------------------------------------------------------

-- Mutation.createIssue: create a new issue in a repository.
-- Input fields: repositoryId (required, Repository node ID), title (required),
--   body, labelIds (array of Label node IDs), assigneeIds (array of User node IDs),
--   milestoneId (Milestone node ID).
-- Sends POST /repos/{owner}/{repo}/issues and returns the created issue.
b:graphql("Mutation.createIssue", function(_parent, args, ctx)
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
  local body = EncodeJson({
    title = input.title,
    body = input.body,
    labels = #labels > 0 and labels or nil,
    assignees = #assignees > 0 and assignees or nil,
    milestone = milestone_id,
  })
  local data, err = issues_cap.create(owner, repo, body)
  if not data then
    graphql_error(ctx, err and err.message or "error creating issue")
    return nil
  end
  return {
    issue = graphql_translate_issue(data, owner, repo),
    clientMutationId = cmid,
  }
end)

-- Mutation.updateIssue: update the title, body, and/or state of an issue.
-- Input fields: id (required, Issue node ID), title, body, state (OPEN or CLOSED).
-- Sends PATCH /repos/{owner}/{repo}/issues/{number}.
b:graphql("Mutation.updateIssue", function(_parent, args, ctx)
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
  local body = EncodeJson({ title = input.title, body = input.body, state = state })
  local data, err = issues_cap.update(owner, repo, number, body)
  if not data then
    graphql_error(ctx, err and err.message or "error updating issue")
    return nil
  end
  return {
    issue = graphql_translate_issue(data, owner, repo),
    clientMutationId = cmid,
  }
end)

-- Mutation.closeIssue: close an open issue.
-- Input fields: issueId (required, Issue node ID).
-- Sends PATCH /repos/{owner}/{repo}/issues/{number} with state=closed.
b:graphql("Mutation.closeIssue", function(_parent, args, ctx)
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
  local data, err = issues_cap.update(owner, repo, number, EncodeJson({ state = "closed" }))
  if not data then
    graphql_error(ctx, err and err.message or "error closing issue")
    return nil
  end
  return {
    issue = graphql_translate_issue(data, owner, repo),
    clientMutationId = cmid,
  }
end)

-- Mutation.reopenIssue: reopen a closed issue.
-- Input fields: issueId (required, Issue node ID).
-- Sends PATCH /repos/{owner}/{repo}/issues/{number} with state=open.
b:graphql("Mutation.reopenIssue", function(_parent, args, ctx)
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
  local data, err = issues_cap.update(owner, repo, number, EncodeJson({ state = "open" }))
  if not data then
    graphql_error(ctx, err and err.message or "error reopening issue")
    return nil
  end
  return {
    issue = graphql_translate_issue(data, owner, repo),
    clientMutationId = cmid,
  }
end)

-- Mutation.createPullRequest: open a new pull request in a repository.
-- Input fields: repositoryId (required, Repository node ID), title (required),
--   body, headRefName (required, source branch), baseRefName (required, target branch).
-- Sends POST /repos/{owner}/{repo}/pulls and returns the created pull request.
b:graphql("Mutation.createPullRequest", function(_parent, args, ctx)
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
  local body = EncodeJson({
    title = input.title,
    body = input.body,
    head = input.headRefName,
    base = input.baseRefName,
  })
  local data, err = pulls_cap.create(owner, repo, body)
  if not data then
    graphql_error(ctx, err and err.message or "error creating pull request")
    return nil
  end
  return {
    pullRequest = graphql_translate_pr(data, owner, repo),
    clientMutationId = cmid,
  }
end)

-- Mutation.updatePullRequest: update the title, body, and/or base branch of a pull request.
-- Input fields: pullRequestId (required, PullRequest node ID), title, body, baseRefName.
-- Sends PATCH /repos/{owner}/{repo}/pulls/{number}.
b:graphql("Mutation.updatePullRequest", function(_parent, args, ctx)
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
  local body = EncodeJson({ title = input.title, body = input.body, base = input.baseRefName })
  local data, err = pulls_cap.update(owner, repo, number, body)
  if not data then
    graphql_error(ctx, err and err.message or "error updating pull request")
    return nil
  end
  return {
    pullRequest = graphql_translate_pr(data, owner, repo),
    clientMutationId = cmid,
  }
end)

-- Mutation.closePullRequest: close an open pull request.
-- Input fields: pullRequestId (required, PullRequest node ID).
-- Sends PATCH /repos/{owner}/{repo}/pulls/{number} with state=closed.
b:graphql("Mutation.closePullRequest", function(_parent, args, ctx)
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
  local data, err = pulls_cap.update(owner, repo, number, EncodeJson({ state = "closed" }))
  if not data then
    graphql_error(ctx, err and err.message or "error closing pull request")
    return nil
  end
  return {
    pullRequest = graphql_translate_pr(data, owner, repo),
    clientMutationId = cmid,
  }
end)

-- Mutation.reopenPullRequest: reopen a closed pull request.
-- Input fields: pullRequestId (required, PullRequest node ID).
-- Sends PATCH /repos/{owner}/{repo}/pulls/{number} with state=open.
b:graphql("Mutation.reopenPullRequest", function(_parent, args, ctx)
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
  local data, err = pulls_cap.update(owner, repo, number, EncodeJson({ state = "open" }))
  if not data then
    graphql_error(ctx, err and err.message or "error reopening pull request")
    return nil
  end
  return {
    pullRequest = graphql_translate_pr(data, owner, repo),
    clientMutationId = cmid,
  }
end)

-- Mutation.mergePullRequest: merge an open pull request.
-- Input fields: pullRequestId (required, PullRequest node ID), mergeMethod
--   (MERGE/SQUASH/REBASE; defaults to MERGE), commitHeadline, commitBody.
-- Sends POST /repos/{owner}/{repo}/pulls/{number}/merge (Gitea uses POST; GitHub uses PUT).
-- The merge endpoint returns 204 No Content, so the PR is re-fetched to populate the payload.
b:graphql("Mutation.mergePullRequest", function(_parent, args, ctx)
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
  local merge_body = EncodeJson({
    Do = do_method,
    MergeTitleField = input.commitHeadline,
    MergeMessageField = input.commitBody,
  })
  -- POST to Gitea's merge endpoint; it returns 204 No Content on success.
  local ok, merge_err = pulls_cap.merge(owner, repo, number, merge_body)
  if not ok then
    if merge_err.status == 0 then
      graphql_error(ctx, merge_err.message, nil, "INTERNAL_ERROR")
    elseif merge_err.status == 401 or merge_err.status == 403 then
      graphql_error(ctx, merge_err.message, nil, "FORBIDDEN")
    elseif merge_err.status == 404 then
      graphql_error(ctx, merge_err.message, nil, "NOT_FOUND")
    elseif merge_err.status == 405 then
      graphql_error(ctx, merge_err.message, nil, "UNPROCESSABLE")
    else
      graphql_error(ctx, merge_err.message, nil, "INTERNAL_ERROR")
    end
    return nil
  end
  -- Re-fetch the PR to return in the payload (merge returns 204, no body).
  local pr_data, _ = pulls_cap.get(owner, repo, number)
  if not pr_data then
    return nil
  end
  return {
    pullRequest = graphql_translate_pr(pr_data, owner, repo),
    clientMutationId = cmid,
  }
end)

-- ---------------------------------------------------------------------------
-- Comment mutations
-- ---------------------------------------------------------------------------

-- Mutation.addComment: add a comment to an issue or pull request.
-- Input fields: subjectId (required, Issue or PullRequest node ID), body (required).
-- Sends POST /repos/{owner}/{repo}/issues/{number}/comments.
-- Both Issue and PullRequest node IDs route to the /issues/{n}/comments path — Gitea
-- uses the issues endpoint for PR comments too.
-- The payload returns commentEdge (containing the new IssueComment) and clientMutationId.
b:graphql("Mutation.addComment", function(_parent, args, ctx)
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
  local body = EncodeJson({ body = input.body })
  local data, cerr = comments_cap.create(owner, repo, number, body)
  if not data then
    if cerr.status == 0 then
      graphql_error(ctx, cerr.message, nil, "INTERNAL_ERROR")
    elseif cerr.status == 401 or cerr.status == 403 then
      graphql_error(ctx, cerr.message, nil, "FORBIDDEN")
    elseif cerr.status == 404 then
      graphql_error(ctx, cerr.message, nil, "NOT_FOUND")
    else
      graphql_error(ctx, cerr.message, nil, "INTERNAL_ERROR")
    end
    return nil
  end
  local comment = graphql_translate_comment(data, owner, repo)
  return {
    commentEdge = {
      __typename = "IssueCommentEdge",
      cursor = graphql_page_to_cursor(1, 1),
      node = comment,
    },
    clientMutationId = cmid,
  }
end)

-- Mutation.updateIssueComment: update the body of an existing issue comment.
-- Input fields: id (required, IssueComment node ID), body (required).
-- Sends PATCH /repos/{owner}/{repo}/issues/comments/{comment_id}.
b:graphql("Mutation.updateIssueComment", function(_parent, args, ctx)
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
  local body = EncodeJson({ body = input.body })
  local data, cerr = comments_cap.update(owner, repo, cid, body)
  if not data then
    if cerr.status == 0 then
      graphql_error(ctx, cerr.message, nil, "INTERNAL_ERROR")
    elseif cerr.status == 401 or cerr.status == 403 then
      graphql_error(ctx, cerr.message, nil, "FORBIDDEN")
    elseif cerr.status == 404 then
      graphql_error(ctx, cerr.message, nil, "NOT_FOUND")
    else
      graphql_error(ctx, cerr.message, nil, "INTERNAL_ERROR")
    end
    return nil
  end
  return {
    issueComment = graphql_translate_comment(data, owner, repo),
    clientMutationId = cmid,
  }
end)

-- Mutation.deleteIssueComment: delete an issue comment.
-- Input fields: id (required, IssueComment node ID).
-- Sends DELETE /repos/{owner}/{repo}/issues/comments/{comment_id}.
-- Returns 204 No Content on success; the payload only contains the optional clientMutationId.
b:graphql("Mutation.deleteIssueComment", function(_parent, args, ctx)
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
  local ok, cerr = comments_cap.delete(owner, repo, cid)
  if not ok then
    if cerr.status == 0 then
      graphql_error(ctx, cerr.message, nil, "INTERNAL_ERROR")
    elseif cerr.status == 401 or cerr.status == 403 then
      graphql_error(ctx, cerr.message, nil, "FORBIDDEN")
    elseif cerr.status == 404 then
      graphql_error(ctx, cerr.message, nil, "NOT_FOUND")
    else
      graphql_error(ctx, cerr.message, nil, "INTERNAL_ERROR")
    end
    return nil
  end
  return { clientMutationId = cmid }
end)

b:graphql("Mutation.addStar", function(_parent, args, ctx)
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
  local ok, cerr = activity.star(owner, repo)
  if not ok then
    if cerr.status == 0 then
      graphql_error(ctx, cerr.message, nil, "INTERNAL_ERROR")
    elseif cerr.status == 401 or cerr.status == 403 then
      graphql_error(ctx, "not authorized to star repository", nil, "FORBIDDEN")
    elseif cerr.status == 404 then
      graphql_error(ctx, "repository not found", nil, "NOT_FOUND")
    else
      graphql_error(ctx, cerr.message, nil, "INTERNAL_ERROR")
    end
    return nil
  end
  -- Re-fetch the repository to return in the payload (star returns 204, no body).
  local repo_data =
    graphql_fetch_or_error(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo, ctx, nil)
  if not repo_data then
    return nil
  end
  return {
    starrable = graphql_translate_repo(translate_repo(repo_data)),
    clientMutationId = cmid,
  }
end)

b:graphql("Mutation.removeStar", function(_parent, args, ctx)
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
  local ok, cerr = activity.unstar(owner, repo)
  if not ok then
    if cerr.status == 0 then
      graphql_error(ctx, cerr.message, nil, "INTERNAL_ERROR")
    elseif cerr.status == 401 or cerr.status == 403 then
      graphql_error(ctx, "not authorized to unstar repository", nil, "FORBIDDEN")
    elseif cerr.status == 404 then
      graphql_error(ctx, "repository not found", nil, "NOT_FOUND")
    else
      graphql_error(ctx, cerr.message, nil, "INTERNAL_ERROR")
    end
    return nil
  end
  -- Re-fetch the repository to return in the payload (unstar returns 204, no body).
  local repo_data =
    graphql_fetch_or_error(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo, ctx, nil)
  if not repo_data then
    return nil
  end
  return {
    starrable = graphql_translate_repo(translate_repo(repo_data)),
    clientMutationId = cmid,
  }
end)

b:graphql("Mutation.updateSubscription", function(_parent, args, ctx)
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
  local ok, cerr
  if input.state == "UNSUBSCRIBED" then
    ok, cerr = activity.delete_subscription(owner, repo)
  else
    -- SUBSCRIBED and IGNORED both use PUT with a JSON body.
    local body = EncodeJson({
      subscribed = input.state == "SUBSCRIBED",
      ignored = input.state == "IGNORED",
    })
    ok, cerr = activity.set_subscription(owner, repo, body)
  end
  if not ok then
    if cerr.status == 0 then
      graphql_error(ctx, cerr.message, nil, "INTERNAL_ERROR")
    elseif cerr.status == 401 or cerr.status == 403 then
      graphql_error(ctx, "not authorized to update subscription", nil, "FORBIDDEN")
    elseif cerr.status == 404 then
      graphql_error(ctx, "repository not found", nil, "NOT_FOUND")
    else
      graphql_error(ctx, cerr.message, nil, "INTERNAL_ERROR")
    end
    return nil
  end
  -- Re-fetch the repository to return in the payload.
  local repo_data =
    graphql_fetch_or_error(fetch_json, base() .. "/repos/" .. owner .. "/" .. repo, ctx, nil)
  if not repo_data then
    return nil
  end
  return {
    subscribable = graphql_translate_repo(translate_repo(repo_data)),
    clientMutationId = cmid,
  }
end)

b:graphql("Mutation.createLabel", function(_parent, args, ctx)
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
  -- GitHub sends color without '#'; Gitea expects '#' prefix.
  local body = EncodeJson({
    name = input.name,
    color = "#" .. input.color,
    description = input.description,
  })
  local data, cerr = labels_cap.create(owner, repo, body)
  if not data then
    if cerr.status == 0 then
      graphql_error(ctx, cerr.message, nil, "INTERNAL_ERROR")
    elseif cerr.status == 401 or cerr.status == 403 then
      graphql_error(ctx, cerr.message, nil, "FORBIDDEN")
    else
      graphql_error(ctx, cerr.message, nil, "INTERNAL_ERROR")
    end
    return nil
  end
  return {
    label = graphql_translate_label(data, owner, repo),
    clientMutationId = cmid,
  }
end)

b:graphql("Mutation.addLabelsToLabelable", function(_parent, args, ctx)
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
    local pr_data, _ = pulls_cap.get(owner, repo, number)
    if not pr_data then
      return nil
    end
    item_data = graphql_translate_pr(pr_data, owner, repo)
  else
    local issue_data, _ = issues_cap.get(owner, repo, number)
    if not issue_data then
      return nil
    end
    item_data = graphql_translate_issue(issue_data, owner, repo)
  end
  return {
    labelable = item_data,
    clientMutationId = cmid,
  }
end)

b:capability("repos", repos)
b:capability("users", users)
b:capability("orgs", orgs)
b:capability("issues", issues_cap)
b:capability("pulls", pulls_cap)
b:capability("labels", labels_cap)
b:capability("milestones", milestones_cap)
b:capability("comments", comments_cap)
b:capability("branches", branches)
b:capability("repo_metadata", repo_metadata)
b:capability("commits", commits_cap)
b:capability("contents", contents)
b:capability("collaborators", collaborators)
b:capability("forks", forks)
b:capability("commit_comments", commit_comments)
b:capability("releases", releases)
b:capability("deploy_keys", deploy_keys)
b:capability("webhooks", webhooks)
b:capability("ssh_keys", ssh_keys)
b:capability("gpg_keys", gpg_keys)
b:capability("user_emails", user_emails)
b:capability("reactions", reactions_cap)
b:capability("issue_events", issue_events_cap)
b:capability("pr_subs", pr_subs)
b:capability("activity", activity)
b:capability("checks", checks)
b:capability("git_db", git_db)
b:capability("teams", teams)
b:capability("actions", actions_cap)
b:capability("packages", packages_cap)
b:capability("search", search_cap)
b:capability("markdown", markdown_cap)
b:capability("meta", meta_cap)
b:set_allow_anonymous(_allow_anon)
b:build()
