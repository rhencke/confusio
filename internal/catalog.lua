-- Endpoint catalog (populates global `endpoints` and registers all routes).
--
-- Requires: defaults (internal/defaults.lua), route_add (internal/router.lua).
--
-- ---------------------------------------------------------------------------
-- Endpoint catalog
--
-- Authoritative source for every registered endpoint, organised by API
-- group. Each section is { group_name, { entries... } } where each entry is
-- { "METHOD /path", handler_name [, default_fn] }.
--
-- group_name matches the test file suffix (<backend>-<group>.hurl) and the
-- compatibility matrix sections in site/compatibility.csv.
--
-- Backends override handlers by setting app.backend.rest.<name>. Parametric
-- captures from {param} segments are passed positionally to the handler.
-- ---------------------------------------------------------------------------

local endpoint_sections = {
  {
    "graphql",
    {
      -- GraphQL API (https://docs.github.com/en/graphql)
      -- graphql_handler is the fixed handler; backends register resolvers via b:graphql().
      { "POST /graphql", "graphql_request", graphql_handler },
    },
  },
  {
    "webhooks",
    {
      -- Webhook receive pipeline (confusio-specific; not part of the GitHub REST API spec).
      -- The real handler is installed as app.webhook_receiver by .init.lua and intercepted
      -- by dispatch.lua before routing.  This catalog entry drives validate-csv/validate-tests
      -- coverage tracking; the default stub is never reached in normal operation.
      {
        "POST /webhooks/{backend}",
        "post_webhooks_backend",
        defaults.webhook_receive_stub,
      },
    },
  },
  {
    "meta",
    {
      -- Root
      {
        "GET /",
        "get_root",
        function()
          respond_json(200, {})
        end,
      },

      -- Meta (https://docs.github.com/en/rest/meta)
      { "GET /meta", "get_meta", defaults.meta_response },
      { "GET /octocat", "get_octocat", defaults.octocat_response },
      { "GET /teapot", "get_teapot", defaults.teapot_response },
      { "GET /versions", "get_versions", defaults.versions_response },
      { "GET /zen", "get_zen", defaults.zen_response },

      -- Emojis
      { "GET /emojis", "get_emojis" },
    },
  },
  {
    "gitignore",
    {
      -- Gitignore templates (https://docs.github.com/en/rest/gitignore)
      { "GET /gitignore/templates", "get_gitignore_templates" },
      { "GET /gitignore/templates/{name}", "get_gitignore_template" },
    },
  },
  {
    "licenses",
    {
      -- Licenses (https://docs.github.com/en/rest/licenses)
      { "GET /licenses", "get_licenses", defaults.licenses_not_implemented },
      { "GET /licenses/{license}", "get_license", defaults.licenses_not_implemented },

      -- Repo license (https://docs.github.com/en/rest/licenses)
      {
        "GET /repos/{owner}/{repo}/license",
        "get_repo_license",
        defaults.licenses_not_implemented,
      },
    },
  },
  {
    "rate-limit",
    {
      -- Rate Limits (https://docs.github.com/en/rest/rate-limit)
      { "GET /rate_limit", "get_rate_limit", defaults.rate_limit_response },
    },
  },
  {
    "gists",
    {
      -- Gists (https://docs.github.com/en/rest/gists)
      { "GET /gists", "get_gists", defaults.empty_list },
      { "POST /gists", "post_gists", defaults.gists_not_implemented },
      { "GET /gists/public", "get_gists_public", defaults.empty_list },
      { "GET /gists/starred", "get_gists_starred", defaults.empty_list },
      { "GET /gists/{gist_id}", "get_gist", defaults.gists_not_implemented },
      { "PATCH /gists/{gist_id}", "patch_gist", defaults.gists_not_implemented },
      { "DELETE /gists/{gist_id}", "delete_gist", defaults.gists_not_implemented },
      { "GET /gists/{gist_id}/comments", "get_gist_comments", defaults.empty_list },
      { "POST /gists/{gist_id}/comments", "post_gist_comment", defaults.gists_not_implemented },
      {
        "GET /gists/{gist_id}/comments/{comment_id}",
        "get_gist_comment",
        defaults.gists_not_implemented,
      },
      {
        "PATCH /gists/{gist_id}/comments/{comment_id}",
        "patch_gist_comment",
        defaults.gists_not_implemented,
      },
      {
        "DELETE /gists/{gist_id}/comments/{comment_id}",
        "delete_gist_comment",
        defaults.gists_not_implemented,
      },
      { "GET /gists/{gist_id}/commits", "get_gist_commits", defaults.empty_list },
      { "GET /gists/{gist_id}/forks", "get_gist_forks", defaults.empty_list },
      { "POST /gists/{gist_id}/forks", "post_gist_fork", defaults.gists_not_implemented },
      { "GET /gists/{gist_id}/star", "get_gist_star", defaults.gists_not_implemented },
      { "PUT /gists/{gist_id}/star", "put_gist_star", defaults.gists_not_implemented },
      { "DELETE /gists/{gist_id}/star", "delete_gist_star", defaults.gists_not_implemented },
      { "GET /gists/{gist_id}/{sha}", "get_gist_revision", defaults.gists_not_implemented },
      { "GET /users/{username}/gists", "get_user_gists", defaults.empty_list },
    },
  },
  {
    "activity",
    {
      -- Activity (https://docs.github.com/en/rest/activity)
      { "GET /events", "get_events", defaults.activity_list_empty },
      { "GET /feeds", "get_feeds", defaults.activity_not_implemented },
      { "GET /networks/{owner}/{repo}/events", "get_network_events", defaults.activity_list_empty },
      { "GET /notifications", "get_notifications", defaults.activity_list_empty },
      { "PUT /notifications", "put_notifications", defaults.activity_not_implemented },
      {
        "GET /notifications/threads/{thread_id}",
        "get_notification_thread",
        defaults.activity_not_implemented,
      },
      {
        "PATCH /notifications/threads/{thread_id}",
        "patch_notification_thread",
        defaults.activity_not_implemented,
      },
      {
        "DELETE /notifications/threads/{thread_id}",
        "delete_notification_thread",
        defaults.activity_not_implemented,
      },
      {
        "GET /notifications/threads/{thread_id}/subscription",
        "get_notification_thread_subscription",
        defaults.activity_not_implemented,
      },
      {
        "PUT /notifications/threads/{thread_id}/subscription",
        "put_notification_thread_subscription",
        defaults.activity_not_implemented,
      },
      {
        "DELETE /notifications/threads/{thread_id}/subscription",
        "delete_notification_thread_subscription",
        defaults.activity_not_implemented,
      },
      { "GET /orgs/{org}/events", "get_org_events", defaults.activity_list_empty },
      { "GET /repos/{owner}/{repo}/events", "get_repo_events", defaults.activity_list_empty },
      {
        "GET /repos/{owner}/{repo}/notifications",
        "get_repo_notifications",
        defaults.activity_list_empty,
      },
      {
        "PUT /repos/{owner}/{repo}/notifications",
        "put_repo_notifications",
        defaults.activity_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/stargazers",
        "get_repo_stargazers",
        defaults.activity_list_empty,
      },
      {
        "GET /repos/{owner}/{repo}/subscribers",
        "get_repo_subscribers",
        defaults.activity_list_empty,
      },
      {
        "GET /repos/{owner}/{repo}/subscription",
        "get_repo_subscription",
        defaults.activity_not_implemented,
      },
      {
        "PUT /repos/{owner}/{repo}/subscription",
        "put_repo_subscription",
        defaults.activity_not_implemented,
      },
      {
        "DELETE /repos/{owner}/{repo}/subscription",
        "delete_repo_subscription",
        defaults.activity_not_implemented,
      },
      { "GET /user/starred", "get_user_starred", defaults.activity_list_empty },
      {
        "GET /user/starred/{owner}/{repo}",
        "get_user_starred_repo",
        defaults.activity_not_implemented,
      },
      {
        "PUT /user/starred/{owner}/{repo}",
        "put_user_starred_repo",
        defaults.activity_not_implemented,
      },
      {
        "DELETE /user/starred/{owner}/{repo}",
        "delete_user_starred_repo",
        defaults.activity_not_implemented,
      },
      { "GET /user/subscriptions", "get_user_subscriptions", defaults.activity_list_empty },
      { "GET /users/{username}/events", "get_users_events", defaults.activity_list_empty },
      {
        "GET /users/{username}/events/orgs/{org}",
        "get_users_org_events",
        defaults.activity_list_empty,
      },
      {
        "GET /users/{username}/events/public",
        "get_users_public_events",
        defaults.activity_list_empty,
      },
      {
        "GET /users/{username}/received_events",
        "get_users_received_events",
        defaults.activity_list_empty,
      },
      {
        "GET /users/{username}/received_events/public",
        "get_users_received_public_events",
        defaults.activity_list_empty,
      },
      { "GET /users/{username}/starred", "get_users_starred", defaults.activity_list_empty },
      {
        "GET /users/{username}/subscriptions",
        "get_users_subscriptions",
        defaults.activity_list_empty,
      },
    },
  },
  {
    "repos",
    {
      -- Repos core (https://docs.github.com/en/rest/repos/repos)
      { "GET /repos/{owner}/{repo}", "get_repo" },
      { "PATCH /repos/{owner}/{repo}", "patch_repo" },
      { "DELETE /repos/{owner}/{repo}", "delete_repo" },
      { "GET /user/repos", "get_user_repos" },
      { "POST /user/repos", "post_user_repos" },
      { "GET /orgs/{org}/repos", "get_org_repos" },
      { "POST /orgs/{org}/repos", "post_org_repos" },
      { "GET /users/{username}/repos", "get_users_repos" },
      { "GET /repositories", "get_repositories" },

      -- Topics / languages / contributors / tags / teams
      { "GET /repos/{owner}/{repo}/topics", "get_repo_topics" },
      { "PUT /repos/{owner}/{repo}/topics", "put_repo_topics" },
      { "GET /repos/{owner}/{repo}/languages", "get_repo_languages" },
      { "GET /repos/{owner}/{repo}/contributors", "get_repo_contributors" },
      { "GET /repos/{owner}/{repo}/tags", "get_repo_tags" },
      { "GET /repos/{owner}/{repo}/teams", "get_repo_teams" },
    },
  },
  {
    "repos-ext",
    {
      -- Branches (https://docs.github.com/en/rest/branches)
      { "GET /repos/{owner}/{repo}/branches", "get_repo_branches" },
      { "GET /repos/{owner}/{repo}/branches/{branch}", "get_repo_branch" },

      -- Commits (https://docs.github.com/en/rest/commits)
      { "GET /repos/{owner}/{repo}/commits", "get_repo_commits" },
      { "GET /repos/{owner}/{repo}/commits/{ref}", "get_repo_commit" },

      -- Commit comments
      { "GET /repos/{owner}/{repo}/comments", "get_repo_comments" },
      { "GET /repos/{owner}/{repo}/comments/{comment_id}", "get_repo_comment" },
      { "PATCH /repos/{owner}/{repo}/comments/{comment_id}", "patch_repo_comment" },
      { "DELETE /repos/{owner}/{repo}/comments/{comment_id}", "delete_repo_comment" },
      { "GET /repos/{owner}/{repo}/commits/{commit_sha}/comments", "get_commit_comments" },
      { "POST /repos/{owner}/{repo}/commits/{commit_sha}/comments", "post_commit_comment" },

      -- Statuses
      { "GET /repos/{owner}/{repo}/commits/{ref}/statuses", "get_commit_statuses" },
      { "GET /repos/{owner}/{repo}/commits/{ref}/status", "get_commit_combined_status" },
      { "POST /repos/{owner}/{repo}/statuses/{sha}", "post_commit_status" },

      -- Contents (https://docs.github.com/en/rest/repos/contents)
      { "GET /repos/{owner}/{repo}/readme", "get_repo_readme" },
      { "GET /repos/{owner}/{repo}/readme/{dir}", "get_repo_readme_dir" },
      { "GET /repos/{owner}/{repo}/contents/{path}", "get_repo_content" },
      { "PUT /repos/{owner}/{repo}/contents/{path}", "put_repo_content" },
      { "DELETE /repos/{owner}/{repo}/contents/{path}", "delete_repo_content" },
      { "GET /repos/{owner}/{repo}/tarball/{ref}", "get_repo_tarball" },
      { "GET /repos/{owner}/{repo}/zipball/{ref}", "get_repo_zipball" },

      -- Compare
      { "GET /repos/{owner}/{repo}/compare/{basehead}", "get_repo_compare" },

      -- Collaborators (https://docs.github.com/en/rest/collaborators)
      { "GET /repos/{owner}/{repo}/collaborators", "get_repo_collaborators" },
      { "GET /repos/{owner}/{repo}/collaborators/{username}", "get_repo_collaborator" },
      { "PUT /repos/{owner}/{repo}/collaborators/{username}", "put_repo_collaborator" },
      { "DELETE /repos/{owner}/{repo}/collaborators/{username}", "delete_repo_collaborator" },
      {
        "GET /repos/{owner}/{repo}/collaborators/{username}/permission",
        "get_repo_collaborator_permission",
      },

      -- Forks (https://docs.github.com/en/rest/repos/forks)
      { "GET /repos/{owner}/{repo}/forks", "get_repo_forks" },
      { "POST /repos/{owner}/{repo}/forks", "post_repo_forks" },

      -- Merges (https://docs.github.com/en/rest/branches/merging)
      { "POST /repos/{owner}/{repo}/merges", "post_repo_merges" },
      { "POST /repos/{owner}/{repo}/merge-upstream", "post_repo_merge_upstream" },

      -- Deploy keys (https://docs.github.com/en/rest/deploy-keys)
      { "GET /repos/{owner}/{repo}/keys", "get_repo_keys" },
      { "POST /repos/{owner}/{repo}/keys", "post_repo_keys" },
      { "GET /repos/{owner}/{repo}/keys/{key_id}", "get_repo_key" },
      { "DELETE /repos/{owner}/{repo}/keys/{key_id}", "delete_repo_key" },

      -- Webhooks (https://docs.github.com/en/rest/repos/webhooks)
      { "GET /repos/{owner}/{repo}/hooks", "get_repo_hooks", defaults.hooks_empty_list },
      { "POST /repos/{owner}/{repo}/hooks", "post_repo_hooks", defaults.hooks_not_implemented },
      { "GET /repos/{owner}/{repo}/hooks/{hook_id}", "get_repo_hook", defaults.hook_not_found },
      {
        "PATCH /repos/{owner}/{repo}/hooks/{hook_id}",
        "patch_repo_hook",
        defaults.hook_not_found,
      },
      {
        "DELETE /repos/{owner}/{repo}/hooks/{hook_id}",
        "delete_repo_hook",
        defaults.hook_not_found,
      },
      {
        "GET /repos/{owner}/{repo}/hooks/{hook_id}/config",
        "get_repo_hook_config",
        defaults.hook_not_found,
      },
      {
        "PATCH /repos/{owner}/{repo}/hooks/{hook_id}/config",
        "patch_repo_hook_config",
        defaults.hook_not_found,
      },
      {
        "GET /repos/{owner}/{repo}/hooks/{hook_id}/deliveries",
        "get_repo_hook_deliveries",
        defaults.hooks_empty_list,
      },
      {
        "GET /repos/{owner}/{repo}/hooks/{hook_id}/deliveries/{delivery_id}",
        "get_repo_hook_delivery",
        defaults.hook_not_found,
      },
      {
        "POST /repos/{owner}/{repo}/hooks/{hook_id}/deliveries/{delivery_id}/attempts",
        "post_repo_hook_delivery_attempt",
        defaults.hooks_not_implemented,
      },
      {
        "POST /repos/{owner}/{repo}/hooks/{hook_id}/pings",
        "post_repo_hook_ping",
        defaults.hook_ping,
      },
      {
        "POST /repos/{owner}/{repo}/hooks/{hook_id}/tests",
        "post_repo_hook_test",
        defaults.hook_ping,
      },

      -- Statistics (https://docs.github.com/en/rest/metrics/statistics)
      { "GET /repos/{owner}/{repo}/stats/code_frequency", "get_repo_stats_code_frequency" },
      { "GET /repos/{owner}/{repo}/stats/commit_activity", "get_repo_stats_commit_activity" },
      { "GET /repos/{owner}/{repo}/stats/contributors", "get_repo_stats_contributors" },
      { "GET /repos/{owner}/{repo}/stats/participation", "get_repo_stats_participation" },
      { "GET /repos/{owner}/{repo}/stats/punch_card", "get_repo_stats_punch_card" },

      -- Traffic (https://docs.github.com/en/rest/metrics/traffic)
      { "GET /repos/{owner}/{repo}/traffic/clones", "get_repo_traffic_clones" },
      { "GET /repos/{owner}/{repo}/traffic/popular/paths", "get_repo_traffic_paths" },
      { "GET /repos/{owner}/{repo}/traffic/popular/referrers", "get_repo_traffic_referrers" },
      { "GET /repos/{owner}/{repo}/traffic/views", "get_repo_traffic_views" },

      -- Invitations (https://docs.github.com/en/rest/collaborators/invitations)
      { "GET /repos/{owner}/{repo}/invitations", "get_repo_invitations" },
      { "PATCH /repos/{owner}/{repo}/invitations/{invitation_id}", "patch_repo_invitation" },
      { "DELETE /repos/{owner}/{repo}/invitations/{invitation_id}", "delete_repo_invitation" },
      { "GET /user/repository_invitations", "get_user_repo_invitations" },
      { "PATCH /user/repository_invitations/{invitation_id}", "patch_user_repo_invitation" },
      { "DELETE /user/repository_invitations/{invitation_id}", "delete_user_repo_invitation" },

      -- Deployments (https://docs.github.com/en/rest/deployments)
      { "GET /repos/{owner}/{repo}/deployments", "get_repo_deployments" },
      { "POST /repos/{owner}/{repo}/deployments", "post_repo_deployments" },
      { "GET /repos/{owner}/{repo}/deployments/{deployment_id}", "get_repo_deployment" },
      { "DELETE /repos/{owner}/{repo}/deployments/{deployment_id}", "delete_repo_deployment" },
      {
        "GET /repos/{owner}/{repo}/deployments/{deployment_id}/statuses",
        "get_repo_deployment_statuses",
      },
      {
        "POST /repos/{owner}/{repo}/deployments/{deployment_id}/statuses",
        "post_repo_deployment_status",
      },
      {
        "GET /repos/{owner}/{repo}/deployments/{deployment_id}/statuses/{status_id}",
        "get_repo_deployment_status",
      },
    },
  },
  {
    "releases",
    {
      -- Releases (https://docs.github.com/en/rest/releases)
      { "GET /repos/{owner}/{repo}/releases", "get_repo_releases" },
      { "POST /repos/{owner}/{repo}/releases", "post_repo_releases" },
      { "GET /repos/{owner}/{repo}/releases/latest", "get_repo_release_latest" },
      { "GET /repos/{owner}/{repo}/releases/tags/{tag}", "get_repo_release_by_tag" },
      { "GET /repos/{owner}/{repo}/releases/{release_id}", "get_repo_release" },
      { "PATCH /repos/{owner}/{repo}/releases/{release_id}", "patch_repo_release" },
      { "DELETE /repos/{owner}/{repo}/releases/{release_id}", "delete_repo_release" },
      { "GET /repos/{owner}/{repo}/releases/{release_id}/assets", "get_repo_release_assets" },
      { "POST /repos/{owner}/{repo}/releases/{release_id}/assets", "post_repo_release_assets" },
      { "GET /repos/{owner}/{repo}/releases/assets/{asset_id}", "get_repo_release_asset" },
      { "PATCH /repos/{owner}/{repo}/releases/assets/{asset_id}", "patch_repo_release_asset" },
      { "DELETE /repos/{owner}/{repo}/releases/assets/{asset_id}", "delete_repo_release_asset" },
    },
  },
  {
    "teams",
    {
      -- Teams (https://docs.github.com/en/rest/teams)
      { "GET /orgs/{org}/teams", "get_org_teams", defaults.empty_list },
      { "POST /orgs/{org}/teams", "post_org_teams" },
      { "GET /orgs/{org}/teams/{team_slug}", "get_org_team" },
      { "PATCH /orgs/{org}/teams/{team_slug}", "patch_org_team" },
      { "DELETE /orgs/{org}/teams/{team_slug}", "delete_org_team" },
      {
        "GET /orgs/{org}/teams/{team_slug}/invitations",
        "get_org_team_invitations",
        defaults.empty_list,
      },
      { "GET /orgs/{org}/teams/{team_slug}/members", "get_org_team_members", defaults.empty_list },
      { "GET /orgs/{org}/teams/{team_slug}/memberships/{username}", "get_org_team_membership" },
      { "PUT /orgs/{org}/teams/{team_slug}/memberships/{username}", "put_org_team_membership" },
      {
        "DELETE /orgs/{org}/teams/{team_slug}/memberships/{username}",
        "delete_org_team_membership",
      },
      { "GET /orgs/{org}/teams/{team_slug}/repos", "get_org_team_repos", defaults.empty_list },
      { "GET /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}", "get_org_team_repo" },
      { "PUT /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}", "put_org_team_repo" },
      { "DELETE /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}", "delete_org_team_repo" },
      { "GET /orgs/{org}/teams/{team_slug}/teams", "get_org_team_children", defaults.empty_list },

      -- Legacy team endpoints (team_id-based) — deprecated in favour of slug-based above
      { "GET /user/teams", "get_user_teams", defaults.empty_list },
      { "GET /teams/{team_id}", "get_team" },
      { "PATCH /teams/{team_id}", "patch_team" },
      { "DELETE /teams/{team_id}", "delete_team" },
      { "GET /teams/{team_id}/invitations", "get_team_invitations", defaults.empty_list },
      { "GET /teams/{team_id}/members", "get_team_members", defaults.empty_list },
      { "GET /teams/{team_id}/members/{username}", "get_team_member" },
      { "PUT /teams/{team_id}/members/{username}", "put_team_member" },
      { "DELETE /teams/{team_id}/members/{username}", "delete_team_member" },
      { "GET /teams/{team_id}/memberships/{username}", "get_team_membership" },
      { "PUT /teams/{team_id}/memberships/{username}", "put_team_membership" },
      { "DELETE /teams/{team_id}/memberships/{username}", "delete_team_membership" },
      { "GET /teams/{team_id}/repos", "get_team_repos", defaults.empty_list },
      { "GET /teams/{team_id}/repos/{owner}/{repo}", "get_team_repo" },
      { "PUT /teams/{team_id}/repos/{owner}/{repo}", "put_team_repo" },
      { "DELETE /teams/{team_id}/repos/{owner}/{repo}", "delete_team_repo" },
      { "GET /teams/{team_id}/teams", "get_team_children", defaults.empty_list },
    },
  },
  {
    "security-advisories",
    {
      -- Security advisories (https://docs.github.com/en/rest/security-advisories)
      { "GET /advisories", "get_global_advisories", defaults.empty_list },
      { "GET /advisories/{ghsa_id}", "get_global_advisory" },
      { "GET /orgs/{org}/security-advisories", "get_org_security_advisories", defaults.empty_list },
      {
        "GET /repos/{owner}/{repo}/security-advisories",
        "get_repo_security_advisories",
        defaults.empty_list,
      },
      { "POST /repos/{owner}/{repo}/security-advisories", "post_repo_security_advisory" },
      {
        "POST /repos/{owner}/{repo}/security-advisories/reports",
        "post_repo_security_advisory_report",
      },
      { "GET /repos/{owner}/{repo}/security-advisories/{ghsa_id}", "get_repo_security_advisory" },
      {
        "PATCH /repos/{owner}/{repo}/security-advisories/{ghsa_id}",
        "patch_repo_security_advisory",
      },
      {
        "POST /repos/{owner}/{repo}/security-advisories/{ghsa_id}/cve",
        "post_repo_security_advisory_cve",
      },
      {
        "POST /repos/{owner}/{repo}/security-advisories/{ghsa_id}/forks",
        "post_repo_security_advisory_fork",
      },
    },
  },
  {
    "issues",
    {
      -- Issues (https://docs.github.com/en/rest/issues)
      { "GET /issues", "get_issues", defaults.empty_list },
      { "GET /orgs/{org}/issues", "get_org_issues", defaults.empty_list },
      { "GET /user/issues", "get_user_issues", defaults.empty_list },
      { "GET /repos/{owner}/{repo}/issues", "get_repo_issues", defaults.empty_list },
      { "POST /repos/{owner}/{repo}/issues", "post_repo_issues" },
      {
        "GET /repos/{owner}/{repo}/issues/comments",
        "get_repo_issue_comments",
        defaults.empty_list,
      },
      { "GET /repos/{owner}/{repo}/issues/comments/{comment_id}", "get_repo_issue_comment" },
      { "PATCH /repos/{owner}/{repo}/issues/comments/{comment_id}", "patch_repo_issue_comment" },
      { "DELETE /repos/{owner}/{repo}/issues/comments/{comment_id}", "delete_repo_issue_comment" },
      {
        "PUT /repos/{owner}/{repo}/issues/comments/{comment_id}/pin",
        "put_repo_issue_comment_pin",
      },
      {
        "DELETE /repos/{owner}/{repo}/issues/comments/{comment_id}/pin",
        "delete_repo_issue_comment_pin",
      },
      { "GET /repos/{owner}/{repo}/issues/events", "get_repo_issue_events", defaults.empty_list },
      { "GET /repos/{owner}/{repo}/issues/events/{event_id}", "get_repo_issue_event" },
      { "GET /repos/{owner}/{repo}/issues/{issue_number}", "get_repo_issue" },
      { "PATCH /repos/{owner}/{repo}/issues/{issue_number}", "patch_repo_issue" },
      { "POST /repos/{owner}/{repo}/issues/{issue_number}/assignees", "post_issue_assignees" },
      { "DELETE /repos/{owner}/{repo}/issues/{issue_number}/assignees", "delete_issue_assignees" },
      {
        "GET /repos/{owner}/{repo}/issues/{issue_number}/assignees/{assignee}",
        "get_issue_assignee",
      },
      {
        "GET /repos/{owner}/{repo}/issues/{issue_number}/comments",
        "get_issue_comments",
        defaults.empty_list,
      },
      { "POST /repos/{owner}/{repo}/issues/{issue_number}/comments", "post_issue_comment" },
      {
        "GET /repos/{owner}/{repo}/issues/{issue_number}/dependencies/blocked_by",
        "get_issue_deps_blocked_by",
        defaults.empty_list,
      },
      {
        "POST /repos/{owner}/{repo}/issues/{issue_number}/dependencies/blocked_by",
        "post_issue_deps_blocked_by",
      },
      {
        "DELETE /repos/{owner}/{repo}/issues/{issue_number}/dependencies/blocked_by/{issue_id}",
        "delete_issue_dep_blocked_by",
      },
      {
        "GET /repos/{owner}/{repo}/issues/{issue_number}/dependencies/blocking",
        "get_issue_deps_blocking",
        defaults.empty_list,
      },
      {
        "GET /repos/{owner}/{repo}/issues/{issue_number}/events",
        "get_issue_events",
        defaults.empty_list,
      },
      {
        "GET /repos/{owner}/{repo}/issues/{issue_number}/issue-field-values",
        "get_issue_field_values",
        defaults.empty_list,
      },
      {
        "GET /repos/{owner}/{repo}/issues/{issue_number}/labels",
        "get_issue_labels",
        defaults.empty_list,
      },
      { "POST /repos/{owner}/{repo}/issues/{issue_number}/labels", "post_issue_labels" },
      { "PUT /repos/{owner}/{repo}/issues/{issue_number}/labels", "put_issue_labels" },
      { "DELETE /repos/{owner}/{repo}/issues/{issue_number}/labels", "delete_issue_labels" },
      { "DELETE /repos/{owner}/{repo}/issues/{issue_number}/labels/{name}", "delete_issue_label" },
      { "PUT /repos/{owner}/{repo}/issues/{issue_number}/lock", "put_issue_lock" },
      { "DELETE /repos/{owner}/{repo}/issues/{issue_number}/lock", "delete_issue_lock" },
      { "GET /repos/{owner}/{repo}/issues/{issue_number}/parent", "get_issue_parent" },
      {
        "GET /repos/{owner}/{repo}/issues/{issue_number}/sub_issues",
        "get_issue_sub_issues",
        defaults.empty_list,
      },
      { "POST /repos/{owner}/{repo}/issues/{issue_number}/sub_issues", "post_issue_sub_issues" },
      { "DELETE /repos/{owner}/{repo}/issues/{issue_number}/sub_issue", "delete_issue_sub_issue" },
      {
        "PATCH /repos/{owner}/{repo}/issues/{issue_number}/sub_issues/priority",
        "patch_issue_sub_issues_priority",
      },
      {
        "GET /repos/{owner}/{repo}/issues/{issue_number}/timeline",
        "get_issue_timeline",
        defaults.empty_list,
      },

      -- Assignees (https://docs.github.com/en/rest/issues/assignees)
      { "GET /repos/{owner}/{repo}/assignees", "get_repo_assignees", defaults.empty_list },
      { "GET /repos/{owner}/{repo}/assignees/{assignee}", "get_repo_assignee" },

      -- Labels (https://docs.github.com/en/rest/issues/labels)
      { "GET /repos/{owner}/{repo}/labels", "get_repo_labels", defaults.empty_list },
      { "POST /repos/{owner}/{repo}/labels", "post_repo_labels" },
      { "GET /repos/{owner}/{repo}/labels/{name}", "get_repo_label" },
      { "PATCH /repos/{owner}/{repo}/labels/{name}", "patch_repo_label" },
      { "DELETE /repos/{owner}/{repo}/labels/{name}", "delete_repo_label" },

      -- Milestones (https://docs.github.com/en/rest/issues/milestones)
      { "GET /repos/{owner}/{repo}/milestones", "get_repo_milestones", defaults.empty_list },
      { "POST /repos/{owner}/{repo}/milestones", "post_repo_milestones" },
      { "GET /repos/{owner}/{repo}/milestones/{milestone_number}", "get_repo_milestone" },
      { "PATCH /repos/{owner}/{repo}/milestones/{milestone_number}", "patch_repo_milestone" },
      { "DELETE /repos/{owner}/{repo}/milestones/{milestone_number}", "delete_repo_milestone" },
      {
        "GET /repos/{owner}/{repo}/milestones/{milestone_number}/labels",
        "get_repo_milestone_labels",
        defaults.empty_list,
      },

      -- Issue field values via repository_id (GitHub-specific)
      {
        "POST /repositories/{repository_id}/issues/{issue_number}/issue-field-values",
        "post_repository_issue_field_values",
      },
      {
        "PUT /repositories/{repository_id}/issues/{issue_number}/issue-field-values",
        "put_repository_issue_field_values",
      },
      {
        "DELETE /repositories/{repository_id}/issues/{issue_number}/issue-field-values/{issue_field_id}",
        "delete_repository_issue_field_value",
      },
    },
  },
  {
    "pulls",
    {
      -- Pull Requests (https://docs.github.com/en/rest/pulls)
      { "GET /repos/{owner}/{repo}/pulls", "get_repo_pulls", defaults.empty_list },
      { "POST /repos/{owner}/{repo}/pulls", "post_repo_pulls" },
      { "GET /repos/{owner}/{repo}/pulls/comments", "get_repo_pull_comments", defaults.empty_list },
      { "GET /repos/{owner}/{repo}/pulls/comments/{comment_id}", "get_repo_pull_comment" },
      { "PATCH /repos/{owner}/{repo}/pulls/comments/{comment_id}", "patch_repo_pull_comment" },
      { "DELETE /repos/{owner}/{repo}/pulls/comments/{comment_id}", "delete_repo_pull_comment" },
      { "GET /repos/{owner}/{repo}/pulls/{pull_number}", "get_repo_pull" },
      { "PATCH /repos/{owner}/{repo}/pulls/{pull_number}", "patch_repo_pull" },
      {
        "GET /repos/{owner}/{repo}/pulls/{pull_number}/codespaces",
        "get_pull_codespaces",
        defaults.empty_list,
      },
      {
        "GET /repos/{owner}/{repo}/pulls/{pull_number}/comments",
        "get_pull_comments",
        defaults.empty_list,
      },
      { "POST /repos/{owner}/{repo}/pulls/{pull_number}/comments", "post_pull_comment" },
      {
        "POST /repos/{owner}/{repo}/pulls/{pull_number}/comments/{comment_id}/replies",
        "post_pull_comment_reply",
      },
      {
        "GET /repos/{owner}/{repo}/pulls/{pull_number}/commits",
        "get_pull_commits",
        defaults.empty_list,
      },
      {
        "GET /repos/{owner}/{repo}/pulls/{pull_number}/files",
        "get_pull_files",
        defaults.empty_list,
      },
      { "GET /repos/{owner}/{repo}/pulls/{pull_number}/merge", "get_pull_merge" },
      { "PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge", "put_pull_merge" },
      {
        "GET /repos/{owner}/{repo}/pulls/{pull_number}/requested_reviewers",
        "get_pull_requested_reviewers",
        defaults.empty_list,
      },
      {
        "POST /repos/{owner}/{repo}/pulls/{pull_number}/requested_reviewers",
        "post_pull_requested_reviewers",
      },
      {
        "DELETE /repos/{owner}/{repo}/pulls/{pull_number}/requested_reviewers",
        "delete_pull_requested_reviewers",
      },
      {
        "GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews",
        "get_pull_reviews",
        defaults.empty_list,
      },
      { "POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews", "post_pull_review" },
      { "GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}", "get_pull_review" },
      { "PUT /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}", "put_pull_review" },
      {
        "DELETE /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}",
        "delete_pull_review",
      },
      {
        "GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}/comments",
        "get_pull_review_comments",
        defaults.empty_list,
      },
      {
        "PUT /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}/dismissals",
        "put_pull_review_dismissal",
      },
      {
        "POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}/events",
        "post_pull_review_event",
      },
      { "POST /repos/{owner}/{repo}/pulls/{pull_number}/update-branch", "post_pull_update_branch" },
      {
        "GET /repos/{owner}/{repo}/commits/{commit_sha}/pulls",
        "get_commit_pulls",
        defaults.empty_list,
      },
    },
  },
  {
    "reactions",
    {
      -- Reactions (https://docs.github.com/en/rest/reactions)
      {
        "GET /repos/{owner}/{repo}/pulls/comments/{comment_id}/reactions",
        "get_repo_pull_comment_reactions",
        defaults.empty_list,
      },
      {
        "POST /repos/{owner}/{repo}/pulls/comments/{comment_id}/reactions",
        "post_repo_pull_comment_reaction",
        defaults.reactions_not_implemented,
      },
      {
        "DELETE /repos/{owner}/{repo}/pulls/comments/{comment_id}/reactions/{reaction_id}",
        "delete_repo_pull_comment_reaction",
        defaults.reactions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/issues/{issue_number}/reactions",
        "get_issue_reactions",
        defaults.empty_list,
      },
      {
        "POST /repos/{owner}/{repo}/issues/{issue_number}/reactions",
        "post_issue_reaction",
        defaults.reactions_not_implemented,
      },
      {
        "DELETE /repos/{owner}/{repo}/issues/{issue_number}/reactions/{reaction_id}",
        "delete_issue_reaction",
        defaults.reactions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/issues/comments/{comment_id}/reactions",
        "get_repo_issue_comment_reactions",
        defaults.empty_list,
      },
      {
        "POST /repos/{owner}/{repo}/issues/comments/{comment_id}/reactions",
        "post_repo_issue_comment_reaction",
        defaults.reactions_not_implemented,
      },
      {
        "DELETE /repos/{owner}/{repo}/issues/comments/{comment_id}/reactions/{reaction_id}",
        "delete_repo_issue_comment_reaction",
        defaults.reactions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/releases/{release_id}/reactions",
        "get_repo_release_reactions",
        defaults.empty_list,
      },
      {
        "POST /repos/{owner}/{repo}/releases/{release_id}/reactions",
        "post_repo_release_reaction",
        defaults.reactions_not_implemented,
      },
      {
        "DELETE /repos/{owner}/{repo}/releases/{release_id}/reactions/{reaction_id}",
        "delete_repo_release_reaction",
        defaults.reactions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/comments/{comment_id}/reactions",
        "get_repo_comment_reactions",
        defaults.empty_list,
      },
      {
        "POST /repos/{owner}/{repo}/comments/{comment_id}/reactions",
        "post_repo_comment_reaction",
        defaults.reactions_not_implemented,
      },
      {
        "DELETE /repos/{owner}/{repo}/comments/{comment_id}/reactions/{reaction_id}",
        "delete_repo_comment_reaction",
        defaults.reactions_not_implemented,
      },
    },
  },
  {
    "users",
    {
      -- Users (https://docs.github.com/en/rest/users)
      { "GET /user", "get_user" },
      { "PATCH /user", "patch_user" },
      { "GET /user/{account_id}", "get_user_by_id" },
      { "GET /users", "get_users" },
      { "GET /users/{username}", "get_users_username" },
      { "GET /users/{username}/hovercard", "get_users_hovercard" },

      -- Blocking
      { "GET /user/blocks", "get_user_blocks" },
      { "GET /user/blocks/{username}", "get_user_block" },
      { "PUT /user/blocks/{username}", "put_user_block" },
      { "DELETE /user/blocks/{username}", "delete_user_block" },

      -- Emails
      { "GET /user/emails", "get_user_emails" },
      { "POST /user/emails", "post_user_emails" },
      { "DELETE /user/emails", "delete_user_emails" },
      { "PATCH /user/email/visibility", "patch_user_email_visibility" },
      { "GET /user/public_emails", "get_user_public_emails" },

      -- Followers
      { "GET /user/followers", "get_user_followers" },
      { "GET /user/following", "get_user_following" },
      { "GET /user/following/{username}", "get_user_is_following" },
      { "PUT /user/following/{username}", "put_user_following" },
      { "DELETE /user/following/{username}", "delete_user_following" },
      { "GET /users/{username}/followers", "get_users_followers" },
      { "GET /users/{username}/following", "get_users_following" },
      { "GET /users/{username}/following/{target_user}", "get_users_is_following" },

      -- GPG Keys
      { "GET /user/gpg_keys", "get_user_gpg_keys" },
      { "POST /user/gpg_keys", "post_user_gpg_keys" },
      { "GET /user/gpg_keys/{gpg_key_id}", "get_user_gpg_key" },
      { "DELETE /user/gpg_keys/{gpg_key_id}", "delete_user_gpg_key" },
      { "GET /users/{username}/gpg_keys", "get_users_gpg_keys" },

      -- SSH Keys
      { "GET /user/keys", "get_user_keys" },
      { "POST /user/keys", "post_user_keys" },
      { "GET /user/keys/{key_id}", "get_user_key" },
      { "DELETE /user/keys/{key_id}", "delete_user_key" },
      { "GET /users/{username}/keys", "get_users_keys" },

      -- Social Accounts
      { "GET /user/social_accounts", "get_user_social_accounts" },
      { "POST /user/social_accounts", "post_user_social_accounts" },
      { "DELETE /user/social_accounts", "delete_user_social_accounts" },
      { "GET /users/{username}/social_accounts", "get_users_social_accounts" },

      -- SSH Signing Keys
      { "GET /user/ssh_signing_keys", "get_user_ssh_signing_keys" },
      { "POST /user/ssh_signing_keys", "post_user_ssh_signing_keys" },
      { "GET /user/ssh_signing_keys/{ssh_signing_key_id}", "get_user_ssh_signing_key" },
      { "DELETE /user/ssh_signing_keys/{ssh_signing_key_id}", "delete_user_ssh_signing_key" },
      { "GET /users/{username}/ssh_signing_keys", "get_users_ssh_signing_keys" },
    },
  },
  {
    "search",
    {
      -- Search (https://docs.github.com/en/rest/search)
      { "GET /search/code", "search_code", defaults.search_empty },
      { "GET /search/commits", "search_commits", defaults.search_empty },
      { "GET /search/issues", "search_issues", defaults.search_empty },
      { "GET /search/labels", "search_labels", defaults.search_empty },
      { "GET /search/repositories", "search_repositories", defaults.search_empty },
      { "GET /search/topics", "search_topics", defaults.search_empty },
      { "GET /search/users", "search_users", defaults.search_empty },
    },
  },
  {
    "apps",
    {
      -- Apps (https://docs.github.com/en/rest/apps)
      { "GET /app", "get_app" },
      { "GET /app/hook/config", "get_app_hook_config" },
      { "PATCH /app/hook/config", "patch_app_hook_config" },
      { "GET /app/hook/deliveries", "get_app_hook_deliveries" },
      { "GET /app/hook/deliveries/{delivery_id}", "get_app_hook_delivery" },
      { "POST /app/hook/deliveries/{delivery_id}/attempts", "post_app_hook_delivery_attempt" },
      { "GET /app/installation-requests", "get_app_installation_requests" },
      { "GET /app/installations", "get_app_installations" },
      { "GET /app/installations/{installation_id}", "get_app_installation" },
      { "DELETE /app/installations/{installation_id}", "delete_app_installation" },
      {
        "POST /app/installations/{installation_id}/access_tokens",
        "post_app_installation_access_tokens",
      },
      { "PUT /app/installations/{installation_id}/suspended", "put_app_installation_suspended" },
      {
        "DELETE /app/installations/{installation_id}/suspended",
        "delete_app_installation_suspended",
      },
      { "GET /apps/{app_slug}", "get_apps_app_slug" },
      { "POST /app-manifests/{code}/conversions", "post_app_manifest_conversions" },
      { "GET /installation/repositories", "get_installation_repositories" },
      { "DELETE /installation/token", "delete_installation_token" },
      { "POST /applications/{client_id}/token", "post_applications_token" },
      { "PATCH /applications/{client_id}/token", "patch_applications_token" },
      { "DELETE /applications/{client_id}/token", "delete_applications_token" },
      { "POST /applications/{client_id}/token/scoped", "post_applications_token_scoped" },
      { "DELETE /applications/{client_id}/grant", "delete_applications_grant" },
      { "GET /orgs/{org}/installation", "get_org_installation" },
      { "GET /orgs/{org}/installations", "get_org_installations" },
      { "GET /repos/{owner}/{repo}/installation", "get_repo_installation" },
      { "GET /user/installations", "get_user_installations" },
      {
        "GET /user/installations/{installation_id}/repositories",
        "get_user_installation_repositories",
      },
      {
        "PUT /user/installations/{installation_id}/repositories/{repository_id}",
        "put_user_installation_repository",
      },
      {
        "DELETE /user/installations/{installation_id}/repositories/{repository_id}",
        "delete_user_installation_repository",
      },
      { "GET /users/{username}/installation", "get_users_installation" },
    },
  },
  {
    "checks",
    {
      -- Checks (https://docs.github.com/en/rest/checks)
      {
        "POST /repos/{owner}/{repo}/check-runs",
        "post_check_runs",
        function(_owner, _repo_name)
          local req = DecodeJson(GetBody() or "{}")
          respond_json(201, {
            id = 0,
            node_id = "",
            head_sha = req.head_sha or "",
            name = req.name or "",
            status = req.status or "queued",
            conclusion = req.conclusion,
            started_at = nil,
            completed_at = nil,
            output = {
              title = (req.output and req.output.title) or "",
              summary = (req.output and req.output.summary) or "",
              text = "",
              annotations_count = 0,
              annotations_url = "",
            },
            url = "",
            html_url = "",
            details_url = req.details_url or "",
          })
        end,
      },
      {
        "GET /repos/{owner}/{repo}/check-runs/{check_run_id}",
        "get_check_run",
        function(_owner, _repo_name, check_run_id)
          respond_json(200, {
            id = tonumber(check_run_id) or 0,
            node_id = "",
            head_sha = "",
            name = "",
            status = "completed",
            conclusion = "success",
            started_at = nil,
            completed_at = nil,
            output = {
              title = "",
              summary = "",
              text = "",
              annotations_count = 0,
              annotations_url = "",
            },
            url = "",
            html_url = "",
            details_url = "",
          })
        end,
      },
      {
        "PATCH /repos/{owner}/{repo}/check-runs/{check_run_id}",
        "patch_check_run",
        function(_owner, _repo_name, check_run_id)
          respond_json(200, {
            id = tonumber(check_run_id) or 0,
            node_id = "",
            head_sha = "",
            name = "",
            status = "completed",
            conclusion = "success",
            started_at = nil,
            completed_at = nil,
            output = {
              title = "",
              summary = "",
              text = "",
              annotations_count = 0,
              annotations_url = "",
            },
            url = "",
            html_url = "",
            details_url = "",
          })
        end,
      },
      {
        "GET /repos/{owner}/{repo}/check-runs/{check_run_id}/annotations",
        "get_check_run_annotations",
        function(_owner, _repo_name, _check_run_id)
          set_preamble()
          Write("[]")
        end,
      },
      {
        "POST /repos/{owner}/{repo}/check-runs/{check_run_id}/rerequest",
        "post_check_run_rerequest",
        function(_owner, _repo_name, _check_run_id)
          respond_json(201, {})
        end,
      },
      {
        "POST /repos/{owner}/{repo}/check-suites",
        "post_check_suites",
        function(owner, repo_name)
          local req = DecodeJson(GetBody() or "{}")
          respond_json(201, {
            id = 0,
            node_id = "",
            head_sha = req.head_sha or "",
            status = "completed",
            conclusion = "success",
            app = { id = 0, slug = "", name = "" },
            repository = { full_name = owner .. "/" .. repo_name },
          })
        end,
      },
      {
        "PATCH /repos/{owner}/{repo}/check-suites/preferences",
        "patch_check_suites_preferences",
        function(_owner, _repo_name) -- luacheck: ignore 212
          local req = DecodeJson(GetBody() or "{}") or {}
          respond_json(200, {
            preferences = req.auto_trigger_checks or {},
          })
        end,
      },
      {
        "GET /repos/{owner}/{repo}/check-suites/{check_suite_id}",
        "get_check_suite",
        function(owner, repo_name, check_suite_id)
          respond_json(200, {
            id = tonumber(check_suite_id) or 0,
            node_id = "",
            head_sha = "",
            status = "completed",
            conclusion = "success",
            app = { id = 0, slug = "", name = "" },
            repository = { full_name = owner .. "/" .. repo_name },
          })
        end,
      },
      {
        "GET /repos/{owner}/{repo}/check-suites/{check_suite_id}/check-runs",
        "get_check_suite_check_runs",
        function(_owner, _repo_name, _check_suite_id)
          respond_json(200, { total_count = 0, check_runs = {} })
        end,
      },
      {
        "POST /repos/{owner}/{repo}/check-suites/{check_suite_id}/rerequest",
        "post_check_suite_rerequest",
        function(_owner, _repo_name, _check_suite_id)
          respond_json(201, {})
        end,
      },
      {
        "GET /repos/{owner}/{repo}/commits/{ref}/check-runs",
        "get_commit_check_runs",
        function(_owner, _repo_name, _ref)
          respond_json(200, { total_count = 0, check_runs = {} })
        end,
      },
      {
        "GET /repos/{owner}/{repo}/commits/{ref}/check-suites",
        "get_commit_check_suites",
        function(_owner, _repo_name, _ref)
          respond_json(200, { total_count = 0, check_suites = {} })
        end,
      },
    },
  },
  {
    "code-scanning",
    {
      -- Code Scanning (https://docs.github.com/en/rest/code-scanning)
      {
        "GET /orgs/{org}/code-scanning/alerts",
        "list_org_code_scanning_alerts",
        defaults.code_scanning_list_empty,
      },
      {
        "GET /repos/{owner}/{repo}/code-scanning/alerts",
        "list_repo_code_scanning_alerts",
        defaults.code_scanning_list_empty,
      },
      {
        "GET /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}",
        "get_code_scanning_alert",
        defaults.code_scanning_not_implemented,
      },
      {
        "PATCH /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}",
        "update_code_scanning_alert",
        defaults.code_scanning_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/autofix",
        "get_code_scanning_autofix",
        defaults.code_scanning_not_implemented,
      },
      {
        "POST /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/autofix",
        "create_code_scanning_autofix",
        defaults.code_scanning_not_implemented,
      },
      {
        "POST /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/autofix/commits",
        "commit_code_scanning_autofix",
        defaults.code_scanning_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/code-scanning/alerts/{alert_number}/instances",
        "list_code_scanning_alert_instances",
        defaults.code_scanning_list_empty,
      },
      {
        "GET /repos/{owner}/{repo}/code-scanning/analyses",
        "list_code_scanning_analyses",
        defaults.code_scanning_list_empty,
      },
      {
        "GET /repos/{owner}/{repo}/code-scanning/analyses/{analysis_id}",
        "get_code_scanning_analysis",
        defaults.code_scanning_not_implemented,
      },
      {
        "DELETE /repos/{owner}/{repo}/code-scanning/analyses/{analysis_id}",
        "delete_code_scanning_analysis",
        defaults.code_scanning_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/code-scanning/codeql/databases",
        "list_codeql_databases",
        defaults.code_scanning_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/code-scanning/codeql/databases/{language}",
        "get_codeql_database",
        defaults.code_scanning_not_implemented,
      },
      {
        "DELETE /repos/{owner}/{repo}/code-scanning/codeql/databases/{language}",
        "delete_codeql_database",
        defaults.code_scanning_not_implemented,
      },
      {
        "POST /repos/{owner}/{repo}/code-scanning/codeql/variant-analyses",
        "create_codeql_variant_analysis",
        defaults.code_scanning_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/code-scanning/codeql/variant-analyses/{codeql_variant_analysis_id}",
        "get_codeql_variant_analysis",
        defaults.code_scanning_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/code-scanning/codeql/variant-analyses/{codeql_variant_analysis_id}/repos/{repo_owner}/{repo_name}",
        "get_codeql_variant_analysis_repo_task",
        defaults.code_scanning_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/code-scanning/default-setup",
        "get_code_scanning_default_setup",
        defaults.code_scanning_not_implemented,
      },
      {
        "PATCH /repos/{owner}/{repo}/code-scanning/default-setup",
        "update_code_scanning_default_setup",
        defaults.code_scanning_not_implemented,
      },
      {
        "POST /repos/{owner}/{repo}/code-scanning/sarifs",
        "upload_code_scanning_sarif",
        defaults.code_scanning_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/code-scanning/sarifs/{sarif_id}",
        "get_code_scanning_sarif",
        defaults.code_scanning_not_implemented,
      },
    },
  },
  {
    "secret-scanning",
    {
      -- Secret Scanning (https://docs.github.com/en/rest/secret-scanning)
      {
        "GET /orgs/{org}/secret-scanning/alerts",
        "list_org_secret_scanning_alerts",
        defaults.secret_scanning_list_empty,
      },
      {
        "GET /orgs/{org}/secret-scanning/pattern-configurations",
        "get_org_secret_scanning_pattern_configs",
        defaults.secret_scanning_not_implemented,
      },
      {
        "PATCH /orgs/{org}/secret-scanning/pattern-configurations",
        "update_org_secret_scanning_pattern_configs",
        defaults.secret_scanning_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/secret-scanning/alerts",
        "list_repo_secret_scanning_alerts",
        defaults.secret_scanning_list_empty,
      },
      {
        "GET /repos/{owner}/{repo}/secret-scanning/alerts/{alert_number}",
        "get_secret_scanning_alert",
        defaults.secret_scanning_not_implemented,
      },
      {
        "PATCH /repos/{owner}/{repo}/secret-scanning/alerts/{alert_number}",
        "update_secret_scanning_alert",
        defaults.secret_scanning_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/secret-scanning/alerts/{alert_number}/locations",
        "list_secret_scanning_alert_locations",
        defaults.secret_scanning_list_empty,
      },
      {
        "POST /repos/{owner}/{repo}/secret-scanning/push-protection-bypasses",
        "create_secret_scanning_push_protection_bypass",
        defaults.secret_scanning_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/secret-scanning/scan-history",
        "get_secret_scanning_scan_history",
        defaults.secret_scanning_not_implemented,
      },
    },
  },
  {
    "dependabot",
    {
      -- Dependabot (https://docs.github.com/en/rest/dependabot)
      {
        "GET /enterprises/{enterprise}/dependabot/alerts",
        "list_enterprise_dependabot_alerts",
        defaults.dependabot_list_empty,
      },
      {
        "GET /orgs/{org}/dependabot/alerts",
        "list_org_dependabot_alerts",
        defaults.dependabot_list_empty,
      },
      {
        "GET /orgs/{org}/dependabot/secrets",
        "list_org_dependabot_secrets",
        defaults.make_empty_collection("secrets"),
      },
      {
        "GET /orgs/{org}/dependabot/secrets/public-key",
        "get_org_dependabot_public_key",
        defaults.dependabot_not_implemented,
      },
      {
        "GET /orgs/{org}/dependabot/secrets/{secret_name}",
        "get_org_dependabot_secret",
        defaults.dependabot_not_implemented,
      },
      {
        "PUT /orgs/{org}/dependabot/secrets/{secret_name}",
        "put_org_dependabot_secret",
        defaults.dependabot_not_implemented,
      },
      {
        "DELETE /orgs/{org}/dependabot/secrets/{secret_name}",
        "delete_org_dependabot_secret",
        defaults.dependabot_not_implemented,
      },
      {
        "GET /orgs/{org}/dependabot/secrets/{secret_name}/repositories",
        "list_org_dependabot_secret_repos",
        defaults.make_empty_collection("repositories"),
      },
      {
        "PUT /orgs/{org}/dependabot/secrets/{secret_name}/repositories",
        "put_org_dependabot_secret_repos",
        defaults.dependabot_not_implemented,
      },
      {
        "PUT /orgs/{org}/dependabot/secrets/{secret_name}/repositories/{repository_id}",
        "add_org_dependabot_secret_repo",
        defaults.dependabot_not_implemented,
      },
      {
        "DELETE /orgs/{org}/dependabot/secrets/{secret_name}/repositories/{repository_id}",
        "remove_org_dependabot_secret_repo",
        defaults.dependabot_not_implemented,
      },
      {
        "GET /organizations/{org}/dependabot/repository-access",
        "get_org_dependabot_repo_access",
        defaults.dependabot_not_implemented,
      },
      {
        "PATCH /organizations/{org}/dependabot/repository-access",
        "update_org_dependabot_repo_access",
        defaults.dependabot_not_implemented,
      },
      {
        "PUT /organizations/{org}/dependabot/repository-access/default-level",
        "set_org_dependabot_repo_access_default_level",
        defaults.dependabot_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/dependabot/alerts",
        "list_repo_dependabot_alerts",
        defaults.dependabot_list_empty,
      },
      {
        "GET /repos/{owner}/{repo}/dependabot/alerts/{alert_number}",
        "get_repo_dependabot_alert",
        defaults.dependabot_not_implemented,
      },
      {
        "PATCH /repos/{owner}/{repo}/dependabot/alerts/{alert_number}",
        "update_repo_dependabot_alert",
        defaults.dependabot_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/dependabot/secrets",
        "list_repo_dependabot_secrets",
        defaults.make_empty_collection("secrets"),
      },
      {
        "GET /repos/{owner}/{repo}/dependabot/secrets/public-key",
        "get_repo_dependabot_public_key",
        defaults.dependabot_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/dependabot/secrets/{secret_name}",
        "get_repo_dependabot_secret",
        defaults.dependabot_not_implemented,
      },
      {
        "PUT /repos/{owner}/{repo}/dependabot/secrets/{secret_name}",
        "put_repo_dependabot_secret",
        defaults.dependabot_not_implemented,
      },
      {
        "DELETE /repos/{owner}/{repo}/dependabot/secrets/{secret_name}",
        "delete_repo_dependabot_secret",
        defaults.dependabot_not_implemented,
      },
    },
  },
  {
    "dependency-graph",
    {
      -- Dependency Graph (https://docs.github.com/en/rest/dependency-graph)
      {
        "GET /repos/{owner}/{repo}/dependency-graph/compare/{basehead}",
        "get_repo_dependency_graph_compare",
        defaults.dependency_graph_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/dependency-graph/sbom",
        "get_repo_dependency_graph_sbom",
        defaults.dependency_graph_not_implemented,
      },
      {
        "POST /repos/{owner}/{repo}/dependency-graph/snapshots",
        "post_repo_dependency_graph_snapshots",
        defaults.dependency_graph_not_implemented,
      },
    },
  },
  {
    "projects",
    {
      -- Projects (https://docs.github.com/en/rest/projects)
      { "GET /orgs/{org}/projectsV2", "projects_list_for_org", defaults.projects_list_empty },
      {
        "GET /orgs/{org}/projectsV2/{project_number}",
        "projects_get_for_org",
        defaults.projects_not_implemented,
      },
      {
        "POST /orgs/{org}/projectsV2/{project_number}/drafts",
        "projects_create_draft_item_for_org",
        defaults.projects_not_implemented,
      },
      {
        "GET /orgs/{org}/projectsV2/{project_number}/fields",
        "projects_list_fields_for_org",
        defaults.projects_list_empty,
      },
      {
        "POST /orgs/{org}/projectsV2/{project_number}/fields",
        "projects_add_field_for_org",
        defaults.projects_not_implemented,
      },
      {
        "GET /orgs/{org}/projectsV2/{project_number}/fields/{field_id}",
        "projects_get_field_for_org",
        defaults.projects_not_implemented,
      },
      {
        "GET /orgs/{org}/projectsV2/{project_number}/items",
        "projects_list_items_for_org",
        defaults.projects_list_empty,
      },
      {
        "POST /orgs/{org}/projectsV2/{project_number}/items",
        "projects_add_item_for_org",
        defaults.projects_not_implemented,
      },
      {
        "GET /orgs/{org}/projectsV2/{project_number}/items/{item_id}",
        "projects_get_item_for_org",
        defaults.projects_not_implemented,
      },
      {
        "PATCH /orgs/{org}/projectsV2/{project_number}/items/{item_id}",
        "projects_update_item_for_org",
        defaults.projects_not_implemented,
      },
      {
        "DELETE /orgs/{org}/projectsV2/{project_number}/items/{item_id}",
        "projects_delete_item_for_org",
        defaults.projects_not_implemented,
      },
      {
        "POST /orgs/{org}/projectsV2/{project_number}/views",
        "projects_create_view_for_org",
        defaults.projects_not_implemented,
      },
      {
        "GET /orgs/{org}/projectsV2/{project_number}/views/{view_number}/items",
        "projects_list_view_items_for_org",
        defaults.projects_list_empty,
      },
      {
        "POST /user/{user_id}/projectsV2/{project_number}/drafts",
        "projects_create_draft_item_for_user",
        defaults.projects_not_implemented,
      },
      {
        "POST /users/{user_id}/projectsV2/{project_number}/views",
        "projects_create_view_for_user",
        defaults.projects_not_implemented,
      },
      {
        "GET /users/{username}/projectsV2",
        "projects_list_for_user",
        defaults.projects_list_empty,
      },
      {
        "GET /users/{username}/projectsV2/{project_number}",
        "projects_get_for_user",
        defaults.projects_not_implemented,
      },
      {
        "GET /users/{username}/projectsV2/{project_number}/fields",
        "projects_list_fields_for_user",
        defaults.projects_list_empty,
      },
      {
        "POST /users/{username}/projectsV2/{project_number}/fields",
        "projects_add_field_for_user",
        defaults.projects_not_implemented,
      },
      {
        "GET /users/{username}/projectsV2/{project_number}/fields/{field_id}",
        "projects_get_field_for_user",
        defaults.projects_not_implemented,
      },
      {
        "GET /users/{username}/projectsV2/{project_number}/items",
        "projects_list_items_for_user",
        defaults.projects_list_empty,
      },
      {
        "POST /users/{username}/projectsV2/{project_number}/items",
        "projects_add_item_for_user",
        defaults.projects_not_implemented,
      },
      {
        "GET /users/{username}/projectsV2/{project_number}/items/{item_id}",
        "projects_get_item_for_user",
        defaults.projects_not_implemented,
      },
      {
        "PATCH /users/{username}/projectsV2/{project_number}/items/{item_id}",
        "projects_update_item_for_user",
        defaults.projects_not_implemented,
      },
      {
        "DELETE /users/{username}/projectsV2/{project_number}/items/{item_id}",
        "projects_delete_item_for_user",
        defaults.projects_not_implemented,
      },
      {
        "GET /users/{username}/projectsV2/{project_number}/views/{view_number}/items",
        "projects_list_view_items_for_user",
        defaults.projects_list_empty,
      },
    },
  },
  {
    "packages",
    {
      -- Packages (https://docs.github.com/en/rest/packages)
      { "GET /orgs/{org}/packages", "get_org_packages", defaults.empty_list },
      { "GET /orgs/{org}/packages/{package_type}/{package_name}", "get_org_package" },
      { "DELETE /orgs/{org}/packages/{package_type}/{package_name}", "delete_org_package" },
      { "POST /orgs/{org}/packages/{package_type}/{package_name}/restore", "restore_org_package" },
      {
        "GET /orgs/{org}/packages/{package_type}/{package_name}/versions",
        "get_org_package_versions",
        defaults.empty_list,
      },
      {
        "GET /orgs/{org}/packages/{package_type}/{package_name}/versions/{package_version_id}",
        "get_org_package_version",
      },
      {
        "DELETE /orgs/{org}/packages/{package_type}/{package_name}/versions/{package_version_id}",
        "delete_org_package_version",
      },
      {
        "POST /orgs/{org}/packages/{package_type}/{package_name}/versions/{package_version_id}/restore",
        "restore_org_package_version",
      },
      { "GET /user/packages", "get_user_packages", defaults.empty_list },
      { "GET /user/packages/{package_type}/{package_name}", "get_user_package" },
      { "DELETE /user/packages/{package_type}/{package_name}", "delete_user_package" },
      { "POST /user/packages/{package_type}/{package_name}/restore", "restore_user_package" },
      {
        "GET /user/packages/{package_type}/{package_name}/versions",
        "get_user_package_versions",
        defaults.empty_list,
      },
      {
        "GET /user/packages/{package_type}/{package_name}/versions/{package_version_id}",
        "get_user_package_version",
      },
      {
        "DELETE /user/packages/{package_type}/{package_name}/versions/{package_version_id}",
        "delete_user_package_version",
      },
      {
        "POST /user/packages/{package_type}/{package_name}/versions/{package_version_id}/restore",
        "restore_user_package_version",
      },
      { "GET /users/{username}/packages", "get_users_packages", defaults.empty_list },
      { "GET /users/{username}/packages/{package_type}/{package_name}", "get_users_package" },
      { "DELETE /users/{username}/packages/{package_type}/{package_name}", "delete_users_package" },
      {
        "POST /users/{username}/packages/{package_type}/{package_name}/restore",
        "restore_users_package",
      },
      {
        "GET /users/{username}/packages/{package_type}/{package_name}/versions",
        "get_users_package_versions",
        defaults.empty_list,
      },
      {
        "GET /users/{username}/packages/{package_type}/{package_name}/versions/{package_version_id}",
        "get_users_package_version",
      },
      {
        "DELETE /users/{username}/packages/{package_type}/{package_name}/versions/{package_version_id}",
        "delete_users_package_version",
      },
      {
        "POST /users/{username}/packages/{package_type}/{package_name}/versions/{package_version_id}/restore",
        "restore_users_package_version",
      },
    },
  },
  {
    "interactions",
    {
      -- Interactions (https://docs.github.com/en/rest/interactions)
      {
        "GET /orgs/{org}/interaction-limits",
        "get_org_interaction_limits",
        defaults.interaction_limits_empty,
      },
      {
        "PUT /orgs/{org}/interaction-limits",
        "put_org_interaction_limits",
        defaults.interaction_limits_put,
      },
      {
        "DELETE /orgs/{org}/interaction-limits",
        "delete_org_interaction_limits",
        defaults.interaction_limits_delete,
      },
      {
        "GET /repos/{owner}/{repo}/interaction-limits",
        "get_repo_interaction_limits",
        defaults.interaction_limits_empty,
      },
      {
        "PUT /repos/{owner}/{repo}/interaction-limits",
        "put_repo_interaction_limits",
        defaults.interaction_limits_put,
      },
      {
        "DELETE /repos/{owner}/{repo}/interaction-limits",
        "delete_repo_interaction_limits",
        defaults.interaction_limits_delete,
      },
      {
        "GET /user/interaction-limits",
        "get_user_interaction_limits",
        defaults.interaction_limits_empty,
      },
      {
        "PUT /user/interaction-limits",
        "put_user_interaction_limits",
        defaults.interaction_limits_put,
      },
      {
        "DELETE /user/interaction-limits",
        "delete_user_interaction_limits",
        defaults.interaction_limits_delete,
      },
    },
  },
  {
    "migrations",
    {
      -- Migrations (https://docs.github.com/en/rest/migrations)
      -- Organization migrations
      { "GET /orgs/{org}/migrations", "get_org_migrations", defaults.empty_list },
      { "POST /orgs/{org}/migrations", "post_org_migrations", defaults.migrations_not_supported },
      {
        "GET /orgs/{org}/migrations/{migration_id}",
        "get_org_migration",
        defaults.migration_not_found,
      },
      {
        "GET /orgs/{org}/migrations/{migration_id}/archive",
        "get_org_migration_archive",
        defaults.migration_not_found,
      },
      {
        "DELETE /orgs/{org}/migrations/{migration_id}/archive",
        "delete_org_migration_archive",
        defaults.migration_not_found,
      },
      {
        "DELETE /orgs/{org}/migrations/{migration_id}/repos/{repo_name}/lock",
        "delete_org_migration_repo_lock",
        defaults.migration_not_found,
      },
      {
        "GET /orgs/{org}/migrations/{migration_id}/repositories",
        "get_org_migration_repos",
        defaults.empty_list,
      },

      -- User migrations
      { "GET /user/migrations", "get_user_migrations", defaults.empty_list },
      { "POST /user/migrations", "post_user_migrations", defaults.migrations_not_supported },
      { "GET /user/migrations/{migration_id}", "get_user_migration", defaults.migration_not_found },
      {
        "GET /user/migrations/{migration_id}/archive",
        "get_user_migration_archive",
        defaults.migration_not_found,
      },
      {
        "DELETE /user/migrations/{migration_id}/archive",
        "delete_user_migration_archive",
        defaults.migration_not_found,
      },
      {
        "DELETE /user/migrations/{migration_id}/repos/{repo_name}/lock",
        "delete_user_migration_repo_lock",
        defaults.migration_not_found,
      },
      {
        "GET /user/migrations/{migration_id}/repositories",
        "get_user_migration_repos",
        defaults.empty_list,
      },
    },
  },
  {
    "pages",
    {
      -- Pages (https://docs.github.com/en/rest/pages)
      { "GET /repos/{owner}/{repo}/pages", "get_repo_pages", defaults.pages_not_implemented },
      { "POST /repos/{owner}/{repo}/pages", "post_repo_pages", defaults.pages_not_implemented },
      { "PUT /repos/{owner}/{repo}/pages", "put_repo_pages", defaults.pages_not_implemented },
      { "DELETE /repos/{owner}/{repo}/pages", "delete_repo_pages", defaults.pages_not_implemented },
      { "GET /repos/{owner}/{repo}/pages/builds", "get_repo_pages_builds", defaults.empty_list },
      {
        "POST /repos/{owner}/{repo}/pages/builds",
        "post_repo_pages_builds",
        defaults.pages_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/pages/builds/latest",
        "get_repo_pages_build_latest",
        defaults.pages_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/pages/builds/{build_id}",
        "get_repo_pages_build",
        defaults.pages_not_implemented,
      },
      {
        "POST /repos/{owner}/{repo}/pages/deployments",
        "post_repo_pages_deployments",
        defaults.pages_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/pages/deployments/{pages_deployment_id}",
        "get_repo_pages_deployment",
        defaults.pages_not_implemented,
      },
      {
        "POST /repos/{owner}/{repo}/pages/deployments/{pages_deployment_id}/cancel",
        "post_repo_pages_deployment_cancel",
        defaults.pages_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/pages/health",
        "get_repo_pages_health",
        defaults.pages_not_implemented,
      },

      -- Source imports (deprecated May 2023 — returns 410 Gone)
      { "GET /repos/{owner}/{repo}/import", "get_repo_import", defaults.source_import_gone },
      { "PUT /repos/{owner}/{repo}/import", "put_repo_import", defaults.source_import_gone },
      { "PATCH /repos/{owner}/{repo}/import", "patch_repo_import", defaults.source_import_gone },
      { "DELETE /repos/{owner}/{repo}/import", "delete_repo_import", defaults.source_import_gone },
      {
        "GET /repos/{owner}/{repo}/import/authors",
        "get_repo_import_authors",
        defaults.source_import_gone,
      },
      {
        "PATCH /repos/{owner}/{repo}/import/authors/{author_id}",
        "patch_repo_import_author",
        defaults.source_import_gone,
      },
      {
        "GET /repos/{owner}/{repo}/import/large_files",
        "get_repo_import_large_files",
        defaults.source_import_gone,
      },
      {
        "PATCH /repos/{owner}/{repo}/import/lfs",
        "patch_repo_import_lfs",
        defaults.source_import_gone,
      },
    },
  },
  {
    "markdown",
    {
      -- Markdown (https://docs.github.com/en/rest/markdown)
      { "POST /markdown", "render_markdown", defaults.markdown_not_implemented },
      { "POST /markdown/raw", "render_markdown_raw", defaults.markdown_not_implemented },
    },
  },
  {
    "actions",
    {
      -- Actions (https://docs.github.com/en/rest/actions)
      -- Enterprise-level cache limits
      {
        "GET /enterprises/{enterprise}/actions/cache/retention-limit",
        "get_enterprise_actions_cache_retention_limit",
        defaults.actions_not_implemented,
      },
      {
        "PUT /enterprises/{enterprise}/actions/cache/retention-limit",
        "put_enterprise_actions_cache_retention_limit",
        defaults.actions_not_implemented,
      },
      {
        "GET /enterprises/{enterprise}/actions/cache/storage-limit",
        "get_enterprise_actions_cache_storage_limit",
        defaults.actions_not_implemented,
      },
      {
        "PUT /enterprises/{enterprise}/actions/cache/storage-limit",
        "put_enterprise_actions_cache_storage_limit",
        defaults.actions_not_implemented,
      },

      -- Enterprise-level OIDC
      {
        "GET /enterprises/{enterprise}/actions/oidc/customization/properties/repo",
        "get_enterprise_actions_oidc_custom_props",
        defaults.empty_list,
      },
      {
        "POST /enterprises/{enterprise}/actions/oidc/customization/properties/repo",
        "post_enterprise_actions_oidc_custom_prop",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /enterprises/{enterprise}/actions/oidc/customization/properties/repo/{custom_property_name}",
        "delete_enterprise_actions_oidc_custom_prop",
        defaults.actions_not_implemented,
      },

      -- Organization-level cache limits (via /organizations/ alias path)
      {
        "GET /organizations/{org}/actions/cache/retention-limit",
        "get_org_actions_cache_retention_limit_v2",
        defaults.actions_not_implemented,
      },
      {
        "PUT /organizations/{org}/actions/cache/retention-limit",
        "put_org_actions_cache_retention_limit_v2",
        defaults.actions_not_implemented,
      },
      {
        "GET /organizations/{org}/actions/cache/storage-limit",
        "get_org_actions_cache_storage_limit_v2",
        defaults.actions_not_implemented,
      },
      {
        "PUT /organizations/{org}/actions/cache/storage-limit",
        "put_org_actions_cache_storage_limit_v2",
        defaults.actions_not_implemented,
      },

      -- Organization cache
      {
        "GET /orgs/{org}/actions/cache/usage",
        "get_org_actions_cache_usage",
        defaults.actions_not_implemented,
      },
      {
        "GET /orgs/{org}/actions/cache/usage-by-repository",
        "get_org_actions_cache_usage_by_repo",
        defaults.actions_not_implemented,
      },

      -- Organization hosted runners
      {
        "GET /orgs/{org}/actions/hosted-runners",
        "get_org_actions_hosted_runners",
        defaults.make_empty_collection("runners"),
      },
      {
        "POST /orgs/{org}/actions/hosted-runners",
        "post_org_actions_hosted_runner",
        defaults.actions_not_implemented,
      },
      {
        "GET /orgs/{org}/actions/hosted-runners/images/custom",
        "get_org_actions_hosted_runner_custom_images",
        defaults.empty_list,
      },
      {
        "GET /orgs/{org}/actions/hosted-runners/images/custom/{image_definition_id}",
        "get_org_actions_hosted_runner_custom_image",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /orgs/{org}/actions/hosted-runners/images/custom/{image_definition_id}",
        "delete_org_actions_hosted_runner_custom_image",
        defaults.actions_not_implemented,
      },
      {
        "GET /orgs/{org}/actions/hosted-runners/images/custom/{image_definition_id}/versions",
        "get_org_actions_hosted_runner_custom_image_versions",
        defaults.empty_list,
      },
      {
        "GET /orgs/{org}/actions/hosted-runners/images/custom/{image_definition_id}/versions/{version}",
        "get_org_actions_hosted_runner_custom_image_version",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /orgs/{org}/actions/hosted-runners/images/custom/{image_definition_id}/versions/{version}",
        "delete_org_actions_hosted_runner_custom_image_version",
        defaults.actions_not_implemented,
      },
      {
        "GET /orgs/{org}/actions/hosted-runners/images/github-owned",
        "get_org_actions_hosted_runner_github_images",
        defaults.empty_list,
      },
      {
        "GET /orgs/{org}/actions/hosted-runners/images/partner",
        "get_org_actions_hosted_runner_partner_images",
        defaults.empty_list,
      },
      {
        "GET /orgs/{org}/actions/hosted-runners/limits",
        "get_org_actions_hosted_runner_limits",
        defaults.actions_not_implemented,
      },
      {
        "GET /orgs/{org}/actions/hosted-runners/machine-sizes",
        "get_org_actions_hosted_runner_machine_sizes",
        defaults.empty_list,
      },
      {
        "GET /orgs/{org}/actions/hosted-runners/platforms",
        "get_org_actions_hosted_runner_platforms",
        defaults.empty_list,
      },
      {
        "GET /orgs/{org}/actions/hosted-runners/{hosted_runner_id}",
        "get_org_actions_hosted_runner",
        defaults.actions_not_implemented,
      },
      {
        "PATCH /orgs/{org}/actions/hosted-runners/{hosted_runner_id}",
        "patch_org_actions_hosted_runner",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /orgs/{org}/actions/hosted-runners/{hosted_runner_id}",
        "delete_org_actions_hosted_runner",
        defaults.actions_not_implemented,
      },

      -- Organization OIDC
      {
        "GET /orgs/{org}/actions/oidc/customization/properties/repo",
        "get_org_actions_oidc_custom_props",
        defaults.empty_list,
      },
      {
        "POST /orgs/{org}/actions/oidc/customization/properties/repo",
        "post_org_actions_oidc_custom_prop",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /orgs/{org}/actions/oidc/customization/properties/repo/{custom_property_name}",
        "delete_org_actions_oidc_custom_prop",
        defaults.actions_not_implemented,
      },
      {
        "GET /orgs/{org}/actions/oidc/customization/sub",
        "get_org_actions_oidc_sub",
        defaults.actions_not_implemented,
      },
      {
        "PUT /orgs/{org}/actions/oidc/customization/sub",
        "put_org_actions_oidc_sub",
        defaults.actions_not_implemented,
      },

      -- Organization permissions
      {
        "GET /orgs/{org}/actions/permissions",
        "get_org_actions_permissions",
        defaults.actions_not_implemented,
      },
      {
        "PUT /orgs/{org}/actions/permissions",
        "put_org_actions_permissions",
        defaults.actions_not_implemented,
      },
      {
        "GET /orgs/{org}/actions/permissions/artifact-and-log-retention",
        "get_org_actions_artifact_log_retention",
        defaults.actions_not_implemented,
      },
      {
        "PUT /orgs/{org}/actions/permissions/artifact-and-log-retention",
        "put_org_actions_artifact_log_retention",
        defaults.actions_not_implemented,
      },
      {
        "GET /orgs/{org}/actions/permissions/fork-pr-contributor-approval",
        "get_org_actions_fork_pr_approval",
        defaults.actions_not_implemented,
      },
      {
        "PUT /orgs/{org}/actions/permissions/fork-pr-contributor-approval",
        "put_org_actions_fork_pr_approval",
        defaults.actions_not_implemented,
      },
      {
        "GET /orgs/{org}/actions/permissions/fork-pr-workflows-private-repos",
        "get_org_actions_fork_pr_private_repos",
        defaults.actions_not_implemented,
      },
      {
        "PUT /orgs/{org}/actions/permissions/fork-pr-workflows-private-repos",
        "put_org_actions_fork_pr_private_repos",
        defaults.actions_not_implemented,
      },
      {
        "GET /orgs/{org}/actions/permissions/repositories",
        "get_org_actions_perm_repos",
        defaults.empty_list,
      },
      {
        "PUT /orgs/{org}/actions/permissions/repositories",
        "put_org_actions_perm_repos",
        defaults.actions_not_implemented,
      },
      {
        "PUT /orgs/{org}/actions/permissions/repositories/{repository_id}",
        "put_org_actions_perm_repo",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /orgs/{org}/actions/permissions/repositories/{repository_id}",
        "delete_org_actions_perm_repo",
        defaults.actions_not_implemented,
      },
      {
        "GET /orgs/{org}/actions/permissions/selected-actions",
        "get_org_actions_selected_actions",
        defaults.actions_not_implemented,
      },
      {
        "PUT /orgs/{org}/actions/permissions/selected-actions",
        "put_org_actions_selected_actions",
        defaults.actions_not_implemented,
      },
      {
        "GET /orgs/{org}/actions/permissions/self-hosted-runners",
        "get_org_actions_self_hosted_runners_perm",
        defaults.actions_not_implemented,
      },
      {
        "PUT /orgs/{org}/actions/permissions/self-hosted-runners",
        "put_org_actions_self_hosted_runners_perm",
        defaults.actions_not_implemented,
      },
      {
        "GET /orgs/{org}/actions/permissions/self-hosted-runners/repositories",
        "get_org_actions_self_hosted_runner_repos",
        defaults.empty_list,
      },
      {
        "PUT /orgs/{org}/actions/permissions/self-hosted-runners/repositories",
        "put_org_actions_self_hosted_runner_repos",
        defaults.actions_not_implemented,
      },
      {
        "PUT /orgs/{org}/actions/permissions/self-hosted-runners/repositories/{repository_id}",
        "put_org_actions_self_hosted_runner_repo",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /orgs/{org}/actions/permissions/self-hosted-runners/repositories/{repository_id}",
        "delete_org_actions_self_hosted_runner_repo",
        defaults.actions_not_implemented,
      },
      {
        "GET /orgs/{org}/actions/permissions/workflow",
        "get_org_actions_default_workflow_perms",
        defaults.actions_not_implemented,
      },
      {
        "PUT /orgs/{org}/actions/permissions/workflow",
        "put_org_actions_default_workflow_perms",
        defaults.actions_not_implemented,
      },

      -- Organization runner groups
      {
        "GET /orgs/{org}/actions/runner-groups",
        "get_org_actions_runner_groups",
        defaults.make_empty_collection("runner_groups"),
      },
      {
        "POST /orgs/{org}/actions/runner-groups",
        "post_org_actions_runner_group",
        defaults.actions_not_implemented,
      },
      {
        "GET /orgs/{org}/actions/runner-groups/{runner_group_id}",
        "get_org_actions_runner_group",
        defaults.actions_not_implemented,
      },
      {
        "PATCH /orgs/{org}/actions/runner-groups/{runner_group_id}",
        "patch_org_actions_runner_group",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /orgs/{org}/actions/runner-groups/{runner_group_id}",
        "delete_org_actions_runner_group",
        defaults.actions_not_implemented,
      },
      {
        "GET /orgs/{org}/actions/runner-groups/{runner_group_id}/hosted-runners",
        "get_org_actions_runner_group_hosted_runners",
        defaults.make_empty_collection("runners"),
      },
      {
        "GET /orgs/{org}/actions/runner-groups/{runner_group_id}/repositories",
        "get_org_actions_runner_group_repos",
        defaults.empty_list,
      },
      {
        "PUT /orgs/{org}/actions/runner-groups/{runner_group_id}/repositories",
        "put_org_actions_runner_group_repos",
        defaults.actions_not_implemented,
      },
      {
        "PUT /orgs/{org}/actions/runner-groups/{runner_group_id}/repositories/{repository_id}",
        "put_org_actions_runner_group_repo",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /orgs/{org}/actions/runner-groups/{runner_group_id}/repositories/{repository_id}",
        "delete_org_actions_runner_group_repo",
        defaults.actions_not_implemented,
      },
      {
        "GET /orgs/{org}/actions/runner-groups/{runner_group_id}/runners",
        "get_org_actions_runner_group_runners",
        defaults.make_empty_collection("runners"),
      },
      {
        "PUT /orgs/{org}/actions/runner-groups/{runner_group_id}/runners",
        "put_org_actions_runner_group_runners",
        defaults.actions_not_implemented,
      },
      {
        "PUT /orgs/{org}/actions/runner-groups/{runner_group_id}/runners/{runner_id}",
        "put_org_actions_runner_group_runner",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /orgs/{org}/actions/runner-groups/{runner_group_id}/runners/{runner_id}",
        "delete_org_actions_runner_group_runner",
        defaults.actions_not_implemented,
      },

      -- Organization runners
      {
        "GET /orgs/{org}/actions/runners",
        "get_org_actions_runners",
        defaults.make_empty_collection("runners"),
      },
      {
        "GET /orgs/{org}/actions/runners/downloads",
        "get_org_actions_runner_downloads",
        defaults.empty_list,
      },
      {
        "POST /orgs/{org}/actions/runners/generate-jitconfig",
        "post_org_actions_runner_jitconfig",
        defaults.actions_not_implemented,
      },
      {
        "POST /orgs/{org}/actions/runners/registration-token",
        "post_org_actions_runner_registration_token",
        defaults.actions_not_implemented,
      },
      {
        "POST /orgs/{org}/actions/runners/remove-token",
        "post_org_actions_runner_remove_token",
        defaults.actions_not_implemented,
      },
      {
        "GET /orgs/{org}/actions/runners/{runner_id}",
        "get_org_actions_runner",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /orgs/{org}/actions/runners/{runner_id}",
        "delete_org_actions_runner",
        defaults.actions_not_implemented,
      },
      {
        "GET /orgs/{org}/actions/runners/{runner_id}/labels",
        "get_org_actions_runner_labels",
        defaults.empty_list,
      },
      {
        "POST /orgs/{org}/actions/runners/{runner_id}/labels",
        "post_org_actions_runner_labels",
        defaults.actions_not_implemented,
      },
      {
        "PUT /orgs/{org}/actions/runners/{runner_id}/labels",
        "put_org_actions_runner_labels",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /orgs/{org}/actions/runners/{runner_id}/labels",
        "delete_org_actions_runner_labels",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /orgs/{org}/actions/runners/{runner_id}/labels/{name}",
        "delete_org_actions_runner_label",
        defaults.actions_not_implemented,
      },

      -- Organization secrets
      {
        "GET /orgs/{org}/actions/secrets",
        "get_org_actions_secrets",
        defaults.make_empty_collection("secrets"),
      },
      {
        "GET /orgs/{org}/actions/secrets/public-key",
        "get_org_actions_secrets_public_key",
        defaults.actions_not_implemented,
      },
      {
        "GET /orgs/{org}/actions/secrets/{secret_name}",
        "get_org_actions_secret",
        defaults.actions_not_implemented,
      },
      {
        "PUT /orgs/{org}/actions/secrets/{secret_name}",
        "put_org_actions_secret",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /orgs/{org}/actions/secrets/{secret_name}",
        "delete_org_actions_secret",
        defaults.actions_not_implemented,
      },
      {
        "GET /orgs/{org}/actions/secrets/{secret_name}/repositories",
        "get_org_actions_secret_repos",
        defaults.empty_list,
      },
      {
        "PUT /orgs/{org}/actions/secrets/{secret_name}/repositories",
        "put_org_actions_secret_repos",
        defaults.actions_not_implemented,
      },
      {
        "PUT /orgs/{org}/actions/secrets/{secret_name}/repositories/{repository_id}",
        "put_org_actions_secret_repo",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /orgs/{org}/actions/secrets/{secret_name}/repositories/{repository_id}",
        "delete_org_actions_secret_repo",
        defaults.actions_not_implemented,
      },

      -- Organization variables
      {
        "GET /orgs/{org}/actions/variables",
        "get_org_actions_variables",
        defaults.make_empty_collection("variables"),
      },
      {
        "POST /orgs/{org}/actions/variables",
        "post_org_actions_variable",
        defaults.actions_not_implemented,
      },
      {
        "GET /orgs/{org}/actions/variables/{name}",
        "get_org_actions_variable",
        defaults.actions_not_implemented,
      },
      {
        "PATCH /orgs/{org}/actions/variables/{name}",
        "patch_org_actions_variable",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /orgs/{org}/actions/variables/{name}",
        "delete_org_actions_variable",
        defaults.actions_not_implemented,
      },
      {
        "GET /orgs/{org}/actions/variables/{name}/repositories",
        "get_org_actions_variable_repos",
        defaults.empty_list,
      },
      {
        "PUT /orgs/{org}/actions/variables/{name}/repositories",
        "put_org_actions_variable_repos",
        defaults.actions_not_implemented,
      },
      {
        "PUT /orgs/{org}/actions/variables/{name}/repositories/{repository_id}",
        "put_org_actions_variable_repo",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /orgs/{org}/actions/variables/{name}/repositories/{repository_id}",
        "delete_org_actions_variable_repo",
        defaults.actions_not_implemented,
      },

      -- Repository artifacts
      {
        "GET /repos/{owner}/{repo}/actions/artifacts",
        "get_repo_actions_artifacts",
        defaults.make_empty_collection("artifacts"),
      },
      {
        "GET /repos/{owner}/{repo}/actions/artifacts/{artifact_id}",
        "get_repo_actions_artifact",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /repos/{owner}/{repo}/actions/artifacts/{artifact_id}",
        "delete_repo_actions_artifact",
        defaults.actions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/actions/artifacts/{artifact_id}/{archive_format}",
        "get_repo_actions_artifact_archive",
        defaults.actions_not_implemented,
      },

      -- Repository cache
      {
        "GET /repos/{owner}/{repo}/actions/cache/retention-limit",
        "get_repo_actions_cache_retention_limit",
        defaults.actions_not_implemented,
      },
      {
        "PUT /repos/{owner}/{repo}/actions/cache/retention-limit",
        "put_repo_actions_cache_retention_limit",
        defaults.actions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/actions/cache/storage-limit",
        "get_repo_actions_cache_storage_limit",
        defaults.actions_not_implemented,
      },
      {
        "PUT /repos/{owner}/{repo}/actions/cache/storage-limit",
        "put_repo_actions_cache_storage_limit",
        defaults.actions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/actions/cache/usage",
        "get_repo_actions_cache_usage",
        defaults.actions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/actions/caches",
        "get_repo_actions_caches",
        defaults.make_empty_collection("actions_caches"),
      },
      {
        "DELETE /repos/{owner}/{repo}/actions/caches",
        "delete_repo_actions_caches",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /repos/{owner}/{repo}/actions/caches/{cache_id}",
        "delete_repo_actions_cache",
        defaults.actions_not_implemented,
      },

      -- Repository jobs
      {
        "GET /repos/{owner}/{repo}/actions/jobs/{job_id}",
        "get_repo_actions_job",
        defaults.actions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/actions/jobs/{job_id}/logs",
        "get_repo_actions_job_logs",
        defaults.actions_not_implemented,
      },
      {
        "POST /repos/{owner}/{repo}/actions/jobs/{job_id}/rerun",
        "post_repo_actions_job_rerun",
        defaults.actions_not_implemented,
      },

      -- Repository OIDC
      {
        "GET /repos/{owner}/{repo}/actions/oidc/customization/sub",
        "get_repo_actions_oidc_sub",
        defaults.actions_not_implemented,
      },
      {
        "PUT /repos/{owner}/{repo}/actions/oidc/customization/sub",
        "put_repo_actions_oidc_sub",
        defaults.actions_not_implemented,
      },

      -- Repository org secrets/variables (read-only inherited view)
      {
        "GET /repos/{owner}/{repo}/actions/organization-secrets",
        "get_repo_actions_org_secrets",
        defaults.make_empty_collection("secrets"),
      },
      {
        "GET /repos/{owner}/{repo}/actions/organization-variables",
        "get_repo_actions_org_variables",
        defaults.make_empty_collection("variables"),
      },

      -- Repository permissions
      {
        "GET /repos/{owner}/{repo}/actions/permissions",
        "get_repo_actions_permissions",
        defaults.actions_not_implemented,
      },
      {
        "PUT /repos/{owner}/{repo}/actions/permissions",
        "put_repo_actions_permissions",
        defaults.actions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/actions/permissions/access",
        "get_repo_actions_access_level",
        defaults.actions_not_implemented,
      },
      {
        "PUT /repos/{owner}/{repo}/actions/permissions/access",
        "put_repo_actions_access_level",
        defaults.actions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/actions/permissions/artifact-and-log-retention",
        "get_repo_actions_artifact_log_retention",
        defaults.actions_not_implemented,
      },
      {
        "PUT /repos/{owner}/{repo}/actions/permissions/artifact-and-log-retention",
        "put_repo_actions_artifact_log_retention",
        defaults.actions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/actions/permissions/fork-pr-contributor-approval",
        "get_repo_actions_fork_pr_approval",
        defaults.actions_not_implemented,
      },
      {
        "PUT /repos/{owner}/{repo}/actions/permissions/fork-pr-contributor-approval",
        "put_repo_actions_fork_pr_approval",
        defaults.actions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/actions/permissions/fork-pr-workflows-private-repos",
        "get_repo_actions_fork_pr_private_repos",
        defaults.actions_not_implemented,
      },
      {
        "PUT /repos/{owner}/{repo}/actions/permissions/fork-pr-workflows-private-repos",
        "put_repo_actions_fork_pr_private_repos",
        defaults.actions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/actions/permissions/selected-actions",
        "get_repo_actions_selected_actions",
        defaults.actions_not_implemented,
      },
      {
        "PUT /repos/{owner}/{repo}/actions/permissions/selected-actions",
        "put_repo_actions_selected_actions",
        defaults.actions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/actions/permissions/workflow",
        "get_repo_actions_default_workflow_perms",
        defaults.actions_not_implemented,
      },
      {
        "PUT /repos/{owner}/{repo}/actions/permissions/workflow",
        "put_repo_actions_default_workflow_perms",
        defaults.actions_not_implemented,
      },

      -- Repository runners
      {
        "GET /repos/{owner}/{repo}/actions/runners",
        "get_repo_actions_runners",
        defaults.make_empty_collection("runners"),
      },
      {
        "GET /repos/{owner}/{repo}/actions/runners/downloads",
        "get_repo_actions_runner_downloads",
        defaults.empty_list,
      },
      {
        "POST /repos/{owner}/{repo}/actions/runners/generate-jitconfig",
        "post_repo_actions_runner_jitconfig",
        defaults.actions_not_implemented,
      },
      {
        "POST /repos/{owner}/{repo}/actions/runners/registration-token",
        "post_repo_actions_runner_registration_token",
        defaults.actions_not_implemented,
      },
      {
        "POST /repos/{owner}/{repo}/actions/runners/remove-token",
        "post_repo_actions_runner_remove_token",
        defaults.actions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/actions/runners/{runner_id}",
        "get_repo_actions_runner",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /repos/{owner}/{repo}/actions/runners/{runner_id}",
        "delete_repo_actions_runner",
        defaults.actions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/actions/runners/{runner_id}/labels",
        "get_repo_actions_runner_labels",
        defaults.empty_list,
      },
      {
        "POST /repos/{owner}/{repo}/actions/runners/{runner_id}/labels",
        "post_repo_actions_runner_labels",
        defaults.actions_not_implemented,
      },
      {
        "PUT /repos/{owner}/{repo}/actions/runners/{runner_id}/labels",
        "put_repo_actions_runner_labels",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /repos/{owner}/{repo}/actions/runners/{runner_id}/labels",
        "delete_repo_actions_runner_labels",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /repos/{owner}/{repo}/actions/runners/{runner_id}/labels/{name}",
        "delete_repo_actions_runner_label",
        defaults.actions_not_implemented,
      },

      -- Repository workflow runs
      {
        "GET /repos/{owner}/{repo}/actions/runs",
        "get_repo_actions_runs",
        defaults.make_empty_collection("workflow_runs"),
      },
      {
        "GET /repos/{owner}/{repo}/actions/runs/{run_id}",
        "get_repo_actions_run",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /repos/{owner}/{repo}/actions/runs/{run_id}",
        "delete_repo_actions_run",
        defaults.actions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/actions/runs/{run_id}/approvals",
        "get_repo_actions_run_approvals",
        defaults.empty_list,
      },
      {
        "POST /repos/{owner}/{repo}/actions/runs/{run_id}/approve",
        "post_repo_actions_run_approve",
        defaults.actions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/actions/runs/{run_id}/artifacts",
        "get_repo_actions_run_artifacts",
        defaults.make_empty_collection("artifacts"),
      },
      {
        "GET /repos/{owner}/{repo}/actions/runs/{run_id}/attempts/{attempt_number}",
        "get_repo_actions_run_attempt",
        defaults.actions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/actions/runs/{run_id}/attempts/{attempt_number}/jobs",
        "get_repo_actions_run_attempt_jobs",
        defaults.make_empty_collection("jobs"),
      },
      {
        "GET /repos/{owner}/{repo}/actions/runs/{run_id}/attempts/{attempt_number}/logs",
        "get_repo_actions_run_attempt_logs",
        defaults.actions_not_implemented,
      },
      {
        "POST /repos/{owner}/{repo}/actions/runs/{run_id}/cancel",
        "post_repo_actions_run_cancel",
        defaults.actions_not_implemented,
      },
      {
        "POST /repos/{owner}/{repo}/actions/runs/{run_id}/deployment_protection_rule",
        "post_repo_actions_run_deployment_prot",
        defaults.actions_not_implemented,
      },
      {
        "POST /repos/{owner}/{repo}/actions/runs/{run_id}/force-cancel",
        "post_repo_actions_run_force_cancel",
        defaults.actions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs",
        "get_repo_actions_run_jobs",
        defaults.make_empty_collection("jobs"),
      },
      {
        "GET /repos/{owner}/{repo}/actions/runs/{run_id}/logs",
        "get_repo_actions_run_logs",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /repos/{owner}/{repo}/actions/runs/{run_id}/logs",
        "delete_repo_actions_run_logs",
        defaults.actions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/actions/runs/{run_id}/pending_deployments",
        "get_repo_actions_run_pending_deployments",
        defaults.empty_list,
      },
      {
        "POST /repos/{owner}/{repo}/actions/runs/{run_id}/pending_deployments",
        "post_repo_actions_run_pending_deployments",
        defaults.actions_not_implemented,
      },
      {
        "POST /repos/{owner}/{repo}/actions/runs/{run_id}/rerun",
        "post_repo_actions_run_rerun",
        defaults.actions_not_implemented,
      },
      {
        "POST /repos/{owner}/{repo}/actions/runs/{run_id}/rerun-failed-jobs",
        "post_repo_actions_run_rerun_failed",
        defaults.actions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/actions/runs/{run_id}/timing",
        "get_repo_actions_run_timing",
        defaults.actions_not_implemented,
      },

      -- Repository secrets
      {
        "GET /repos/{owner}/{repo}/actions/secrets",
        "get_repo_actions_secrets",
        defaults.make_empty_collection("secrets"),
      },
      {
        "GET /repos/{owner}/{repo}/actions/secrets/public-key",
        "get_repo_actions_secrets_public_key",
        defaults.actions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/actions/secrets/{secret_name}",
        "get_repo_actions_secret",
        defaults.actions_not_implemented,
      },
      {
        "PUT /repos/{owner}/{repo}/actions/secrets/{secret_name}",
        "put_repo_actions_secret",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /repos/{owner}/{repo}/actions/secrets/{secret_name}",
        "delete_repo_actions_secret",
        defaults.actions_not_implemented,
      },

      -- Repository variables
      {
        "GET /repos/{owner}/{repo}/actions/variables",
        "get_repo_actions_variables",
        defaults.make_empty_collection("variables"),
      },
      {
        "POST /repos/{owner}/{repo}/actions/variables",
        "post_repo_actions_variable",
        defaults.actions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/actions/variables/{name}",
        "get_repo_actions_variable",
        defaults.actions_not_implemented,
      },
      {
        "PATCH /repos/{owner}/{repo}/actions/variables/{name}",
        "patch_repo_actions_variable",
        defaults.actions_not_implemented,
      },
      {
        "DELETE /repos/{owner}/{repo}/actions/variables/{name}",
        "delete_repo_actions_variable",
        defaults.actions_not_implemented,
      },

      -- Repository workflows
      {
        "GET /repos/{owner}/{repo}/actions/workflows",
        "get_repo_actions_workflows",
        defaults.make_empty_collection("workflows"),
      },
      {
        "GET /repos/{owner}/{repo}/actions/workflows/{workflow_id}",
        "get_repo_actions_workflow",
        defaults.actions_not_implemented,
      },
      {
        "PUT /repos/{owner}/{repo}/actions/workflows/{workflow_id}/disable",
        "put_repo_actions_workflow_disable",
        defaults.actions_not_implemented,
      },
      {
        "POST /repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches",
        "post_repo_actions_workflow_dispatch",
        defaults.actions_not_implemented,
      },
      {
        "PUT /repos/{owner}/{repo}/actions/workflows/{workflow_id}/enable",
        "put_repo_actions_workflow_enable",
        defaults.actions_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/actions/workflows/{workflow_id}/runs",
        "get_repo_actions_workflow_runs",
        defaults.make_empty_collection("workflow_runs"),
      },
      {
        "GET /repos/{owner}/{repo}/actions/workflows/{workflow_id}/timing",
        "get_repo_actions_workflow_timing",
        defaults.actions_not_implemented,
      },
    },
  },
  {
    "git",
    {
      -- Git database (https://docs.github.com/en/rest/git)
      -- Blobs
      { "POST /repos/{owner}/{repo}/git/blobs", "create_git_blob", defaults.git_not_implemented },
      {
        "GET /repos/{owner}/{repo}/git/blobs/{file_sha}",
        "get_git_blob",
        defaults.git_not_implemented,
      },

      -- Commits
      {
        "POST /repos/{owner}/{repo}/git/commits",
        "create_git_commit",
        defaults.git_not_implemented,
      },
      {
        "GET /repos/{owner}/{repo}/git/commits/{commit_sha}",
        "get_git_commit",
        defaults.git_not_implemented,
      },

      -- Refs
      {
        "GET /repos/{owner}/{repo}/git/matching-refs/{ref+}",
        "list_git_matching_refs",
        defaults.git_not_implemented,
      },
      { "GET /repos/{owner}/{repo}/git/ref/{ref+}", "get_git_ref", defaults.git_not_implemented },
      { "POST /repos/{owner}/{repo}/git/refs", "create_git_ref", defaults.git_not_implemented },
      {
        "PATCH /repos/{owner}/{repo}/git/refs/{ref+}",
        "update_git_ref",
        defaults.git_not_implemented,
      },
      {
        "DELETE /repos/{owner}/{repo}/git/refs/{ref+}",
        "delete_git_ref",
        defaults.git_not_implemented,
      },

      -- Tags
      { "POST /repos/{owner}/{repo}/git/tags", "create_git_tag", defaults.git_not_implemented },
      {
        "GET /repos/{owner}/{repo}/git/tags/{tag_sha}",
        "get_git_tag",
        defaults.git_not_implemented,
      },

      -- Trees
      { "POST /repos/{owner}/{repo}/git/trees", "create_git_tree", defaults.git_not_implemented },
      {
        "GET /repos/{owner}/{repo}/git/trees/{tree_sha}",
        "get_git_tree",
        defaults.git_not_implemented,
      },
    },
  },
}

-- Flatten sections into the global endpoints table and register routes.
-- endpoints[i].group is the authoritative group name for each endpoint;
-- downstream tools (scripts/dump-endpoints.lua) consume it.
endpoints = {}
for _, section in ipairs(endpoint_sections) do
  local g = section[1]
  for _, e in ipairs(section[2]) do
    e.group = g
    endpoints[#endpoints + 1] = e
    route_add(e[1], e[2], e[3])
  end
end
