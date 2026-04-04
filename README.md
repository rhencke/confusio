# confusio

*confusio linguarum* — the confusion of tongues.

A REST API shim that implements a subset of GitHub's remote API, translating requests to other providers under the hood.

## What it is

GitHub's API is the lingua franca of git hosting tools. Other providers speak their own dialects. Confusio stands in the middle, translating.

Built with [Redbean](https://redbean.dev) — a single-file web server containing a Lua interpreter, distributed as a self-extracting zip.

## How it works

Confusio runs as a local proxy. Point your tools at it and Confusio translates GitHub API calls to the target provider's native API.

Auth is PAT passthrough. Include a standard `Authorization` header in your request to confusio (e.g. `Authorization: token ghp_abc123…` — same as GitHub) and it will be re-formatted for the target provider:

| Provider | confusio sends |
|----------|---------------|
| Gitea, Forgejo, Gogs, Codeberg, NotABug, Pagure, Sourcehut | `Authorization: token <value>` |
| GitLab, OneDev, RhodeCode, Kallithea, Gitbucket, Harness, Radicle | `Authorization: Bearer <value>` |
| Azure DevOps | `Authorization: Basic base64(:<value>)` |
| Bitbucket, Gerrit | `Authorization: Basic base64(<value>)` — pass `user:password` as the token value |
| SourceForge, Launchpad, Phabricator | No auth forwarded (public health endpoints) |

The token value is never stored or modified — only the scheme wrapper changes. OAuth is out of scope for now.

## Compatibility

See the [full compatibility matrix](https://rhencke.github.io/confusio/) on the project landing page.

The full matrix is also published at the [project landing page](https://rhencke.github.io/confusio/).

## Status

Early design stage.
