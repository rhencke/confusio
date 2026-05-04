-- AWS CodeCommit backend handler overrides.
-- Uses AWS CodeCommit REST API v1.
-- CodeCommit has no owner/org concept; the GitHub {owner} segment must always
-- be "codecommit". All repos are scoped to an AWS account.
if config.base_url == "" then
  config.base_url = "https://codecommit.us-east-1.amazonaws.com"
end

local base = function()
  return config.base_url .. "/v1"
end

local auth = function()
  return make_fetch_opts("basic")
end
local fetch_json = make_backend_transport("basic").fetch_json

local ZERO_SHA = "0000000000000000000000000000000000000000"

local function codecommit_timestamp(value)
  return value and tostring(value) or nil
end

local translate_repo_owner = make_translator({
  login = field("accountId", { default = "" }),
  id = const(0),
  node_id = const(""),
  avatar_url = const(""),
  url = const(""),
  html_url = const(""),
  type = const("Organization"),
})

-- Translate a CodeCommit repositoryMetadata (or summary) object to GitHub format.
local translate_repo = make_translator({
  id = const(0),
  node_id = field("repositoryId", { default = "" }),
  name = field("repositoryName", { default = "" }),
  full_name = field("repositoryName", { default = "" }),
  private = const(true),
  owner = computed(function(r)
    return translate_repo_owner(r)
  end),
  html_url = field("cloneUrlHttp", { default = "" }),
  description = "repositoryDescription",
  fork = const(false),
  url = const(""),
  clone_url = field("cloneUrlHttp", { default = "" }),
  homepage = const(""),
  size = const(0),
  stargazers_count = const(0),
  watchers_count = const(0),
  language = const(nil),
  has_issues = const(false),
  has_wiki = const(false),
  forks_count = const(0),
  archived = const(false),
  disabled = const(false),
  open_issues_count = const(0),
  default_branch = field("defaultBranch", { default = "main" }),
  visibility = const("private"),
  forks = const(0),
  open_issues = const(0),
  watchers = const(0),
  created_at = field("creationDate", { transform = codecommit_timestamp }),
  updated_at = field("lastModifiedDate", { transform = codecommit_timestamp }),
  pushed_at = field("lastModifiedDate", { transform = codecommit_timestamp }),
})

local function codecommit_user_from_arn(arn)
  local login = tostring(arn or ""):match(":user/(.+)$")
    or tostring(arn or ""):match(":role/(.+)$")
    or tostring(arn or ""):match(":federated%-user/(.+)$")
    or tostring(arn or ""):match(":assumed%-role/[^/]+/(.+)$")
    or ""
  return {
    login = login,
    id = 0,
    node_id = "",
    avatar_url = "",
    url = "",
    html_url = "",
    type = "User",
    site_admin = false,
  }
end

local function codecommit_repository(name, account_id, region)
  name = name or ""
  return translate_repo({
    repositoryId = "",
    repositoryName = name,
    repositoryDescription = nil,
    defaultBranch = "main",
    cloneUrlHttp = region ~= ""
        and ("https://git-codecommit." .. region .. ".amazonaws.com/v1/repos/" .. name)
      or "",
    accountId = account_id or "",
  })
end

local function codecommit_eventbridge_ref(detail)
  detail = detail or {}
  local name = detail.referenceFullName or detail.referenceName or ""
  local ref_type = detail.referenceType or "branch"
  if name:match("^refs/") then
    return name
  end
  if ref_type == "tag" then
    return "refs/tags/" .. name
  end
  return "refs/heads/" .. name
end

local function codecommit_ref_type(ref)
  if tostring(ref or ""):match("^refs/tags/") then
    return "tag"
  end
  return "branch"
end

local function codecommit_ref_name(ref)
  return tostring(ref or ""):match("^refs/[^/]+/(.+)$") or tostring(ref or "")
end

local function codecommit_bool(value)
  if type(value) == "boolean" then
    return value
  end
  value = tostring(value or ""):lower()
  return value == "true" or value == "yes" or value == "1"
end

local function codecommit_reference_action(raw_action, before, after)
  if raw_action == "referenceCreated" or before == ZERO_SHA then
    return "create"
  end
  if raw_action == "referenceDeleted" or after == ZERO_SHA then
    return "delete"
  end
  return "push"
end

local function codecommit_supported_reference_event(raw_action)
  return raw_action == "referenceCreated"
    or raw_action == "referenceUpdated"
    or raw_action == "referenceDeleted"
end

local CODECOMMIT_PR_ACTIONS = {
  pullRequestCreated = "opened",
  pullRequestSourceBranchUpdated = "synchronize",
}

local CODECOMMIT_COMMENT_ACTIONS = {
  commentOnCommitCreated = "created",
  commentOnCommitUpdated = "edited",
  commentOnPullRequestCreated = "created",
  commentOnPullRequestUpdated = "edited",
}

local CODECOMMIT_APPROVAL_RULE_ACTIONS = {
  pullRequestApprovalRuleCreated = "created",
  pullRequestApprovalRuleUpdated = "edited",
  pullRequestApprovalRuleDeleted = "deleted",
  approvalRuleTemplateCreated = "created",
  approvalRuleTemplateUpdated = "edited",
  approvalRuleTemplateDeleted = "deleted",
}

local function codecommit_pull_request_action(detail)
  local raw_action = detail.event or ""
  if raw_action == "pullRequestStatusChanged" then
    if detail.pullRequestStatus == "Closed" then
      return "closed"
    elseif detail.pullRequestStatus == "Open" then
      return "reopened"
    end
  elseif raw_action == "pullRequestMergeStatusUpdated" then
    return codecommit_bool(detail.isMerged) and "closed" or "edited"
  end
  return CODECOMMIT_PR_ACTIONS[raw_action] or "unknown"
end

local function codecommit_supported_pull_request_event(raw_action)
  return CODECOMMIT_PR_ACTIONS[raw_action] ~= nil
    or raw_action == "pullRequestStatusChanged"
    or raw_action == "pullRequestMergeStatusUpdated"
end

local function codecommit_is_approval_event(raw_action)
  return raw_action == "pullRequestApprovalStateChanged"
    or raw_action == "pullRequestApprovalRuleOverridden"
    or CODECOMMIT_APPROVAL_RULE_ACTIONS[raw_action] ~= nil
end

local function codecommit_is_approval_template_association_event(raw_action)
  return raw_action == "approvalRuleTemplateAssociatedWithRepository"
    or raw_action == "approvalRuleTemplateDisassociatedFromRepository"
    or raw_action == "batchAssociateApprovalRuleTemplateWithRepositories"
    or raw_action == "batchDisassociateApprovalRuleTemplateFromRepositories"
end

local CODECOMMIT_ACTIONLESS_EVENTS = {
  create = true,
  delete = true,
  push = true,
}

local function codecommit_normalized_payload_without_envelope_fields(data)
  local payload = {}
  for k, v in pairs(data or {}) do
    if k ~= "sender" and k ~= "repository" then
      payload[k] = v
    end
  end
  return payload
end

local function codecommit_normalized_event_type(internal_event, fields)
  if fields and fields.type then
    return fields.type
  end
  if CODECOMMIT_ACTIONLESS_EVENTS[internal_event.event] then
    return normalized_webhook_event_type(internal_event.event, "")
  end
  return normalized_webhook_event_type(internal_event.event, internal_event.action)
end

local function codecommit_resource_repository_name(payload, detail)
  local repositories = type(detail.repositories) == "table" and detail.repositories or {}
  local name = next(repositories)
  if name then
    return name
  end
  local resource = (payload.resources or {})[1] or ""
  return resource:match(":([^:]+)$") or ""
end

local function codecommit_repository_from_detail(payload, detail)
  local repo_names = detail.repositoryNames or {}
  local repo_name = repo_names[1]
    or detail.repositoryName
    or codecommit_resource_repository_name(payload, detail)
  return codecommit_repository(repo_name or "", payload.account or "", payload.region or "")
end

local function codecommit_pr_ref(ref, commit, repository)
  local short = codecommit_ref_name(ref)
  return {
    label = short,
    ref = short,
    sha = commit or "",
    repo = repository,
  }
end

local function codecommit_pr_url(payload, repository, pull_request_id)
  if payload.region == "" or repository.name == "" or not pull_request_id then
    return ""
  end
  return "https://"
    .. payload.region
    .. ".console.aws.amazon.com/codesuite/codecommit/repositories/"
    .. repository.name
    .. "/pull-requests/"
    .. pull_request_id
    .. "?region="
    .. payload.region
end

local function codecommit_pr_from_comment_detail(payload, detail, repository, sender)
  local pull_request_id = tonumber(detail.pullRequestId) or 0
  return {
    id = pull_request_id,
    node_id = detail.revisionId or "",
    number = pull_request_id,
    state = "open",
    title = "",
    body = nil,
    user = sender,
    head = codecommit_pr_ref("", detail.afterCommitId, repository),
    base = codecommit_pr_ref("", detail.beforeCommitId, repository),
    created_at = payload.time,
    updated_at = payload.time,
    merged = false,
    html_url = codecommit_pr_url(
      payload,
      repository,
      pull_request_id ~= 0 and pull_request_id or nil
    ),
    url = "",
  }
end

local function codecommit_pr_from_detail(payload, detail, repository, sender)
  local merged = codecommit_bool(detail.isMerged)
  local closed = detail.pullRequestStatus == "Closed"
  return {
    id = tonumber(detail.pullRequestId) or 0,
    node_id = detail.revisionId or "",
    number = tonumber(detail.pullRequestId) or 0,
    state = closed and "closed" or "open",
    title = detail.title or "",
    body = detail.description,
    user = codecommit_user_from_arn(detail.author) or sender,
    head = codecommit_pr_ref(detail.sourceReference, detail.sourceCommit, repository),
    base = codecommit_pr_ref(detail.destinationReference, detail.destinationCommit, repository),
    created_at = detail.creationDate,
    updated_at = detail.lastModifiedDate or payload.time,
    closed_at = closed and (detail.lastModifiedDate or payload.time) or nil,
    merged_at = merged and (detail.lastModifiedDate or payload.time) or nil,
    merge_commit_sha = merged and detail.destinationCommit or nil,
    merged = merged,
    mergeable = detail.mergeOption ~= nil and not merged or nil,
    mergeable_state = detail.mergeOption or "unknown",
    html_url = codecommit_pr_url(payload, repository, detail.pullRequestId),
    url = "",
  }
end

local function codecommit_console_comment_url(payload, repository, detail)
  if payload.region == "" or repository.name == "" then
    return ""
  end
  local console_base = "https://" .. payload.region .. ".console.aws.amazon.com"
  if detail.pullRequestId and detail.pullRequestId ~= "" then
    return console_base
      .. "/codesuite/codecommit/repositories/"
      .. repository.name
      .. "/pull-requests/"
      .. detail.pullRequestId
      .. "/activity#"
      .. (detail.commentId or "")
      .. "?region="
      .. payload.region
  end
  return console_base
    .. "/codesuite/codecommit/repositories/"
    .. repository.name
    .. "/commit/"
    .. (detail.afterCommitId or detail.beforeCommitId or "")
    .. "?region="
    .. payload.region
end

local function codecommit_comment_from_detail(payload, detail, repository, sender)
  local html_url = codecommit_console_comment_url(payload, repository, detail)
  return {
    id = tonumber(detail.commentId) or 0,
    node_id = detail.commentId or "",
    url = "",
    html_url = html_url,
    body = detail.content or detail.commentContent or detail.notificationBody or "",
    path = detail.filePath,
    position = tonumber(detail.filePosition or ""),
    line = tonumber(detail.fileLineNumber or ""),
    commit_id = detail.afterCommitId or detail.commitId or detail.beforeCommitId or "",
    original_commit_id = detail.beforeCommitId or detail.commitId or "",
    user = sender,
    created_at = payload.time,
    updated_at = payload.time,
    author_association = "NONE",
  }
end

local function codecommit_review_state(approval_status)
  if approval_status == "APPROVE" then
    return "submitted", "approved"
  end
  if approval_status == "REVOKE" then
    return "dismissed", "dismissed"
  end
  return "unknown", "commented"
end

local function codecommit_review_from_detail(payload, detail, sender)
  local action, state = codecommit_review_state(detail.approvalStatus)
  return {
    id = 0,
    node_id = (detail.pullRequestId or "") .. ":" .. (detail.callerUserArn or ""),
    body = detail.notificationBody,
    state = state,
    html_url = codecommit_pr_url(
      payload,
      codecommit_repository_from_detail(payload, detail),
      detail.pullRequestId
    ),
    user = sender,
    submitted_at = payload.time or detail.lastModifiedDate or "",
    commit_id = detail.destinationCommit or detail.sourceCommit or "",
  },
    action
end

local function codecommit_rule_from_detail(payload, detail, repository)
  local name = detail.approvalRuleName or detail.approvalRuleTemplateName or ""
  local id = detail.approvalRuleId or detail.approvalRuleTemplateId or ""
  local content_sha = detail.approvalRuleContentSha256
    or detail.approvalRuleTemplateContentSha256
    or ""
  return {
    id = 0,
    node_id = id,
    name = name,
    pattern = codecommit_ref_name(detail.destinationReference or "*"),
    created_at = detail.creationDate or payload.time or "",
    updated_at = detail.lastModifiedDate or payload.time or "",
    required_approving_review_count = 0,
    required_status_checks = {},
    admin_enforced = false,
    allows_deletions = false,
    allows_force_pushes = false,
    blocks_creations = false,
    dismisses_stale_reviews = false,
    is_admin_enforced = false,
    repository_id = repository.id or 0,
    codecommit = {
      content_sha256 = content_sha,
      pull_request_id = detail.pullRequestId,
      repository_names = detail.repositoryNames,
      template_id = detail.approvalRuleTemplateId,
      template_name = detail.approvalRuleTemplateName,
    },
  }
end

local function codecommit_pull_request_from_eventbridge(payload)
  local detail = payload.detail or {}
  if not codecommit_supported_pull_request_event(detail.event) then
    return nil, "Unsupported CodeCommit pull request event"
  end
  local action = codecommit_pull_request_action(detail)
  local repo_names = detail.repositoryNames or {}
  local repo_name = repo_names[1] or detail.repositoryName or ""
  local repository = codecommit_repository(repo_name, payload.account or "", payload.region or "")
  local sender = codecommit_user_from_arn(detail.callerUserArn or detail.author)
  return make_internal_event({
    event = "pull_request",
    action = action,
    raw_action = action == "unknown" and detail.event or nil,
    provider = "codecommit",
    raw = payload,
    data = {
      action = action,
      number = tonumber(detail.pullRequestId) or 0,
      pull_request = codecommit_pr_from_detail(payload, detail, repository, sender),
      repository = repository,
      sender = sender,
    },
    timestamp = payload.time or detail.lastModifiedDate or "",
  })
end

local function codecommit_approval_from_eventbridge(payload)
  local detail = payload.detail or {}
  local raw_action = detail.event or ""
  if codecommit_is_approval_template_association_event(raw_action) then
    return nil,
      "CodeCommit approval rule template association events have no GitHub webhook equivalent"
  end
  if raw_action == "pullRequestApprovalRuleOverridden" then
    return nil, "CodeCommit approval rule override events have no GitHub webhook equivalent"
  end

  local repository = codecommit_repository_from_detail(payload, detail)
  local sender = codecommit_user_from_arn(detail.callerUserArn or detail.author)
  if raw_action == "pullRequestApprovalStateChanged" then
    local review, action = codecommit_review_from_detail(payload, detail, sender)
    return make_internal_event({
      event = "pull_request_review",
      action = action,
      raw_action = action == "unknown" and detail.approvalStatus or nil,
      provider = "codecommit",
      raw = payload,
      data = {
        action = action,
        review = review,
        pull_request = codecommit_pr_from_detail(payload, detail, repository, sender),
        repository = repository,
        sender = sender,
      },
      timestamp = payload.time or detail.lastModifiedDate or "",
    })
  end

  local action = CODECOMMIT_APPROVAL_RULE_ACTIONS[raw_action]
  if action then
    local data = {
      action = action,
      rule = codecommit_rule_from_detail(payload, detail, repository),
      repository = repository,
      sender = sender,
    }
    if action == "edited" then
      data.changes = {
        codecommit_content_sha256 = {
          from = detail.oldApprovalRuleContentSha256
            or detail.oldApprovalRuleTemplateContentSha256
            or "",
        },
      }
    end
    return make_internal_event({
      event = "branch_protection_rule",
      action = action,
      provider = "codecommit",
      raw = payload,
      data = data,
      timestamp = payload.time or detail.lastModifiedDate or "",
    })
  end
  return nil, "Unsupported CodeCommit approval event"
end

local function codecommit_comment_from_eventbridge(payload)
  local detail = payload.detail or {}
  local action = CODECOMMIT_COMMENT_ACTIONS[detail.event]
  if not action then
    if
      detail.event == "commentReactionCreated"
      or detail.event == "commentReactionUpdated"
      or payload["detail-type"] == "CodeCommit Comment Reaction Change"
    then
      return nil, "CodeCommit comment reaction events have no GitHub webhook equivalent"
    end
    return nil, "Unsupported CodeCommit comment event"
  end

  local repository =
    codecommit_repository(detail.repositoryName or "", payload.account or "", payload.region or "")
  local sender = codecommit_user_from_arn(detail.callerUserArn)
  local comment = codecommit_comment_from_detail(payload, detail, repository, sender)
  local event = detail.pullRequestId and "pull_request_review_comment" or "commit_comment"
  local data = {
    action = action,
    comment = comment,
    repository = repository,
    sender = sender,
  }
  if event == "pull_request_review_comment" then
    data.pull_request = codecommit_pr_from_comment_detail(payload, detail, repository, sender)
  end
  return make_internal_event({
    event = event,
    action = action,
    provider = "codecommit",
    raw = payload,
    data = data,
    timestamp = payload.time or "",
  })
end

local function translate_codecommit_normalized_webhook(internal_event, fields)
  local data = internal_event.data or {}
  fields = fields or {}
  return make_normalized_webhook_envelope(internal_event, {
    id = fields.id,
    type = codecommit_normalized_event_type(internal_event, fields),
    occurred_at = fields.occurred_at,
    actor = fields.actor or data.sender,
    repository = fields.repository or data.repository,
    payload = fields.payload or codecommit_normalized_payload_without_envelope_fields(data),
  })
end

local function translate_codecommit_github_webhook(internal_event, fields)
  return github_webhook_payload(internal_event, fields)
end

local function decode_json_table(value)
  if type(value) ~= "string" or value == "" then
    return nil
  end
  local ok, decoded = pcall(DecodeJson, value)
  if ok and type(decoded) == "table" then
    return decoded
  end
  return nil
end

local function codecommit_record_nested_payload(record)
  record = record or {}
  local sns = record.Sns or record.sns
  if type(sns) == "table" then
    return decode_json_table(sns.Message or sns.message)
  end
  return nil
end

local function decode_codecommit_message(payload, depth)
  if type(payload) ~= "table" then
    return {}
  end
  depth = (depth or 0) + 1
  if depth > 8 then
    return payload
  end
  if payload.Type == "Notification" then
    local nested = decode_json_table(payload.Message)
    if nested then
      return decode_codecommit_message(nested, depth)
    end
  end
  if type(payload.Records) == "table" then
    for _, record in ipairs(payload.Records) do
      if record.eventSource == "aws:codecommit" or type(record.codecommit) == "table" then
        return payload
      end
      local nested = codecommit_record_nested_payload(record)
      if nested then
        return decode_codecommit_message(nested, depth)
      end
    end
  end
  return payload
end

local function codecommit_push_from_record(payload, record)
  record = record or {}
  local reference = ((record.codecommit or {}).references or {})[1] or {}
  local raw_ref = reference.ref or reference.referenceName or ""
  local after = reference.commit or reference.commitId or ""
  local before = reference.oldCommit or reference.oldCommitId or ""
  if before == "" and after ~= "" then
    before = ZERO_SHA
  elseif after == "" and before ~= "" then
    after = ZERO_SHA
  end
  local repo_name = record.eventSourceARN and record.eventSourceARN:match(":([^:]+)$")
    or record.repositoryName
    or ""
  local region = record.awsRegion or ""
  local account_id = tostring(record.eventSourceARN or ""):match(":codecommit:[^:]+:(%d+):") or ""
  local sender = codecommit_user_from_arn(record.userIdentityARN)
  local repository = codecommit_repository(repo_name, account_id, region)
  local action = codecommit_reference_action(reference.event, before, after)
  if action == "create" or action == "delete" then
    return make_internal_event({
      event = action,
      action = action,
      provider = "codecommit",
      raw = payload,
      data = {
        ref = codecommit_ref_name(raw_ref),
        ref_type = codecommit_ref_type(raw_ref),
        master_branch = repository.default_branch or "",
        description = repository.description,
        pusher_type = "user",
        repository = repository,
        sender = sender,
      },
      timestamp = record.eventTime or "",
    })
  end
  return make_internal_event({
    event = "push",
    action = "push",
    provider = "codecommit",
    raw = payload,
    data = {
      ref = raw_ref,
      before = before,
      after = after,
      created = before == "" or before == ZERO_SHA,
      deleted = after == "" or after == ZERO_SHA,
      forced = false,
      compare = "",
      commits = {},
      head_commit = nil,
      pusher = { name = sender.login, email = "" },
      repository = repository,
      sender = sender,
    },
    timestamp = record.eventTime or "",
  })
end

local function codecommit_push_from_eventbridge(payload)
  local detail = payload.detail or {}
  if not codecommit_supported_reference_event(detail.event) then
    return nil, "Unsupported CodeCommit reference event"
  end
  local raw_ref = codecommit_eventbridge_ref(detail)
  local after = detail.commitId or ""
  local before = detail.oldCommitId or ""
  if before == "" and after ~= "" then
    before = ZERO_SHA
  elseif after == "" and before ~= "" then
    after = ZERO_SHA
  end
  local region = payload.region or ""
  local account_id = payload.account or ""
  local repo_name = detail.repositoryName or ""
  local sender = codecommit_user_from_arn(detail.callerUserArn or detail.userIdentityARN)
  local repository = codecommit_repository(repo_name, account_id, region)
  local action = codecommit_reference_action(detail.event, before, after)
  if action == "create" or action == "delete" then
    return make_internal_event({
      event = action,
      action = action,
      provider = "codecommit",
      raw = payload,
      data = {
        ref = codecommit_ref_name(raw_ref),
        ref_type = codecommit_ref_type(raw_ref),
        master_branch = repository.default_branch or "",
        description = repository.description,
        pusher_type = "user",
        repository = repository,
        sender = sender,
      },
      timestamp = payload.time or "",
    })
  end
  return make_internal_event({
    event = "push",
    action = "push",
    provider = "codecommit",
    raw = payload,
    data = {
      ref = raw_ref,
      before = before,
      after = after,
      created = before == "" or before == ZERO_SHA,
      deleted = after == "" or after == ZERO_SHA,
      forced = false,
      compare = "",
      commits = {},
      head_commit = nil,
      pusher = { name = sender.login, email = "" },
      repository = repository,
      sender = sender,
    },
    timestamp = payload.time or "",
  })
end

local function codecommit_webhook(payload)
  payload = decode_codecommit_message(payload)
  if type(payload.Records) == "table" and type(payload.Records[1]) == "table" then
    return codecommit_push_from_record(payload, payload.Records[1])
  end
  if
    payload["detail-type"] == "CodeCommit Comment on Commit"
    or payload["detail-type"] == "CodeCommit Comment on Pull Request"
    or payload["detail-type"] == "CodeCommit Comment Reaction Change"
  then
    return codecommit_comment_from_eventbridge(payload)
  end
  if payload["detail-type"] == "CodeCommit Pull Request State Change" then
    if codecommit_is_approval_event((payload.detail or {}).event) then
      return codecommit_approval_from_eventbridge(payload)
    end
    return codecommit_pull_request_from_eventbridge(payload)
  end
  if payload["detail-type"] == "CodeCommit Approval Rule Template Change" then
    return codecommit_approval_from_eventbridge(payload)
  end
  if
    payload.source == "aws.codecommit"
    or payload["detail-type"] == "CodeCommit Repository State Change"
  then
    return codecommit_push_from_eventbridge(payload)
  end
  return nil, "Unsupported CodeCommit webhook payload"
end

-- Fetch one page of repository summaries from /v1/repos.
-- max_results: optional integer to pass as maxResults to CodeCommit.
-- Returns repos list, incomplete (bool), and status code.
local function list_repos_page(max_results)
  local url = base() .. "/repos"
  if max_results then
    url = url .. "?maxResults=" .. max_results
  end
  local ok, status, _, body = fetch_json(url)
  if not ok then
    return nil, false, 503
  end
  if status ~= 200 then
    return nil, false, status
  end
  local data = DecodeJson(body) or {}
  local incomplete = data.nextToken ~= nil and data.nextToken ~= ""
  return data.repositories or {}, incomplete, 200
end

-- Error if the caller requested page > 1 (CodeCommit uses cursor-based pagination;
-- arbitrary page offsets are not supported).
local function check_page()
  local page = tonumber(GetParam("page") or "1") or 1
  if page > 1 then
    respond_json(422, {
      message = "CodeCommit uses cursor-based pagination; only page=1 is supported",
    })
    return false
  end
  return true
end

local b = make_backend_builder()
b:rest("get_root", function()
  proxy_health_check(pcall(Fetch, base() .. "/repos", auth()))
end)

-- GET /repos/{owner}/{repo}: owner must be "codecommit".
-- CodeCommit returns 400 (RepositoryDoesNotExistException) for unknown repos;
-- map that to 404 for GitHub compatibility.
b:rest("get_repo", function(owner, repo_name)
  if owner ~= "codecommit" then
    respond_json(404, { message = "Not Found" })
    return
  end
  local ok, status, _, body = fetch_json(base() .. "/repos/" .. repo_name)
  if not ok then
    respond_json(503, {})
    return
  end
  if status == 400 then
    local err = DecodeJson(body) or {}
    if (err["__type"] or ""):find("DoesNotExist") then
      respond_json(404, { message = "Not Found" })
      return
    end
  end
  if status ~= 200 then
    respond_json(status, {})
    return
  end
  local data = DecodeJson(body) or {}
  local r = data.repositoryMetadata
  if not r then
    respond_json(404, { message = "Not Found" })
    return
  end
  respond_json(200, translate_repo(r))
end)

b:rest("get_repositories", function()
  if not check_page() then
    return
  end
  local per_page = tonumber(GetParam("per_page") or "") or nil
  local repos, _, status = list_repos_page(per_page)
  if not repos then
    respond_json(status, {})
    return
  end
  respond_json(200, translate_list(translate_repo, repos))
end)

-- GET /repos/{owner}/{repo}/branches: owner must be "codecommit".
b:rest("get_repo_branches", function(owner, repo_name)
  if owner ~= "codecommit" then
    respond_json(404, { message = "Not Found" })
    return
  end
  local ok, status, _, body = fetch_json(base() .. "/repos/" .. repo_name .. "/branches")
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
  for _, branch_name in ipairs(data.branches or {}) do
    result[#result + 1] = {
      name = branch_name,
      commit = { sha = "", url = "" },
      protected = false,
    }
  end
  respond_json(200, result)
end)

b:rest("search_repositories", function()
  if not check_page() then
    return
  end
  local q = (GetParam("q") or ""):lower()
  local per_page = tonumber(GetParam("per_page") or "") or nil
  local repos, incomplete, status = list_repos_page(per_page)
  if not repos then
    respond_json(status, {})
    return
  end
  local items = {}
  for _, r in ipairs(repos) do
    local name = (r.repositoryName or ""):lower()
    if q == "" or name:find(q, 1, true) then
      items[#items + 1] = translate_repo(r)
    end
  end
  respond_json(200, { total_count = #items, incomplete_results = incomplete, items = items })
end)

b:webhook("codecommit", codecommit_webhook)
b:webhook_translator("branch_protection_rule", translate_codecommit_normalized_webhook)
b:webhook_translator("commit_comment", translate_codecommit_normalized_webhook)
b:webhook_translator("create", translate_codecommit_normalized_webhook)
b:webhook_translator("delete", translate_codecommit_normalized_webhook)
b:webhook_translator("pull_request", translate_codecommit_normalized_webhook)
b:webhook_translator("pull_request_review", translate_codecommit_normalized_webhook)
b:webhook_translator("pull_request_review_comment", translate_codecommit_normalized_webhook)
b:webhook_translator("push", translate_codecommit_normalized_webhook)
b:webhook_github_translator("branch_protection_rule", translate_codecommit_github_webhook)
b:webhook_github_translator("commit_comment", translate_codecommit_github_webhook)
b:webhook_github_translator("create", translate_codecommit_github_webhook)
b:webhook_github_translator("delete", translate_codecommit_github_webhook)
b:webhook_github_translator("pull_request", translate_codecommit_github_webhook)
b:webhook_github_translator("pull_request_review", translate_codecommit_github_webhook)
b:webhook_github_translator("pull_request_review_comment", translate_codecommit_github_webhook)
b:webhook_github_translator("push", translate_codecommit_github_webhook)

b:build()
