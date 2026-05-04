# Webhooks: Translation Contract

## Overview

Confusio's webhook surface extends the API translation layer to the **event side**.
Where the REST and GraphQL layers let clients *query* any forge as if it were GitHub,
the webhook layer lets forge events *arrive* at consumers as if they came from GitHub.

Two output shapes are available; targets choose one at startup:

| Shape | Description |
|-------|-------------|
| **GitHub emulation** | Payloads byte-compatible with GitHub's webhook format. Consumers already wired to GitHub (CI runners, bots, kennel) work without modification. |
| **Confusio normalized** | Forge-agnostic event stream using confusio's own namespace and envelope. Suitable for consumers that want a stable cross-forge contract without GitHub's legacy quirks. |

Both shapes are first-class.  Every event family claimed in the support catalog can be
emitted in both shapes.  Configuration selects per-target which shape to emit.

### Goals

- **Zero-modification GitHub consumers** — CI runners, bots, and automation already
  wired to GitHub webhooks work against any forge without code changes.
- **Stable cross-forge contract** — The confusio normalized shape provides a
  forge-agnostic event stream that remains stable as backends evolve and add or
  rename fields.
- **Provider-bound ingest** — A running confusio process receives webhooks from exactly
  one configured upstream provider.  Multi-provider deployments run one confusio process
  per provider.
- **Signature verification before processing** — Every inbound event is authenticated
  using the originating forge's native scheme before entering the pipeline.  Unverified
  requests are rejected before any payload parsing occurs.
- **Multi-target fan-out** — A single inbound event can be delivered to multiple
  consumers, each with independent shape selection and event-type filtering.
- **Fire-and-record delivery** — Matching targets are POSTed synchronously during the
  inbound request.  Every attempted delivery is logged, but no
  retry, outbox, replay, or delivery-inspection layer is implemented.

### Non-Goals

- **Webhook registration** — Confusio does not create or delete webhooks on forges.
  Forge administrators register the confusio receiver URL manually in forge settings.
  There is no API for managing forge-side webhook subscriptions.
- **Runtime target registration** — Targets are fixed at startup.  There is no admin UI,
  config file, environment-variable target registry, or HTTP API for adding, removing,
  inspecting, or replaying deliveries.
- **Exactly-once delivery** — Consumers should still treat webhook delivery as
  potentially duplicate, especially when the originating forge retries an inbound
  request.
- **Durable replay** — Confusio currently logs delivery outcomes but does not persist
  an outbox, retry failed targets, or expose a replay API.
- **Full GitHub webhook management API** — Ping events, webhook secret rotation
  endpoints, and GitHub's `/repos/{owner}/{repo}/hooks` REST surface are out of
  scope.  Confusio is a receiver, not a webhook management proxy.
- **Event deduplication** — Deduplication (e.g., idempotency keys) is the consumer's
  responsibility.

## Architecture

```
Forge                          Confusio                          Consumer(s)
─────                          ────────                          ─────────────
Gitea   ──▶ /webhooks/gitea  ─┐
Forgejo ──▶ /webhooks/forgejo ─┤  verify  normalize  choose       ┌─▶ target A  (GitHub shape)
GitLab  ──▶ /webhooks/gitlab  ─┼──▶ sig ──▶ event ──▶ shape ─────├─▶ target B  (confusio shape)
Confusio ─▶ /webhooks/confusio ┤                  fan-out         └─▶ target C  (filtered subset)
...     ──▶ ...               ─┘                  (sync)

Operator ──▶ startup CLI / SCRIPTARGS ──▶ static target registry
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

4. **Translate** — Delivery shape is selected per target:
   - `github`: GitHub emulation re-encodes the provider-compatible webhook payload.
     See [GitHub-Emulation Contract](#github-emulation-contract).
   - `confusio`: Confusio normalized wraps the internal event in the normalized
     envelope.  See [Normalized Confusio Event Model](#normalized-confusio-event-model).

5. **Dispatch** — The translated payload is delivered synchronously to all matching
   configured targets.  Delivery is fire-and-record: each matching target receives one
   POST attempt, the outcome is logged, and the inbound request then receives `200 OK`.

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

Each supported inbound source has a dedicated ingest endpoint.  Forge administrators
register the corresponding URL as a webhook target in their forge's settings.  A
configured confusio process accepts only the endpoint for its configured provider;
requests for other known providers are treated as `404 Not Found`.

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
| `azuredevops` | `POST /webhooks/azuredevops` | `https://dev.azure.com` | azuredevops | Basic auth in `Authorization` header |
| `bitbucket` | `POST /webhooks/bitbucket` | `https://bitbucket.org` | bitbucket | `X-Hub-Signature` HMAC-SHA256 |
| `bitbucket_datacenter` | `POST /webhooks/bitbucket_datacenter` | _(self-hosted)_ | bitbucket_datacenter | `X-Hub-Signature` HMAC-SHA256 |
| `codeberg` | `POST /webhooks/codeberg` | `https://codeberg.org` | gitea | `X-Gitea-Signature` HMAC-SHA256 |
| `codecommit` | `POST /webhooks/codecommit` | `https://aws.amazon.com` | codecommit | Trust-the-network mode only; configured secret rejects until SNS verification is implemented |
| `confusio` | `POST /webhooks/confusio` | _(another confusio instance)_ | confusio | `X-Confusio-Signature-256` HMAC-SHA256 with timestamp |
| `forgejo` | `POST /webhooks/forgejo` | `https://forgejo.org` | gitea | `X-Gitea-Signature` HMAC-SHA256 |
| `gerrit` | `POST /webhooks/gerrit` | _(self-hosted)_ | gerrit | Shared secret in `Authorization` header |
| `gitblit` | `POST /webhooks/gitblit` | _(self-hosted)_ | gitblit | Shared token in `X-Gitblit-Token` header |
| `gitbucket` | `POST /webhooks/gitbucket` | _(self-hosted)_ | gitbucket | `X-Hub-Signature` HMAC-SHA1 |
| `gitea` | `POST /webhooks/gitea` | `https://gitea.com` | gitea | `X-Gitea-Signature` HMAC-SHA256 |
| `gitlab` | `POST /webhooks/gitlab` | `https://gitlab.com` | gitlab | `X-Gitlab-Token` shared secret |
| `gogs` | `POST /webhooks/gogs` | `https://try.gogs.io` | gitea | `X-Gogs-Signature` HMAC-SHA256 |
| `harness` | `POST /webhooks/harness` | `https://app.harness.io` | harness | Shared secret in `X-Harness-Token` header |
| `kallithea` | `POST /webhooks/kallithea` | _(self-hosted)_ | kallithea | Shared secret in request body |
| `launchpad` | `POST /webhooks/launchpad` | `https://launchpad.net` | launchpad | `X-Hub-Signature` HMAC-SHA1 |
| `notabug` | `POST /webhooks/notabug` | `https://notabug.org` | gitea | `X-Gogs-Signature` HMAC-SHA256 |
| `onedev` | `POST /webhooks/onedev` | _(self-hosted)_ | onedev | Shared secret in `X-OneDev-Signature` header |
| `pagure` | `POST /webhooks/pagure` | `https://pagure.io` | pagure | `X-Pagure-Signature` HMAC-SHA512 + `X-Pagure-Signature-256` HMAC-SHA256 |
| `phabricator` | `POST /webhooks/phabricator` | _(self-hosted)_ | phabricator | `X-Phabricator-Webhook-Signature` HMAC-SHA256 (Conduit key) |
| `radicle` | `POST /webhooks/radicle` | `https://radicle.xyz` | radicle | Shared secret in `Authorization` header |
| `rhodecode` | `POST /webhooks/rhodecode` | _(self-hosted)_ | rhodecode | Shared secret in `X-RhodeCode-Signature` header |
| `sourceforge` | `POST /webhooks/sourceforge` | `https://sourceforge.net` | sourceforge | `X-Allura-Signature` HMAC-SHA1 |
| `sourcehut` | `POST /webhooks/sourcehut` | `https://sr.ht` | sourcehut | `X-Payload-Signature` ed25519 (public key published by sr.ht) |
| `tuleap` | `POST /webhooks/tuleap` | _(self-hosted)_ | tuleap | `X-Tuleap-Webhook-Secret` shared secret |

### Event-type headers

Each backend uses a different header to communicate which event type is being
delivered.  Confusio maps these to its canonical internal event family names.

| API family | Event-type header | Example value |
|------------|------------------|---------------|
| gitea (gitea, forgejo, codeberg) | `X-Gitea-Event` | `issues`, `push`, `pull_request` |
| gogs (gogs, notabug) | `X-Gogs-Event` | `issues`, `push`, `pull_request` |
| gitlab | `X-Gitlab-Event` | `Issue Hook`, `Push Hook`, `Merge Request Hook` |
| bitbucket | `X-Event-Key` | `repo:push`, `pullrequest:created` |
| bitbucket_datacenter | `X-Event-Key` | `repo:refs_changed`, `pr:opened` |
| azuredevops | _(body field)_ | `git.push`, `git.pullrequest.created`, `build.complete`, `ms.vss-alerts.alert-created-event` |
| codecommit | _(SNS `Message.detail-type`)_ | `CodeCommit Repository State Change` |
| confusio | _(body field `type`)_ | `push`, `issue.opened`, `pull_request.synchronize` |
| kallithea | _(body fields)_ | `push`, `CREATE_REPO_HOOK`, `CREATE_PULLREQUEST_HOOK` |
| pagure | `X-Pagure-Event` | `issue`, `pull-request`, `git` |
| launchpad | `X-Launchpad-Event-Type` | `git:push:0.1`, `merge-proposal:0.1`, `bug:0.1` |
| radicle | _(body field `event_type`)_ | `push`, `patch` |
| sourcehut | _(body field `event`)_ | `GIT_POST_RECEIVE`, `EVENT_CREATED`, `PATCHSET_RECEIVED` |
| All others | _(backend-specific — see [Signature Verification](#signature-verification))_ | — |

### Request format

Confusio reads the following from every inbound webhook request:

| Element | How it is used |
|---------|---------------|
| Path segment `{backend}` | Selects the signature verification scheme |
| `Content-Type` header | Must include `application/json`, except Tuleap may send `application/x-www-form-urlencoded` with a JSON `payload` field |
| Backend event-type header or body field | Backend-specific (e.g. `X-Gitea-Event`, `X-Gitlab-Event`, `payload.type`) — identifies the event family |
| Signature header(s) | Backend-specific — used for payload verification before any processing |
| Request body | Raw JSON payload from the forge |

### Response codes

| Code | Meaning |
|------|---------|
| `200 OK` | Payload accepted; matching targets received their one synchronous delivery attempt |
| `400 Bad Request` | Malformed payload or unsupported `Content-Type` |
| `401 Unauthorized` | Signature verification failed |
| `404 Not Found` | Unknown backend name in path |
| `404 Not Found` | Known backend path that does not match the provider configured for this process |
| `422 Unprocessable Entity` | Valid JSON but unrecognised event type, unsupported action, or backend/body mismatch |

### Family aliases

Backends in the same API family share a receiver implementation.  The path segment
still uniquely identifies each alias so that forge administrators can register different
secrets per variant.

| Root backend | Aliases sharing the receiver implementation |
|-------------|---------------------------------------------|
| `gitea` | `forgejo`, `codeberg`, `gogs`, `notabug` |

All other backends have independent receiver implementations.

## Startup Configuration

Webhook configuration is immutable after startup.  To change provider, upstream, target
URL, target shape, event filter, or secrets, change the launch command and restart the
process.  There is no config file, environment-variable configuration, admin API,
runtime target registry, delivery inspection endpoint, retry queue, outbox, or replay
path.

### Provider and upstream

The preferred startup flags bind one confusio process to exactly one upstream provider:

```sh
sh ./confusio.com -p 8080 -- \
  --provider=gitea \
  --upstream=https://gitea.example
```

`--provider` names the inbound source and loads the matching backend implementation.
`--upstream` sets that provider's API base URL.  When `--provider` is used,
`--upstream` is required.  The older positional form remains supported:

```sh
sh ./confusio.com -p 8080 -- gitea https://gitea.example
```

Do not combine `--provider` with positional backend arguments, or `--upstream` with a
positional upstream URL.  Confusio fails startup on conflicting provider/upstream
configuration.

### Repeated webhook targets

Use one `--webhook-target` flag per outbound target:

```sh
sh ./confusio.com -p 8080 -- \
  --provider=gitea \
  --upstream=https://gitea.example \
  --webhook-target=name=fido,url=https://fido.example/webhooks,shape=github,events=issues+pull_request,secret_file=/run/secrets/fido-hook \
  --webhook-target=name=audit,url=https://audit.example/events,shape=confusio,events=*
```

Each target spec is comma-separated:

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Unique logical target name used in delivery log lines |
| `url` | yes | Absolute `http` or `https` URL to POST deliveries to |
| `shape` | no | `github` (default) or `confusio` |
| `events` | no | `*` or `+`/`,` separated event-family names such as `issues+push` |
| `secret` | no | Inline outbound signing secret; useful for tests only |
| `secret_file` | no | Path to a `0600` file containing the outbound signing secret |

Target names must be unique across all repeated target flags and the legacy single
target, if one is also configured.

### Legacy SCRIPTARGS compatibility

The original single-target key/value SCRIPTARGS remain supported for compatibility:

| Mechanism | Syntax |
|-----------|--------|
| Inbound secret file | `webhook_secret_file_BACKEND=/path` |
| Outbound target URL | `webhook_target=https://consumer.example/webhooks` |
| Target name | `webhook_target_name=NAME` |
| Target events | `webhook_target_events=push,pull_request` |
| Target shape | `webhook_target_shape=github` or `webhook_target_shape=confusio` |
| Target secret file | `webhook_target_secret_file=/path` |

Secret files must be owned by the running user and have permissions exactly `0600`.
Confusio trims trailing whitespace after reading the file.  If a required secret file
is missing or has broader permissions, startup fails.

### Event filtering

Target filters operate on canonical event-family names, not dotted normalized body
types.  For example, use `events=issues+pull_request` to receive all issue and pull
request actions, and inspect the GitHub `action` field or normalized `type` body field
inside the target if action-level routing is needed.  `events=*` matches every
accepted event family.

---

## Signature Verification

Every inbound webhook request is authenticated before any payload parsing or event
processing occurs.  A request that fails verification is rejected with `401
Unauthorized` and no further processing takes place.

### Verification principles

- **Constant-time comparison** — All secret comparisons use constant-time equality to
  prevent timing oracle attacks.  HMAC digest comparisons must not short-circuit.
- **Raw body integrity** — HMAC schemes sign the raw request body bytes exactly as
  received, before any JSON decoding.  Confusio must buffer the full body before
  verification.
- **Missing header = rejection** — If the expected signature or token header is absent
  and no fallback is configured, the request is rejected as if the signature were wrong.
- **Shared secret storage** — Secrets are stored in confusio's configuration and are
  never echoed back in responses or logs.

### Scheme types

Several distinct schemes appear across the supported inbound sources:

| Scheme | Description | Backends |
|--------|-------------|----------|
| **HMAC-SHA256** | Signature = `HMAC-SHA256(secret, body)`, hex-encoded | gitea, forgejo, codeberg, notabug, gogs, bitbucket, bitbucket_datacenter, phabricator, pagure (SHA-256 header) |
| **HMAC-SHA512** | Signature = `HMAC-SHA512(secret, body)`, hex-encoded | pagure (SHA-512 header, older instances) |
| **HMAC-SHA1** | Signature = `HMAC-SHA1(secret, body)`, hex-encoded | gitbucket (GitHub legacy compat), launchpad, sourceforge |
| **Shared token** | Secret echoed verbatim in a header or body field; constant-time string compare | gitlab, gitblit, harness, onedev, radicle, rhodecode, tuleap, kallithea |
| **Bearer / Basic** | Secret in Authorization header (Bearer or Basic form) | azuredevops (Basic), gerrit (Basic or Bearer) |
| **Asymmetric / platform** | ed25519 or platform-managed certificate signing | sourcehut |
| **Confusio HMAC** | Versioned HMAC basestring with timestamp replay window | confusio |

### Quick reference

| Backend | Header | Scheme | Format |
|---------|--------|--------|--------|
| `azuredevops` | `Authorization` | Basic auth | `Basic <base64(user:password)>` |
| `bitbucket` | `X-Hub-Signature` | HMAC-SHA256 | `sha256=<hex>` |
| `bitbucket_datacenter` | `X-Hub-Signature` | HMAC-SHA256 | `sha256=<hex>` |
| `codeberg` | `X-Gitea-Signature` | HMAC-SHA256 | `<hex>` |
| `codecommit` | SNS body fields | SNS X.509 RSA signature | `SignatureVersion` 1 or 2 |
| `confusio` | `X-Confusio-Signature-256` | HMAC-SHA256 with timestamp | `sha256=<hex>, v=1, ts=<unix>` |
| `forgejo` | `X-Gitea-Signature` | HMAC-SHA256 | `<hex>` |
| `gerrit` | `Authorization` | Basic or Bearer | see notes |
| `gitblit` | `X-Gitblit-Token` | Shared token | verbatim |
| `gitbucket` | `X-Hub-Signature` | HMAC-SHA1 | `sha1=<hex>` |
| `gitea` | `X-Gitea-Signature` | HMAC-SHA256 | `<hex>` |
| `gitlab` | `X-Gitlab-Token` | Shared token | verbatim |
| `gogs` | `X-Gogs-Signature` | HMAC-SHA256 | `<hex>` |
| `harness` | `X-Harness-Token` | Shared token | verbatim |
| `kallithea` | _(body field)_ | Body-embedded token | see notes |
| `launchpad` | `X-Hub-Signature` | HMAC-SHA1 | `sha1=<hex>` |
| `notabug` | `X-Gogs-Signature` | HMAC-SHA256 | `<hex>` |
| `onedev` | `X-OneDev-Signature` | Shared token | verbatim |
| `pagure` | `X-Pagure-Signature-256` / `X-Pagure-Signature` | HMAC-SHA256 / HMAC-SHA512 | `<hex>` |
| `phabricator` | `X-Phabricator-Webhook-Signature` | HMAC-SHA256 | `<hex>` |
| `radicle` | `Authorization` | Shared token | verbatim |
| `rhodecode` | `X-RhodeCode-Signature` | Shared token | verbatim |
| `sourceforge` | `X-Allura-Signature` | HMAC-SHA1 | `sha1=<hex>` |
| `sourcehut` | `X-Payload-Signature` | ed25519 | base64 |
| `tuleap` | `X-Tuleap-Webhook-Secret` | Shared token | verbatim |

### Test vectors

Implementers should validate their HMAC routines against these known-good vectors
before connecting to a live forge.  All values are derived from RFC 4231 (SHA-2
family) and RFC 2202 (SHA-1).

**HMAC-SHA256** (used by gitea family, bitbucket family, phabricator, pagure):

```
Key (ASCII):  Jefe
Data (ASCII): what do ya want for nothing?
Expected:     5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964a374a3
```

Verification command:
```sh
printf 'what do ya want for nothing?' | openssl dgst -sha256 -hmac 'Jefe'
# → SHA2-256(stdin)= 5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964a374a3
```

**HMAC-SHA512** (used by pagure primary header on older instances):

```
Key (ASCII):  Jefe
Data (ASCII): what do ya want for nothing?
Expected:     164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737
```

Verification command:
```sh
printf 'what do ya want for nothing?' | openssl dgst -sha512 -hmac 'Jefe'
# → SHA2-512(stdin)= 164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737
```

**HMAC-SHA1** (used by gitbucket):

```
Key (ASCII):  Jefe
Data (ASCII): what do ya want for nothing?
Expected:     effcdf6ae5eb2fa2d27416d5f184df9c259a7c79
```

Verification command:
```sh
printf 'what do ya want for nothing?' | openssl dgst -sha1 -hmac 'Jefe'
# → SHA1(stdin)= effcdf6ae5eb2fa2d27416d5f184df9c259a7c79
```

**Header prefix formats** — the following backends prepend a scheme prefix to their
hex digest.  Implementers must include the prefix in the comparison string:

| Backend | Full header value example |
|---------|--------------------------|
| `bitbucket`, `bitbucket_datacenter` | `sha256=5bdcc146...` |
| `gitbucket` | `sha1=effcdf6a...` |
| Gitea family, Gogs family, `phabricator`, `pagure` | `5bdcc146...` (no prefix) |

---

### Gitea family (gitea, forgejo, codeberg) and gogs-family aliases

All five backends use HMAC-SHA256 over the raw request body.  The header name differs
between the Gitea-derived backends and the Gogs-backed aliases, but the algorithm is
identical.

| Backend | Signature header | Algorithm |
|---------|-----------------|-----------|
| `gitea` | `X-Gitea-Signature` | HMAC-SHA256, lowercase hex |
| `forgejo` | `X-Gitea-Signature` | HMAC-SHA256, lowercase hex |
| `codeberg` | `X-Gitea-Signature` | HMAC-SHA256, lowercase hex |
| `gogs` | `X-Gogs-Signature` | HMAC-SHA256, lowercase hex |
| `notabug` | `X-Gogs-Signature` | HMAC-SHA256, lowercase hex |

Gitea-derived backends also send `X-Hub-Signature` (`sha1=<hex>`) for GitHub-client
compatibility; Gogs-backed backends may send `X-Hub-Signature` as well.  Confusio
verifies only `X-Gitea-Signature` for Gitea-derived backends or `X-Gogs-Signature`
for Gogs-backed backends and ignores `X-Hub-Signature`.

**Verification algorithm:**

```
secret       = configured shared secret (UTF-8 bytes)
body         = raw request body bytes
expected_hex = HMAC-SHA256(secret, body) in lowercase hex
received_hex = value of X-Gitea-Signature header (or X-Gogs-Signature for gogs/notabug)

accept if constant_time_equal(expected_hex, received_hex)
```

**Configuration:** The shared secret is set in the forge's webhook settings under
"Secret".  An empty secret disables HMAC verification — confusio should reject
requests with no signature when a secret is configured and accept all when no
secret is configured (trust-the-network mode, not recommended).

---

### GitLab

GitLab does **not** use HMAC.  It sends the configured secret as a plain string in
the `X-Gitlab-Token` header.

```
secret        = configured shared token (UTF-8 string)
received_token = value of X-Gitlab-Token header

accept if constant_time_equal(secret, received_token)
```

No body hashing is involved.  The token is just echoed verbatim.  This means the
token value itself must be kept secret — anyone who captures a request can replay it.
Confusio should warn operators that GitLab's scheme provides authentication but not
replay protection.

**Configuration:** Set in GitLab webhook settings as "Secret token".

---

### Bitbucket Cloud (bitbucket)

Bitbucket Cloud sends `X-Hub-Signature` in the same format as GitHub's legacy header
but using SHA-256.

```
Header:    X-Hub-Signature
Format:    sha256=<lowercase hex>
Algorithm: HMAC-SHA256(secret, raw_body)
```

```
expected = "sha256=" ++ HMAC-SHA256(secret, body) as lowercase hex
received = value of X-Hub-Signature

accept if constant_time_equal(expected, received)
```

**Configuration:** Set in Bitbucket Cloud webhook settings as "Secret".

---

### Bitbucket Datacenter (bitbucket_datacenter)

Bitbucket Datacenter (formerly Bitbucket Server) also uses `X-Hub-Signature` with
HMAC-SHA256.

```
Header:    X-Hub-Signature
Format:    sha256=<lowercase hex>
Algorithm: HMAC-SHA256(secret, raw_body)
```

Identical verification algorithm to Bitbucket Cloud.

**Configuration:** Set in webhook settings as "Secret".

---

### Pagure

Pagure sends two signature headers.  `X-Pagure-Signature` uses HMAC-SHA512 and is the
original scheme; `X-Pagure-Signature-256` uses HMAC-SHA256 and was added in later
versions.  Both are lowercase hex with no prefix.

| Header | Algorithm | Format | Availability |
|--------|-----------|--------|--------------|
| `X-Pagure-Signature` | HMAC-SHA512 | lowercase hex | all versions |
| `X-Pagure-Signature-256` | HMAC-SHA256 | lowercase hex | Pagure ≥ 5.13 |

**Verification algorithm:**

Confusio prefers `X-Pagure-Signature-256` when present (HMAC-SHA256 is preferred over
SHA-512 for consistency with other backends).  When only the SHA-512 header is present
(older instances), confusio falls back to verifying `X-Pagure-Signature`.

```
if X-Pagure-Signature-256 is present:
  expected = HMAC-SHA256(secret, body) as lowercase hex
  received = value of X-Pagure-Signature-256
  accept if constant_time_equal(expected, received)

  -- also verify SHA-512 if both headers are present:
  if X-Pagure-Signature is also present:
    expected_512 = HMAC-SHA512(secret, body) as lowercase hex
    received_512 = value of X-Pagure-Signature
    reject if NOT constant_time_equal(expected_512, received_512)

else if X-Pagure-Signature is present:
  expected = HMAC-SHA512(secret, body) as lowercase hex
  received = value of X-Pagure-Signature
  accept if constant_time_equal(expected, received)

else:
  reject (401)
```

**Configuration:** Set in Pagure webhook settings under "Pagure hook" → "Payload secret".

---

### Phabricator

Phabricator sends `X-Phabricator-Webhook-Signature` with an HMAC-SHA256 digest.
The key is the "HMAC Key" configured in the Herald webhook rule (not the application
Conduit API key).

```
Header:    X-Phabricator-Webhook-Signature
Format:    lowercase hex (no prefix)
Algorithm: HMAC-SHA256(hmac_key, raw_body)
```

```
expected = HMAC-SHA256(hmac_key, body) as lowercase hex
received = value of X-Phabricator-Webhook-Signature

accept if constant_time_equal(expected, received)
```

**Configuration:** The HMAC key is displayed in Phabricator's Herald webhook configuration
after creation.  It is distinct from Conduit API keys.

---

### GitBucket

GitBucket is GitHub API-compatible and uses the same signature scheme.

```
Header:    X-Hub-Signature
Format:    sha1=<lowercase hex>   (GitBucket uses SHA-1, not SHA-256)
Algorithm: HMAC-SHA1(secret, raw_body)
```

```
expected = "sha1=" ++ HMAC-SHA1(secret, body) as lowercase hex
received = value of X-Hub-Signature

accept if constant_time_equal(expected, received)
```

Note: GitBucket uses the legacy SHA-1 variant.  There is no SHA-256 variant.

**Configuration:** Set in GitBucket webhook settings as "Secret".

---

### Harness

Harness sends the shared token verbatim in `X-Harness-Token`.

```
secret         = configured shared token
received_token = value of X-Harness-Token

accept if constant_time_equal(secret, received_token)
```

**Configuration:** Set when creating the webhook in Harness under "Authentication" →
"Token".

---

### OneDev (onedev)

OneDev sends the shared secret verbatim in the `X-OneDev-Signature` header.

```
Header:    X-OneDev-Signature
Format:    <secret>
```

```
secret   = configured webhook secret
received = value of X-OneDev-Signature header

accept if constant_time_equal(secret, received)
```

**Configuration:** Set in OneDev webhook settings as "Secret".

---

### Radicle

Radicle sends the shared secret in the `Authorization` header.  Current Radicle node
versions do not use a `Bearer` or `Basic` prefix — the secret value is sent as-is.
Radicle CI adapter requests identify the event family in the root `event_type` body
field; current values are `push` for branch/tag ref changes and `patch` for patch
create/update requests.

Confusio maps Radicle `push` requests to GitHub `push`, `create`, or `delete`
deliveries based on the `before` / `after` all-zero SHA convention.  Radicle `patch`
requests currently map `created` to `pull_request.opened` and `updated` to
`pull_request.synchronize`.

```
secret   = configured shared secret
received = value of Authorization header (verbatim, no prefix stripping)

accept if constant_time_equal(secret, received)
```

**Note:** Radicle's webhook support is experimental as of Radicle 1.x.  If the header
format changes in a future Radicle release, the confusio receiver will need updating.
Verify against the Radicle node version in use.

---

### RhodeCode

RhodeCode sends the shared secret in `X-RhodeCode-Signature` as a plain token (no
HMAC).  Early RhodeCode Enterprise versions may use HMAC-SHA1 in this header instead;
verify against the deployed version.

```
secret   = configured shared secret
received = value of X-RhodeCode-Signature

accept if constant_time_equal(secret, received)
```

**If the deployed version uses HMAC-SHA1** (check RhodeCode release notes):

```
expected = "sha1=" ++ HMAC-SHA1(secret, body) as lowercase hex
received = value of X-RhodeCode-Signature

accept if constant_time_equal(expected, received)
```

**Configuration:** Set in RhodeCode webhook settings as "Authentication token".

---

### SourceForge

SourceForge runs Allura for project webhooks. Allura signs the raw JSON payload
with the configured webhook secret and sends the digest in `X-Allura-Signature`.

```
secret   = configured shared secret
expected = "sha1=" ++ HMAC-SHA1(secret, body) as lowercase hex
received = value of X-Allura-Signature

accept if constant_time_equal(expected, received)
```

**Configuration:** Set `secret` when registering the webhook in SourceForge or
Allura project settings; Allura may generate one if left blank.

**Supported events:** SourceForge / Allura repository hooks do not send an event
type header.  Confusio infers Allura `repo-push` payloads from the documented
ref update shape and translates them to GitHub-compatible `push`, `create`, or
`delete` events.  Branch and tag create/delete events are derived when `before`
or `after` is the all-zero SHA; other SourceForge webhook families are not
mapped.

---

### Tuleap

Tuleap sends the shared secret in `X-Tuleap-Webhook-Secret`.

```
secret   = configured shared secret
received = value of X-Tuleap-Webhook-Secret

accept if constant_time_equal(secret, received)
```

**Configuration:** Set in Tuleap webhook settings as "Secret".

**Supported events:** Tuleap sends form-encoded webhook bodies with a JSON `payload`
field.  Confusio accepts project creation, Git ref updates, and tracker artifact
create/update payloads.  Git ref updates translate to GitHub-compatible `push`,
`create`, or `delete` events depending on the `before` / `after` all-zero SHA
markers; artifact create/update payloads translate to `issues.opened` and
`issues.edited`.

---

### Gerrit

Gerrit's webhook plugin does not have a standardized signature scheme.  Authentication
is typically configured as HTTP Basic auth credentials embedded in the webhook URL,
`Authorization: Bearer <secret>`, or a raw shared token in `Authorization` depending
on the plugin version.

Confusio supports all three `Authorization` header forms:

```
Authorization: <secret>
Authorization: Bearer <secret>
Authorization: Basic <base64(user:password)>
```

For Basic auth, confusio extracts and Base64-decodes the credential pair, then
verifies the decoded `user:password` string against the configured secret.

**Note:** Gerrit webhook signature support varies by plugin version.  Operators should
pin the plugin version and verify which auth form is in use.

---

### Gitblit

Gitblit sends the shared token in `X-Gitblit-Token`.

```
secret   = configured shared token
received = value of X-Gitblit-Token

accept if constant_time_equal(secret, received)
```

**Configuration:** Set in Gitblit's `gitblit.properties` as `groovy.postReceiveScripts`
with the token value in the webhook receiver configuration.

---

### Kallithea

Kallithea does not use signature headers.  Authentication depends on the Kallithea
version and the webhook plugin in use.

**Option A — Body-embedded token** (Kallithea's built-in webhook receiver):
Kallithea may embed an authentication token in the JSON body.  The exact field path
varies by Kallithea version.  Confusio extracts the token from the body, compares it
against the configured secret, then proceeds.  This requires decoding the body before
verification — an exception to the "verify before parse" principle.  Confusio buffers
the raw body, parses it only to extract the token, verifies, then re-uses the buffered
bytes for event processing.

```
secret   = configured shared secret
body     = decoded JSON payload
received = body token value (field path TBD per Kallithea version)

accept if constant_time_equal(secret, received)
```

**Option B — No authentication** (Kallithea's default):
Kallithea's default webhook plugin sends no authentication.  If confusio is configured
with no secret for this endpoint, all inbound requests are accepted.  Operators should
restrict access to the `/webhooks/kallithea` endpoint via network policy.

**Note:** Kallithea's webhook authentication support is poorly documented and varies
significantly by version.  Operators should verify the exact scheme against their
deployed Kallithea version before relying on authentication.  If no reliable
authentication is available, network-level access controls are strongly recommended.

---

### Azure DevOps (azuredevops)

Azure DevOps service hooks use HTTP Basic authentication.  The username and password
are configured in the service hook settings; confusio verifies the `Authorization`
header against the exact `username:password` credential stored in the backend secret
file.

```
Header:    Authorization
Format:    Basic <base64(username:password)>
```

```
configured_secret = configured "username:password" string
received_header     = value of Authorization header

decoded = base64_decode(received_header after stripping "Basic ")

accept if constant_time_equal(configured_secret, decoded)
```

**Configuration:** Set in Azure DevOps service hook settings under "Basic authentication"
→ "Username" and "Password".

**Implemented service hook families:** Confusio maps Azure DevOps Git, pull request,
work item, build, release/deployment, and Advanced Security service hooks into the
closest GitHub webhook families:

| Azure DevOps event family | GitHub event family |
|---------------------------|---------------------|
| `git.push` | `push`, `create`, `delete` |
| `git.repo.*` | `repository` |
| `git.pullrequest.*` | `pull_request`, `pull_request_review` |
| `workitem.*` | `issues`, `issue_comment` |
| `build.complete` | `workflow_run` |
| `ms.azure-devops-release.*` | `release`, `deployment`, `deployment_status`, `deployment_review` |
| `ms.vss-alerts.*` | `code_scanning_alert`, `dependabot_alert`, `secret_scanning_alert` |

---

### AWS CodeCommit (codecommit)

CodeCommit can deliver repository changes through SNS-style, EventBridge-style, or
trigger-style JSON payloads.  Confusio currently supports event-family inference and
payload translation for those body shapes.  When CodeCommit is delivered through SNS,
confusio can verify the SNS `SignatureVersion` 1 or 2 RSA signature against the
certificate published in `SigningCertURL`.

When no `webhook_secret_file_codecommit` is configured, CodeCommit ingest runs in
trust-the-network mode for direct trigger, EventBridge, and SNS payloads.  When a
CodeCommit inbound secret is configured, confusio requires a signed SNS HTTP payload,
validates that `SigningCertURL` points at an SNS `amazonaws.com` certificate endpoint,
builds the canonical SNS string-to-sign, fetches and caches the certificate, and
verifies the decoded signature before dispatch.  Unsigned direct trigger/EventBridge
payloads are rejected in this mode.

**Configuration:** Register the confusio receiver URL as the CodeCommit/SNS/EventBridge
HTTP endpoint.  Leave the CodeCommit inbound secret unset for network-trusted direct
trigger/EventBridge delivery; set `webhook_secret_file_codecommit` to any non-empty
value to require SNS signature verification.

---

### Confusio-to-confusio

A confusio instance can receive another confusio instance's normalized envelope at
`POST /webhooks/confusio`.  The event family is derived from the body `type` field, and
`X-Confusio-Event` is validated against that family when present.

```
Header:    X-Confusio-Signature-256
Format:    sha256=<lowercase hex>, v=1, ts=<unix>
Algorithm: HMAC-SHA256(secret, "v1:<ts>:<raw_body>")
```

The timestamp must be within the receiver's replay window.  A stale timestamp rejects
the request even when the HMAC is otherwise correct.

**Configuration:** Configure the receiving instance with
`webhook_secret_file_confusio=/path` when signed cross-confusio delivery is required.
With no secret configured, the endpoint uses the same trust-the-network mode as other
webhook sources.

---

### Sourcehut

Sourcehut uses ed25519 asymmetric signatures.  The signing key is sr.ht's private key;
the public key is published at a well-known URL.

```
Header:    X-Payload-Signature
Format:    base64-encoded ed25519 signature (standard encoding)
```

**Verification steps:**

1. **Fetch public key**: `GET https://meta.sr.ht/.well-known/webhook-key` returns the
   raw ed25519 public key in base64 format (32 bytes decoded).  Cache this key; it
   changes only during key rotation.

2. **Verify signature**:

```
public_key = base64_decode(key from well-known URL)
message    = raw request body bytes
signature  = base64_decode(value of X-Payload-Signature)

accept if ed25519_verify(public_key, message, signature) == true
```

**No shared secret is configured** — authentication is established by sr.ht's published
public key.  Configure that base64 public key with `webhook_secret_file_sourcehut`;
when no key is configured, confusio uses the same trust-the-network mode as other
webhook backends.

---

### Launchpad

Launchpad signs webhook payloads with the optional secret configured on the webhook.
When a secret is configured, the signature is sent in the `X-Hub-Signature` header
using the PubSubHubbub-compatible HMAC-SHA1 form.

```
Header:    X-Hub-Signature
Format:    sha1=<lowercase hex digest>
Algorithm: HMAC-SHA1(secret, raw body bytes)
```

**Verification steps:**

```
expected = "sha1=" .. hmac_sha1(secret, raw_body)
received = value of X-Hub-Signature

accept if constant_time_equal(expected, received)
```

**No shared secret configured** — Launchpad omits `X-Hub-Signature`; confusio accepts
the request in trust-the-network mode.

## GitHub-Emulation Contract

When a delivery target is configured for GitHub-emulation shape, confusio translates
the normalized internal event into a payload that is byte-compatible with what GitHub
itself would deliver for the equivalent event.  Consumers wired to GitHub webhooks —
CI runners, bots, kennel — receive confusio deliveries without modification.

### Delivery headers

Confusio sends the following HTTP headers with every GitHub-emulation delivery:

| Header | Value | Notes |
|--------|-------|-------|
| `X-GitHub-Event` | GitHub event name (e.g. `push`, `issues`) | Always present |
| `X-GitHub-Delivery` | UUID v4, unique per delivery attempt | Always present |
| Provider-native signature header(s) | Backend-specific | Present when the outbound target has a secret; produced by the source provider's signing helper |
| `Content-Type` | `application/json` | Always `application/json` |
| `User-Agent` | `confusio/1.0` | Identifies confusio; differs from GitHub's `GitHub-Hookshot/<hash>` |

**Signature computation:** Outbound signing uses the source provider's native scheme
and the consumer target's configured secret (not the inbound forge secret).  For
example, a GitHub-shaped delivery sourced from `gitea` carries `X-Gitea-Signature`,
while one sourced from `gitlab` carries `X-Gitlab-Token`.  This preserves the
provider-bound trust model across both output shapes.

**`User-Agent` difference:** Confusio emits `confusio/1.0` rather than GitHub's
`GitHub-Hookshot/<hash>`.  Consumers that check `User-Agent` exactly will
need configuration adjustment; consumers that check only `X-GitHub-Event` and
the configured signature header are unaffected.

### Concrete delivery example

A complete outbound delivery for an `issues` event looks like:

```http
POST /hooks/confusio HTTP/1.1
Host: consumer.example.com
Content-Type: application/json
X-GitHub-Event: issues
X-GitHub-Delivery: 72d3162e-cc78-11e3-81ab-4c9367dc0958
X-Gitea-Signature: d57c68ca6f92289e6987d106c9e3f9b2cc4e0b8c6c6f16e6df27b2c5e8d3a14
User-Agent: confusio/1.0
Content-Length: 347

{"action":"opened","issue":{"id":1,"number":42,"title":"Found a bug","body":"Something broke.","state":"open","html_url":"https://gitea.com/alice/myrepo/issues/42","user":{"id":1,"login":"alice","avatar_url":"https://gitea.com/user/avatar/alice","html_url":"https://gitea.com/alice","type":"User"},"labels":[],"assignees":[],"milestone":null,"created_at":"2024-01-15T10:00:00Z","updated_at":"2024-01-15T10:00:00Z","closed_at":null},"repository":{"id":100,"name":"myrepo","full_name":"alice/myrepo","private":false,"html_url":"https://gitea.com/alice/myrepo","description":null,"fork":false,"default_branch":"main","owner":{"id":1,"login":"alice","avatar_url":"https://gitea.com/user/avatar/alice","html_url":"https://gitea.com/alice","type":"User"},"created_at":"2023-01-01T00:00:00Z","updated_at":"2024-01-15T10:00:00Z","pushed_at":"2024-01-15T10:00:00Z"},"sender":{"id":1,"login":"alice","avatar_url":"https://gitea.com/user/avatar/alice","html_url":"https://gitea.com/alice","type":"User"}}
```

### Supported event names

Confusio emits the following GitHub event names.  Coverage depends on the originating
backend — see [Field-Level Mapping Tables](#field-level-mapping-tables) for per-backend
action availability.

| GitHub event | Trigger | Supported actions |
|-------------|---------|------------------|
| `push` | Commits pushed to a branch or tag | _(no action field — push is a single event)_ |
| `create` | Branch or tag created | _(no action field)_ |
| `delete` | Branch or tag deleted | _(no action field)_ |
| `fork` | Repository forked | _(no action field)_ |
| `issues` | Issue lifecycle | `opened`, `closed`, `reopened`, `edited`, `labeled`, `unlabeled`, `assigned`, `unassigned` |
| `issue_comment` | Comment on issue or PR | `created`, `edited`, `deleted` |
| `pull_request` | Pull request lifecycle | `opened`, `closed`, `reopened`, `edited`, `labeled`, `unlabeled`, `assigned`, `unassigned`, `synchronize` |
| `pull_request_review` | Review submitted on a PR | `submitted`, `dismissed` |
| `pull_request_review_comment` | Comment on a PR review diff | `created`, `edited`, `deleted` |
| `release` | Release lifecycle | `published`, `edited`, `deleted`, `prereleased` |
| `repository` | Repository lifecycle | `created`, `deleted`, `edited`, `renamed`, `transferred`, `publicized`, `privatized` |
| `gollum` | Wiki page created or edited | _(no top-level action — action is per-page in `pages[]`)_ |
| `deploy_key` | SSH deploy key added or removed | `created`, `deleted` |
| `public` | Private repository made public | _(no action field)_ |
| `member` | Collaborator added or removed | `added`, `removed`, `edited` |
| `membership` | Team membership changed | `added`, `removed` |
| `organization` | Org lifecycle event | `created`, `deleted`, `renamed`, `member_added`, `member_invited`, `member_removed` |
| `team` | Team lifecycle event | `created`, `deleted`, `edited`, `added_to_repository`, `removed_from_repository` |
| `team_add` | Team granted access to repository | _(no action field)_ |
| `milestone` | Milestone lifecycle | `created`, `closed`, `opened`, `edited`, `deleted` |
| `label` | Label lifecycle | `created`, `edited`, `deleted` |
| `commit_comment` | Comment on a commit | `created` |
| `status` | Commit status update | _(no action field — status is a single event)_ |
| `deployment` | Deployment created | `created` |
| `deployment_status` | Deployment status updated | `created` |
| `deployment_review` | Deployment awaiting or receiving review | `approved`, `rejected`, `requested` |
| `deployment_protection_rule` | Deployment protection rule triggered | `requested` |
| `ping` | Upstream webhook ping/test event | _(no action field)_ |
| `meta` | Webhook deleted | `deleted` |
| `page_build` | GitHub Pages build completed | _(no action field)_ |
| `custom_property` | Org-level custom property lifecycle | `created`, `deleted`, `updated` |
| `custom_property_values` | Repo-level custom property values changed | `updated` |
| `star` | Repository starred or unstarred | `created`, `deleted` |
| `watch` | User started watching repository | `started` |
| `sponsorship` | GitHub Sponsors lifecycle | `created`, `cancelled`, `edited`, `tier_changed`, `pending_cancellation`, `pending_tier_change` |
| `discussion` | Discussion thread lifecycle | `created`, `edited`, `deleted`, `closed`, `reopened`, `answered`, `unanswered`, `labeled`, `unlabeled`, `locked`, `unlocked`, `pinned`, `unpinned`, `category_changed`, `transferred` |
| `discussion_comment` | Comment on a discussion thread | `created`, `edited`, `deleted` |

Events not in this table are not currently emitted by confusio in GitHub-emulation
shape.  Backends that produce event types with no GitHub equivalent are dropped or
mapped to the closest GitHub event family with a fidelity note in the body.

### Body envelope

All GitHub webhook bodies share a common envelope.  Fields present depend on the
event type, but the following are included in every body:

```json
{
  "action":     "<string or absent>",
  "sender":     { ... },
  "repository": { ... },
  "organization": { ... }
}
```

| Field | Present when | Description |
|-------|-------------|-------------|
| `action` | Most events | The action within the event family (e.g. `"opened"`) |
| `sender` | Always | GitHub user object for the actor who triggered the event |
| `repository` | Always for repo-scoped events | Repository object |
| `organization` | Org-scoped events | Organization object; omitted for personal repos |
| `installation` | GitHub App events | GitHub App installation; omitted in confusio emulation |

### Per-event body schemas

#### `push`

```json
{
  "ref":        "refs/heads/main",
  "before":     "<sha>",
  "after":      "<sha>",
  "created":    false,
  "deleted":    false,
  "forced":     false,
  "commits":    [
    {
      "id":        "<sha>",
      "message":   "<string>",
      "timestamp": "<iso8601>",
      "url":       "<string>",
      "author":    { "name": "<string>", "email": "<string>", "username": "<string>" },
      "committer": { "name": "<string>", "email": "<string>", "username": "<string>" },
      "added":     ["<path>"],
      "removed":   ["<path>"],
      "modified":  ["<path>"]
    }
  ],
  "head_commit":   { ... },
  "pusher":        { "name": "<string>", "email": "<string>" },
  "compare":       "<url>",
  "repository":    { ... },
  "sender":        { ... }
}
```

#### `create` / `delete`

```json
{
  "ref":          "main",
  "ref_type":     "branch",
  "master_branch": "main",
  "description":  "<string or null>",
  "pusher_type":  "user",
  "repository":   { ... },
  "sender":       { ... }
}
```

`ref_type` is `"branch"` or `"tag"`.

#### `issues`

```json
{
  "action":     "opened",
  "issue":      {
    "id":         12345,
    "number":     42,
    "title":      "<string>",
    "body":       "<string or null>",
    "state":      "open",
    "html_url":   "<url>",
    "user":       { ... },
    "labels":     [ { "name": "<string>", "color": "<hex>" } ],
    "assignees":  [ { ... } ],
    "milestone":  { ... },
    "created_at": "<iso8601>",
    "updated_at": "<iso8601>",
    "closed_at":  "<iso8601 or null>"
  },
  "repository": { ... },
  "sender":     { ... }
}
```

#### `issue_comment`

```json
{
  "action":     "created",
  "issue":      { ... },
  "comment":    {
    "id":         67890,
    "body":       "<string>",
    "html_url":   "<url>",
    "user":       { ... },
    "created_at": "<iso8601>",
    "updated_at": "<iso8601>"
  },
  "repository": { ... },
  "sender":     { ... }
}
```

#### `pull_request`

```json
{
  "action":       "opened",
  "number":       7,
  "pull_request": {
    "id":                12345,
    "number":            7,
    "title":             "<string>",
    "body":              "<string or null>",
    "state":             "open",
    "html_url":          "<url>",
    "user":              { ... },
    "head":              { "ref": "feature", "sha": "<sha>", "repo": { ... } },
    "base":              { "ref": "main",    "sha": "<sha>", "repo": { ... } },
    "merged":            false,
    "merged_at":         "<iso8601 or null>",
    "merge_commit_sha":  "<sha or null>",
    "labels":            [ { "name": "<string>", "color": "<hex>" } ],
    "assignees":         [ { ... } ],
    "requested_reviewers": [ { ... } ],
    "draft":             false,
    "created_at":        "<iso8601>",
    "updated_at":        "<iso8601>",
    "closed_at":         "<iso8601 or null>"
  },
  "repository":   { ... },
  "sender":       { ... }
}
```

When `action` is `"closed"` and `pull_request.merged` is `true`, the PR was merged.

#### `pull_request_review`

```json
{
  "action":       "submitted",
  "review":       {
    "id":          99,
    "body":        "<string or null>",
    "state":       "approved",
    "html_url":    "<url>",
    "user":        { ... },
    "submitted_at": "<iso8601>"
  },
  "pull_request": { ... },
  "repository":   { ... },
  "sender":       { ... }
}
```

`review.state` values: `"approved"`, `"changes_requested"`, `"commented"`, `"dismissed"`.

#### `release`

```json
{
  "action":  "published",
  "release": {
    "id":              111,
    "tag_name":        "v1.2.3",
    "name":            "<string or null>",
    "body":            "<string or null>",
    "draft":           false,
    "prerelease":      false,
    "html_url":        "<url>",
    "tarball_url":     "<url or null>",
    "zipball_url":     "<url or null>",
    "author":          { ... },
    "created_at":      "<iso8601>",
    "published_at":    "<iso8601 or null>"
  },
  "repository": { ... },
  "sender":     { ... }
}
```

#### `deployment`

```json
{
  "action": "created",
  "deployment": {
    "id":                     1,
    "sha":                    "<commit sha>",
    "ref":                    "main",
    "task":                   "deploy",
    "environment":            "production",
    "original_environment":   "staging",
    "description":            "<string or null>",
    "payload":                {},
    "creator":                { ... },
    "created_at":             "<iso8601>",
    "updated_at":             "<iso8601>",
    "statuses_url":           "<url>",
    "repository_url":         "<url>",
    "production_environment": true,
    "transient_environment":  false
  },
  "workflow":     { ... },
  "workflow_run": { ... },
  "repository":   { ... },
  "sender":       { ... }
}
```

`task` is typically `"deploy"`.  `environment` is a free-form string naming the target
(e.g. `"production"`, `"staging"`).  `original_environment` is the environment that was
configured before any promotion.  `payload` is an arbitrary JSON object provided by the
creator.  `production_environment` and `transient_environment` are booleans set by the
creator at deployment time.  `workflow` and `workflow_run` are present when the deployment
was triggered by a GitHub Actions workflow and are `null` otherwise.

#### `deployment_status`

```json
{
  "action": "created",
  "deployment_status": {
    "id":               2,
    "state":            "success",
    "description":      "<string or null>",
    "environment":      "production",
    "environment_url":  "<url or null>",
    "log_url":          "<url or null>",
    "target_url":       "<url or null>",
    "deployment_url":   "<url>",
    "created_at":       "<iso8601>",
    "updated_at":       "<iso8601>",
    "creator":          { ... }
  },
  "deployment":   { ... },
  "repository":   { ... },
  "sender":       { ... }
}
```

`state` values: `"error"`, `"failure"`, `"inactive"`, `"pending"`, `"success"`,
`"queued"`, `"in_progress"`, `"waiting"`.  `deployment` is the full deployment object
(same shape as in the `deployment` event body).  `environment_url` is a URL for the
live environment, if set.  `log_url` is a direct link to the deployment log.

#### `deployment_review`

```json
{
  "action":       "approved",
  "approver":     { "login": "<string>", "id": 0 },
  "comment":      "<string or null>",
  "since":        "<iso8601>",
  "environment":  "production",
  "reviewers":    [
    {
      "type":     "User",
      "reviewer": { "login": "<string>", "id": 0 }
    }
  ],
  "workflow_run": { ... },
  "repository":   { ... },
  "sender":       { ... }
}
```

Fired when a deployment pending a required review is approved or rejected, or when a
review is first requested.  `approver` is present on `approved` and `rejected` actions.
`reviewers` is the list of users or teams that can review the deployment.  `since` is the
ISO 8601 timestamp from which the review request has been pending.

#### `deployment_protection_rule`

```json
{
  "action":                  "requested",
  "environment":             "production",
  "event":                   "pull_request",
  "sha":                     "<commit sha>",
  "ref":                     "main",
  "deployment_callback_url": "<url>",
  "deployment":              { ... },
  "pull_requests":           [ { ... } ],
  "repository":              { ... },
  "sender":                  { ... }
}
```

Fired when a deployment protection rule is triggered for an environment.  `event` is the
GitHub event that triggered the deployment (e.g. `"pull_request"`, `"push"`).
`deployment_callback_url` is the URL that an integration must POST to in order to approve
or reject the deployment.  `deployment` is the full deployment object; `pull_requests`
is the list of pull requests that triggered this deployment (may be empty).

#### `ping`

```json
{
  "zen":          "<GitHub zen quote>",
  "hook_id":      42,
  "hook":         {
    "type":        "Repository",
    "id":          42,
    "active":      true,
    "events":      ["*"],
    "config":      { "url": "<confusio receiver URL>", "content_type": "json" },
    "created_at":  "<iso8601>",
    "updated_at":  "<iso8601>"
  },
  "repository":   { ... },
  "sender":       { ... }
}
```

Confusio emits `ping` only when an analogous upstream source emits a ping-style event.
Startup target configuration does not produce a ping; targets are static and there is
no runtime registration handshake.

#### `fork`

```json
{
  "forkee":     {
    "id":           99,
    "name":         "myrepo",
    "full_name":    "bob/myrepo",
    "private":      false,
    "html_url":     "<url>",
    "description":  "<string or null>",
    "owner":        { ... }
  },
  "repository": { ... },
  "sender":     { ... }
}
```

`forkee` is the newly created fork (owned by the forker); `repository` is the upstream
source repository.

#### `status`

```json
{
  "id":          12345678,
  "sha":         "<commit sha>",
  "name":        "alice/myrepo",
  "state":       "success",
  "description": "<string or null>",
  "target_url":  "<url or null>",
  "context":     "ci/test",
  "created_at":  "<iso8601>",
  "updated_at":  "<iso8601>",
  "commit":      {
    "sha":     "<sha>",
    "html_url": "<url>",
    "author":  { ... },
    "committer": { ... }
  },
  "branches":    [
    { "name": "main", "commit": { "sha": "<sha>", "url": "<url>" }, "protected": false }
  ],
  "repository":  { ... },
  "sender":      { ... }
}
```

`state` values: `"pending"`, `"success"`, `"failure"`, `"error"`.

`context` identifies the status reporter (e.g. `"ci/build"`, `"security/scan"`).
`target_url` links to the CI run; `description` is a short human-readable summary.

#### `member`

```json
{
  "action":   "added",
  "member":   {
    "id":       7,
    "login":    "carol",
    "html_url": "<url>",
    "type":     "User"
  },
  "changes":    { },
  "repository": { ... },
  "sender":     { ... }
}
```

`changes` is populated for `"edited"` actions with before/after values of changed
fields (e.g. `{ "permission": { "from": "pull" } }`).  It is empty for `"added"` and
`"removed"`.

#### `membership`

```json
{
  "action":       "added",
  "scope":        "team",
  "member":       { "id": 7, "login": "carol", "html_url": "<url>", "type": "User" },
  "team":         {
    "id":               42,
    "name":             "backend-team",
    "slug":             "backend-team",
    "description":      "<string>",
    "privacy":          "closed",
    "permission":       "pull",
    "html_url":         "<url>",
    "members_url":      "<url>",
    "repositories_url": "<url>"
  },
  "organization": { ... },
  "sender":       { ... }
}
```

`scope` is always `"team"`.  GitBucket passes the payload through verbatim from its
GitHub-compatible webhook.  GitLab maps group-member events to this shape, using the
group as both the team stub and the organization; there are no sub-team IDs.

#### `organization`

```json
{
  "action":       "member_added",
  "organization": {
    "login":        "<string>",
    "id":           1,
    "description":  "<string>",
    "html_url":     "<url>",
    "type":         "Organization"
  },
  "membership":   {
    "user":   { ... },
    "role":   "member",
    "state":  "active"
  },
  "sender": { ... }
}
```

`membership` is present for `member_added`, `member_invited`, and `member_removed`
actions; absent for `created`, `deleted`, and `renamed`.  For `renamed`, confusio
includes `changes.login.from` with the old organization login.  GitBucket passes the
payload through verbatim.  GitLab maps group lifecycle events to this shape via System
Hook; `sender` fields are empty stubs because GitLab System Hook payloads do not
include an actor.

#### `team`

```json
{
  "action":       "created",
  "team":         {
    "id":               42,
    "name":             "backend-team",
    "slug":             "backend-team",
    "description":      "<string>",
    "privacy":          "closed",
    "permission":       "pull",
    "html_url":         "<url>",
    "members_url":      "<url>",
    "repositories_url": "<url>"
  },
  "organization": { ... },
  "repository":   { ... },
  "sender":       { ... }
}
```

`repository` is present for `added_to_repository`, `removed_from_repository`, and
`edited` actions that affect repository access; absent for `created` and `deleted`.
GitBucket passes the payload through verbatim from its GitHub-compatible webhook.

#### `team_add`

```json
{
  "team":         {
    "id":               42,
    "name":             "backend-team",
    "slug":             "backend-team",
    "description":      "<string>",
    "privacy":          "closed",
    "permission":       "pull",
    "html_url":         "<url>",
    "members_url":      "<url>",
    "repositories_url": "<url>"
  },
  "repository":   { ... },
  "organization": { ... },
  "sender":       { ... }
}
```

There is no `action` field.  The event itself indicates that a team was granted access
to a repository.  GitBucket passes the payload through verbatim.

#### `commit_comment`

```json
{
  "action":   "created",
  "comment":  {
    "id":         9999,
    "body":       "<string>",
    "html_url":   "<url>",
    "path":       "<file path or null>",
    "position":   "<integer or null>",
    "line":       "<integer or null>",
    "commit_id":  "<sha>",
    "user":       { ... },
    "created_at": "<iso8601>",
    "updated_at": "<iso8601>"
  },
  "repository": { ... },
  "sender":     { ... }
}
```

`path`, `position`, and `line` are present when the comment is anchored to a specific
file and line; they are `null` for top-level commit comments.

#### `pull_request_review_comment`

```json
{
  "action":       "created",
  "comment":      {
    "id":                111,
    "body":              "<string>",
    "html_url":          "<url>",
    "path":              "<file path>",
    "position":          3,
    "original_position": 3,
    "diff_hunk":         "@@ -1,4 +1,6 @@\n ...",
    "commit_id":         "<sha>",
    "original_commit_id": "<sha>",
    "pull_request_review_id": 99,
    "user":              { ... },
    "created_at":        "<iso8601>",
    "updated_at":        "<iso8601>"
  },
  "pull_request": { ... },
  "repository":   { ... },
  "sender":       { ... }
}
```

#### `milestone`

```json
{
  "action":    "created",
  "milestone": {
    "id":           55,
    "number":       3,
    "title":        "v2.0",
    "description":  "<string or null>",
    "state":        "open",
    "html_url":     "<url>",
    "open_issues":  0,
    "closed_issues": 0,
    "due_on":       "<iso8601 or null>",
    "created_at":   "<iso8601>",
    "updated_at":   "<iso8601>",
    "closed_at":    "<iso8601 or null>",
    "creator":      { ... }
  },
  "repository": { ... },
  "sender":     { ... }
}
```

#### `label`

```json
{
  "action": "created",
  "label":  {
    "id":          22,
    "name":        "bug",
    "color":       "d73a4a",
    "description": "<string or null>",
    "default":     true,
    "url":         "<url>"
  },
  "changes":    { },
  "repository": { ... },
  "sender":     { ... }
}
```

`changes` is populated for `"edited"` action with before-values of changed fields
(e.g. `{ "name": { "from": "defect" }, "color": { "from": "ee0701" } }`).

#### `repository`

```json
{
  "action":     "created",
  "repository": { ... },
  "sender":     { ... }
}
```

The `repository` object carries the full repository schema for all actions.  For
`"renamed"`, `changes` is also present:

```json
{
  "action":     "renamed",
  "changes":    { "repository": { "name": { "from": "old-name" } } },
  "repository": { ... },
  "sender":     { ... }
}
```

#### `discussion`

```json
{
  "action":     "created",
  "discussion": {
    "id":               1,
    "node_id":          "<string>",
    "number":           1,
    "title":            "<string>",
    "body":             "<string>",
    "html_url":         "<url>",
    "state":            "open",
    "state_reason":     null,
    "locked":           false,
    "active_lock_reason": null,
    "comments":         0,
    "author_association": "OWNER",
    "answer_html_url":  null,
    "answer_chosen_at": null,
    "answer_chosen_by": null,
    "category": {
      "id":           1,
      "name":         "<string>",
      "slug":         "<string>",
      "description":  "<string>",
      "emoji":        ":<name>:",
      "is_answerable": false,
      "repository_id": 1,
      "created_at":   "<iso8601>",
      "updated_at":   "<iso8601>"
    },
    "user":        { "id": 1, "login": "<string>", ... },
    "labels":      [],
    "reactions":   { "url": "<url>", "total_count": 0, "+1": 0, "-1": 0, "laugh": 0, "confused": 0, "heart": 0, "hooray": 0, "eyes": 0, "rocket": 0 },
    "created_at":  "<iso8601>",
    "updated_at":  "<iso8601>"
  },
  "repository": { ... },
  "sender":     { ... }
}
```

Additional fields present for specific actions:

| Action | Extra field | Description |
|--------|-------------|-------------|
| `edited` | `changes.title.from` | Previous title (if title changed) |
| `edited` | `changes.body.from` | Previous body (if body changed) |
| `labeled` | `label` | The label that was applied |
| `unlabeled` | `label` | The label that was removed |
| `transferred` | `changes.new_repository` | The repository the discussion was transferred to |
| `category_changed` | `changes.category.from` | The previous discussion category |
| `answered` | `answer` | The comment that was marked as the answer |
| `unanswered` | `old_answer` | The comment that had previously been the answer |

#### `discussion_comment`

```json
{
  "action":     "created",
  "comment": {
    "id":                 1,
    "node_id":            "<string>",
    "html_url":           "<url>",
    "body":               "<string>",
    "discussion_id":      1,
    "parent_id":          null,
    "child_comment_count": 0,
    "author_association": "OWNER",
    "created_at":         "<iso8601>",
    "updated_at":         "<iso8601>",
    "user":               { "id": 1, "login": "<string>", ... },
    "reactions":          { "url": "<url>", "total_count": 0, "+1": 0, "-1": 0, "laugh": 0, "confused": 0, "heart": 0, "hooray": 0, "eyes": 0, "rocket": 0 }
  },
  "discussion": { ... },
  "repository": { ... },
  "sender":     { ... }
}
```

For the `"edited"` action, a `changes` object is also present:

```json
{
  "action":  "edited",
  "changes": { "body": { "from": "<previous body>" } },
  "comment": { ... },
  "discussion": { ... },
  "repository": { ... },
  "sender":  { ... }
}
```

### Edge cases

#### Tag push

When commits are pushed to a tag reference rather than a branch:

```json
{
  "ref":       "refs/tags/v1.2.3",
  "before":    "0000000000000000000000000000000000000000",
  "after":     "<sha>",
  "created":   true,
  "deleted":   false,
  "forced":    false,
  "commits":   [],
  "head_commit": { ... },
  "repository": { ... },
  "sender":    { ... }
}
```

`before` is all zeros when a tag is created for the first time.  `commits` is empty
for tag pushes — GitHub does not populate the commit list for tag events; use the
`create` event for tag creation notifications if you need metadata.

#### Force push

A force push sets `forced: true` and the `before` SHA is not an ancestor of `after`:

```json
{
  "ref":     "refs/heads/main",
  "before":  "<sha-of-overwritten-tip>",
  "after":   "<sha-of-new-tip>",
  "created": false,
  "deleted": false,
  "forced":  true,
  "commits": [ ... ],
  "repository": { ... },
  "sender":  { ... }
}
```

Consumers should check `forced` before computing diff ranges between `before` and
`after`.

#### Branch deletion via push

A branch delete arrives as a `push` event with `deleted: true` and `after` all zeros,
**and** as a separate `delete` event.  Consumers should handle both forms:

```json
{
  "ref":     "refs/heads/stale-branch",
  "before":  "<last-commit-sha>",
  "after":   "0000000000000000000000000000000000000000",
  "created": false,
  "deleted": true,
  "forced":  false,
  "commits": [],
  "head_commit": null,
  "repository": { ... },
  "sender":  { ... }
}
```

#### Merged pull request

A merged PR arrives as `pull_request` with `action: "closed"` and `merged: true`.
The merge commit SHA and merge timestamp are populated:

```json
{
  "action": "closed",
  "number": 7,
  "pull_request": {
    "state":            "closed",
    "merged":           true,
    "merged_at":        "2024-01-15T11:00:00Z",
    "merge_commit_sha": "abc123def456...",
    "merged_by":        { ... },
    "base": { "ref": "main", "sha": "<sha>", "repo": { ... } },
    "head": { "ref": "feature", "sha": "<sha>", "repo": { ... } }
  },
  "repository": { ... },
  "sender":     { ... }
}
```

Closed-without-merge: same shape but `merged: false`, `merged_at: null`,
`merge_commit_sha: null`, `merged_by: null`.

#### Labeled / unlabeled issue or PR

When `action` is `"labeled"` or `"unlabeled"`, a top-level `label` field identifies
the specific label that was added or removed:

```json
{
  "action": "labeled",
  "label":  { "id": 22, "name": "bug", "color": "d73a4a" },
  "issue":  { ... },
  "repository": { ... },
  "sender": { ... }
}
```

The same pattern applies to `pull_request` events with `action: "labeled"`.

#### Null / empty optional fields

Several commonly checked fields are legitimately absent or null:

| Field | When null/empty | Consumer implication |
|-------|----------------|---------------------|
| `issue.body` | Issue created with no description | Treat as empty string |
| `pull_request.body` | PR created with no description | Treat as empty string |
| `milestone` on issue/PR | Not assigned to a milestone | Check before accessing sub-fields |
| `commits[]` on push | Tag push or branch deletion | Do not assume non-empty |
| `head_commit` on push | Branch deletion | May be `null` |
| `review.body` on `pull_request_review` | Approve/request-changes with no comment | May be `null` or `""` |
| `comment.path` on `commit_comment` | Top-level commit comment | May be `null` |

### Required vs optional fields

The tables below use **R** (always present, non-null) and **O** (optional or nullable).

#### User / sender fields

| Field | R/O | Notes |
|-------|-----|-------|
| `id` | R | Integer |
| `login` | R | String |
| `html_url` | R | String |
| `type` | R | `"User"` or `"Organization"` |
| `avatar_url` | R | May point to a default avatar |
| `name` | O | Display name; not all forges expose this |

#### Repository fields

| Field | R/O | Notes |
|-------|-----|-------|
| `id` | R | Integer |
| `name` | R | Short name |
| `full_name` | R | `"owner/name"` |
| `private` | R | Boolean |
| `html_url` | R | String |
| `fork` | R | Boolean |
| `default_branch` | R | String |
| `owner` | R | User / org object |
| `description` | O | Null if no description set |
| `pushed_at` | O | Null on repos with no pushes; fallback = ingest time |

#### Issue fields

| Field | R/O | Notes |
|-------|-----|-------|
| `id` | R | Integer |
| `number` | R | Integer |
| `title` | R | String |
| `state` | R | `"open"` or `"closed"` |
| `html_url` | R | String |
| `user` | R | Author |
| `labels` | R | Array (may be empty) |
| `assignees` | R | Array (may be empty) |
| `body` | O | Null if no description |
| `milestone` | O | Null if not assigned |
| `closed_at` | O | Null when open |

#### Pull request fields

| Field | R/O | Notes |
|-------|-----|-------|
| `id` | R | Integer |
| `number` | R | Integer |
| `title` | R | String |
| `state` | R | `"open"` or `"closed"` |
| `html_url` | R | String |
| `user` | R | Author |
| `head` | R | Object with `ref`, `sha`, `repo` |
| `base` | R | Object with `ref`, `sha`, `repo` |
| `merged` | R | Boolean |
| `draft` | R | Boolean |
| `labels` | R | Array (may be empty) |
| `assignees` | R | Array (may be empty) |
| `body` | O | Null if no description |
| `merged_at` | O | Null until merged |
| `merge_commit_sha` | O | Null until merged |
| `merged_by` | O | Null until merged |
| `requested_reviewers` | O | May be absent if forge doesn't support it |
| `closed_at` | O | Null when open |

### Common object schemas

#### User / sender

```json
{
  "id":         1,
  "login":      "<username>",
  "name":       "<display name or null>",
  "avatar_url": "<url>",
  "html_url":   "<url>",
  "type":       "User"
}
```

#### Repository

```json
{
  "id":           12345,
  "name":         "<repo-name>",
  "full_name":    "<owner>/<repo-name>",
  "private":      false,
  "html_url":     "<url>",
  "description":  "<string or null>",
  "fork":         false,
  "default_branch": "main",
  "owner":        { ... },
  "created_at":   "<iso8601>",
  "updated_at":   "<iso8601>",
  "pushed_at":    "<iso8601>"
}
```

### Fidelity notes

Some fields cannot be sourced from all forge backends.  The following known gaps apply
across the emitted GitHub-shape payloads:

| Field / feature | Gap | Affected backends |
|----------------|-----|------------------|
| `commits[].added` / `removed` / `modified` | Most forges do not include per-file diff in push events; arrays may be empty | Varies by provider |
| `pull_request.requested_reviewers` | Only forges with native reviewer request events provide this | Varies |
| `release.tarball_url` / `zipball_url` | Emitted when the forge provides download URLs; `null` otherwise | Varies |
| `sender.name` | Not all forges expose the display name; may be `null` | Varies |
| `installation` / `installation_repositories` | Emitted only as confusio startup lifecycle events, not sourced from forge webhooks | All forge backends |
| `check_run` / `check_suite` | Not yet emitted in GitHub-emulation shape | All backends |
| `repository.pushed_at` | Forges without push timestamps emit the ingest arrival time | Varies |

Where a required field cannot be sourced, confusio uses a safe fallback (empty string,
`null`, or `0` as appropriate for the schema type) and logs the omission at debug level.
Consumers that strictly require all GitHub fields should verify their backend's
coverage in the [Field-Level Mapping Tables](#field-level-mapping-tables).

## Normalized Confusio Event Model

When a delivery target is configured for the confusio-normalized shape, confusio wraps
the internal event in a stable, forge-agnostic envelope.  This shape is designed for
consumers that want cross-forge portability without GitHub's legacy quirks — the same
schema works regardless of whether the originating forge is Gitea, GitLab, or Sourcehut.

### Design goals

- **Stable across forge versions** — field names and structure do not change when a
  forge adds or renames its native fields.  Backend-specific details remain inside
  the event-family payload.
- **Consistent with the internal event model** — the envelope is a thin wrapper around
  the internal representation defined in [Backend-agnostic internal model](#backend-agnostic-internal-model).
- **Orthogonal to the GitHub-emulation shape** — no GitHub-specific legacy (e.g.
  `X-Hub-Signature` vs `sha256=` prefix conventions); confusio defines its own naming.
- **Self-describing** — the envelope carries enough metadata for a consumer to route
  and deduplicate without inspecting the payload body.

### Delivery headers

Confusio sends the following HTTP headers with every confusio-normalized delivery:

| Header | Value | Notes |
|--------|-------|-------|
| `X-Confusio-Event` | confusio event family name (e.g. `issues`, `push`) | Always present |
| `X-Confusio-Delivery` | UUID v4, unique per delivery attempt | Always present |
| `X-Confusio-Source` | originating backend identifier (e.g. `gitea`, `gitlab`) | Always present |
| Provider-native signature header(s) | Backend-specific | Present when the outbound target has a secret; produced by the same signing helper used for GitHub-emulation deliveries |
| `Content-Type` | `application/json` | Always `application/json` |
| `User-Agent` | `confusio/1.0` | Same as GitHub-emulation deliveries |

**Signature computation:** Outbound signing is selected from the source backend, not
from the delivery shape.  For example, a `gitea` source signs with `X-Gitea-Signature`,
`gitlab` signs with `X-Gitlab-Token`, and `gitbucket` signs with `X-Hub-Signature`
using the GitBucket SHA-1 format.  If no target secret is configured, no signature
header is emitted.

**Action handling:** The action is represented in the JSON body through the dotted
`type` field, not as a separate header.  Action-less events such as `push`, `create`,
`delete`, and `fork` use the event family name alone as `type`.

### Namespace

Confusio uses two related names for each normalized delivery:

- The **event family** is the internal canonical key and the value of
  `X-Confusio-Event`, such as `issues`, `issue_comment`, `pull_request`, or `push`.
- The body **type** is the stable dotted event namespace, such as `issue.opened`,
  `issue.comment.created`, `pull_request.opened`, or `push`.

The event-family names match the GitHub event name set defined in
[Supported event names](#supported-event-names).  The dotted type is derived by
mapping the family to a normalized base name and appending the action when one exists.
For example, `issues` maps to `issue`, `issue_comment` maps to `issue.comment`, and
`pull_request_review` maps to `pull_request.review`.

### Envelope schema

Every confusio-normalized delivery body follows this structure:

```json
{
  "id":        "<uuid>",
  "type":      "<normalized dotted type>",
  "occurred_at": "<iso8601>",
  "actor":     { ... },
  "repository": { ... },
  "payload":   { ... }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `id` | string (UUID v4) | Unique outbound delivery ID; same value as `X-Confusio-Delivery` |
| `type` | string | Dotted normalized event type, for example `issue.opened` or `workflow.run.completed` |
| `occurred_at` | string | Event timestamp from the forge when available, otherwise the current confusio time |
| `actor` | object | Actor that triggered the event; usually from normalized `sender` data |
| `repository` | object | Repository associated with the event, or `{}` when the event has none |
| `payload` | object | Event-family-specific normalized payload |

The delivery source and event family are intentionally kept in headers rather than
duplicated in the body.  Consumers that route only by event family can use
`X-Confusio-Event`; consumers that need action-level routing should use `body.type`.

### The `payload` object

The `payload` object contains the normalized event payload.  Its schema is
event-family-specific and generally mirrors the provider-agnostic `data` bag produced
by the inbound webhook normalizer.  Backend translators remove envelope-level fields
such as `sender` and `repository` from the payload when those values are already
promoted to `actor` and `repository`.

Common examples:

| Event family | Example `type` | Payload fields |
|--------------|----------------|----------------|
| `issues` | `issue.opened` | `issue`, plus event-specific fields when available |
| `issue_comment` | `issue.comment.created` | `issue`, `comment` |
| `pull_request` | `pull_request.opened` | `pull_request` |
| `pull_request_review` | `pull_request.review.submitted` | `pull_request`, `review` |
| `workflow_run` | `workflow.run.completed` | `workflow_run` |
| `workflow_job` | `workflow.job.completed` | `workflow_job` |
| `push` | `push` | `ref`, `before`, `after`, `commits`, `head_commit`, and related push fields |

The field-level source coverage is documented in
[Field-Level Mapping Tables](#field-level-mapping-tables).

### Concrete delivery example

A complete outbound delivery for a confusio-normalized `issues:opened` event:

```http
POST /hooks/confusio-normalized HTTP/1.1
Host: consumer.example.com
Content-Type: application/json
X-Confusio-Event: issues
X-Confusio-Delivery: 72d3162e-cc78-11e3-81ab-4c9367dc0958
X-Confusio-Source: gitea
X-Gitea-Signature: a3b9f12c8d7e4f01bc6234567890abcd1234ef567890abcd1234ef567890abcd
User-Agent: confusio/1.0
Content-Length: 431

{ ... envelope body ... }
```

A delivery for an action-less event:

```http
POST /hooks/confusio-normalized HTTP/1.1
Host: consumer.example.com
Content-Type: application/json
X-Confusio-Event: push
X-Confusio-Delivery: 83e4273f-dd89-22f4-92bc-5d0478ed1069
X-Confusio-Source: gitlab
X-Gitlab-Token: <target-secret>
User-Agent: confusio/1.0
Content-Length: 891

{ ... envelope body ... }
```

### Concrete envelope example

A `issues:opened` event originating from Gitea:

```json
{
  "id": "72d3162e-cc78-11e3-81ab-4c9367dc0958",
  "type": "issue.opened",
  "occurred_at": "2024-01-15T10:00:00Z",
  "actor": {
    "id": 1,
    "login": "alice",
    "source_url": "https://gitea.com/alice"
  },
  "repository": {
    "id": 100,
    "name": "myrepo",
    "full_name": "alice/myrepo",
    "private": false,
    "source_url": "https://gitea.com/alice/myrepo",
    "description": null,
    "fork": false,
    "default_branch": "main",
    "owner": {
      "id": 1,
      "login": "alice"
    },
    "created_at": "2023-01-01T00:00:00Z",
    "updated_at": "2024-01-15T10:00:00Z",
    "pushed_at": "2024-01-15T10:00:00Z"
  },
  "payload": {
    "issue": {
      "id": 1,
      "number": 42,
      "title": "Found a bug",
      "body": "Something broke.",
      "state": "open",
      "source_url": "https://gitea.com/alice/myrepo/issues/42",
      "author": {
        "id": 1,
        "login": "alice",
        "source_url": "https://gitea.com/alice"
      },
      "labels": [],
      "assignees": [],
      "milestone": null,
      "created_at": "2024-01-15T10:00:00Z",
      "updated_at": "2024-01-15T10:00:00Z",
      "closed_at": null
    }
  }
}
```

### Translator contract

Backend files register confusio-shape translators with
`b:webhook_translator(event, fn)`.  The event key is the internal event family name.
The function is called as:

```lua
translator(internal_event, fields) -> envelope_table
```

`internal_event` is the table returned by the backend's inbound webhook normalizer.
`fields` carries delivery-time overrides, currently including the outbound delivery
`id`.  Translators should call `make_normalized_webhook_envelope(internal_event,
fields)` and override only the fields whose source data needs backend-specific
handling.

The shared envelope helper applies these defaults:

| Envelope field | Default source |
|----------------|----------------|
| `id` | `fields.id`, otherwise a generated UUID |
| `type` | `normalized_webhook_event_type(internal_event.event, internal_event.action)` |
| `occurred_at` | `fields.occurred_at`, then `internal_event.timestamp`, then current confusio time |
| `actor` | `fields.actor`, then `data.actor`, `data.sender`, `raw.sender`, then `{}` |
| `repository` | `fields.repository`, then `data.repository`, `raw.repository`, then `{}` |
| `payload` | `fields.payload`, then `data.payload`, then the full `data` bag |

Provider translators normally use the helper but remove envelope-level values from
`payload` so `actor` and `repository` are not duplicated.  They may also normalize
action-less events by forcing an empty action when deriving `type`.

### Fallback behavior

If no backend translator is registered for an event, or the registered translator does
not return a table, confusio falls back to `make_normalized_webhook_envelope` with the
internal event.  This means a target configured with `webhook_target_shape=confusio`
still receives a valid envelope even while a backend has partial translator coverage.

The fallback is intentionally conservative:

- It preserves the canonical event family through `X-Confusio-Event`.
- It derives the dotted body `type` from the internal event and action.
- It keeps the full normalized `data` bag as `payload` when no provider-specific
  payload pruning exists.
- It falls back to the original raw `sender` and `repository` objects when the
  normalized data bag does not provide promoted envelope fields.

### Actor schema

The top-level `actor` object and user/actor objects inside `payload` use a
confusio-specific schema that differs from the GitHub-emulation shape:

**Confusio-normalized actor:**
```json
{
  "id":           1,
  "login":        "alice",
  "display_name": "Alice Smith",
  "source_url":   "https://gitea.com/alice",
  "avatar_url":   "https://gitea.com/user/avatar/alice"
}
```

**GitHub-emulation actor (for comparison):**
```json
{
  "id":         1,
  "login":      "alice",
  "name":       "Alice Smith",
  "avatar_url": "https://gitea.com/user/avatar/alice",
  "html_url":   "https://gitea.com/alice",
  "type":       "User"
}
```

| confusio field | GitHub-emulation field | Notes |
|----------------|----------------------|-------|
| `id` | `id` | Same |
| `login` | `login` | Same |
| `display_name` | `name` | Renamed to avoid ambiguity with repo `name` |
| `source_url` | `html_url` | Renamed to clarify it points to the originating forge |
| `avatar_url` | `avatar_url` | Same; may be `null` if forge does not provide one |
| _(absent)_ | `type` | Not present in confusio shape; `"User"` vs `"Organization"` is inferred from context |

**Naming convention — `author` vs `user`:** In GitHub webhook bodies the issue/PR
creator field is `user` (which is ambiguous — it could refer to anyone).  Confusio
uses `author` for the resource creator and `sender` for the actor who triggered the
webhook event.  These may be different people (e.g. someone else closes your issue).

### Consistency with GitHub-emulation contract

The following table maps each confusio-normalized header to its GitHub-emulation
equivalent.  Where both shapes carry the same semantic, consumers can share
verification code with a simple header-name substitution.

| Confusio-normalized header | GitHub-emulation equivalent | Same value? |
|---------------------------|----------------------------|-------------|
| `X-Confusio-Event` | `X-GitHub-Event` | Yes — same event family names |
| `X-Confusio-Delivery` | `X-GitHub-Delivery` | Yes — both are UUID v4 |
| `X-Confusio-Source` | _(absent)_ | No GitHub equivalent |
| Provider-native signature header(s) | Provider-native signature header(s) | Same signing helper, using the target secret |
| `Content-Type` | `Content-Type` | Same |
| `User-Agent` | `User-Agent` | Same (`confusio/1.0`) |

**Key differences to call out to consumer authors:**

1. The action is encoded in the confusio body `type`; GitHub-emulation keeps it in the
   JSON body's `action` field.
2. `X-Confusio-Source` has no GitHub equivalent; use it to route events by source
   forge without inspecting the body.
3. The confusio body is an envelope with `id`, `type`, `occurred_at`, `actor`,
   `repository`, and `payload`; GitHub-emulation forwards GitHub-compatible webhook
   payloads.
4. Provider-native signature headers are reused for both shapes.  Consumers should
   verify the header scheme associated with `X-Confusio-Source`.
5. `source_url` in normalized payload objects corresponds to `html_url` in the
   GitHub-emulation shape — same URL, different key name.
6. `author` in normalized payload objects corresponds to `user` in the
   GitHub-emulation issue/PR objects.

## Field-Level Mapping Tables

Field-level mapping tables specify, for each event family, which GitHub-emulation
output fields can be sourced from each backend and at what fidelity.  The confusio
normalized shape uses the same source data; differences are noted where the output
field name or structure changes.  Some historical tables include a `github` reference
column for GitHub-native payload behavior; `github` is a compatibility reference here,
not a supported upstream provider for this provider-bound PR.

### How to read these tables

**Coverage symbols:**

| Symbol | Meaning |
|--------|---------|
| ✓ | Native: field is available directly from the forge webhook payload |
| ~ | Partial: field is approximated, synthesized, or available only on some versions |
| ✗ | Not available: field is always empty, `[]`, `null`, or `0` in the output |
| — | Not applicable: the event type does not exist for this backend |

**Stub values for `✗` fields:**

When a field cannot be sourced from the originating forge, confusio emits the following
stub in GitHub-emulation output to satisfy the schema contract:

| GitHub field type | Stub value |
|------------------|------------|
| Nullable string | `null` |
| Non-nullable string | `""` |
| Integer | `0` |
| Boolean | `false` |
| Array | `[]` |
| Object | `null` |

In confusio-normalized output, unavailable fields are **omitted** from the `data` object
rather than stubbed.  This keeps normalized payloads compact and allows consumers to
distinguish "not available" from "explicitly empty."

Fields marked `~` carry an inline note or a **Notes** annotation explaining the
approximation strategy and the fallback stub when the approximation is not possible.

**Backend grouping:** Backends in the same API family share the same implementation
and therefore the same coverage.  Where a whole family shares a symbol, the family
name is used instead of listing individual backends.

| Family | Members |
|--------|---------|
| gitea-family | `gitea`, `forgejo`, `codeberg` |
| gogs-family | `gogs`, `notabug` |
| bitbucket | `bitbucket` (Bitbucket Cloud) |
| bitbucket-dc | `bitbucket_datacenter` |
| gitlab | `gitlab` |
| github | reference only (GitHub-native payload behavior; not a supported upstream provider in this PR) |
| gitbucket | `gitbucket` |

Backends with independent implementations are listed individually.

### Generated action support matrix

Webhook event/action support is generated from the catalog exposed by
`scripts/dump-endpoints.lua` and `site/compatibility.csv`; update those source files
and regenerate this grid with:

```sh
./redbean.com -i scripts/dump-endpoints.lua | python3 scripts/gen-matrix.py --update-webhook-docs - site/compatibility.csv docs/webhooks.md
```

<!-- WEBHOOK_ACTION_SUPPORT_START -->
| Event | Action | Azure DevOps | Bitbucket | Bitbucket DC | Codeberg | CodeCommit | Forgejo | Gerrit | GitBlit | GitBucket | Gitea | GitLab | Gogs | Harness | Kallithea | Launchpad | NotABug | OneDev | Pagure | Phabricator | Radicle | RhodeCode | SourceForge | Sourcehut | Tuleap |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Create | `create` | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | ✓ | ✓ | ✓ |
| Custom Property | `created` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `deleted` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `updated` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Custom Property Values | `updated` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Commit Comments | `created` | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Delete | `delete` | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | ✓ | ✓ | ✓ |
| Discussions | `answered` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `category_changed` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `closed` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `created` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `deleted` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `edited` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `labeled` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `locked` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `pinned` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `reopened` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `transferred` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `unanswered` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `unlabeled` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `unlocked` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `unpinned` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Discussion Comments | `created` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `deleted` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `edited` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Fork | `fork` | ✗ | ✓ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Gollum | `created` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `edited` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Issues | `opened` | ✓ | ✓ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ |
|  | `closed` | ✓ | ✓ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ |
|  | `edited` | ✓ | ✓ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ |
|  | `reopened` | ✓ | ✓ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ |
|  | `labeled` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ |
|  | `unlabeled` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ |
|  | `assigned` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ |
|  | `unassigned` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ |
| Issue Comments | `created` | ✓ | ✓ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ |
|  | `edited` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `deleted` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Labels | `created` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ |
|  | `edited` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ |
|  | `deleted` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ |
| Member | `added` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `removed` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `edited` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Membership | `added` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `removed` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Merge Group | `checks_requested` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `destroyed` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Meta | `deleted` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Milestones | `created` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `closed` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `opened` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `edited` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `deleted` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `reopened` | ~ (reopen emits opened) | ✗ | ✗ | ✗ | ✗ | ~ (reopen emits opened) | ✗ | ✗ | ✗ | ✗ | ✗ | ~ (reopen emits opened) | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Organization | `created` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `deleted` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `renamed` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `member_added` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `member_invited` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `member_removed` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Package | `published` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `updated` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Page Build | `page_build` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Ping | `ping` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Pull Requests | `opened` | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | ✗ |
|  | `closed` | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `reopened` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `edited` | ✗ | ✗ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `synchronize` | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ |
|  | `labeled` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `unlabeled` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `assigned` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `unassigned` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `review_requested` | ✗ | ✗ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `review_request_removed` | ✗ | ✗ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| PR Reviews | `submitted` | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `edited` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `dismissed` | ✓ | ✓ | ✗ | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| PR Review Comments | `created` | ✗ | ✓ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `edited` | ✗ | ✓ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `deleted` | ✗ | ✓ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Push | `push` | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ |
| Release | `published` | ✓ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `edited` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `deleted` | ✓ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `prereleased` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Registry Package | `published` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `updated` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Repository | `created` | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ |
|  | `deleted` | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ |
|  | `edited` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ |
|  | `renamed` | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `transferred` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `publicized` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `privatized` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Commit Status | `pending` | ✗ | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `success` | ✗ | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `failure` | ✗ | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Team | `created` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `deleted` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `edited` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `added_to_repository` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `removed_from_repository` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Team Add | `team_add` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Workflow Run | `requested` | ✗ | ✓ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ |
|  | `in_progress` | ✗ | ✓ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ |
|  | `completed` | ✓ | ✓ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ |
| Workflow Job | `queued` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `in_progress` | ✗ | ✓ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `completed` | ✗ | ✓ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `waiting` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Deployment | `created` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Deployment Status | `created` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Deployment Review | `approved` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `rejected` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `requested` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Deployment Protection Rule | `requested` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Code Scanning Alert | `appeared_in_branch` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `closed_by_user` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `created` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `fixed` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `reopened` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `reopened_by_user` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `updated_assignment` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Dependabot Alert | `assignees_changed` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `auto_dismissed` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `auto_reopened` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `created` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `dismissed` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `fixed` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `reintroduced` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `reopened` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Secret Scanning Alert | `assigned` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `created` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `publicly_leaked` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `reopened` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `resolved` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `unassigned` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `validated` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Secret Scanning Alert Location | `created` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Security Advisory | `published` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `updated` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `withdrawn` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Repository Advisory | `published` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `reported` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Repository Vulnerability Alert | `create` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `dismiss` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `reopen` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `resolve` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Security And Analysis | `changed` | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Star | `created` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `deleted` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Watch | `started` | ✗ | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Sponsorship | `cancelled` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `created` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `edited` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `pending_cancellation` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `pending_tier_change` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `tier_changed` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Project | `closed` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `created` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ |
|  | `deleted` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `edited` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `reopened` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Project Card | `converted` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `created` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `deleted` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `edited` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `moved` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Project Column | `created` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `deleted` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `edited` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `moved` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Projects V2 | `closed` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `created` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `deleted` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `edited` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `reopened` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Projects V2 Item | `archived` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `converted` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `created` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `deleted` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `edited` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `reordered` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `restored` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Projects V2 Status Update | `created` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `deleted` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `edited` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Installation | `created` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `deleted` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `new_permissions_accepted` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `suspend` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `unsuspend` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Installation Repositories | `added` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `removed` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Installation Target | `renamed` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Github App Authorization | `revoked` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Personal Access Token Request | `approved` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `cancelled` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `created` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `denied` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Marketplace Purchase | `cancelled` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `changed` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `pending_change` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `pending_change_cancelled` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
|  | `purchased` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
<!-- WEBHOOK_ACTION_SUPPORT_END -->

---

### `push`

Triggered when one or more commits are pushed to a branch or tag.

#### Top-level fields

| GitHub field | gitea-family | gogs | gitlab | bitbucket | bitbucket-dc | github | gitbucket | azuredevops | gerrit | sourcehut | pagure | All others |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `ref` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `before` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `after` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `created` | ✓ | ✓ | ✓ | ~ | ~ | ✓ | ✓ | ~ | ✗ | ✓ | ✓ | ✗ |
| `deleted` | ✓ | ✓ | ✓ | ~ | ~ | ✓ | ✓ | ~ | ✗ | ✓ | ✓ | ✗ |
| `forced` | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| `compare` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✗ | ✗ | ✓ | ✗ |
| `commits` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ✓ | ~ |
| `head_commit` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ~ |
| `pusher` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ~ |

**Notes:**
- `created` / `deleted`: Bitbucket and Bitbucket Datacenter do not include these
  boolean flags directly; confusio derives them from `before` / `after` being all-zero
  (`0000000...`).
- `forced`: No forge other than Gitea-family, Gogs, GitLab, and GitBucket exposes a
  force-push flag in the webhook payload.  The field is always `false` for other
  backends even when a force push occurred.
- `compare`: Azure DevOps provides a compare URL in a non-standard field; confusio
  synthesizes it from the repository URL and SHAs.  Sourcehut does not provide a web
  compare URL.
- Gerrit `ref-updated` and `batch-ref-updated` events do not include commit lists or
  compare URLs; confusio emits an empty `commits` array, `head_commit: null`, and
  `compare: ""`.
- Radicle `push` requests carry branch or tag ref changes in the body `event_type:
  "push"` family.  Confusio forwards commit details when present and derives
  create/delete from all-zero `before` / `after` SHAs.
- SourceForge / Allura `repo-push` events do not include an event header.  Confusio
  infers the event from the body, forwards commit `id`, `url`, `timestamp`, and
  `message` when present, and derives create/delete from all-zero `before` /
  `after` SHAs.

#### `commits[]` fields

| GitHub field | gitea-family | gogs | gitlab | bitbucket | bitbucket-dc | github | gitbucket | azuredevops | sourcehut | pagure | All others |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `id` (SHA) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `message` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `timestamp` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `url` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `author.name` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `author.email` | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `author.username` | ✓ | ✓ | ~ | ✗ | ✗ | ✓ | ✓ | ~ | ✗ | ✗ | ✗ |
| `committer.name` | ✓ | ✓ | ~ | ✗ | ✗ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ |
| `committer.email` | ✓ | ✓ | ~ | ✗ | ✗ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ |
| `added` | ✗ | ✗ | ✓ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| `removed` | ✗ | ✗ | ✓ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| `modified` | ✗ | ✗ | ✓ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |

**Notes:**
- `author.email`: Bitbucket Cloud does not expose committer/author emails in webhook
  payloads.  The field is always `""`.
- `author.username`: GitLab provides a `username` in some versions; confusio uses
  `user_username` when available.  Most non-GitHub forges do not provide a platform
  username in the commit object.
- `committer.*`: Gitea-family includes committer in the commit object.  Most other
  forges include only the author.
- `added` / `removed` / `modified`: Only GitHub and GitLab include per-file diff lists
  in push events.  All other backends emit `[]` for these three fields.
- SourceForge / Allura documents commit `id`, `url`, `timestamp`, and `message`.
  Author, committer, and file lists are empty unless present in the delivered
  payload.

**Confusio-normalized differences:** In the confusio shape, `commits[].author` uses
the actor schema (`id`, `login`, `display_name`, `source_url`) rather than the git
identity schema (`name`, `email`, `username`).  Both the git identity and the platform
user object are included where available; the git identity is in `commits[].git_author`
and `commits[].git_committer`.

---

### `create` and `delete`

Triggered when a branch or tag is created or deleted.  Both events share the same
field structure.

| GitHub field | gitea-family | gogs | gitlab | bitbucket | bitbucket-dc | github | gitbucket | azuredevops | sourcehut | pagure | All others |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `ref` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `ref_type` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `master_branch` | ✓ | ✓ | ✓ | ~ | ~ | ✓ | ✓ | ~ | ✗ | ✗ | ✗ |
| `description` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✗ | ✓ | ✗ |
| `pusher_type` | ✓ | ✓ | ~ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ |

**Notes:**
- `ref`: For `delete`, the ref is the name of the deleted branch or tag.
- `master_branch`: Synthesized from the repository's default branch field when the
  forge does not include it directly in the create/delete event.
- `pusher_type`: Hardcoded to `"user"` when not provided by the forge; organizations
  and bots that push may not be accurately reflected on non-GitHub backends.
- Azure DevOps and Bitbucket: create/delete events arrive as push events with special
  before/after SHA patterns.  Confusio derives `ref_type` from the ref format
  (`refs/tags/` prefix = tag, otherwise branch).

**Backend-specific gaps:**
- `gerrit`: Gerrit `ref-updated` events become `create` or `delete` when `oldRev` or
  `newRev` is the all-zero SHA.
- `sourcehut`, `pagure`, `phabricator`, `launchpad`, `radicle`, `sourceforge`:
  Create/delete events may arrive embedded in a push event rather than as
  discrete event types.  Confusio splits them when the push `before` or `after`
  is all-zero.
- `codecommit`, `kallithea`, `rhodecode`: Create/delete events may not
  be delivered at all depending on forge configuration.  If no event is
  received, the `create` / `delete` event will not be emitted.
- `tuleap`: Create/delete events are derived from Git webhook payloads when the
  `before` or `after` SHA is all-zero.

---

### `fork`

Triggered when a repository is forked.

| GitHub field | gitea-family | gogs | gitlab | bitbucket | bitbucket-dc | github | gitbucket | azuredevops | All others |
|---|---|---|---|---|---|---|---|---|---|
| `forkee.id` | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `forkee.name` | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `forkee.full_name` | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `forkee.private` | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `forkee.html_url` | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `forkee.owner` | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✗ |

**Notes:**
- Fork events are common in open-source hosting forges (Gitea, GitLab, GitHub,
  Bitbucket) but are rarely sent by enterprise or self-hosted systems.
- Bitbucket Datacenter, Azure DevOps, and most "All others" backends do not emit fork
  events at all.  The `fork` event will not be delivered by confusio for these backends.
- When `forkee` fields cannot be sourced, confusio emits `null` for the `forkee`
  object and logs a warning.

---

### `repository`

Triggered on repository lifecycle events (created, deleted, renamed, etc.).

| GitHub field | gitea-family | gogs | gitlab | bitbucket | bitbucket-dc | gerrit | github | gitbucket | azuredevops | All others |
|---|---|---|---|---|---|---|---|---|---|---|
| `action` | ✓ | ~ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ✗ |
| `repository` | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ✓ | ✓ | ~ |
| `changes` (renamed/default branch) | ✓ | ✗ | ✓ | ~ | ✓ | ~ | ✓ | ✗ | ~ | ✗ |
| `sender` | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ✓ | ✓ | ~ |

**Supported actions:** See the generated [action support matrix](#generated-action-support-matrix).

**Notes:**
- Gogs does not send repository lifecycle webhooks.  The `repository` event is never
  emitted for `gogs`.
- GitBucket only emits repository events for create and delete, and only in newer
  versions.
- Gerrit maps `project-created` and `project-deleted` to repository `created` and
  `deleted`.  `project-head-updated` maps to `edited` and reports the old default
  branch under `changes.repository.default_branch.from`; Gerrit project lifecycle
  events often omit actor details, so `sender` may be empty.
- `changes` for `renamed`: Gitea-family includes a `changes` object with the old name.
  GitLab sends separate `rename` events with before/after fields.  Azure DevOps sends
  rename notifications via the service hook but without a structured `changes` payload.
- Kallithea emits repository create/delete hooks only.  Rename, visibility, transfer,
  and default-branch changes are not currently available from the Kallithea translator.
- Sourcehut emits `REPO_CREATED`, `REPO_UPDATE`, and `REPO_DELETED`; confusio maps
  those to `repository` `created`, `edited`, and `deleted`.
- Backends not listed (pagure, etc.) do not emit repository lifecycle events.
  Confusio cannot generate `repository` events from these backends.

---

### `gollum`

Triggered when a wiki page is created or edited.

There is no top-level `action` field on the event.  The `pages[]` array carries one entry per
modified wiki page; each entry has its own `action` field (`"created"` or `"edited"`).  Confusio
surfaces the first page's action as the internal routing action for filtering purposes.

| GitHub field | gitea-family | gogs | gitlab | bitbucket | bitbucket-dc | github | gitbucket | azuredevops | All others |
|---|---|---|---|---|---|---|---|---|---|
| `pages[]` | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `pages[].page_name` | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `pages[].title` | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `pages[].summary` | ✓ | ✗ | ~ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `pages[].action` | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `pages[].sha` | ✓ | ✗ | ~ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `pages[].html_url` | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `repository` | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `sender` | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ |

**Supported actions:** See the generated [action support matrix](#generated-action-support-matrix).

**Notes:**
- GitLab sends wiki events via `X-Gitlab-Event: Wiki Page Hook` with `object_kind = "wiki_page"`.
  The `object_attributes.action` values are `"create"` and `"update"`, mapped to `"created"` and
  `"edited"` respectively.
- `pages[].summary`: Gitea passes this through as-is (often `null`); GitLab maps
  `object_attributes.message` (the commit message) into `summary`.
- `pages[].sha`: Gitea provides the commit SHA directly; GitLab maps `object_attributes.version_id`.
- Gogs, Bitbucket, Bitbucket DC, and Azure DevOps do not emit wiki webhook events.

---

### `deploy_key`

Triggered when an SSH deploy key is added to or removed from a repository.

| GitHub field | gitea-family | gogs | gitlab | bitbucket | bitbucket-dc | github | gitbucket | azuredevops | All others |
|---|---|---|---|---|---|---|---|---|---|
| `action` | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `key.id` | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `key.key` | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `key.url` | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `key.title` | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `key.verified` | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `key.created_at` | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `key.read_only` | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `repository` | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `sender` | ✓ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ |

**Supported actions:** See the generated [action support matrix](#generated-action-support-matrix).

**Notes:**
- GitLab, Bitbucket, Bitbucket DC, Gogs, and Azure DevOps do not emit deploy key webhook events.
- Gitea sends deploy key events via `X-Gitea-Event: deploy_key`.
- GitBucket sends them via `X-GitHub-Event: deploy_key` with GitHub-compatible payload.

---

### `public`

Triggered when a private repository is made public.  There is no `action` field on this event;
the event itself signals the visibility change.  Confusio synthesizes `action = "publicized"` for
internal routing and filtering purposes.

| GitHub field | gitea-family | gogs | gitlab | bitbucket | bitbucket-dc | github | gitbucket | azuredevops | All others |
|---|---|---|---|---|---|---|---|---|---|
| `repository` | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `sender` | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ |

**Notes:**
- Gitea-family backends use the `repository` event with `action = "publicized"` instead of a
  standalone `public` event.  Confusio emits `repository/publicized` from Gitea, not `public`.
- GitLab, Bitbucket, Bitbucket DC, Gogs, and Azure DevOps do not emit a `public` event.
- GitBucket sends this event via `X-GitHub-Event: public` with GitHub-compatible payload.

---

### `issues`

Triggered on issue lifecycle events.

#### Issue object fields

| GitHub field | gitea-family | gogs | gitlab | bitbucket | bitbucket-dc | github | gitbucket | azuredevops | pagure | All others |
|---|---|---|---|---|---|---|---|---|---|---|
| `id` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `number` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `title` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `body` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `state` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `html_url` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `user` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `labels` | ✓ | ✓ | ✓ | ~ | ~ | ✓ | ✓ | ✗ | ✓ | ✗ |
| `assignees` | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ |
| `milestone` | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ |
| `created_at` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `updated_at` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `closed_at` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ✗ |

#### Supported actions by backend

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- `labels`: Bitbucket Cloud includes label names but not label colors or IDs.
  Bitbucket Datacenter has limited label support depending on version.
- `assignees`: Bitbucket Cloud does not support issue assignees in webhooks.
- `closed_at`: Azure DevOps includes a resolution date but the format differs;
  confusio normalizes to ISO 8601.
- `edited` action: For most backends, the edit event does not include a `changes`
  object (before/after values).  GitHub and GitLab include `changes`; others do not.
  Confusio emits `changes: {}` when not available.
- Sourcehut ticket hooks map to `issues` events.  Direct ticket create/update
  hooks produce `opened` and `edited`; ticket activity hooks produce `closed`,
  `reopened`, `labeled`, `unlabeled`, `assigned`, and `unassigned`.
- Backends not listed (gerrit, harness, rhodecode, etc.) do not emit issue
  lifecycle events.

---

### `issue_comment`

Triggered when a comment is created, edited, or deleted on an issue or pull request.

| GitHub field | gitea-family | gogs | gitlab | bitbucket | bitbucket-dc | github | gitbucket | pagure | All others |
|---|---|---|---|---|---|---|---|---|---|
| `comment.id` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `comment.body` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `comment.html_url` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `comment.user` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `comment.created_at` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `comment.updated_at` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `issue` (full object) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |

#### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- GitLab distinguishes note events on issues (`Note Hook`) from notes on PRs
  (`Merge Request Hook`).  Confusio maps both to `issue_comment` with the appropriate
  `issue` or `pull_request` context object in the body.
- `issue` object: Most backends include the parent issue in the comment event.
  When the forge omits the issue body, confusio back-fetches it via the REST API
  if configured.

---

### `pull_request`

Triggered on pull request lifecycle events.

#### Pull request object fields

| GitHub field | gitea-family | gogs | gitlab | bitbucket | bitbucket-dc | github | gitbucket | azuredevops | pagure | All others |
|---|---|---|---|---|---|---|---|---|---|---|
| `id` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `number` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `title` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `body` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ~ |
| `state` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `html_url` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `user` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `head.ref` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `head.sha` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `head.repo` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ~ |
| `base.ref` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `base.sha` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ~ |
| `base.repo` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `merged` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `merged_at` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ~ |
| `merge_commit_sha` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ~ | ✗ |
| `merged_by` | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✗ | ~ | ✗ | ✗ |
| `draft` | ✓ | ✗ | ✓ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ |
| `labels` | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ |
| `assignees` | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ |
| `requested_reviewers` | ✓ | ✗ | ✓ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ |
| `created_at` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `updated_at` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `closed_at` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ~ |

#### Supported actions by backend

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- `merged_by`: Gitea-family includes the user who merged.  GitHub always includes it.
  Gogs, Bitbucket, GitBucket do not expose the merger separately; confusio emits `null`.
- `draft`: Gogs, Bitbucket Cloud, GitBucket, and Azure DevOps do not have a draft PR
  concept; the field is always `false`.
- `requested_reviewers`: Only forges with native reviewer request events include this.
  Confusio emits `[]` when not available.
- `synchronize` action: Triggered when new commits are pushed to the PR branch.  All
  major forges support this; minor/self-hosted forges may not emit it.
- GitLab uses the term "merge request" rather than "pull request".  Confusio maps all
  GitLab `Merge Request Hook` events to the `pull_request` event family.
- **Pagure**: Uses "pull request" terminology.  `body` is synthesized from the initial
  comment on the PR.  `base.sha`, `merged_at`, and `closed_at` are not included in
  Pagure's webhook payloads; confusio emits `null`.  `merge_commit_sha` is available only
  after merge via the `commit_stop` field.  `synchronize` maps to Pagure's `updated`
  event.  `edited` maps to `comment added` on the PR description; not all edit
  scenarios produce a confusio `edited` event.
- **Radicle**: Patch events arrive as `event_type: "patch"`.  Confusio maps
  `action: "created"` to `pull_request.opened` and `action: "updated"` to
  `pull_request.synchronize`.  Closed, reopened, review, label, assignee, and reviewer
  request actions are not emitted by the current Radicle adapter.

---

### `pull_request_review`

Triggered when a review is submitted or dismissed on a pull request.

| GitHub field | gitea-family | gitlab | bitbucket | bitbucket-dc | azuredevops | gerrit | github | gitbucket | All others |
|---|---|---|---|---|---|---|---|---|---|
| `review.id` | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ |
| `review.body` | ✓ | ✓ | ✗ | ✓ | ✗ | ✓ | ✓ | ✓ | ✗ |
| `review.state` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| `review.html_url` | ✓ | ✓ | ✗ | ~ | ✗ | ✗ | ✓ | ✓ | ✗ |
| `review.user` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| `review.submitted_at` | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ✓ | ✗ |
| `pull_request` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |

#### `review.state` mapping

| Forge state | GitHub `review.state` |
|-------------|----------------------|
| Gitea `APPROVED` | `"approved"` |
| Gitea `REQUEST_CHANGES` | `"changes_requested"` |
| Gitea `COMMENT` | `"commented"` |
| GitLab `approved` | `"approved"` |
| GitLab `unapproved` | `"dismissed"` |
| GitLab `commented` | `"commented"` |
| Bitbucket Cloud `approved` | `"approved"` |
| Bitbucket Cloud `changes_request_created` | `"changes_requested"` |
| Bitbucket Cloud `unapproved` | `"dismissed"` |
| Bitbucket Cloud `changes_request_removed` | `"dismissed"` |
| Bitbucket DC `APPROVED` | `"approved"` |
| Bitbucket DC `NEEDS_WORK` | `"changes_requested"` |
| Azure DevOps vote 10 (approved) | `"approved"` |
| Azure DevOps vote 5 (approved with suggestions) | `"approved"` |
| Azure DevOps vote 0 (no vote / reset) | `"dismissed"` |
| Azure DevOps vote -5 (waiting for author) | `"changes_requested"` |
| Azure DevOps vote -10 (rejected) | `"changes_requested"` |
| Gerrit Code-Review +1 or +2 | `"approved"` |
| Gerrit Code-Review -1 or -2 | `"changes_requested"` |
| Gerrit Code-Review 0 or no score | `"commented"` |

#### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- `pull_request_review` events require the forge to have a native review/approval
  system that emits a discrete webhook event for review submissions.  Backends not
  listed in the table above do not emit this event and have no handler registered;
  they are documented individually below.
- GitBucket 4.32+ emits `pull_request_review` in GitHub-compatible format.
  All fields are passed through without translation.
- Bitbucket Cloud emits `pullrequest:approved` (→ `submitted / APPROVED`),
  `pullrequest:changes_request_created` (→ `submitted / CHANGES_REQUESTED`),
  `pullrequest:unapproved` (→ `dismissed / DISMISSED`), and
  `pullrequest:changes_request_removed` (→ `dismissed / DISMISSED`).  `review.id`,
  `review.body`, and `review.html_url` are always empty because Bitbucket Cloud's
  approval/change-request events do not carry a review object.
- `dismissed` action: Gitea marks a dismissed review by changing state; confusio
  synthesizes the `dismissed` action from a state transition to `dismissed`.  GitLab
  and Bitbucket Cloud support explicit dismissal.  Bitbucket Datacenter does not.
- `review.html_url`: Bitbucket Datacenter does not provide a direct URL to the review;
  confusio constructs an approximate URL from the PR URL.
- Azure DevOps emits `git.pullrequest.reviewervote` when a reviewer's vote changes.
  Vote 10 and 5 → `APPROVED`; vote -5 and -10 → `CHANGES_REQUESTED`; vote 0 (reset)
  → `dismissed / DISMISSED`.  `review.id`, `review.body`, and `review.html_url` are
  always empty because the ADO vote event carries no review body or direct URL.
- Gerrit emits `comment-added` events when a reviewer scores a change and
  `vote-deleted` events when a score is removed.  The `approvals` array is inspected
  for the `Code-Review` label; scores +1 or +2 map to `APPROVED`, -1 or -2 map to
  `CHANGES_REQUESTED`, and 0 or no score maps to `COMMENTED`.  `comment-added` emits
  `submitted`; `vote-deleted` emits `dismissed`.  `review.id` and `review.html_url`
  are always empty.  `review.submitted_at` is derived from `patchSet.createdOn` for
  submitted reviews, or from the event timestamp for dismissed reviews.
- **Phabricator** does not emit discrete `pull_request_review` webhook events.
  Phabricator Hermes webhooks deliver generic object-changed notifications keyed by
  `object.type` (e.g., `DREV` for differential revisions), not action-typed review
  events.  Accept/reject/request-changes actions on a differential do not produce a
  separate review payload; no handler is registered.
- **OneDev** does not emit a dedicated pull-request review webhook event.  OneDev's
  webhook system sends generic `PullRequestChanged` notifications when a reviewer's
  status changes; it does not produce a separate reviewer-vote event with a distinct
  event type.  No handler is registered.
- **Sourcehut** has no GitHub-style pull-request review model.  Code review on
  Sourcehut is conducted via mailing-list patch series (lists.sr.ht); patchset
  receipt maps to `pull_request.opened`, but review submission/dismissal events
  are not emitted.  No review handler is registered.
- **Pagure** does not emit a discrete pull-request review webhook event.  Pagure's
  webhook system covers PR lifecycle (opened, updated, closed) but has no separate
  reviewer-approval or review-submission event.  No handler is registered.
- **Gogs** has a minimal webhook system with no code-review feature.  Gogs does not
  emit pull-request review events.  No handler is registered.
- **Gitblit** has a basic webhook system (push notifications only) with no pull-request
  or review model.  No handler is registered.
- **Kallithea** has a basic webhook system with no pull-request review event.  No
  handler is registered.
- **RhodeCode** (Community Edition) webhooks cover push and repository events; the
  pull-request model does not include a discrete reviewer-vote or review-submission
  event.  No handler is registered.
- **Tuleap** has a pull-request module with review/approval, but its webhook system
  emits generic `pullrequest:update` notifications rather than discrete review events.
  No handler is registered.
- **CodeCommit** webhooks are delivered via Amazon EventBridge/SNS; the basic PR events
  do not include a reviewer-approval payload — code review is surfaced through
  CodeGuru Reviewer as a separate service.  No handler is registered.
- **Harness** is a CI/CD platform whose webhook system covers pipeline and build events;
  it does not emit pull-request review events.  No handler is registered.
- **Launchpad** uses Bazaar merge proposals rather than pull requests, and its webhook
  system does not emit reviewer-approval events.  No handler is registered.
- **SourceForge** has a basic webhook system (push notifications) with no pull-request
  review model.  No handler is registered.
- **Radicle** is a peer-to-peer forge.  Patch proposals have a review/revision concept,
  but Radicle's event system does not emit a discrete reviewer-approval webhook event.
  No handler is registered.

---

### `pull_request_review_comment`

Triggered when a comment is added, edited, or deleted on a pull request review diff.

| GitHub field | gitea-family | gitlab | bitbucket | github | All others |
|---|---|---|---|---|---|
| `comment.id` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `comment.body` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `comment.path` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `comment.position` | ~ | ~ | ~ | ✓ | ✗ |
| `comment.original_position` | ~ | ~ | ~ | ✓ | ✗ |
| `comment.diff_hunk` | ✓ | ✓ | ✗ | ✓ | ✗ |
| `comment.commit_id` | ✓ | ✓ | ✗ | ✓ | ✗ |
| `comment.original_commit_id` | ~ | ~ | ✗ | ✓ | ✗ |
| `comment.pull_request_review_id` | ✓ | ✓ | ✗ | ✓ | ✗ |
| `comment.user` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `comment.html_url` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `comment.created_at` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `comment.updated_at` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `pull_request` | ✓ | ✓ | ✓ | ✓ | ✗ |

#### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- Bitbucket Cloud emits `pullrequest:comment_created`, `pullrequest:comment_updated`, and
  `pullrequest:comment_deleted`.  Inline pull-request comments map to
  `pull_request_review_comment`; top-level pull-request comments map to `issue_comment`.
- `comment.position`: GitHub uses a position index within the diff hunk.  Gitea, GitLab,
  and Bitbucket Cloud use line numbers instead.  Confusio maps the line number to `position`
  as a best-effort approximation; the value may not match GitHub's exact position encoding.
  Stub: `null` when approximation is not possible.
- `comment.original_position`: The position in the original diff before any force-pushes.
  Gitea, GitLab, and Bitbucket Cloud provide line-number equivalents; confusio applies the
  same approximation as `position`.  Stub: same as `position` when unavailable.
- `comment.original_commit_id`: The commit SHA at which the comment was originally placed,
  before any subsequent force-push moved the head.  Gitea and GitLab provide this in some
  versions; confusio falls back to `commit_id` when absent.
- `comment.pull_request_review_id`: The enclosing review's ID.  Gitea and GitLab include
  this in their review comment payloads.  Bitbucket Cloud comment events are not nested
  under a review object, so the field is `null`.
- Bitbucket Cloud does not provide GitHub-style diff hunks or commit IDs on pull-request
  comment webhooks; those fields are emitted as `null`.
- Most forges do not expose diff-level review comments in webhooks.  Backends not
  listed always emit `✗` for this event.

---

### `merge_group`

Triggered on merge queue activity.  GitHub groups pull requests in a merge queue into
merge groups to be tested and merged together.  This event fires when a group is created
(checks must pass before merging) or destroyed (merged, removed from queue, or invalidated
by an earlier entry being dequeued).

No equivalent native event exists in Gitea, Forgejo, GitLab, or other self-hosted backends.
Confusio emits `merge_group` only when the originating backend sends it; for the
gitea-family this requires a Forgejo version with merge-queue support or a future Gitea
release that introduces the feature.

#### Merge group object fields

| GitHub field | gitea-family | All others |
|---|---|---|
| `merge_group.head_sha` | ✓ | ✗ |
| `merge_group.head_ref` | ✓ | ✗ |
| `merge_group.base_sha` | ✓ | ✗ |
| `merge_group.base_ref` | ✓ | ✗ |
| `merge_group.head_commit` | ✓ | ✗ |

#### Supported actions by backend

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- `checks_requested`: Fired when a merge group is formed and checks must pass before the
  group can be merged into the base branch.
- `destroyed`: Fired when a merge group is removed from the queue.  The top-level `reason`
  field indicates why: `"merged"` (successfully merged), `"dequeued"` (pull request manually
  removed from the queue), or `"invalidated"` (an earlier queue entry was dequeued, making
  this group stale).  The `reason` field is only present for the `destroyed` action.
- Backends not listed do not emit merge group events; confusio never generates `merge_group`
  for those backends regardless of queue configuration.

---

### `commit_comment`

Triggered when a comment is created directly on a commit (not a PR or review).

| GitHub field | gitea-family | gogs | gitlab | bitbucket | github | gitbucket | All others |
|---|---|---|---|---|---|---|---|
| `comment.id` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| `comment.body` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| `comment.commit_id` | ✓ | ✓ | ✓ | ~ | ✓ | ✓ | ✗ |
| `comment.path` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| `comment.position` | ~ | ~ | ~ | ~ | ✓ | ✓ | ✗ |
| `comment.line` | ~ | ~ | ~ | ~ | ✓ | ✓ | ✗ |
| `comment.user` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| `comment.html_url` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| `comment.created_at` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| `comment.updated_at` | ✓ | ~ | ✓ | ✓ | ✓ | ✓ | ✗ |

**Notes:**
- `position` and `line`: Gitea, Gogs, GitLab, and Bitbucket Cloud use line-number
  references; confusio maps these to `position` and `line` with a note that the encoding
  differs from GitHub's.  Stub: `null` when not available.
- Bitbucket Cloud emits `repo:commit_comment_created`.  It does not emit commit comment
  update/delete events; `comment.commit_id` is extracted from payload links when the SHA is
  not present as a first-class field.
- `comment.updated_at`: Gogs webhook payloads do not always include an update timestamp;
  confusio falls back to `created_at` when `updated_at` is absent.
- Backends not listed (Azure DevOps, etc.) do not emit commit comment events.

---

### `release`

Triggered on release lifecycle events.

#### Release object fields

| GitHub field | gitea-family | gitlab | github | gitbucket | azuredevops | All others |
|---|---|---|---|---|---|---|
| `release.id` | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| `release.tag_name` | ✓ | ✓ | ✓ | ✓ | ~ | ✗ |
| `release.name` | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| `release.body` | ✓ | ✓ | ✓ | ✓ | ~ | ✗ |
| `release.draft` | ✓ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `release.prerelease` | ✓ | ~ | ✓ | ✓ | ✗ | ✗ |
| `release.html_url` | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| `release.tarball_url` | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ |
| `release.zipball_url` | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ |
| `release.author` | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| `release.created_at` | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| `release.published_at` | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |

#### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- `release.draft`: GitLab has no concept of draft releases; the field is emitted as `false`.
- `release.prerelease`: GitLab has no native prerelease concept.  Confusio infers `prerelease`
  from the presence of a recognized suffix in the tag name (e.g. `-alpha`, `-beta`, `-rc`,
  `-pre`).  When no such suffix is present, `prerelease` is set to `false`.
- `prereleased` action: For gitea-family backends this action fires when a release with
  `prerelease: true` is created.  For GitLab it is emitted only when the tag suffix heuristic
  fires.  GitBucket does not distinguish prerelease releases.
- `edited` action: Does not include a `changes` object for gitea-family backends;
  confusio emits `changes: {}` as a stub.
- **Gogs**: Gogs has limited and version-dependent release webhook support.  Confusio
  normalizes `published`, `edited`, `deleted`, and `prereleased` when the Gogs instance
  emits those payloads.  Operators should verify their Gogs version supports release
  webhooks before relying on this event.
- **Azure DevOps**: Release-created service hooks map to `published`; release-abandoned
  service hooks map to `deleted`.  Azure DevOps releases are not Git tags, so
  `tag_name` is the release name and archive URLs are unavailable.
- Backends not listed (Bitbucket, etc.) do not emit release lifecycle events.

---

### `status`

Triggered when a commit status is created or updated.  This event is in the CI/CD category:
it carries the result of an external CI, security scan, or deployment check against a specific
commit SHA.

| GitHub field | github | gitbucket | gitlab | bitbucket | gitea-family | All others |
|---|---|---|---|---|---|---|
| `id` | ✓ | ✓ | ~ | ✗ | ~ | ✗ |
| `sha` | ✓ | ✓ | ✓ | ~ | ~ | ✗ |
| `name` | ✓ | ✓ | ~ | ✓ | ~ | ✗ |
| `state` | ✓ | ✓ | ✓ | ✓ | ~ | ✗ |
| `description` | ✓ | ✓ | ~ | ✓ | ~ | ✗ |
| `target_url` | ✓ | ✓ | ✓ | ✓ | ~ | ✗ |
| `context` | ✓ | ✓ | ~ | ✓ | ~ | ✗ |
| `created_at` | ✓ | ✓ | ✓ | ✓ | ~ | ✗ |
| `updated_at` | ✓ | ✓ | ✓ | ✓ | ~ | ✗ |
| `commit` | ✓ | ✓ | ~ | ✗ | ~ | ✗ |
| `branches` | ✓ | ✓ | ~ | ✗ | ✗ | ✗ |

**`state` mapping:**

| Forge state | GitHub `state` |
|-------------|---------------|
| `success` / `passed` | `success` |
| `failure` / `failed` | `failure` |
| `error` / `cancelled` | `error` |
| `pending` / `running` | `pending` |
| Bitbucket Cloud `SUCCESSFUL` | `success` |
| Bitbucket Cloud `FAILED` | `failure` |
| Bitbucket Cloud `INPROGRESS` | `pending` |

**Notes:**
- **GitHub / GitBucket**: Native `status` webhook events.  All fields present verbatim.
- **GitLab**: Pipeline events are mapped to `status`.  `id` is the pipeline ID.  `context` is
  synthesized as `"ci/<pipeline-name>"` or `"ci/<stage>/<job>"` for job-level events.  `name`
  is the repository full path.  `branches` is back-fetched via the REST API when the pipeline
  provides a `ref`; omitted on failure.
- **Bitbucket Cloud**: Commit status created/updated webhooks map to `status`.  `context`
  is the Bitbucket status key, `name` is the repository full name, and `sha` is extracted
  from the status payload or commit link when available.  Bitbucket Cloud does not include
  a GitHub-style `commit` object or branch list in the webhook payload.
- **gitea-family**: Gitea does not emit a dedicated commit status webhook.  Confusio synthesizes
  `status` events from Gitea's workflow/actions events when available — the `~` symbol reflects
  that synthesis requires Gitea Actions to be enabled and does not fire for external CI that
  only sets commit statuses via the API.  `id` is the workflow run ID.  `branches` is not
  available and is emitted as `[]` (stub).
- Backends not listed (Bitbucket DC, Azure DevOps, Pagure, etc.) do not produce
  events mappable to GitHub `status`.  All fields are `✗` (stub: type-appropriate null/empty).

---

### `member`

Triggered when a collaborator is added, removed, or has their permission changed on a repository.
This event is in the org/access-control category.

| GitHub field | github | gitbucket | gitea-family | gitlab | All others |
|---|---|---|---|---|---|
| `member.id` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `member.login` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `member.html_url` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `member.type` | ✓ | ✓ | ~ | ~ | ✗ |
| `changes` | ✓ | ✓ | ✗ | ~ | ✗ |

#### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- `member.type`: gitea-family always emits `"User"` (teams are not surfaced here).  GitLab
  emits the member's role (`"Reporter"`, `"Developer"`, etc.) in the `type` field; confusio
  normalizes to `"User"`.
- `changes`: Only populated for the `edited` action on GitHub and GitBucket.  GitLab
  Member Hook payloads can include changed access details for role updates; confusio
  preserves those when present and emits `changes: {}` otherwise.  gitea-family does not
  include permission change details and emits `changes: {}`.
- GitLab project member events are mapped to `member` with a synthetic `repository`
  constructed from the project path.
- Backends not listed do not emit collaborator lifecycle events.

---

### `membership`

Triggered when a user is added to or removed from a team.

| GitHub field | github | gitbucket | gitlab | All others |
|---|---|---|---|---|
| `scope` | ✓ | ✓ | ✓ | — |
| `member.id` | ✓ | ✓ | ✓ | — |
| `member.login` | ✓ | ✓ | ✓ | — |
| `member.html_url` | ✓ | ✓ | ✗ | — |
| `member.type` | ✓ | ✓ | ✓ | — |
| `team.id` | ✓ | ✓ | ~ | — |
| `team.name` | ✓ | ✓ | ✓ | — |
| `team.slug` | ✓ | ✓ | ✓ | — |
| `team.description` | ✓ | ✓ | ✗ | — |
| `team.privacy` | ✓ | ✓ | ~ | — |
| `team.permission` | ✓ | ✓ | ~ | — |
| `team.html_url` | ✓ | ✓ | ✗ | — |
| `organization` | ✓ | ✓ | ✓ | — |

#### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- GitBucket emits GitHub-compatible `membership` payloads; confusio passes them through verbatim.
- GitLab maps `user_add_to_group` / `user_remove_from_group` System Hook events.  GitLab
  groups have no sub-team concept; the group itself is used as the team stub and as the
  organization.  `team.id` is set to the group ID; `team.privacy` and `team.permission` are
  stub values (`"closed"`, `"pull"`).  `member.html_url` and `team.html_url` are empty because
  the System Hook payload does not include URLs.  `sender` fields are empty stubs.
- Backends not listed do not emit team-membership events.

---

### `organization`

Triggered on organization lifecycle events and org-level membership changes.

| GitHub field | github | gitbucket | gitlab | All others |
|---|---|---|---|---|
| `organization.login` | ✓ | ✓ | ✓ | — |
| `organization.id` | ✓ | ✓ | ✓ | — |
| `organization.description` | ✓ | ✓ | ✗ | — |
| `organization.html_url` | ✓ | ✓ | ✗ | — |
| `organization.type` | ✓ | ✓ | ✓ | — |
| `membership` | ✓ | ✓ | ✗ | — |
| `changes` | ✓ | ✓ | ~ | — |
| `sender` | ✓ | ✓ | ✗ | — |

#### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- GitBucket emits GitHub-compatible `organization` payloads; confusio passes them through
  verbatim.  GitBucket does not emit `created` events.
- GitLab maps group lifecycle System Hook events (`group_create`, `group_destroy`,
  `group_rename`).  GitLab `sender` fields are always empty stubs because System Hook payloads
  do not include an actor user.  `organization.description` and `organization.html_url` are
  empty because the System Hook payload omits them.  `membership` is always absent (GitLab uses
  separate `user_add_to_group` events instead).
- `changes.login.from` is populated for `renamed` events from both GitBucket and GitLab.
- Backends not listed do not emit organization lifecycle events.

---

### `team`

Triggered on team lifecycle and repository assignment events.

| GitHub field | github | gitbucket | All others |
|---|---|---|---|
| `team.id` | ✓ | ✓ | — |
| `team.name` | ✓ | ✓ | — |
| `team.slug` | ✓ | ✓ | — |
| `team.description` | ✓ | ✓ | — |
| `team.privacy` | ✓ | ✓ | — |
| `team.permission` | ✓ | ✓ | — |
| `team.html_url` | ✓ | ✓ | — |
| `organization` | ✓ | ✓ | — |
| `repository` | ✓ | ✓ | — |
| `sender` | ✓ | ✓ | — |

#### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- GitBucket emits GitHub-compatible `team` payloads; confusio passes them through verbatim.
- `repository` is present for `added_to_repository`, `removed_from_repository`, and repository-
  scoped `edited` actions; absent for `created` and `deleted`.
- Backends not listed do not emit team lifecycle events.

---

### `team_add`

Triggered when a team is granted access to a repository.  There is no `action` field.

| GitHub field | github | gitbucket | All others |
|---|---|---|---|
| `team.id` | ✓ | ✓ | — |
| `team.name` | ✓ | ✓ | — |
| `team.slug` | ✓ | ✓ | — |
| `team.description` | ✓ | ✓ | — |
| `team.privacy` | ✓ | ✓ | — |
| `team.permission` | ✓ | ✓ | — |
| `team.html_url` | ✓ | ✓ | — |
| `repository` | ✓ | ✓ | — |
| `organization` | ✓ | ✓ | — |
| `sender` | ✓ | ✓ | — |

**Notes:**
- GitBucket emits GitHub-compatible `team_add` payloads; confusio passes them through verbatim.
- This event has no action field; the event type itself is the action.
- Backends not listed do not emit team-to-repository grant events.

---

### `milestone`

Triggered on milestone lifecycle events.

| GitHub field | gitea-family | gitlab | github | gitbucket | All others |
|---|---|---|---|---|---|
| `milestone.id` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `milestone.number` | ✓ | ~ | ✓ | ✓ | ✗ |
| `milestone.title` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `milestone.description` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `milestone.state` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `milestone.html_url` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `milestone.open_issues` | ✓ | ~ | ✓ | ✓ | ✗ |
| `milestone.closed_issues` | ✓ | ~ | ✓ | ✓ | ✗ |
| `milestone.due_on` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `milestone.creator` | ✓ | ~ | ✓ | ✓ | ✗ |
| `milestone.created_at` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `milestone.updated_at` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `milestone.closed_at` | ✓ | ✓ | ✓ | ✓ | ✗ |

#### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- `milestone.number`: GitLab milestones have an `iid` (per-project) and a global `id`.
  Confusio maps `iid` to `number`.  When the milestone is group-scoped there is no `iid`;
  confusio synthesizes `number` from the global `id`.
- `milestone.open_issues` / `closed_issues`: GitLab omits issue counts from milestone webhook
  payloads; confusio emits `0` as a stub.
- `milestone.creator`: GitLab does not include creator information in milestone events;
  confusio emits `null`.
- `opened` action: In GitHub's milestone contract, `opened` is the *re-open* action (a
  previously-closed milestone is reopened).  It is distinct from `created` (a new milestone
  is created).  Backends that emit a single generic "reopened" event are mapped to `opened`.
- `deleted` action: GitLab does not emit a delete event for milestones.
- Backends not listed do not emit milestone lifecycle events.

---

### `label`

Triggered when a repository label is created, edited, or deleted.

| GitHub field | gitea-family | gitlab | github | gitbucket | All others |
|---|---|---|---|---|---|
| `label.id` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `label.name` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `label.color` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `label.description` | ✓ | ~ | ✓ | ✓ | ✗ |
| `label.default` | ~ | ✗ | ✓ | ✓ | ✗ |
| `label.url` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `changes` | ✓ | ✗ | ✓ | ✓ | ✗ |

#### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- `label.description`: GitLab includes a label description field but it may be `null` for
  older labels.
- `label.default`: Gitea-family labels have no `default` concept; confusio emits `false`.
  GitLab does not have a `default` flag; confusio emits `false`.
- `changes`: Gitea-family **does** include a `changes` object for `edited` label events
  (unlike the `issues` event family where most backends omit `changes`).  GitLab does not
  include `changes` in label events; confusio emits `changes: {}` as a stub.  GitBucket
  includes `changes` on `edited`.
- `deleted` action: GitLab does not emit a label delete event.  Backends not listed do not
  emit label lifecycle events.

---

### `deployment`

Triggered when a deployment is created.  Deployment events represent the initiation of a
deployment to a named environment — distinct from the status updates that follow.

#### Deployment object fields

| GitHub field | github | gitlab | azuredevops | All others |
|---|---|---|---|---|
| `deployment.id` | ✓ | ✓ | ✓ | ✗ |
| `deployment.sha` | ✓ | ~ | ✗ | ✗ |
| `deployment.ref` | ✓ | ✓ | ~ | ✗ |
| `deployment.task` | ✓ | ✗ | ✗ | ✗ |
| `deployment.environment` | ✓ | ✓ | ✓ | ✗ |
| `deployment.original_environment` | ✓ | ✗ | ✗ | ✗ |
| `deployment.description` | ✓ | ✗ | ~ | ✗ |
| `deployment.payload` | ✓ | ✗ | ✗ | ✗ |
| `deployment.creator` | ✓ | ✓ | ✓ | ✗ |
| `deployment.created_at` | ✓ | ~ | ✓ | ✗ |
| `deployment.updated_at` | ✓ | ~ | ✓ | ✗ |
| `deployment.statuses_url` | ✓ | ✗ | ✗ | ✗ |
| `deployment.repository_url` | ✓ | ✗ | ✗ | ✗ |
| `deployment.production_environment` | ✓ | ✗ | ✗ | ✗ |
| `deployment.transient_environment` | ✓ | ✗ | ✗ | ✗ |

#### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- **GitLab**: GitLab fires a single "Deployment events" webhook per status transition.
  Confusio emits a synthetic `deployment` (`created`) event when a GitLab deployment first
  enters the `running` state.  The deployment object is reconstructed from the GitLab
  payload: `id` is `deployment_id`, `ref` and `environment` map directly, `creator` is
  the GitLab `user` object.
- `deployment.sha`: GitLab provides only a short SHA (`short_sha`); confusio emits it as-is.
  Full SHAs are not available without a back-fetch.
- `deployment.created_at` / `updated_at`: GitLab provides `status_changed_at`; confusio
  uses it for both timestamps.
- `deployment.task`: GitLab has no task concept; confusio emits `"deploy"` as a stub.
- `deployment.payload`: GitLab has no custom payload; confusio emits `{}`.
- `deployment.original_environment`, `production_environment`, `transient_environment`:
  GitLab does not expose these; confusio emits stubs (`""`, `false`, `false`).
- `deployment.statuses_url`, `repository_url`: GitLab does not provide these URLs;
  confusio emits `""`.
- `workflow` / `workflow_run`: present in GitHub pass-through when the deployment was
  triggered by GitHub Actions; always `null` in confusio-translated output.
- **Azure DevOps**: Release deployment-started service hooks map to `deployment`
  (`created`).  The release name is used as `ref`, and Azure DevOps does not expose a
  commit SHA or GitHub-style deployment URLs in this payload.
- Backends not listed (Gitea-family, Bitbucket, etc.) do not emit deployment lifecycle
  events.  Gitea explicitly has no deployment webhook equivalent.

---

### `deployment_status`

Triggered when the status of a deployment changes.

#### Deployment status object fields

| GitHub field | github | gitlab | azuredevops | All others |
|---|---|---|---|---|
| `deployment_status.id` | ✓ | ✗ | ✓ | ✗ |
| `deployment_status.state` | ✓ | ~ | ✓ | ✗ |
| `deployment_status.description` | ✓ | ✗ | ✓ | ✗ |
| `deployment_status.environment` | ✓ | ✓ | ✓ | ✗ |
| `deployment_status.environment_url` | ✓ | ✗ | ✗ | ✗ |
| `deployment_status.log_url` | ✓ | ~ | ✗ | ✗ |
| `deployment_status.target_url` | ✓ | ✗ | ✗ | ✗ |
| `deployment_status.deployment_url` | ✓ | ✗ | ✓ | ✗ |
| `deployment_status.creator` | ✓ | ✓ | ✓ | ✗ |
| `deployment_status.created_at` | ✓ | ~ | ✓ | ✗ |
| `deployment_status.updated_at` | ✓ | ~ | ✓ | ✗ |
| `deployment` (full object) | ✓ | ~ | ~ | ✗ |

#### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**`state` mapping from GitLab:**

| GitLab `status` | GitHub `state` |
|----------------|----------------|
| `running` | `in_progress` |
| `success` | `success` |
| `failed` | `failure` |
| `canceled` | `inactive` |
| `blocked` | `waiting` |

**Notes:**
- **GitLab**: GitLab fires "Deployment events" webhooks for every status transition.
  Confusio emits a `deployment_status` (`created`) event for each GitLab deployment
  event regardless of direction.  The `deployment` object embedded in the body is the
  same reconstructed deployment object as in the `deployment` event.
- `deployment_status.id`: GitLab does not expose a separate status ID; confusio emits `0`.
- `deployment_status.state`: Mapped from GitLab's `status` field using the table above.
- `deployment_status.log_url`: GitLab's `deployable_url` (a link to the CI job) is used.
- `deployment_status.target_url`, `environment_url`, `deployment_url`: GitLab does not
  provide these separately; confusio emits `""`.
- `deployment_status.description`: GitLab has no free-form description; confusio emits `""`.
- `created_at` / `updated_at`: GitLab provides `status_changed_at`; confusio uses it for
  both timestamps.
- `deployment` (embedded): reconstructed from GitLab fields — same fidelity as the
  `deployment` event object (see `deployment` section Notes above).
- **Azure DevOps**: Release deployment-completed service hooks map to
  `deployment_status` (`created`).  ADO states are mapped to GitHub deployment states:
  `succeeded` → `success`, `failed`/`rejected`/`partiallySucceeded` → `failure`,
  `canceled` → `inactive`, and `inProgress` → `in_progress`.
- Backends not listed do not emit deployment status events.

---

### `deployment_review`

Triggered when a deployment pending a required review is approved, rejected, or first
requested.  This event is specific to GitHub's environment protection rules.

| GitHub field | github | azuredevops | All others |
|---|---|---|---|
| `approver` | ✓ | ✓ | — |
| `comment` | ✓ | ✓ | — |
| `since` | ✓ | ✓ | — |
| `environment` | ✓ | ✓ | — |
| `reviewers` | ✓ | ✓ | — |
| `workflow_run` | ✓ | ✗ | — |

#### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- `deployment_review` is a GitHub Actions-specific event, but Azure DevOps release
  approvals have a close equivalent.  Confusio maps approval-pending service hooks to
  `requested` and approval-completed hooks to `approved` or `rejected`.

---

### `deployment_protection_rule`

Triggered when a configured deployment protection rule is evaluated.  This event is
specific to GitHub's custom deployment protection integrations.

| GitHub field | github | All others |
|---|---|---|
| `environment` | ✓ | — |
| `event` | ✓ | — |
| `sha` | ✓ | — |
| `ref` | ✓ | — |
| `deployment_callback_url` | ✓ | — |
| `deployment` | ✓ | — |
| `pull_requests` | ✓ | — |

#### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- `deployment_protection_rule` is a GitHub-specific integration mechanism with no
  cross-forge equivalent.  Confusio marks configured providers as `—` (not applicable).

---

### `ping`

The `ping` event is translated only when an upstream forge emits a ping/test event.
Confusio does not synthesize pings for outbound targets because targets are fixed at
startup and there is no runtime target management API.

#### Inbound forge ping: per-backend field coverage

| GitHub field | gitea-family | gitbucket | github | All others |
|---|---|---|---|---|
| `zen` | ~ | ✓ | ✓ | — |
| `hook_id` | ~ | ✓ | ✓ | — |
| `hook` | ~ | ✓ | ✓ | — |
| `repository` | ✓ | ✓ | ✓ | — |
| `sender` | ✓ | ✓ | ✓ | — |

**Notes:**
- Gitea-family: Gitea fires a native `ping` event on webhook creation.  `zen` is a
  fixed string from the Gitea instance (`"Gitea"`), not a random zen quote.  `hook_id`
  and `hook` are present in the raw payload but the field names differ slightly from
  GitHub's.  Confusio normalizes the payload and forwards it verbatim as-is.
- GitBucket: passes through verbatim (GitHub API-compatible).
- GitLab and all other backends: no native ping equivalent; these backends do not emit
  a ping when a webhook is created and confusio has nothing to forward.
- Backends not listed do not emit ping events.

### `meta`

Triggered when the webhook itself is deleted.  GitHub fires this event to the hook's
configured URL just before removing it, giving the target a last-chance notification.

| GitHub field | gitbucket | github | All others |
|---|---|---|---|
| `action` | ✓ | ✓ | — |
| `hook_id` | ✓ | ✓ | — |
| `hook` | ✓ | ✓ | — |
| `repository` | ✓ | ✓ | — |
| `sender` | ✓ | ✓ | — |

#### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- GitBucket: passes through verbatim (GitHub API-compatible).
- All other backends: no native webhook-deletion event equivalent.  Backends not listed
  do not emit `meta` events.

---

### `page_build`

Triggered when a GitHub Pages build completes (whether successfully or with an error).
This event has no action field — the result is conveyed through the `build.status` field
(`"built"`, `"errored"`).

| GitHub field | gitbucket | github | All others |
|---|---|---|---|
| `id` | ✓ | ✓ | — |
| `build.url` | ✓ | ✓ | — |
| `build.status` | ✓ | ✓ | — |
| `build.error.message` | ✓ | ✓ | — |
| `build.pusher` | ✓ | ✓ | — |
| `build.commit` | ✓ | ✓ | — |
| `build.duration` | ✓ | ✓ | — |
| `build.created_at` | ✓ | ✓ | — |
| `build.updated_at` | ✓ | ✓ | — |
| `repository` | ✓ | ✓ | — |
| `sender` | ✓ | ✓ | — |

**Notes:**
- GitBucket: passes through verbatim (GitHub API-compatible).
- GitLab, Gitea, Bitbucket, and all other backends: Pages build notifications are not
  surfaced as webhook events by these platforms even when a Pages site is hosted.
  No `page_build` delivery occurs for these backends.
- Backends not listed do not emit `page_build` events.

---

### `custom_property`

Triggered when an organization-level custom property definition is created, deleted,
or updated.  This is an organization-scoped event — it is not tied to any individual
repository.

This event is only available on GitHub.com and GitHub Enterprise.  GitBucket passes it
through as a GitHub-API-compatible host; no other self-hosted forge has an equivalent
concept.

| GitHub field | gitbucket | github | All others |
|---|---|---|---|
| `action` | ✓ | ✓ | — |
| `definition.property_name` | ✓ | ✓ | — |
| `definition.value_type` | ✓ | ✓ | — |
| `definition.required` | ✓ | ✓ | — |
| `definition.default_value` | ✓ | ✓ | — |
| `definition.description` | ✓ | ✓ | — |
| `definition.allowed_values` | ✓ | ✓ | — |
| `organization` | ✓ | ✓ | — |
| `sender` | ✓ | ✓ | — |

#### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- For the `deleted` action, `definition` only contains `property_name` — the other
  definition fields are not present because the property no longer exists.
- GitBucket: passes through verbatim (GitHub API-compatible).
- Backends not listed do not emit `custom_property` events.

---

### `custom_property_values`

Triggered when the custom property values for an individual repository are updated.
Unlike `custom_property` (which tracks property definitions at the org level), this event
fires at the repository level when the values assigned to that repository change.

| GitHub field | gitbucket | github | All others |
|---|---|---|---|
| `action` | ✓ | ✓ | — |
| `new_property_values` | ✓ | ✓ | — |
| `old_property_values` | ✓ | ✓ | — |
| `repository` | ✓ | ✓ | — |
| `organization` | ✓ | ✓ | — |
| `sender` | ✓ | ✓ | — |

#### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- GitBucket: passes through verbatim (GitHub API-compatible).
- Backends not listed do not emit `custom_property_values` events.

---

### `star`

Triggered when a user stars or removes a star from a repository.

| GitHub field | github | gitea-family | All others |
|---|---|---|---|
| `action` | ✓ | ✓ | — |
| `starred_at` | ✓ | ✓ | — |
| `repository` | ✓ | ✓ | — |
| `sender` | ✓ | ✓ | — |

#### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- `starred_at`: Gitea emits an ISO 8601 timestamp for the `created` action and `null` for
  `deleted`.  GitHub behaves identically.
- The gitea-family includes Gitea 1.20+, Forgejo, and Codeberg.  Gogs and NotABug share the
  handler code but do not emit star webhook events; no delivery will occur for those backends.
- Backends not listed do not emit star lifecycle events.

---

### `watch`

Triggered when a user starts watching (subscribing to) a repository.  GitHub only defines the
`started` action — there is no GitHub webhook for unwatching a repository.

| GitHub field | github | gitea-family | All others |
|---|---|---|---|
| `action` | ✓ | ✓ | — |
| `repository` | ✓ | ✓ | — |
| `sender` | ✓ | ✓ | — |

#### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- The gitea-family includes Gitea, Forgejo, and Codeberg.
- Backends not listed do not emit watch lifecycle events.

---

### `sponsorship`

GitHub Sponsors lifecycle events.  These events are only available on GitHub.com and require
a webhook registered on a sponsored account — they cannot be created on any self-hosted forge.
Confusio does not emit these events for any backend.

| GitHub field | github | All others |
|---|---|---|
| `action` | ✓ | — |
| `sponsorship` | ✓ | — |
| `sender` | ✓ | — |

#### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

---

### CI/CD events beyond `status`

The events below are GitHub-native CI/CD families.  Confusio maps analogous signals from
other providers where they exist, preserving the GitHub event family in GitHub-emulation
shape and the normalized envelope in confusio shape.

| GitHub event | Cross-forge mapping status |
|---|---|
| `check_run` | ✗ |
| `check_suite` | ✗ |
| `workflow_run` | Azure DevOps `build.complete`; GitLab/Gitea-family workflow events; Bitbucket Cloud `pipeline:span_created` pipeline-run spans; OneDev build events |
| `workflow_job` | Bitbucket Cloud `pipeline:span_created` step/command/container/log spans |
| `deployment_review` | Azure DevOps release approval events |
| `deployment_protection_rule` | ✗ |

`deployment_protection_rule` is a GitHub Actions-specific integration event with no
cross-forge equivalent.  `deployment_review` is GitHub-native, but Azure DevOps release
approvals are close enough to map into the same event family.

The `deployment` and `deployment_status` events have cross-forge mapping targets and are
documented as full event families below (see [`deployment`](#deployment-1) and
[`deployment_status`](#deployment_status-1)).

For cross-forge CI/CD signal in confusio-normalized shape the `status` event provides a
consistent commit-check envelope regardless of backend.  Bitbucket Cloud's OTLP pipeline
spans also map to `workflow_run` and `workflow_job`, with `bbc.pipeline_run` spans treated
as workflow runs and step/command/container/log spans treated as workflow jobs.

---

### Security events

GitHub's security event families are mostly GitHub-specific.  Confusio maps Azure
DevOps Advanced Security alert service hooks and GitLab Vulnerability Hook payloads into
the closest GitHub alert families where those providers expose equivalent data.

| GitHub event | Azure DevOps | GitLab |
|---|---|---|
| `security_advisory` | ✗ | ✗ |
| `repository_advisory` | ✗ | ✗ |
| `code_scanning_alert` | ✓ | ~ |
| `secret_scanning_alert` | ✓ | ~ |
| `secret_scanning_alert_location` | ✗ | ✗ |
| `dependabot_alert` | ✓ | ~ |
| `repository_vulnerability_alert` | ✗ | ✗ |
| `branch_protection_rule` | ✗ | ✗ |
| `branch_protection_configuration` | ✗ | ✗ |

Azure DevOps uses the `ms.vss-alerts.*` service-hook family for Advanced Security.
Confusio derives the GitHub event family from `resource.alertType`: `code` maps to
`code_scanning_alert`, `dependency` maps to `dependabot_alert`, and `secret` maps to
`secret_scanning_alert`.

GitLab uses a single Vulnerability Hook payload.  Confusio derives the alert family from
`object_attributes.report_type` and scanner metadata: secret reports map to
`secret_scanning_alert`, dependency or container reports map to `dependabot_alert`, and
other reports map to `code_scanning_alert`.  GitLab security alert mappings are best-effort:
they preserve the source vulnerability object under `alert`, but GitHub-only alert details
such as enterprise, installation, and organization context are not available.

#### `security_advisory`

Triggered when a GitHub security advisory is published, updated, or withdrawn.

| GitHub field | github | All others |
|---|---|---|
| `action` | ✓ | — |
| `security_advisory` | ✓ | — |
| `enterprise` | ✓ | — |
| `installation` | ✓ | — |
| `organization` | ✓ | — |
| `repository` | ✓ | — |
| `sender` | ✓ | — |

**Supported actions:** See the generated [action support matrix](#generated-action-support-matrix).

#### `code_scanning_alert`

Triggered when a code scanning alert is created, closed, fixed, or reassigned.

| GitHub field | github | azuredevops | gitlab | All others |
|---|---|---|---|---|
| `action` | ✓ | ✓ | ✓ | — |
| `alert` | ✓ | ~ | ~ | — |
| `enterprise` | ✓ | ✗ | ✗ | — |
| `installation` | ✓ | ✗ | ✗ | — |
| `organization` | ✓ | ✗ | ✗ | — |
| `repository` | ✓ | ✓ | ✓ | — |
| `sender` | ✓ | ~ | ~ | — |

**Supported actions:** See the generated [action support matrix](#generated-action-support-matrix).

#### `secret_scanning_alert`

Triggered when a secret scanning alert is created, resolved, validated, or assigned.

| GitHub field | github | azuredevops | gitlab | All others |
|---|---|---|---|---|
| `action` | ✓ | ✓ | ✓ | — |
| `alert` | ✓ | ~ | ~ | — |
| `assignee` | ✓ | ✗ | ✗ | — |
| `enterprise` | ✓ | ✗ | ✗ | — |
| `installation` | ✓ | ✗ | ✗ | — |
| `organization` | ✓ | ✗ | ✗ | — |
| `repository` | ✓ | ✓ | ✓ | — |
| `sender` | ✓ | ~ | ~ | — |

**Supported actions:** See the generated [action support matrix](#generated-action-support-matrix).

**Notes:**
- `assignee`: present only for `assigned` and `unassigned` actions; `null` for all others.

#### `secret_scanning_alert_location`

Triggered when a new location is discovered for an existing secret scanning alert.
Subscribe to this event alongside `secret_scanning_alert` to receive location-level detail.

| GitHub field | github | All others |
|---|---|---|
| `action` | ✓ | — |
| `alert` | ✓ | — |
| `installation` | ✓ | — |
| `location` | ✓ | — |
| `organization` | ✓ | — |
| `repository` | ✓ | — |
| `sender` | ✓ | — |

**Supported actions:** See the generated [action support matrix](#generated-action-support-matrix).

#### `dependabot_alert`

Triggered when a Dependabot alert is created, dismissed, fixed, or reassigned.

| GitHub field | github | azuredevops | gitlab | All others |
|---|---|---|---|---|
| `action` | ✓ | ✓ | ✓ | — |
| `alert` | ✓ | ~ | ~ | — |
| `enterprise` | ✓ | ✗ | ✗ | — |
| `installation` | ✓ | ✗ | ✗ | — |
| `organization` | ✓ | ✗ | ✗ | — |
| `repository` | ✓ | ✓ | ✓ | — |
| `sender` | ✓ | ~ | ~ | — |

**Supported actions:** See the generated [action support matrix](#generated-action-support-matrix).

**Notes:**
- `dependabot_alert` supersedes the older `repository_vulnerability_alert` event, which
  is closing down.  New integrations should subscribe to `dependabot_alert` instead.
- GitLab dependency and container scanning vulnerabilities map here because they are the
  closest GitHub alert family for package and image dependency findings.

#### `repository_advisory`

Triggered when a repository security advisory is published or reported.

| GitHub field | github | All others |
|---|---|---|
| `action` | ✓ | — |
| `enterprise` | ✓ | — |
| `installation` | ✓ | — |
| `organization` | ✓ | — |
| `repository` | ✓ | — |
| `repository_advisory` | ✓ | — |
| `sender` | ✓ | — |

**Supported actions:** See the generated [action support matrix](#generated-action-support-matrix).

#### `repository_vulnerability_alert`

Triggered when a repository vulnerability alert is created, dismissed, reopened, or
resolved.  This event is the deprecated predecessor to `dependabot_alert`; confusio
normalises incoming `repository_vulnerability_alert` events to the `dependabot_alert`
event family with translated action names.

| GitHub field | github | All others |
|---|---|---|
| `action` | ✓ | — |
| `alert` | ✓ | — |
| `enterprise` | ✓ | — |
| `installation` | ✓ | — |
| `organization` | ✓ | — |
| `repository` | ✓ | — |
| `sender` | ✓ | — |

**Supported actions:** See the generated [action support matrix](#generated-action-support-matrix).

**Notes:**
- `repository_vulnerability_alert` is deprecated.  Prefer `dependabot_alert` for new
  integrations.  confusio translates the legacy wire actions to `dependabot_alert`
  action names so subscribers to `dependabot_alert` receive both event streams.

#### `branch_protection_rule`

Triggered when a branch protection rule is created, edited, or deleted.

| GitHub field | github | All others |
|---|---|---|
| `action` | ✓ | — |
| `changes` | ✓ | — |
| `enterprise` | ✓ | — |
| `installation` | ✓ | — |
| `organization` | ✓ | — |
| `repository` | ✓ | — |
| `rule` | ✓ | — |
| `sender` | ✓ | — |

**Supported actions:** See the generated [action support matrix](#generated-action-support-matrix).

**Notes:**
- `rule`: present for all actions.  Includes the full branch protection rule object with
  settings such as `admin_enforced`, `required_approving_review_count`,
  `required_status_checks`, and enforcement levels for various checks.
- `changes`: present only for `edited` action.  Each key in `changes` has a `from` field
  recording the previous value.  Keys match the corresponding fields in `rule`.

#### `branch_protection_configuration`

Triggered when branch protection is enabled or disabled for a repository.

| GitHub field | github | All others |
|---|---|---|
| `action` | ✓ | — |
| `enterprise` | ✓ | — |
| `installation` | ✓ | — |
| `organization` | ✓ | — |
| `repository` | ✓ | — |
| `sender` | ✓ | — |

**Supported actions:** See the generated [action support matrix](#generated-action-support-matrix).

---

### `discussion`

Triggered on discussion thread lifecycle events.  GitHub Discussions are
forum-style threads attached to a repository.  Most forge backends do not have
a direct equivalent; coverage is limited to backends that expose a native
discussion webhook surface.

#### Discussion object fields

| GitHub field | gitea-family | gitlab | github | gitbucket | All others |
|---|---|---|---|---|---|
| `discussion.id` | ✓ | ✗ | ✓ | ✓ | ✗ |
| `discussion.node_id` | ✗ | ✗ | ✓ | ✓ | ✗ |
| `discussion.number` | ✓ | ✗ | ✓ | ✓ | ✗ |
| `discussion.title` | ✓ | ✗ | ✓ | ✓ | ✗ |
| `discussion.body` | ✓ | ✗ | ✓ | ✓ | ✗ |
| `discussion.html_url` | ✓ | ✗ | ✓ | ✓ | ✗ |
| `discussion.state` | ✓ | ✗ | ✓ | ✓ | ✗ |
| `discussion.state_reason` | ✗ | ✗ | ✓ | ✓ | ✗ |
| `discussion.locked` | ✓ | ✗ | ✓ | ✓ | ✗ |
| `discussion.comments` | ✓ | ✗ | ✓ | ✓ | ✗ |
| `discussion.author_association` | ✗ | ✗ | ✓ | ✓ | ✗ |
| `discussion.category` | ✗ | ✗ | ✓ | ✓ | ✗ |
| `discussion.labels` | ✓ | ✗ | ✓ | ✓ | ✗ |
| `discussion.reactions` | ✗ | ✗ | ✓ | ✓ | ✗ |
| `discussion.answer_html_url` | ✗ | ✗ | ✓ | ✓ | ✗ |
| `discussion.answer_chosen_at` | ✗ | ✗ | ✓ | ✓ | ✗ |
| `discussion.answer_chosen_by` | ✗ | ✗ | ✓ | ✓ | ✗ |
| `discussion.user` | ✓ | ✗ | ✓ | ✓ | ✗ |
| `discussion.created_at` | ✓ | ✗ | ✓ | ✓ | ✗ |
| `discussion.updated_at` | ✓ | ✗ | ✓ | ✓ | ✗ |
| `repository` | ✓ | ✗ | ✓ | ✓ | ✗ |
| `sender` | ✓ | ✗ | ✓ | ✓ | ✗ |

#### Supported actions by backend

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- `discussion.category`: GitHub Discussions have a category concept (Q&A, Announcements,
  etc.).  Gitea discussions do not have categories; confusio emits `null` for the
  `category` field when translating from Gitea.
- `discussion.author_association`, `discussion.reactions`, `discussion.answer_*`:
  Gitea's discussion webhook payload does not expose these fields; confusio stubs them
  with the appropriate zero values (`"NONE"`, zeroed reactions object, `null`).
- `discussion.state_reason`: only populated by GitHub; confusio stubs `null` for all
  other backends.
- GitLab does not have a repository-level discussions feature equivalent to GitHub
  Discussions.  GitLab note threads on issues and MRs are already mapped to the
  `issue_comment` and `pull_request_review_comment` event families.
- `answered` / `unanswered` / `locked` / `unlocked` / `pinned` / `unpinned` /
  `category_changed` / `transferred`: Gitea's discussion webhook does not emit events
  for these lifecycle transitions; only `github` and `gitbucket` support them.

---

### `discussion_comment`

Triggered when a comment is created, edited, or deleted on a discussion thread.

#### Comment object fields

| GitHub field | gitea-family | gitlab | github | gitbucket | All others |
|---|---|---|---|---|---|
| `comment.id` | ✓ | ✗ | ✓ | ✓ | ✗ |
| `comment.node_id` | ✗ | ✗ | ✓ | ✓ | ✗ |
| `comment.html_url` | ✓ | ✗ | ✓ | ✓ | ✗ |
| `comment.body` | ✓ | ✗ | ✓ | ✓ | ✗ |
| `comment.discussion_id` | ✓ | ✗ | ✓ | ✓ | ✗ |
| `comment.parent_id` | ✗ | ✗ | ✓ | ✓ | ✗ |
| `comment.child_comment_count` | ✗ | ✗ | ✓ | ✓ | ✗ |
| `comment.author_association` | ✗ | ✗ | ✓ | ✓ | ✗ |
| `comment.reactions` | ✗ | ✗ | ✓ | ✓ | ✗ |
| `comment.user` | ✓ | ✗ | ✓ | ✓ | ✗ |
| `comment.created_at` | ✓ | ✗ | ✓ | ✓ | ✗ |
| `comment.updated_at` | ✓ | ✗ | ✓ | ✓ | ✗ |
| `discussion` | ✓ | ✗ | ✓ | ✓ | ✗ |
| `repository` | ✓ | ✗ | ✓ | ✓ | ✗ |
| `sender` | ✓ | ✗ | ✓ | ✓ | ✗ |

#### Supported actions by backend

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- `comment.parent_id`: Gitea discussion comments do not expose a parent ID for threaded
  replies; confusio stubs `null`.
- `comment.child_comment_count`, `comment.author_association`, `comment.reactions`:
  not available from Gitea; confusio stubs with zero values.
- GitLab note threads on issues and MRs are mapped to `issue_comment` /
  `pull_request_review_comment`, not `discussion_comment`.  GitLab has no standalone
  Discussions surface equivalent to GitHub Discussions.

---

### `package`

Triggered on package registry lifecycle events.  Fires when a package version is
published or (for some backends) deleted from the registry.

#### Top-level fields

| GitHub field | gitea-family | github | All others |
|---|---|---|---|
| `action` | ✓ | ✓ | — |
| `package` | ✓ | ✓ | — |
| `repository` | ~ | ✓ | — |
| `sender` | ✓ | ✓ | — |

#### Package object fields

| GitHub field | gitea-family | github | All others |
|---|---|---|---|
| `package.id` | ✓ | ✓ | — |
| `package.name` | ✓ | ✓ | — |
| `package.namespace` | ~ | ✓ | — |
| `package.ecosystem` | ✓ | ✓ | — |
| `package.package_type` | ✓ | ✓ | — |
| `package.html_url` | ✓ | ✓ | — |
| `package.created_at` | ~ | ✓ | — |
| `package.updated_at` | ~ | ✓ | — |
| `package.owner` | ✓ | ✓ | — |
| `package.description` | ✗ | ✓ | — |
| `package.package_version.id` | ✓ | ✓ | — |
| `package.package_version.name` | ✓ | ✓ | — |
| `package.package_version.html_url` | ✓ | ✓ | — |
| `package.package_version.created_at` | ✓ | ✓ | — |
| `package.package_version.metadata` | ✗ | ✓ | — |
| `package.package_version.package_files` | ✗ | ✓ | — |
| `package.package_version.installation_command` | ✗ | ✓ | — |
| `package.registry` | ✗ | ✓ | — |

#### Supported actions by backend

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- `package.namespace`: Gitea does not expose a `namespace` field in the package webhook
  payload.  Confusio synthesizes it from the owner login (e.g. `"octocat"`).  GitHub
  populates this as `"owner/package-name"` for repository-scoped packages.
- `package.created_at` / `package.updated_at`: Gitea's package webhook payload does not
  carry a package-level timestamp.  Confusio derives both fields from the version's
  `created_at`; `updated_at` will equal `created_at`.
- `package.description`: Not present in Gitea package webhook payloads; confusio emits
  `null`.
- `package.package_version.metadata`, `package.package_version.package_files`,
  `package.package_version.installation_command`: Gitea's package webhook does not include
  these rich version fields.  Confusio emits empty stubs (`[]`, `""`) to satisfy the
  schema contract.
- `package.registry`: Gitea does not expose registry-level metadata in webhook payloads;
  confusio emits `null`.
- `repository`: Gitea package webhooks include a `repository` field only when the package
  is linked to a repository.  Confusio emits `null` when the field is absent.
- Action mapping: Gitea fires `action: "created"` when a new version is published (mapped
  to `published`) and `action: "deleted"` when a version is removed.  GitHub fires
  `published` and `updated`; there is no `deleted` action on the GitHub side.  Gitea
  `deleted` events surface with `action: "deleted"` in confusio output — this action is
  not part of the GitHub `package` schema but is preserved so consumers can detect
  removals from Gitea-family backends.
- Forgejo and Codeberg inherit Gitea's `package` webhook handler.  Gogs and NotABug strip
  all package-related handlers; no `package` events will be delivered from those backends.
- OneDev `PackPublished` events map to `package/published`; OneDev does not emit a
  matching GitHub-style `package/updated` event.
- Backends not listed (GitLab, Bitbucket, Azure DevOps, etc.) do not emit package
  registry lifecycle webhook events.

---

### `registry_package`

Legacy GitHub Packages webhook event name, superseded by `package` (above).
GitHub still fires `registry_package` for Container Registry activity on some
repository types alongside the newer `package` event.

**This event has no cross-forge mapping for the configured providers in this PR.**  Use
`package` instead.

| GitHub field | github | All others |
|---|---|---|
| `action` | ✓ | — |
| `registry_package` | ✓ | — |
| `repository` | ✓ | — |
| `sender` | ✓ | — |

#### Supported actions by backend

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- `registry_package` is the older event key used before GitHub renamed the field to
  `package`.  The object schema is nearly identical to `package.*`.
- New consumers should subscribe to `package` rather than `registry_package`.
- No self-hosted forge (Gitea, GitLab, Bitbucket, etc.) sends `registry_package` events.

---

### Org events

The org-category events in the GitHub-emulation output are `member`, `membership`,
`organization`, `team`, and `team_add`.  `member` is documented in its own section
above; the others are documented below.  Backend support varies — see the field-level
mapping tables that follow.

| GitHub event | Status | Notes |
|---|---|---|
| `member` | ✓ gitea-family, gitlab, gitbucket | See `member` field-level mapping table above |
| `membership` | ✓ gitbucket, gitlab | GitBucket pass-through; GitLab group-member system hook |
| `organization` | ✓ gitbucket, gitlab | GitBucket pass-through; GitLab group lifecycle system hook |
| `team` | ✓ gitbucket | GitBucket pass-through only |
| `team_add` | ✓ gitbucket | GitBucket pass-through only |
| `org_block` | ✗ | No cross-forge equivalent |

For backends without a mapping, these event families are not emitted.

### Repository automation events

The following GitHub repository-management events have no cross-forge mapping today:

| GitHub event | Status | Reason |
|---|---|---|
| `repository_dispatch` | ✗ | Triggered by a client `POST /repos/{owner}/{repo}/dispatches` API call. This is a GitHub-only mechanism for custom event triggers; no other forge exposes an equivalent webhook payload. |
| `repository_ruleset` | ✗ | Triggered when a repository ruleset is created, edited, or deleted. Rulesets are a GitHub-specific branch/tag protection feature; no other backend exposes an equivalent webhook event. |
| `repository_import` | ✗ | Triggered when a repository source import finishes. GitHub's import service is not exposed by any backend confusio supports. |

These events are not emitted for the configured providers in this PR; there is no
cross-forge mapping target.

---

### App and installation events

GitHub App lifecycle events are generated by GitHub's App platform and mostly have no
equivalent in any self-hosted forge.  Two events are **synthesized by confusio at startup**
when a backend is configured and at least one outbound target is registered:

- **`installation/created`** — fired once at startup to signal that confusio came
  online for the configured backend.  The `installation` object has `app_slug =
  "confusio"`, `repository_selection = "all"`, and `account.login` set to the backend
  name.
- **`installation_repositories/added`** — fired immediately after `installation/created`
  with `repository_selection = "all"` and empty `repositories_added` / `repositories_removed`
  arrays, indicating that all repositories on the backend are accessible via confusio.

These synthesized events give GitHub-App-aware consumers (CI runners, bots) a lifecycle
signal that confusio has started and is ready to forward events.  All other actions in
the `installation` and `installation_repositories` families are GitHub-platform-specific.
GitLab resource token expiry hooks map to `personal_access_token_request/created`; the
remaining app and marketplace event families have no cross-forge equivalent.

| GitHub event | Status | Reason |
|---|---|---|
| `installation` | ~ | `created` synthesized at startup; all other actions are GitHub-platform-specific with no self-hosted forge equivalent. |
| `installation_repositories` | ~ | `added` (all repos) synthesized at startup; `removed` and individual repository events are GitHub-platform-specific. |
| `installation_target` | ✗ | An account (user or org) that owns a GitHub App installation was renamed. No cross-forge equivalent. |
| `github_app_authorization` | ✗ | A user revoked their authorization of a GitHub App. GitHub-specific OAuth lifecycle event. |
| `personal_access_token_request` | ~ | Fine-grained PAT request lifecycle (approved, cancelled, created, denied) is GitHub Enterprise only. GitLab resource access and deploy token expiry hooks map to `created` as the closest normalized token event. |
| `marketplace_purchase` | ✗ | GitHub Marketplace purchase lifecycle. GitHub.com-only; no self-hosted forge has a marketplace. |

#### `installation`

Triggered when a GitHub App installation is created, deleted, suspended, unsuspended,
or when the user accepts new permissions requested by the app.  Confusio synthesizes the
`created` action at startup for any configured backend; all other actions are
GitHub-platform-specific and are never emitted.

| GitHub field | github | All others |
|---|---|---|
| `action` | ✓ | ~ |
| `installation` | ✓ | ~ |
| `repositories` | ✓ | ~ |
| `requester` | ✓ | — |
| `sender` | ✓ | ~ |

##### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

---

#### `installation_repositories`

Triggered when repositories are added to or removed from a GitHub App installation.
Confusio synthesizes the `added` action at startup (with `repository_selection = "all"`
and empty arrays) for any configured backend; other actions and per-repository events are
GitHub-platform-specific and are never emitted.

| GitHub field | github | All others |
|---|---|---|
| `action` | ✓ | ~ |
| `installation` | ✓ | ~ |
| `repository_selection` | ✓ | ~ |
| `repositories_added` | ✓ | ~ |
| `repositories_removed` | ✓ | ~ |
| `requester` | ✓ | — |
| `sender` | ✓ | ~ |

##### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

---

#### `installation_target`

Triggered when a user or organization that owns a GitHub App installation is renamed.

| GitHub field | github | All others |
|---|---|---|
| `action` | ✓ | — |
| `account` | ✓ | — |
| `changes` | ✓ | — |
| `installation` | ✓ | — |
| `target_type` | ✓ | — |
| `sender` | ✓ | — |

##### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

---

#### `github_app_authorization`

Triggered when a user revokes their authorization of a GitHub App.

| GitHub field | github | All others |
|---|---|---|
| `action` | ✓ | — |
| `sender` | ✓ | — |

##### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

---

#### `personal_access_token_request`

Triggered when there is activity relating to a request for a fine-grained personal
access token to access organization resources.  Requires a GitHub Enterprise instance
with the "Require approval of fine-grained personal access tokens" policy enabled.

| GitHub field | github | gitlab | All others |
|---|---|---|---|
| `action` | ✓ | ✓ | — |
| `personal_access_token_request` | ✓ | ~ | — |
| `organization` | ✓ | ~ | — |
| `installation` | ✓ | ✗ | — |
| `sender` | ✓ | ~ | — |

##### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

**Notes:**
- GitLab emits Resource Access Token and Resource Deploy Token hooks for expiring project
  or group tokens.  Confusio maps both to `personal_access_token_request` with action
  `created`; GitLab does not expose the approval lifecycle actions that GitHub Enterprise
  emits for fine-grained PAT requests.

---

#### `marketplace_purchase`

Triggered when there is activity in the GitHub Marketplace: a plan is purchased,
cancelled, changed, or has a pending change.  GitHub.com only; requires a GitHub
Marketplace listing.

| GitHub field | github | All others |
|---|---|---|
| `action` | ✓ | — |
| `effective_date` | ✓ | — |
| `marketplace_purchase` | ✓ | — |
| `previous_marketplace_purchase` | ✓ | — |
| `sender` | ✓ | — |

##### Supported actions

Action support for this event is generated in the [action support matrix](#generated-action-support-matrix).

---

## Delivery Semantics

The current delivery path is fire-and-record.  After an inbound webhook is verified and
normalized, confusio walks the in-memory target registry and performs one synchronous
HTTP POST to each target whose event filter matches.  The result of each POST is logged.
Failed deliveries are terminal for that attempt: confusio does not retry, persist
delivery state, or expose a replay API.

### Current guarantee: try once, log all

Each matching target receives one delivery attempt during the inbound request.  The
log line includes the target name, event type, backend, delivery ID, latency,
HTTP status when a response is received, and error text when delivery fails before a
response.  Logging is best-effort observability; the inbound response does not imply
that downstream consumers processed the event, and consumers that miss an event must
reconcile from the upstream forge API.

There is no durable delivery subsystem in this PR.  The sections below describe the
implemented one-shot behavior and startup-only target configuration.

### No durable delivery state

Confusio does not write an outbox entry before dispatch, does not keep per-target
delivery state, and does not run a retry scheduler.  A process crash during fan-out may
leave some matching targets undelivered.  This mirrors GitHub webhook expectations:
receivers must be idempotent and must reconcile missed work from the upstream provider
API.

The only retained delivery information is the process log line for each attempted POST.
There is no HTTP endpoint for listing, inspecting, replaying, redelivering, pausing, or
deleting deliveries.

### Success and failure

A target attempt is considered successful when the target returns an HTTP 2xx response.
Any non-2xx response, network error, DNS failure, TLS failure, or fetch exception is
logged as a failed attempt and then dropped.  Confusio does not follow redirects, retry
timeouts, open a circuit breaker, or hold failed attempts for later replay.

The inbound webhook response still reports whether the inbound event was accepted by
confusio, not whether every downstream consumer processed it.  Downstream consumers
that need a complete view should periodically reconcile from the upstream API.

### Logging

Each attempted outbound delivery emits one log line with the target URL, HTTP status or
network error, target name, source backend, event family, generated delivery UUID, and
elapsed time.  Logs are operational evidence only; they are not a durable delivery
store and cannot be queried through confusio.

## Multi-Target Dispatch and Configuration

Targets are registered only from startup arguments.  Repeated `--webhook-target` flags
create multiple static targets; legacy `webhook_target=*` SCRIPTARGS create one
additional compatibility target.  All targets live only in process memory and are rebuilt
from the launch command on restart.

### Current repeated-target configuration

```sh
sh ./confusio.com -p 8080 -- \
  --provider=gitea \
  --upstream=https://gitea.example \
  --webhook-target=name=fido,url=https://fido.example/webhooks,shape=github,events=issues+pull_request,secret_file=/run/secrets/fido-hook \
  --webhook-target=name=audit,url=https://audit.example/events,shape=confusio,events=*
```

### Legacy single-target configuration

```sh
sh ./confusio.com -p 8080 -- gitea https://gitea.example \
  webhook_target=https://example.com/webhook \
  webhook_target_name=primary \
  webhook_target_events=push,pull_request \
  webhook_target_shape=confusio \
  webhook_target_secret_file=/run/secrets/webhook-target
```

`webhook_target_name` defaults to `default`, `webhook_target_events` defaults to `*`,
`webhook_target_shape` defaults to `github`, and the target secret is optional.

### Event-type filter

The target event filter controls which event families are delivered to a target.  Filters
match canonical event-family names such as `issues`, `push`, `pull_request`, and
`release`.  They do not match action names or normalized dotted body types.

| Value | Meaning |
|-------|---------|
| `*` | All event families; this is the default |
| `issues+pull_request` | Only issue and pull request families in repeated target syntax |
| `issues,pull_request` | Only issue and pull request families in legacy syntax |

If an inbound event's family is not in the target filter, no HTTP request is attempted
for that target and no delivery state is saved.

### Shape selection

The target `shape` field selects the outbound body format for all events delivered to
that target.

| Value | Description |
|-------|-------------|
| `github` | GitHub-emulation shape; this is the default |
| `confusio` | Confusio-normalized envelope and namespace |

Changing shape requires changing the launch command and restarting the process.

### Outbound signatures

When a target secret is configured, confusio signs the outbound body with the source
backend's native signing scheme.  This applies to both GitHub-emulation and
confusio-normalized shapes.  For example, Gitea-sourced deliveries use
`X-Gitea-Signature`, GitLab-sourced deliveries use `X-Gitlab-Token`, and
Confusio-to-confusio deliveries use `X-Confusio-Signature-256`.

Targets without a secret receive no signature header.  Secret rotation is also
startup-only: update the secret file or target spec and restart.

### Fan-out dispatch logic

For each accepted inbound event, confusio walks the in-memory target list in registration
order.  For each target whose event filter matches, it serializes the selected shape,
adds delivery headers and any signature header, performs one synchronous HTTP POST, logs
the result, and moves to the next target.  There is no cross-target ordering guarantee
beyond this single process loop, and a failure for one target does not stop attempts to
other matching targets.

### Explicitly absent surfaces

Confusio intentionally does not expose any of the following webhook administration or
delivery-state features in this PR:

| Surface | Status |
|---------|--------|
| Config file | Not implemented |
| Environment-variable target config | Not implemented |
| Admin UI | Not implemented |
| Runtime target registration API | Not implemented |
| `GET /webhooks/targets` or similar target inspection | Not implemented |
| Delivery list / delivery detail endpoints | Not implemented |
| Replay or redelivery endpoint | Not implemented |
| Durable outbox | Not implemented |
| Retry queue / scheduler | Not implemented |
| Circuit breaker or retry budget | Not implemented |

Restart is the change-control mechanism.  Missed deliveries are handled by receiver-side
reconciliation against the upstream provider API.
