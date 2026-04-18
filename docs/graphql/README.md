# GraphQL Support Design

This directory contains the design for adding GitHub GraphQL API support to confusio.
Each document below covers one concern.  Together they form a complete plan from zero
to a working, incrementally-deployable GraphQL endpoint.

## Why GraphQL matters

GitHub clients increasingly use `POST /graphql` instead of the REST endpoints confusio
already translates.  Tools like the GitHub CLI, GitHub Actions runners, many third-party
integrations, and most modern GitHub SDKs send GraphQL by default.  Without GraphQL
support confusio is invisible to them.

Adding GraphQL is the largest single capability gap between confusio and a drop-in
GitHub API replacement.

## Approach

GraphQL requests arrive at `POST /graphql`.  Confusio parses the query document,
validates it against a bundled subset of GitHub's published SDL schema, walks the
selection set, dispatches each resolver to the appropriate backend REST call, and
assembles the standard `{"data": {...}, "errors": [...]}` envelope.

No new runtime dependencies are introduced.  The parser, executor, and schema registry
are all Lua modules loaded alongside the existing `internal/` stack.  Authentication,
transport, and error handling reuse the same primitives the REST layer already provides.

## Design documents

| Document | What it covers |
|----------|---------------|
| [01-api-surface.md](01-api-surface.md) | GitHub GraphQL API surface, scale, and scope assumptions |
| [02-lexer-parser.md](02-lexer-parser.md) | GraphQL lexer and parser for Lua on Redbean |
| [03-schema.md](03-schema.md) | Schema loading, SDL storage, and type validation strategy |
| [04-executor.md](04-executor.md) | Query executor, resolver dispatch, and selection walking |
| [05-translation.md](05-translation.md) | GraphQL-to-REST translation and resolver binding model |
| [06-fragments-vars-directives.md](06-fragments-vars-directives.md) | Fragment, variable, directive, and introspection handling |
| [07-pagination.md](07-pagination.md) | Relay cursor pagination mapping to REST page params |
| [08-node-id.md](08-node-id.md) | Node/ID global identifier scheme and `node()` resolution |
| [09-errors.md](09-errors.md) | Error model, partial results, and GraphQL error envelope |
| [10-auth-ratelimit.md](10-auth-ratelimit.md) | Authentication passthrough and rate limit accounting |
| [11-mutations.md](11-mutations.md) | Mutation handling and write-side translation |
| [12-batching-caching.md](12-batching-caching.md) | Request batching, caching, and cost-limit enforcement |
| [13-testing.md](13-testing.md) | Testing strategy with GraphQL hurl fixtures and mocks |
| [14-backend-feasibility.md](14-backend-feasibility.md) | Per-backend GraphQL feasibility matrix and fallback policy |
| [15-compat-site.md](15-compat-site.md) | Compatibility site integration for GraphQL coverage reporting |
| [16-roadmap.md](16-roadmap.md) | Incremental rollout roadmap and issue decomposition plan |

## Reading order

If you are reading this for the first time, start with **01** (scope), then **02–04**
(the core engine), then **05–08** (translation concerns), then **09–12** (cross-cutting
concerns), and finish with **13–16** (validation and delivery plan).

## Status

Implementation is complete.  All phases of the [rollout roadmap](16-roadmap.md) have shipped:
Phase 0 (schema), Phase 1 (query engine + Gitea resolvers), Phase 1b (additional backends),
Phase 2 (mutations), and Phase 2b (batch requests, backward pagination, item-level cursors,
additional node resolvers).  These documents serve as reference for the design decisions made.
