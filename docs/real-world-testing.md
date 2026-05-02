# Real-World Testing Plan

## Why this exists

Unit tests run confusio against mock backends — hand-crafted Redbean servers that return
canned JSON.  Mock tests are fast and hermetic, but they can only verify that confusio
correctly translates the responses *we wrote into the mock*.  If a provider changes a field
name, drops a field, or returns a subtly different shape, the mocks keep passing and confusio
ships broken translations.

An opt-in integration harness exists for one backend (gitea.com) against a single endpoint
group, but it is skipped unless explicitly enabled.  Every other backend ships with zero
validation against a real instance.

This plan describes how real-world coverage could extend to all 24 backends without
making normal CI or local test runs contact live providers.  Until dedicated test
accounts and an explicit opt-in workflow exist, these checks remain documentation only.

## Goals

- Run confusio against real provider instances for every backend that claims any support
  (`y` or `~` in the compatibility matrix).
- Catch provider API changes that silently break translations.
- Confirm that the compatibility matrix entries are accurate — `y` means it actually works,
  not "it worked once in development".
- Do not run from normal CI, PR checks, or `make test`; live-provider checks must require
  an explicit opt-in environment variable or manual workflow.
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
| azuredevops | 80 | 79 |
| onedev | 21 | 72 |
| pagure | 40 | 76 |
| sourcehut | 19 | 68 |
| harness | 17 | 72 |
| gitblit | 16 | 74 |
| radicle | 11 | 73 |
| gerrit | 10 | 73 |
| phabricator | 9 | 72 |
| codecommit | 8 | 74 |
| launchpad | 8 | 73 |
| kallithea | 5 | 73 |
| rhodecode | 5 | 73 |
| sourceforge | 5 | 69 |
| tuleap | 12 | 79 |

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
| `gitea` | gitea.com | Free registration.  Already used by the opt-in `test-integration` harness. |
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
| `bitbucket` | App password: `Repositories: Read/Write`, `Issues: Read/Write`, `Pull requests: Read/Write`, `Pipelines: Read`, `Account: Read` |
| `azuredevops` | PAT scopes: `Code (Read & Write)`, `Work Items (Read & Write)`, `Project and Team (Read)`, `Build (Read)`, `Release (Read)`, `Advanced Security (Read)` |
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

`bitbucket_datacenter` is the Tier 2 exception: the container can boot without persistent
provider credentials, but Atlassian requires a Data Center license before repository and
webhook flows are usable.  If `REAL_WORLD_BITBUCKET_DC_LICENSE` is absent, the job should
skip with a classified `missing-secret` result instead of reporting endpoint regressions.

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

### Workflow file

`.github/workflows/real-world.yml`

Triggers:
- **Schedule**: `cron: '37 6 * * 1'` — Mondays at 06:37 UTC.  Off-minute scheduling avoids
  the thundering herd at the top of the hour when many scheduled workflows fire simultaneously.
- **`workflow_dispatch`**: manual trigger for debugging or on-demand runs.

```yaml
name: Real-world tests
on:
  schedule:
    - cron: '37 6 * * 1'
  workflow_dispatch:

concurrency:
  group: real-world
  cancel-in-progress: false   # let the in-progress run finish; queue the new one

permissions:
  contents: read
  issues: write               # needed to create/update the result issue
```

### Job structure

One job per backend, all running in parallel.  Each job is independent — a Tier 1 job does
not need to wait for fixture setup to complete globally because each job runs its own setup
step.  A final `report` job (with `needs` pointing at all backend jobs and `if: always()`)
collects results and posts the issue.

**Why one job per backend rather than one job for all backends:**

- GHA surfaces per-job pass/fail in the UI — it is immediately clear which backends are
  broken without reading logs.
- A hung or rate-limited backend does not block other backends.
- Docker service containers are job-scoped, so Tier 2 backends require a separate job anyway.

### Tier 1 job skeleton

```yaml
test-gitea:
  runs-on: ubuntu-latest
  if: ${{ secrets.REAL_WORLD_GITEA_TOKEN != '' }}
  steps:
    - uses: actions/checkout@v4
    - uses: ./.github/actions/setup
    - run: make build
    - name: Setup fixtures
      run: test/real-world/setup/gitea.sh
      env:
        CONFUSIO_TEST_TOKEN: ${{ secrets.REAL_WORLD_GITEA_TOKEN }}
        CONFUSIO_TEST_BASE_URL: https://gitea.com
        CONFUSIO_TEST_USER: confusio-test
    - name: Generate hurl
      run: python3 scripts/gen-realworld-hurl.py gitea
    - name: Run real-world tests
      run: test/test-realworld.sh gitea https://gitea.com
      env:
        CONFUSIO_TEST_TOKEN: ${{ secrets.REAL_WORLD_GITEA_TOKEN }}
        CONFUSIO_TEST_USER: confusio-test
    - name: Upload results
      if: always()
      uses: actions/upload-artifact@v4
      with:
        name: results-gitea
        path: results/gitea.json
```

The `if: ${{ secrets.REAL_WORLD_GITEA_TOKEN != '' }}` guard skips the job entirely when the
secret is absent (e.g. for backends whose accounts have not been created yet).  A skipped job
is not treated as a failure by the `report` job.

### Tier 2 job skeleton (Docker service container)

```yaml
test-gerrit:
  runs-on: ubuntu-latest
  services:
    gerrit:
      image: gerritcodereview/gerrit:latest
      ports:
        - 8080:8080
      options: >-
        --health-cmd "curl -sf http://localhost:8080"
        --health-interval 10s
        --health-timeout 5s
        --health-retries 18
  steps:
    - uses: actions/checkout@v4
    - uses: ./.github/actions/setup
    - run: make build
    - name: Bootstrap container
      run: test/real-world/docker/gerrit/bootstrap.sh
      # bootstrap.sh writes CONFUSIO_TEST_TOKEN and CONFUSIO_TEST_BASE_URL to $GITHUB_ENV
    - name: Generate hurl
      run: python3 scripts/gen-realworld-hurl.py gerrit
    - name: Run real-world tests
      run: test/test-realworld.sh gerrit "$CONFUSIO_TEST_BASE_URL"
    - name: Upload results
      if: always()
      uses: actions/upload-artifact@v4
      with:
        name: results-gerrit
        path: results/gerrit.json
```

No token secret is needed for Tier 2; the bootstrap script generates one at runtime and
writes it to `$GITHUB_ENV`.

### Report job

```yaml
report:
  needs:
    - test-gitea
    - test-forgejo
    # ... all 22 backend jobs ...
  if: always()
  runs-on: ubuntu-latest
  permissions:
    issues: write
  steps:
    - uses: actions/checkout@v4
    - uses: actions/download-artifact@v4
      with:
        pattern: results-*
        merge-multiple: true
        path: results/
    - name: Post results
      run: python3 scripts/report-realworld.py
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
```

Script: `scripts/report-realworld.py`

Steps:
1. Reads all `results/<backend>.json` hurl report files.
2. Classifies each failure by HTTP response code (see *Failure classification* below).
3. If all backends pass (or were skipped): exits without opening an issue.
4. If any backend has real failures: calls the GitHub Issues API to open a new issue (or
   append a comment to the already-open issue from the previous week if it describes the same
   set of failing backends — avoids duplicate issues for persistent outages).
5. If a prior-week failure issue is open and this run shows all-clear: closes the issue with
   a "resolved" comment.

### Issue format

**Title**: `[Real-world] Weekly run YYYY-MM-DD — N backends failing`

**Labels**: `real-world`, `automated` (both created on first use)

**Body**:

```markdown
## Real-world test results — YYYY-MM-DD

Run: [#RUN_ID](RUN_URL) | Triggered: scheduled

| Backend | Result | Failure count | Category |
|---------|--------|:-------------:|----------|
| gitea | ✅ pass | — | — |
| gitlab | ❌ fail | 3 | assertion |
| gerrit | ⚠️ skip | — | token not configured |
| bitbucket | ⚠️ warn | 1 | rate-limited |

### Failures

<details>
<summary>gitlab (3 failures)</summary>

| Endpoint | Expected | Actual |
|----------|---------|--------|
| `GET /repos/{owner}/{repo}` | HTTP 200, `$.visibility` isString | `$.visibility` is null |
| `POST /user/repos` | HTTP 201 | HTTP 422 |
| `GET /repos/{owner}/{repo}/topics` | HTTP 200 | HTTP 404 |

</details>
```

### Failure classification

The report script examines the HTTP status code of each failing entry to classify the root
cause.  This prevents token expiry or provider outages from being filed as confusio bugs.

| HTTP status | Classification | Label | Action |
|------------|---------------|-------|--------|
| `401` | Auth failure (token expired or revoked) | `auth-failure` | Open a separate issue reminding maintainer to rotate the token |
| `429` | Rate-limited | `rate-limited` | Log as warning, not failure; retry next week |
| `5xx` | Provider infrastructure | `provider-outage` | Log as warning; do not count as assertion failure |
| `200` with assertion failure | Translation regression | `regression` | Include in the failure issue |
| `404`/`422` where `2xx` expected | API change or confusio bug | `regression` | Include in the failure issue |

Only `regression`-classified failures trigger a new issue.  Auth and outage events are noted
in the issue body but do not count toward the failure total.

### Preserving history

Each weekly issue is a snapshot.  Do not update the body of a prior issue — open a new one.
This preserves a searchable audit trail: searching the repo issues for `[Real-world]` shows
the history of when specific backends started or stopped failing.

The one exception is persistent failures: if the same backend is failing with the same
endpoints for three consecutive weeks, the report script adds a comment to the current open
issue rather than opening a third duplicate.  This keeps the issue list from accumulating
open duplicates for a long-running outage.

## Phased rollout

### Phase 0 — Infrastructure (prerequisite)

Before any real-world tests can run, the following must exist:

- `test/real-world/setup/common.sh` — shared fixture helpers
- `scripts/gen-realworld-hurl.py` — hurl generator (reads catalog, CSV, OpenAPI spec)
- `scripts/report-realworld.py` — result collector and issue poster
- `test/test-realworld.sh` — per-backend test runner
- `.github/workflows/real-world.yml` — manual workflow skeleton (with all backend jobs
  requiring explicit opt-in until each backend is ready)
- `test/real-world/backends.json` — per-backend base URLs and fixture variable values
- `test/real-world/fixtures.md` — fixture inventory with `fixtures_version` front matter

Phase 0 is complete when the infrastructure can be run manually against gitea (the one
backend that already has an opt-in integration harness) and produces a well-formed JSON
result and a draft issue.

### Phase 1 — Gitea family (Tier 1)

Backends: `gitea`, `forgejo`, `codeberg`, `notabug`, `gogs`

These five backends share the same API family, so one setup script shape covers all of them.
The existing `test-integration` harness can validate gitea.com only when explicitly enabled;
Phase 1 extends that opt-in coverage to the full endpoint set and adds the remaining four
family members.

Codeberg webhook live coverage should run as its own backend job against the shared
codeberg.org account so routing and `X-Confusio-Source` remain `codeberg`.  Until that
opt-in job exists, Codeberg webhook parity is enforced by the mock-backed delivery tests.

**Exit criteria**: all five backends pass two consecutive weekly runs without manual
intervention.

### Phase 2 — GitLab and Bitbucket (Tier 1)

Backends: `gitlab`, `bitbucket`

Both have well-documented APIs, high uptime, and mature free tiers.  GitLab coverage should
exercise native webhook delivery for issues, notes, merge requests, CI/deployment events,
repository and group lifecycle, member changes, wiki/release/tag events, work items, and the
security alert and resource-token hooks where the account and project features allow them.
GitLab.com may not expose vulnerability or expiring-token hooks on every free-tier project;
those cases should be recorded as setup skips while mock-backed fixture delivery remains the
active signal for those source events.

Bitbucket coverage should exercise repository lifecycle, issues, commit comments, pull-request
comments/reviews/change requests, commit statuses, and `pipeline:span_created` OTLP spans.
Pipeline-span runs require Bitbucket Pipelines to be enabled on the fixture repository and a
minimal `bitbucket-pipelines.yml` so step/command/container/log spans are observable.

**Exit criteria**: both backends pass two consecutive weekly runs, including GitLab webhook
delivery assertions for the supported issue/MR/review/comment, CI/deployment,
repository/group/member, security alert, resource token, and work-item event families, plus
Bitbucket webhook delivery assertions for the supported repository, PR/comment/review, status,
and pipeline-span event families.

### Phase 3 — Remaining Tier 1 SaaS

Backends: `azuredevops`, `harness`, `gitbucket` (Tier 2 standing in for no public SaaS),
`sourcehut`, `pagure`, `launchpad`, `sourceforge`

These are less homogeneous — each needs its own setup script and potentially more overrides.
`sourcehut` write endpoints are deferred until a paid subscription is in place; read-only
endpoints can be enabled immediately.

Pagure live webhook coverage should configure a Pagure hook with a payload secret and drive
native deliveries for `issue.new`, `issue.edit`, `issue.status.change`, `issue.comment.added`,
`pull-request.new`, `pull-request.updated`, `pull-request.closed`, `git.receive`, and
`project.forked`.  The `git.receive` cases should cover a normal push, branch or tag creation,
and branch or tag deletion so the derived GitHub `push`, `create`, and `delete` events are all
asserted.  Each run should check both GitHub-emulation delivery and the confusio-normalized
shape, including `X-Pagure-Event`, `X-Confusio-Source: pagure`, and the preferred
`X-Pagure-Signature-256` verification path with the SHA-512 fallback kept in mock-backed
signature tests.

**Exit criteria**: all enabled backends pass two consecutive weekly runs.

### Phase 4 — Tier 2 Docker backends

Backends: `gerrit`, `gitblit`, `gitbucket` (Docker), `gogs` (Docker fallback),
`kallithea`, `onedev`, `rhodecode`, `tuleap`, `phabricator`, `bitbucket_datacenter`

Start with simpler bootstrap (gitbucket, onedev) then work toward the more complex ones
(kallithea, tuleap, bitbucket_datacenter).  Phabricator/Phorge is lowest priority given
Phabricator's archived upstream status.

Bitbucket Datacenter real-world coverage should create a project and repository inside the
ephemeral container, configure a webhook with an `X-Hub-Signature` secret, and drive native
events for `repo:refs_changed`, `pr:*`, `pr:reviewer:*`, `build:status_*`, and repository
lifecycle where the installed version exposes them.  If the evaluation license is missing or
expired, the run should be recorded as a license/setup skip; the mock-backed unit coverage
remains authoritative until a licensed container is reachable.

Gitblit real-world webhook coverage should run against the `gitblit/gitblit` container,
configure the post-receive hook with `X-Gitblit-Token`, and drive one branch update, one
branch creation, and one branch deletion against the fixture repository.  Those three
post-receive commands are the supported Gitblit webhook surface and should assert both
GitHub-shaped delivery headers and confusio-shaped normalized event bodies.

Tuleap real-world webhook coverage should run against the
`tuleap/tuleap-community-edition` container, configure a webhook secret, and drive
project creation, Git branch/tag update/create/delete, and tracker artifact
create/update payloads.  The live run should assert both GitHub-shaped delivery
headers and confusio-shaped normalized event bodies.

**Exit criteria**: all Docker backends produce a result (pass or classified failure) for two
consecutive weekly runs without the bootstrap script hanging or erroring.

### Phase summary

| Phase | Backends | Key dependency |
|-------|---------|---------------|
| 0 — Infrastructure | (none — tooling only) | Generator, runner, reporter written |
| 1 — Gitea family | gitea, forgejo, codeberg, notabug, gogs | Phase 0 done; accounts created |
| 2 — GitLab + Bitbucket | gitlab, bitbucket | Accounts created |
| 3 — Remaining Tier 1 | azuredevops, harness, sourcehut, pagure, launchpad, sourceforge | Accounts created; sourcehut subscription |
| 4 — Tier 2 Docker | gerrit, gitblit, gitbucket, kallithea, onedev, rhodecode, tuleap, phabricator, bitbucket_datacenter | Docker bootstrap scripts |

## Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Provider changes a field name or drops a field | High (over time) | Medium — test fails, surfaces as `regression` issue | Expected and desired — this is the point of the tests |
| Public SaaS instance goes offline (e.g. notabug) | Medium | Low — one backend skips | Tier 2 Docker fallback for gogs; skip guard on missing token |
| Token expires silently | Medium | Medium — test produces 401, looks like backend failure | 401 classification; rotation reminder issue; prefer non-expiring tokens |
| Rate limiting by provider | Low (weekly cadence, 1 req/s) | Low — job skips for the week | `429` classification; weekly cadence is conservative |
| Generator produces wrong assertions for `~` endpoints | Medium (initially) | Low — false positive failures | Override layer; conservative initial assertions; tighten iteratively |
| Docker image tag changes break bootstrap | Medium | Medium — Tier 2 job fails at bootstrap | Pin image tags in workflow; schedule quarterly tag updates |
| Bitbucket Datacenter evaluation license expires | High (30-day trial) | Medium — DC job skips or fails before provider assertions | Classify as `license-expired`, open a rotation reminder issue, and keep mock-backed webhook coverage as the active signal until a fresh license is installed |
| Generator or reporter script has a bug | Low | Low — entire run produces no results | Phase 0 validation against gitea before enabling other backends |
| GHA secrets sprawl (16+ secrets) | Low | Low — maintainability concern | Document all secrets in `test/real-world/SECRETS.md`; consistent naming |

## Open questions

1. **Forgejo/Codeberg job deduplication**: `forgejo` and `codeberg` both test against
   codeberg.org with the same token.  Should they run as one job (halving API calls) or
   separate jobs (clearer per-backend failure attribution)?  Separate jobs are cleaner but
   double the load on codeberg.org.

2. **Docker image pinning strategy**: pin to `image:latest` (always tests the newest
   version, which is the most realistic) or pin to a specific tag (reproducible but stale)?
   Suggestion: pin tags, update on a quarterly schedule via a separate maintenance PR.

3. **`~` annotation machine-readability**: should partial annotations be standardised as
   structured tags (e.g. `~no_release_assets`, `~read_only`) so the generator can auto-suppress
   the corresponding field assertions?  Or defer and manage via the override layer?

4. **Real-world tests on PR pushes**: should the workflow also trigger on PRs that modify a
   specific backend file (e.g. `backends/gitlab.lua`)?  This would catch regressions earlier
   but consumes more API quota and GHA minutes.

5. **Sourcehut write access**: the read-only free tier covers 19 endpoints.  Is a paid
   subscription worth it for the remaining write endpoints, or should sourcehut be limited to
   read-only indefinitely?

6. **`test/real-world/generated/` commit strategy**: should generated hurl files be committed
   to the repo (reviewable diffs when the generator changes) or always regenerated at CI time
   (no stale files)?  Committed generated files add noise to PRs that update the generator.
