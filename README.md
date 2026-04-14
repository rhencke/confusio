# confusio

*confusio linguarum* — the confusion of tongues.

A REST API shim that implements a subset of GitHub's API, translating requests to other git hosting providers under the hood.

## What it is

GitHub's API is the lingua franca of git hosting tools. Other providers speak their own dialects. Confusio stands in the middle, translating.

Built with [Redbean](https://redbean.dev) — a single-file web server containing a Lua interpreter, distributed as a self-extracting zip.

## Prerequisites

- `make`, `zip`, `curl` — needed to build and run tests
- `bash` — needed to run tests

## Quick start

**1. Build**

```bash
git clone https://github.com/rhencke/confusio
cd confusio
make build       # produces confusio.com
```

**2. Run**

```bash
# Cloud-hosted providers — base URL defaults to the well-known public instance
sh ./confusio.com -p 8080 -- gitea
sh ./confusio.com -p 8080 -- gitlab
sh ./confusio.com -p 8080 -- forgejo

# Self-hosted instance — supply your own base URL
sh ./confusio.com -p 8080 -- gitea https://my-gitea.example.com
sh ./confusio.com -p 8080 -- gitlab https://gitlab.example.com
```

**3. Point your tools at it**

Set your tool's GitHub API base URL to `http://localhost:8080` and provide your provider token in the `Authorization` header (same format as GitHub: `token <pat>`).

## Configuration

Config is supplied as positional CLI arguments after `--`:

```bash
sh ./confusio.com -p 8080 -- <backend> [base_url]
```

```bash
# Use provider default URL
sh ./confusio.com -p 8080 -- gitea

# Override the URL (self-hosted instance)
sh ./confusio.com -p 8080 -- gitea https://my-gitea.example.com
```

## Providers

| Provider | `backend` value | Default `base_url` | Auth: pass as `token` |
|----------|----------------|--------------------|-----------------------|
| [Azure DevOps](https://dev.azure.com) | `azuredevops` | *(required: `https://dev.azure.com/{org}`)* | Personal access token *(see note)* |
| [Bitbucket](https://bitbucket.org) | `bitbucket` | `https://api.bitbucket.org` | `user:app-password` *(see note)* |
| [Bitbucket Datacenter](https://www.atlassian.com/software/bitbucket/enterprise) | `bitbucket_datacenter` | *(self-hosted — required)* | `user:password` *(see note)* |
| [Codeberg](https://codeberg.org) | `codeberg` | `https://codeberg.org` | API token |
| [Forgejo](https://forgejo.org) | `forgejo` | `https://codeberg.org` | API token |
| [Gerrit](https://www.gerritcodereview.com) | `gerrit` | *(self-hosted — required)* | `user:http-password` *(see note)* |
| [Gitbucket](https://gitbucket.github.io) | `gitbucket` | *(self-hosted — required)* | API token |
| [Gitea](https://gitea.com) | `gitea` | `https://gitea.com` | API token |
| [GitLab](https://gitlab.com) | `gitlab` | `https://gitlab.com` | Personal access token |
| [Gogs](https://gogs.io) | `gogs` | `https://try.gogs.io` | API token |
| [Harness Code](https://harness.io) | `harness` | `https://app.harness.io` | API token |
| [Kallithea](https://kallithea-scm.org) | `kallithea` | *(self-hosted — required)* | API token |
| [Launchpad](https://launchpad.net) | `launchpad` | `https://api.launchpad.net` | *(public endpoints only)* |
| [NotABug](https://notabug.org) | `notabug` | `https://notabug.org` | API token |
| [OneDev](https://onedev.io) | `onedev` | `https://code.onedev.io` | API token |
| [Pagure](https://pagure.io) | `pagure` | `https://pagure.io` | API token |
| [Phabricator](https://www.phacility.com) | `phabricator` | *(self-hosted — required)* | *(public endpoints only)* |
| [Radicle](https://radicle.xyz) | `radicle` | `http://127.0.0.1:8080` | Bearer token |
| [RhodeCode](https://rhodecode.com) | `rhodecode` | *(self-hosted — required)* | API token |
| [SourceForge](https://sourceforge.net) | `sourceforge` | `https://sourceforge.net` | *(public endpoints only)* |
| [Sourcehut](https://sr.ht) | `sourcehut` | `https://git.sr.ht` | Personal access token |

**Notes on auth format:**

- **Azure DevOps**: pass your PAT as `token <pat>` — confusio re-encodes it as `Basic base64(:<pat>)`.
- **Bitbucket / Gerrit / Bitbucket Datacenter**: pass `user:password` (or `user:app-password`) as `token user:password` — confusio re-encodes it as `Basic base64(user:password)`.
- All other providers: pass your token as `token <value>` (same header format as GitHub).

## Auth passthrough

Confusio never stores or logs tokens. The raw token value passes through unchanged; only the scheme wrapper is adjusted:

| Provider group | Confusio sends |
|----------------|---------------|
| Gitea, Forgejo, Gogs, Codeberg, NotABug, Pagure, Sourcehut | `Authorization: token <value>` |
| GitLab, OneDev, RhodeCode, Kallithea, Gitbucket, Harness, Radicle | `Authorization: Bearer <value>` |
| Azure DevOps | `Authorization: Basic base64(:<value>)` |
| Bitbucket, Gerrit, Bitbucket Datacenter | `Authorization: Basic base64(<value>)` |
| SourceForge, Launchpad, Phabricator | *(no auth forwarded)* |

## Status

Early design stage.

## Compatibility

See the [full compatibility matrix](https://rhencke.github.io/confusio/) on the project landing page.

## Testing

Unit tests run against mock backends on every push.  See [`docs/real-world-testing.md`](docs/real-world-testing.md) for the plan to extend coverage to real provider instances on a weekly cadence.

## Design docs

| Topic | Document |
|-------|----------|
| GraphQL support (overview) | [`docs/graphql/README.md`](docs/graphql/README.md) |
| GitHub GraphQL API surface and scope | [`docs/graphql/01-api-surface.md`](docs/graphql/01-api-surface.md) |
| Lexer and parser | [`docs/graphql/02-lexer-parser.md`](docs/graphql/02-lexer-parser.md) |
| Schema loading | [`docs/graphql/03-schema.md`](docs/graphql/03-schema.md) |
| Query executor | [`docs/graphql/04-executor.md`](docs/graphql/04-executor.md) |
| REST translation | [`docs/graphql/05-translation.md`](docs/graphql/05-translation.md) |
| Fragments, variables, directives | [`docs/graphql/06-fragments-vars-directives.md`](docs/graphql/06-fragments-vars-directives.md) |
| Relay pagination | [`docs/graphql/07-pagination.md`](docs/graphql/07-pagination.md) |
| Node/ID scheme | [`docs/graphql/08-node-id.md`](docs/graphql/08-node-id.md) |
| Error model | [`docs/graphql/09-errors.md`](docs/graphql/09-errors.md) |
| Auth and rate limiting | [`docs/graphql/10-auth-ratelimit.md`](docs/graphql/10-auth-ratelimit.md) |
| Mutations | [`docs/graphql/11-mutations.md`](docs/graphql/11-mutations.md) |
| Batching and caching | [`docs/graphql/12-batching-caching.md`](docs/graphql/12-batching-caching.md) |
| Testing strategy | [`docs/graphql/13-testing.md`](docs/graphql/13-testing.md) |
| Per-backend feasibility | [`docs/graphql/14-backend-feasibility.md`](docs/graphql/14-backend-feasibility.md) |
| Compatibility site integration | [`docs/graphql/15-compat-site.md`](docs/graphql/15-compat-site.md) |
| Rollout roadmap | [`docs/graphql/16-roadmap.md`](docs/graphql/16-roadmap.md) |
