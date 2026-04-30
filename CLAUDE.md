# confusio — Claude instructions

## What this is

A Redbean/Lua HTTP proxy that translates GitHub API calls to other git hosting providers (Gitea, GitLab, Bitbucket, Forgejo, Sourcehut). The GitHub API is the interface; provider-native APIs are the backends.

Built with [Redbean](https://redbean.dev): a self-contained web server + Lua interpreter distributed as a self-extracting zip. The entry point is `.init.lua` (boot/composition only); all application logic lives in `internal/` modules and `backends/` files, all zipped into the single `confusio.com` binary.

## Build and test

| Command | What it does |
|---------|-------------|
| `make -j build` | Produces `confusio.com` (app) |
| `make -j test-unit` | Unit tests against mock backends, no network |
| `make -j test-integration` | Integration tests against live gitea.com |
| `make -j test` | Unit tests, integration tests, format check, and lint — all checks |
| `make -j test-format` | Check StyLua formatting only (no changes — fails if any file needs reformatting) |
| `make -j test-lint` | Run luacheck linting only |
| `make -j validate-mock` | Run `test/validate/gitea-api-version.hurl` against both the mock and a real Gitea instance to check they agree |
| `make -j validate-csv` | Check every `site/compatibility.csv` row exists in the catalog |
| `make -j validate-tests` | Check every catalog group has test coverage per backend |
| `make -j dump-endpoints` | Print catalog as JSON to stdout |
| `make -j site` | Build GitHub Pages site into `_site/` (catalog + CSV → matrix HTML) |

**Before any commit and before any push: run `make -j test`.** This runs unit tests, integration tests, format check, and lint in one shot. CI enforces all of these — fix any failures before pushing.

**Checking test results:** Use the exit code, not stdout parsing. The output is noisy (redbean logs prefixed with `I2026-`). The correct pattern:
```bash
make -j test; echo "EXIT: $?"
```
Only spelunk the output if the exit code is non-zero.

## Project structure

```
.init.lua                    — Redbean entry point: config, SCRIPTARGS, module load order, backend wiring
internal/
  http.lua                   — HTTP response primitives: set_preamble, respond_json
  proxy.lua                  — upstream proxy helpers: proxy_json family, translate_list, proxy_search_envelope
  transport.lua              — auth/fetch scaffolding: make_fetch_opts, make_proxy_handler, make_backend_transport, append_page_params
  capabilities.lua           — capability module helpers: cap_fetch, cap_fetch_paged, cap_err; REST adapters: cap_rest_respond, cap_rest_created, cap_rest_204, cap_rest_paged
  translators.lua            — shared Gitea-family translators: translate_repo, translate_user, translate_migration, owner_repo_id
  families.lua               — provider_families table
  defaults.lua               — default stub handlers collected in the global `defaults` table
  router.lua                 — segment-based radix trie: route_add, route_match, path_known
  catalog.lua                — endpoint_sections table; populates global `endpoints` and registers routes at load time
  dispatch.lua               — make_dispatcher(app): factory returning the OnHttpRequest closure; auth gate, route_match, handler dispatch
backends/                    — per-provider implementations; each uses make_backend_builder() and b:build() to register handlers
docs/
  graphql/                   — GraphQL support design docs (README.md + 01–16 numbered documents)
  real-world-testing.md      — plan for weekly live-backend integration tests
Makefile                     — build, test, and download targets
.redbean-version             — pinned Redbean version (wget'd by make)
.hurl-version                — pinned Hurl version (curl'd by make)
site/
  index.html                 — GitHub Pages template (contains <!-- COMPAT_MATRIX --> placeholder)
  compatibility.csv          — support values only: one row per endpoint (keyed by "METHOD /path"), one column per provider; section structure comes from the catalog
scripts/
  dump-endpoints.lua         — exports endpoint catalog as JSON (run via redbean.com -i)
  gen-matrix.py              — generates HTML table from catalog JSON + compatibility.csv
  validate-csv.py            — checks every CSV row exists in the catalog
  validate-tests.py          — checks every catalog group has test coverage per backend
_site/                       — generated output (gitignored; produced by `make site` or the Pages workflow)
test/
  test-unit.sh               — unit test harness (starts confusio + mock, runs hurl)
  test-integration.sh        — integration test harness (live gitea.com)
  test-mock-validate.sh      — validate mock response structure vs real instance
  root.hurl                  — hurl assertions for GET / (no backend)
  gitea-root.hurl            — hurl assertions for GET / (gitea backend)
  validate/
    gitea-api-version.hurl   — hurl assertions for /api/v1/version (used by validate-mock only)
  mock-gitea.lua             — Redbean handler for the mock Gitea server
.github/
  workflows/ci.yml           — CI: parallel test-unit and test-integration jobs
  workflows/pages.yml        — GitHub Pages build: generates matrix from CSV, deploys _site/
  actions/setup/action.yml   — composite action: cache redbean.com and hurl
vendor/
  github-rest-api-description/
    api.github.com.yaml      — GitHub's REST API OpenAPI spec (MIT, vendored for reference)
    LICENSE.md               — upstream MIT license
    README.md                — update instructions
```

## Running confusio

```bash
# No backend (returns {} for GET /)
sh ./confusio.com -p 8080

# Gitea backend via CLI args (positional: backend [base_url])
sh ./confusio.com -p 8080 -- gitea
sh ./confusio.com -p 8080 -- gitea https://gitea.com
```

## Configuration system

Config is supplied as SCRIPTARGS after `--`.  Positional args set the backend and base URL; key=value args configure webhook options.

| Mechanism | Syntax |
|-----------|--------|
| SCRIPTARGS (positional) | `sh ./confusio.com -- <backend> [base_url]` |
| SCRIPTARGS (inbound secret file) | `webhook_secret_file_BACKEND=/path` — path to 0600 file containing inbound signing secret |
| SCRIPTARGS (outbound target) | `webhook_target=URL` — outbound delivery target URL |
| SCRIPTARGS (target name) | `webhook_target_name=NAME` — logical outbound target name in delivery log lines (default: `default`) |
| SCRIPTARGS (target events) | `webhook_target_events=push,pull_request` — comma-separated filter (default: *) |
| SCRIPTARGS (target shape) | `webhook_target_shape=confusio` — `github` (default) or `confusio` |
| SCRIPTARGS (target secret file) | `webhook_target_secret_file=/path` — path to 0600 file containing outbound HMAC signing secret |
| Defaults | hardcoded in `.init.lua` |

## GitHub API reference

The vendored spec at `vendor/github-rest-api-description/api.github.com.yaml` is the source of truth for what endpoints confusio should expose and what their request/response shapes are.

When implementing a new endpoint, check the spec for:
- Path and method
- Required/optional query params and request body fields
- Response status codes and body schema

## Adding a new endpoint

1. Check `vendor/github-rest-api-description/api.github.com.yaml` for the endpoint's contract.
2. Add the endpoint to the appropriate `endpoint_sections` entry in `internal/catalog.lua`. Each entry is
   `{ "VERB /path", "handler_name" }` or `{ "VERB /path", "handler_name", defaults.fn }`.
   Endpoints are grouped into named sections (e.g. `"repos"`, `"issues"`) that drive the
   compatibility matrix sections and test file naming.
3. Add a default handler to `internal/defaults.lua`: define it as a local function and add it
   to the `defaults` table at the bottom of that file.
4. If any backend behaves differently, add an override in `backends/<name>.lua`.
   Parametric captures are passed positionally: `repo = function(owner, repo) ... end`
5. Add a hurl assertion file in `test/` named `test/stub-<group>.hurl` (if the default behavior
   is the same for all backends) or `test/<backend>-<group>.hurl` (for backend-specific
   behavior). The `BACKEND_RULE` in the Makefile automatically includes stub files as fallback
   for any backend without its own group file.
6. Update `site/compatibility.csv`: add a row for the new endpoint. Values: `y` = native
   support, `~` = partial/stub, `~explanation` = partial with tooltip explanation,
   `n` = returns 404/501. The endpoint column must match exactly what the catalog emits
   (`make dump-endpoints`). Run `make validate-csv` to check. The GitHub Pages site is
   regenerated automatically from the catalog + CSV in CI — never edit the generated HTML.

## Adding a new backend

### Standalone backend (new API family)

1. Create `backends/<name>.lua`. Use `make_backend_builder()` to register only the handlers that
   differ from the defaults, then call `b:build()` to commit them. The file is loaded automatically
   when `config.backend == "<name>"` — no changes to `.init.lua` needed.
   ```lua
   local b = make_backend_builder()
   local _t = make_backend_transport("token", { per_page = "limit", page = "page" })
   local fetch_json = _t.fetch_json

   b:rest("get_repo", function(owner, repo) ... end)
   b:graphql("Query.viewer", function(_parent, _args, ctx) ... end)
   b:capability("repos", { get = function(...) ... end })
   b:build()
   ```
   `make validate-builders` enforces that every backend calls `b:build()` and never assigns
   directly to `app.backend.rest` or `graphql_resolvers`.
2. Add mock server as `test/mock-<newbackend>.lua` and build it in the `Makefile` (copy pattern from `mock-gitea.com`).
3. Add a `test/test-mock-validate.sh`-equivalent for the new backend if its spec differs meaningfully.
4. Add `<name>` to the `BACKENDS` list in the Makefile. Port numbers are assigned automatically.
5. For each catalog group where this backend has native support, create `test/<name>-<group>.hurl`.
   Groups with no custom file fall back to `test/stub-<group>.hurl` automatically. Run
   `make validate-tests` to see which groups lack coverage.
6. Add a column for the new backend in `site/compatibility.csv` and fill in support values
   for every endpoint row. Run `make validate-csv` to check consistency.

### Family-alias backend (API-compatible with an existing family)

A family alias shares one backend implementation, mock, and most tests with an existing root
backend. All four authoritative locations must be updated consistently — `make validate-providers`
will catch any mismatch.

1. Add the alias to `provider_families` in `internal/families.lua` (the single authoritative declaration):
   ```lua
   gitea = {
     aliases = {
       myalias = { default_url = "https://myalias.example.com",
                   strip = { "_package" } },  -- omit strip if no feature gaps
     },
   },
   ```
2. Create `backends/<alias>.lua` — a short file that sets the default base URL and
   dofiles the root backend:
   ```lua
   -- MyAlias is API-compatible with Gitea v1.  Family metadata in provider_families.
   if config.base_url == "" then
     config.base_url = provider_families.gitea.aliases[config.backend].default_url
   end
   dofile("/zip/backends/gitea.lua")
   ```
   The root backend (gitea.lua) reads strip patterns from `provider_families` automatically
   at build time — no separate strip wiring needed in the alias file.
3. Add `<alias>` to the `BACKENDS` list in the Makefile.
   No `test/mock-<alias>.lua` file is needed — `.make-families.mk` is auto-generated
   from `provider_families` and builds `mock-<alias>.com` from the root family's mock.
4. Add hurl test files and a `site/compatibility.csv` column as for a standalone backend (steps 5–6 above).
5. Run `make validate-providers` to confirm all three locations agree.

## Redbean API notes

- `GetMethod()`, `GetPath()`, `GetHeader()` — inspect the incoming request
- `SetStatus(code, reason)`, `SetHeader(name, value)`, `Write(body)` — build the response
- `Fetch(url[, opts])` — outgoing HTTP. `opts` may include `method`, `body`, and `headers` (table). Returns `status, headers, body`; wrap in `pcall` (throws on network failure). `make_fetch_opts(scheme)` in `internal/transport.lua` builds the opts table for auth passthrough.
- `EncodeBase64(str)` — standard base64 encoding (used for Basic auth headers)
- `EncodeJson(table)`, `DecodeJson(string)` — JSON encode/decode
- `Route()` — fall through to default Redbean routing (static files in the zip)
- `dofile(path)` — load a Lua file into the current environment (used for backend files)

## Process isolation in tests

Redbean sends `SIGTERM` to its entire process group on shutdown. Test scripts use `setsid` to isolate mock and app servers so killing one doesn't kill the harness. Always wrap new test server starts with:

```bash
if command -v setsid >/dev/null 2>&1; then
  (cd "$dir" && setsid $cmd) &
else
  (cd "$dir" && $cmd) &
fi
```

## Commit discipline

Every commit and every push must pass `make -j test`. No exceptions. This covers unit tests, integration tests, format, and lint in one command.

Fido's commits must use the GitHub noreply email and name:

```
git config user.email "190991155+FidoCanCode@users.noreply.github.com"
git config user.name "Fido Can Code"
```

Historical commits are covered by `.mailmap` — no rewrite needed.

## Lessons learned

Hard-won insights from building this project. **Keep this section current**: whenever you discover something surprising, fix a non-obvious bug, or learn a constraint that isn't derivable from the code, add it here before committing.

### Architectural deduplication baseline

Issues #111–#117 established four authoritative seams. Future endpoint and provider work should touch only these sources — all other surfaces are derived and must not be edited directly.

| Concern | Authoritative source | What is derived from it |
|---------|---------------------|------------------------|
| Routes and default handler stubs | `endpoint_sections` in `internal/catalog.lua` | route registration, `defaults` table wire-up, compatibility matrix sections, test file discovery, `make dump-endpoints` / `validate-tests` / `validate-csv` / `site` |
| Provider family membership | `provider_families` in `internal/families.lua` | mock building via `.make-families.mk` (auto-generated), `make validate-providers`, alias backend base URL and strip wiring |
| Backend transport scaffold | `make_backend_transport` in `internal/transport.lua` | `fetch_json`, `proxy_json*`, `proxy_204`, `proxy_json_list`, `proxy_health_check`, pagination params — all consumed by backends via the transport object |
| Application module layout | eleven `internal/*.lua` files, dofile'd in fixed order by `.init.lua` | the full global surface for backends; see "Internal module layout" for load order and exported globals |

**Adding an endpoint**: touch `internal/catalog.lua` (`endpoint_sections`) and `internal/defaults.lua`, plus per-backend overrides in `backends/<name>.lua` if native support is needed.

**Adding a standalone backend**: create `backends/<name>.lua`, add `<name>` to `BACKENDS` in the Makefile, create hurl test files, add a `site/compatibility.csv` column.

**Adding a family-alias backend**: update `provider_families` in `internal/families.lua` (the single declaration), create a `backends/<alias>.lua` that sets `config.base_url` from `provider_families` and dofiles the root backend, add to `BACKENDS` — no mock file needed.

**Guardrails — what CI will catch if you get it wrong:**

| What you're adding | What must be true | CI check that enforces it |
|--------------------|-------------------|--------------------------|
| New endpoint | Row in `endpoint_sections` in `internal/catalog.lua` | `make validate-tests`, `make validate-csv` |
| New endpoint with native support | CSV row updated with `y`/`~`/`n` and matching backend handler | `make validate-claims`, `make validate-csv` |
| New standalone backend | `backends/<name>.lua` calls `make_backend_builder()` and `b:build()` | `make validate-builders` |
| New standalone backend | Backend file does NOT assign `app.backend.rest` or `graphql_resolvers` directly | `make validate-builders` |
| New standalone backend | Mock + hurl tests cover at least every catalog group | `make validate-tests` |
| New family-alias backend | Alias declared in `provider_families` in `internal/families.lua` | `make validate-providers` |
| New family-alias backend | `backends/<alias>.lua` dofiles the root backend | `make validate-providers` |
| New family-alias backend | Alias listed in `BACKENDS` in the Makefile | `make validate-providers` |
| New capability module | Module registered via `b:capability()` with at least one function | `make validate-capabilities` |

**Backend registration**: all backends must use `make_backend_builder()` / `b:rest()` / `b:graphql()` / `b:capability()` / `b:build()`. Direct assignment to `app.backend.rest` or `graphql_resolvers` is forbidden. `make validate-builders` enforces this and is wired into `make test`.

**Building a capability module**: use `cap_fetch` / `cap_fetch_paged` inside capability operations to own the fetch+error-mapping step. Capability operations return `(data, nil)` on success or `(nil, err)` on failure where `err = { status = N, message = string }` (status 0 = network error). REST handlers call `cap_rest_respond` / `cap_rest_paged` / `cap_rest_created` / `cap_rest_204` to write the HTTP response. GraphQL resolvers just check `if not data then return nil end` and pass data to `graphql_translate_*`.

### SQLite via lsqlite3

Redbean 3.0 ships the `lsqlite3` Lua binding.  Load it with `require("lsqlite3")` — note that the module name is `lsqlite3`, not `sqlite3` (which is not found).

```lua
local sq = require("lsqlite3")
local db = sq.open(":memory:")          -- in-memory; or pass a file path
local db = sq.open_memory()            -- alternate in-memory helper
db:exec("CREATE TABLE ...")            -- DDL/DML with no result rows
for row in db:nrows("SELECT ...") do   -- iterator over named-key tables
  print(row.col_name)
end
local stmt = db:prepare("SELECT * WHERE id = ?")
stmt:bind_values(id)                   -- positional binding; nil → NULL
while stmt:step() == sq.ROW do
  local row = stmt:get_named_values()  -- {col_name = value, ...}
end
stmt:finalize()
db:close()
```

- **`sqlite3` global is `nil`** — the module is not auto-loaded; always `require("lsqlite3")`.
- **`sq.open(path)` returns `nil` on failure** (not an error), so check the result.
- **`stmt:bind_values(...)` handles nil correctly** — a nil argument binds to SQL NULL.  `select("#", ...)` counts trailing nils in Lua 5.4, so the C layer sees the correct count.
- **`INSERT OR REPLACE` is the idiom for upsert** — it deletes the existing row then inserts, so foreign-key dependents are NOT cascade-deleted unless you delete them explicitly first.
- **`db:exec()` is fine for `BEGIN`/`COMMIT`** — no binding needed; use `_exec(sql, ...)` only for parametrised statements.

### Redbean

- **`-D key=value` is NOT for Lua globals.** It means "directory overlay" — passing `-D backend=gitea` errors with "not a directory: backend=gitea". Use positional SCRIPTARGS instead: `sh ./confusio.com -- gitea`.
- **`Fetch(url, opts)` full signature**: `opts` is an optional table with keys `method`, `body`, and `headers` (a table of string pairs). Returns `status, headers, body` on success — but wrap in `pcall` because it throws on connection failure rather than returning an error status. Passing `nil` as `opts` is valid and makes an unauthenticated GET.
- **`EncodeBase64(str)`** is available and produces standard base64. Used by `make_fetch_opts` for Basic auth schemes.
- **`EncodeJson({})` produces `"{}"` (a JSON object), not `"[]"`.** Lua tables with no integer keys serialize as objects.
- **Redbean sends `SIGTERM` to its entire process group** on shutdown (not just to itself). Any test script that starts Redbean without `setsid` will be killed when confusio shuts down. Always use `setsid` to isolate server processes.

### Hurl

- **`jsonpath "$" == {}`** is not valid Hurl syntax — it errors with "invalid predicate value". Use `body == "{}"` for asserting an empty JSON object response.
- **`jsonpath "$.field" isString`** is the correct way to assert a field exists and is a string type.

### GitHub Actions composite actions

- **A local composite action (`uses: ./.github/actions/setup`) cannot contain `actions/checkout`.** The workflow runner needs to find the action file before checkout has run — chicken-and-egg. Always put `actions/checkout@v4` as an explicit first step in each job; the composite action handles everything after.

### Endpoint catalog

- **`endpoint_sections` is the single source of truth** for all routes. It drives route
  registration, the compatibility matrix, and test file discovery. When adding endpoints,
  only touch `endpoint_sections` in `internal/catalog.lua` — never manually update the matrix HTML or
  add hardcoded group lists elsewhere.
- **Group names** (the first element of each `endpoint_sections` entry) match test file
  suffixes (`test/<backend>-<group>.hurl`) and CSV section keys. They are stable identifiers;
  changing a group name requires updating test files and CSV rows.
- **Stub files as universal fallback**: `test/stub-<group>.hurl` is automatically run for
  any backend that lacks a `test/<backend>-<group>.hurl`. Write stubs to test the **default**
  confusio behavior (empty arrays, 404s). If a backend has native support for a group, create
  `test/<backend>-<group>.hurl` instead — never rely on the stub for a backend that returns
  real data, or the stub's 404 assertions will fail.
- **`make dump-endpoints`** exports the catalog as JSON. Used internally by `make site`,
  `make validate-csv`, and `make validate-tests`.

### Provider families

- **`provider_families` in `internal/families.lua` is the single authoritative source** for which
  backends belong to the same API family. It drives backend loading, mock building, and
  the `validate-providers` check. Never encode family membership only in filesystem layout
  or Makefile variables — both are derived from this table.
- **Alias backends set `config.base_url` from `provider_families` and dofile the root backend directly.**
  The root backend reads the alias's strip patterns from `provider_families` in the final
  `b:build(strip)` call, so feature gaps are applied declaratively rather than by post-hoc
  `app.backend.rest` mutation.
- **`strip` patterns are Lua patterns, not exact names.** `"_package"` matches any key
  containing `_package` (e.g. `list_packages`, `get_package`). Keep patterns tight enough
  not to accidentally strip unrelated keys.
- **Mock reuse is driven by `ALIAS_MOCK_RULE` in the Makefile**, not by `test/mock-<alias>.lua`
  symlinks. The `mock-<alias>.com` rule is generated automatically into `.make-families.mk`
  (gitignored) by `scripts/gen-family-mk.py` reading `dump-families.lua` output.  The
  Makefile `-include`s this file; if it doesn't exist Make rebuilds it before re-reading.
  No family-specific variable (e.g. `GITEA_FAMILY_ALIASES`) is needed in the Makefile.
- **`make dump-families`** exports `provider_families` as JSON. Useful for debugging and
  piped into `make validate-providers`.
- **`make validate-providers`** is wired into `make test`. It checks: root backend and mock
  exist; each alias backend dofiles the root backend; no stale `test/mock-<alias>.lua`
  files; every alias is in `BACKENDS`.

### Routing

- **Segment-based radix trie** (`route_add` / `route_match` in `internal/router.lua`): O(k) lookup where
  k = path depth. Static edges are preferred over param edges at each node, so `/repos/search`
  beats `/repos/{owner}` when both are registered. Captures from `{param}` segments are passed
  as positional arguments to the handler.
- **Startup-time handler resolution**: `app.backend.rest` is populated once by the backend file
  via `make_backend_builder()` / `b:build()`; the `OnHttpRequest` closure returned by
  `make_dispatcher(app)` reads it on every request via the `app` upvalue. The backend is fixed
  for the program's lifetime — no per-request dispatch needed. `dofile` runs in global scope so
  locals from any internal module are not visible to backend files.
- **`/zip/` prefix for dofile**: Redbean's `dofile` resolves paths on the real filesystem by
  default. Files inside the zip must be accessed as `dofile("/zip/backends/gitea.lua")`.
- **`SetStatus` clears all previously-set response headers.** Any `SetHeader` call made before
  `SetStatus` (or before `set_preamble`, which calls `SetStatus`) is silently discarded. Always
  call `SetStatus` / `set_preamble` first, then set additional headers like `Link`. This is why
  `proxy_json_paged` calls `set_preamble(200)` before `SetHeader("Link", rewritten)` rather than
  using the `respond_json` helper (which would call `SetStatus` last).
- **Mock route entries support an optional third element for extra headers**: `{status, body,
  {HeaderName = value, ...}}`. The dispatch loop iterates `entry[3]` and calls `SetHeader` for
  each pair, allowing mock routes to return headers like `Link` for pagination testing.

### Anonymous access

- **`app.allow_anonymous` is a boolean field on the app context** defaulting to `true`. `OnHttpRequest()` checks it on every request: if `false` and no `Authorization` header is present, confusio returns `401 { message = "This instance requires authentication." }` immediately, before routing.
- **Only Gitea probes its backend at startup.** The Gitea backend calls `GET /api/v1/settings/api` and sets `app.allow_anonymous = (settings.require_signin_view ~= true)`. If the probe fails (network error or non-200), the default `true` is preserved and anonymous requests are allowed.
- **All other backends leave the default `true`.** They neither probe nor set `app.allow_anonymous`, so anonymous access is always permitted regardless of the upstream's actual configuration.
- **Gitea-family backends (forgejo, gogs, codeberg, notabug) inherit Gitea's probe** because their alias backend files dofile `backends/gitea.lua`, which includes the probe block.
- **Test pattern**: `*-anon.hurl` files verify that unauthenticated requests succeed when the mock advertises anonymous access. The mock's `/api/v1/settings/api` route returns `{"require_signin_view": false}` to simulate an open instance. Closed-instance (401) behavior is covered by unit tests that set `app.allow_anonymous = false` directly.

### Mock server design

- **Use Redbean itself as the mock server** — no Python/Node dependency, same binary already in the repo. Build `mock-<backend>.com` by copying `redbean.com` and zipping in a `.init.lua` handler. See `mock-gitea.com` target in `Makefile`.
- **Mock validation via Hurl**: run the same `.hurl` assertion file against both the mock and the real endpoint. If both pass the same structural assertions, the mock is compatible. See `make validate-mock`.

### Webhook fixture generation

Webhook test fixtures live in `test/fixtures/webhooks/<backend>/`.  **Never hand-craft fixture variants that differ from a base file in only a few fields.** Instead, add a VARIANTS table entry to `scripts/gen-webhook-fixtures.sh` so the derived file is produced by a jq transform at test time:

```
backend|src_file.json|dst_file.json|.action = "closed" | .field = "value"
```

- **One base file per event** (e.g. `release-published.json`, `issues-opened.json`) — committed to git, hand-crafted.
- **All derived variants** (e.g. `release-edited.json`, `release-deleted.json`, `issues-closed.json`) — generated by the VARIANTS table; listed in `.gitignore`.
- **Run `make gen-webhook-fixtures`** (or `bash scripts/gen-webhook-fixtures.sh test`) before running tests if you changed the VARIANTS table.  `make test-unit` runs it automatically.
- **Forgejo fixtures are fully generated** from the Gitea source tree — the entire `test/fixtures/webhooks/forgejo/` directory is gitignored.
- **`validate-fixtures`** (`make validate-fixtures`) checks that every file referenced in a delivery hurl is present on disk and that no unreferenced files exist; it runs after `gen-webhook-fixtures` in `make test-unit`.

### Capability modules

A capability module is a local Lua table of named domain operations that owns fetch + error-mapping + translation for one resource type. Both REST handlers and GraphQL resolvers call into it, eliminating duplicated fetch+translate logic.

**Return shapes — three canonical forms:**

| Operation kind | Success | Failure |
|----------------|---------|---------|
| Single-item (GET, POST, PATCH) | `(data, nil)` — translated REST table | `(nil, err)` |
| Paginated list (GET list) | `(items, headers, nil)` — translated array + raw headers | `(nil, nil, err)` |
| Delete / merge (204 No Content) | `(true, nil)` | `(nil, err)` |

`err = { status = N, message = string }` always. `status = 0` means network error (pcall failure); any other value is the upstream HTTP status.

**When to use each fetch primitive:**

- **`cap_fetch(fetch_json, url [, method, body])`** — for operations that return a JSON body (single-item GET, POST, PATCH). Handles status checking and decodes the body; returns `(raw, err)`.
- **`cap_fetch_paged(fetch_json, url)`** — for paginated list operations. Returns `(items, headers, err)` where `headers` carries the raw response headers (including `Link` for pagination forwarding).
- **Direct `fetch_json(url, method)` + manual status check** — for operations that return 204 No Content (DELETE, POST-that-merges). There is no JSON body to decode. Return `(true, nil)` on success or `(nil, cap_err(status, message))` on failure.

**Translation layering:** capability operations apply `translate_gitea_*` internally before returning, so callers always receive GitHub REST shape. REST handlers pass it straight to the response adapters. GraphQL resolvers apply `graphql_translate_*` on top — they do **not** call `translate_gitea_*` again.

```lua
-- Good: cap returns REST shape; resolver applies graphql layer only.
local data, _ = issues_cap.get(owner, repo, number)
if not data then return nil end
return graphql_translate_issue(data, owner, repo)

-- Wrong: double-translate.
local data, _ = issues_cap.get(owner, repo, number)
return graphql_translate_issue(translate_gitea_issue(data), owner, repo)
```

**REST adapter selection guide:**

| Handler type | Adapter | Typical endpoint |
|-------------|---------|-----------------|
| Single-item read or update | `cap_rest_respond(data, err)` | GET or PATCH, 200 |
| Create (returns the new resource) | `cap_rest_created(data, err)` | POST, 201 |
| Delete / merge | `cap_rest_204(ok, err)` | DELETE, 204 |
| Paginated list | `cap_rest_paged(items, hdrs, err, PAGES)` | GET list, 200 + Link |

**GraphQL mutation error mapping for delete/merge operations:**

```lua
local ok, cerr = cap.delete(owner, repo, id)
if not ok then
  if cerr.status == 0 then
    graphql_error(ctx, cerr.message, nil, "INTERNAL_ERROR")
  elseif cerr.status == 401 or cerr.status == 403 then
    graphql_error(ctx, cerr.message, nil, "FORBIDDEN")
  elseif cerr.status == 404 then
    graphql_error(ctx, cerr.message, nil, "NOT_FOUND")
  else
    graphql_error(ctx, cerr.message, nil, "INTERNAL_ERROR")
  end
  return nil
end
```

**Naming conventions:**

- Capability table variable: plain domain name when no conflict (`repos`, `users`, `orgs`); `_cap` suffix when the name would shadow an existing variable (`issues_cap`, `pulls_cap`, `labels_cap`).
- Register with `b:capability("domain_name", table)`. The domain name is the key in `app.backend.capabilities` and is used for debugging / validation only — it does not affect routing.
- Operations: `get`, `list`, `create`, `update`, `delete`, `merge` for the primary CRUD surface. Use a `list_` prefix to disambiguate sub-resource lists: `list_repo` (all comments in a repo) vs `list_issue` (comments on one issue).

**`gitea_repo_connection` is intentionally NOT backed by a capability module.** It receives pre-fetched items inline from a single upstream page fetch and applies translation per item. Using `cap.get` per item would make O(n) redundant network calls. Keep `translate_gitea_*` direct for items inside connection translators.

**`make validate-capabilities`** checks that every registered capability module is a non-nil table with at least one function-valued operation. Wired into `make test`. Backends with zero capability registrations pass cleanly — zero is valid for backends not yet migrated.

### Shared proxy helpers

Two global helpers defined in `internal/proxy.lua` are available to all backend files:

**`translate_list(fn, items)`** — applies `fn` to every element of `items` (ipairs) and returns a new array. A nil `items` argument returns `{}`. Use whenever a backend loop has the form `for i, x in ipairs(arr) do result[i] = fn(x) end` where `fn` is an already-defined **named** function.

Do **not** use `translate_list` when:
- The loop **filters** (skips items with an `if` guard)
- The loop **truncates** (`for i = 1, math.min(limit, #arr) do`) — that's a slice, not a map
- The loop uses index `i` meaningfully in the output (e.g., `runs[i] = { id = i, ... }`)
- The transform is a **single-use inline anonymous closure** — don't extract a named function just to feed `translate_list`; the goal is removing duplication, not adding abstraction
- The loop has **side effects** (HTTP calls, state mutations)

**`proxy_search_envelope(translate_item, container, ok, status, _headers, body)`** — decodes the upstream body, extracts items from `container` (nil = root array, string = named key such as `"data"` or `"values"`), translates each with `translate_item`, and writes the GitHub search envelope `{"total_count":N,"incomplete_results":false,"items":[...]}`. The `ok/status/_headers/body` tuple is the raw return from `fetch_json`.

Do **not** use `proxy_search_envelope` when:
- The envelope key is not `"items"` (e.g., `check_runs`, `runners`) — use `respond_json` with the correct key
- The response must also **forward a Link header** — `proxy_search_envelope` only writes the body; `proxy_search_gl` (GitLab) and `proxy_actions_list` (Gitea) handle this themselves

**Retained patterns** intentionally left as custom code:
- `proxy_search_gl` (gitlab) — rewrites the upstream Link pagination header then writes the search envelope; `proxy_search_envelope` does not touch headers
- `proxy_actions_list` (gitea) — emits `{total_count, <key>: [...]}` with a caller-supplied key; `proxy_search_envelope` hardcodes `"items"`
- `get_commit_check_runs` in most backends — emits `{total_count, check_runs: [...]}` with key `"check_runs"`, not `"items"`
- `get_user_repos`/`get_org_repos`/`get_users_repos` in azuredevops — loop is `for i=1, math.min(limit, #all)` to honour a per_page cap; not a plain full-array map

### Internal module layout

The twelve `internal/` modules are loaded by `.init.lua` in a fixed order. Each exports only globals — no `require`/`return` pattern; `dofile` runs in global scope.

**Load order and exports:**

| Module | Globals exported | Consumer |
|--------|-----------------|----------|
| `http.lua` | `set_preamble`, `respond_json` | all modules + backends |
| `proxy.lua` | `proxy_json`, `proxy_json_paged`, `proxy_json_created`, `proxy_health_check`, `proxy_204`, `proxy_json_list`, `translate_list`, `proxy_search_envelope`, `rewrite_link_header` | backends |
| `transport.lua` | `append_page_params`, `make_fetch_opts`, `make_proxy_handler`, `make_backend_transport` | backends |
| `capabilities.lua` | `cap_err`, `cap_fetch`, `cap_fetch_paged`, `cap_rest_respond`, `cap_rest_created`, `cap_rest_204`, `cap_rest_paged` | backends (capability modules) |
| `translators.lua` | `owner_repo_id`, `translate_repo`, `translate_user`, `translate_migration` | backends |
| `families.lua` | `provider_families` | backends + Makefile scripts |
| `registry.lua` | `make_backend_builder` | backends |
| *(backend loaded here)* | calls `b:build()` to populate `app.backend.rest` and `graphql_resolvers` (aliased to `app.backend.graphql`); Gitea sets `app.allow_anonymous` | dispatch |
| `defaults.lua` | `defaults` (table of handler functions) | catalog |
| `router.lua` | `route_add`, `route_match`, `path_known` | catalog, dispatch |
| `catalog.lua` | `endpoints` (flat array); registers routes via `route_add` | dispatch, scripts |
| `signing.lua` | `sign_github`, `sign_for_backend` | backends (outbound delivery) |
| `webhooks.lua` | `make_webhook_receiver` | `.init.lua` (installed as `app.webhook_receiver`) |
| `dispatch.lua` | `make_dispatcher` | `.init.lua` (called once at startup to install `OnHttpRequest`) |

After `dispatch.lua` is loaded, `.init.lua` completes the composition:
```lua
app.route_match = route_match   -- bound router lookup
app.path_known = path_known     -- bound path-existence check
OnHttpRequest = make_dispatcher(app)  -- install Redbean entry point
```
`graphql_register_builtin_resolvers()` is called before the backend loads to register `Query.node`, `Query.nodes`, and `Query.rateLimit` into `graphql_resolvers`.

**Global surface for backend authors** (backends can call any of these):
- App context (write target): `app.allow_anonymous`, `app.config` — never assign `app.backend.rest`, `app.backend.graphql`, or `app.backend.capabilities` directly
- Builder (required): `make_backend_builder` — call `b:rest(name, fn)`, `b:graphql(key, fn)`, `b:capability(name, module)`, `b:set_allow_anonymous(v)`, then `b:build()` to commit; see `internal/registry.lua`
- Response: `set_preamble`, `respond_json`
- Proxy: all of `proxy.lua`'s exports
- Transport: all of `transport.lua`'s exports
- Capabilities: all of `capabilities.lua`'s exports — `cap_fetch`, `cap_fetch_paged` for operations; `cap_rest_*` for REST handlers; `cap_err` for error construction
- Translators: all of `translators.lua`'s exports
- Family metadata: `provider_families`

**Internal-only globals** (backends must not depend on these):
- `defaults` — implementation detail of the catalog; not part of the backend API
- `route_add`, `route_match`, `path_known` — router internals used only by catalog and dispatch
- `endpoints` — catalog output, consumed only by scripts and CI validation

**`/zip/internal/` → `internal/` redirect pattern**: scripts and unit tests load `.init.lua` via `redbean.com -i` (no zip context). They stub `dofile` to translate `/zip/internal/xxx` → `internal/xxx` (strip the `/zip/` prefix with `path:sub(6)`). The same stub skips `/zip/backends/` loads (not needed in test context). See `test/unit-init.lua` and `scripts/dump-endpoints.lua` for the canonical implementation.

### Compatibility CSV and validate-claims

- **`make validate-claims` cross-checks CSV claims against `app.backend.rest`** by running
  `scripts/dump-claims.lua` (all backends) and piping the JSON output to
  `scripts/validate-claims.lua`. It is wired into `make test` and must pass before any push.
- **CONFUSIO_NATIVE exemption**: five handlers (`get_meta`, `get_octocat`, `get_teapot`,
  `get_versions`, `get_zen`) synthesize complete GitHub-compatible responses without a per-backend
  handler. A `y` claim for these is valid for every backend and is exempted from the presence check.
  Do not broaden this set — other endpoints with `defaults.empty_list` or similar stubs are
  *not* confusio-native; a `y` claim for them requires an actual backend handler.
- **`has_default=true` does NOT exempt a `y` claim** from requiring a backend handler. The
  `has_default` flag only means there's a catalog default function — not that the response is
  meaningful for every backend. Only the five `CONFUSIO_NATIVE` handlers are truly backend-agnostic.
- **Common `~` patterns found during the audit** (record new ones as they appear):
  - `~files only` — `get_repo_content` proxies file blobs only; directory listing returns an error
    (most backends: onedev, pagure, sourcehut, gerrit, azuredevops)
  - `~no email fields` — commit translator always emits `email = ""`
    (Bitbucket Cloud: Bitbucket API does not expose committer emails)
  - `~no date fields` — commit translator always emits `date = ""`
    (Radicle: the commit API does not include timestamps)
  - `~primary language only` — language endpoint returns only the dominant language, not a
    breakdown by byte count (Bitbucket Cloud)
  - `~stub; returns 405` — handler exists but explicitly rejects the operation with 405
    (Radicle `delete_repo`: Radicle has no deletion endpoint)
- **GitBucket is GitHub-API-compatible**: its `nil`-translator pass-through handlers proxy
  directly to GitBucket's `/api/v3/` which mirrors the GitHub v3 API. All such handlers are `y`.
- **`dump-claims.lua` stubs `Fetch` to a noop** before loading each backend so that
  load-time network probes (e.g. Gitea's anonymous-access check) fail inside their `pcall`
  wrappers without making real network calls. This is necessary for `redbean.com -i` mode.
- **Alias backends dofile the root backend directly** (`dofile("/zip/backends/<root>.lua")`).
  The `dump-claims.lua` dofile stub must redirect `/zip/backends/` → `backends/` (not block
  it) so alias backends load their root correctly.

### Code coverage (luacov)

- **Redbean ships Lua 5.4 with the full `debug` library** (`debug.sethook` is available), so
  luacov's line-hook mechanism works without modification.
- **`package.path` is restricted to `/zip/.lua/` by default.** To `require 'luacov'`, extend it
  first: `package.path = 'path/to/luacov/?.lua;' .. package.path`. This must happen before
  `require('luacov')` is called.
- **luacov writes `luacov.stats.out` to the current working directory** (not the script directory).
  The report generator reads the same file; both must run from the same `cwd`.
- **luacov's `on_exit` cleanup fires via a `__gc` finalizer** on an anchor object. In Redbean `-i`
  mode the GC runs on script end — stats are written automatically without an explicit
  `runner.shutdown()` call.
- **Unit tests achieve 97.4% coverage of `.init.lua`** (527 executable lines hit, 14 missed).
  The 14 missed lines are: the SCRIPTARGS parsing block (requires a real `arg` table), four static
  response handler bodies (`get_emojis`, `get_repositories`, `octocat_response`,
  `versions_response`), and the coverage-bootstrap block in `test/unit-init.lua` itself.
- **HTTP-level (Hurl) tests CAN contribute coverage in Redbean uniprocess mode (`-u`).**
  The debug hook installed by `require('luacov')` IS active during `OnHttpRequest()` — the original
  assumption that "the hook doesn't survive request dispatch" was wrong. Verified empirically: a
  three-request session covers 381 lines of `.init.lua`, including request-handling code.
  The real obstacles are:
  1. **Flush**: SIGTERM kills the process before the GC `__gc` finalizer can write stats. You must
     call `luacov.runner.shutdown()` explicitly before the server exits — e.g. via a special HTTP
     endpoint or a SIGUSR1 handler patched into `.init.lua`.
  2. **Path mismatch**: server mode records source as `/zip/.init.lua`; unit tests record `.init.lua`.
     Merging both into one report requires normalising the filename key.
  3. **`runner.init()` vs `require('luacov')`**: use `runner.init()` in server mode so you hold a
     reference to the runner and can call `runner.shutdown()` later.
  **Practical verdict — not worth it**: unit tests already cover 97.4% and exercise every request
  dispatch path via direct Lua calls. HTTP tests would cover at most the 14 missed lines
  (SCRIPTARGS block + four static handlers), adding roughly 1.5 percentage points. The flush and
  path-normalisation machinery is not justified for that marginal gain.

### GraphQL design

The full design lives in `docs/graphql/` (16 numbered documents).  Key decisions recorded
here so they stay visible without reading all 16 docs:

- **`EncodeJson({data=nil})` silently drops the `data` key** — produces `{"errors":[...]}` instead of `{"data":null,"errors":[...]}`. The `respond_graphql` function works around this by using manual string concatenation: `EncodeJson(nil)` → `"null"`, so `'{"data":' .. data_json .. ...}` is assembled by hand when `data` is nil. Never pass `{data=nil}` to `EncodeJson` in the GraphQL response path.
- **All GraphQL-facing Lua tables use camelCase keys** (GraphQL field names, e.g. `nameWithOwner`, `totalCount`, `hasNextPage`) — not the REST snake_case field names. The executor plucks fields by doing `parent[field_name]` where `field_name` is the GraphQL name from the query, so the keys must match exactly. This is an exception to the REST translator convention.
- **`graphql_resolvers` is a global table aliased to `app.backend.graphql`**. `.init.lua` assigns `app.backend.graphql = graphql_resolvers` after creating the app context, so both names reference the same table. Backends populate it via `b:graphql(key, fn)`; the executor reads it on every request. Backends never assign a `graphql_request` key directly; that handler is always `graphql_handler` from `graphql_executor.lua`.
- **GraphQL coverage is bounded by REST coverage** — a GraphQL resolver calls the same REST endpoint the REST handler already uses. A backend that doesn't implement a REST endpoint will return `null` for the corresponding GraphQL field, with an error entry if the field is non-null. No backend gains new REST coverage by adding GraphQL.
- **Node IDs use path-segment encoding**: `encode_node_id("Repository", "owner/repo")` = `EncodeBase64("Repository:owner/repo")`. Path segments (not integer IDs) because REST backends universally support `GET /repos/{owner}/{repo}` but rarely `GET /repositories/{integer_id}`. Stable across restarts; the `node()` resolver constructs the same REST URL any other resolver uses.
- **Item-level cursors** (`EncodeBase64("page:N:M")`) where N is the 1-based page number and M is the 1-based item index within the page. Each edge carries a unique cursor. `graphql_cursor_to_page` accepts both the old `page:N` format (backward compat) and the new `page:N:M` format, extracting only the page number — so all REST URL construction is unaffected. `startCursor` and `endCursor` in `pageInfo` are the first and last edge cursors respectively; they are distinct for multi-item pages.
- **`graphql_request = true` must be added to `CONFUSIO_NATIVE`** in `scripts/validate-claims.lua` when the GraphQL catalog entry ships. Without this exemption, any `y` CSV claim for `POST /graphql` will fail `make validate-claims` (the handler is `graphql_handler`, not an `app.backend.rest` key).
- **`pages.yml` passes args to `gen-matrix.py` in a different order than the Makefile** — the workflow passes `site/compatibility.csv` as the first positional arg (catalog position) while the Makefile pipes catalog via stdin with `-`. This pre-existing discrepancy exists independently of GraphQL; note it before touching either invocation.
- **`graphql_schema_data.lua` is committed generated output**, not regenerated at build time. The `make generate-schema` target regenerates it from the vendored SDL; `make validate-schema` checks it is up to date. This mirrors how `vendor/github-rest-api-description/` handles the REST OpenAPI spec.

### GraphQL mutations (Phase 2)

- **Serial execution is free**: Lua/Redbean is single-threaded, so all mutation root fields execute serially in document order automatically. No special serial-execution machinery was added; the existing `execute_selection_set` loop already processes fields one at a time.
- **`get_client_mutation_id(args)` is the canonical helper** for extracting the Relay `clientMutationId` from mutation input. Call it at the top of every mutation resolver, store the result in a local, and include it in the returned payload table. Never forward it to the REST API body.
- **Input `ID!` fields are base64 node IDs** — always decode with `decode_node_id(id)` and type-check the returned type tag before extracting the path segments. A wrong type tag (e.g., passing an Issue ID to a resolver expecting a Repository ID) returns `BAD_USER_INPUT`, not a network call.
- **Enum coercion is manual**: GraphQL enum values arrive as uppercase strings (`"OPEN"`, `"CLOSED"`, `"PRIVATE"`, `"SUBSCRIBED"`, etc.). Map them to REST values in the resolver body — typically lowercase strings or booleans. There is no automatic coercion layer.
- **`EncodeJson` silently drops nil-valued keys**: pass the full input table to `EncodeJson` and let nil fields disappear naturally. Do not build conditional tables with `if input.foo then body.foo = input.foo end` — just assign all fields and let nil omit them.
- **`DELETE`-returning-204 mutations call `fetch_json` directly** (not `graphql_fetch_or_error`) because there is no JSON body to decode. Check `ok, status` manually, map error statuses to `graphql_error` calls, then re-fetch the resource with `graphql_fetch_or_error` to populate the payload. The same pattern applies to `PUT`/`DELETE` for star, unstar, and subscription mutations.
- **Integration tests use hurl `[Captures]` + GraphQL variables** to thread node IDs through a multi-step sequence without hardcoding base64 strings. Capture the `id` field from a create step, then pass it as a `variables` object in subsequent queries (`$id: ID!`). This makes test intent clear and avoids fragile base64 literals.
- **Self-cleaning integration tests use a fixed repo name** (`confusio-mutation-test`). If a prior failed run leaves the repo behind, delete it manually on gitea.com and re-run. The `deleteRepository` step always comes last so it cascades to all issues, comments, and labels created during the run.
- **`GITEA_TOKEN` gates mutation integration tests**: `test/test-integration.sh` checks `[ -n "${GITEA_TOKEN:-}" ]` before invoking `test/integration-graphql-mutations.hurl`. Tests are skipped (not failed) when the token is absent, so CI stays green without the secret wired in.

### GraphQL Phase 2b (batch, pagination, cursors, additional nodes)

- **Batch requests are detected by `req[1] ~= nil`** — if the decoded JSON body is a table with a numeric key, it is a batch array; otherwise it is a single operation.  The response is a parallel JSON array with one result object per input operation, each independently encoded via `encode_result`. HTTP 200 is always returned, even when individual operations fail.
- **Each batch operation gets its own execution context** (`errors`, `path`, `cache`, `rate_cost`). Failures in one operation do not affect others. Cost is per-operation, not summed across the batch.
- **Backward pagination with `last: N` (no `before`) requires a two-pass strategy**: first fetch the collection with `limit=1` to read the total from `X-Total` / `X-Total-Count`, then compute `last_page = ceil(total / per_page)` and fetch the real last page.  `graphql_prefetch_total_from_headers` encapsulates the first pass.  Backends without total headers fall back to page 1 (returning the first page, not the last) — a known limitation documented per backend.
- **`last: N, before: cursor` never needs a prefetch** — the cursor already encodes the target page; the resolver fetches `page = cursor_page - 1` directly.
- **`gitea_repo_connection` is the single orchestrator** for all paginated list sub-resolvers under `Repository.*` (issues, pullRequests, labels, milestones, refs, releases, collaborators).  Adding a new paginated field means calling `gitea_repo_connection` with the REST suffix, a translate function, and a connection builder — the two-pass prefetch and header extraction are already wired in.
- **`?type=issues` is required on the Gitea issues endpoint** — without it, `/repos/{o}/{r}/issues` returns both issues and pull requests.  `Repository.issues` always appends `?type=issues`; `Repository.pullRequests` calls the separate `/pulls` endpoint.
- **Item-level cursors encode `page:N:M`** where N is the 1-based page number and M is the 1-based item index within the page.  `graphql_cursor_to_page` extracts only N (the `:M` suffix is ignored), so the cursor remains valid when the client changes `first`/`last` between requests.  Old page-only cursors (`page:N`) are also accepted — backward compat is unconditional.
- **`startCursor` and `endCursor` are distinct on multi-item pages** (first vs. last edge cursor) but equal when the page holds exactly one item.  Inline connections (labels, assignees) set `cursor = ""` on each edge because they are never paginated.
- **Gitea branch objects use `commit.id` instead of `commit.sha`** — `node.Ref` normalises this with `data.commit.sha = data.commit.id` before calling `graphql_translate_ref`, which reads `commit.sha`.  Any future Ref resolver must apply the same normalisation.
- **`node.Ref` only handles `refs/heads/…` paths** — the local ID stores the full ref path (e.g., `refs/heads/main`), the short branch name is extracted with `ref_path:match("^refs/heads/(.+)$")`.  Tag refs (`refs/tags/…`) are not yet supported; the resolver returns `nil` for them.
- **`graphql_translate_commit` handles two incoming shapes**: REST commit endpoints nest author/committer under `c.commit.author`; git-API endpoints put them at the root.  The translator selects with `local git = c.commit or c` and then reads `git.author`, `git.committer` for the git-level fields.
- **Team node lookup is O(teams)**: Gitea has no slug-based lookup, so `node.Team` lists all org teams (`?limit=50`) and scans for a name match.  Orgs with more than 50 teams will silently fail to find teams beyond the first page — a known limitation.
- **Multi-page backward pagination mock tests use `GetParam("page")`** — `mock-gitea.lua` cannot use the table-driven route map for page-varying responses.  Add an `elseif` branch that calls `GetParam("page")` and returns the appropriate fixture, as done for `octocat/paged-repo`.

### Webhook receiver

- **Auth bypass belongs BEFORE the anonymous-access gate.**  Forge webhook deliveries carry their own authentication (HMAC signatures, bearer tokens, verbatim shared secrets) and must never be gated by the REST API `Authorization` header check.  `dispatch.lua` tests `GetPath():match("^/webhooks/")` and routes to `a.webhook_receiver()` before `a.allow_anonymous` is consulted.  The receiver's own signature verification serves as the auth layer.
- **Verify the raw bytes before JSON decoding.**  HMAC is computed over the exact bytes the forge serialised — not over a round-tripped Lua table.  Buffer the body with `GetBody()` first, pass those bytes to `verify_signature`, then call `DecodeJson`.  Re-encoding after decode would change byte order and invalidate the digest.
- **Constant-time comparison is mandatory for secrets and digests.**  Use `ct_equal(a, b)` (XOR-accumulate over all bytes) rather than `a == b`.  Lua's built-in `==` short-circuits on the first mismatched byte, leaking the comparison result via timing.  Length differences are not secret and may return early.
- **Kallithea is the sole exception to verify-before-parse.**  Its authentication token is embedded in the JSON body (`secret` or `data.secret`), so the body must be decoded to extract the token.  The decoded table is then re-used for event processing — no second decode needed.
- **Trust-the-network for unimplemented schemes.**  CodeCommit (SNS X.509), Sourcehut (ed25519), and Launchpad (OpenPGP) use asymmetric or platform-managed schemes not yet implemented.  When no secret is configured, all requests are accepted.  When a secret IS configured, all requests are rejected — operators must restrict access via network policy until verification ships.
- **Pre-routing endpoints need catalog entries for validate-csv/validate-tests.**  `POST /webhooks/{backend}` is intercepted by `dispatch.lua` before the router runs, so the catalog's default stub is never called in production.  The entry exists purely so `validate-csv` and `validate-tests` can account for the endpoint.  Add such handler names to `CONFUSIO_NATIVE` in `scripts/validate-claims.lua` — otherwise `y` CSV claims for all backends will fail because `app.backend.rest` has no entry.
- **`b:build(strip)` never strips webhook handlers.**  Strip patterns only apply to `app.backend.rest` keys; `app.backend.webhooks` entries registered via `b:webhook()` are always preserved regardless of the strip list passed to `b:build()`.
- **Raw hurl bodies require backtick syntax.**  To send a body that doesn't start with `{` or `[` (e.g., `not-valid-json` for an invalid-JSON test), wrap it in backticks: `` `not-valid-json` ``.  Without backticks, hurl attempts to parse the first word as an HTTP method and fails with a parse error.
- **Signature schemes are verified in `verify_signature(backend, secret, body[, now])`** in `internal/webhooks.lua`.  The optional `now` parameter defaults to `os.time()` and exists purely for unit testing — pass a fixed timestamp to test replay prevention without sleeping.  Production code always omits it.
- **Outbound signing lives in `internal/signing.lua`** (`sign_github`, `sign_for_backend`).  `sign_github(secret, body)` returns `(sha256_value, sha1_value)`; `sign_for_backend(backend, secret, body)` returns a table of native signature headers for the given backend (empty table when no secret).
- **Confusio inbound HMAC basestring is `"v1:<ts>:<body>"`** — the timestamp is baked into the signed material, not just the header.  This means a replay with a fresh timestamp produces a different digest and fails even before the window check.  The `confusio` case in `sign_for_backend` and inbound `verify_signature("confusio", ...)` are symmetric — they must stay in sync.
- **Replay window is 300 seconds (±5 minutes)** enforced by `REPLAY_WINDOW_SECS` in `webhooks.lua`.  Only the confusio scheme has replay prevention; other schemes (HMAC or token) rely on TLS and network policy.
- **`webhook_secret_file_BACKEND=/path` SCRIPTARG** — path to a file containing the inbound signing secret for a specific backend.  The file must be owned by the current process's effective uid and have permissions exactly 0600; confusio errors at startup if these conditions are not met.  Absent key → trust-the-network for that backend.  Example: `sh ./confusio.com -- gitea webhook_secret_file_gitea=/run/secrets/gitea-webhook`.
- **Phase 4 in `test/test-unit.sh`** computes HMAC test vectors at runtime with `openssl dgst` and passes them to `hurl` via `--variable` flags.  Never hard-code pre-computed HMACs in the test file — the confusio signature embeds `$(date +%s)` and would be stale by replay-window expiry if pre-computed.  The gitea/bitbucket/gitbucket vectors are stable (no timestamp), but computing all of them uniformly at runtime is simpler and safer.  Secrets are written to temp files with `chmod 600` and passed via `webhook_secret_file_BACKEND=/path` SCRIPTARGS.

### Outbound webhook dispatcher

When a webhook event arrives from a forge backend, confusio can forward it to a single configured outbound target.  Delivery is fire-and-record: the HTTP POST is attempted synchronously, the outcome is logged (status code or error), and confusio responds immediately.  There is no SQLite persistence, no retry scheduler, and no circuit breaker.

**Modules:**

| Module | Role |
|--------|------|
| `internal/fanout.lua` | In-memory target registry; `fanout_register_target`, `fanout_dispatch`, `fanout_body`; routes `confusio` shape through normalized webhook translators |
| `internal/deliver.lua` | Outbound HTTP delivery: `deliver_fire(target, backend, event_type, payload[, internal_event, translators])` |
| `internal/signing.lua` | HMAC signing for outbound deliveries using the backend's native scheme |

**Configuration:**
- **`webhook_target=URL` SCRIPTARG** — URL of the single outbound target.  Optional; when absent, no deliveries are made.  Example: `sh ./confusio.com -- gitea webhook_target=https://hook.example.com`.
- **`webhook_target_name=NAME`** — logical name for the configured outbound target in delivery log lines (default: `default`).
- **`webhook_target_events=A,B`** — comma-separated event filter (default: `*` = all events).
- **`webhook_target_shape=github|confusio`** — delivery body shape (default: `github`).
- **`webhook_target_secret_file=/path`** — path to a 0600-permission file containing the HMAC signing secret for the outbound target.
- **`webhook_secret_file_BACKEND=/path`** provides per-backend inbound signing secrets (see above).

**Dispatch flow:** After the webhook receiver validates an inbound event, `fanout_dispatch(backend, event_type, payload, internal_event, app.backend.webhook_translators)` fires `deliver_fire` for each registered target whose event subscription matches.  The default `github` shape forwards the raw payload; `confusio` shape uses `app.backend.webhook_translators[event_type]` when present and falls back to `make_normalized_webhook_envelope`.  `deliver_fire` makes one HTTP POST with optional HMAC signing and emits a delivery-attempt log line to stderr with the target name, backend, event type, delivery ID, duration, HTTP status when available, and error text when delivery fails before an HTTP response.  It logs at `kLogWarn` on failure or `kLogVerbose` on success.  Returns `(ok, http_status_or_nil, error_or_nil)`.  The caller does not inspect the return values — the result is purely for log visibility.

- **Outbound signing mirrors the active backend's inbound scheme.** The `sign_for_backend` function in `internal/signing.lua` maps backend names to their native signature headers using the same schemes documented in `verify_signature` in `internal/webhooks.lua`.  The two must stay in sync when new backends are added.
