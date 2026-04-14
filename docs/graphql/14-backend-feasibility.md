# 14 — Per-Backend GraphQL Feasibility Matrix and Fallback Policy

## What this document covers

GraphQL coverage in confusio is bounded by each backend's REST coverage: a GraphQL
resolver calls the same REST endpoint that the REST handler already uses.  This document
states the fallback policy for unsupported fields, derives a feasibility matrix from the
existing compatibility CSV, and notes backend-specific constraints that affect GraphQL
resolver behaviour beyond the plain REST surface.

## Fallback policy

### Fields with no resolver and no parent data

When `execute_field` finds neither a registered resolver nor a value in the parent table
for a field, `complete_value` receives `nil`:

- A **nullable** field evaluates to `null` in the response — no error.
- A **non-null** field triggers null propagation (see [09-errors.md](09-errors.md)) and
  an error entry.

This means a client querying a field that no resolver implements will receive `null`
silently for optional fields — which is the same behaviour as GitHub when a field is
genuinely absent.

### Resolver returns nil after an error

When a resolver calls `graphql_fetch_or_error` and the backend returns a non-200 status,
the resolver records an error in `ctx.errors` and returns `nil`.  The field is `null` in
the response and the error describes why (e.g. `"NOT_FOUND"`, `"FORBIDDEN"`).

### Backends without a REST endpoint

When a backend's `compatibility.csv` value for an endpoint is `n` (not supported), the
corresponding REST handler either returns 404 or is absent from `backend_impl`.  If a
GraphQL resolver calls that endpoint, `graphql_fetch_or_error` records a `NOT_FOUND` or
`INTERNAL_ERROR` and the field is `null`.

No GraphQL-specific "not implemented" stub is needed — the null result plus error entry
is the correct GraphQL expression of "this backend doesn't support this".

### Backends with partial REST support

When a backend's CSV value is `~explanation`, the resolver produces partial results.
Examples:

| CSV value | GraphQL effect |
|---|---|
| `~no email fields` | `author.email` is `""` on all commits |
| `~no date fields` | `committedDate` is `""` on all commits |
| `~files only` | `repository.object` works for blob paths; directory paths return `null` + error |
| `~primary language only` | `repository.languages.edges` has exactly one entry |

These constraints are documented per-backend in the matrix below and match what the REST
layer already does.

## Feasibility matrix

The matrix grades each backend's GraphQL capability for the Phase 1 root fields and key
sub-fields.  The grade derives directly from the CSV.

**Grade key:**

| Grade | Meaning |
|---|---|
| `✓` | Full support — REST endpoint exists and translator covers all Phase 1 fields |
| `~` | Partial — REST endpoint exists but one or more fields are missing/degraded |
| `✗` | Not supported — REST endpoint absent; field returns `null` (nullable) or error (non-null) |
| `—` | Not applicable (field not meaningful for this backend) |

### Root fields

| Root field | gitea / forgejo / codeberg / notabug / gogs | gitlab | bitbucket | bitbucket_datacenter | gitbucket | azuredevops | sourcehut | pagure | gerrit | others |
|---|---|---|---|---|---|---|---|---|---|---|
| `viewer` | `✓` | `✓` | `✓` | `✗` | `✓` | `✗` | `✓` | `✓` | `✓` | varies |
| `user(login)` | `✓` | `✓` | `✓` | `✓` | `✓` | `✗` | `✗` | `✓` | `✓` | varies |
| `organization(login)` | `✓` | `✓` | `✓` | `✓` | `✓` | `✓` | `✗` | `✗` | `✗` | varies |
| `repository(owner,name)` | `✓` | `✓` | `✓` | `✓` | `✓` | `✓` | `✓` | `✓` | `✓` | varies |
| `repositoryOwner(login)` | `✓` | `✓` | `✓` | `✓` | `✓` | `✗` | `✗` | `✗` | `✗` | varies |
| `node(id)` | `~` (type-dependent) | `~` | `~` | `~` | `~` | `✗` | `✗` | `~` | `✗` | `✗` |
| `search(...)` | `✓` | `✓` | `~` | `✓` | `✓` | `✗` | `~` | `✗` | `✗` | varies |
| `rateLimit` | `✓` | `✓` | `✓` | `✓` | `✓` | `✓` | `✓` | `✓` | `✓` | `✓` |
| `meta` | `✓` | `✓` | `✓` | `✓` | `✓` | `✓` | `✓` | `✓` | `✓` | `✓` |

(`rateLimit` and `meta` are always `✓` because they are synthesised or use the same REST
endpoint across all backends — see [10-auth-ratelimit.md](10-auth-ratelimit.md).)

### `Repository` sub-fields

| Sub-field | REST call | gitea family | gitlab | bitbucket | gitbucket | azuredevops | sourcehut | pagure | gerrit |
|---|---|---|---|---|---|---|---|---|---|
| `nameWithOwner`, `description`, `url`, scalar fields | `GET /repos/{o}/{r}` | `✓` | `✓` | `✓` | `✓` | `✓` | `✓` | `✓` | `✓` |
| `stargazerCount` | same | `✓` | `✓` | `✓` | `✓` | `✗` | `✗` | `✓` | `✗` |
| `primaryLanguage` | same | `✓` | `✓` | `~` (primary only) | `✓` | `✓` | `✗` | `✗` | `✗` |
| `issues` connection | `GET /repos/{o}/{r}/issues` | `✓` | `✓` | `✓` | `✓` | `✓` | `✗` | `✓` | `✗` |
| `pullRequests` connection | `GET /repos/{o}/{r}/pulls` | `✓` | `✓` | `✓` | `✓` | `✗` | `✗` | `✗` | `✗` |
| `releases` connection | `GET /repos/{o}/{r}/releases` | `✓` | `✓` | `✗` | `✓` | `✗` | `✗` | `✗` | `✗` |
| `labels` connection | `GET /repos/{o}/{r}/labels` | `✓` | `✓` | `✗` | `✓` | `✗` | `✗` | `~` (stub only) | `✗` |
| `milestones` connection | `GET /repos/{o}/{r}/milestones` | `✓` | `✓` | `✓` | `✓` | `✗` | `✗` | `✗` | `✗` |
| `refs` connection (branches/tags) | `GET /repos/{o}/{r}/branches` | `✓` | `✓` | `✓` | `✓` | `✓` | `✓` | `✓` | `✓` |
| `defaultBranchRef` | derived from repo response | `✓` | `✓` | `✓` | `✓` | `✓` | `✓` | `✗` | `✗` |
| `collaborators` connection | `GET /repos/{o}/{r}/collaborators` | `✓` | `✓` | `✓` | `✓` | `✗` | `✗` | `✗` | `✗` |
| `languages` connection | `GET /repos/{o}/{r}/languages` | `✓` | `✓` | `~` (primary only) | `✓` | `✗` | `✗` | `✗` | `✗` |

### `Issue` sub-fields

| Sub-field | gitea family | gitlab | bitbucket | gitbucket | others |
|---|---|---|---|---|---|
| `number`, `title`, `body`, `state`, scalar fields | `✓` | `✓` | `✓` | `✓` | varies |
| `author` | `✓` | `✓` | `✓` | `✓` | varies |
| `labels` connection | `✓` | `✓` | `✗` | `✓` | `✗` |
| `comments` connection | `✓` | `✓` | `✗` | `✓` | varies |
| `assignees` connection | `✓` | `✓` | `✗` | `✓` | varies |
| `milestone` | `✓` | `✓` | `✓` | `✓` | varies |
| `reactions` connection | `✓` | `✗` | `✗` | `✗` | `✗` |

### `Commit` sub-fields

| Sub-field | gitea family | gitlab | bitbucket | azuredevops | others |
|---|---|---|---|---|---|
| `oid`, `messageHeadline`, `committedDate` | `✓` | `✓` | `✓` | `✓` | varies |
| `author.email` | `✓` | `✓` | `~` (always `""`) | `✓` | varies |
| `author.date` | `✓` | `✓` | `✓` | `~` (always `""`) | varies |
| `statusCheckRollup` | `✓` (via commit statuses) | `✓` | `✗` | `✓` | `✗` |

## Backend-specific notes

### Gitea family (gitea, forgejo, codeberg, gogs, notabug)

Gitea is the primary target for Phase 1.  All Phase 1 resolvers are implemented for
Gitea first; family aliases inherit them via `load_family_backend("gitea")`.

**gogs and notabug**: The `strip` patterns in `provider_families` remove package and
Actions handlers from the alias.  GraphQL resolvers registered as `graphql_resolvers`
keys are not stripped (they are not in `backend_impl`).  A new `strip`-equivalent for
GraphQL resolvers is not needed yet; if gogs/notabug-specific gaps are discovered during
implementation, those resolvers are registered conditionally:

```lua
-- In graphql_resolvers registration, after load_family_backend:
if config.backend == "gogs" or config.backend == "notabug" then
  graphql_resolvers["Repository.releases"] = function(parent, args, ctx)
    return graphql_error(ctx, "releases not supported on this backend",
      nil, "BAD_USER_INPUT")
  end
end
```

**notabug**: Strips gitignore templates. `Query.gitignoreTemplate` and
`Query.gitignoreTemplates` return `null`.

### GitLab

GitLab uses URL-encoded project paths (`owner%2Frepo`) via `owner_repo_id(owner, repo)`.
All GraphQL resolvers for GitLab must apply this encoding when constructing REST URLs.

GitLab reactions (`thumbsup`, `thumbsdown`, etc.) use a different endpoint
(`/projects/{id}/issues/{n}/award_emoji`) and a different format; the `reactions`
sub-field for issues returns `null` on GitLab.

GitLab issues have separate "confidential" issues that behave differently; the translator
maps `confidential = true` to a `visibility` field but does not surface it in the Phase 1
schema subset.

### Bitbucket Cloud

`GET /user` returns the authenticated user but uses a different field structure than
GitHub.  The existing `translate_user` handles this; `graphql_translate_user` builds on
it.

Bitbucket does not expose commit author email addresses in its commits API.
`Commit.author.email` is always `""`.  This is noted in the CSV as `~no email fields` and
carries over to the GraphQL layer.

Bitbucket does not have a `GET /orgs` endpoint in the same sense; organisations are
"workspaces".  `Query.organization` maps to `GET /2.0/workspaces/{workspace}`.  The
existing REST handler for `GET /orgs/{org}` covers this.

`node()` for issues is not supported on Bitbucket Cloud because the issue REST endpoint
requires workspace+repo context (`GET /2.0/repositories/{w}/{r}/issues/{n}`) but
Bitbucket's issue IDs in the node local_id format do include owner/repo/number, so the
resolver can construct the path.  The `node.Issue` resolver for Bitbucket is feasible but
not in Phase 1 scope.

### Bitbucket Data Center

`GET /user` is absent from the Data Center REST API (CSV value `n`).  `Query.viewer`
returns `null` for Bitbucket Data Center.  The resolver records no error (null is valid
for an unauthenticated-equivalent scenario); callers cannot rely on `viewer`.

### GitBucket

GitBucket mirrors the GitHub v3 REST API at `/api/v3/`.  Its responses are already in
GitHub REST shape; translator functions pass through with minimal transformation.  This
makes GitBucket one of the highest-fidelity backends for GraphQL: any Phase 1 resolver
that works for Gitea will work for GitBucket with a path prefix change.

The GitBucket backend sets `base()` to `config.base_url .. "/api/v3"`, so resolver URLs
are automatically correct.

### Azure DevOps

Azure DevOps has a fundamentally different API structure.  It supports repositories and
commits but not issues (uses Work Items instead), pull requests (uses its own PR model),
or releases (uses Pipelines).

`Query.repository` works.  `repository.issues` and `repository.pullRequests` return empty
connections with no error (not an error condition — ADO simply has no issues endpoint in
the GitHub sense).

`Query.viewer` is not supported (`GET /user` absent — CSV `n`).  `Query.viewer` returns
`null` with a `FORBIDDEN` or `NOT_FOUND` error depending on the ADO response.

### Sourcehut

Sourcehut has a native GraphQL API but confusio targets its REST API (Hut REST).
`GET /repos/{owner}/{repo}` exists and works.  Issues, pull requests, and releases are
absent or partially supported.

`Query.user` is not supported (CSV `n`).

`search` maps to Sourcehut's projects API; repository search is partial (`~via projects API`).

### Pagure

`GET /repos/{owner}/{repo}` works.  `GET /users/{username}` works.
Issues work (`GET /repos/{owner}/{repo}/issues`).  Pull requests are absent.

`node.Issue` is not feasible on Pagure: there is no endpoint to look up an issue by
integer ID without listing all issues.  The `node.Issue` resolver for Pagure returns
`nil` immediately (no REST call), consistent with the [08-node-id.md](08-node-id.md)
policy for backends without sub-resource ID lookup.

### Gerrit

Gerrit uses change IDs and patch sets rather than issues and pull requests.  None of the
issue or PR resolvers apply.  `GET /repos/{owner}/{repo}` is mapped to Gerrit's project
API.

`Query.viewer` works (Gerrit's `/accounts/self` endpoint maps to the user shape).

Most sub-fields beyond the repository scalar fields return `null`.

### Launchpad

Only `GET /repos/{owner}/{repo}/issues` has `y` in the CSV; everything else is `n` or
absent.  The GraphQL layer surfaces only `repository.issues`; all other sub-fields return
`null`.

`Query.viewer`, `Query.user`, and `Query.organization` all return `null`.

### CodeCommit, Harness, Kallithea, Phabricator, Radicle, RhodeCode, SourceForge, Tuleap, OneDev

These backends have sparse REST coverage.  GraphQL resolver registration follows the same
pattern: only register resolvers for endpoints with `y` or `~` in the CSV.  Fields
without a resolver silently return `null`.

No GraphQL-specific code is written for these backends in Phase 1.  The fallback policy
(null for unsupported fields) provides a functioning, if limited, GraphQL endpoint.

## Resolver registration strategy by backend

### Tier 1: Full Phase 1 coverage

Backends with REST `y` for all or most Phase 1 endpoints:

| Backend | Resolver registration file |
|---|---|
| gitea | `backends/gitea.lua` (inline, at bottom) |
| forgejo | inherits from gitea via `load_family_backend` |
| codeberg | inherits from gitea |
| gogs | inherits from gitea (minus Actions/package resolvers if any) |
| notabug | inherits from gitea (minus gitignore resolvers) |
| gitbucket | `backends/gitbucket.lua` (path prefix differs) |
| gitlab | `backends/gitlab.lua` (URL encoding, field differences) |

### Tier 2: Partial coverage

Backends where the key root fields work but sub-fields are sparse:

| Backend | Notable gap |
|---|---|
| bitbucket | `viewer` works; no `labels`, no `reactions`; commit email always `""` |
| bitbucket_datacenter | no `viewer`; `repository` and `issues` work |
| azuredevops | `repository` works; no `issues`, no `viewer` |
| sourcehut | `repository` works; `issues`, `pullRequests` absent |
| pagure | `repository` + `issues` work; no `pullRequests`, no `node.Issue` |

These backends register resolvers only for supported endpoints.  Unsupported fields fall
back to `null` via the default policy.

### Tier 3: Minimal / no coverage

Backends with fewer than three Phase 1 root fields supported:

`gerrit`, `launchpad`, `codecommit`, `harness`, `kallithea`, `phabricator`, `radicle`,
`rhodecode`, `sourceforge`, `tuleap`, `onedev`.

These backends register no GraphQL resolvers in Phase 1.  `POST /graphql` responds to
introspection correctly (schema is independent of backend) and to simple scalar queries
on `repository` if the REST endpoint works.  All connection and sub-field requests return
`null`.

## `totalCount` accuracy by backend

[07-pagination.md](07-pagination.md) specifies four sources for `totalCount`.  Their
availability per backend:

| Backend | Source |
|---|---|
| gitea family | `X-Total` header on list responses |
| gitlab | `X-Total` header |
| bitbucket | `pagelen` + `size` in response body |
| gitbucket | `X-Total-Count` header |
| azuredevops | `value` + `count` in response body |
| others | fallback: `#nodes` on current page (lower bound) |

Backends that fall back to `#nodes` produce a `totalCount` that equals the page size on
every full page and the actual count on the last page.  This is documented in the
compatibility site per-backend.

## Phase 2 mutations — backend feasibility preview

Write endpoints follow the same derivation: if the REST handler for `POST /repos/{o}/{r}/issues`
is `y` in the CSV, `Mutation.createIssue` is feasible for that backend.

| Mutation category | gitea family | gitlab | bitbucket | gitbucket | others |
|---|---|---|---|---|---|
| `createRepository` | `✓` | `✓` | `✓` | `✓` | varies |
| `createIssue` | `✓` | `✓` | `✓` | `✓` | varies |
| `createPullRequest` | `✓` | `✓` | `✓` | `✓` | `✗` mostly |
| `addComment` | `✓` | `✓` | `✗` | `✓` | `✗` mostly |
| `addStar` | `✓` | `✓` | `✓` | `✓` | varies |
| `mergePullRequest` | `✓` | `✓` | `✓` | `✓` | `✗` mostly |

This preview is informational; the Phase 2 mutation design ([11-mutations.md](11-mutations.md))
is authoritative for the implementation plan.
