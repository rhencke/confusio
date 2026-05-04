-- Shared translators (global: backends/<name>.lua uses them).
--
-- owner_repo_id    — URL-encode owner/repo as "owner%2Frepo"
-- translate_repo   — map a Gitea-style repo object to GitHub field names
-- translate_user   — map a Gitea-style user object to GitHub field names
-- translate_migration — map a backend migration object to GitHub field names

-- owner_repo_id is global: URL-encodes owner/repo as "owner%2Frepo".
-- Used by backends (GitLab, Gerrit, Harness) whose APIs address repositories
-- by a URL-encoded "owner/repo" composite identifier rather than separate segments.
function owner_repo_id(owner, repo_name)
  return owner .. "%2F" .. repo_name
end

local translate_repo_owner = make_translator({
  login = "login",
  id = "id",
  node_id = const(""),
  avatar_url = "avatar_url",
  url = "url",
  html_url = "html_url",
  type = computed(function(owner)
    return owner.type or (owner.is_admin and "Admin" or "User")
  end),
})

translate_repo = make_translator({
  id = "id",
  node_id = const(""),
  name = "name",
  full_name = "full_name",
  private = "private",
  owner = computed(function(r)
    return translate_repo_owner(r.owner or {})
  end),
  html_url = "html_url",
  description = "description",
  fork = "fork",
  url = "url",
  git_url = "ssh_url",
  ssh_url = "ssh_url",
  clone_url = "clone_url",
  homepage = "website",
  size = "size",
  stargazers_count = "stars_count",
  watchers_count = "watchers_count",
  language = "language",
  has_issues = "has_issues",
  has_wiki = "has_wiki",
  forks_count = "forks_count",
  archived = "archived",
  disabled = const(false),
  open_issues_count = "open_issues_count",
  default_branch = "default_branch",
  visibility = computed(function(r)
    return r.visibility or (r.private and "private" or "public")
  end),
  forks = "forks_count",
  open_issues = "open_issues_count",
  watchers = "watchers_count",
  created_at = "created",
  updated_at = "updated",
  pushed_at = "updated",
  permissions = "permissions",
})

translate_user = make_translator({
  login = "login",
  id = "id",
  node_id = const(""),
  avatar_url = "avatar_url",
  html_url = "html_url",
  type = const("User"),
  site_admin = field("is_admin", { default = false }),
  name = "full_name",
  email = "email",
  location = "location",
  blog = "website",
  followers = computed(function(u)
    return u.followers_count or 0
  end),
  following = computed(function(u)
    return u.following_count or 0
  end),
  created_at = "created",
})

-- translate_migration is global: maps a backend migration object to GitHub field names.
-- The GitHub migration schema: https://docs.github.com/en/rest/migrations
-- Required fields: id, node_id, owner, guid, state, lock_repositories,
--   exclude_metadata, exclude_git_data, exclude_attachments, exclude_releases,
--   exclude_owner_projects, org_metadata_only, repositories, url, created_at, updated_at.
-- Optional fields: archive_url, exclude.
translate_migration = make_translator({
  id = "id",
  node_id = computed(function(m)
    return m.node_id or ""
  end),
  owner = "owner",
  guid = computed(function(m)
    return m.guid or ""
  end),
  state = computed(function(m)
    return m.state or "pending"
  end),
  lock_repositories = field("lock_repositories", { default = false }),
  exclude_metadata = field("exclude_metadata", { default = false }),
  exclude_git_data = field("exclude_git_data", { default = false }),
  exclude_attachments = field("exclude_attachments", { default = false }),
  exclude_releases = field("exclude_releases", { default = false }),
  exclude_owner_projects = field("exclude_owner_projects", { default = false }),
  org_metadata_only = field("org_metadata_only", { default = false }),
  repositories = computed(function(m)
    return m.repositories or {}
  end),
  url = computed(function(m)
    return m.url or ""
  end),
  created_at = computed(function(m)
    return m.created_at or ""
  end),
  updated_at = computed(function(m)
    return m.updated_at or ""
  end),
  archive_url = "archive_url",
  exclude = computed(function(m)
    return m.exclude or {}
  end),
})
