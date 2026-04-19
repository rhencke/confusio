# Webhooks: GitHub-Emulation Contract

## Overview

Confusio's webhook surface extends the API translation layer to the **event side**.
Where the REST and GraphQL layers let clients *query* any forge as if it were GitHub,
the webhook layer lets forge events *arrive* at consumers as if they came from GitHub.

Two output shapes are available; targets opt in per registration:

| Shape | Description |
|-------|-------------|
| **GitHub emulation** | Payloads byte-compatible with GitHub's webhook format. Consumers already wired to GitHub (CI runners, bots, kennel) work without modification. |
| **Confusio normalized** | Forge-agnostic event stream using confusio's own namespace and envelope. Suitable for consumers that want a stable cross-forge contract without GitHub's legacy quirks. |

Both shapes are first-class.  Every event family is available in both.  Configuration
selects per-target which shape to emit.

### Goals

- **Zero-modification GitHub consumers** — CI runners, bots, and automation already
  wired to GitHub webhooks work against any forge without code changes.
- **Stable cross-forge contract** — The confusio normalized shape provides a
  forge-agnostic event stream that remains stable as backends evolve and add or
  rename fields.
- **Universal backend coverage** — All 24 backends supported by confusio's REST/GraphQL
  layer are also supported as webhook sources.
- **Signature verification before processing** — Every inbound event is authenticated
  using the originating forge's native scheme before entering the pipeline.  Unverified
  requests are rejected before any payload parsing occurs.
- **Multi-target fan-out** — A single inbound event can be delivered to multiple
  consumers, each with independent shape selection and event-type filtering.
- **Durable at-least-once delivery** — Events survive process restarts; failed
  deliveries are retried with exponential backoff.

### Non-Goals

- **Webhook registration** — Confusio does not create or delete webhooks on forges.
  Forge administrators register the confusio receiver URL manually in forge settings.
  There is no API for managing forge-side webhook subscriptions.
- **Exactly-once delivery** — The outbox guarantees at-least-once.  Consumers must
  be idempotent with respect to duplicate deliveries.
- **Synchronous passthrough** — Ingest is decoupled from delivery.  The inbound HTTP
  response (`200` / `202`) is returned before all targets have been notified.
- **Full GitHub webhook management API** — Ping events, webhook secret rotation
  endpoints, and GitHub's `/repos/{owner}/{repo}/hooks` REST surface are out of
  scope.  Confusio is a receiver, not a webhook management proxy.
- **Event deduplication across replays** — Replay re-delivers events from the outbox
  in order.  Deduplication (e.g., idempotency keys) is the consumer's responsibility.

## Architecture

```
Forge                          Confusio                         Consumer(s)
─────                          ────────                         ─────────────
Gitea     ──POST /webhooks/gitea──▶  verify sig
Forgejo   ──POST /webhooks/forgejo──▶  verify sig  ──▶  normalize
GitLab    ──POST /webhooks/gitlab──▶  verify sig  ──▶  translate  ──▶  outbox ──▶  target A (GitHub shape)
GitHub    ──POST /webhooks/github──▶  verify sig  ──▶  dispatch   ──▶        ──▶  target B (confusio shape)
...                                                                            ──▶  target C (filtered subset)
```

### Processing stages

1. **Receive** — Confusio listens on `POST /webhooks/{backend}`.  The path segment
   identifies which backend's signature scheme to apply.

2. **Verify** — The backend-specific signature or token is checked before any further
   processing.  Requests that fail verification are rejected with `401`.  See
   [Signature Verification](#signature-verification) for per-backend details.

3. **Normalize** — The raw payload is translated into confusio's internal event
   representation.  This is the canonical intermediate form; both output shapes are
   derived from it.

4. **Translate** — The internal event is converted to the requested output shape:
   - GitHub emulation applies field-level mappings to produce a byte-compatible GitHub
     webhook payload.  See [GitHub-Emulation Contract](#github-emulation-contract).
   - Confusio normalized wraps the internal event in the confusio envelope.  See
     [Normalized Confusio Event Model](#normalized-confusio-event-model).

5. **Dispatch** — The translated payload is placed in the durable outbox and delivered
   to all matching targets.  Filters, retries, and replay are described in
   [Delivery Semantics](#delivery-semantics).

### Backend-agnostic internal model

The internal event representation is a Lua table shared across all backends.  Every
field in the GitHub-emulation and confusio-normalized output shapes is populated from
this intermediate, not directly from the raw forge payload.  This ensures consistent
handling of missing or renamed fields across providers.

```
{
  event     = "issues",         -- GitHub event family name (canonical internal key)
  action    = "opened",         -- action within the event family
  provider  = "gitea",          -- originating backend
  delivery  = "<uuid>",         -- unique delivery identifier (generated by confusio)
  timestamp = "<iso8601>",      -- event timestamp (forge-supplied or arrival time)
  raw       = { ... },          -- original decoded payload (for debugging / passthrough)
  data      = { ... },          -- normalized field bag (provider-agnostic)
}
```

## Receiver Endpoints

Each supported backend has a dedicated ingest endpoint.  Forge administrators register
the corresponding URL as a webhook target in their forge's settings.

```
POST /webhooks/{backend}
```

### Per-backend inventory

Each row lists the ingest endpoint, the forge's canonical hosted URL (or _self-hosted_
for software with no official cloud instance), the API family that provides the shared
receiver implementation, and a brief note on the signature scheme used.  The
[Signature Verification](#signature-verification) section specifies each scheme in full.

| Backend | Endpoint | Default forge URL | API family | Signature scheme |
|---------|----------|------------------|------------|-----------------|
| `azuredevops` | `POST /webhooks/azuredevops` | `https://dev.azure.com` | azuredevops | Basic auth (username + shared secret in request body) |
| `bitbucket` | `POST /webhooks/bitbucket` | `https://bitbucket.org` | bitbucket | `X-Hub-Signature` HMAC-SHA256 |
| `bitbucket_datacenter` | `POST /webhooks/bitbucket_datacenter` | _(self-hosted)_ | bitbucket_datacenter | `X-Hub-Signature` HMAC-SHA256 |
| `codeberg` | `POST /webhooks/codeberg` | `https://codeberg.org` | gitea | `X-Gitea-Signature` HMAC-SHA256 |
| `codecommit` | `POST /webhooks/codecommit` | `https://aws.amazon.com` | codecommit | AWS SNS subscription confirmation + message signature |
| `forgejo` | `POST /webhooks/forgejo` | `https://forgejo.org` | gitea | `X-Gitea-Signature` HMAC-SHA256 |
| `gerrit` | `POST /webhooks/gerrit` | _(self-hosted)_ | gerrit | Shared secret in `Authorization` header |
| `gitblit` | `POST /webhooks/gitblit` | _(self-hosted)_ | gitblit | Shared token in `X-Gitblit-Token` header |
| `gitbucket` | `POST /webhooks/gitbucket` | _(self-hosted)_ | gitbucket | `X-Hub-Signature` HMAC-SHA1 |
| `gitea` | `POST /webhooks/gitea` | `https://gitea.com` | gitea | `X-Gitea-Signature` HMAC-SHA256 |
| `gitlab` | `POST /webhooks/gitlab` | `https://gitlab.com` | gitlab | `X-Gitlab-Token` shared secret |
| `gogs` | `POST /webhooks/gogs` | `https://try.gogs.io` | gitea | `X-Gogs-Signature` HMAC-SHA256 |
| `harness` | `POST /webhooks/harness` | `https://app.harness.io` | harness | Shared secret in `X-Harness-Token` header |
| `kallithea` | `POST /webhooks/kallithea` | _(self-hosted)_ | kallithea | Shared secret in request body |
| `launchpad` | `POST /webhooks/launchpad` | `https://launchpad.net` | launchpad | OpenPGP-signed payload |
| `notabug` | `POST /webhooks/notabug` | `https://notabug.org` | gitea | `X-Gitea-Signature` HMAC-SHA256 |
| `onedev` | `POST /webhooks/onedev` | _(self-hosted)_ | onedev | Shared secret in `Authorization: Bearer` header |
| `pagure` | `POST /webhooks/pagure` | `https://pagure.io` | pagure | `X-Pagure-Signature` HMAC-SHA512 + `X-Pagure-Signature-256` HMAC-SHA256 |
| `phabricator` | `POST /webhooks/phabricator` | _(self-hosted)_ | phabricator | `X-Phabricator-Webhook-Signature` HMAC-SHA256 (Conduit key) |
| `radicle` | `POST /webhooks/radicle` | `https://radicle.xyz` | radicle | Shared secret in `Authorization` header |
| `rhodecode` | `POST /webhooks/rhodecode` | _(self-hosted)_ | rhodecode | Shared secret in `X-RhodeCode-Signature` header |
| `sourceforge` | `POST /webhooks/sourceforge` | `https://sourceforge.net` | sourceforge | Shared secret in `X-Sourceforge-Webhook-Secret` header |
| `sourcehut` | `POST /webhooks/sourcehut` | `https://sr.ht` | sourcehut | `X-Payload-Signature` ed25519 (public key published by sr.ht) |
| `tuleap` | `POST /webhooks/tuleap` | _(self-hosted)_ | tuleap | `X-Tuleap-Webhook-Secret` shared secret |

### Event-type headers

Each backend uses a different header to communicate which event type is being
delivered.  Confusio maps these to its canonical internal event family names.

| API family | Event-type header | Example value |
|------------|------------------|---------------|
| gitea (gitea, forgejo, codeberg, gogs, notabug) | `X-Gitea-Event` | `issues`, `push`, `pull_request` |
| gitlab | `X-Gitlab-Event` | `Issues Hook`, `Push Hook`, `Merge Request Hook` |
| github | `X-GitHub-Event` | `issues`, `push`, `pull_request` |
| bitbucket | `X-Event-Key` | `repo:push`, `pullrequest:created` |
| bitbucket_datacenter | `X-Event-Key` | `repo:refs_changed`, `pr:opened` |
| azuredevops | _(body field)_ | `git.push`, `git.pullrequest.created` |
| codecommit | _(SNS `Message.detail-type`)_ | `CodeCommit Repository State Change` |
| pagure | `X-Pagure-Event` | `issue`, `pull-request`, `git` |
| sourcehut | _(body field `event`)_ | `push`, `patchset:created` |
| All others | _(backend-specific — see [Signature Verification](#signature-verification))_ | — |

### Request format

Confusio reads the following from every inbound webhook request:

| Element | How it is used |
|---------|---------------|
| Path segment `{backend}` | Selects the signature verification scheme |
| `Content-Type` header | Must be `application/json`; `application/x-www-form-urlencoded` is rejected |
| Backend event-type header | Backend-specific (e.g. `X-Gitea-Event`, `X-Gitlab-Event`, `X-GitHub-Event`) — identifies the event family |
| Signature header(s) | Backend-specific — used for payload verification before any processing |
| Request body | Raw JSON payload from the forge |

### Response codes

| Code | Meaning |
|------|---------|
| `200 OK` | Payload accepted, queued for delivery |
| `202 Accepted` | Payload accepted asynchronously (used when the outbox is non-blocking) |
| `400 Bad Request` | Malformed payload or unsupported `Content-Type` |
| `401 Unauthorized` | Signature verification failed |
| `404 Not Found` | Unknown backend name in path |
| `422 Unprocessable Entity` | Valid JSON but unrecognised event type (still logged for debugging) |

### Family aliases

Backends in the same API family share a receiver implementation.  The path segment
still uniquely identifies each alias so that forge administrators can register different
secrets per variant.

| Root backend | Aliases sharing the receiver implementation |
|-------------|---------------------------------------------|
| `gitea` | `forgejo`, `codeberg`, `gogs`, `notabug` |

All other backends have independent receiver implementations.

---

## Signature Verification

_(Details for each backend — HMAC schemes, token headers, IP allowlists, Conduit
signatures — are specified in a dedicated section.  See [signature-verification.md](webhooks/signature-verification.md) or the next
committed section of this document.)_

## GitHub-Emulation Contract

_(Headers, event names, and body schemas anchored to GitHub's OpenAPI webhook
descriptions are specified in a subsequent section of this document.)_

## Normalized Confusio Event Model

_(The confusio-native event namespace, envelope schema, and `X-Confusio-Signature`
header are specified in a subsequent section of this document.)_

## Field-Level Mapping Tables

_(Per-event-family × per-provider mapping tables are specified in a subsequent section
of this document.)_

## Delivery Semantics

_(Durable outbox design, retry backoff, replay API, and at-least-once guarantees are
specified in a subsequent section of this document.)_

## Multi-Target Dispatch and Configuration

_(Per-target filters, shape selection, and the admin registration surface are specified
in a subsequent section of this document.)_
