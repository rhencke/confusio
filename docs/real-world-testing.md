# Real-World Testing Plan

## Why this exists

Unit tests run confusio against mock backends — hand-crafted Redbean servers that return
canned JSON.  Mock tests are fast and hermetic, but they can only verify that confusio
correctly translates the responses *we wrote into the mock*.  If a provider changes a field
name, drops a field, or returns a subtly different shape, the mocks keep passing and confusio
ships broken translations.

Integration tests currently cover one backend (gitea.com) against a single endpoint group.
Every other backend ships with zero validation against a real instance.

This plan describes how to extend real-world coverage to all 24 backends on a recurring
schedule, surface regressions automatically, and keep the compatibility matrix honest.

## Goals

- Run confusio against real provider instances for every backend that claims any support
  (`y` or `~` in the compatibility matrix).
- Catch provider API changes that silently break translations.
- Confirm that the compatibility matrix entries are accurate — `y` means it actually works,
  not "it worked once in development".
- Run automatically on a weekly cadence via GitHub Actions.
- Post a GitHub issue summarising any failures so regressions are visible without watching
  CI logs.

## Non-goals

- **Performance or load testing.** Rate limits on public instances make this impractical and
  unkind.  Correctness only.
- **Testing confusio's internal logic.** Unit tests own that.  Real-world tests trust the
  mock and unit layers and focus only on "does the real provider return what we expect?".
- **Full endpoint coverage for every backend.** We test the endpoints each backend actually
  supports (`y`/`~`), not the full 451-endpoint catalog.  Stub-only endpoints (`n`) are
  already verified by unit tests.
- **Testing self-hosted configurations we cannot reproduce.** Authentication schemes,
  enterprise features, and LDAP integrations are out of scope.

## Scope

### What we test

For each backend, we test every endpoint row in `site/compatibility.csv` where the support
value is `y` or starts with `~`.  Concretely:

| Backend | `y` endpoints | `~` (partial) |
|---------|:-------------:|:-------------:|
| gitea | 141 | 72 |
| forgejo | 140 | 72 |
| codeberg | 140 | 72 |
| gogs | 134 | 66 |
| notabug | 122 | 65 |
| gitlab | 96 | 68 |
| gitbucket | 93 | 66 |
| bitbucket | 55 | 71 |
| bitbucket_datacenter | 39 | 78 |
| azuredevops | 31 | 67 |
| onedev | 21 | 72 |
| pagure | 24 | 73 |
| sourcehut | 19 | 68 |
| harness | 17 | 72 |
| gitblit | 13 | 73 |
| radicle | 11 | 73 |
| gerrit | 10 | 73 |
| phabricator | 9 | 72 |
| codecommit | 8 | 74 |
| launchpad | 8 | 73 |
| kallithea | 5 | 73 |
| rhodecode | 5 | 73 |
| sourceforge | 5 | 69 |
| tuleap | 5 | 79 |

### What a "passing" test means

For `y` endpoints: confusio returns HTTP 200 with a structurally valid response (correct
top-level fields and types per the GitHub API spec).

For `~` endpoints: confusio returns a non-5xx status and the response conforms to whatever
partial contract is documented.  We do not assert on fields that the partial annotation
explicitly exempts.

## Backend inventory

Each backend is assigned to a tier that determines how we provision the test instance.

### Tier 1 — SaaS with free accounts

These backends have a well-known public SaaS instance.  We create a dedicated test account
once, store the token as a GitHub Actions secret, and point confusio at the public URL.

| Backend | Public instance | Account notes |
|---------|----------------|---------------|
| `gitea` | gitea.com | Free registration.  Already used by `test-integration`. |
| `forgejo` | codeberg.org | codeberg.org runs Forgejo; same account as `codeberg`. |
| `codeberg` | codeberg.org | Free registration; shares instance with `forgejo`. |
| `gogs` | *(see notabug)* | No dedicated public gogs.io instance.  Use notabug. |
| `notabug` | notabug.org | Runs Gogs.  Free registration; uptime has been spotty — see Tier 3 fallback. |
| `gitlab` | gitlab.com | Free tier; GitLab account. |
| `gitbucket` | *(see Tier 2)* | No public GitBucket SaaS. |
| `bitbucket` | bitbucket.org | Free; Atlassian account required. |
| `azuredevops` | dev.azure.com | Free tier; Microsoft account required; free for public projects. |
| `harness` | app.harness.io | Free Developer plan. |
| `sourcehut` | sr.ht | Paid subscription required for API write access; read-only free. |
| `pagure` | pagure.io | Free; Fedora Account System (FAS) required. |
| `launchpad` | launchpad.net | Free; Ubuntu One account. |
| `sourceforge` | sourceforge.net | Free registration. |

### Tier 2 — Self-hosted via Docker (GHA service containers)

These backends have no public SaaS we can use, or the public instance is too unreliable.
We run the official Docker image as a GHA service container and test against it.  The
container is ephemeral — it starts fresh for every weekly run, so teardown is just "job
ends".

| Backend | Docker image | Notes |
|---------|-------------|-------|
| `bitbucket_datacenter` | `atlassian/bitbucket` | Data Center evaluation license (30-day trial, renewable).  Requires license key secret. |
| `gerrit` | `gerritcodereview/gerrit` | No license needed; open source. |
| `gitblit` | `gitblit/gitblit` | No license needed; open source. |
| `gitbucket` | `gitbucket/gitbucket` | No license needed; open source. |
| `gogs` | `gogs/gogs` | Fallback if notabug.org is unreachable. |
| `kallithea` | `kallithea/kallithea` | Community edition; no license needed. |
| `onedev` | `1dev/server` | Open source; no license needed. |
| `phabricator` | `phorge/phorge` | Phabricator upstream archived 2022; Phorge is the active fork. |
| `rhodecode` | `rhodecode/rhodecode-community` | Community edition; no license needed. |
| `tuleap` | `tuleap/tuleap-community-edition` | Community edition; no license needed. |

### Tier 3 — Specialized / deferred

These backends require setup that does not fit the SaaS or Docker model, or whose testing
value is marginal given their support level.

| Backend | Why deferred | Path forward |
|---------|-------------|--------------|
| `codecommit` | AWS CodeCommit entered maintenance mode in February 2024 and is no longer accepting new users as of July 2024.  Only 8 `y` endpoints. | Keep unit tests.  Remove or archive backend once AWS formally retires the service. |
| `radicle` | Peer-to-peer; no central server.  Requires a local Radicle node and a seed server; not suitable for standard GHA runners. | Investigate self-hosted runner with persistent Radicle node. |

## Account and credential management

### Account creation (Tier 1 — SaaS)

Account creation is a one-time manual task per provider.  It cannot be automated because
most providers require email verification, CAPTCHA, or human review.

**Naming convention:** use `confusio-test` as the username everywhere it is available.
Where that name is taken, use `confusio-ci`.  Consistency makes it obvious which account
belongs to this project and simplifies token revocation if needed.

**Email:** use a single dedicated address (e.g. a `+confusio-test` alias of the project
maintainer's address) so that verification emails and provider notifications go to one place.

The table below documents the one-time steps for each Tier 1 backend.

| Backend | Registration URL | Special requirements |
|---------|-----------------|---------------------|
| `gitea` | https://gitea.com/user/sign_up | None. Free. |
| `forgejo` / `codeberg` | https://codeberg.org/user/sign_up | Single account covers both backends. |
| `notabug` / `gogs` | https://notabug.org/user/sign_up | Single account covers both backends.  If notabug is unreachable, fall back to Tier 2 Docker for `gogs`. |
| `gitlab` | https://gitlab.com/users/sign_up | Free tier sufficient. |
| `bitbucket` | https://bitbucket.org/account/signup/ | Atlassian account.  Enable app passwords — Bitbucket does not support PATs for the Cloud API. |
| `azuredevops` | https://dev.azure.com (sign in with Microsoft account) | Create one organisation named `confusio-test`.  Free tier (5 parallel jobs) is sufficient. |
| `harness` | https://app.harness.io/auth/#/signup | Free Developer plan. |
| `sourcehut` | https://sr.ht (paid subscription) | Read-only endpoints work unauthenticated; write endpoints require a paid account.  Defer write endpoints until a subscription is in place. |
| `pagure` | https://id.fedoraproject.org/login/ | Fedora Account System required. |
| `launchpad` | https://launchpad.net/+login | Ubuntu One account. |
| `sourceforge` | https://sourceforge.net/user/registration | None. Free. |

### Authentication mechanisms

Different providers use different schemes; confusio passes the caller's `Authorization` header
straight through.  The test runner supplies the right format for each backend.

| Backend | Mechanism | Header / format |
|---------|-----------|----------------|
| `gitea`, `forgejo`, `codeberg`, `notabug`, `gogs` | API token (PAT) | `Authorization: token <TOKEN>` |
| `gitlab` | Personal access token | `Authorization: Bearer <TOKEN>` |
| `bitbucket` | App password | `Authorization: Basic base64(user:app_password)` |
| `azuredevops` | Personal access token | `Authorization: Basic base64(:TOKEN)` (empty username, PAT as password) |
| `harness` | PAT | `Authorization: Bearer <TOKEN>` |
| `sourcehut` | OAuth2 PAT | `Authorization: token <TOKEN>` |
| `pagure` | API key | `Authorization: token <TOKEN>` |
| `launchpad` | OAuth 1.0a | Handled by confusio's passthrough; requires pre-obtained token |
| `sourceforge` | Bearer token | `Authorization: Bearer <TOKEN>` |
| All Tier 2 Docker | Admin PAT generated at boot | Same scheme as the corresponding root family (e.g. `token <TOKEN>` for gitea-family) |

### Token scopes (minimum required)

Request the narrowest scopes that cover all `y`/`~` endpoints.  The table below gives the
minimum set; request no more than this.

| Backend | Minimum scopes |
|---------|---------------|
| `gitea` / `forgejo` / family | `read:repository`, `read:user`, `read:organization`, `read:issue`, `write:repository` (for mutation endpoints), `write:issue` |
| `gitlab` | `read_api` for read-only; `api` for mutation endpoints |
| `bitbucket` | App password: `Repositories: Read/Write`, `Issues: Read/Write`, `Pull requests: Read/Write`, `Account: Read` |
| `azuredevops` | PAT scopes: `Code (Read & Write)`, `Work Items (Read & Write)`, `Project and Team (Read)` |
| `harness` | Account-level PAT with `core_project_viewer` + `code_repo_viewer` minimum |
| `sourcehut` | `REPOSITORIES`, `PROFILE` (read-only until paid account) |
| `pagure` | Default token scopes: `pull_request`, `issue_comment`, `create_branch` |
| `launchpad` | OAuth token: `WRITE_PUBLIC` (covers most endpoints) |
| `sourceforge` | Default token scopes |

### GitHub Actions secrets

Each Tier 1 token is stored as a repository secret.  Naming convention:
`REAL_WORLD_<BACKEND>_TOKEN` (all caps, underscores).  Additional secrets where needed:

| Secret name | Used by | Notes |
|-------------|---------|-------|
| `REAL_WORLD_GITEA_TOKEN` | `gitea` | — |
| `REAL_WORLD_FORGEJO_TOKEN` | `forgejo`, `codeberg` | Same account on codeberg.org |
| `REAL_WORLD_CODEBERG_TOKEN` | `codeberg` | Same value as `FORGEJO` if sharing account |
| `REAL_WORLD_NOTABUG_TOKEN` | `notabug`, `gogs` (Tier 1) | — |
| `REAL_WORLD_GITLAB_TOKEN` | `gitlab` | — |
| `REAL_WORLD_BITBUCKET_TOKEN` | `bitbucket` | App password, not a PAT |
| `REAL_WORLD_BITBUCKET_USER` | `bitbucket` | Username for Basic auth |
| `REAL_WORLD_AZUREDEVOPS_TOKEN` | `azuredevops` | PAT |
| `REAL_WORLD_AZUREDEVOPS_ORG` | `azuredevops` | Organisation name (e.g. `confusio-test`) |
| `REAL_WORLD_HARNESS_TOKEN` | `harness` | PAT |
| `REAL_WORLD_HARNESS_ACCOUNT` | `harness` | Harness account ID |
| `REAL_WORLD_SOURCEHUT_TOKEN` | `sourcehut` | OAuth PAT |
| `REAL_WORLD_PAGURE_TOKEN` | `pagure` | API key |
| `REAL_WORLD_LAUNCHPAD_TOKEN` | `launchpad` | OAuth access token |
| `REAL_WORLD_LAUNCHPAD_TOKEN_SECRET` | `launchpad` | OAuth token secret (OAuth 1.0a pair) |
| `REAL_WORLD_SOURCEFORGE_TOKEN` | `sourceforge` | Bearer token |
| `REAL_WORLD_BITBUCKET_DC_LICENSE` | `bitbucket_datacenter` | Evaluation license key for the Docker container |

Tier 2 Docker backends (gerrit, gitblit, gitbucket, gogs, kallithea, onedev, phabricator,
rhodecode, tuleap) generate ephemeral admin credentials at container boot; no GHA secrets
are needed for them.  The bootstrap credentials are written into the test job's environment
by the setup script (see *Setup and teardown automation*).

### Token lifetime and rotation

- **Prefer non-expiring tokens** where the provider allows.  Expiring tokens fail silently
  on the day they expire, producing failures that look like endpoint regressions.
- **Where expiry is mandatory** (e.g. Azure DevOps PATs max out at 1 year): create a
  reminder issue on the repo 30 days before expiry.  The weekly workflow should detect
  `401` responses and open a labelled issue distinct from endpoint-regression issues.
- **Rotation procedure**: revoke the old token, generate a new one with the same scopes,
  update the GHA secret.  No code changes needed — the secret name stays the same.
- **Principle of least privilege**: the test account should have no admin rights on any
  organisation outside the dedicated `confusio-test` org/group.  If a token is compromised
  it can at worst write to test repos.

## Setup and teardown automation

### Design principles

- **Idempotent everywhere.** The setup step runs at the top of every weekly job.  It must
  be safe to run repeatedly: check whether a fixture already exists before creating it, never
  fail if a resource is already in the correct state.
- **Tier 1 fixtures are persistent.** SaaS test fixtures (repos, orgs, issues) are created
  once and left in place across runs.  The weekly job only recreates them if they are missing.
  This keeps run times short and avoids hammering provider rate limits.
- **Tier 2 fixtures are ephemeral.** Docker containers start fresh every run; the bootstrap
  script creates everything from scratch.  Teardown is free — the job just exits.
- **Mutation tests clean up after themselves (best effort).** Endpoints that create, modify,
  or delete resources operate on uniquely-named ephemeral sub-resources, not on the standing
  fixtures.  Cleanup is attempted after each mutation test; failure to clean up is logged
  but does not fail the overall test job.
- **No Terraform.** Terraform would add state-file management overhead and not all providers
  have first-class Terraform providers.  Shell + curl is sufficient, consistent with the
  project's existing toolchain, and easy to read at a glance.

### Standard fixture inventory

Every backend that supports a resource type should have the following fixtures present before
tests run.  Setup scripts create exactly this set, no more.

**User / account**
- The `confusio-test` user (the test account itself).

**Organisation / group**
- `confusio-test` org (or group, project, namespace — whatever the provider calls it).
  Created under the test account.

**Repositories**
- `confusio-test/fixtures-main` — the primary test repo.  Required contents:
  - At least one file per language (Go, Python, Markdown) — needed for language-stats
    endpoint assertions.
  - A `LICENSE` file (MIT) — needed for the license endpoint.
  - Topics/labels: `["testing", "confusio"]` — needed for topic endpoints.
  - Branches: `main` (default), `develop`, `feature/test-branch`.
  - 10+ commits distributed across branches.
  - Two annotated tags: `v1.0.0`, `v1.1.0`.
  - One release: `v1.0.0` with a release body.
  - Two open issues, one closed issue.  Each has at least one comment.
  - One open pull request: `develop` → `main`.
  - One closed/merged pull request.
- `confusio-test/fixtures-fork-target` — a minimal repo (single commit, no branches beyond
  main).  `fixtures-main` should be a fork of this repo on providers that support forks.

**Fixture versioning**

The fixture set is described in `test/real-world/fixtures.md` (machine-readable front matter +
human narrative).  If a fixture needs to change (e.g. an endpoint test requires a new field),
bump the `fixtures_version` field in that file.  Setup scripts check the version tag on
the live fixture and re-create it if the version is stale.

### Tier 1 setup scripts

Location: `test/real-world/setup/<backend>.sh`

Each script:
1. Sources `test/real-world/setup/common.sh` for shared helpers (`fixture_repo_exists`,
   `create_repo`, `create_issue`, etc. — thin wrappers around `curl`).
2. Accepts credentials and base URL via environment variables
   (`CONFUSIO_TEST_TOKEN`, `CONFUSIO_TEST_USER`, `CONFUSIO_TEST_BASE_URL`).
3. Creates missing fixtures in dependency order (org → repos → branches →
   issues → PRs → releases).
4. Exits non-zero if any creation step fails after retries.

A lightweight driver script `test/real-world/setup/run-all.sh` iterates all per-backend
scripts and is called by the weekly GHA job.

Example shape of a single-backend setup script:

```sh
#!/usr/bin/env bash
# setup/gitea.sh — idempotent fixture setup for gitea.com
set -euo pipefail
source "$(dirname "$0")/common.sh"

BASE="${CONFUSIO_TEST_BASE_URL:-https://gitea.com}"
ORG="confusio-test"
MAIN_REPO="fixtures-main"
FORK_TARGET="fixtures-fork-target"

ensure_org "$BASE" "$ORG"
ensure_repo "$BASE" "$ORG" "$MAIN_REPO" --has-issues --has-projects
ensure_repo "$BASE" "$ORG" "$FORK_TARGET"
ensure_branches "$BASE" "$ORG/$MAIN_REPO" develop "feature/test-branch"
ensure_tags "$BASE" "$ORG/$MAIN_REPO" v1.0.0 v1.1.0
ensure_release "$BASE" "$ORG/$MAIN_REPO" v1.0.0
ensure_issues "$BASE" "$ORG/$MAIN_REPO" 2   # at least 2 open issues
ensure_pull_request "$BASE" "$ORG/$MAIN_REPO" develop main
```

### Tier 2 bootstrap scripts

Location: `test/real-world/docker/<backend>/bootstrap.sh`

Each script runs inside the GHA job after the service container passes its health check.
Steps:

1. **Wait for readiness** — poll the container's health or status endpoint until it returns
   a 200 (with exponential back-off, 60 s timeout).
2. **Create admin user** — use the provider's initial-setup API or CLI.  The admin
   credentials are written to `$GITHUB_ENV` so subsequent steps in the job can read them.
3. **Generate token** — call the provider's token-creation API as the admin user; export as
   `CONFUSIO_TEST_TOKEN`.
4. **Create fixtures** — call the same `common.sh` helpers used by Tier 1 scripts.  The
   `BASE_URL` points to `http://localhost:<port>`.

Example for gitbucket:

```sh
#!/usr/bin/env bash
# docker/gitbucket/bootstrap.sh
set -euo pipefail
source "$(dirname "$0")/../../setup/common.sh"

BASE="http://localhost:8080"
wait_for_health "$BASE/signin"          # polls until 200
admin_setup "$BASE" root password123    # first-time wizard via API
TOKEN=$(create_token "$BASE" root password123 confusio-ci-token)
echo "CONFUSIO_TEST_TOKEN=$TOKEN" >> "$GITHUB_ENV"
echo "CONFUSIO_TEST_BASE_URL=$BASE" >> "$GITHUB_ENV"
echo "CONFUSIO_TEST_USER=root" >> "$GITHUB_ENV"

source "$(dirname "$0")/../../setup/gitbucket.sh"
```

### Mutation test isolation

Endpoints that mutate state (create, update, or delete a resource) must not operate on the
standing fixtures, which are shared across all test runs.  The isolation rule:

> **Every mutation test creates its own uniquely-named resource, asserts on it, then
> deletes it.**  The resource name includes a short timestamp or run ID to avoid collisions
> between concurrent runs.

Implementation in hurl (example for `POST /user/repos`):

```hurl
# Create a temp repo for this test run
POST http://{{host}}/user/repos
Authorization: token {{token}}
{
  "name": "confusio-tmp-{{run_id}}",
  "private": false
}
HTTP 201
[Captures]
tmp_repo_name: jsonpath "$.name"

# ... assertions ...

# Cleanup (best effort — failure here does not abort the suite)
DELETE http://{{host}}/repos/{{user}}/{{tmp_repo_name}}
Authorization: token {{token}}
HTTP *
```

The `run_id` variable is set once per job invocation (e.g. the GHA run number) and injected
via `--variable run_id=${{ github.run_id }}`.

### Rate limit handling

Real-world tests must be polite.  Guidelines:

- Run at most one request per second against any Tier 1 SaaS instance.  Hurl's
  `--delay` flag sets a global inter-request delay; set it to `1000` ms for all real-world
  runs.
- Abort the job (not just the backend) if a `429 Too Many Requests` is received.
  Do not retry — flag it as a rate-limit event in the issue report and skip the backend for
  this run.
- Tier 2 Docker containers have no rate limits; delay is not needed there.

### File layout

```
test/real-world/
  fixtures.md                    — fixture inventory and version (machine-readable front matter)
  setup/
    common.sh                    — shared helpers: wait_for_health, ensure_repo, ensure_org, …
    run-all.sh                   — driver: iterates per-backend scripts
    gitea.sh
    forgejo.sh
    codeberg.sh
    notabug.sh
    gitlab.sh
    bitbucket.sh
    azuredevops.sh
    harness.sh
    sourcehut.sh
    pagure.sh
    launchpad.sh
    sourceforge.sh
  docker/
    gerrit/
      bootstrap.sh
    gitblit/
      bootstrap.sh
    gitbucket/
      bootstrap.sh
    gogs/
      bootstrap.sh
    kallithea/
      bootstrap.sh
    onedev/
      bootstrap.sh
    phabricator/
      bootstrap.sh
    rhodecode/
      bootstrap.sh
    tuleap/
      bootstrap.sh
    bitbucket_datacenter/
      bootstrap.sh
```

## Test harness design

### Approach: generator-primary with per-backend overrides

Two approaches were considered:

**Option A — Hurl file per provider** (extend the existing unit-test pattern):  
Write `test/real-world/<backend>-<group>.hurl` files by hand, one per backend per endpoint
group, using real fixture variables instead of mock-hardcoded values.

**Option B — Metadata-driven generator** (generate hurl files from the catalog + OpenAPI spec):  
A script reads the endpoint catalog, the compatibility CSV, and the vendored GitHub OpenAPI
spec (`vendor/github-rest-api-description/api.github.com.yaml`) and emits one hurl file per
backend containing structural assertions for every `y`/`~` endpoint.

**Decision: Option B (generator), with a per-backend manual override layer.**

Rationale: 24 backends × ~100–140 supported endpoints each is on the order of 2,400–3,400
request/assertion blocks.  Hand-maintaining that volume is not viable — every new endpoint
added to the catalog would require touching up to 24 files.  The generator pattern already
exists in this project (`scripts/gen-matrix.py`), and the OpenAPI spec is already vendored.

A pure generator covers the common structural shape; the override layer handles the small
number of endpoints where the generated assertions are wrong or insufficient for a specific
backend.

### What the generator produces

Script: `scripts/gen-realworld-hurl.py`

Inputs:
- `make dump-endpoints` JSON (catalog: verb, path, group, handler)
- `site/compatibility.csv` (which endpoints each backend supports)
- `vendor/github-rest-api-description/api.github.com.yaml` (response schemas)
- `test/real-world/backends.json` (per-backend config: base URL, fixture variable values)

Output: one hurl file per backend at `test/real-world/generated/<backend>.hurl`

For each (backend, endpoint) pair where the CSV value is `y` or starts with `~`, the
generator emits:

```hurl
# <VERB> <path>
<VERB> http://{{host}}<path-with-vars>
Authorization: <scheme> {{token}}

HTTP <expected-status>
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
<field-assertions from OpenAPI schema>
```

**Assertion strategy — structural, not value-based.**  Real-world tests cannot assert exact
values (we don't control the content of real repos).  Every assertion is one of:
- `isInteger`, `isFloat`, `isString`, `isBoolean`, `isCollection`, `isNotEmpty`
- `exists` / `not exists`
- Range checks for known-bounded fields (e.g. HTTP status integers)

Example of generated output for `GET /repos/{owner}/{repo}` (gitea-family):

```hurl
# GET /repos/{owner}/{repo}
GET http://{{host}}/repos/{{owner}}/{{repo}}
Authorization: token {{token}}

HTTP 200
[Asserts]
header "Content-Type" == "application/json; charset=utf-8"
jsonpath "$.id" isInteger
jsonpath "$.name" isString
jsonpath "$.full_name" isString
jsonpath "$.owner.login" isString
jsonpath "$.private" isBoolean
jsonpath "$.html_url" isString
jsonpath "$.default_branch" isString
jsonpath "$.visibility" isString
```

**Handling `~` (partial) entries.**  The partial annotation may carry an explanation
(e.g. `~no release assets`).  Fields that the annotation exempts are omitted from the
generated assertions.  Initially the generator treats all `~` entries identically to `y`
(assert all required fields from the schema) and relies on the override layer to suppress
assertions that don't apply.  A future improvement is to make partial annotations
machine-parseable so suppressions are automatic.

**Mutation endpoints** (`POST`, `PATCH`, `DELETE`, `PUT`).  The generator emits a create,
assert, and cleanup triple using the mutation isolation pattern described in *Setup and
teardown automation* (unique `{{run_id}}`-suffixed resource names, best-effort DELETE).

### Per-backend variable conventions

The hurl runner injects these variables for every backend:

| Variable | Value | Example |
|----------|-------|---------|
| `host` | confusio listen address | `localhost:18300` |
| `token` | auth token in the backend's expected format | `abcdef123...` |
| `owner` | fixture user or org name | `confusio-test` |
| `repo` | primary fixture repo | `fixtures-main` |
| `fork_repo` | fork-target fixture repo | `fixtures-fork-target` |
| `run_id` | GHA run number (for unique mutation names) | `12345678` |
| `backend` | backend identifier | `gitea` |

For backends that require extra variables (e.g. `azuredevops` needs `org`), the generator
reads `test/real-world/backends.json` for the additional bindings.

### Per-backend override layer

Location: `test/real-world/overrides/<backend>/<group>.hurl`

When the runner finds an override file for a (backend, group) pair it uses that file
*instead of* the generated snippet for that group.  This covers cases like:

- Paginated endpoints where the `Link` header must be asserted (generator omits header
  assertions by default).
- Endpoints where a backend returns a different HTTP status for a supported operation
  (e.g. 201 vs 200 on create).
- Endpoints that the generator cannot express correctly from the OpenAPI schema alone.

Override files use the same variable conventions as generated files.  They are checked in
and reviewed like any other source file.  The expectation is that overrides are rare — if an
override is needed for more than a handful of endpoints on a backend, that suggests a
systematic translation difference that belongs in the backend implementation, not the test.

### Test runner

Script: `test/test-realworld.sh`

Analogous in shape to `test/test-unit.sh` but iterates real instances instead of mocks.
For each backend:

1. Merge the generated hurl file with any override snippets into a temporary combined file.
2. Start confusio pointed at the real backend URL: `sh ./confusio.com -p $PORT -- $BACKEND $BASE_URL`
3. Run hurl with:
   ```sh
   ./hurl --delay 1000 \
          --retry 3 --retry-interval 2000 \
          --variable host=localhost:$PORT \
          --variable token="$TOKEN" \
          --variable owner="$OWNER" \
          --variable repo="$REPO" \
          --variable fork_repo="$FORK_REPO" \
          --variable run_id="$RUN_ID" \
          --report-json "$RESULTS_DIR/$BACKEND.json" \
          "$TMPDIR/$BACKEND.hurl"
   ```
4. Stop confusio.
5. Append the per-backend JSON result to a running summary.

The `--report-json` output is a machine-readable hurl JSON report.  The GHA workflow reads
this to build the issue body (see *Weekly GHA workflow*).

Backends run sequentially (not in parallel) to respect rate limits and avoid port conflicts.

### Difference from existing unit/mock hurl files

| Dimension | Unit tests (`test/<backend>-<group>.hurl`) | Real-world tests |
|-----------|-------------------------------------------|-----------------|
| Target | confusio + mock backend | confusio + real instance |
| Assertions | Value-exact (`== "hello-world"`) | Structural (`isString`) |
| Fixture data | Hardcoded in mock | Live data from real account |
| File authoring | Hand-written | Generator + optional overrides |
| Auth header | None (mock ignores it) | Real token injected per-backend |
| Run cadence | Every CI push | Weekly |
| Failure meaning | confusio translation bug | Provider API change or real bug |

The two test layers are complementary: unit tests catch confusio regressions quickly on every
push; real-world tests catch provider-side drift weekly.

## Weekly GHA workflow and issue reporting

*(To be detailed in the next section of this plan.)*

## Phased rollout

*(To be detailed in the next section of this plan.)*

## Open questions

*(To be collected as each section is written.)*
