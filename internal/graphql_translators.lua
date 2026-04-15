-- GraphQL translators, connection helpers, and fetch utilities.
-- Provides shared functions used by backend resolvers to convert
-- GitHub REST-shaped responses into GraphQL-shaped responses.
--
-- Requires: EncodeBase64, DecodeBase64, DecodeJson (Redbean built-ins)
--
-- Globals exported:
--   encode_node_id(type_name, local_id)
--   decode_node_id(encoded)
--   graphql_fetch(fetch_json, path[, method[, body]])
--   graphql_fetch_with_headers(fetch_json, path[, method[, body]])
--   graphql_fetch_or_error(fetch_json, path, ctx, field_node[, method[, body]])
--   graphql_page_to_cursor(page)
--   graphql_cursor_to_page(cursor)
--   graphql_cursor_url(url_base, args, param_names)
--   graphql_inline_connection(typename, nodes)
--   graphql_make_connection(typename, nodes, args, total[, ctx])
--   graphql_issues_connection(nodes, args, total[, ctx])
--   graphql_prs_connection(nodes, args, total[, ctx])
--   graphql_repos_connection(nodes, args, total[, ctx])
--   graphql_users_connection(nodes, args, total[, ctx])
--   graphql_labels_connection(nodes, args, total[, ctx])
--   graphql_refs_connection(nodes, args, total[, ctx])
--   graphql_translate_repo(r)
--   graphql_translate_user(u)
--   graphql_translate_org(o)
--   graphql_translate_owner(o)
--   graphql_translate_issue(i[, owner, repo])
--   graphql_translate_pr(p[, owner, repo])
--   graphql_translate_label(l[, owner, repo])
--   graphql_translate_milestone(m[, owner, repo])
--   graphql_translate_comment(c[, owner, repo])
--   graphql_translate_commit(c)
--   graphql_translate_ref(r, repo)
--   graphql_translate_release(r[, owner, repo])
--   graphql_translate_reaction(r)

-- ---------------------------------------------------------------------------
-- Enum maps (local: used by translators only)
-- ---------------------------------------------------------------------------

-- REST lowercase state → GraphQL SCREAMING_SNAKE_CASE enum value.
-- Fallback "OPEN" / "UNKNOWN" prevents a nil state from crashing the response.
local ISSUE_STATE = { open = "OPEN", closed = "CLOSED" }
local PR_STATE = { open = "OPEN", closed = "CLOSED" }
local MILESTONE_STATE = { open = "OPEN", closed = "CLOSED" }
local VISIBILITY = { public = "PUBLIC", private = "PRIVATE", internal = "INTERNAL" }
-- MERGEABLE handles both the GitHub REST string convention (clean/dirty/unknown)
-- and Gitea's boolean convention (true → MERGEABLE, false → CONFLICTING).
local MERGEABLE = {
  clean = "MERGEABLE",
  dirty = "CONFLICTING",
  unknown = "UNKNOWN",
  [true] = "MERGEABLE",
  [false] = "CONFLICTING",
}
local REACTION_CONTENT = {
  ["+1"] = "THUMBS_UP",
  ["-1"] = "THUMBS_DOWN",
  laugh = "LAUGH",
  confused = "CONFUSED",
  heart = "HEART",
  hooray = "HOORAY",
  rocket = "ROCKET",
  eyes = "EYES",
}

-- ---------------------------------------------------------------------------
-- Node ID encoding
-- ---------------------------------------------------------------------------

-- encode_node_id is global: base64-encodes a GraphQL node ID as "TypeName:local_id".
-- local_id is the REST path segment that identifies the object:
--   Repository  → "owner/repo"
--   User/Org    → "login"
--   Issue/PR    → "owner/repo/number"
--   Comment     → "owner/repo/comment_id"
function encode_node_id(type_name, local_id) -- luacheck: globals encode_node_id
  return EncodeBase64(type_name .. ":" .. local_id)
end

-- decode_node_id is global: decodes a node ID produced by encode_node_id.
-- Returns (type_name, local_id) on success.
-- Returns (nil, nil) if the value is absent, not valid base64, or missing the colon separator.
function decode_node_id(encoded) -- luacheck: globals decode_node_id
  if not encoded then
    return nil, nil
  end
  local decoded = DecodeBase64(encoded)
  if not decoded then
    return nil, nil
  end
  local t, id = decoded:match("^([^:]+):(.+)$")
  return t, id -- both nil when the pattern does not match
end

-- ---------------------------------------------------------------------------
-- Fetch helpers
-- ---------------------------------------------------------------------------

-- graphql_fetch is global: thin adapter over a backend's fetch_json for use in resolvers.
-- Calls fetch_json, checks the status, decodes the JSON body, and returns a simple pair.
--
-- Returns (decoded_table, nil)       on HTTP 2xx with a valid JSON body.
-- Returns (nil, error_string)        on network failure, non-2xx status, or bad JSON.
--
-- fetch_json: the backend's local fetch function (from make_backend_transport)
-- path:       full URL to request
-- method:     HTTP method string, or nil for GET
-- body:       request body (JSON-encoded string) or nil
function graphql_fetch(fetch_json, path, method, body) -- luacheck: globals graphql_fetch
  local ok, status, _, raw = fetch_json(path, method, body)
  if not ok then
    return nil, "network error fetching " .. path
  end
  if status == 404 then
    return nil, "not found: " .. path
  end
  if status < 200 or status >= 300 then
    return nil, "upstream error " .. tostring(status) .. " fetching " .. path
  end
  local decoded = DecodeJson(raw)
  if decoded == nil then
    return nil, "invalid JSON from upstream for " .. path
  end
  return decoded, nil
end

-- graphql_fetch_with_headers is global: like graphql_fetch but also returns response headers.
-- Resolvers that need X-Total or X-Total-Count for pagination use this variant.
--
-- Returns (decoded_table, headers_table, nil)        on success (headers is {} when upstream omits them).
-- Returns (nil,           nil,           error_string) on failure.
function graphql_fetch_with_headers(fetch_json, path, method, body) -- luacheck: globals graphql_fetch_with_headers
  local ok, status, headers, raw = fetch_json(path, method, body)
  if not ok then
    return nil, nil, "network error fetching " .. path
  end
  if status == 404 then
    return nil, nil, "not found: " .. path
  end
  if status < 200 or status >= 300 then
    return nil, nil, "upstream error " .. tostring(status) .. " fetching " .. path
  end
  local decoded = DecodeJson(raw)
  if decoded == nil then
    return nil, nil, "invalid JSON from upstream for " .. path
  end
  return decoded, headers or {}, nil
end

-- graphql_fetch_or_error is global: like graphql_fetch but records an error in ctx on
-- failure and returns nil, so callers can write `if not data then return nil end` instead
-- of repeating the HTTP-status → error-code mapping in every resolver.
--
-- fetch_json:  the backend's fetch function (from make_backend_transport)
-- path:        full URL to request
-- ctx:         GraphQL execution context (errors array)
-- field_node:  FieldNode being resolved (for location tracking), or nil
-- method:      HTTP method string, or nil for GET
-- body:        request body (JSON-encoded string) or nil
--
-- Returns decoded_table on success, nil on failure (error already in ctx.errors).
function graphql_fetch_or_error(fetch_json, path, ctx, field_node, method, body) -- luacheck: globals graphql_fetch_or_error
  local data, err = graphql_fetch(fetch_json, path, method, body)
  if not data then
    local code = "INTERNAL_ERROR"
    if err:find("not found") then
      code = "NOT_FOUND"
    elseif err:find("40[13]") then
      code = "FORBIDDEN"
    elseif err:find("429") then
      code = "RATE_LIMITED"
    end
    graphql_error(ctx, err, field_node, code)
    return nil
  end
  return data
end

-- ---------------------------------------------------------------------------
-- Pagination cursor helpers
-- ---------------------------------------------------------------------------

-- graphql_page_to_cursor is global: encodes a 1-based page number as a stable opaque cursor.
-- Page-number cursors are stable across page-size changes; clients should treat them as opaque.
function graphql_page_to_cursor(page) -- luacheck: globals graphql_page_to_cursor
  return EncodeBase64("page:" .. tostring(page))
end

-- graphql_cursor_to_page is global: decodes a cursor produced by graphql_page_to_cursor.
-- Returns the 1-based page number on success, or nil if the cursor is absent or malformed.
function graphql_cursor_to_page(cursor) -- luacheck: globals graphql_cursor_to_page
  if not cursor then
    return nil
  end
  local decoded = DecodeBase64(cursor)
  if not decoded then
    return nil
  end
  return tonumber(decoded:match("^page:(%d+)$"))
end

-- graphql_cursor_url is global: builds a paginated REST URL from GraphQL connection args.
-- url_base:    base REST URL (may already contain a query string)
-- args:        GraphQL connection arguments table; reads args.first (default 30) and args.after
-- param_names: table mapping REST parameter names, e.g. { per_page = "limit", page = "page" }.
--              Keys present in param_names are appended; omitted keys are skipped.
--              The page parameter is only appended when the resolved page is > 1.
function graphql_cursor_url(url_base, args, param_names) -- luacheck: globals graphql_cursor_url
  local per_page = args.first or 30
  local page = 1
  if args.after then
    local p = graphql_cursor_to_page(args.after)
    if p then
      page = p + 1
    end
  end
  local sep = url_base:find("?", 1, true) and "&" or "?"
  local parts = {}
  if param_names.per_page then
    parts[#parts + 1] = param_names.per_page .. "=" .. tostring(per_page)
  end
  if param_names.page and page > 1 then
    parts[#parts + 1] = param_names.page .. "=" .. tostring(page)
  end
  if #parts == 0 then
    return url_base
  end
  return url_base .. sep .. table.concat(parts, "&")
end

-- ---------------------------------------------------------------------------
-- Connection builders
-- ---------------------------------------------------------------------------

-- graphql_inline_connection is global: builds a Relay Connection for a list already present
-- in the parent REST response (e.g. issue labels, PR assignees) where no pagination is needed.
-- All keys are GraphQL camelCase so the executor can pluck them by field name directly.
function graphql_inline_connection(typename, nodes) -- luacheck: globals graphql_inline_connection
  local edges = {}
  for i, node in ipairs(nodes) do
    edges[i] = { __typename = typename .. "Edge", cursor = "", node = node }
  end
  return {
    __typename = typename .. "Connection",
    totalCount = #nodes,
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

-- graphql_make_connection is global: builds a Relay Connection for a paginated REST list.
-- typename: GraphQL type name of the items (e.g. "Issue", "Repository")
-- nodes:    array of already-translated GraphQL objects for this page
-- args:     GraphQL connection arguments (first, after, last, before)
-- total:    total item count from the upstream header (X-Total / X-Total-Count), or nil
-- ctx:      optional GraphQL field context; when present, backward-pagination errors are
--           reported via graphql_error; when nil the error is silently dropped.
--
-- Backward pagination (last/before) is not supported in Phase 1: returns an empty connection
-- with an error added to ctx when provided.
function graphql_make_connection(typename, nodes, args, total, ctx) -- luacheck: globals graphql_make_connection
  if args.last or args.before then
    if ctx then
      graphql_error(ctx, "backward pagination (last/before) is not supported in this version")
    end
    return {
      __typename = typename .. "Connection",
      totalCount = 0,
      pageInfo = {
        __typename = "PageInfo",
        hasNextPage = false,
        hasPreviousPage = false,
        startCursor = nil,
        endCursor = nil,
      },
      nodes = {},
      edges = {},
    }
  end
  local per_page = args.first or 30
  local page = 1
  if args.after then
    local p = graphql_cursor_to_page(args.after)
    if p then
      page = p + 1
    end
  end
  local count = #nodes
  local has_next
  if total ~= nil then
    has_next = (page * per_page) < total
  else
    has_next = count == per_page
  end
  local start_cursor = count > 0 and graphql_page_to_cursor(page) or nil
  local edges = {}
  for i, node in ipairs(nodes) do
    edges[i] =
      { __typename = typename .. "Edge", cursor = graphql_page_to_cursor(page), node = node }
  end
  return {
    __typename = typename .. "Connection",
    totalCount = total or count,
    pageInfo = {
      __typename = "PageInfo",
      hasNextPage = has_next,
      hasPreviousPage = page > 1,
      startCursor = start_cursor,
      endCursor = start_cursor,
    },
    nodes = nodes,
    edges = edges,
  }
end

-- Typed convenience wrappers around graphql_make_connection.

function graphql_issues_connection(nodes, args, total, ctx) -- luacheck: globals graphql_issues_connection
  return graphql_make_connection("Issue", nodes, args, total, ctx)
end

function graphql_prs_connection(nodes, args, total, ctx) -- luacheck: globals graphql_prs_connection
  return graphql_make_connection("PullRequest", nodes, args, total, ctx)
end

function graphql_repos_connection(nodes, args, total, ctx) -- luacheck: globals graphql_repos_connection
  return graphql_make_connection("Repository", nodes, args, total, ctx)
end

function graphql_users_connection(nodes, args, total, ctx) -- luacheck: globals graphql_users_connection
  return graphql_make_connection("User", nodes, args, total, ctx)
end

function graphql_labels_connection(nodes, args, total, ctx) -- luacheck: globals graphql_labels_connection
  return graphql_make_connection("Label", nodes, args, total, ctx)
end

function graphql_refs_connection(nodes, args, total, ctx) -- luacheck: globals graphql_refs_connection
  return graphql_make_connection("Ref", nodes, args, total, ctx)
end

-- ---------------------------------------------------------------------------
-- Object translators
-- ---------------------------------------------------------------------------

-- graphql_translate_user is global: converts a GitHub REST user object to GraphQL User shape.
-- isViewer is always false here; the Query.viewer resolver overrides it to true.
function graphql_translate_user(u) -- luacheck: globals graphql_translate_user
  if not u then
    return nil
  end
  return {
    __typename = "User",
    id = encode_node_id("User", u.login or ""),
    login = u.login,
    name = (u.name and u.name ~= "") and u.name or nil,
    email = u.email or "",
    bio = (u.bio and u.bio ~= "") and u.bio or nil,
    company = (u.company and u.company ~= "") and u.company or nil,
    location = (u.location and u.location ~= "") and u.location or nil,
    websiteUrl = (u.blog and u.blog ~= "") and u.blog or nil,
    avatarUrl = u.avatar_url,
    url = u.html_url,
    isSiteAdmin = u.site_admin and true or false,
    isViewer = false,
    createdAt = u.created_at,
    updatedAt = u.updated_at,
  }
end

-- graphql_translate_org is global: converts a GitHub REST org object to GraphQL Organization shape.
function graphql_translate_org(o) -- luacheck: globals graphql_translate_org
  if not o then
    return nil
  end
  return {
    __typename = "Organization",
    id = encode_node_id("Organization", o.login or ""),
    login = o.login,
    name = o.name,
    description = (o.description and o.description ~= "") and o.description or nil,
    avatarUrl = o.avatar_url,
    url = o.html_url,
    websiteUrl = (o.blog and o.blog ~= "") and o.blog or nil,
    email = o.email or "",
    location = (o.location and o.location ~= "") and o.location or nil,
    createdAt = o.created_at,
    updatedAt = o.updated_at,
  }
end

-- graphql_translate_owner is global: converts a GitHub REST user/org to User or Organization.
-- Branches on o.type: "Organization" → graphql_translate_org, anything else → graphql_translate_user.
function graphql_translate_owner(o) -- luacheck: globals graphql_translate_owner
  if not o then
    return nil
  end
  if o.type == "Organization" then
    return graphql_translate_org(o)
  else
    return graphql_translate_user(o)
  end
end

-- graphql_translate_label is global: converts a GitHub REST label to GraphQL Label shape.
-- owner and repo are optional; when provided they give the label a resolvable node ID.
function graphql_translate_label(l, owner, repo) -- luacheck: globals graphql_translate_label
  if not l then
    return nil
  end
  local local_id
  if owner and repo then
    local_id = owner .. "/" .. repo .. "/" .. tostring(l.id or "")
  else
    local_id = tostring(l.id or "")
  end
  return {
    __typename = "Label",
    id = encode_node_id("Label", local_id),
    name = l.name,
    color = l.color,
    description = (l.description and l.description ~= "") and l.description or nil,
    isDefault = l.default and true or false,
    url = l.url,
  }
end

-- graphql_translate_milestone is global: converts a GitHub REST milestone to GraphQL Milestone shape.
-- owner and repo are optional; when provided they give the milestone a resolvable node ID.
function graphql_translate_milestone(m, owner, repo) -- luacheck: globals graphql_translate_milestone
  if not m then
    return nil
  end
  local number = m.number or m.id
  local local_id
  if owner and repo then
    local_id = owner .. "/" .. repo .. "/" .. tostring(number or "")
  else
    local_id = tostring(number or "")
  end
  return {
    __typename = "Milestone",
    id = encode_node_id("Milestone", local_id),
    number = number,
    title = m.title,
    description = (m.description and m.description ~= "") and m.description or nil,
    state = MILESTONE_STATE[m.state] or "OPEN",
    dueOn = m.due_on,
    createdAt = m.created_at,
    updatedAt = m.updated_at,
    closedAt = m.closed_at,
  }
end

-- graphql_translate_comment is global: converts a GitHub REST issue comment to GraphQL IssueComment.
-- owner and repo are optional; when provided they give the comment a resolvable node ID.
function graphql_translate_comment(c, owner, repo) -- luacheck: globals graphql_translate_comment
  if not c then
    return nil
  end
  local local_id
  if owner and repo then
    local_id = owner .. "/" .. repo .. "/" .. tostring(c.id or "")
  else
    local_id = tostring(c.id or "")
  end
  return {
    __typename = "IssueComment",
    id = encode_node_id("IssueComment", local_id),
    body = c.body,
    author = c.user and graphql_translate_user(c.user) or nil,
    url = c.html_url,
    createdAt = c.created_at,
    updatedAt = c.updated_at,
  }
end

-- graphql_translate_commit is global: converts a GitHub REST commit to GraphQL Commit shape.
-- Node IDs for commits omit owner/repo context (Commit is a Phase 2 node resolver target).
function graphql_translate_commit(c) -- luacheck: globals graphql_translate_commit
  if not c then
    return nil
  end
  -- REST commits nest author/committer metadata under c.commit; bare objects have them at root.
  local git = c.commit or c
  local msg = git.message or c.message or ""
  local git_author = git.author or {}
  local git_committer = git.committer or {}
  return {
    __typename = "Commit",
    id = encode_node_id("Commit", c.sha or ""),
    oid = c.sha,
    message = msg,
    messageHeadline = msg:match("^([^\n]*)") or "",
    author = {
      __typename = "GitActor",
      name = git_author.name,
      email = git_author.email,
      date = git_author.date,
      user = c.author and graphql_translate_user(c.author) or nil,
    },
    committer = {
      __typename = "GitActor",
      name = git_committer.name,
      email = git_committer.email,
      date = git_committer.date,
      user = c.committer and graphql_translate_user(c.committer) or nil,
    },
    authoredDate = git_author.date,
    committedDate = git_committer.date,
    url = c.html_url,
  }
end

-- graphql_translate_ref is global: converts a GitHub REST branch/ref to GraphQL Ref shape.
-- repo must be a translated Repository table (provides nameWithOwner for the node ID).
-- Handles both GitHub's git/refs shape ({ref, object.sha}) and branches shape ({name, commit.sha}).
function graphql_translate_ref(r, repo) -- luacheck: globals graphql_translate_ref
  if not r then
    return nil
  end
  -- Determine the full ref path and the short name.
  local ref_path = r.ref or ("refs/heads/" .. (r.name or ""))
  local short_name = r.name or ref_path:match("[^/]+$") or ref_path
  -- Commit SHA: git/refs uses r.object.sha; branches uses r.commit.sha.
  local sha = (r.object and r.object.sha) or (r.commit and r.commit.sha)
  local owner_repo = (repo and repo.nameWithOwner) or ""
  return {
    __typename = "Ref",
    id = encode_node_id("Ref", owner_repo .. "/" .. ref_path),
    name = short_name,
    prefix = ref_path:match("^(refs/[^/]+/)") or "",
    target = sha and { __typename = "Commit", oid = sha } or nil,
  }
end

-- graphql_translate_release is global: converts a GitHub REST release to GraphQL Release shape.
-- owner and repo are optional; when provided they give the release a resolvable node ID.
function graphql_translate_release(r, owner, repo) -- luacheck: globals graphql_translate_release
  if not r then
    return nil
  end
  local local_id
  if owner and repo then
    local_id = owner .. "/" .. repo .. "/" .. tostring(r.id or "")
  else
    local_id = tostring(r.id or "")
  end
  return {
    __typename = "Release",
    id = encode_node_id("Release", local_id),
    tagName = r.tag_name,
    name = r.name,
    description = (r.body and r.body ~= "") and r.body or nil,
    isDraft = r.draft and true or false,
    isPrerelease = r.prerelease and true or false,
    createdAt = r.created_at,
    publishedAt = r.published_at,
    url = r.html_url,
    author = r.author and graphql_translate_user(r.author) or nil,
  }
end

-- graphql_translate_reaction is global: converts a GitHub REST reaction to GraphQL Reaction shape.
function graphql_translate_reaction(r) -- luacheck: globals graphql_translate_reaction
  if not r then
    return nil
  end
  return {
    __typename = "Reaction",
    id = encode_node_id("Reaction", tostring(r.id or "")),
    content = REACTION_CONTENT[r.content] or (r.content and r.content:upper()) or "",
    user = r.user and graphql_translate_user(r.user) or nil,
    createdAt = r.created_at,
  }
end

-- graphql_translate_issue is global: converts a GitHub REST issue to GraphQL Issue shape.
-- owner and repo are optional; when provided they give the issue a resolvable node ID and
-- give its inline labels/assignees their full node IDs too.
-- Note: REST issues with pull_request field set are actually PRs; callers should filter them.
function graphql_translate_issue(i, owner, repo) -- luacheck: globals graphql_translate_issue
  if not i then
    return nil
  end
  local local_id
  if owner and repo then
    local_id = owner .. "/" .. repo .. "/" .. tostring(i.number or "")
  else
    local_id = tostring(i.id or "")
  end
  local translated_labels = {}
  for _, l in ipairs(i.labels or {}) do
    translated_labels[#translated_labels + 1] = graphql_translate_label(l, owner, repo)
  end
  local translated_assignees = {}
  for _, u in ipairs(i.assignees or {}) do
    translated_assignees[#translated_assignees + 1] = graphql_translate_user(u)
  end
  return {
    __typename = "Issue",
    id = encode_node_id("Issue", local_id),
    number = i.number,
    title = i.title,
    body = (i.body and i.body ~= "") and i.body or nil,
    state = ISSUE_STATE[i.state] or "OPEN",
    url = i.html_url,
    author = i.user and graphql_translate_user(i.user) or nil,
    assignees = graphql_inline_connection("User", translated_assignees),
    labels = graphql_inline_connection("Label", translated_labels),
    milestone = graphql_translate_milestone(i.milestone, owner, repo),
    comments = { __typename = "IssueCommentConnection", totalCount = i.comments or 0 },
    createdAt = i.created_at,
    updatedAt = i.updated_at,
    closedAt = i.closed_at,
  }
end

-- graphql_translate_pr is global: converts a GitHub REST pull request to GraphQL PullRequest shape.
-- State is derived: MERGED when merged_at is non-nil, otherwise OPEN or CLOSED from state field.
-- owner and repo are optional; when provided they give the PR and its inline lists proper node IDs.
function graphql_translate_pr(p, owner, repo) -- luacheck: globals graphql_translate_pr
  if not p then
    return nil
  end
  local local_id
  if owner and repo then
    local_id = owner .. "/" .. repo .. "/" .. tostring(p.number or "")
  else
    local_id = tostring(p.id or "")
  end
  local merged = p.merged_at ~= nil
  local state = merged and "MERGED" or PR_STATE[p.state] or "OPEN"
  local head = p.head or {}
  local base = p.base or {}
  local translated_labels = {}
  for _, l in ipairs(p.labels or {}) do
    translated_labels[#translated_labels + 1] = graphql_translate_label(l, owner, repo)
  end
  local translated_assignees = {}
  for _, u in ipairs(p.assignees or {}) do
    translated_assignees[#translated_assignees + 1] = graphql_translate_user(u)
  end
  return {
    __typename = "PullRequest",
    id = encode_node_id("PullRequest", local_id),
    number = p.number,
    title = p.title,
    body = (p.body and p.body ~= "") and p.body or nil,
    state = state,
    merged = merged,
    mergedAt = p.merged_at,
    url = p.html_url,
    author = p.user and graphql_translate_user(p.user) or nil,
    headRefName = head.ref,
    headRefOid = head.sha,
    baseRefName = base.ref,
    baseRefOid = base.sha,
    mergeable = MERGEABLE[p.mergeable] or "UNKNOWN",
    assignees = graphql_inline_connection("User", translated_assignees),
    labels = graphql_inline_connection("Label", translated_labels),
    createdAt = p.created_at,
    updatedAt = p.updated_at,
    closedAt = p.closed_at,
  }
end

-- graphql_translate_repo is global: converts a GitHub REST repository to GraphQL Repository shape.
-- Sub-resolver fields (issues, pullRequests, labels, refs, releases, etc.) are left nil;
-- the executor fetches them via registered sub-resolvers when the client selects them.
function graphql_translate_repo(r) -- luacheck: globals graphql_translate_repo
  if not r then
    return nil
  end
  return {
    __typename = "Repository",
    id = encode_node_id("Repository", r.full_name or ""),
    name = r.name,
    nameWithOwner = r.full_name,
    description = (r.description and r.description ~= "") and r.description or nil,
    isPrivate = r.private and true or false,
    isFork = r.fork and true or false,
    isArchived = r.archived and true or false,
    isDisabled = r.disabled and true or false,
    url = r.html_url,
    sshUrl = r.ssh_url,
    cloneUrl = r.clone_url,
    homepageUrl = (r.homepage and r.homepage ~= "") and r.homepage or nil,
    stargazerCount = r.stargazers_count or 0,
    forkCount = r.forks_count or 0,
    diskUsage = r.size,
    primaryLanguage = r.language and { __typename = "Language", name = r.language } or nil,
    visibility = VISIBILITY[r.visibility] or (r.private and "PRIVATE" or "PUBLIC"),
    hasIssuesEnabled = r.has_issues and true or false,
    hasWikiEnabled = r.has_wiki and true or false,
    hasProjectsEnabled = r.has_projects and true or false,
    createdAt = r.created_at,
    updatedAt = r.updated_at,
    pushedAt = r.pushed_at,
    defaultBranchRef = r.default_branch and { __typename = "Ref", name = r.default_branch } or nil,
    owner = graphql_translate_owner(r.owner),
  }
end
