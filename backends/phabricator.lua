-- Phabricator backend handler overrides.
-- Uses Phabricator Conduit API at /api/.
-- Issues: maniphest.search (tasks linked to projects via project PHID).
-- Projects: project.search (find by slug = owner/repo or just repo).
-- Comments: transaction.search (type = comment, objectIdentifier = T{N}).
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

backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, config.base_url .. "/api/conduit.ping")
    if ok and status == 200 then
      respond_json(200, "OK", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,

  -- Issues --------------------------------------------------------------------
  -- GET /repos/{owner}/{repo}/issues
  -- Phabricator: POST /api/maniphest.search with constraints[projects][0]=PHID

  get_repo_issues = function(owner, repo_name)
    local phid = resolve_project_phid(owner, repo_name)
    if not phid then
      respond_json(404, "Not Found", { message = "Not Found" })
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
      respond_json(err or 503, "Error", {})
      return
    end
    local issues = {}
    for _, t in ipairs(result.data or {}) do
      issues[#issues + 1] = translate_task(t)
    end
    respond_json(200, "OK", issues)
  end,

  -- GET /repos/{owner}/{repo}/issues/{issue_number}
  -- Phabricator: POST /api/maniphest.search with constraints[ids][0]=N

  get_repo_issue = function(_owner, _repo_name, issue_number)
    local ok, status, _, body = conduit("maniphest.search", {
      ["constraints[ids][0]"] = issue_number,
      ["limit"] = 1,
    })
    local result, err = conduit_result(ok, status, nil, body)
    if not result then
      respond_json(err or 503, "Error", {})
      return
    end
    local t = (result.data or {})[1]
    if not t then
      respond_json(404, "Not Found", { message = "Not Found" })
      return
    end
    respond_json(200, "OK", translate_task(t))
  end,

  -- GET /repos/{owner}/{repo}/issues/{issue_number}/comments
  -- Phabricator: POST /api/transaction.search with objectIdentifier=T{N}
  -- Filter to comment-type transactions only.

  get_issue_comments = function(_owner, _repo_name, issue_number)
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
      respond_json(err or 503, "Error", {})
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
    respond_json(200, "OK", comments)
  end,
}
