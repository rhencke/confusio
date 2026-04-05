# confusio — Claude instructions

## What this is

A single-file Redbean/Lua HTTP proxy that translates GitHub API calls to other git hosting providers (Gitea, GitLab, Bitbucket, Forgejo, Sourcehut). The GitHub API is the interface; provider-native APIs are the backends.

Built with [Redbean](https://redbean.dev): a self-contained web server + Lua interpreter distributed as a self-extracting zip. The main application source is `.init.lua`, which Redbean executes on startup.

## Build and test

| Command | What it does |
|---------|-------------|
| `make build` | Produces `confusio.com` (app) |
| `make test-unit` | Unit tests against mock backends, no network |
| `make test-integration` | Integration tests against live gitea.com |
| `make test` | Both of the above |
| `make validate-mock` | Run `test/gitea-api-version.hurl` against both the mock and a real Gitea instance to check they agree |
| `make site` | Build GitHub Pages site into `_site/` (generates matrix from CSV) |

**Before any commit: run `make -j test-unit`.** `make -j test-integration` requires network and is acceptable to defer to CI.

**Checking test results:** Use the exit code, not stdout parsing. The output is noisy (redbean logs prefixed with `I2026-`). The correct pattern:
```bash
make -j test-unit; echo "EXIT: $?"
```
Only spelunk the output if the exit code is non-zero.

## Project structure

```
.init.lua                    — Redbean app entry point (all application logic lives here)
Makefile                     — build, test, and download targets
.redbean-version             — pinned Redbean version (wget'd by make)
.hurl-version                — pinned Hurl version (curl'd by make)
site/
  index.html                 — GitHub Pages template (contains <!-- COMPAT_MATRIX --> placeholder)
  compatibility.csv          — compatibility matrix source data (one row per route group, one column per provider)
scripts/
  gen-matrix.py              — generates the HTML table from compatibility.csv into the template
_site/                       — generated output (gitignored; produced by `make site` or the Pages workflow)
test/
  test-unit.sh               — unit test harness (starts confusio + mock, runs hurl)
  test-integration.sh        — integration test harness (live gitea.com)
  test-mock-validate.sh      — validate mock response structure vs real instance
  root.hurl                  — hurl assertions for GET / (no backend)
  gitea-root.hurl            — hurl assertions for GET / (gitea backend)
  gitea-api-version.hurl     — hurl assertions for /api/v1/version (used by validate-mock)
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

# Gitea backend via config file (.confusio.lua in working directory)
sh ./confusio.com -p 8080
# .confusio.lua: confusio = { backend="gitea", base_url="https://gitea.com" }
```

## Configuration system

Config has two mechanisms:

| Mechanism | Syntax |
|-----------|--------|
| SCRIPTARGS (highest precedence) | `sh ./confusio.com -- <backend> [base_url]` |
| `.confusio.lua` config file | `confusio = { backend = "...", base_url = "..." }` |
| Defaults (lowest precedence) | hardcoded in `.init.lua` |

SCRIPTARGS are positional: first arg = backend, second arg = base_url. Key=value form (`backend=gitea base_url=https://...`) is also accepted.

Config file is Lua (not TOML/JSON) so it can call functions — useful for secrets backends (e.g., `base_url = vault_read("secret/gitea-url")`).

## GitHub API reference

The vendored spec at `vendor/github-rest-api-description/api.github.com.yaml` is the source of truth for what endpoints confusio should expose and what their request/response shapes are.

When implementing a new endpoint, check the spec for:
- Path and method
- Required/optional query params and request body fields
- Response status codes and body schema

## Adding a new endpoint

1. Check `vendor/github-rest-api-description/api.github.com.yaml` for the endpoint's contract.
2. Add a `route_add(...)` call in `.init.lua`:
   - Exact path: `route_add("/emojis", "emojis")`
   - Parametric path: `route_add("/repos/{owner}/{repo}", "repo")`
3. Add a default handler to the `defaults` table in `.init.lua`.
4. If any backend behaves differently, add an override in `backends/<name>.lua`.
   Parametric captures are passed positionally: `repo = function(owner, repo) ... end`
5. Add a hurl assertion file in `test/` and wire it into `test/test-unit.sh` (mock) and `test/test-integration.sh` (live).
6. Update `site/compatibility.csv`: add a row (or update an existing row) for the new endpoint. Values: `y` = native support, `~` = partial/stub, `n` = returns 404/501. The GitHub Pages site is regenerated automatically from this CSV in CI — never edit the generated HTML.

## Adding a new backend

1. Create `backends/<name>.lua`. Set `backend_impl = { endpoint = function, ... }` with only
   the endpoints that differ from the defaults. The file is loaded automatically when
   `config.backend == "<name>"` — no changes to `.init.lua` needed.
2. Add mock server as `test/mock-<newbackend>.lua` and build it in the `Makefile` (copy pattern from `mock-gitea.com`).
3. Add a `test/test-mock-validate.sh`-equivalent for the new backend if its spec differs meaningfully.
4. Add a column for the new backend in `site/compatibility.csv` and fill in support values for every row.

## Redbean API notes

- `GetMethod()`, `GetPath()`, `GetHeader()` — inspect the incoming request
- `SetStatus(code, reason)`, `SetHeader(name, value)`, `Write(body)` — build the response
- `Fetch(url[, opts])` — outgoing HTTP. `opts` may include `method`, `body`, and `headers` (table). Returns `status, headers, body`; wrap in `pcall` (throws on network failure). `make_fetch_opts(scheme)` in `.init.lua` builds the opts table for auth passthrough.
- `EncodeBase64(str)` — standard base64 encoding (used for Basic auth headers)
- `EncodeJson(table)`, `DecodeJson(string)` — JSON encode/decode
- `Route()` — fall through to default Redbean routing (static files in the zip)
- `dofile(path)` — load a Lua file into the current environment (used for `.confusio.lua`)

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

Every commit must pass `make -j test-unit`. No exceptions.

## Lessons learned

Hard-won insights from building this project. **Keep this section current**: whenever you discover something surprising, fix a non-obvious bug, or learn a constraint that isn't derivable from the code, add it here before committing.

### Redbean

- **`-D key=value` is NOT for Lua globals.** It means "directory overlay" — passing `-D backend=gitea` errors with "not a directory: backend=gitea". Use SCRIPTARGS instead: `sh ./confusio.com -- backend=gitea`.
- **`Fetch(url, opts)` full signature**: `opts` is an optional table with keys `method`, `body`, and `headers` (a table of string pairs). Returns `status, headers, body` on success — but wrap in `pcall` because it throws on connection failure rather than returning an error status. Passing `nil` as `opts` is valid and makes an unauthenticated GET.
- **`EncodeBase64(str)`** is available and produces standard base64. Used by `make_fetch_opts` for Basic auth schemes.
- **`EncodeJson({})` produces `"{}"` (a JSON object), not `"[]"`.** Lua tables with no integer keys serialize as objects.
- **Redbean sends `SIGTERM` to its entire process group** on shutdown (not just to itself). Any test script that starts Redbean without `setsid` will be killed when confusio shuts down. Always use `setsid` to isolate server processes.

### Hurl

- **`jsonpath "$" == {}`** is not valid Hurl syntax — it errors with "invalid predicate value". Use `body == "{}"` for asserting an empty JSON object response.
- **`jsonpath "$.field" isString`** is the correct way to assert a field exists and is a string type.

### GitHub Actions composite actions

- **A local composite action (`uses: ./.github/actions/setup`) cannot contain `actions/checkout`.** The workflow runner needs to find the action file before checkout has run — chicken-and-egg. Always put `actions/checkout@v4` as an explicit first step in each job; the composite action handles everything after.

### Routing

- **Segment-based radix trie** (`route_add` / `route_match` in `.init.lua`): O(k) lookup where
  k = path depth. Static edges are preferred over param edges at each node, so `/repos/search`
  beats `/repos/{owner}` when both are registered. Captures from `{param}` segments are passed
  as positional arguments to the handler.
- **Startup-time handler resolution**: `setmetatable(backend_impl, { __index = defaults })` is
  built once after config loads. The backend is fixed for the program's lifetime — no per-request
  dispatch needed. Backend files set `backend_impl = { ... }` globally; `dofile` runs in global
  scope so locals from `.init.lua` are not visible to backend files.
- **`/zip/` prefix for dofile**: Redbean's `dofile` resolves paths on the real filesystem by
  default. Files inside the zip must be accessed as `dofile("/zip/backends/gitea.lua")`.

### Mock server design

- **Use Redbean itself as the mock server** — no Python/Node dependency, same binary already in the repo. Build `mock-<backend>.com` by copying `redbean.com` and zipping in a `.init.lua` handler. See `mock-gitea.com` target in `Makefile`.
- **Mock validation via Hurl**: run the same `.hurl` assertion file against both the mock and the real endpoint. If both pass the same structural assertions, the mock is compatible. See `make validate-mock`.
