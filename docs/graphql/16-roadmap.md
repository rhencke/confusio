# 16 — Incremental Rollout Roadmap and Issue Decomposition Plan

## What this document covers

The 15 preceding design documents specify the full GraphQL implementation for confusio.
This document translates those specifications into a sequenced set of GitHub issues,
groups them into milestones, identifies dependencies, and defines the "done" criteria for
each phase.

## Phases

| Phase | Scope | Gate | Status |
|---|---|---|---|
| **0 — Schema prep** | Vendor SDL, write generator, produce `graphql_schema_data.lua` | Generated file committed; `make validate-schema` passes | ✅ complete |
| **1 — Query engine** | Parser, schema loader, executor, translators, Gitea resolvers, tests | `make test` green on gitea; `POST /graphql` works end-to-end for queries | ✅ complete |
| **1b — Additional backends** | Resolver registration for GitLab, GitBucket, Bitbucket, and others | Per-backend `<backend>-graphql.hurl` passes | ✅ complete |
| **2 — Mutations** | Mutation execution, write-side translators, Gitea mutation resolvers | `make test` green; mutation queries round-trip | 🔜 next |
| **2b — Batch & extras** | Batch requests, backward pagination, item-level cursors, APQ | Client compatibility tests pass | ⏳ future |

## Issue list

Each issue below maps to one or more design doc sections.  Issues within a phase are
ordered by dependency; later issues may be worked in parallel once their listed
predecessors are merged.

---

### Phase 0 — Schema prep

#### #GQL-01: Vendor GitHub GraphQL SDL and write schema generator

**Design doc**: [03-schema.md §SDL vendoring](03-schema.md)

**Deliverables**:
- `vendor/github-graphql-schema/schema.docs.graphql` — vendored SDL snapshot
- `vendor/github-graphql-schema/README.md` — update instructions
- `scripts/gen-graphql-schema.py` — reads SDL, outputs `graphql_schema_data.lua`
- `internal/graphql_schema_data.lua` — committed generated output
- `Makefile` targets: `generate-schema`, `validate-schema`

**Done when**: `make validate-schema` passes; `graphql_schema_data.lua` contains correct
type maps for all Phase 1 reachable types.

**Dependencies**: none

---

### Phase 1 — Query engine

#### #GQL-02: Implement GraphQL lexer and parser

**Design doc**: [02-lexer-parser.md](02-lexer-parser.md)

**Deliverables**:
- `internal/graphql_parser.lua` — exports `graphql_parse`, `graphql_tokenize`
- `test/graphql-parser.lua` — all unit tests from §Testing in 02-lexer-parser.md

**Done when**: all unit tests pass; `graphql_parse` round-trips the standard GitHub CLI
IntrospectionQuery without error.

**Dependencies**: #GQL-01 (needs schema_data for some parser-adjacent tests; can start in
parallel but must integrate before merge)

---

#### #GQL-03: Implement schema loader and type validation API

**Design doc**: [03-schema.md](03-schema.md)

**Deliverables**:
- `internal/graphql_schema.lua` — seven exported functions
- `test/graphql-schema.lua` — unit tests

**Done when**: `graphql_schema_field("Repository", "issues")` returns the correct field
definition; `graphql_introspect_schema()` returns a table that passes the standard
introspection assertions.

**Dependencies**: #GQL-01

---

#### #GQL-04: Implement query executor and resolver dispatch

**Design doc**: [04-executor.md](04-executor.md)

**Deliverables**:
- `internal/graphql_executor.lua` — `graphql_resolvers`, `graphql_handler`
- Catalog entry `{ "POST /graphql", "graphql_request", graphql_handler }` in
  `internal/catalog.lua`
- `defaults.graphql_stub` in `internal/defaults.lua`
- `test/graphql-executor.lua` — unit tests
- Phase 1 mutation/subscription rejection guard

**Done when**: `graphql_handler` executes `{ viewer { login } }` (with a mock resolver),
returns `{"data":{"viewer":{"login":"test"}}}`, and the mutation rejection test passes.

**Dependencies**: #GQL-02, #GQL-03

---

#### #GQL-05: Implement fragment, variable, directive, and introspection handling

**Design doc**: [06-fragments-vars-directives.md](06-fragments-vars-directives.md)

**Deliverables**:
- Fragment spread and inline fragment resolution in executor
- Variable coercion (`coerce_value`) for all 9 node kinds
- `@skip` / `@include` evaluation
- `__typename`, `__schema`, `__type` meta-field interception
- `test/graphql-fragments-vars.lua` — unit tests including standard IntrospectionQuery

**Done when**: the graphql-js standard IntrospectionQuery executes without error and
`__schema.queryType.name` returns `"Query"`.

**Dependencies**: #GQL-04

---

#### #GQL-06: Implement GraphQL-to-REST translation and connection helpers

**Design doc**: [05-translation.md](05-translation.md), [07-pagination.md](07-pagination.md),
[08-node-id.md](08-node-id.md)

**Deliverables**:
- `internal/graphql_translators.lua` — `graphql_translate_repo`, `graphql_translate_user`,
  `graphql_translate_org`, `graphql_translate_issue`, `graphql_translate_pr`,
  `graphql_translate_comment`, `graphql_translate_label`, `graphql_translate_release`,
  `graphql_translate_milestone`, `graphql_translate_ref`, `graphql_translate_commit`,
  `graphql_translate_reaction`
- `graphql_fetch`, `graphql_fetch_or_error`, `graphql_fetch_with_headers`
- `graphql_page_to_cursor`, `graphql_cursor_to_page`, `graphql_cursor_url`
- `graphql_make_connection` and six convenience wrappers
- `graphql_inline_connection`
- `encode_node_id`, `decode_node_id`
- `test/graphql-translators.lua`, `test/graphql-pagination.lua`, `test/graphql-node-id.lua`

**Done when**: all unit tests pass; `graphql_translate_repo` applied to a Gitea REST
response produces a table with correct `nameWithOwner`, `stargazerCount`, and a
base64-encoded `id`.

**Dependencies**: #GQL-01 (for translator field mapping reference)

---

#### #GQL-07: Implement error model, path tracking, and null propagation

**Design doc**: [09-errors.md](09-errors.md)

**Deliverables**:
- `respond_graphql(data, errors)` in `graphql_executor.lua`
- `graphql_error(ctx, message, field_node, code)`
- `graphql_validate_error(message, name_node)`
- `ctx.path` push/pop in `execute_selection_set` and `complete_value`
- `PROPAGATE` sentinel and non-null propagation in `complete_value`
- `test/graphql-errors.lua` — all 12 unit tests

**Done when**: `respond_graphql(nil, errors)` writes `{"data":null,"errors":[...]}` and
non-null propagation test passes.

**Dependencies**: #GQL-04

---

#### #GQL-08: Implement auth passthrough and rateLimit resolver

**Design doc**: [10-auth-ratelimit.md](10-auth-ratelimit.md)

**Deliverables**:
- `Query.rateLimit` resolver in `graphql_executor.lua`
- `estimate_query_cost(op, variables)` in `graphql_executor.lua`
- `ctx.rate_cost` populated before execution
- `test/graphql-auth-ratelimit.lua` — unit tests

**Done when**: `{ rateLimit { cost remaining resetAt } }` returns a well-formed response
with `remaining = 999999`.

**Dependencies**: #GQL-04, #GQL-07

---

#### #GQL-09: Implement cost-limit enforcement and batch/APQ rejection

**Design doc**: [12-batching-caching.md](12-batching-caching.md)

**Deliverables**:
- `GRAPHQL_MAX_COST` constant and enforcement in `graphql_handler`
- Array-body (batch) rejection in Phase 1
- APQ body detection and rejection
- `ctx.cache` field and `graphql_cached` helper
- `test/graphql-batching-caching.lua` — unit tests

**Done when**: a 100×100 nested query is rejected with `estimatedCost` in the error
extensions; a valid query under the ceiling executes normally.

**Dependencies**: #GQL-08

---

#### #GQL-10: Register Gitea GraphQL resolvers

**Design doc**: [05-translation.md §Minimum resolver coverage](05-translation.md),
[08-node-id.md §Node resolvers](08-node-id.md), [10-auth-ratelimit.md §viewer](10-auth-ratelimit.md)

**Deliverables** (all in `backends/gitea.lua`, in the `graphql_resolvers` block):

Root resolvers:
- `Query.viewer`, `Query.user`, `Query.organization`, `Query.repositoryOwner`
- `Query.repository`, `Query.search`
- `Query.rateLimit` (already in executor; gitea may override if needed)

Repository sub-resolvers:
- `Repository.issues`, `Repository.pullRequests`, `Repository.releases`
- `Repository.labels`, `Repository.milestones`, `Repository.refs`
- `Repository.defaultBranchRef`, `Repository.collaborators`
- `Repository.owner`, `Repository.languages`

Node resolvers:
- `node.Repository`, `node.User`, `node.Organization`
- `node.Issue`, `node.PullRequest`, `node.IssueComment`
- `node.Release`, `node.Label`

Issue/PR sub-resolvers:
- `Issue.comments`, `Issue.labels`, `Issue.assignees`, `Issue.author`, `Issue.milestone`
- `PullRequest.commits`, `PullRequest.reviews`, `PullRequest.labels`, `PullRequest.assignees`

**Done when**: `test/gitea-graphql.hurl` passes against the mock Gitea server;
`make test` is green.

**Dependencies**: #GQL-05, #GQL-06, #GQL-07, #GQL-08, #GQL-09

---

#### #GQL-11: Add GraphQL catalog group, CSV row, and site integration

**Design doc**: [04-executor.md §Catalog registration](04-executor.md),
[15-compat-site.md](15-compat-site.md)

**Deliverables**:
- `"graphql"` section in `internal/catalog.lua`
- `test/stub-graphql.hurl` — backend-agnostic HTTP assertions
- `POST /graphql` row in `site/compatibility.csv` (all backends initially `~`)
- `"graphql": "GraphQL"` in `GROUP_NAMES` in `scripts/gen-matrix.py`
- `graphql_request = true` in `CONFUSIO_NATIVE` in `scripts/validate-claims.lua`

**Done when**: `make validate-csv validate-claims validate-tests` all pass; `make site`
produces an HTML page with a GraphQL section.

**Dependencies**: #GQL-10 (need the handler to exist before the CSV row is valid)

---

#### #GQL-12: Add GraphQL unit test driver

**Design doc**: [13-testing.md §Unit tests](13-testing.md)

**Deliverables**:
- `test/unit-graphql.lua` — driver loading all `test/graphql-*.lua` files
- `test-unit-functions` target in `Makefile` invokes `unit-graphql.lua`

**Done when**: `make test-unit-functions` runs all GraphQL unit tests and exits 0.

**Dependencies**: all unit test files from #GQL-02 through #GQL-09

---

### Phase 1b — Additional backends

These issues are independent of each other and can be parallelised.

#### #GQL-13: GitLab GraphQL resolvers

**Deliverables**: `graphql_resolvers` block in `backends/gitlab.lua`; `test/gitlab-graphql.hurl`; CSV row for gitlab updated to `y`.

**Dependencies**: #GQL-10 (Gitea resolvers as reference implementation)

---

#### #GQL-14: GitBucket GraphQL resolvers

**Deliverables**: `graphql_resolvers` block in `backends/gitbucket.lua`; `test/gitbucket-graphql.hurl`; CSV row updated.

**Dependencies**: #GQL-10

---

#### #GQL-15: Bitbucket Cloud GraphQL resolvers

**Deliverables**: partial resolvers for repository, issues; `test/bitbucket-graphql.hurl`; CSV row `~`.

**Dependencies**: #GQL-10

---

#### #GQL-16: Partial resolvers for remaining backends

**Scope**: azuredevops, bitbucket_datacenter, sourcehut, pagure — minimum: `Query.repository`.

**Dependencies**: #GQL-10

---

### Phase 2 — Mutations

#### #GQL-17: Enable mutation execution in executor

**Design doc**: [11-mutations.md §Executor changes for Phase 2](11-mutations.md)

**Deliverables**:
- Remove Phase 1 mutation rejection guard from `graphql_handler`
- `get_client_mutation_id` helper
- `test/graphql-mutations.lua` updated: Phase 1 rejection test replaced by execution test

**Dependencies**: #GQL-10 (Phase 1 must be complete and stable)

---

#### #GQL-18: Repository mutations (create, update, delete)

**Design doc**: [11-mutations.md §Repository mutations](11-mutations.md)

**Deliverables**: `Mutation.createRepository`, `Mutation.updateRepository`,
`Mutation.deleteRepository` in `backends/gitea.lua`; hurl tests.

**Dependencies**: #GQL-17

---

#### #GQL-19: Issue mutations (create, update, close, reopen)

**Design doc**: [11-mutations.md §Issue mutations](11-mutations.md)

**Deliverables**: `Mutation.createIssue`, `Mutation.updateIssue`, `Mutation.closeIssue`,
`Mutation.reopenIssue`.

**Dependencies**: #GQL-17

---

#### #GQL-20: Pull request mutations

**Design doc**: [11-mutations.md §Pull request mutations](11-mutations.md)

**Deliverables**: `Mutation.createPullRequest`, `Mutation.updatePullRequest`,
`Mutation.closePullRequest`, `Mutation.reopenPullRequest`, `Mutation.mergePullRequest`.

**Dependencies**: #GQL-17

---

#### #GQL-21: Comment mutations

**Design doc**: [11-mutations.md §Comment mutations](11-mutations.md)

**Deliverables**: `Mutation.addComment`, `Mutation.updateIssueComment`,
`Mutation.deleteIssueComment`.

**Dependencies**: #GQL-17

---

#### #GQL-22: Label, star, and subscription mutations

**Design doc**: [11-mutations.md §Label mutations](11-mutations.md),
[11-mutations.md §Star mutations](11-mutations.md)

**Deliverables**: `Mutation.createLabel`, `Mutation.addLabelsToLabelable`,
`Mutation.addStar`, `Mutation.removeStar`, `Mutation.updateSubscription`.

**Dependencies**: #GQL-17

---

### Phase 2b — Batch and extras

#### #GQL-23: Batch request support

**Design doc**: [12-batching-caching.md §Phase 2 batch implementation](12-batching-caching.md)

**Deliverables**: `execute_single` refactor of `graphql_handler`; array-body detection
and iteration; batch unit tests.

**Dependencies**: #GQL-10

---

#### #GQL-24: Backward pagination (`last`/`before`)

**Design doc**: [07-pagination.md §Backward pagination](07-pagination.md)

**Deliverables**: reverse-order REST fetching strategy; remove Phase 1 error for
`last`/`before`; pagination unit tests updated.

**Dependencies**: #GQL-10

---

#### #GQL-25: Item-level cursors

**Design doc**: [07-pagination.md §Connection assembly helper](07-pagination.md)

**Deliverables**: per-item cursor encoding in `edges[i].cursor`; updated
`graphql_make_connection`.

**Dependencies**: #GQL-24

---

#### #GQL-26: Additional node resolvers (Milestone, Team, Commit, Ref)

**Design doc**: [08-node-id.md §Phase 1 type coverage](08-node-id.md)

**Deliverables**: `node.Milestone`, `node.Team`, `node.Commit`, `node.Ref` resolvers.

**Dependencies**: #GQL-10

---

## Dependency graph

```
#GQL-01 (schema vendor)
  ├─► #GQL-02 (parser)
  │     └─► #GQL-04 (executor)
  │           ├─► #GQL-05 (fragments/vars)
  │           ├─► #GQL-07 (errors)
  │           │     └─► #GQL-08 (auth/rateLimit)
  │           │           └─► #GQL-09 (cost/batch)
  │           └─► ─────────────────────────────────┐
  ├─► #GQL-03 (schema loader)                       │
  │     └─► #GQL-04                                 │
  └─► #GQL-06 (translators/pagination/node IDs)     │
                                                     ▼
                              #GQL-10 (Gitea resolvers) ◄─ all of above
                                    ├─► #GQL-11 (catalog/CSV/site)
                                    ├─► #GQL-12 (test driver)
                                    ├─► #GQL-13..16 (other backends, parallel)
                                    └─► #GQL-17 (enable mutations)
                                              ├─► #GQL-18..22 (mutation categories)
                                              └─► #GQL-23..26 (batch/pagination extras)
```

## Milestone mapping

| Milestone | Issues | Outcome |
|---|---|---|
| `graphql-phase-0` | #GQL-01 | SDL vendored; schema data generated |
| `graphql-phase-1` | #GQL-02 through #GQL-12 | `POST /graphql` ships for Gitea queries |
| `graphql-phase-1b` | #GQL-13 through #GQL-16 | Multi-backend GraphQL query support |
| `graphql-phase-2` | #GQL-17 through #GQL-22 | Mutation support ships for Gitea |
| `graphql-phase-2b` | #GQL-23 through #GQL-26 | Batch, backward pagination, extras |

## Phase 1 "done" definition

Phase 1 is complete when:

1. `make test` passes (unit tests, integration tests, format, lint, validate-csv,
   validate-claims, validate-tests).
2. `POST /graphql` accepts and executes these queries against a live Gitea instance:
   - `{ viewer { login } }`
   - `{ repository(owner: "o", name: "r") { nameWithOwner stargazerCount issues(first: 5) { totalCount nodes { title } } } }`
   - `{ __schema { queryType { name } } }` (introspection)
   - `{ rateLimit { cost remaining resetAt } }`
3. `test/stub-graphql.hurl` and `test/gitea-graphql.hurl` both pass against the mock.
4. The compatibility site shows a **GraphQL** section with correct per-backend values.
5. No regressions in existing REST endpoint tests.

## Phase 2 "done" definition

Phase 2 is complete when:

1. All Phase 1 criteria remain satisfied.
2. These mutations round-trip against a live Gitea instance:
   - `mutation { createIssue(input: {...}) { issue { number title } } }`
   - `mutation { addComment(input: {...}) { commentEdge { node { body } } } }`
   - `mutation { mergePullRequest(input: {...}) { pullRequest { merged } } }`
3. `clientMutationId` is echoed back correctly in all mutation payloads.
4. Phase 1 mutation rejection guard is removed from `graphql_handler`.

## What is explicitly deferred beyond Phase 2

These items are not in any phase milestone and require a separate design decision before
starting:

- **Subscriptions**: require chunked/streaming HTTP not supported by Redbean's uniprocess
  model.
- **APQ (Automatic Persisted Queries)**: require a persistent hash→query store.
- **`@defer` / `@stream`**: same streaming constraint as subscriptions.
- **Marketplace, sponsors, enterprise-admin types**: no REST analog in confusio's catalog.
- **Full `ProjectV2` support**: complex relational state; no clean REST mapping.
- **Field-level deprecation warnings via `X-GitHub-Deprecation` header**: low client
  demand; spec-optional.
