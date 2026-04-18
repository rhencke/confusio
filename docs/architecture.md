# Confusio Target Architecture

This document defines the target runtime model for confusio and the invariants
that must hold throughout the migration from the current global/load-order design
to the explicit app context, backend builder/registry, and shared provider
capability layer described here.

Later issues (#203–#209) implement the migration step by step.  Read this document
first so each step can be judged against the intended destination.

---

## Why the current architecture needs to change

The current runtime depends on load order and mutable globals:

- `.init.lua` constructs `config`, `backend_impl`, and `backend_allow_anonymous` as
  bare globals and then `dofile`s modules in a fixed sequence
- `internal/dispatch.lua` reads those globals directly on every request
- `internal/graphql_executor.lua` declares a bare global `graphql_resolvers` table
  that backends mutate at load time
- `internal/families.lua` implements alias inheritance by `dofile`ing a root backend
  and then destructively stripping keys from the global `backend_impl` table after
  the fact

This makes ownership implicit, makes it easy to mis-wire a new backend, and forces
REST and GraphQL to duplicate the same provider-domain logic (fetching, translating,
paginating) rather than sharing it.

---

## Target runtime objects

The target architecture has four named, owned objects.  Each has a defined scope and
a set of things it is **not allowed** to mutate directly.

### 1. App context (`app`)

The composition root.  Built once at startup by `.init.lua` and passed or closed over
by everything that needs runtime state.  It holds:

| Field | Type | Description |
|-------|------|-------------|
| `config` | table | Parsed SCRIPTARGS: `backend`, `base_url` |
| `backend` | backend runtime (see §2) | The active backend, or nil for no-backend mode |
| `router` | router object | Populated from the endpoint catalog at startup |
| `allow_anonymous` | boolean | Whether unauthenticated requests are permitted |

The app context **may not** be mutated after startup completes.  It is frozen once
`OnHttpRequest` is installed.

The app context does **not** own raw handler tables directly.  It delegates handler
lookup to the backend runtime.

### 2. Backend runtime

Produced by a backend's registration call (see §3 — Backend builder/registry).
Owned by the app context.  It holds:

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Backend identifier (e.g. `"gitea"`, `"gitlab"`) |
| `handlers` | table | REST endpoint name → handler function |
| `resolvers` | table | GraphQL `"TypeName.fieldName"` → resolver function |
| `allow_anonymous` | boolean | Whether this backend allows unauthenticated requests |
| `capabilities` | table | Shared provider capabilities (see §4) |

Backend runtimes are built by the builder and **frozen** before being installed into
the app context.  A backend file may not mutate `handlers` or `resolvers` after
`build()` returns.

Handler lookup at request time: `backend.handlers[endpoint_name] or default_fn`.

### 3. REST handler registry

A logical view over `backend.handlers`.  Not a separate object — conceptually the
REST surface of the backend runtime.  The catalog still owns the canonical endpoint
list (`endpoint_sections` in `internal/catalog.lua`); the backend runtime provides
the overrides.

Default handlers continue to live in `internal/defaults.lua` and are looked up the
same way as today: `backend.handlers[ep] or default_fn`.

### 4. GraphQL resolver registry

`backend.resolvers` — a table keyed by `"TypeName.fieldName"` strings (e.g.
`"Query.repository"`, `"Repository.issues"`).  Populated by the backend builder
alongside the REST handlers.

The executor reads `backend.resolvers` through the app context instead of the
bare global `graphql_resolvers`.  Backends do **not** write directly to a global
resolver table.

### 5. Provider capability modules

Shared, provider-specific domain logic that both REST handlers and GraphQL resolvers
call into.  Each capability module exposes functions in terms of provider-domain
operations (fetch a repo, list issues, paginate results) rather than HTTP-surface
operations.

A backend's REST handlers and GraphQL resolvers become thin adapters that:
1. Extract relevant inputs (path captures, query params, or GraphQL args)
2. Call the shared capability function
3. Shape the result for the specific response surface (REST JSON vs. GraphQL node)

Capability modules live in `backends/<name>/` subdirectories, e.g.:
- `backends/gitea/capabilities.lua` — repo, user, issue, PR operations
- `backends/gitea/translators.lua` — response translation helpers

The capability layer is the **only** place provider-specific fetch logic lives.
REST handlers and GraphQL resolvers must not independently re-implement the same
provider call.

---

## Startup flow

The target startup sequence is explicit and owned.  `.init.lua` becomes a composition
root, not a load-order script.

```
1. Parse SCRIPTARGS → config table
2. Load internal framework modules (http, proxy, transport, translators,
   graphql_parser, graphql_schema_data, graphql_schema, graphql_executor,
   graphql_translators, families, router, catalog)
   — these export helpers but do NOT install global runtime state
3. Load backend (if config.backend != ""):
   a. Call backend builder: returns a backend runtime object
   b. Set app.allow_anonymous from backend.allow_anonymous
4. Build app context from config + backend runtime + router + catalog
5. Install OnHttpRequest (dispatch) as a closure over the app context
6. Startup complete — app context is frozen
```

The key difference from today: steps 3–5 are explicit function calls whose
return values are passed forward.  No module installs state into shared globals
as a side effect of being `dofile`d.

---

## Family alias inheritance

Today, family aliases work by loading a root backend (which mutates `backend_impl`)
and then stripping keys from `backend_impl` after the fact.  This is fragile because
it depends on post-hoc mutation of shared global state.

In the target model, alias inheritance is declarative:

1. `provider_families` in `internal/families.lua` remains the authoritative declaration.
2. The **builder** (not `load_family_backend`) handles inheritance:
   - Clone the root backend's `handlers` and `resolvers` tables
   - Delete keys matching each `strip` pattern from the clones
   - Return a new backend runtime built from the clones
3. The alias backend file calls `build_alias_backend(root)` instead of
   `load_family_backend(root)`.  No `dofile(root)` at alias time; the root backend
   was already built and its tables are available through the builder registry.
4. `load_family_backend` is deleted once all aliases use the new path.

This eliminates the global mutation window and makes alias inheritance testable
without running the full startup sequence.

---

## Migration invariants

These invariants must hold at every commit throughout the migration:

1. **No public behavior changes as a side effect of the refactor.**  The HTTP
   responses that backends produce must be identical before and after any migration
   step.  If a change is *intended* to alter behavior, that must be explicit in the
   commit message and covered by a test.

2. **No giant flag day.**  Each issue (#203–#208) must leave the repo in a
   shippable state.  Partial migrations are acceptable if they pass all tests.
   A compatibility shim may be left in place *temporarily* to allow incremental
   landing, but must be marked `-- TODO(#NNN): remove after full migration` and
   removed by a later issue in the series.

3. **Migration order: Gitea → GitLab → aliases and smaller backends.**  Gitea is
   the family root for five providers and the largest backend; it is the right
   architectural proof point.  GitLab is the second largest and proves the design
   generalizes.  Aliases and smaller backends follow once the seams are proven.

4. **REST and GraphQL converge on the same capability layer.**  By the end of #208,
   every backend's REST handlers and GraphQL resolvers call into shared capability
   modules rather than each maintaining independent fetch/translate paths.

5. **The catalog (`internal/catalog.lua`) remains the single source of truth for
   routes and default handlers.**  The backend builder is additive — it supplies
   overrides — and must not duplicate the catalog's route definitions.

---

## Legacy seams to delete

These four global coordination points are the primary targets of the migration.
Each has a defined issue where it is removed:

| Global | Removed in | Replacement |
|--------|-----------|-------------|
| `backend_impl` | #208 | `app.backend.handlers` |
| `graphql_resolvers` | #208 | `app.backend.resolvers` |
| `backend_allow_anonymous` | #203 | `app.allow_anonymous` |
| Startup-by-load-order (dofile side effects) | #203 | explicit composition in `.init.lua` |

A temporary compatibility shim **may** exist during the migration window (issues
#203–#207) to keep the old path working while backends are incrementally updated.
The shim must be removed in #208 before the branch is marked ready for review.

---

## New authoritative seams

After the migration, the four authoritative seams from issue #111–#117 expand to six:

| Concern | Authoritative source |
|---------|---------------------|
| Routes and default handlers | `endpoint_sections` in `internal/catalog.lua` |
| Provider family membership | `provider_families` in `internal/families.lua` |
| Backend transport scaffold | `make_backend_transport` in `internal/transport.lua` |
| Application module layout | nine `internal/*.lua` files + new `internal/app.lua` |
| Backend builder/registry | `internal/backend_builder.lua` (new in #204) |
| Provider capability interface | `backends/<name>/capabilities.lua` (new in #205) |

---

## File layout after migration

```
internal/
  app.lua             — app context builder and startup composition (new)
  backend_builder.lua — backend builder/registry abstraction (new)
  http.lua            — unchanged
  proxy.lua           — unchanged
  transport.lua       — unchanged
  translators.lua     — unchanged
  families.lua        — provider_families table only; load_family_backend deleted
  defaults.lua        — unchanged
  router.lua          — unchanged
  catalog.lua         — unchanged
  dispatch.lua        — reads app context instead of globals
  graphql_*.lua       — executor reads app.backend.resolvers instead of global

backends/
  gitea.lua           — thin registration shim: calls backend_builder
  gitea/
    capabilities.lua  — shared provider logic (repo, user, issue, PR)
    translators.lua   — response translators
    rest.lua          — REST handler adapter table
    graphql.lua       — GraphQL resolver adapter table
  gitlab.lua          — same structure
  gitlab/
    capabilities.lua
    translators.lua
    rest.lua
    graphql.lua
  <other backends>/   — builder registration + optional capabilities/
  forgejo.lua         — alias: calls build_alias_backend("gitea")
  codeberg.lua        — alias: calls build_alias_backend("gitea")
  gogs.lua            — alias: calls build_alias_backend("gitea")
  notabug.lua         — alias: calls build_alias_backend("gitea")
```

Smaller backends that do not have significant provider logic may keep a single flat
`backends/<name>.lua` file that registers directly through the builder without a
subdirectory.

---

## Reading this alongside the issue series

| Issue | What it implements from this document |
|-------|--------------------------------------|
| #203 | App context object, explicit startup flow, removes `backend_allow_anonymous` |
| #204 | Backend builder/registry, stops `backend_impl` mutation |
| #205 | Provider capability interface and base module structure |
| #206 | Gitea migrated to capabilities + thin REST/GraphQL adapters |
| #207 | GitLab migrated to capabilities + thin adapters |
| #208 | Aliases + remaining backends migrated; legacy globals deleted |
| #209 | Guardrails, tests, CLAUDE.md updated to teach the new seams |
