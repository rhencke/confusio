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
  translators.lua            — shared Gitea-family translators: translate_repo, translate_user, translate_migration, owner_repo_id
  families.lua               — provider_families table and load_family_backend
  defaults.lua               — default stub handlers collected in the global `defaults` table
  router.lua                 — segment-based radix trie: route_add, route_match, path_known
  catalog.lua                — endpoint_sections table; populates global `endpoints` and registers routes at load time
  dispatch.lua               — OnHttpRequest: auth gate, route_match, handler dispatch
backends/                    — per-provider implementations; each sets app.backend_impl = { handler = fn, ... }
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

Config is supplied as positional SCRIPTARGS after `--`: first arg = backend, second arg = base_url.

| Mechanism | Syntax |
|-----------|--------|
| SCRIPTARGS (positional) | `sh ./confusio.com -- <backend> [base_url]` |
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

1. Create `backends/<name>.lua`. Set `app.backend_impl = { endpoint = function, ... }` with only
   the endpoints that differ from the defaults. The file is loaded automatically when
   `config.backend == "<name>"` — no changes to `.init.lua` needed.
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
2. Create `backends/<alias>.lua` — one line plus a comment:
   ```lua
   -- MyAlias is API-compatible with Gitea v1.  Family metadata in provider_families.
   load_family_backend("gitea")
   ```
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
| Provider family membership | `provider_families` in `internal/families.lua` | mock building via `.make-families.mk` (auto-generated), `make validate-providers`, `load_family_backend` behavior |
| Backend transport scaffold | `make_backend_transport` in `internal/transport.lua` | `fetch_json`, `proxy_json*`, `proxy_204`, `proxy_json_list`, `proxy_health_check`, pagination params — all consumed by backends via the transport object |
| Application module layout | ten `internal/*.lua` files, dofile'd in fixed order by `.init.lua` | the full global surface for backends; see "Internal module layout" for load order and exported globals |

**Adding an endpoint**: touch `internal/catalog.lua` (`endpoint_sections`) and `internal/defaults.lua`, plus per-backend overrides in `backends/<name>.lua` if native support is needed.

**Adding a standalone backend**: create `backends/<name>.lua`, add `<name>` to `BACKENDS` in the Makefile, create hurl test files, add a `site/compatibility.csv` column.

**Adding a family-alias backend**: update `provider_families` in `internal/families.lua` (the single declaration), create a one-line `backends/<alias>.lua` calling `load_family_backend`, add to `BACKENDS` — no mock file needed.

**Backend registration**: all backends must use `make_backend_builder()` / `b:rest()` / `b:graphql()` / `b:build()`. Direct assignment to `app.backend_impl` or `graphql_resolvers` is forbidden. `make validate-builders` enforces this and is wired into `make test`.

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
- **`load_family_backend(root)`** is the helper alias backends call instead of raw `dofile`.
  It reads the alias's entry from `provider_families[root].aliases[config.backend]`, sets
  `config.base_url` from `default_url` when none was supplied, declares the alias's strip
  patterns in `app._family_strip`, then dofiles the root backend.  The root backend's
  builder reads `app._family_strip` in `b:build()` and excludes matching REST keys — no
  post-hoc `app.backend_impl` mutation needed.  `app._family_strip` is cleared to nil
  after dofile returns so it doesn't affect other code.
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
  exist; each alias backend calls `load_family_backend`; no stale `test/mock-<alias>.lua`
  files; every alias is in `BACKENDS`.

### Routing

- **Segment-based radix trie** (`route_add` / `route_match` in `internal/router.lua`): O(k) lookup where
  k = path depth. Static edges are preferred over param edges at each node, so `/repos/search`
  beats `/repos/{owner}` when both are registered. Captures from `{param}` segments are passed
  as positional arguments to the handler.
- **Startup-time handler resolution**: `app.backend_impl` is populated once by the backend file;
  `internal/dispatch.lua` reads it on every request via the `app` context. The backend is fixed
  for the program's lifetime — no per-request dispatch needed. Backend files set
  `app.backend_impl = { ... }`; `dofile` runs in global scope so locals from any module
  are not visible to backend files.
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
- **Gitea-family backends (forgejo, gogs, codeberg, notabug) inherit Gitea's probe** because `load_family_backend("gitea")` dofiles `backends/gitea.lua`, which includes the probe block.
- **Test pattern**: `*-anon.hurl` files verify that unauthenticated requests succeed when the mock advertises anonymous access. The mock's `/api/v1/settings/api` route returns `{"require_signin_view": false}` to simulate an open instance. Closed-instance (401) behavior is covered by unit tests that set `app.allow_anonymous = false` directly.

### Mock server design

- **Use Redbean itself as the mock server** — no Python/Node dependency, same binary already in the repo. Build `mock-<backend>.com` by copying `redbean.com` and zipping in a `.init.lua` handler. See `mock-gitea.com` target in `Makefile`.
- **Mock validation via Hurl**: run the same `.hurl` assertion file against both the mock and the real endpoint. If both pass the same structural assertions, the mock is compatible. See `make validate-mock`.

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

The ten `internal/` modules are loaded by `.init.lua` in a fixed order. Each exports only globals — no `require`/`return` pattern; `dofile` runs in global scope.

**Load order and exports:**

| Module | Globals exported | Consumer |
|--------|-----------------|----------|
| `http.lua` | `set_preamble`, `respond_json` | all modules + backends |
| `proxy.lua` | `proxy_json`, `proxy_json_paged`, `proxy_json_created`, `proxy_health_check`, `proxy_204`, `proxy_json_list`, `translate_list`, `proxy_search_envelope`, `rewrite_link_header` | backends |
| `transport.lua` | `append_page_params`, `make_fetch_opts`, `make_proxy_handler`, `make_backend_transport` | backends |
| `translators.lua` | `owner_repo_id`, `translate_repo`, `translate_user`, `translate_migration` | backends |
| `families.lua` | `provider_families`, `load_family_backend` | backends + Makefile scripts |
| `registry.lua` | `make_backend_builder` | backends |
| *(backend loaded here)* | calls `b:build()` to populate `app.backend_impl` and `graphql_resolvers`; Gitea sets `app.allow_anonymous` | dispatch |
| `defaults.lua` | `defaults` (table of handler functions) | catalog |
| `router.lua` | `route_add`, `route_match`, `path_known` | catalog, dispatch |
| `catalog.lua` | `endpoints` (flat array); registers routes via `route_add` | dispatch, scripts |
| `dispatch.lua` | `OnHttpRequest` | Redbean (entry point) |

**Global surface for backend authors** (backends can call any of these):
- App context (write target): `app.allow_anonymous`, `app.config` — never assign `app.backend_impl` directly
- Builder (required): `make_backend_builder` — call `b:rest(name, fn)`, `b:graphql(key, fn)`, `b:set_allow_anonymous(v)`, then `b:build()` to commit; see `internal/registry.lua`
- Response: `set_preamble`, `respond_json`
- Proxy: all of `proxy.lua`'s exports
- Transport: all of `transport.lua`'s exports
- Translators: all of `translators.lua`'s exports
- Family loading: `load_family_backend`

**Internal-only globals** (backends must not depend on these):
- `defaults` — implementation detail of the catalog; not part of the backend API
- `route_add`, `route_match`, `path_known` — router internals used only by catalog and dispatch
- `endpoints` — catalog output, consumed only by scripts and CI validation

**`/zip/internal/` → `internal/` redirect pattern**: scripts and unit tests load `.init.lua` via `redbean.com -i` (no zip context). They stub `dofile` to translate `/zip/internal/xxx` → `internal/xxx` (strip the `/zip/` prefix with `path:sub(6)`). The same stub skips `/zip/backends/` loads (not needed in test context). See `test/unit-init.lua` and `scripts/dump-endpoints.lua` for the canonical implementation.

### Compatibility CSV and validate-claims

- **`make validate-claims` cross-checks CSV claims against `app.backend_impl`** by running
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
- **Alias backends call `load_family_backend(root)`**, which internally calls
  `dofile("/zip/backends/<root>.lua")`. The `dump-claims.lua` dofile stub must redirect
  `/zip/backends/` → `backends/` (not block it) so alias backends load their root correctly.

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
- **`graphql_resolvers` is a global table, not part of `app.backend_impl`**. Backends populate it at load time alongside `app.backend_impl`. The executor reads it on every request. Backends never set `app.backend_impl.graphql_request`; that handler is always `graphql_handler` from `graphql_executor.lua`.
- **GraphQL coverage is bounded by REST coverage** — a GraphQL resolver calls the same REST endpoint the REST handler already uses. A backend that doesn't implement a REST endpoint will return `null` for the corresponding GraphQL field, with an error entry if the field is non-null. No backend gains new REST coverage by adding GraphQL.
- **Node IDs use path-segment encoding**: `encode_node_id("Repository", "owner/repo")` = `EncodeBase64("Repository:owner/repo")`. Path segments (not integer IDs) because REST backends universally support `GET /repos/{owner}/{repo}` but rarely `GET /repositories/{integer_id}`. Stable across restarts; the `node()` resolver constructs the same REST URL any other resolver uses.
- **Item-level cursors** (`EncodeBase64("page:N:M")`) where N is the 1-based page number and M is the 1-based item index within the page. Each edge carries a unique cursor. `graphql_cursor_to_page` accepts both the old `page:N` format (backward compat) and the new `page:N:M` format, extracting only the page number — so all REST URL construction is unaffected. `startCursor` and `endCursor` in `pageInfo` are the first and last edge cursors respectively; they are distinct for multi-item pages.
- **`graphql_request = true` must be added to `CONFUSIO_NATIVE`** in `scripts/validate-claims.lua` when the GraphQL catalog entry ships. Without this exemption, any `y` CSV claim for `POST /graphql` will fail `make validate-claims` (the handler is `graphql_handler`, not an `app.backend_impl` key).
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
