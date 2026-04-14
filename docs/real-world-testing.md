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

*(To be detailed in the next section of this plan.)*

## Test harness design

*(To be detailed in the next section of this plan.)*

## Weekly GHA workflow and issue reporting

*(To be detailed in the next section of this plan.)*

## Phased rollout

*(To be detailed in the next section of this plan.)*

## Open questions

*(To be collected as each section is written.)*
