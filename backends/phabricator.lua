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
local function phabricator_task_fields(t)
  return (t or {}).fields or {}
end

local function phabricator_task_id(t)
  local f = phabricator_task_fields(t)
  return (t or {}).id
    or f.id
    or tonumber((t or {}).monogram and (t or {}).monogram:match("^T(%d+)$"))
    or 0
end

local function phabricator_task_state(t)
  local f = phabricator_task_fields(t)
  local status_obj = type(f.status) == "table" and f.status or {}
  local status_value = status_obj.value or f.status
  local state = (status_value == "open" or status_value == nil) and "open" or "closed"
  if status_obj.closed or f.closed then
    state = "closed"
  end
  return state
end

local function phabricator_task_body(t)
  local desc = phabricator_task_fields(t).description or {}
  return type(desc) == "table" and (desc.raw or "") or tostring(desc)
end

local translate_phabricator_user = make_translator({
  login = computed(function(phid)
    return phid or ""
  end),
  id = const(0),
  node_id = computed(function(phid)
    return phid or ""
  end),
  avatar_url = const(""),
  url = const(""),
  type = const("User"),
})

local function phabricator_user(phid)
  return translate_phabricator_user(phid or "")
end

local translate_task = make_translator({
  id = computed(phabricator_task_id),
  node_id = field("phid", { default = "" }),
  number = computed(phabricator_task_id),
  title = computed(function(t)
    local f = phabricator_task_fields(t)
    return f.name or t.name or t.title or ""
  end),
  body = computed(phabricator_task_body),
  state = computed(phabricator_task_state),
  user = computed(function(t)
    return phabricator_user(phabricator_task_fields(t).authorPHID)
  end),
  assignees = computed(function()
    return {}
  end),
  labels = computed(function()
    return {}
  end),
  milestone = const(nil),
  created_at = computed(function(t)
    return ts(phabricator_task_fields(t).dateCreated)
  end),
  updated_at = computed(function(t)
    return ts(phabricator_task_fields(t).dateModified)
  end),
  closed_at = const(nil),
  html_url = computed(function(t)
    local id = phabricator_task_id(t)
    return t.uri or (config.base_url .. "/T" .. id)
  end),
})

local function phabricator_repository(payload)
  return payload.repository or payload.project or {}
end

local function phabricator_repository_id(repo)
  if type(repo) ~= "table" then
    return 0
  end
  return repo.id
    or (repo.fields or {}).id
    or tonumber(repo.monogram and repo.monogram:match("^r([A-Z0-9]+)$"))
    or 0
end

local function phabricator_repository_fields(repo)
  return (repo or {}).fields or {}
end

local function phabricator_repository_name(repo)
  local f = phabricator_repository_fields(repo)
  return f.shortName or f.name or repo.shortName or repo.name or ""
end

local function phabricator_repository_default_branch(repo)
  local f = phabricator_repository_fields(repo)
  return f.defaultBranch or f.repositoryBranch or repo.default_branch or "master"
end

local function phabricator_repository_clone_url(repo)
  local f = phabricator_repository_fields(repo)
  return f.cloneURI or f.uri or f.remoteURI or repo.clone_url or repo.uri or ""
end

local translate_phabricator_repository_owner = make_translator({
  login = computed(function(repo)
    return phabricator_repository_fields(repo).ownerPHID or ""
  end),
  id = const(0),
  node_id = computed(function(repo)
    return phabricator_repository_fields(repo).ownerPHID or ""
  end),
  avatar_url = const(""),
  url = const(""),
  type = const("User"),
})

local translate_phabricator_repository = make_translator({
  id = computed(phabricator_repository_id),
  node_id = field("phid", { default = "" }),
  name = computed(phabricator_repository_name),
  full_name = computed(function(repo)
    local f = phabricator_repository_fields(repo)
    local name = phabricator_repository_name(repo)
    return f.slug or f.fullName or repo.full_name or name
  end),
  private = computed(function(repo)
    local f = phabricator_repository_fields(repo)
    return f.viewPolicy and f.viewPolicy ~= "public" or repo.private or false
  end),
  owner = computed(function(repo)
    return translate_phabricator_repository_owner(repo)
  end),
  html_url = computed(function(repo)
    local f = phabricator_repository_fields(repo)
    return repo.uri
      or f.uri
      or (config.base_url .. "/diffusion/" .. tostring(phabricator_repository_id(repo)))
  end),
  description = computed(function(repo)
    local f = phabricator_repository_fields(repo)
    return f.description or repo.description
  end),
  fork = const(false),
  url = const(""),
  clone_url = computed(phabricator_repository_clone_url),
  ssh_url = computed(function(repo)
    local f = phabricator_repository_fields(repo)
    return f.sshURI or repo.ssh_url or phabricator_repository_clone_url(repo)
  end),
  default_branch = computed(phabricator_repository_default_branch),
  master_branch = computed(phabricator_repository_default_branch),
  created_at = computed(function(repo)
    return ts(phabricator_repository_fields(repo).dateCreated)
  end),
  updated_at = computed(function(repo)
    return ts(phabricator_repository_fields(repo).dateModified)
  end),
})

local function phabricator_object_phid_type(phid)
  if type(phid) ~= "string" then
    return nil
  end
  return phid:match("^PHID%-([A-Z0-9]+)%-")
end

local function phabricator_event_repository(payload)
  payload = payload or {}
  local repo = payload.repository or payload.project
  if type(repo) == "table" then
    return repo.full_name and repo or translate_phabricator_repository(repo)
  end
  local object = payload.object or {}
  if object.type == "REPO" or phabricator_object_phid_type(object.phid) == "REPO" then
    return translate_phabricator_repository(object)
  end
  return {}
end

local function phabricator_sender(payload, tx)
  local action = payload.action or {}
  return payload.sender
    or payload.actor
    or phabricator_user((tx and tx.authorPHID) or action.actorPHID)
end

local function phabricator_first_transaction_timestamp(payload)
  for _, tx in ipairs((payload or {}).transactions or {}) do
    if tx.dateModified or tx.dateCreated then
      return tx.dateModified or tx.dateCreated
    end
  end
  return nil
end

local function phabricator_task_timestamp(payload, tx)
  payload = payload or {}
  local action = payload.action or {}
  local fields = (payload.object or {}).fields or {}
  return ts(
    (tx and (tx.dateModified or tx.dateCreated))
      or action.epoch
      or phabricator_first_transaction_timestamp(payload)
      or fields.dateModified
      or fields.dateCreated
  )
end

local function phabricator_transaction_type(tx)
  if type(tx) ~= "table" then
    return ""
  end
  return tx.type or tx.transactionType or ""
end

local function phabricator_transaction_new_value(tx)
  if type(tx) ~= "table" then
    return nil
  end
  return tx.newValue or tx.new or tx.value
end

local function phabricator_comment_body(tx)
  local comments = tx and tx.comments
  local comment = comments and comments[1] or tx and tx.comment or {}
  local content = comment.content or {}
  return type(content) == "table" and (content.raw or content.remarkup or "") or tostring(content)
end

local translate_phabricator_comment = make_translator({
  id = field("id", { default = 0 }),
  node_id = field("phid", { default = "" }),
  url = const(""),
  body = computed(phabricator_comment_body),
  user = computed(function(tx)
    return phabricator_user(tx.authorPHID)
  end),
  created_at = computed(function(tx)
    return ts(tx.dateCreated)
  end),
  updated_at = computed(function(tx)
    return ts(tx.dateModified or tx.dateCreated)
  end),
  html_url = const(""),
})

local function phabricator_task_action(payload)
  for _, tx in ipairs(payload.transactions or {}) do
    local tx_type = phabricator_transaction_type(tx)
    if tx_type == "core:create" or tx_type == "create" then
      return "opened"
    elseif tx_type == "status" then
      local value = phabricator_transaction_new_value(tx)
      if value == "open" then
        return "reopened"
      end
      return "closed"
    end
  end
  return "edited"
end

local function phabricator_task_comment_transaction(payload)
  for _, tx in ipairs(payload.transactions or {}) do
    if phabricator_transaction_type(tx) == "comment" then
      return tx
    end
  end
  return nil
end

local function phabricator_revision_id(rev)
  if type(rev) ~= "table" then
    return 0
  end
  return rev.id
    or (rev.fields or {}).id
    or tonumber(rev.monogram and rev.monogram:match("^D(%d+)$"))
    or 0
end

local function phabricator_branch_name(value, fallback)
  if type(value) == "table" then
    return value.name or value.shortName or fallback or ""
  end
  return value or fallback or ""
end

local function phabricator_revision_fields(rev)
  return (rev or {}).fields or {}
end

local function phabricator_revision_status_value(rev)
  local f = phabricator_revision_fields(rev)
  local status = type(f.status) == "table" and f.status or {}
  return status.value or f.status or ""
end

local function phabricator_revision_closed(rev)
  local f = phabricator_revision_fields(rev)
  local status = type(f.status) == "table" and f.status or {}
  local status_value = phabricator_revision_status_value(rev)
  return status.closed or status_value == "accepted" or status_value == "abandoned"
end

local function phabricator_revision_body(rev)
  local summary = phabricator_revision_fields(rev).summary
  return type(summary) == "table" and (summary.raw or "") or tostring(summary or "")
end

local translate_differential_revision_head = make_translator({
  label = computed(function(rev)
    local f = phabricator_revision_fields(rev)
    return phabricator_branch_name(f.sourceBranch or f.branch, "HEAD")
  end),
  ref = computed(function(rev)
    local f = phabricator_revision_fields(rev)
    return phabricator_branch_name(f.sourceBranch or f.branch, "HEAD")
  end),
  sha = computed(function(rev)
    local f = phabricator_revision_fields(rev)
    return f.sourceCommit or f.diffPHID or ""
  end),
  repo = computed(function(_rev, payload)
    return phabricator_repository(payload or {})
  end),
})

local translate_differential_revision_base = make_translator({
  label = computed(function(rev)
    local f = phabricator_revision_fields(rev)
    return phabricator_branch_name(f.targetBranch or f.repositoryBranch, "master")
  end),
  ref = computed(function(rev)
    local f = phabricator_revision_fields(rev)
    return phabricator_branch_name(f.targetBranch or f.repositoryBranch, "master")
  end),
  sha = computed(function(rev)
    return phabricator_revision_fields(rev).targetCommit or ""
  end),
  repo = computed(function(_rev, payload)
    return phabricator_repository(payload or {})
  end),
})

local translate_differential_revision = make_translator({
  id = computed(phabricator_revision_id),
  node_id = field("phid", { default = "" }),
  number = computed(phabricator_revision_id),
  title = computed(function(rev)
    local f = phabricator_revision_fields(rev)
    return f.title or rev.title or rev.name or ""
  end),
  body = computed(phabricator_revision_body),
  state = computed(function(rev)
    return phabricator_revision_closed(rev) and "closed" or "open"
  end),
  user = computed(function(rev)
    return phabricator_user(phabricator_revision_fields(rev).authorPHID)
  end),
  head = computed(function(rev, payload)
    return translate_differential_revision_head(rev, payload)
  end),
  base = computed(function(rev, payload)
    return translate_differential_revision_base(rev, payload)
  end),
  draft = const(false),
  created_at = computed(function(rev)
    return ts(phabricator_revision_fields(rev).dateCreated)
  end),
  updated_at = computed(function(rev)
    return ts(phabricator_revision_fields(rev).dateModified)
  end),
  closed_at = computed(function(rev)
    return phabricator_revision_closed(rev) and ts(phabricator_revision_fields(rev).dateModified)
      or nil
  end),
  merged_at = computed(function(rev)
    return phabricator_revision_status_value(rev) == "accepted"
        and ts(phabricator_revision_fields(rev).dateModified)
      or nil
  end),
  merge_commit_sha = const(nil),
  merged = computed(function(rev)
    return phabricator_revision_status_value(rev) == "accepted"
  end),
  merged_by = computed(function(rev)
    return phabricator_revision_status_value(rev) == "accepted"
        and phabricator_user(phabricator_revision_fields(rev).authorPHID)
      or nil
  end),
  html_url = computed(function(rev)
    local id = phabricator_revision_id(rev)
    return rev.uri or (config.base_url .. "/D" .. id)
  end),
  url = const(""),
  mergeable = computed(function(rev)
    return not phabricator_revision_closed(rev) or nil
  end),
  comments = const(0),
  review_comments = const(0),
  commits = const(0),
  additions = const(0),
  deletions = const(0),
  changed_files = const(0),
})

local function phabricator_differential_action(payload)
  for _, tx in ipairs(payload.transactions or {}) do
    local tx_type = phabricator_transaction_type(tx)
    if tx_type == "core:create" or tx_type == "create" then
      return "opened"
    elseif tx_type == "status" then
      local value = phabricator_transaction_new_value(tx)
      if value == "needs-review" or value == "needs-revision" or value == "open" then
        return "reopened"
      end
      return "closed"
    elseif tx_type == "update" or tx_type == "diff" or tx_type == "differential:update" then
      return "synchronize"
    end
  end
  return "edited"
end

local function phabricator_differential_revision_payload(payload)
  payload = payload or {}
  if type(payload.revision) == "table" then
    return payload.revision
  end
  if type(payload.differentialRevision) == "table" then
    return payload.differentialRevision
  end
  return payload.object or {}
end

local function phabricator_ref_name(value)
  local ref = phabricator_branch_name(value, "master")
  if ref:match("^refs/") then
    return ref
  end
  return "refs/heads/" .. ref
end

local function phabricator_git_identity(value, fallback_phid)
  if type(value) == "table" then
    return {
      name = value.name or value.realName or value.username or fallback_phid or "",
      email = value.email or value.emailAddress or "",
      username = value.username or value.login or fallback_phid or "",
    }
  end
  return {
    name = value or fallback_phid or "",
    email = "",
    username = fallback_phid or "",
  }
end

local function phabricator_commit_fields(commit)
  return (commit or {}).fields or {}
end

local function phabricator_commit_identifier(commit)
  local f = phabricator_commit_fields(commit)
  return f.identifier or commit.identifier or commit.name or ""
end

local translate_phabricator_commit = make_translator({
  id = computed(phabricator_commit_identifier),
  message = computed(function(commit)
    local f = phabricator_commit_fields(commit)
    return f.message or f.commitMessage or f.summary or commit.message or ""
  end),
  timestamp = computed(function(commit)
    local f = phabricator_commit_fields(commit)
    return ts(f.epoch or f.dateCreated or commit.epoch or commit.dateCreated)
  end),
  url = computed(function(commit)
    local identifier = phabricator_commit_identifier(commit)
    return commit.uri or (identifier ~= "" and (config.base_url .. "/r" .. identifier) or "")
  end),
  author = computed(function(commit)
    local f = phabricator_commit_fields(commit)
    return phabricator_git_identity(
      f.author or f.authorName or commit.author,
      f.authorPHID or commit.authorPHID
    )
  end),
  committer = computed(function(commit)
    local f = phabricator_commit_fields(commit)
    local author_phid = f.authorPHID or commit.authorPHID
    local committer_phid = f.committerPHID or commit.committerPHID or author_phid
    return phabricator_git_identity(
      f.committer or f.committerName or commit.committer or f.author or f.authorName,
      committer_phid
    )
  end),
  added = computed(function(commit)
    return phabricator_commit_fields(commit).added or commit.added or {}
  end),
  removed = computed(function(commit)
    return phabricator_commit_fields(commit).removed or commit.removed or {}
  end),
  modified = computed(function(commit)
    return phabricator_commit_fields(commit).modified or commit.modified or {}
  end),
})

local function phabricator_commit_payload(payload)
  payload = payload or {}
  if type(payload.commit) == "table" then
    return payload.commit
  end
  return payload.object or {}
end

local function phabricator_commit_ref(payload, commit)
  payload = payload or {}
  commit = commit or {}
  local f = commit.fields or {}
  return phabricator_ref_name(payload.ref or f.branch or f.ref or payload.branch)
end

local function phabricator_repository_action(payload)
  for _, tx in ipairs(payload.transactions or {}) do
    local tx_type = phabricator_transaction_type(tx)
    if tx_type == "core:create" or tx_type == "create" then
      return "created"
    elseif tx_type == "delete" or tx_type == "destroy" or tx_type == "repository:delete" then
      return "deleted"
    elseif tx_type == "name" or tx_type == "shortname" or tx_type == "callsign" then
      return "renamed"
    end
  end
  return payload.action_name or payload.repository_action or "edited"
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
local function harbormaster_build_fields(b)
  return (b or {}).fields or {}
end

local function harbormaster_build_status(b)
  local hs = harbormaster_build_fields(b).buildStatus or {}
  return hs.value or "building"
end

local function harbormaster_check_status(raw_status)
  if raw_status == "passed" then
    return "completed", "success"
  elseif
    raw_status == "failed"
    or raw_status == "aborted"
    or raw_status == "unexpected"
    or raw_status == "deadlocked"
  then
    return "completed", "failure"
  end
  return "in_progress", nil
end

local function harbormaster_build_name(b)
  local plan = harbormaster_build_fields(b).buildPlan or {}
  return plan.name or ("build/" .. tostring((b or {}).id or 0))
end

local translate_harbormaster_build_output = make_translator({
  title = computed(function(b)
    return harbormaster_build_name(b)
  end),
  summary = computed(harbormaster_build_status),
  text = const(""),
  annotations_count = const(0),
  annotations_url = const(""),
})

local translate_harbormaster_build = make_translator({
  id = field("id", { default = 0 }),
  node_id = field("phid", { default = "" }),
  head_sha = computed(function(_b, ref)
    return ref
  end),
  name = computed(harbormaster_build_name),
  status = computed(function(b)
    local status = harbormaster_check_status(harbormaster_build_status(b))
    return status
  end),
  conclusion = computed(function(b)
    local _, conclusion = harbormaster_check_status(harbormaster_build_status(b))
    return conclusion
  end),
  started_at = computed(function(b)
    return ts(harbormaster_build_fields(b).dateCreated)
  end),
  completed_at = computed(function(b)
    local status = harbormaster_check_status(harbormaster_build_status(b))
    return status == "completed" and ts(harbormaster_build_fields(b).dateModified) or nil
  end),
  output = computed(function(b)
    return translate_harbormaster_build_output(b)
  end),
  url = const(""),
  html_url = computed(function(b)
    return config.base_url .. "/B" .. tostring(b.id or "")
  end),
  details_url = const(""),
})

local PHABRICATOR_HARBORMASTER_FAILURE_STATUSES = {
  failed = "failure",
  unexpected = "failure",
  deadlocked = "failure",
  aborted = "cancelled",
}

local function phabricator_harbormaster_status_value(object)
  local f = object and object.fields or {}
  local status = f.buildStatus or f.status or object and object.status or {}
  if type(status) == "table" then
    return status.value or status.name or ""
  end
  return status or ""
end

local function phabricator_harbormaster_run_state(object)
  local raw_status = phabricator_harbormaster_status_value(object)
  if raw_status == "passed" then
    return "completed", "completed", "success"
  end
  local failure = PHABRICATOR_HARBORMASTER_FAILURE_STATUSES[raw_status]
  if failure then
    return "completed", "completed", failure
  end
  if raw_status == "queued" or raw_status == "pending" or raw_status == "waiting" then
    return "requested", "queued", nil
  end
  return "in_progress", "in_progress", nil
end

local function phabricator_harbormaster_job_state(object)
  local raw_status = phabricator_harbormaster_status_value(object)
  if raw_status == "passed" then
    return "completed", "completed", "success"
  end
  local failure = PHABRICATOR_HARBORMASTER_FAILURE_STATUSES[raw_status]
  if failure then
    return "completed", "completed", failure
  end
  if raw_status == "paused" or raw_status == "waiting" then
    return "waiting", "waiting", nil
  end
  if raw_status == "queued" or raw_status == "pending" then
    return "queued", "queued", nil
  end
  return "in_progress", "in_progress", nil
end

local function phabricator_harbormaster_name(object)
  local f = object and object.fields or {}
  local plan = f.buildPlan or object and object.buildPlan or {}
  return f.name
    or f.buildableName
    or f.buildName
    or plan.name
    or object and (object.name or object.title)
    or ("Harbormaster " .. tostring(object and object.id or "build"))
end

local function phabricator_harbormaster_ref(payload, object)
  local f = object and object.fields or {}
  local commit = payload and payload.commit or {}
  local commit_fields = commit.fields or {}
  return f.commitIdentifier
    or f.commit
    or f.commitIdentifierRaw
    or payload and payload.head_sha
    or commit_fields.identifier
    or commit.identifier
    or ""
end

local function phabricator_harbormaster_branch(payload, object)
  local f = object and object.fields or {}
  return phabricator_branch_name(
    payload and (payload.branch or payload.ref) or f.branch or f.repositoryBranch,
    ""
  )
end

local function phabricator_harbormaster_timestamp(payload, object)
  local f = object and object.fields or {}
  local action = payload and payload.action or {}
  return ts(f.dateModified or f.dateCreated or action.epoch)
end

local translate_harbormaster_workflow = make_translator({
  id = computed(function(object)
    local f = object.fields or {}
    return f.buildPlanID or 0
  end),
  name = computed(phabricator_harbormaster_name),
  path = const(""),
  state = const("active"),
  url = const(""),
  html_url = computed(function(object)
    return object.uri or (config.base_url .. "/B" .. tostring(object.id or ""))
  end),
  badge_url = const(""),
  created_at = computed(function(object)
    local f = object.fields or {}
    return ts(f.dateCreated)
  end),
  updated_at = computed(function(object, payload)
    return phabricator_harbormaster_timestamp(payload, object)
  end),
})

local translate_harbormaster_workflow_run_payload = make_translator({
  id = field("id", { default = 0 }),
  name = computed(phabricator_harbormaster_name),
  head_branch = computed(function(object, payload)
    return phabricator_harbormaster_branch(payload, object)
  end),
  head_sha = computed(function(object, payload)
    return phabricator_harbormaster_ref(payload, object)
  end),
  run_number = field("id", { default = 0 }),
  event = const("push"),
  display_title = computed(phabricator_harbormaster_name),
  status = computed(function(object)
    local _, status = phabricator_harbormaster_run_state(object)
    return status
  end),
  conclusion = computed(function(object)
    local _, _, conclusion = phabricator_harbormaster_run_state(object)
    return conclusion
  end),
  workflow_id = computed(function(object)
    local f = object.fields or {}
    return f.buildPlanID or 0
  end),
  url = const(""),
  html_url = computed(function(object)
    return object and (object.uri or (config.base_url .. "/B" .. tostring(object.id or ""))) or ""
  end),
  pull_requests = computed(function()
    return {}
  end),
  created_at = computed(function(object)
    local f = object.fields or {}
    return ts(f.dateCreated)
  end),
  updated_at = computed(function(object, payload)
    return phabricator_harbormaster_timestamp(payload, object)
  end),
  run_attempt = const(1),
  referenced_workflows = computed(function()
    return {}
  end),
  actor = computed(function(_object, payload)
    return phabricator_sender(payload)
  end),
  triggering_actor = computed(function(_object, payload)
    return phabricator_sender(payload)
  end),
})

local function harbormaster_workflow_run(object, payload)
  local action, status, conclusion = phabricator_harbormaster_run_state(object)
  local run = translate_harbormaster_workflow_run_payload(object, payload)
  run.status = status
  run.conclusion = conclusion
  return action, run
end

local translate_harbormaster_workflow_job_payload = make_translator({
  id = field("id", { default = 0 }),
  run_id = computed(function(object)
    local f = object.fields or {}
    return f.buildID or 0
  end),
  run_url = const(""),
  run_attempt = const(1),
  name = computed(phabricator_harbormaster_name),
  head_sha = computed(function(object, payload)
    return phabricator_harbormaster_ref(payload, object)
  end),
  url = const(""),
  html_url = computed(function(object)
    return object and (object.uri or (config.base_url .. "/B" .. tostring(object.id or ""))) or ""
  end),
  status = computed(function(object)
    local _, status = phabricator_harbormaster_job_state(object)
    return status
  end),
  conclusion = computed(function(object)
    local _, _, conclusion = phabricator_harbormaster_job_state(object)
    return conclusion
  end),
  started_at = computed(function(object)
    local f = object.fields or {}
    return ts(f.dateStarted or f.dateCreated)
  end),
  completed_at = computed(function(object)
    local _, status = phabricator_harbormaster_job_state(object)
    local f = object.fields or {}
    return status == "completed" and ts(f.dateCompleted or f.dateModified) or nil
  end),
  steps = computed(function()
    return {}
  end),
  labels = computed(function()
    return {}
  end),
  runner_id = const(nil),
  runner_name = const(""),
})

local function harbormaster_workflow_job(object, payload)
  local action, status, conclusion = phabricator_harbormaster_job_state(object)
  local job = translate_harbormaster_workflow_job_payload(object, payload)
  job.status = status
  job.conclusion = conclusion
  return action, job
end

local PHABRICATOR_NATIVE_TO_GITHUB_EVENT = {
  TASK = "issues",
  DREV = "pull_request",
  DIFF = "pull_request",
  CMIT = "push",
  REPO = "repository",
  HMBB = "workflow_run",
  HMBD = "workflow_run",
  HMBT = "workflow_job",
}

local PHABRICATOR_WEBHOOK_OBJECT_TYPES = {
  "TASK",
  "DREV",
  "DIFF",
  "CMIT",
  "REPO",
  "HMBB",
  "HMBD",
  "HMBT",
}

local function phabricator_webhook_unimplemented(object_type)
  local github_event = PHABRICATOR_NATIVE_TO_GITHUB_EVENT[object_type] or object_type
  return function(_payload)
    return nil, "Phabricator webhook event not implemented: " .. github_event
  end
end

local function phabricator_normalized_payload_without_envelope_fields(data)
  local payload = {}
  for k, v in pairs(data or {}) do
    if k ~= "sender" and k ~= "repository" then
      payload[k] = v
    end
  end
  return payload
end

local function translate_phabricator_normalized_webhook(internal_event, fields)
  local data = internal_event.data or {}
  fields = fields or {}
  return make_normalized_webhook_envelope(internal_event, {
    id = fields.id,
    type = fields.type
      or normalized_webhook_event_type(internal_event.event, internal_event.action),
    occurred_at = fields.occurred_at,
    actor = fields.actor or data.sender,
    repository = fields.repository or data.repository,
    payload = fields.payload or phabricator_normalized_payload_without_envelope_fields(data),
  })
end

local function translate_phabricator_github_webhook(internal_event, fields)
  return github_webhook_payload(internal_event, fields)
end

local b = make_backend_builder()
b:rest("get_root", function()
  proxy_health_check(pcall(Fetch, config.base_url .. "/api/conduit.ping"))
end)

-- Inbound webhook dispatch --------------------------------------------------
-- Phabricator sends a generic webhook envelope with object.type (or an object
-- PHID whose prefix is the same type constant).  Register the native object
-- families up front so the receiver can distinguish known Phabricator webhook
-- families from truly unknown payloads while the family translators land.

for _, object_type in ipairs(PHABRICATOR_WEBHOOK_OBJECT_TYPES) do
  b:webhook(object_type, phabricator_webhook_unimplemented(object_type))
end

b:webhook_translator("issues", translate_phabricator_normalized_webhook)
b:webhook_translator("issue_comment", translate_phabricator_normalized_webhook)
b:webhook_translator("pull_request", translate_phabricator_normalized_webhook)
b:webhook_translator("push", translate_phabricator_normalized_webhook)
b:webhook_translator("repository", translate_phabricator_normalized_webhook)
b:webhook_translator("workflow_run", translate_phabricator_normalized_webhook)
b:webhook_translator("workflow_job", translate_phabricator_normalized_webhook)
b:webhook_github_translator("issues", translate_phabricator_github_webhook)
b:webhook_github_translator("issue_comment", translate_phabricator_github_webhook)
b:webhook_github_translator("pull_request", translate_phabricator_github_webhook)
b:webhook_github_translator("push", translate_phabricator_github_webhook)
b:webhook_github_translator("repository", translate_phabricator_github_webhook)
b:webhook_github_translator("workflow_run", translate_phabricator_github_webhook)
b:webhook_github_translator("workflow_job", translate_phabricator_github_webhook)

b:webhook("TASK", function(payload)
  payload = payload or {}
  local task = payload.object or {}
  local comment_tx = phabricator_task_comment_transaction(payload)
  if comment_tx then
    return make_internal_event({
      event = "issue_comment",
      action = "created",
      provider = "phabricator",
      raw = payload,
      data = {
        action = "created",
        issue = translate_task(task),
        comment = translate_phabricator_comment(comment_tx),
        repository = phabricator_repository(payload),
        sender = phabricator_sender(payload, comment_tx),
      },
      timestamp = phabricator_task_timestamp(payload, comment_tx),
    })
  end

  local action = phabricator_task_action(payload)
  return make_internal_event({
    event = "issues",
    action = action,
    provider = "phabricator",
    raw = payload,
    data = {
      action = action,
      issue = translate_task(task),
      repository = phabricator_repository(payload),
      sender = phabricator_sender(payload),
    },
    timestamp = phabricator_task_timestamp(payload),
  })
end)

b:webhook("DREV", function(payload)
  payload = payload or {}
  local action = phabricator_differential_action(payload)
  local pull_request = translate_differential_revision(payload.object, payload)
  return make_internal_event({
    event = "pull_request",
    action = action,
    provider = "phabricator",
    raw = payload,
    data = {
      action = action,
      number = pull_request.number,
      pull_request = pull_request,
      repository = phabricator_repository(payload),
      sender = phabricator_sender(payload),
    },
    timestamp = phabricator_task_timestamp(payload),
  })
end)

b:webhook("DIFF", function(payload)
  payload = payload or {}
  local revision = phabricator_differential_revision_payload(payload)
  local pull_request = translate_differential_revision(revision, payload)
  return make_internal_event({
    event = "pull_request",
    action = "synchronize",
    provider = "phabricator",
    raw = payload,
    data = {
      action = "synchronize",
      number = pull_request.number,
      pull_request = pull_request,
      repository = phabricator_repository(payload),
      sender = phabricator_sender(payload),
    },
    timestamp = phabricator_task_timestamp(payload),
  })
end)

b:webhook("CMIT", function(payload)
  payload = payload or {}
  local commit_source = phabricator_commit_payload(payload)
  local commit = translate_phabricator_commit(commit_source)
  local repository = phabricator_event_repository(payload)
  return make_internal_event({
    event = "push",
    action = "",
    provider = "phabricator",
    raw = payload,
    data = {
      ref = phabricator_commit_ref(payload, commit_source),
      before = payload.before or "",
      after = commit.id,
      created = false,
      deleted = false,
      forced = false,
      compare = payload.compare or payload.compare_url or "",
      commits = { commit },
      head_commit = commit,
      pusher = {
        name = commit.committer.name or commit.author.name or "",
        email = commit.committer.email or commit.author.email or "",
      },
      repository = repository,
      sender = phabricator_sender(payload),
    },
    timestamp = commit.timestamp,
  })
end)

b:webhook("REPO", function(payload)
  payload = payload or {}
  local action = phabricator_repository_action(payload)
  local repository = translate_phabricator_repository(payload.object or payload.repository or {})
  local data = {
    action = action,
    repository = repository,
    sender = phabricator_sender(payload),
  }
  if action == "renamed" then
    for _, tx in ipairs(payload.transactions or {}) do
      local tx_type = phabricator_transaction_type(tx)
      if tx_type == "name" or tx_type == "shortname" or tx_type == "callsign" then
        data.changes = {
          repository = { name = { from = tx.oldValue or tx.old or "" } },
        }
        break
      end
    end
  end
  return make_internal_event({
    event = "repository",
    action = action,
    provider = "phabricator",
    raw = payload,
    data = data,
    timestamp = phabricator_task_timestamp(payload),
  })
end)

local function phabricator_harbormaster_workflow_run_event(payload)
  payload = payload or {}
  local object = payload.object or {}
  local action, workflow_run = harbormaster_workflow_run(object, payload)
  return make_internal_event({
    event = "workflow_run",
    action = action,
    provider = "phabricator",
    raw = payload,
    data = {
      action = action,
      workflow_run = workflow_run,
      workflow = translate_harbormaster_workflow(object, payload),
      repository = phabricator_event_repository(payload),
      sender = phabricator_sender(payload),
    },
    timestamp = phabricator_harbormaster_timestamp(payload, object),
  })
end

b:webhook("HMBB", phabricator_harbormaster_workflow_run_event)
b:webhook("HMBD", phabricator_harbormaster_workflow_run_event)

b:webhook("HMBT", function(payload)
  payload = payload or {}
  local object = payload.object or {}
  local action, workflow_job = harbormaster_workflow_job(object, payload)
  return make_internal_event({
    event = "workflow_job",
    action = action,
    provider = "phabricator",
    raw = payload,
    data = {
      action = action,
      workflow_job = workflow_job,
      repository = phabricator_event_repository(payload),
      sender = phabricator_sender(payload),
    },
    timestamp = phabricator_harbormaster_timestamp(payload, object),
  })
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
