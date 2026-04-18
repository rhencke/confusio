# Target Architecture and Migration Invariants

## Why this document exists

Issues #203–#208 will refactor confusio's runtime from the current global/load-order model
to an explicit composition root with a proper backend registry and shared provider
capability modules.  Before any file is moved or any global is deleted, this document
records the target shape so every subsequent change can be judged against the same
destination.

## What the current architecture looks like

`.init.lua` runs a fixed sequence of `dofile` calls.  Each call mutates the global
environment:

- Core modules populate helpers (`respond_json`, `proxy_json`, `make_backend_transport`,
  `graphql_resolvers`, …).
- `backend_impl = {}` and `backend_allow_anonymous = true` are initialized as globals.
- The backend file (e.g. `backends/gitea.lua`) is `dofile`'d; it reads and mutates
  `config.base_url`, assigns handler functions into `backend_impl`, assigns resolver
  functions into `graphql_resolvers`, and may set `backend_allow_anonymous = false` after
  an HTTP probe.
- For family-alias backends, `load_family_backend(root)` `dofile`s the root backend file
  and then iterates over `backend_impl` to delete keys matching the alias's `strip`
  patterns.
- `dispatch.lua` defines `OnHttpRequest()` which reads `backend_allow_anonymous`,
  `backend_impl`, and the router globals on every request.

Ownership is implicit.  The backend file is the only place `backend_impl` is written, but
there is no enforcement.  Any module loaded in the right order can read or mutate any
global.  Family alias inheritance works by running the root backend's entire side-effecting
load and undoing some of it afterwards.

## Target runtime objects

### `app` — composition root

A single Lua table constructed by `.init.lua` before the first request arrives.  All
per-application state lives in `app`; no other globals are written after startup.

**Owns:**

| Field | Type | Description |
|-------|------|-------------|
| `config` | table | `{ backend, base_url }` — frozen after construction |
| `backend` | table | the backend runtime object (see below) |
| `allow_anonymous` | boolean | whether unauthenticated requests are accepted |
| `route_match` | function | bound router lookup |
| `path_known` | function | bound router path-existence check |

**Forbidden to mutate:** any field of `app` after `.init.lua` returns.  Request handlers
read `app`; they never write it.  `OnHttpRequest` receives `app` as a parameter (or via
an upvalue in the closure returned by a dispatch factory) — it does not reach for a global.

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

The target startup sequence is explicit and linear.  No module has silent startup-time
side effects on globals.

```
1.  Parse SCRIPTARGS → build config table (local)
2.  Load core helpers (http, proxy, transport, translators, graphql_* modules)
      — these export only functions; they do not mutate any app-level state
3.  Load provider_families (families.lua)
      — read-only metadata table; not app state
4.  Call backend_builder(config) → backend
      — pure function: returns backend object, writes no globals
5.  Assemble app = { config, backend, allow_anonymous, … }
6.  Load defaults.lua, router.lua, catalog.lua (register routes)
      — these use app.backend.rest to resolve handler names
7.  Bind OnHttpRequest as a closure over app
```

Steps 1–5 happen once at process start.  Steps 6–7 complete the wiring.  After step 7 the
global environment is frozen for the lifetime of the process; `OnHttpRequest` reads only
the `app` closure and the router globals.

## Family alias inheritance

Today `load_family_backend` works by running the root backend file and then mutating the
resulting `backend_impl` to delete unsupported keys.  The target replaces this with a
composing builder.

**Target model:**

1. Each root backend exposes a `build(config, overrides) → backend` builder function.
2. An alias backend calls `build_family_alias(root_name, config, strip_patterns)`:
   - Calls `root_builder(config)` to get the root backend table.
   - Copies it to a new table (shallow clone of `rest`, `graphql`, `capabilities`).
   - Iterates the alias's `strip` patterns and deletes matching keys from the copy.
   - Sets `config.base_url` from the alias's `default_url` when none was supplied.
   - Returns the modified copy.
3. No global is mutated.  No root backend file is `dofile`'d as a side effect.

`provider_families` in `internal/families.lua` remains the single authoritative source of
alias metadata.  Only the loading mechanism changes.

## Migration invariants

These rules apply to every commit in #203–#208.  Any change that violates them is out of
scope for the refactor and must be handled separately.

1. **No externally visible behavior changes.**  Request/response semantics, status codes,
   header names, and JSON field names must be identical before and after each commit.  The
   full test suite (`make -j test`) must pass at every commit.

2. **No flag day.**  The repository must remain buildable and shippable throughout the
   migration.  The old global path and the new explicit path may coexist during the
   transition; backends that have not yet migrated continue to use the legacy wiring.

3. **Migration order: Gitea → GitLab → remaining backends.**  Gitea is first because it
   is the most complete backend and has the best test coverage.  GitLab is second because
   it is the second largest.  Family aliases (forgejo, codeberg, gogs, notabug) migrate
   with their root (Gitea).  Remaining standalone backends migrate together in #208.

4. **REST and GraphQL converge on the same capability layer.**  By the end of #208 there
   must be no logic that is duplicated between a REST handler and a GraphQL resolver for
   the same provider.  Each piece of provider-domain knowledge lives in one capability
   function; the REST and GraphQL layers are thin adapters over it.

5. **Legacy global wiring is deleted, not deprecated.**  Once all backends have migrated
   to the new builder pattern, the globals `backend_impl`, `graphql_resolvers`, and
   `backend_allow_anonymous` are deleted from `.init.lua` and any module that references
   them.  There is no long-term compatibility shim.

## Legacy seams to delete

These four seams are the concrete targets.  Every step in #203–#208 moves the codebase
closer to eliminating them.  They must all be gone by the end of #208.

| Seam | Where it lives today | Replaced by |
|------|---------------------|-------------|
| global `backend_impl` | `.init.lua` + every backend file | `app.backend.rest` |
| global `graphql_resolvers` | `internal/graphql_executor.lua` + every backend file | `app.backend.graphql` |
| global `backend_allow_anonymous` | `.init.lua` + gitea/gitea-family backends | `app.allow_anonymous` (set from `backend.allow_anonymous` during composition) |
| startup by hidden load order | `.init.lua` `dofile` sequence | explicit `backend_builder(config)` call in `.init.lua` step 4 |

The four seams are listed here in dependency order.  Eliminating `backend_impl` and
`graphql_resolvers` is the core of #203–#207.  `backend_allow_anonymous` and the load-order
seam are cleaned up as part of the Gitea migration (#205) and the composition root
introduction (#203) respectively.

## Relationship to the GraphQL design

The GraphQL design documents in `docs/graphql/` describe how the executor, parser, and
schema work.  This document does not supersede those decisions; it adds the ownership
model that was implicit there.

Specifically: `graphql_resolvers` is the global table that `docs/graphql/04-executor.md`
treats as a given.  In the target architecture it becomes `app.backend.graphql`, a field of
the backend object.  The executor receives it via `app` rather than reading a global.
Everything else in the GraphQL design (resolver dispatch, selection walking, cursor
pagination, node IDs, mutation execution) remains unchanged.
