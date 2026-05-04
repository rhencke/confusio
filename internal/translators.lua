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
  type = computed(function(owner)
    return owner.type or (owner.is_admin and "Admin" or "User")
  end),
  copy_fields("login", "id", "avatar_url", "url"),
  copy_fields("html_url"),
  const_fields("", "node_id"),
})

translate_repo = make_translator({
  owner = computed(function(r)
    return translate_repo_owner(r.owner or {})
  end),
  git_url = "ssh_url",
  homepage = "website",
  stargazers_count = "stars_count",
  visibility = computed(function(r)
    return r.visibility or (r.private and "private" or "public")
  end),
  forks = "forks_count",
  open_issues = "open_issues_count",
  watchers = "watchers_count",
  created_at = "created",
  updated_at = "updated",
  pushed_at = "updated",
  copy_fields("id", "name", "full_name", "private"),
  copy_fields("html_url", "description", "fork", "url"),
  copy_fields("ssh_url", "clone_url", "size", "watchers_count"),
  copy_fields("language", "has_issues", "has_wiki", "forks_count"),
  copy_fields("archived", "open_issues_count", "default_branch", "permissions"),
  const_fields("", "node_id"),
  const_fields(false, "disabled"),
})

translate_user = make_translator({
  site_admin = field("is_admin", { default = false }),
  name = "full_name",
  blog = "website",
  followers = computed(function(u)
    return u.followers_count or 0
  end),
  following = computed(function(u)
    return u.following_count or 0
  end),
  created_at = "created",
  copy_fields("login", "id", "avatar_url", "html_url"),
  copy_fields("email", "location"),
  const_fields("", "node_id"),
  const_fields("User", "type"),
})

-- translate_migration is global: maps a backend migration object to GitHub field names.
-- The GitHub migration schema: https://docs.github.com/en/rest/migrations
-- Required fields: id, node_id, owner, guid, state, lock_repositories,
--   exclude_metadata, exclude_git_data, exclude_attachments, exclude_releases,
--   exclude_owner_projects, org_metadata_only, repositories, url, created_at, updated_at.
-- Optional fields: archive_url, exclude.
translate_migration = make_translator({
  node_id = computed(function(m)
    return m.node_id or ""
  end),
  guid = computed(function(m)
    return m.guid or ""
  end),
  state = computed(function(m)
    return m.state or "pending"
  end),
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
  exclude = computed(function(m)
    return m.exclude or {}
  end),
  copy_fields("id", "owner", "archive_url"),
  default_fields(
    false,
    "lock_repositories",
    "exclude_metadata",
    "exclude_git_data",
    "exclude_attachments"
  ),
  default_fields(false, "exclude_releases", "exclude_owner_projects", "org_metadata_only"),
})
