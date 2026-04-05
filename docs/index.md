---
title: confusio
---

# confusio

*confusio linguarum* — the confusion of tongues.

A REST API shim that implements a subset of [GitHub's API](https://docs.github.com/en/rest), translating requests to other git hosting providers under the hood.

Built with [Redbean](https://redbean.dev) — a single-file web server + Lua interpreter distributed as a self-extracting zip.

[View on GitHub](https://github.com/rhencke/confusio) · [README](https://github.com/rhencke/confusio#readme)

---

## How it works

Confusio runs as a local proxy. Your tools talk to confusio using the GitHub API; confusio translates each request to the target provider's native API and returns a GitHub-shaped response.

```
your tool  →  confusio (localhost)  →  Gitea / GitLab / Forgejo / …
              (GitHub API)              (provider native API)
```

Auth is PAT passthrough. Include a standard GitHub `Authorization: token <pat>` header in your requests to confusio — it reformats the header for the target provider. The token is never stored or logged.

---

## Quick start

```bash
# 1. Build
git clone https://github.com/rhencke/confusio
cd confusio
make build          # produces confusio.com

# 2. Run (example: Gitea)
sh ./confusio.com -p 8080 -- backend=gitea base_url=https://gitea.com

# 3. Use
curl -H "Authorization: token <your-pat>" http://localhost:8080/user/repos
```

---

## Providers

| Provider | `backend` | Default `base_url` | Token format |
|----------|----------|-------------------|--------------|
| [Gitea](https://gitea.com) | `gitea` | `https://gitea.com` | API token |
| [Forgejo](https://forgejo.org) | `forgejo` | `https://codeberg.org` | API token |
| [Codeberg](https://codeberg.org) | `codeberg` | `https://codeberg.org` | API token |
| [Gogs](https://gogs.io) | `gogs` | `https://try.gogs.io` | API token |
| [NotABug](https://notabug.org) | `notabug` | `https://notabug.org` | API token |
| [GitLab](https://gitlab.com) | `gitlab` | `https://gitlab.com` | Personal access token |
| [Gitbucket](https://gitbucket.github.io) | `gitbucket` | `https://your-host` | API token |
| [Harness Code](https://harness.io) | `harness` | `https://app.harness.io` | API token |
| [OneDev](https://onedev.io) | `onedev` | `https://code.onedev.io` | API token |
| [RhodeCode](https://rhodecode.com) | `rhodecode` | `https://your-host` | API token |
| [Kallithea](https://kallithea-scm.org) | `kallithea` | `https://your-host` | API token |
| [Radicle](https://radicle.xyz) | `radicle` | `http://127.0.0.1:8080` | Bearer token |
| [Azure DevOps](https://dev.azure.com) | `azuredevops` | `https://dev.azure.com/{org}` | PAT (re-encoded as Basic) |
| [Bitbucket](https://bitbucket.org) | `bitbucket` | `https://api.bitbucket.org` | `user:app-password` |
| [Bitbucket Datacenter](https://www.atlassian.com/software/bitbucket/enterprise) | `bitbucket_datacenter` | `https://your-host` | `user:password` |
| [Gerrit](https://www.gerritcodereview.com) | `gerrit` | `https://gerrit.example.com` | `user:http-password` |
| [Pagure](https://pagure.io) | `pagure` | `https://pagure.io` | API token |
| [Sourcehut](https://sr.ht) | `sourcehut` | `https://git.sr.ht` | Personal access token |
| [SourceForge](https://sourceforge.net) | `sourceforge` | `https://sourceforge.net` | *(health check only)* |
| [Launchpad](https://launchpad.net) | `launchpad` | `https://api.launchpad.net` | *(health check only)* |
| [Phabricator](https://www.phacility.com) | `phabricator` | `https://phab.example.com` | *(health check only)* |

---

## Compatibility matrix

`✓` = fully supported · `~` = partial · `✗` = not implemented

<div class="matrix-wrapper" markdown="1">

| Feature | Gitea | Forgejo | Codeberg | Gogs | NotABug | GitLab | Gitbucket | Harness | Azure&nbsp;DevOps | Bitbucket | Bitbucket&nbsp;DC | Gerrit | OneDev | Pagure | Radicle | Sourcehut | Kallithea | RhodeCode | Launchpad | SourceForge | Phabricator |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Repos (read) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ✓ | ~ | ~ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Repos (write) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Branches | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Commits | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ~ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Commit statuses | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Contents | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ~ | ~ | ~ | ~ | ~ | ~ | ~ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Tags | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Topics | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Languages | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Contributors | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Releases | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Archive (tar/zip) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Collaborators | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Forks | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ~ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Deploy keys | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Webhooks | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| User profile | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✗ | ✓ | ~ | ✓ | ~ | ✓ | ✗ | ~ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Teams | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |

</div>

<style>
.matrix-wrapper { overflow-x: auto; }
.matrix-wrapper table { min-width: 900px; font-size: 0.85em; }
</style>
