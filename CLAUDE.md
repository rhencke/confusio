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

**Before any commit: run `make test-unit`.** `make test-integration` requires network and is acceptable to defer to CI.

## Project structure

```
.init.lua                    — Redbean app entry point (all application logic lives here)
Makefile                     — build, test, and download targets
.redbean-version             — pinned Redbean version (wget'd by make)
.hurl-version                — pinned Hurl version (curl'd by make)
test/
  test-unit.sh               — unit test harness (starts confusio + mock, runs hurl)
  test-integration.sh        — integration test harness (live gitea.com)
  test-mock-validate.sh      — validate mock response structure vs real instance
  default-root.hurl          — hurl assertions for GET / (no backend)
  default-emojis.hurl        — hurl assertions for GET /emojis (no backend)
  gitea-root.hurl            — hurl assertions for GET / (gitea backend)
  gitea-emojis.hurl          — hurl assertions for GET /emojis (gitea backend)
  mock-gitea.lua             — Redbean handler for the mock Gitea server
  lib.sh                     — shared helpers for test scripts
  validate/
    gitea-api-version.hurl   — hurl assertions for /api/v1/version (used by validate-mock)
.github/
  workflows/ci.yml           — CI: parallel test-unit and test-integration jobs
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

# Gitea backend via CLI args
sh ./confusio.com -p 8080 -- backend=gitea base_url=https://gitea.com

# Gitea backend via config file (.confusio.lua in working directory)
sh ./confusio.com -p 8080
# .confusio.lua: confusio = { backend="gitea", base_url="https://gitea.com" }
```

## Configuration system

Config has two mechanisms with **structural parity** — both use the same key names, enforced by a single `CONFIG_KEYS` table in `.init.lua`:

| Mechanism | Syntax |
|-----------|--------|
| SCRIPTARGS (highest precedence) | `sh ./confusio.com -- key=value key2=value2` |
| `.confusio.lua` config file | `confusio = { key = "value" }` |
| Defaults (lowest precedence) | hardcoded in `.init.lua` |

Config file is Lua (not TOML/JSON) so it can call functions — useful for secrets backends (e.g., `base_url = vault_read("secret/gitea-url")`).

**Adding a new config key**: add it to the `config` table defaults AND to `CONFIG_KEYS`. Both mechanisms pick it up automatically.

## GitHub API reference

The vendored spec at `vendor/github-rest-api-description/api.github.com.yaml` is the source of truth for what endpoints confusio should expose and what their request/response shapes are.

When implementing a new endpoint, check the spec for:
- Path and method
- Required/optional query params and request body fields
- Response status codes and body schema

## Adding a new endpoint

1. Check `vendor/github-rest-api-description/api.github.com.yaml` for the endpoint's contract.
2. Add a `handle_<path>_<backend>()` function in `.init.lua`.
3. Route to it in `OnHttpRequest()`.
4. Add a hurl assertion file in `test/` and wire it into `test/test-unit.sh` (mock) and `test/test-integration.sh` (live).
5. Update the compatibility matrix in `README.md`.

## Adding a new backend

1. Add the backend name to config validation in `.init.lua` (or leave open — currently no validation).
2. Implement `handle_<endpoint>_<newbackend>()` functions.
3. Add mock server as `test/mock-<newbackend>.lua` and build it in the `Makefile` (copy pattern from `mock-gitea.com`).
4. Add a `test/test-mock-validate.sh`-equivalent for the new backend if its spec differs meaningfully.

## Redbean API notes

- `GetMethod()`, `GetPath()`, `GetHeader()` — inspect the incoming request
- `SetStatus(code, reason)`, `SetHeader(name, value)`, `Write(body)` — build the response
- `Fetch(url)` — outgoing HTTP (returns `status, headers, body`; use `pcall` for error handling)
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

Every commit must pass `make test-unit`. No exceptions.

## Lessons learned

Hard-won insights from building this project. **Keep this section current**: whenever you discover something surprising, fix a non-obvious bug, or learn a constraint that isn't derivable from the code, add it here before committing.

### Redbean

- **`-D key=value` is NOT for Lua globals.** It means "directory overlay" — passing `-D backend=gitea` errors with "not a directory: backend=gitea". Use SCRIPTARGS instead: `sh ./confusio.com -- backend=gitea`.
- **`Fetch(url)` return values**: returns `status, headers, body` — but wrap in `pcall` because it throws on connection failure rather than returning an error status.
- **`EncodeJson({})` produces `"{}"` (a JSON object), not `"[]"`.** Lua tables with no integer keys serialize as objects.
- **Redbean sends `SIGTERM` to its entire process group** on shutdown (not just to itself). Any test script that starts Redbean without `setsid` will be killed when confusio shuts down. Always use `setsid` to isolate server processes.

### Hurl

- **`jsonpath "$" == {}`** is not valid Hurl syntax — it errors with "invalid predicate value". Use `body == "{}"` for asserting an empty JSON object response.
- **`jsonpath "$.field" isString`** is the correct way to assert a field exists and is a string type.

### GitHub Actions composite actions

- **A local composite action (`uses: ./.github/actions/setup`) cannot contain `actions/checkout`.** The workflow runner needs to find the action file before checkout has run — chicken-and-egg. Always put `actions/checkout@v4` as an explicit first step in each job; the composite action handles everything after.

### Handler architecture

- **The backend is fixed for the program's lifetime** — config is loaded once at startup and never changes. Resolve handler functions at startup, not per-request. Use `setmetatable(backend_impls[config.backend] or {}, { __index = defaults })` so backend-specific handlers override the defaults, and missing entries fall through automatically. This avoids per-request dispatch and leverages Lua's native prototype-style inheritance.

### Mock server design

- **Use Redbean itself as the mock server** — no Python/Node dependency, same binary already in the repo. Build `mock-<backend>.com` by copying `redbean.com` and zipping in a `.init.lua` handler. See `mock-gitea.com` target in `Makefile`.
- **Mock validation via Hurl**: run the same `.hurl` assertion file against both the mock and the real endpoint. If both pass the same structural assertions, the mock is compatible. See `make validate-mock`.
