# confusio

*confusio linguarum* — the confusion of tongues.

A REST API shim that implements a subset of GitHub's API, translating requests to other git hosting providers under the hood.

## What it is

GitHub's API is the lingua franca of git hosting tools. Other providers speak their own dialects. Confusio stands in the middle, translating.

Built with [Redbean](https://redbean.dev) — a single-file web server containing a Lua interpreter, distributed as a self-extracting zip.

## Prerequisites

- `make`, `zip`, `wget` — needed to build
- `curl`, `bash` — additionally needed to run tests

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

Config is supplied as positional CLI arguments after `--`, or in a `.confusio.lua` file in the working directory. CLI arguments take precedence.

**CLI arguments (positional):**

```bash
sh ./confusio.com -p 8080 -- <backend> [base_url]
```

```bash
# Use provider default URL
sh ./confusio.com -p 8080 -- gitea

# Override the URL (self-hosted instance)
sh ./confusio.com -p 8080 -- gitea https://my-gitea.example.com
```

**Config file (`.confusio.lua`):**

```lua
confusio = {
  backend  = "gitea",
  base_url = "https://my-gitea.example.com",
}
```

The config file is plain Lua, so secrets backends work naturally:

```lua
confusio = {
  backend  = "gitea",
  base_url = vault_read("secret/gitea-url"),
}
```

## Providers

| Provider | `backend` value | Default `base_url` | Auth: pass as `token` |
|----------|----------------|--------------------|-----------------------|
| [Gitea](https://gitea.com) | `gitea` | `https://gitea.com` | API token |
| [Forgejo](https://forgejo.org) | `forgejo` | `https://codeberg.org` | API token |
| [Gogs](https://gogs.io) | `gogs` | `https://try.gogs.io` | API token |
| [Codeberg](https://codeberg.org) | `codeberg` | `https://codeberg.org` | API token |
| [NotABug](https://notabug.org) | `notabug` | `https://notabug.org` | API token |
| [GitLab](https://gitlab.com) | `gitlab` | `https://gitlab.com` | Personal access token |
| [Gitbucket](https://gitbucket.github.io) | `gitbucket` | *(self-hosted — required)* | API token |
| [Harness Code](https://harness.io) | `harness` | `https://app.harness.io` | API token |
| [OneDev](https://onedev.io) | `onedev` | `https://code.onedev.io` | API token |
| [RhodeCode](https://rhodecode.com) | `rhodecode` | *(self-hosted — required)* | API token |
| [Kallithea](https://kallithea-scm.org) | `kallithea` | *(self-hosted — required)* | API token |
| [Radicle](https://radicle.xyz) | `radicle` | `http://127.0.0.1:8080` | Bearer token |
| [Azure DevOps](https://dev.azure.com) | `azuredevops` | *(required: `https://dev.azure.com/{org}`)* | Personal access token *(see note)* |
| [Bitbucket](https://bitbucket.org) | `bitbucket` | `https://api.bitbucket.org` | `user:app-password` *(see note)* |
| [Bitbucket Datacenter](https://www.atlassian.com/software/bitbucket/enterprise) | `bitbucket_datacenter` | *(self-hosted — required)* | `user:password` *(see note)* |
| [Gerrit](https://www.gerritcodereview.com) | `gerrit` | *(self-hosted — required)* | `user:http-password` *(see note)* |
| [Pagure](https://pagure.io) | `pagure` | `https://pagure.io` | API token |
| [Sourcehut](https://sr.ht) | `sourcehut` | `https://git.sr.ht` | Personal access token |
| [SourceForge](https://sourceforge.net) | `sourceforge` | `https://sourceforge.net` | *(public endpoints only)* |
| [Launchpad](https://launchpad.net) | `launchpad` | `https://api.launchpad.net` | *(public endpoints only)* |
| [Phabricator](https://www.phacility.com) | `phabricator` | *(self-hosted — required)* | *(public endpoints only)* |

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

## Compatibility

See the [full compatibility matrix](https://rhencke.github.io/confusio/) on the project landing page.
