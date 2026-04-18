# Architecture: App Context and Backend Composition

## Status

This document was written before issues #203–#208 (merged as #211–#218) as a migration
guide.  Issues #202–#209 are now closed; PR #221 completed the remaining gaps
(`app.backend` nesting, `make_dispatcher` closure, `graphql_register_builtin_resolvers`
explicit composition).  The migration is **complete**.  The "pre-migration state" section
below is preserved for historical context.

## Pre-migration state (historical)

Before #203, `.init.lua` ran a fixed sequence of `dofile` calls.  Each call mutated the
global environment:

- Core modules populated helpers (`respond_json`, `proxy_json`, `make_backend_transport`,
  `graphql_resolvers`, …).
- `backend_impl = {}` and `backend_allow_anonymous = true` were initialized as globals.
- The backend file (e.g. `backends/gitea.lua`) was `dofile`'d; it read and mutated
  `config.base_url`, assigned handler functions into `backend_impl`, assigned resolver
  functions into `graphql_resolvers`, and may have set `backend_allow_anonymous = false`
  after an HTTP probe.
- For family-alias backends, `load_family_backend(root)` `dofile`'d the root backend file
  and then iterated over `backend_impl` to delete keys matching the alias's `strip`
  patterns.
- `dispatch.lua` defined `OnHttpRequest()` which read `backend_allow_anonymous`,
  `backend_impl`, and the router globals on every request.

Ownership was implicit.  Any module loaded in the right order could read or mutate any
global.  Family alias inheritance worked by running the root backend's entire side-effecting
load and undoing some of it afterwards.

## Current runtime objects

### `app` — composition root

A single Lua table constructed by `.init.lua` before the first request arrives.  All
per-application state lives in `app`; no other globals are written after startup.

**Owns:**

| Field | Type | Description |
|-------|------|-------------|
| `config` | table | `{ backend, base_url }` — frozen after construction |
| `backend` | table | the backend runtime object (see below) |
| `allow_anonymous` | boolean | whether unauthenticated requests are accepted |
| `route_match` | function | bound router lookup — set by `.init.lua` after loading `router.lua` |
| `path_known` | function | bound router path-existence check — set by `.init.lua` after loading `router.lua` |

**Forbidden to mutate:** any field of `app` after `.init.lua` returns.  Request handlers
read `app`; they never write it.  `OnHttpRequest` is the closure returned by
`make_dispatcher(app)` — it holds `app` as an upvalue and does not reach for a global.

### `backend` — backend runtime object

A table returned by the backend builder.  It is the only place per-provider state lives.

**Owns:**

| Field | Type | Description |
|-------|------|-------------|
| `rest` | table | REST handler registry (see below) |
| `graphql` | table | GraphQL resolver registry (see below) |
| `allow_anonymous` | boolean | false when the provider requires sign-in |
| `capabilities` | table | provider capability modules (see below) |

**Forbidden to mutate:** any field after the builder returns.  Builders are pure: given a
config, they return the same backend object every time.

### `rest` — REST handler registry

A plain Lua table mapping handler name (string, e.g. `"get_repo"`) to a handler function.
The catalog looks up a handler by name for every routed request.

**Owns:** nothing except the function references.  Functions are closures that hold the
transport and capability references they need.

**Forbidden to mutate:** at request time.  The registry is written once by the backend
builder; dispatch only reads it.

### `graphql` — GraphQL resolver registry

A plain Lua table mapping resolver key (string, `"TypeName.fieldName"`) to a resolver
function.  The GraphQL executor dispatches field resolution through this table.

**Owns:** nothing except the function references.  Resolvers are closures over the same
capability references that REST handlers use.

**Forbidden to mutate:** at request time.  The registry is written once by the backend
builder; the executor only reads it.

### `capabilities` — provider capability modules

A table of functions that perform provider-native REST calls and return typed Lua tables
(not HTTP responses).  Both REST handlers and GraphQL resolvers call the same capability
functions to perform their underlying work.

Example: a `repos` capability module might expose
`repos.get(owner, repo) → { id, name, description, … }`.  The REST handler for
`GET /repos/{owner}/{repo}` calls `repos.get`, translates the result to the GitHub shape,
and writes the response.  The GraphQL resolver for `Query.repository` calls the same
`repos.get`, then plucks the fields the query requested.

**What capabilities must not do:** write HTTP responses (`respond_json`, `Write`,
`SetHeader`, `SetStatus`).  They return data or raise errors; response formatting belongs
to the REST or GraphQL adapter layer above them.

**What capabilities may do:** call `Fetch` (via the transport closure they hold), call
other capabilities, and return `nil, error_string` on failure.

## Startup flow

The startup sequence is explicit and linear.  No module has silent startup-time
side effects on globals.

```
1.  Parse SCRIPTARGS → build config table (local)
2.  Load core helpers (http, proxy, transport, translators, graphql_* modules)
      — these export only functions; they do not mutate any app-level state
3.  Load provider_families (families.lua)
      — read-only metadata table; not app state
4.  Construct app = make_app(config)
      — creates { config, backend={rest={},graphql={},capabilities={}}, allow_anonymous=true }
5.  Wire graphql_resolvers alias: app.backend.graphql = graphql_resolvers
6.  Call graphql_register_builtin_resolvers()
      — registers Query.node, Query.nodes, Query.rateLimit into graphql_resolvers
7.  Load backend file (e.g. backends/gitea.lua) via make_backend_builder():b:build()
      — populates app.backend.rest, graphql_resolvers, app.backend.capabilities
      — Gitea probes the upstream and may set app.allow_anonymous = false
8.  Load defaults.lua, router.lua, catalog.lua (register routes)
9.  Load dispatch.lua (exports make_dispatcher)
10. Bind router lookups and install closure:
      app.route_match = route_match
      app.path_known = path_known
      OnHttpRequest = make_dispatcher(app)
```

Steps 1–9 happen once at process start.  Step 10 completes the wiring.  After step 10 the
global environment is frozen for the lifetime of the process; `OnHttpRequest` reads only
the `app` upvalue — no ambient globals.

## Family alias inheritance

Alias backends (e.g. `codeberg`, `forgejo`, `notabug`) share an implementation with their
root backend (e.g. `gitea`) through the following pattern:

1. `provider_families` in `internal/families.lua` declares the alias and its `strip`
   patterns and `default_url`.  This is the single authoritative source of alias metadata.
2. `backends/<alias>.lua` sets `config.base_url` from `provider_families` (when not
   supplied by the user) and then `dofile`s the root backend file.
3. The root backend calls `make_backend_builder()`, registers handlers, and calls
   `b:build(strip)` where `strip` comes from `provider_families[config.backend]`.  Keys
   matching any strip pattern are omitted from `app.backend.rest` — feature gaps are
   applied declaratively at build time rather than by post-hoc mutation.
4. No global is mutated after `b:build()` returns.

## Migration invariants (completed)

These rules governed every commit in #203–#209.

1. **No externally visible behavior changes.**  Request/response semantics, status codes,
   header names, and JSON field names were identical before and after each commit.

2. **No flag day.**  The repository remained buildable and shippable throughout the
   migration.

3. **Migration order: Gitea → GitLab → remaining backends** (#205 → #206 → #207–#208).

4. **REST and GraphQL converge on the same capability layer.**  Each piece of
   provider-domain knowledge lives in one capability function; REST and GraphQL layers
   are thin adapters over it.

5. **Legacy global wiring is deleted, not deprecated.**  `backend_impl`,
   `backend_allow_anonymous`, and `load_family_backend` are gone.  `graphql_resolvers`
   is retained as an alias for `app.backend.graphql` (same table) to avoid breaking
   the executor's existing reads.

## Legacy seams — all eliminated

| Seam | Replaced by | Closed by |
|------|-------------|-----------|
| global `backend_impl` | `app.backend.rest` | #211–#218 |
| global `backend_allow_anonymous` | `app.allow_anonymous` | #212 |
| startup by hidden load order | explicit `make_app` + `make_dispatcher(app)` | #212, #221 |
| built-in resolver assignment at module load | `graphql_register_builtin_resolvers()` | #221 |

## Relationship to the GraphQL design

The GraphQL design documents in `docs/graphql/` describe how the executor, parser, and
schema work.  This document does not supersede those decisions; it adds the ownership
model that was implicit there.

Specifically: `graphql_resolvers` is the global table that `docs/graphql/04-executor.md`
treats as a given.  In the target architecture it becomes `app.backend.graphql`, a field of
the backend object.  The executor receives it via `app` rather than reading a global.
Everything else in the GraphQL design (resolver dispatch, selection walking, cursor
pagination, node IDs, mutation execution) remains unchanged.
