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

Four distinct schemes appear across the 24 backends:

| Scheme | Description | Backends |
|--------|-------------|----------|
| **HMAC-SHA256** | Signature = `HMAC-SHA256(secret, body)`, hex-encoded | gitea, forgejo, codeberg, notabug, gogs, bitbucket, bitbucket_datacenter, phabricator, pagure (SHA-256 header) |
| **HMAC-SHA512** | Signature = `HMAC-SHA512(secret, body)`, hex-encoded | pagure (SHA-512 header, older instances) |
| **HMAC-SHA1** | Signature = `HMAC-SHA1(secret, body)`, hex-encoded | gitbucket (GitHub legacy compat) |
| **Shared token** | Secret echoed verbatim in a header; constant-time string compare | gitlab, gitblit, harness, onedev, rhodecode, sourceforge, tuleap, kallithea |
| **Bearer / Basic** | Secret in Authorization header (Bearer or Basic form) | onedev (Bearer), azuredevops (Basic), gerrit (Basic or Bearer), radicle (raw) |
| **Asymmetric / platform** | ed25519, OpenPGP, or platform-managed certificate signing | sourcehut, launchpad, codecommit |

### Quick reference

| Backend | Header | Scheme | Format |
|---------|--------|--------|--------|
| `azuredevops` | `Authorization` | Basic auth | `Basic <base64(user:password)>` |
| `bitbucket` | `X-Hub-Signature` | HMAC-SHA256 | `sha256=<hex>` |
| `bitbucket_datacenter` | `X-Hub-Signature` | HMAC-SHA256 | `sha256=<hex>` |
| `codeberg` | `X-Gitea-Signature` | HMAC-SHA256 | `<hex>` |
| `codecommit` | _(SNS body fields)_ | AWS SNS X.509 | `Signature` in body |
| `forgejo` | `X-Gitea-Signature` | HMAC-SHA256 | `<hex>` |
| `gerrit` | `Authorization` | Basic or Bearer | see notes |
| `gitblit` | `X-Gitblit-Token` | Shared token | verbatim |
| `gitbucket` | `X-Hub-Signature` | HMAC-SHA1 | `sha1=<hex>` |
| `gitea` | `X-Gitea-Signature` | HMAC-SHA256 | `<hex>` |
| `gitlab` | `X-Gitlab-Token` | Shared token | verbatim |
| `gogs` | `X-Gogs-Signature` | HMAC-SHA256 | `<hex>` |
| `harness` | `X-Harness-Token` | Shared token | verbatim |
| `kallithea` | _(body field)_ | Body-embedded token | see notes |
| `launchpad` | `X-Launchpad-Signature` | OpenPGP detached | armored |
| `notabug` | `X-Gitea-Signature` | HMAC-SHA256 | `<hex>` |
| `onedev` | `Authorization` | Bearer token | `Bearer <secret>` |
| `pagure` | `X-Pagure-Signature-256` / `X-Pagure-Signature` | HMAC-SHA256 / HMAC-SHA512 | `<hex>` |
| `phabricator` | `X-Phabricator-Webhook-Signature` | HMAC-SHA256 | `<hex>` |
| `radicle` | `Authorization` | Shared token | verbatim |
| `rhodecode` | `X-RhodeCode-Signature` | Shared token | verbatim |
| `sourceforge` | `X-Sourceforge-Webhook-Secret` | Shared token | verbatim |
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
| All gitea family, `gogs`, `phabricator`, `pagure` | `5bdcc146...` (no prefix) |

---

### Gitea family (gitea, forgejo, codeberg, notabug) and gogs

All five backends use HMAC-SHA256 over the raw request body.  The header name differs
between the Gitea-derived backends and Gogs, but the algorithm is identical.

| Backend | Signature header | Algorithm |
|---------|-----------------|-----------|
| `gitea` | `X-Gitea-Signature` | HMAC-SHA256, lowercase hex |
| `forgejo` | `X-Gitea-Signature` | HMAC-SHA256, lowercase hex |
| `codeberg` | `X-Gitea-Signature` | HMAC-SHA256, lowercase hex |
| `notabug` | `X-Gitea-Signature` | HMAC-SHA256, lowercase hex |
| `gogs` | `X-Gogs-Signature` | HMAC-SHA256, lowercase hex |

Gitea-derived backends also send `X-Hub-Signature` (`sha1=<hex>`) for GitHub-client
compatibility; gogs sends `X-Hub-Signature` as well.  Confusio verifies only
`X-Gitea-Signature` (or `X-Gogs-Signature` for gogs) and ignores `X-Hub-Signature`.

**Verification algorithm:**

```
secret       = configured shared secret (UTF-8 bytes)
body         = raw request body bytes
expected_hex = HMAC-SHA256(secret, body) in lowercase hex
received_hex = value of X-Gitea-Signature header (or X-Gogs-Signature)

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

### GitHub

GitHub sends two signature headers: the primary SHA-256 variant and a legacy SHA-1
variant.  Confusio verifies the SHA-256 variant.

```
Header:    X-Hub-Signature-256
Format:    sha256=<lowercase hex>
Algorithm: HMAC-SHA256(secret, raw_body)
```

```
expected = "sha256=" ++ HMAC-SHA256(secret, body) as lowercase hex
received = value of X-Hub-Signature-256

accept if constant_time_equal(expected, received)
```

The legacy `X-Hub-Signature` (SHA-1) header is also present; confusio ignores it.

**Configuration:** Set in GitHub webhook settings as "Secret".

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

OneDev sends the shared secret in a Bearer authorization header.

```
Header:    Authorization
Format:    Bearer <secret>
```

```
secret   = configured shared secret
received = value of Authorization header, with "Bearer " prefix stripped

accept if constant_time_equal(secret, received)
```

**Configuration:** Set in OneDev webhook settings as "Secret".

---

### Radicle

Radicle sends the shared secret in the `Authorization` header.  Current Radicle node
versions do not use a `Bearer` or `Basic` prefix — the secret value is sent as-is.

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

SourceForge sends the shared secret in `X-Sourceforge-Webhook-Secret`.

```
secret   = configured shared secret
received = value of X-Sourceforge-Webhook-Secret

accept if constant_time_equal(secret, received)
```

**Configuration:** Set when registering the webhook in SourceForge project settings.

---

### Tuleap

Tuleap sends the shared secret in `X-Tuleap-Webhook-Secret`.

```
secret   = configured shared secret
received = value of X-Tuleap-Webhook-Secret

accept if constant_time_equal(secret, received)
```

**Configuration:** Set in Tuleap webhook settings as "Secret".

---

### Gerrit

Gerrit's webhook plugin does not have a standardized signature scheme.  Authentication
is typically configured as HTTP Basic auth credentials embedded in the webhook URL, or
as a shared token in the `Authorization` header depending on the plugin version.

Confusio supports the `Authorization` header form:

```
secret   = configured shared token
received = value of Authorization header

accept if constant_time_equal(secret, received)
```

For URL-embedded credentials, confusio extracts and verifies the Base64-decoded
`user:password` pair against the configured secret.

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
header.

```
Header:    Authorization
Format:    Basic <base64(username:password)>
```

```
configured_user     = configured username (may be empty string)
configured_password = configured shared secret / password
received_header     = value of Authorization header

decoded = base64_decode(received_header after stripping "Basic ")
[received_user, received_password] = split(decoded, ":", limit=2)

accept if constant_time_equal(configured_user, received_user)
       AND constant_time_equal(configured_password, received_password)
```

**Configuration:** Set in Azure DevOps service hook settings under "Basic authentication"
→ "Username" and "Password".

---

### AWS CodeCommit (codecommit)

CodeCommit delivers events through Amazon SNS.  Confusio receives SNS HTTP/HTTPS
notifications and must validate SNS message signatures before processing.

**Validation steps:**

1. **Confirm subscription**: On first delivery, SNS sends a `SubscriptionConfirmation`
   message.  Confusio must fetch the `SubscribeURL` (HTTPS only) to confirm the
   subscription.  The URL is validated against the `sns.amazonaws.com` domain before
   fetching.

2. **Verify message signature**: For `Notification` messages, confusio constructs the
   canonical signing string from SNS fields (`Message`, `MessageId`, `Subject`,
   `Timestamp`, `TopicArn`, `Type`) and verifies the `Signature` field using the
   X.509 certificate at `SigningCertURL`.

3. **Certificate URL validation**: `SigningCertURL` must be a well-formed HTTPS URL on
   an `amazonaws.com` subdomain.  Confusio must not fetch certificates from arbitrary
   URLs.

4. **Certificate caching**: SNS certificates rotate infrequently.  Confusio caches
   fetched certificates keyed by URL to avoid repeated fetches.

**No shared secret is required** for CodeCommit/SNS — authenticity is established by
the AWS-issued certificate chain.  Operators must ensure the SNS topic's access policy
only allows CodeCommit to publish.

**Configuration:** Register the confusio receiver URL as an SNS HTTPS endpoint
subscription on the CodeCommit-linked SNS topic.

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
key.  Confusio should re-fetch the well-known key on verification failure to handle
key rotation, then retry once before rejecting.

---

### Launchpad

Launchpad signs webhook payloads with an OpenPGP key.  The signature is sent in the
`X-Launchpad-Signature` header (if present) or the body may be a cleartext-signed
PGP message.

**Verification steps:**

1. **Fetch Launchpad's signing key**: Launchpad publishes its webhook signing key on
   its keyserver.  The fingerprint is documented in Launchpad's developer documentation.

2. **Verify OpenPGP signature**:

```
signing_key = Launchpad's published OpenPGP public key (fetched from keyserver)
body        = raw request body bytes
signature   = value of X-Launchpad-Signature (detached PGP signature, armored)

accept if openpgp_verify(signing_key, body, signature) == true
```

**Note:** OpenPGP verification requires a PGP library.  This is the most complex
verification scheme across all 24 backends.  The implementation should use a
well-audited PGP library and must validate the key fingerprint against the expected
Launchpad fingerprint before trusting the key.

**No shared secret is configured** — authentication is established by Launchpad's
published key.

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
