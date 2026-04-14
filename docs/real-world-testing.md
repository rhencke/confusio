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

*(To be detailed in the next section of this plan.)*

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
