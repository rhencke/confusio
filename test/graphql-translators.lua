-- Unit tests for GQL-06: GraphQL object translators.
-- Covers graphql_translate_repo, graphql_translate_user, graphql_translate_org,
-- graphql_translate_owner, graphql_translate_issue, graphql_translate_pr,
-- graphql_translate_label, graphql_translate_milestone, graphql_translate_comment,
-- graphql_translate_commit, graphql_translate_ref, graphql_translate_release,
-- graphql_translate_reaction, and the inline connection helper used by issue/PR.
-- Loaded by test/unit-graphql.lua; relies on shared state from the driver.
-- ============================================================

-- Globals provided by the driver (test/unit-graphql.lua):
-- luacheck: globals ok eq PASS FAIL

-- ============================================================
-- Sample REST fixtures
-- ============================================================

local SAMPLE_USER = {
  id = 1,
  login = "octocat",
  name = "The Octocat",
  email = "octocat@github.com",
  bio = "A cool cat",
  company = "GitHub",
  location = "San Francisco",
  blog = "https://github.blog",
  avatar_url = "https://avatars.githubusercontent.com/u/1",
  html_url = "https://github.com/octocat",
  site_admin = false,
  created_at = "2011-01-25T18:44:36Z",
  updated_at = "2021-01-01T00:00:00Z",
}

local SAMPLE_ORG = {
  id = 9919,
  login = "github",
  name = "GitHub",
  description = "How people build software.",
  avatar_url = "https://avatars.githubusercontent.com/u/9919",
  html_url = "https://github.com/github",
  blog = "https://github.blog",
  email = "support@github.com",
  location = "San Francisco",
  type = "Organization",
  created_at = "2008-05-11T04:37:31Z",
  updated_at = "2022-01-01T00:00:00Z",
}

local SAMPLE_REPO = {
  id = 1296269,
  full_name = "octocat/Hello-World",
  name = "Hello-World",
  description = "This is your first repository",
  private = false,
  fork = false,
  archived = false,
  disabled = false,
  html_url = "https://github.com/octocat/Hello-World",
  ssh_url = "git@github.com:octocat/Hello-World.git",
  clone_url = "https://github.com/octocat/Hello-World.git",
  homepage = "https://github.com",
  stargazers_count = 80,
  forks_count = 9,
  size = 108,
  language = "Go",
  visibility = "public",
  has_issues = true,
  has_wiki = true,
  has_projects = true,
  created_at = "2011-01-26T19:01:12Z",
  updated_at = "2011-01-26T19:14:43Z",
  pushed_at = "2011-01-26T19:06:43Z",
  default_branch = "main",
  owner = {
    login = "octocat",
    id = 1,
    type = "User",
    avatar_url = "https://avatars.githubusercontent.com/u/1",
    html_url = "https://github.com/octocat",
  },
}

local SAMPLE_LABEL = {
  id = 208045946,
  name = "bug",
  color = "ee0701",
  description = "Something isn't working",
  default = true,
  url = "https://api.github.com/repos/octocat/Hello-World/labels/bug",
}

local SAMPLE_MILESTONE = {
  id = 1002604,
  number = 1,
  title = "v1.0",
  description = "Tracking milestone for version 1.0",
  state = "open",
  open_issues = 4,
  closed_issues = 8,
  created_at = "2011-04-10T20:09:31Z",
  updated_at = "2014-03-03T18:58:10Z",
  closed_at = nil,
  due_on = "2012-10-09T23:39:01Z",
}

local SAMPLE_ISSUE = {
  id = 1,
  number = 1347,
  title = "Found a bug",
  body = "I'm having a problem with this.",
  state = "open",
  html_url = "https://github.com/octocat/Hello-World/issues/1347",
  user = SAMPLE_USER,
  assignees = { SAMPLE_USER },
  labels = { SAMPLE_LABEL },
  milestone = SAMPLE_MILESTONE,
  comments = 2,
  created_at = "2011-04-22T13:33:48Z",
  updated_at = "2011-04-22T13:33:48Z",
  closed_at = nil,
}

local SAMPLE_PR = {
  id = 1,
  number = 1,
  title = "Amazing new feature",
  body = "Please pull this in!",
  state = "open",
  merged_at = nil,
  html_url = "https://github.com/octocat/Hello-World/pull/1",
  user = SAMPLE_USER,
  head = { ref = "new-feature", sha = "6dcb09b5b57875f334f61aebed695e2e4193db5e" },
  base = { ref = "master", sha = "7fd1a60b01f91b314f59955a4e4d4e80d8edf11d" },
  mergeable = true,
  assignees = {},
  labels = {},
  created_at = "2011-01-26T19:01:12Z",
  updated_at = "2011-01-26T19:14:43Z",
  closed_at = nil,
}

-- ============================================================
-- graphql_translate_user
-- ============================================================

do -- maps all fields and sets isViewer = false
  local u = graphql_translate_user(SAMPLE_USER)
  eq(u.__typename, "User", "translate_user: __typename")
  eq(u.login, "octocat", "translate_user: login")
  eq(u.name, "The Octocat", "translate_user: name")
  eq(u.email, "octocat@github.com", "translate_user: email")
  eq(u.bio, "A cool cat", "translate_user: bio")
  eq(u.company, "GitHub", "translate_user: company")
  eq(u.location, "San Francisco", "translate_user: location")
  eq(u.websiteUrl, "https://github.blog", "translate_user: websiteUrl")
  eq(u.avatarUrl, "https://avatars.githubusercontent.com/u/1", "translate_user: avatarUrl")
  eq(u.url, "https://github.com/octocat", "translate_user: url")
  eq(u.isSiteAdmin, false, "translate_user: isSiteAdmin")
  eq(u.isViewer, false, "translate_user: isViewer is always false")
  eq(u.createdAt, "2011-01-25T18:44:36Z", "translate_user: createdAt")
  -- id is a base64 node ID encoding "User:octocat"
  eq(u.id, encode_node_id("User", "octocat"), "translate_user: id is encode_node_id(User, login)")
end

do -- empty blog → nil websiteUrl
  local u = graphql_translate_user({ login = "x", blog = "" })
  ok(u.websiteUrl == nil, "translate_user: empty blog → nil websiteUrl")
end

do -- nil input → nil output
  ok(graphql_translate_user(nil) == nil, "translate_user: nil input → nil output")
end

-- ============================================================
-- graphql_translate_org
-- ============================================================

do -- maps all fields with __typename = "Organization"
  local o = graphql_translate_org(SAMPLE_ORG)
  eq(o.__typename, "Organization", "translate_org: __typename")
  eq(o.login, "github", "translate_org: login")
  eq(o.name, "GitHub", "translate_org: name")
  eq(o.description, "How people build software.", "translate_org: description")
  eq(o.email, "support@github.com", "translate_org: email")
  eq(o.id, encode_node_id("Organization", "github"), "translate_org: id")
end

-- ============================================================
-- graphql_translate_owner
-- ============================================================

do -- type = "Organization" → Organization branch
  local o = graphql_translate_owner(SAMPLE_ORG)
  eq(o.__typename, "Organization", "translate_owner: org __typename")
end

do -- type = "User" → User branch
  local o = graphql_translate_owner(SAMPLE_USER)
  eq(o.__typename, "User", "translate_owner: user __typename")
end

do -- type absent → User branch (default)
  local o = graphql_translate_owner({ login = "anon" })
  eq(o.__typename, "User", "translate_owner: no type → User")
end

-- ============================================================
-- graphql_translate_repo
-- ============================================================

do -- maps all fields correctly
  local r = graphql_translate_repo(SAMPLE_REPO)
  eq(r.__typename, "Repository", "translate_repo: __typename")
  eq(r.name, "Hello-World", "translate_repo: name")
  eq(r.nameWithOwner, "octocat/Hello-World", "translate_repo: nameWithOwner")
  eq(r.description, "This is your first repository", "translate_repo: description")
  eq(r.isPrivate, false, "translate_repo: isPrivate")
  eq(r.isFork, false, "translate_repo: isFork")
  eq(r.isArchived, false, "translate_repo: isArchived")
  eq(r.isDisabled, false, "translate_repo: isDisabled")
  eq(r.url, "https://github.com/octocat/Hello-World", "translate_repo: url")
  eq(r.sshUrl, "git@github.com:octocat/Hello-World.git", "translate_repo: sshUrl")
  eq(r.cloneUrl, "https://github.com/octocat/Hello-World.git", "translate_repo: cloneUrl")
  eq(r.homepageUrl, "https://github.com", "translate_repo: homepageUrl")
  eq(r.stargazerCount, 80, "translate_repo: stargazerCount")
  eq(r.forkCount, 9, "translate_repo: forkCount")
  eq(r.diskUsage, 108, "translate_repo: diskUsage")
  eq(r.visibility, "PUBLIC", "translate_repo: visibility uppercased")
  eq(r.hasIssuesEnabled, true, "translate_repo: hasIssuesEnabled")
  eq(r.hasWikiEnabled, true, "translate_repo: hasWikiEnabled")
  eq(r.hasProjectsEnabled, true, "translate_repo: hasProjectsEnabled")
  eq(r.createdAt, "2011-01-26T19:01:12Z", "translate_repo: createdAt")
  eq(r.id, encode_node_id("Repository", "octocat/Hello-World"), "translate_repo: id")
end

do -- primaryLanguage is a Language sub-object
  local r = graphql_translate_repo(SAMPLE_REPO)
  ok(type(r.primaryLanguage) == "table", "translate_repo: primaryLanguage is table")
  eq(r.primaryLanguage.__typename, "Language", "translate_repo: primaryLanguage __typename")
  eq(r.primaryLanguage.name, "Go", "translate_repo: primaryLanguage name")
end

do -- no language → nil primaryLanguage
  local r = graphql_translate_repo({ full_name = "a/b", language = nil })
  ok(r.primaryLanguage == nil, "translate_repo: nil language → nil primaryLanguage")
end

do -- defaultBranchRef is a Ref stub
  local r = graphql_translate_repo(SAMPLE_REPO)
  ok(type(r.defaultBranchRef) == "table", "translate_repo: defaultBranchRef is table")
  eq(r.defaultBranchRef.__typename, "Ref", "translate_repo: defaultBranchRef __typename")
  eq(r.defaultBranchRef.name, "main", "translate_repo: defaultBranchRef name")
end

do -- visibility enum uppercased
  local r = graphql_translate_repo({ full_name = "a/b", visibility = "private" })
  eq(r.visibility, "PRIVATE", "translate_repo: private → PRIVATE")
end

do -- private flag fallback when visibility absent
  local r = graphql_translate_repo({ full_name = "a/b", private = true })
  eq(r.visibility, "PRIVATE", "translate_repo: private flag → PRIVATE when no visibility")
end

do -- empty homepage → nil homepageUrl
  local r = graphql_translate_repo({ full_name = "a/b", homepage = "" })
  ok(r.homepageUrl == nil, "translate_repo: empty homepage → nil homepageUrl")
end

do -- owner is translated through graphql_translate_owner
  local r = graphql_translate_repo(SAMPLE_REPO)
  ok(type(r.owner) == "table", "translate_repo: owner is table")
  eq(r.owner.__typename, "User", "translate_repo: owner __typename")
  eq(r.owner.login, "octocat", "translate_repo: owner login")
end

-- ============================================================
-- graphql_translate_label
-- ============================================================

do -- maps all fields
  local l = graphql_translate_label(SAMPLE_LABEL, "octocat", "Hello-World")
  eq(l.__typename, "Label", "translate_label: __typename")
  eq(l.name, "bug", "translate_label: name")
  eq(l.color, "ee0701", "translate_label: color")
  eq(l.description, "Something isn't working", "translate_label: description")
  eq(l.isDefault, true, "translate_label: isDefault")
  eq(
    l.id,
    encode_node_id("Label", "octocat/Hello-World/208045946"),
    "translate_label: node ID with context"
  )
end

do -- without owner/repo context the ID still encodes (just integer ID)
  local l = graphql_translate_label(SAMPLE_LABEL)
  eq(l.id, encode_node_id("Label", "208045946"), "translate_label: node ID without context")
end

-- ============================================================
-- graphql_translate_milestone
-- ============================================================

do -- maps all fields
  local m = graphql_translate_milestone(SAMPLE_MILESTONE, "octocat", "Hello-World")
  eq(m.__typename, "Milestone", "translate_milestone: __typename")
  eq(m.number, 1, "translate_milestone: number")
  eq(m.title, "v1.0", "translate_milestone: title")
  eq(m.state, "OPEN", "translate_milestone: state uppercased")
  eq(m.dueOn, "2012-10-09T23:39:01Z", "translate_milestone: dueOn")
  eq(m.id, encode_node_id("Milestone", "octocat/Hello-World/1"), "translate_milestone: node ID")
end

-- ============================================================
-- graphql_translate_issue
-- ============================================================

do -- maps state, author, and node ID with context
  local i = graphql_translate_issue(SAMPLE_ISSUE, "octocat", "Hello-World")
  eq(i.__typename, "Issue", "translate_issue: __typename")
  eq(i.number, 1347, "translate_issue: number")
  eq(i.title, "Found a bug", "translate_issue: title")
  eq(i.state, "OPEN", "translate_issue: state uppercased")
  eq(i.url, "https://github.com/octocat/Hello-World/issues/1347", "translate_issue: url")
  eq(
    i.id,
    encode_node_id("Issue", "octocat/Hello-World/1347"),
    "translate_issue: node ID with context"
  )
  ok(type(i.author) == "table", "translate_issue: author is table")
  eq(i.author.login, "octocat", "translate_issue: author.login")
end

do -- closed state → CLOSED
  local i =
    graphql_translate_issue({ id = 2, number = 2, state = "closed", labels = {}, assignees = {} })
  eq(i.state, "CLOSED", "translate_issue: closed → CLOSED")
end

do -- labels inline connection shape is correct
  local i = graphql_translate_issue(SAMPLE_ISSUE, "octocat", "Hello-World")
  ok(type(i.labels) == "table", "translate_issue: labels is table")
  eq(i.labels.__typename, "LabelConnection", "translate_issue: labels.__typename")
  eq(i.labels.totalCount, 1, "translate_issue: labels.totalCount")
  ok(type(i.labels.pageInfo) == "table", "translate_issue: labels.pageInfo is table")
  eq(i.labels.pageInfo.hasNextPage, false, "translate_issue: labels.pageInfo.hasNextPage = false")
  eq(
    i.labels.pageInfo.hasPreviousPage,
    false,
    "translate_issue: labels.pageInfo.hasPreviousPage = false"
  )
  ok(type(i.labels.nodes) == "table", "translate_issue: labels.nodes is table")
  eq(#i.labels.nodes, 1, "translate_issue: labels.nodes has 1 item")
  eq(i.labels.nodes[1].name, "bug", "translate_issue: labels.nodes[1].name")
end

do -- assignees inline connection shape is correct
  local i = graphql_translate_issue(SAMPLE_ISSUE, "octocat", "Hello-World")
  ok(type(i.assignees) == "table", "translate_issue: assignees is table")
  eq(i.assignees.__typename, "UserConnection", "translate_issue: assignees.__typename")
  eq(i.assignees.totalCount, 1, "translate_issue: assignees.totalCount")
  eq(
    i.assignees.pageInfo.hasNextPage,
    false,
    "translate_issue: assignees.pageInfo.hasNextPage = false"
  )
  eq(#i.assignees.nodes, 1, "translate_issue: assignees.nodes has 1 item")
  eq(i.assignees.nodes[1].login, "octocat", "translate_issue: assignees.nodes[1].login")
end

do -- comments field carries totalCount
  local i = graphql_translate_issue(SAMPLE_ISSUE)
  eq(i.comments.totalCount, 2, "translate_issue: comments.totalCount")
end

do -- milestone is translated inline
  local i = graphql_translate_issue(SAMPLE_ISSUE, "octocat", "Hello-World")
  ok(type(i.milestone) == "table", "translate_issue: milestone is table")
  eq(i.milestone.title, "v1.0", "translate_issue: milestone.title")
end

-- ============================================================
-- graphql_translate_pr
-- ============================================================

do -- maps state, ref names, and author
  local p = graphql_translate_pr(SAMPLE_PR, "octocat", "Hello-World")
  eq(p.__typename, "PullRequest", "translate_pr: __typename")
  eq(p.number, 1, "translate_pr: number")
  eq(p.title, "Amazing new feature", "translate_pr: title")
  eq(p.state, "OPEN", "translate_pr: state OPEN")
  eq(p.merged, false, "translate_pr: merged = false when merged_at nil")
  ok(p.mergedAt == nil, "translate_pr: mergedAt nil when not merged")
  eq(p.headRefName, "new-feature", "translate_pr: headRefName")
  eq(p.headRefOid, "6dcb09b5b57875f334f61aebed695e2e4193db5e", "translate_pr: headRefOid")
  eq(p.baseRefName, "master", "translate_pr: baseRefName")
  eq(p.mergeable, "MERGEABLE", "translate_pr: mergeable true → MERGEABLE")
  eq(
    p.id,
    encode_node_id("PullRequest", "octocat/Hello-World/1"),
    "translate_pr: node ID with context"
  )
end

do -- state = MERGED when merged_at is set
  local merged_pr = {}
  for k, v in pairs(SAMPLE_PR) do
    merged_pr[k] = v
  end
  merged_pr.merged_at = "2021-01-01T00:00:00Z"
  local p = graphql_translate_pr(merged_pr)
  eq(p.state, "MERGED", "translate_pr: state MERGED when merged_at set")
  eq(p.merged, true, "translate_pr: merged = true when merged_at set")
  eq(p.mergedAt, "2021-01-01T00:00:00Z", "translate_pr: mergedAt passthrough")
end

do -- closed state → CLOSED (when not merged)
  local closed_pr = {}
  for k, v in pairs(SAMPLE_PR) do
    closed_pr[k] = v
  end
  closed_pr.state = "closed"
  local p = graphql_translate_pr(closed_pr)
  eq(p.state, "CLOSED", "translate_pr: closed state → CLOSED")
end

do -- boolean mergeable false → CONFLICTING
  local conflict_pr = {}
  for k, v in pairs(SAMPLE_PR) do
    conflict_pr[k] = v
  end
  conflict_pr.mergeable = false
  local p = graphql_translate_pr(conflict_pr)
  eq(p.mergeable, "CONFLICTING", "translate_pr: mergeable false → CONFLICTING")
end

do -- string mergeable "dirty" → CONFLICTING
  local dirty_pr = {}
  for k, v in pairs(SAMPLE_PR) do
    dirty_pr[k] = v
  end
  dirty_pr.mergeable = "dirty"
  local p = graphql_translate_pr(dirty_pr)
  eq(p.mergeable, "CONFLICTING", "translate_pr: mergeable dirty → CONFLICTING")
end

do -- nil mergeable → UNKNOWN
  local unknown_pr = {}
  for k, v in pairs(SAMPLE_PR) do
    unknown_pr[k] = v
  end
  unknown_pr.mergeable = nil
  local p = graphql_translate_pr(unknown_pr)
  eq(p.mergeable, "UNKNOWN", "translate_pr: nil mergeable → UNKNOWN")
end

do -- labels and assignees are inline connections
  local p = graphql_translate_pr(SAMPLE_PR)
  eq(p.labels.__typename, "LabelConnection", "translate_pr: labels connection typename")
  eq(p.labels.totalCount, 0, "translate_pr: empty labels → totalCount 0")
  eq(p.assignees.__typename, "UserConnection", "translate_pr: assignees connection typename")
end

-- ============================================================
-- graphql_translate_comment
-- ============================================================

do -- maps fields
  local c = graphql_translate_comment({
    id = 1,
    body = "Hello!",
    user = SAMPLE_USER,
    html_url = "https://gh.com",
    created_at = "2021-01-01T00:00:00Z",
    updated_at = "2021-01-02T00:00:00Z",
  }, "octocat", "Hello-World")
  eq(c.__typename, "IssueComment", "translate_comment: __typename")
  eq(c.body, "Hello!", "translate_comment: body")
  eq(c.author.login, "octocat", "translate_comment: author.login")
  eq(c.id, encode_node_id("IssueComment", "octocat/Hello-World/1"), "translate_comment: node ID")
end

-- ============================================================
-- graphql_translate_commit
-- ============================================================

do -- maps SHA, message, and headline
  local c = graphql_translate_commit({
    sha = "abc123",
    commit = {
      message = "Fix the bug\n\nLonger description here.",
      author = { name = "Alice", email = "alice@example.com", date = "2021-01-01T00:00:00Z" },
      committer = { name = "Bob", email = "bob@example.com", date = "2021-01-01T00:00:00Z" },
    },
    html_url = "https://github.com/octocat/Hello-World/commit/abc123",
  })
  eq(c.__typename, "Commit", "translate_commit: __typename")
  eq(c.oid, "abc123", "translate_commit: oid")
  eq(c.message, "Fix the bug\n\nLonger description here.", "translate_commit: message")
  eq(c.messageHeadline, "Fix the bug", "translate_commit: messageHeadline is first line")
  eq(c.author.name, "Alice", "translate_commit: author.name")
  eq(c.author.email, "alice@example.com", "translate_commit: author.email")
  eq(c.id, encode_node_id("Commit", "abc123"), "translate_commit: id")
  eq(c.url, "https://github.com/octocat/Hello-World/commit/abc123", "translate_commit: url")
end

-- ============================================================
-- graphql_translate_ref
-- ============================================================

do -- branches shape (name + commit.sha)
  local repo = { nameWithOwner = "octocat/Hello-World" }
  local r = graphql_translate_ref({ name = "main", commit = { sha = "abc123" } }, repo)
  eq(r.__typename, "Ref", "translate_ref: __typename")
  eq(r.name, "main", "translate_ref: name")
  eq(r.prefix, "refs/heads/", "translate_ref: prefix inferred from branches shape")
  ok(type(r.target) == "table", "translate_ref: target is table")
  eq(r.target.oid, "abc123", "translate_ref: target.oid")
  eq(r.id, encode_node_id("Ref", "octocat/Hello-World/refs/heads/main"), "translate_ref: id")
end

do -- git/refs shape (ref + object.sha)
  local repo = { nameWithOwner = "octocat/Hello-World" }
  local r = graphql_translate_ref({ ref = "refs/tags/v1.0", object = { sha = "def456" } }, repo)
  eq(r.name, "v1.0", "translate_ref: git/refs shape name")
  eq(r.prefix, "refs/tags/", "translate_ref: git/refs shape prefix")
  eq(r.target.oid, "def456", "translate_ref: git/refs shape target.oid")
end

-- ============================================================
-- graphql_translate_release
-- ============================================================

do -- maps all fields
  local r = graphql_translate_release({
    id = 1,
    tag_name = "v1.0.0",
    name = "v1.0.0",
    body = "Release notes",
    draft = false,
    prerelease = false,
    created_at = "2013-02-27T19:35:32Z",
    published_at = "2013-02-27T19:35:32Z",
    html_url = "https://github.com/octocat/Hello-World/releases/tag/v1.0.0",
    author = SAMPLE_USER,
  }, "octocat", "Hello-World")
  eq(r.__typename, "Release", "translate_release: __typename")
  eq(r.tagName, "v1.0.0", "translate_release: tagName")
  eq(r.isDraft, false, "translate_release: isDraft")
  eq(r.isPrerelease, false, "translate_release: isPrerelease")
  eq(r.description, "Release notes", "translate_release: description")
  eq(r.author.login, "octocat", "translate_release: author.login")
  eq(r.id, encode_node_id("Release", "octocat/Hello-World/1"), "translate_release: node ID")
end

-- ============================================================
-- graphql_translate_reaction
-- ============================================================

do -- maps content string to SCREAMING_SNAKE_CASE enum
  local r = graphql_translate_reaction({
    id = 1,
    content = "+1",
    user = SAMPLE_USER,
    created_at = "2016-05-20T20:09:31Z",
  })
  eq(r.__typename, "Reaction", "translate_reaction: __typename")
  eq(r.content, "THUMBS_UP", "translate_reaction: +1 → THUMBS_UP")
  eq(r.user.login, "octocat", "translate_reaction: user.login")
  eq(r.id, encode_node_id("Reaction", "1"), "translate_reaction: id")
end

do -- heart content
  local r = graphql_translate_reaction({ id = 2, content = "heart" })
  eq(r.content, "HEART", "translate_reaction: heart → HEART")
end

do -- -1 content
  local r = graphql_translate_reaction({ id = 3, content = "-1" })
  eq(r.content, "THUMBS_DOWN", "translate_reaction: -1 → THUMBS_DOWN")
end
