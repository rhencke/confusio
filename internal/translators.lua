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

-- translate_repo is global: maps a Gitea-style repo object to GitHub field names.
-- Called by any Gitea-API-compatible backend (gitea, forgejo, gogs, codeberg, notabug).
function translate_repo(r)
  if not r then
    return {}
  end
  local owner = r.owner or {}
  return {
    id = r.id,
    node_id = "",
    name = r.name,
    full_name = r.full_name,
    private = r.private,
    owner = {
      login = owner.login,
      id = owner.id,
      node_id = "",
      avatar_url = owner.avatar_url,
      url = owner.url,
      html_url = owner.html_url,
      type = owner.type or (owner.is_admin and "Admin" or "User"),
    },
    html_url = r.html_url,
    description = r.description,
    fork = r.fork,
    url = r.url,
    git_url = r.ssh_url,
    ssh_url = r.ssh_url,
    clone_url = r.clone_url,
    homepage = r.website,
    size = r.size,
    stargazers_count = r.stars_count,
    watchers_count = r.watchers_count,
    language = r.language,
    has_issues = r.has_issues,
    has_wiki = r.has_wiki,
    forks_count = r.forks_count,
    archived = r.archived,
    disabled = false,
    open_issues_count = r.open_issues_count,
    default_branch = r.default_branch,
    visibility = r.visibility or (r.private and "private" or "public"),
    forks = r.forks_count,
    open_issues = r.open_issues_count,
    watchers = r.watchers_count,
    created_at = r.created,
    updated_at = r.updated,
    pushed_at = r.updated,
    permissions = r.permissions,
  }
end

-- translate_user is global: maps a Gitea-style user object to GitHub field names.
-- Called by any Gitea-API-compatible backend (gitea, forgejo, gogs, codeberg, notabug).
function translate_user(u)
  if not u then
    return {}
  end
  return {
    login = u.login,
    id = u.id,
    node_id = "",
    avatar_url = u.avatar_url,
    html_url = u.html_url,
    type = "User",
    site_admin = u.is_admin or false,
    name = u.full_name,
    email = u.email,
    location = u.location,
    blog = u.website,
    followers = u.followers_count or 0,
    following = u.following_count or 0,
    created_at = u.created,
  }
end

-- translate_migration is global: maps a backend migration object to GitHub field names.
-- The GitHub migration schema: https://docs.github.com/en/rest/migrations
-- Required fields: id, node_id, owner, guid, state, lock_repositories,
--   exclude_metadata, exclude_git_data, exclude_attachments, exclude_releases,
--   exclude_owner_projects, org_metadata_only, repositories, url, created_at, updated_at.
-- Optional fields: archive_url, exclude.
function translate_migration(m)
  if not m then
    return {}
  end
  return {
    id = m.id,
    node_id = m.node_id or "",
    owner = m.owner,
    guid = m.guid or "",
    state = m.state or "pending",
    lock_repositories = m.lock_repositories or false,
    exclude_metadata = m.exclude_metadata or false,
    exclude_git_data = m.exclude_git_data or false,
    exclude_attachments = m.exclude_attachments or false,
    exclude_releases = m.exclude_releases or false,
    exclude_owner_projects = m.exclude_owner_projects or false,
    org_metadata_only = m.org_metadata_only or false,
    repositories = m.repositories or {},
    url = m.url or "",
    created_at = m.created_at or "",
    updated_at = m.updated_at or "",
    archive_url = m.archive_url,
    exclude = m.exclude or {},
  }
end
