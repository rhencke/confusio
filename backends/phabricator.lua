-- Phabricator backend handler overrides.
-- Uses Phabricator Conduit API at /api/.
-- Issues: maniphest.search (tasks linked to projects via project PHID).
-- Projects: project.search (find by slug = owner/repo or just repo).
-- Comments: transaction.search (type = comment, objectIdentifier = T{N}).
-- Checks: diffusion.commit.search + harbormaster.build.search (Harbormaster builds).
if config.base_url == "" then
  config.base_url = "https://phabricator.example.com"
end

-- Get the Conduit API token from the Authorization header.
local function api_token()
  local h = GetHeader("Authorization")
  if not h or h == "" then
    return nil
  end
  return h:match("^[Tt]oken%s+(.+)$") or h:match("^[Bb]earer%s+(.+)$") or h
end

-- POST to a Conduit method with a flat table of params.
-- Params with array-style keys (e.g. "constraints[ids][0]") are passed directly.
-- Returns ok, status, headers, body (same shape as pcall(Fetch, ...)).
local function conduit(method, params)
  local parts = {}
  local tok = api_token()
  if tok then
    parts[#parts + 1] = "api.token=" .. EscapeParam(tok)
  end
  for k, v in pairs(params or {}) do
    parts[#parts + 1] = EscapeParam(k) .. "=" .. EscapeParam(tostring(v))
  end
  return pcall(Fetch, config.base_url .. "/api/" .. method, {
    method = "POST",
    body = table.concat(parts, "&"),
    headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
  })
end

-- Unwrap a Conduit response: check for API-level errors and return result table.
-- Returns nil if the response is an error or cannot be decoded.
local function conduit_result(ok, status, _headers, body)
  if not ok or status ~= 200 then
    return nil, status or 503
  end
  local r = DecodeJson(body)
  if not r or r.error_code then
    return nil, 400
  end
  return r.result, 200
end

-- Translate Unix timestamp (int or string) to ISO 8601 string.
local function ts(t)
  if not t or t == 0 then
    return ""
  end
  -- Redbean's FormatHttpDateTime is not available for arbitrary epochs,
  -- so produce a minimal ISO-8601 string via os.date.
  return os.date("!%Y-%m-%dT%H:%M:%SZ", tonumber(t))
end

-- Translate a Maniphest task object (from maniphest.search) to GitHub issue format.
-- Task: { id, phid, fields: { name, status, authorPHID, ownerPHID, dateCreated, dateModified, description } }
local function translate_task(t)
  if not t then
    return {}
  end
  local f = t.fields or {}
  local status_obj = f.status or {}
  local state = (status_obj.value == "open" or status_obj.value == nil) and "open" or "closed"
  if status_obj.closed then
    state = "closed"
  end
  local desc = f.description or {}
  return {
    id = t.id or 0,
    node_id = t.phid or "",
    number = t.id or 0,
    title = f.name or "",
    body = type(desc) == "table" and (desc.raw or "") or tostring(desc),
    state = state,
    user = {
      login = f.authorPHID or "",
      id = 0,
      node_id = f.authorPHID or "",
      avatar_url = "",
      url = "",
      type = "User",
    },
    assignees = {},
    labels = {},
    milestone = nil,
    created_at = ts(f.dateCreated),
    updated_at = ts(f.dateModified),
    closed_at = nil,
    html_url = config.base_url .. "/T" .. (t.id or ""),
  }
end

-- Look up a project PHID by slug (repo name, or owner/repo).
-- Returns the PHID string on success, nil on failure.
local function resolve_project_phid(owner, repo_name)
  -- Try "owner/repo" slug first, then fall back to just "repo".
  local slug = owner ~= "" and (owner .. "/" .. repo_name) or repo_name
  local ok, status, _, body = conduit("project.search", {
    ["constraints[slugs][0]"] = slug,
    ["limit"] = 1,
  })
  local result = conduit_result(ok, status, nil, body)
  if result and result.data and result.data[1] then
    return result.data[1].phid
  end
  -- Fallback: search by just the repo name.
  if owner ~= "" then
    local ok2, status2, _, body2 = conduit("project.search", {
      ["constraints[slugs][0]"] = repo_name,
      ["limit"] = 1,
    })
    local result2 = conduit_result(ok2, status2, nil, body2)
    if result2 and result2.data and result2.data[1] then
      return result2.data[1].phid
    end
  end
  return nil
end

-- Checks (via Harbormaster builds) -------------------------------------------
--
-- Phabricator Harbormaster stores CI builds linked to Diffusion commits.
--   • GET commits/{ref}/check-runs:
--       1. diffusion.commit.search (constraints[identifiers][0]=sha) → commit PHID
--       2. harbormaster.build.search (constraints[buildables][0]=commit PHID) → builds
--   • POST check-runs / GET|PATCH by id → stubs (no write API equivalent)
--   • Check Suites have no Harbormaster equivalent; all suite endpoints are stubs.
--   • Annotations are always empty.
--
-- Status mapping (Harbormaster → GitHub):
--   building/paused  → status=in_progress, conclusion=null
--   passed           → status=completed,   conclusion=success
--   failed/aborted/unexpected/deadlocked → status=completed, conclusion=failure

-- Look up a commit PHID from a SHA via diffusion.commit.search.
-- Returns the PHID string on success, nil on failure.
local function resolve_commit_phid(sha)
  local ok, status, _, body = conduit("diffusion.commit.search", {
    ["constraints[identifiers][0]"] = sha,
    ["limit"] = 1,
  })
  local result = conduit_result(ok, status, nil, body)
  if result and result.data and result.data[1] then
    return result.data[1].phid
  end
  return nil
end

-- Translate a Harbormaster build object to a GitHub check run object.
local function translate_harbormaster_build(b, ref)
  if not b then
    return {}
  end
  local f = b.fields or {}
  local hs = f.buildStatus or {}
  local raw_status = hs.value or "building"
  local gh_status, gh_conclusion
  if raw_status == "passed" then
    gh_status = "completed"
    gh_conclusion = "success"
  elseif
    raw_status == "failed"
    or raw_status == "aborted"
    or raw_status == "unexpected"
    or raw_status == "deadlocked"
  then
    gh_status = "completed"
    gh_conclusion = "failure"
  else
    -- building, paused, or unknown
    gh_status = "in_progress"
    gh_conclusion = nil
  end
  local plan = f.buildPlan or {}
  local name = plan.name or ("build/" .. tostring(b.id or 0))
  local date_created = ts(f.dateCreated)
  local date_modified = ts(f.dateModified)
  return {
    id = b.id or 0,
    node_id = b.phid or "",
    head_sha = ref,
    name = name,
    status = gh_status,
    conclusion = gh_conclusion,
    started_at = date_created,
    completed_at = gh_status == "completed" and date_modified or nil,
    output = {
      title = name,
      summary = raw_status,
      text = "",
      annotations_count = 0,
      annotations_url = "",
    },
    url = "",
    html_url = config.base_url .. "/B" .. tostring(b.id or ""),
    details_url = "",
  }
end

local b = make_backend_builder()
b:rest("get_root", function()
  proxy_health_check(pcall(Fetch, config.base_url .. "/api/conduit.ping"))
end)

-- Issues --------------------------------------------------------------------
-- GET /repos/{owner}/{repo}/issues
-- Phabricator: POST /api/maniphest.search with constraints[projects][0]=PHID

b:rest("get_repo_issues", function(owner, repo_name)
  local phid = resolve_project_phid(owner, repo_name)
  if not phid then
    respond_json(404, { message = "Not Found" })
    return
  end
  local count = tonumber(GetParam("per_page")) or 30
  local page = tonumber(GetParam("page")) or 1
  local state = GetParam("state") or "open"
  local params = {
    ["constraints[projects][0]"] = phid,
    ["limit"] = count,
  }
  -- Phabricator cursor pagination: compute after cursor for page > 1.
  -- Each page has 'count' items; after = (page-1)*count as a numeric cursor string.
  if page > 1 then
    params["after"] = tostring((page - 1) * count)
  end
  if state == "open" then
    params["constraints[statuses][0]"] = "open"
  elseif state == "closed" then
    params["constraints[statuses][0]"] = "resolved"
    params["constraints[statuses][1]"] = "wontfix"
    params["constraints[statuses][2]"] = "invalid"
    params["constraints[statuses][3]"] = "spite"
  end
  -- state == "all": no status constraint
  local ok, status, _, body = conduit("maniphest.search", params)
  local result, err = conduit_result(ok, status, nil, body)
  if not result then
    respond_json(err or 503, {})
    return
  end
  local issues = {}
  for _, t in ipairs(result.data or {}) do
    issues[#issues + 1] = translate_task(t)
  end
  respond_json(200, issues)
end)

-- GET /repos/{owner}/{repo}/issues/{issue_number}
-- Phabricator: POST /api/maniphest.search with constraints[ids][0]=N

b:rest("get_repo_issue", function(_owner, _repo_name, issue_number)
  local ok, status, _, body = conduit("maniphest.search", {
    ["constraints[ids][0]"] = issue_number,
    ["limit"] = 1,
  })
  local result, err = conduit_result(ok, status, nil, body)
  if not result then
    respond_json(err or 503, {})
    return
  end
  local t = (result.data or {})[1]
  if not t then
    respond_json(404, { message = "Not Found" })
    return
  end
  respond_json(200, translate_task(t))
end)

-- GET /repos/{owner}/{repo}/issues/{issue_number}/comments
-- Phabricator: POST /api/transaction.search with objectIdentifier=T{N}
-- Filter to comment-type transactions only.

b:rest("get_issue_comments", function(_owner, _repo_name, issue_number)
  local count = tonumber(GetParam("per_page")) or 30
  local page = tonumber(GetParam("page")) or 1
  local params = {
    ["objectIdentifier"] = "T" .. issue_number,
    ["limit"] = count,
  }
  if page > 1 then
    params["after"] = tostring((page - 1) * count)
  end
  local ok, status, _, body = conduit("transaction.search", params)
  local result, err = conduit_result(ok, status, nil, body)
  if not result then
    respond_json(err or 503, {})
    return
  end
  local comments = {}
  for _, txn in ipairs(result.data or {}) do
    -- Only include comment transactions (type = "comment").
    if txn.type == "comment" then
      local comment = txn.comments and txn.comments[1]
      local content = comment and (comment.content or {})
      comments[#comments + 1] = {
        id = txn.id or 0,
        node_id = txn.phid or "",
        url = "",
        body = type(content) == "table" and (content.raw or "") or tostring(content),
        user = {
          login = (txn.authorPHID or ""),
          id = 0,
          node_id = txn.authorPHID or "",
          avatar_url = "",
          url = "",
          type = "User",
        },
        created_at = ts(txn.dateCreated),
        updated_at = ts(txn.dateModified),
        html_url = "",
      }
    end
  end
  respond_json(200, comments)
end)

-- Checks (via Harbormaster) -------------------------------------------------

-- GET /repos/{owner}/{repo}/commits/{ref}/check-runs
-- 1. Resolve commit PHID via diffusion.commit.search.
-- 2. List Harbormaster builds for that commit's buildable.
b:rest("get_commit_check_runs", function(_owner, _repo_name, ref)
  local commit_phid = resolve_commit_phid(ref)
  if not commit_phid then
    respond_json(200, { total_count = 0, check_runs = {} })
    return
  end
  local ok, status, _, body = conduit("harbormaster.build.search", {
    ["constraints[buildables][0]"] = commit_phid,
    ["limit"] = 100,
  })
  local result, err = conduit_result(ok, status, nil, body)
  if not result then
    respond_json(err or 503, {})
    return
  end
  local runs = {}
  for _, br in ipairs(result.data or {}) do
    runs[#runs + 1] = translate_harbormaster_build(br, ref)
  end
  respond_json(200, { total_count = #runs, check_runs = runs })
end)

b:build()
