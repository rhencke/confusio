# 01 — GitHub GraphQL API Surface, Scale, and Scope Assumptions

## What this document covers

Before designing a translation layer it is necessary to understand what it must translate.
This document characterises GitHub's GraphQL API — its endpoint, schema scale, rate-limit
model, and feature inventory — and then states the explicit scope assumptions that all
subsequent design documents build on.

## GitHub GraphQL basics

### Single endpoint

All GraphQL traffic goes to one HTTP endpoint:

```
POST https://api.github.com/graphql
Content-Type: application/json
Authorization: Bearer <token>

{ "query": "...", "variables": {...}, "operationName": "..." }
```

From confusio's perspective this means `POST /graphql` is the only new route.  Unlike the
REST catalog, there are no method-differentiated paths to register — one route, one handler.

### Authentication

Bearer tokens work identically to the REST layer: the client sends `Authorization: Bearer
<token>` and confusio forwards it unchanged to the upstream backend.  The same token that
authenticates REST calls also authenticates GraphQL calls.  No new auth mechanism is needed.

Unauthenticated GraphQL requests are allowed by GitHub for a very small set of public
queries, but practically all useful queries require authentication.  Confusio will apply
the same `backend_allow_anonymous` gate to `/graphql` as to the REST routes.

### Schema publication

GitHub publishes its SDL schema at:

```
https://docs.github.com/public/fpt/schema.docs.graphql
```

The schema is large (see "Scale" below) but stable in shape; GitHub follows a no-breaking-
change deprecation policy.  Fields are deprecated rather than removed, and new fields are
added frequently.  Confusio will vendor a snapshot of the schema, similar to how
`vendor/github-rest-api-description/` holds the REST OpenAPI spec.

## Scale

### Schema size

GitHub's GraphQL schema (as of mid-2025) contains approximately:

| Kind | Count |
|------|------:|
| Object types | ~210 |
| Interface types | ~30 |
| Union types | ~30 |
| Enum types | ~70 |
| Input object types | ~130 |
| Scalar types | ~15 |
| Query root fields | ~45 |
| Mutation root fields | ~165 |
| Total named types | ~490 |
| Total fields (across all types) | ~3 500 |

For comparison, confusio's REST catalog contains 734 endpoints across 30 groups.  The
GraphQL schema covers overlapping ground but organises it differently: a single `repository`
type carries ~200 fields rather than ~80 separate REST paths.

### Relay connections

Pagination in GitHub's GraphQL uses the [Relay Connection
specification](https://relay.dev/graphql/connections.htm).  Almost every list field is a
`*Connection` type with `edges { node cursor } pageInfo { hasNextPage endCursor }` and a
`totalCount`.  This is structurally uniform but means every paginated field requires a
cursor↔page translation when the upstream provider uses REST page numbers.

Confusio's REST translation layer already maps `per_page`/`page` query parameters; the
GraphQL layer will map `first`/`after` (forward pagination) and `last`/`before` (backward
pagination) to those same page parameters.  This is covered in [07-pagination.md](07-pagination.md).

### Rate limiting

GitHub charges a "node cost" per query:

- Each leaf scalar field costs 0 points.
- Each node (object) fetched costs 1 point.
- Connection fields multiply by the `first`/`last` argument value.
- Mutations cost a flat 1 point for the mutation itself plus node costs for the returned
  selection set.
- The default limit is **5 000 points per hour** per authenticated user.
- The introspection query (`__schema`) is exempt from rate limiting.

The `rateLimit { cost remaining resetAt }` field can be requested on any query.  GitHub
clients routinely include it to track consumption.  Confusio must return a plausible
`rateLimit` response even when the upstream backend does not expose one.  This is covered
in [10-auth-ratelimit.md](10-auth-ratelimit.md).

### Introspection

All GraphQL clients depend on introspection (`__schema`, `__type`) to discover the schema
at development time (code generation, IDE tooling) and at runtime (dynamic clients).
Introspection is not translated to backend REST calls; confusio answers it directly from the
vendored schema.  This is a hard requirement — any client that sends an introspection query
before its first real query will fail if introspection is not implemented.

## Feature inventory

### Query root fields (select)

The query root fields most relevant to confusio's existing REST coverage:

| Field | Maps to |
|-------|---------|
| `viewer` | `GET /user` |
| `user(login)` | `GET /users/{login}` |
| `organization(login)` | `GET /orgs/{org}` |
| `repositoryOwner(login)` | `GET /users/{login}` or `/orgs/{org}` |
| `repository(owner, name)` | `GET /repos/{owner}/{repo}` |
| `node(id)` / `nodes(ids)` | per-type REST lookup by decoded ID |
| `search(query, type, first)` | `GET /search/{repositories,users,issues}` |
| `rateLimit` | synthesised or `GET /rate_limit` |
| `meta` | `GET /meta` |
| `topic(name)` | `GET /topics/{topic}` |
| `license(key)` / `licenses` | `GET /licenses/{key}` / `GET /licenses` |
| `gitignoreTemplate(name)` / `gitignoreTemplates` | `GET /gitignore/templates` |
| `codesOfConduct` / `codeOfConduct(key)` | `GET /codes_of_conduct` |
| `securityAdvisories` | `GET /advisories` |

Fields with no REST counterpart in confusio's catalog (marketplace, sponsors, relay,
resource) will return `null` or a stub error initially.

### Mutations (select)

The mutation categories that map to confusio's existing REST coverage:

| Category | Examples | REST equivalent |
|----------|----------|-----------------|
| Repositories | `createRepository`, `updateRepository`, `deleteRepository` | `POST /user/repos`, `PATCH /repos/{o}/{r}`, `DELETE /repos/{o}/{r}` |
| Issues | `createIssue`, `updateIssue`, `closeIssue` | `POST /repos/{o}/{r}/issues`, `PATCH /…/issues/{n}` |
| Pull requests | `createPullRequest`, `updatePullRequest`, `mergePullRequest` | `POST /repos/{o}/{r}/pulls`, `PATCH`, `PUT /…/merge` |
| Labels | `createLabel`, `addLabelsToLabelable` | `POST /repos/{o}/{r}/labels` |
| Comments | `addComment`, `updateIssueComment`, `deleteIssueComment` | `POST/PATCH/DELETE /repos/{o}/{r}/issues/{n}/comments` |
| Reactions | `addReaction`, `removeReaction` | `POST/DELETE /repos/{o}/{r}/issues/{n}/reactions` |
| Stars | `addStar`, `removeStar` | `PUT/DELETE /user/starred/{o}/{r}` |
| Projects (v2) | `createProjectV2`, `updateProjectV2` | no direct REST analog; low priority |

Subscriptions are not part of GitHub's public API and are out of scope entirely.

## Scope assumptions

The following assumptions apply to all subsequent design documents.  They represent
deliberate constraints, not oversights.

### In scope (Phase 1 — queries)

1. **`POST /graphql` route** receiving standard GraphQL request JSON.
2. **Query operations only** — mutations are deferred to Phase 2.
3. **Introspection** — `__schema` and `__type` answered from the vendored schema snapshot.
4. **Root fields that map to REST endpoints confusio already implements**: `viewer`, `user`,
   `organization`, `repository`, `repositoryOwner`, `node`/`nodes`, `search`, `rateLimit`,
   `meta`, `license`, `licenses`, `gitignoreTemplate`, `gitignoreTemplates`.
5. **Sub-fields within those types** up to the depth required by common GitHub clients
   (GitHub CLI, Octokit, GitHub Actions): repositories, issues, pull requests, commits,
   refs, releases, labels, milestones, reactions, comments, checks, deployments, teams.
6. **Relay-style pagination** on all Connection fields in the above types.
7. **Variables and fragments** — required by virtually every real-world client.
8. **`@skip` and `@include` directives** — the two built-in directives; custom directives
   are not supported.
9. **The standard `{"data": ..., "errors": [...]}` response envelope**.
10. **Partial results** — a resolver failure should populate `errors` and return `null` for
    that field rather than failing the entire query.

### In scope (Phase 2 — mutations)

11. **Mutation operations** for the categories listed in the mutations table above.

### Out of scope (explicitly)

- **Subscriptions**: GitHub's public API does not expose them; backends do not support them.
- **`@defer` / `@stream`**: Incremental delivery requires chunked responses; Redbean's
  single-threaded uniprocess model makes this impractical.
- **Persisted queries / APQ**: Automatic Persisted Queries require a server-side cache
  keyed by query hash.  No cache infrastructure exists today; this is a future addition.
- **GitHub Apps installation tokens / GHES Enterprise endpoints**: Confusio proxies
  whatever token the client supplies; it does not manage token lifecycle.
- **Marketplace, sponsors, billing, enterprise-admin types**: These have no REST analog in
  confusio's catalog and are likely unavailable on alternative backends.
- **`ProjectV2` beyond basic CRUD**: Project boards involve complex relational state that
  does not map cleanly to any backend's REST API.
- **Field-level deprecation warnings**: The schema marks deprecated fields but confusio
  will not surface `X-GitHub-Deprecation` headers on GraphQL responses.

### Per-backend assumptions

The GraphQL layer translates to the same REST calls confusio already makes.  A backend that
does not implement a REST handler will return `null` for the corresponding GraphQL field
(with an error entry).  This means the GraphQL completeness of each backend is bounded by
its REST completeness; no backend gains new REST coverage by adding GraphQL.

Backend-specific feasibility is covered in [14-backend-feasibility.md](14-backend-feasibility.md).

### Schema versioning assumption

Confusio will vendor a single schema snapshot.  It will not fetch the upstream schema at
runtime.  Clients that introspect will see the vendored snapshot; if GitHub adds a field
that confusio does not implement, a query for that field will receive `null` and an error
entry rather than a schema validation error.  Schema updates follow the same manual process
as REST spec updates (`vendor/github-rest-api-description/README.md`).

## Summary

| Dimension | Value |
|-----------|-------|
| New routes | 1 (`POST /graphql`) |
| Phase 1 scope | Queries, introspection, ~15 root fields, ~30 sub-types |
| Phase 2 scope | Mutations across ~8 categories |
| Permanently out of scope | Subscriptions, `@defer`/`@stream`, APQ, marketplace/enterprise types |
| Schema strategy | Vendored SDL snapshot, answered locally for introspection |
| Auth | Existing Bearer passthrough, existing `backend_allow_anonymous` gate |
| Rate limit | Synthesised `rateLimit` field; no upstream billing data |

The design documents that follow assume all of the above.  If a constraint changes (e.g.,
persisted queries become a requirement), the relevant doc should be updated before any
implementation begins.
