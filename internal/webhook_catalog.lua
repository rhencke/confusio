-- Webhook coverage catalog.
--
-- This is the event-side source of truth for GitHub webhook event families,
-- action names, normalized confusio event bases, and provider source coverage.
-- Later fixture/docs/shape checks consume this same table so validation does
-- not drift from startup event-filter parsing.
--
-- Provider status values:
--   supported   - native source exists and is expected to be translated
--   partial     - native source covers only part of GitHub semantics
--   unsupported - analogous native source exists but confusio does not claim it yet
--   no_analog   - provider has no comparable native source event

local PROVIDERS = {
  "azuredevops",
  "bitbucket",
  "bitbucket_datacenter",
  "codeberg",
  "codecommit",
  "confusio",
  "forgejo",
  "gerrit",
  "gitblit",
  "gitbucket",
  "gitea",
  "gitlab",
  "gogs",
  "harness",
  "kallithea",
  "launchpad",
  "notabug",
  "onedev",
  "pagure",
  "phabricator",
  "radicle",
  "rhodecode",
  "sourceforge",
  "sourcehut",
  "tuleap",
}

local GITEA_FAMILY = { "codeberg", "forgejo", "gitea", "gogs", "notabug" }
local BITBUCKET_FAMILY = { "bitbucket", "bitbucket_datacenter" }
local CHANGE_REVIEW_PROVIDERS = { "gerrit", "onedev" }
local SIMPLE_GIT_PROVIDERS = { "gitblit", "gitbucket", "kallithea", "pagure" }
local SOURCEHUT_RELATED = { "phabricator", "radicle", "sourceforge", "sourcehut", "tuleap" }

local RHODECODE_WEBHOOK_SOURCES = {
  create = { "PUSH_HOOK", "POST_PUSH" },
  delete = { "PUSH_HOOK", "POST_PUSH" },
  push = { "PUSH_HOOK", "POST_PUSH" },
  pull_request = {
    "webhook integration pull_request",
    "CREATE_PULLREQUEST_HOOK",
    "CLOSE_PULLREQUEST_HOOK",
  },
  repository = { "CREATE_REPO_HOOK", "DELETE_REPO_HOOK" },
}

local function append_all(dst, src)
  for _, value in ipairs(src) do
    dst[#dst + 1] = value
  end
end

local function provider_list(...)
  local out = {}
  for _, item in ipairs({ ... }) do
    if type(item) == "table" then
      append_all(out, item)
    else
      out[#out + 1] = item
    end
  end
  return out
end

local function status_map(spec)
  local map = {}
  for _, provider in ipairs(PROVIDERS) do
    map[provider] = {
      status = provider == "confusio" and "supported" or "no_analog",
      sources = {},
    }
  end
  for status, providers in pairs(spec or {}) do
    for _, provider in ipairs(providers) do
      map[provider] = {
        status = status,
        sources = {},
      }
    end
  end
  return map
end

local function event(name, normalized_base, actions, spec)
  return {
    name = name,
    normalized_base = normalized_base,
    actions = actions,
    providers = status_map(spec),
  }
end

local function attach_provider_sources(defs, provider, sources_by_event)
  for _, def in ipairs(defs) do
    local sources = sources_by_event[def.name]
    if sources and def.providers[provider] then
      def.providers[provider].sources = sources
    end
  end
end

local REF_PROVIDERS = provider_list(
  GITEA_FAMILY,
  BITBUCKET_FAMILY,
  CHANGE_REVIEW_PROVIDERS,
  SIMPLE_GIT_PROVIDERS,
  SOURCEHUT_RELATED,
  "azuredevops",
  "gitlab",
  "rhodecode"
)

local ISSUE_PROVIDERS = provider_list(
  GITEA_FAMILY,
  "azuredevops",
  "gitlab",
  "harness",
  "onedev",
  "pagure",
  "phabricator",
  "sourcehut",
  "tuleap"
)

local PULL_REQUEST_PROVIDERS = provider_list(
  GITEA_FAMILY,
  BITBUCKET_FAMILY,
  CHANGE_REVIEW_PROVIDERS,
  SIMPLE_GIT_PROVIDERS,
  "azuredevops",
  "gitlab",
  "harness",
  "launchpad",
  "phabricator",
  "radicle",
  "rhodecode",
  "sourcehut"
)

local EVENT_DEFS = {
  event(
    "branch_protection_configuration",
    "branch_protection_configuration",
    { "created", "edited", "deleted" },
    {
      unsupported = provider_list(GITEA_FAMILY, "gitlab"),
    }
  ),
  event("branch_protection_rule", "branch_protection_rule", { "created", "edited", "deleted" }, {
    supported = { "codecommit" },
    unsupported = provider_list(GITEA_FAMILY, "gitlab"),
  }),
  event("check_run", "check_run", { "created", "completed", "rerequested", "requested_action" }, {
    partial = { "azuredevops", "gitlab", "harness", "sourcehut" },
  }),
  event("check_suite", "check_suite", { "completed", "requested", "rerequested" }, {
    partial = { "azuredevops", "gitlab", "harness" },
  }),
  event(
    "code_scanning_alert",
    "code_scanning_alert",
    { "created", "reopened", "closed", "fixed_in_branch" },
    {
      partial = { "azuredevops", "gitbucket", "gitlab" },
    }
  ),
  event("commit_comment", "commit_comment", { "created" }, {
    supported = { "bitbucket", "codecommit" },
  }),
  event("create", "create", { "" }, {
    supported = provider_list(REF_PROVIDERS, "codecommit"),
  }),
  event("custom_property", "custom_property", { "created", "updated", "deleted" }, {
    partial = { "gitbucket" },
  }),
  event("custom_property_values", "custom_property_values", { "updated" }, {
    partial = { "gitbucket" },
  }),
  event("delete", "delete", { "" }, {
    supported = provider_list(REF_PROVIDERS, "codecommit"),
  }),
  event(
    "dependabot_alert",
    "dependabot_alert",
    { "created", "dismissed", "fixed", "reintroduced", "reopened" },
    {
      partial = { "azuredevops", "gitbucket" },
      unsupported = { "gitlab" },
    }
  ),
  event("deploy_key", "deploy_key", { "created", "deleted" }, {
    unsupported = provider_list(GITEA_FAMILY, "gitlab"),
  }),
  event("deployment", "deployment", { "created" }, {
    supported = { "azuredevops", "gitlab" },
    partial = { "harness" },
  }),
  event("deployment_protection_rule", "deployment.protection_rule", { "requested" }, {}),
  event("deployment_review", "deployment.review", { "approved", "rejected", "requested" }, {
    partial = { "azuredevops", "harness" },
  }),
  event("deployment_status", "deployment.status", { "created" }, {
    supported = { "azuredevops", "gitlab" },
    partial = { "harness" },
  }),
  event("discussion", "discussion", {
    "created",
    "edited",
    "deleted",
    "transferred",
    "pinned",
    "unpinned",
    "labeled",
    "unlabeled",
    "locked",
    "unlocked",
    "category_changed",
    "answered",
    "unanswered",
  }, {
    partial = { "codeberg", "gitbucket", "sourcehut" },
  }),
  event("discussion_comment", "discussion.comment", { "created", "edited", "deleted" }, {
    partial = { "sourcehut" },
  }),
  event("fork", "fork", { "" }, {
    supported = GITEA_FAMILY,
    partial = { "pagure" },
    unsupported = provider_list("gitlab", BITBUCKET_FAMILY),
  }),
  event("github_app_authorization", "github_app_authorization", { "revoked" }, {}),
  event("gollum", "gollum", { "" }, {
    supported = { "gitlab" },
    partial = provider_list(GITEA_FAMILY, "sourcehut"),
  }),
  event(
    "installation",
    "installation",
    { "created", "deleted", "new_permissions_accepted", "suspend", "unsuspend" },
    {
      supported = { "confusio" },
    }
  ),
  event("installation_repositories", "installation.repositories", { "added", "removed" }, {
    supported = { "confusio" },
  }),
  event("installation_target", "installation.target", { "renamed" }, {}),
  event("issue_comment", "issue.comment", { "created", "edited", "deleted" }, {
    supported = ISSUE_PROVIDERS,
    partial = provider_list(BITBUCKET_FAMILY, "gitbucket", "launchpad", "radicle"),
  }),
  event("issues", "issue", {
    "opened",
    "edited",
    "deleted",
    "transferred",
    "pinned",
    "unpinned",
    "closed",
    "reopened",
    "assigned",
    "unassigned",
    "labeled",
    "unlabeled",
    "locked",
    "unlocked",
    "milestoned",
    "demilestoned",
  }, {
    supported = ISSUE_PROVIDERS,
    partial = provider_list(BITBUCKET_FAMILY, "gitbucket", "launchpad", "radicle"),
  }),
  event("label", "label", { "created", "edited", "deleted" }, {
    supported = provider_list(GITEA_FAMILY, "gitlab", "sourcehut"),
    partial = { "pagure" },
  }),
  event(
    "marketplace_purchase",
    "marketplace_purchase",
    { "purchased", "cancelled", "changed", "pending_change", "pending_change_cancelled" },
    {}
  ),
  event("member", "member", { "added", "edited", "deleted" }, {
    supported = { "gitlab" },
    partial = provider_list(GITEA_FAMILY, "gitbucket", "sourcehut"),
  }),
  event("membership", "membership", { "added", "removed" }, {
    partial = { "gitbucket", "gitlab" },
  }),
  event("merge_group", "merge_group", { "checks_requested", "destroyed" }, {}),
  event("meta", "meta", { "deleted" }, {}),
  event("milestone", "milestone", { "created", "closed", "opened", "edited", "deleted" }, {
    supported = provider_list(GITEA_FAMILY, "gitlab"),
    partial = { "gitbucket" },
  }),
  event("org_block", "org_block", { "blocked", "unblocked" }, {}),
  event(
    "organization",
    "organization",
    { "created", "deleted", "renamed", "member_added", "member_removed", "member_invited" },
    {
      supported = { "gitlab", "sourcehut" },
      partial = provider_list(GITEA_FAMILY, "gitbucket"),
    }
  ),
  event("package", "package", { "created", "published", "updated", "deleted" }, {
    partial = provider_list(GITEA_FAMILY, "gitbucket", "launchpad"),
    unsupported = { "gitlab" },
  }),
  event("page_build", "page_build", { "" }, {
    unsupported = provider_list(GITEA_FAMILY, "gitlab"),
  }),
  event(
    "personal_access_token_request",
    "personal_access_token_request",
    { "approved", "cancelled", "created", "denied" },
    {
      partial = { "gitlab" },
    }
  ),
  event("ping", "ping", { "" }, {
    supported = provider_list(GITEA_FAMILY, "gitlab", BITBUCKET_FAMILY, "launchpad"),
  }),
  event(
    "project",
    "project",
    { "created", "updated", "closed", "reopened", "edited", "deleted" },
    {
      partial = provider_list(GITEA_FAMILY, "gitbucket", "gitlab", "sourcehut", "tuleap"),
    }
  ),
  event("project_card", "project.card", { "converted", "created", "deleted", "edited", "moved" }, {
    supported = { "gitbucket" },
  }),
  event("project_column", "project.column", { "created", "deleted", "edited", "moved" }, {
    supported = { "gitbucket" },
  }),
  event("projects_v2", "projects_v2", { "created", "edited", "closed", "reopened", "deleted" }, {
    partial = { "gitbucket" },
  }),
  event(
    "projects_v2_item",
    "projects_v2.item",
    { "created", "edited", "deleted", "archived", "restored", "converted" },
    {
      partial = { "gitbucket" },
    }
  ),
  event(
    "projects_v2_status_update",
    "projects_v2.status_update",
    { "created", "edited", "deleted" },
    {
      supported = { "gitbucket" },
    }
  ),
  event("public", "public", { "" }, {
    unsupported = provider_list(GITEA_FAMILY, "gitlab"),
  }),
  event("pull_request", "pull_request", {
    "assigned",
    "unassigned",
    "review_requested",
    "review_request_removed",
    "labeled",
    "unlabeled",
    "opened",
    "edited",
    "closed",
    "reopened",
    "synchronize",
    "ready_for_review",
    "converted_to_draft",
    "locked",
    "unlocked",
    "enqueued",
    "dequeued",
    "milestoned",
    "demilestoned",
    "auto_merge_enabled",
    "auto_merge_disabled",
  }, {
    supported = provider_list(PULL_REQUEST_PROVIDERS, "codecommit"),
  }),
  event("pull_request_review", "pull_request.review", { "submitted", "edited", "dismissed" }, {
    supported = provider_list(
      GITEA_FAMILY,
      "gitlab",
      BITBUCKET_FAMILY,
      CHANGE_REVIEW_PROVIDERS,
      "codecommit"
    ),
    partial = { "azuredevops", "gitbucket", "radicle", "sourcehut" },
  }),
  event(
    "pull_request_review_comment",
    "pull_request.review_comment",
    { "created", "edited", "deleted" },
    {
      supported = provider_list(
        GITEA_FAMILY,
        "gitlab",
        BITBUCKET_FAMILY,
        CHANGE_REVIEW_PROVIDERS,
        "codecommit"
      ),
      partial = { "azuredevops", "radicle", "sourcehut" },
    }
  ),
  event("pull_request_review_thread", "pull_request.review_thread", { "resolved", "unresolved" }, {
    partial = provider_list(GITEA_FAMILY, "gitlab", BITBUCKET_FAMILY),
  }),
  event("push", "push", { "" }, {
    supported = provider_list(REF_PROVIDERS, "launchpad", "codecommit"),
  }),
  event("registry_package", "registry_package", { "published", "updated" }, {
    unsupported = provider_list(GITEA_FAMILY, "gitlab"),
  }),
  event(
    "release",
    "release",
    { "published", "unpublished", "created", "edited", "deleted", "prereleased", "released" },
    {
      supported = provider_list(GITEA_FAMILY, "gitlab"),
      partial = { "azuredevops", "gitbucket", "harness" },
    }
  ),
  event("repository", "repository", {
    "created",
    "deleted",
    "archived",
    "unarchived",
    "publicized",
    "privatized",
    "renamed",
    "edited",
    "transferred",
  }, {
    supported = provider_list(GITEA_FAMILY, "gitlab", "azuredevops", "sourcehut"),
    partial = provider_list(
      BITBUCKET_FAMILY,
      SIMPLE_GIT_PROVIDERS,
      "gerrit",
      "phabricator",
      "rhodecode",
      "sourceforge"
    ),
  }),
  event(
    "repository_advisory",
    "repository.advisory",
    { "published", "updated", "withdrawn", "reported" },
    {
      partial = { "gitbucket" },
    }
  ),
  event("repository_dispatch", "repository.dispatch", { "" }, {}),
  event("repository_import", "repository.import", { "success", "failure", "cancel" }, {
    unsupported = provider_list(GITEA_FAMILY, "gitlab"),
  }),
  event("repository_ruleset", "repository.ruleset", { "created", "edited", "deleted" }, {}),
  event(
    "repository_vulnerability_alert",
    "repository.vulnerability_alert",
    { "create", "dismiss", "resolve" },
    {
      unsupported = { "gitlab" },
    }
  ),
  event(
    "secret_scanning_alert",
    "secret_scanning_alert",
    { "created", "reopened", "resolved", "revoked", "validated" },
    {
      partial = { "azuredevops", "gitbucket" },
      unsupported = { "gitlab" },
    }
  ),
  event("secret_scanning_alert_location", "secret_scanning_alert.location", { "created" }, {
    partial = { "gitbucket" },
    unsupported = { "gitlab" },
  }),
  event("security_advisory", "security_advisory", { "published", "updated", "withdrawn" }, {
    partial = { "gitbucket" },
  }),
  event("security_and_analysis", "security_and_analysis", { "" }, {
    unsupported = provider_list(GITEA_FAMILY, "gitlab"),
  }),
  event("sponsorship", "sponsorship", {
    "created",
    "cancelled",
    "edited",
    "tier_changed",
    "pending_cancellation",
    "pending_tier_change",
  }, {}),
  event("star", "star", { "created", "deleted" }, {
    supported = provider_list(GITEA_FAMILY),
    partial = { "gitlab" },
  }),
  event("status", "status", { "" }, {
    supported = provider_list(GITEA_FAMILY, "gitlab", BITBUCKET_FAMILY, CHANGE_REVIEW_PROVIDERS),
    partial = { "azuredevops", "harness", "sourcehut" },
  }),
  event("sub_issues", "sub_issues", {
    "parent_issue_added",
    "parent_issue_removed",
    "sub_issue_added",
    "sub_issue_removed",
    "sub_issue_reprioritized",
  }, {}),
  event(
    "team",
    "team",
    { "created", "deleted", "edited", "added_to_repository", "removed_from_repository" },
    {
      partial = { "gitbucket", "gitlab" },
    }
  ),
  event("team_add", "team.add", { "" }, {
    partial = { "gitbucket", "gitlab" },
  }),
  event("watch", "watch", { "started" }, {
    supported = provider_list(GITEA_FAMILY),
    partial = { "gitlab" },
  }),
  event("workflow_dispatch", "workflow.dispatch", { "" }, {
    unsupported = provider_list(GITEA_FAMILY, "gitlab", "azuredevops", "harness"),
  }),
  event("workflow_job", "workflow.job", { "queued", "in_progress", "completed", "waiting" }, {
    supported = { "gitlab" },
    partial = { "azuredevops", "bitbucket", "harness", "phabricator", "sourcehut" },
  }),
  event("workflow_run", "workflow.run", { "requested", "in_progress", "completed" }, {
    supported = { "gitlab" },
    partial = {
      "azuredevops",
      "bitbucket",
      "codeberg",
      "forgejo",
      "gitea",
      "harness",
      "launchpad",
      "onedev",
      "phabricator",
      "sourcehut",
    },
  }),
}

attach_provider_sources(EVENT_DEFS, "rhodecode", RHODECODE_WEBHOOK_SOURCES)

local CATALOG_BY_EVENT = {}
local EVENT_NAMES = {}
for _, def in ipairs(EVENT_DEFS) do
  CATALOG_BY_EVENT[def.name] = def
  EVENT_NAMES[def.name] = true
end

webhook_event_catalog = { -- luacheck: globals webhook_event_catalog
  providers = PROVIDERS,
  events = EVENT_DEFS,
  by_event = CATALOG_BY_EVENT,
}

function webhook_catalog_events() -- luacheck: globals webhook_catalog_events
  return EVENT_DEFS
end

function webhook_catalog_providers() -- luacheck: globals webhook_catalog_providers
  return PROVIDERS
end

function webhook_catalog_event_names() -- luacheck: globals webhook_catalog_event_names
  return EVENT_NAMES
end

function webhook_catalog_event(name) -- luacheck: globals webhook_catalog_event
  return CATALOG_BY_EVENT[name]
end

function webhook_catalog_event_known(name) -- luacheck: globals webhook_catalog_event_known
  return EVENT_NAMES[name] == true
end

function webhook_catalog_normalized_base(name) -- luacheck: globals webhook_catalog_normalized_base
  local def = CATALOG_BY_EVENT[name]
  return def and def.normalized_base or nil
end

function webhook_catalog_event_for_normalized_type(value) -- luacheck: globals webhook_catalog_event_for_normalized_type
  if type(value) ~= "string" or value == "" then
    return nil, nil
  end
  local match = nil
  for _, def in ipairs(EVENT_DEFS) do
    local base = def.normalized_base
    if value == base or value:sub(1, #base + 1) == base .. "." then
      if not match or #base > #match.normalized_base then
        match = def
      end
    end
  end
  if not match then
    return nil, nil
  end
  if value == match.normalized_base then
    return match.name, ""
  end
  return match.name, value:sub(#match.normalized_base + 2)
end
