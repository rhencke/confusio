# confusio

*confusio linguarum* — the confusion of tongues.

A REST API shim that implements a subset of GitHub's remote API, translating requests to other providers under the hood.

## What it is

GitHub's API is the lingua franca of git hosting tools. Other providers speak their own dialects. Confusio stands in the middle, translating.

Built with [Redbean](https://redbean.dev) — a single-file web server containing a Lua interpreter, distributed as a self-extracting zip.

## Initially targeted providers

- GitLab
- Bitbucket
- Gitea
- Forgejo
- Sourcehut

## How it works

Confusio runs as a local proxy. Point your tools at it and Confusio translates GitHub API calls to the target provider's native API.

Auth is currently PAT-based: provide a token for the target provider and Confusio passes it through, translated to the right format. OAuth is out of scope for now.

## Compatibility

| Endpoint | GitLab | Bitbucket | Gitea | Forgejo | Sourcehut |
|----------|:------:|:---------:|:-----:|:-------:|:---------:|
| `GET /`  | ❌ | ❌ | ❌ | ❌ | ❌ |

✅ Supported · ⚠️ Partial · ❌ Unsupported

The matrix will be published to GitHub Pages.

## Status

Early design stage.
