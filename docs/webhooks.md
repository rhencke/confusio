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
| `X-Hub-Signature-256` | `sha256=<lowercase hex>` | HMAC-SHA256 of body using target's secret; omitted if no secret configured |
| `X-Hub-Signature` | `sha1=<lowercase hex>` | HMAC-SHA1 of body (legacy compat); omitted if no secret configured |
| `Content-Type` | `application/json` | Always `application/json` |
| `User-Agent` | `Confusio-Hookshot/<version>` | Identifies confusio; differs from GitHub's `GitHub-Hookshot/<hash>` |

**Signature computation:** Both HMAC signatures are computed over the raw delivery
body bytes using the consumer target's configured secret (not the inbound forge
secret).  Consumers verify using `X-Hub-Signature-256` and may fall back to
`X-Hub-Signature` for compatibility with older GitHub webhook clients.

**`User-Agent` difference:** Confusio emits `Confusio-Hookshot/<version>` rather than
GitHub's `GitHub-Hookshot/<hash>`.  Consumers that check `User-Agent` exactly will
need configuration adjustment; consumers that check only `X-GitHub-Event` and
`X-Hub-Signature-256` are unaffected.

### Concrete delivery example

A complete outbound delivery for an `issues` event looks like:

```http
POST /hooks/confusio HTTP/1.1
Host: consumer.example.com
Content-Type: application/json
X-GitHub-Event: issues
X-GitHub-Delivery: 72d3162e-cc78-11e3-81ab-4c9367dc0958
X-Hub-Signature-256: sha256=d57c68ca6f92289e6987d106c9e3f9b2cc4e0b8c6c6f16e6df27b2c5e8d3a14
X-Hub-Signature: sha1=4a7b9b4ee6be63e7f8a9c2d5b1f30819c3dd7a3
User-Agent: Confusio-Hookshot/1.0
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
| `repository` | Repository lifecycle | `created`, `deleted`, `renamed`, `transferred`, `publicized`, `privatized` |
| `member` | Collaborator added or removed | `added`, `removed`, `edited` |
| `milestone` | Milestone lifecycle | `created`, `closed`, `opened`, `edited`, `deleted` |
| `label` | Label lifecycle | `created`, `edited`, `deleted` |
| `commit_comment` | Comment on a commit | `created` |
| `status` | Commit status update | _(no action field — status is a single event)_ |
| `ping` | Sent on webhook registration | _(no action field)_ |

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

Confusio emits `ping` when a new target registration is confirmed.  The `zen` value
is drawn from confusio's own zen endpoint.

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
| `commits[].added` / `removed` / `modified` | Most forges do not include per-file diff in push events; arrays may be empty | All except GitHub passthrough |
| `pull_request.requested_reviewers` | Only forges with native reviewer request events provide this | Varies |
| `release.tarball_url` / `zipball_url` | Emitted when the forge provides download URLs; `null` otherwise | Varies |
| `sender.name` | Not all forges expose the display name; may be `null` | Varies |
| `installation` | Never emitted — confusio is not a GitHub App | All backends |
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
  forge adds or renames its native fields.  Forge-specific details live in `raw`.
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
| `X-Confusio-Action` | action within the event family (e.g. `opened`) | Present when the event has an action; absent for action-less events |
| `X-Confusio-Delivery` | UUID v4, unique per delivery attempt | Always present |
| `X-Confusio-Provider` | originating backend identifier (e.g. `gitea`, `gitlab`) | Always present |
| `X-Confusio-Signature-256` | `sha256=<lowercase hex>` | HMAC-SHA256 of body using target's secret; omitted if no secret configured |
| `Content-Type` | `application/json` | Always `application/json` |
| `User-Agent` | `Confusio-Hookshot/<version>` | Same as GitHub-emulation deliveries |

**Signature computation:** `X-Confusio-Signature-256` is computed over the raw
delivery body bytes using the consumer target's configured secret.  The format
`sha256=<hex>` mirrors the GitHub `X-Hub-Signature-256` convention so consumers can
reuse the same HMAC verification code path.

**Action-less events:** `push`, `create`, `delete`, `fork`, `status`, and `ping` carry
no action field — the event type alone identifies the operation.  For these,
`X-Confusio-Action` is omitted from the delivery headers.

### Namespace

All confusio event family names are lower-snake-case strings in the `confusio.`
namespace when used in subscription filters and configuration, but the header value
carries only the short name without the prefix:

```
X-Confusio-Event: issues       ← short name in header
subscription filter: confusio.issues   ← full name in config
```

The canonical event family names match the GitHub event name set defined in
[Supported event names](#supported-event-names).  This alignment means the same event
taxonomy is used across both output shapes, simplifying mixed deployments.

### Envelope schema

Every confusio-normalized delivery body follows this structure:

```json
{
  "confusio": "1.0",
  "id":        "<uuid>",
  "event":     "<event-family>",
  "action":    "<action or null>",
  "provider":  "<backend>",
  "timestamp": "<iso8601>",
  "data":      { ... },
  "raw":       { ... }
}
```

| Field | Type | R/O | Description |
|-------|------|-----|-------------|
| `confusio` | string | R | Envelope schema version; currently `"1.0"` |
| `id` | string (UUID v4) | R | Unique delivery ID; same value as `X-Confusio-Delivery` header |
| `event` | string | R | Event family name (e.g. `"issues"`, `"push"`) |
| `action` | string or null | R | Action within the event family; `null` for action-less events |
| `provider` | string | R | Originating backend (e.g. `"gitea"`, `"gitlab"`) |
| `timestamp` | string (ISO 8601) | R | Event timestamp — forge-supplied if available, otherwise confusio ingest time |
| `data` | object | R | Normalized field bag; schema is event-family-specific (see below) |
| `raw` | object | R | Original decoded payload from the forge, unmodified |

The `confusio` version field allows consumers to guard against future schema changes:

```json
if (body.confusio !== "1.0") { /* handle unknown version */ }
```

### The `data` object

The `data` object contains the normalized event payload.  Its schema mirrors the
GitHub-emulation output shape with the following differences:

- **No GitHub-specific IDs** — integer IDs that are meaningful only to GitHub are
  replaced with the forge's native identifier.  Both `id` (forge-native) and
  `number` (human-visible reference) are included where available.
- **No `node_id`** — GitHub's GraphQL node ID is not present; confusio does not
  synthesize a GraphQL node ID for the confusio-normalized shape.
- **`source_url` instead of `html_url`** — the forge's own web URL for the resource
  (issue page, PR page, etc.) is in `source_url`.  This makes it clear the URL points
  to the originating forge, not to GitHub.
- **Timestamps always ISO 8601** — all timestamp fields use ISO 8601 format in UTC.
  Fields that are absent from the forge response are `null`, not omitted.

The `data` object for each event family is documented in [Field-Level Mapping Tables](#field-level-mapping-tables).

### Concrete delivery example

A complete outbound delivery for a confusio-normalized `issues:opened` event:

```http
POST /hooks/confusio-normalized HTTP/1.1
Host: consumer.example.com
Content-Type: application/json
X-Confusio-Event: issues
X-Confusio-Action: opened
X-Confusio-Delivery: 72d3162e-cc78-11e3-81ab-4c9367dc0958
X-Confusio-Provider: gitea
X-Confusio-Signature-256: sha256=a3b9f12c8d7e4f01bc6234567890abcd1234ef567890abcd1234ef567890abcd
User-Agent: Confusio-Hookshot/1.0
Content-Length: 712

{ ... envelope body ... }
```

A delivery for an action-less event (no `X-Confusio-Action` header):

```http
POST /hooks/confusio-normalized HTTP/1.1
Host: consumer.example.com
Content-Type: application/json
X-Confusio-Event: push
X-Confusio-Delivery: 83e4273f-dd89-22f4-92bc-5d0478ed1069
X-Confusio-Provider: gitlab
X-Confusio-Signature-256: sha256=b4c0g23d9e8f5g12cd7345678901bcde2345fg678901bcde2345fg678901bcde
User-Agent: Confusio-Hookshot/1.0
Content-Length: 891

{ ... envelope body ... }
```

### Concrete envelope example

A `issues:opened` event originating from Gitea:

```json
{
  "confusio":  "1.0",
  "id":        "72d3162e-cc78-11e3-81ab-4c9367dc0958",
  "event":     "issues",
  "action":    "opened",
  "provider":  "gitea",
  "timestamp": "2024-01-15T10:00:00Z",
  "data": {
    "issue": {
      "id":         1,
      "number":     42,
      "title":      "Found a bug",
      "body":       "Something broke.",
      "state":      "open",
      "source_url": "https://gitea.com/alice/myrepo/issues/42",
      "author": {
        "id":         1,
        "login":      "alice",
        "source_url": "https://gitea.com/alice"
      },
      "labels":     [],
      "assignees":  [],
      "milestone":  null,
      "created_at": "2024-01-15T10:00:00Z",
      "updated_at": "2024-01-15T10:00:00Z",
      "closed_at":  null
    },
    "repository": {
      "id":           100,
      "name":         "myrepo",
      "full_name":    "alice/myrepo",
      "private":      false,
      "source_url":   "https://gitea.com/alice/myrepo",
      "description":  null,
      "fork":         false,
      "default_branch": "main",
      "owner": {
        "id":    1,
        "login": "alice"
      },
      "created_at": "2023-01-01T00:00:00Z",
      "updated_at": "2024-01-15T10:00:00Z",
      "pushed_at":  "2024-01-15T10:00:00Z"
    },
    "sender": {
      "id":         1,
      "login":      "alice",
      "source_url": "https://gitea.com/alice"
    }
  },
  "raw": {
    "action": "opened",
    "issue": {
      "id": 1,
      "number": 42,
      "title": "Found a bug"
    }
  }
}
```

The `raw` object truncated for readability; it contains the complete original forge payload.

### `X-Confusio-Signature-256` verification

Consumer verification follows the same pattern as GitHub's `X-Hub-Signature-256`:

```
secret        = configured consumer target secret (UTF-8 bytes)
body          = raw delivery body bytes
expected      = "sha256=" ++ HMAC-SHA256(secret, body) as lowercase hex
received      = value of X-Confusio-Signature-256

accept if constant_time_equal(expected, received)
```

Verification command (for testing):
```sh
printf '<body>' | openssl dgst -sha256 -hmac '<secret>'
# prepend "sha256=" to the output and compare to X-Confusio-Signature-256
```

### Version negotiation

The `confusio` field in the envelope is the envelope schema version.  Confusio
increments this on breaking changes.  The current version is `"1.0"`.

| Version | Status | Notes |
|---------|--------|-------|
| `1.0` | Current | Initial release |

Additive changes (new optional fields in `data`) do not increment the version.
Breaking changes (renamed/removed fields, changed types) increment the minor or major
version string.  Consumers should treat unknown fields as ignorable.

### Actor schema in `data`

User/actor objects inside `data` use a confusio-specific schema that differs from the
GitHub-emulation shape:

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

### `raw` field behaviour

The `raw` field always contains the original JSON payload decoded from the forge
request body, exactly as received.  No field renaming, translation, or filtering is
applied.

**Edge cases:**

| Situation | `raw` value |
|-----------|-------------|
| Normal delivery | Decoded JSON object from forge body |
| Forge sends empty body | `{}` (empty object) |
| Forge sends a JSON array (unusual) | The decoded array |
| Forge body cannot be decoded as JSON | `null`; confusio logs a warning |

When `raw` is `null`, the `data` object is also `{}` and the event type is
`"unknown"`.  The delivery is still queued so consumers can inspect the original bytes
via the replay API.

### Consistency with GitHub-emulation contract

The following table maps each confusio-normalized header to its GitHub-emulation
equivalent.  Where both shapes carry the same semantic, consumers can share
verification code with a simple header-name substitution.

| Confusio-normalized header | GitHub-emulation equivalent | Same value? |
|---------------------------|----------------------------|-------------|
| `X-Confusio-Event` | `X-GitHub-Event` | Yes — same event family names |
| `X-Confusio-Action` | _(in body only)_ | Confusio promotes action to a header; GitHub keeps it in `action` field |
| `X-Confusio-Delivery` | `X-GitHub-Delivery` | Yes — both are UUID v4 |
| `X-Confusio-Provider` | _(absent)_ | No GitHub equivalent |
| `X-Confusio-Signature-256` | `X-Hub-Signature-256` | Same format (`sha256=<hex>`), different secret |
| _(absent)_ | `X-Hub-Signature` | Confusio does not emit a SHA-1 fallback header |
| `Content-Type` | `Content-Type` | Same |
| `User-Agent` | `User-Agent` | Same (`Confusio-Hookshot/<version>`) |

**Key differences to call out to consumer authors:**

1. `X-Confusio-Action` is a header in the confusio shape; in GitHub-emulation the
   action is only in the JSON body's `action` field.
2. `X-Confusio-Provider` has no GitHub equivalent; use it to route events by source
   forge without inspecting the body.
3. There is no SHA-1 fallback header (`X-Hub-Signature`) in the confusio shape.
   Consumers must use `X-Confusio-Signature-256`.
4. `source_url` in `data` objects corresponds to `html_url` in the GitHub-emulation
   shape — same URL, different key name.
5. `author` in `data` corresponds to `user` in the GitHub-emulation issue/PR objects.

## Field-Level Mapping Tables

Field-level mapping tables specify, for each event family, which GitHub-emulation
output fields can be sourced from each backend and at what fidelity.  The confusio
normalized shape uses the same source data; differences are noted where the output
field name or structure changes.

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
| gitea-family | `gitea`, `forgejo`, `codeberg`, `notabug` |
| gogs | `gogs` (same scheme as gitea-family but separate impl) |
| bitbucket | `bitbucket` (Bitbucket Cloud) |
| bitbucket-dc | `bitbucket_datacenter` |
| gitlab | `gitlab` |
| github | `github` (passthrough; all fields native) |
| gitbucket | `gitbucket` |

Backends with independent implementations are listed individually.

---

### `push`

Triggered when one or more commits are pushed to a branch or tag.

#### Top-level fields

| GitHub field | gitea-family | gogs | gitlab | bitbucket | bitbucket-dc | github | gitbucket | azuredevops | sourcehut | pagure | All others |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `ref` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `before` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `after` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `created` | ✓ | ✓ | ✓ | ~ | ~ | ✓ | ✓ | ~ | ✓ | ✓ | ✗ |
| `deleted` | ✓ | ✓ | ✓ | ~ | ~ | ✓ | ✓ | ~ | ✓ | ✓ | ✗ |
| `forced` | ✓ | ✓ | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ |
| `compare` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✗ | ✓ | ✗ |
| `commits` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `head_commit` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `pusher` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ~ |

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
- `sourcehut`, `pagure`, `gerrit`, `phabricator`, `launchpad`, `radicle`: Create/delete
  events may arrive embedded in a push event rather than as discrete event types.
  Confusio splits them when the push `before` or `after` is all-zero.
- `codecommit`, `kallithea`, `rhodecode`, `tuleap`, `sourceforge`: Create/delete events
  may not be delivered at all depending on forge configuration.  If no event is
  received, the `create` / `delete` event will not be emitted.

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

| GitHub field | gitea-family | gogs | gitlab | bitbucket | bitbucket-dc | github | gitbucket | azuredevops | All others |
|---|---|---|---|---|---|---|---|---|---|
| `action` | ✓ | ~ | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ✗ |
| `repository` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `changes` (renamed) | ✓ | ✗ | ✓ | ~ | ✓ | ✓ | ✗ | ~ | ✗ |
| `sender` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |

**Supported actions by backend:**

| Action | gitea-family | gogs | gitlab | bitbucket | bitbucket-dc | github | gitbucket | azuredevops |
|--------|---|---|---|---|---|---|---|---|
| `created` | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ |
| `deleted` | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ |
| `renamed` | ✓ | ✗ | ✓ | ✗ | ✓ | ✓ | ✗ | ~ |
| `transferred` | ✗ | ✗ | ✓ | ✗ | ✗ | ✓ | ✗ | ✗ |
| `publicized` | ✗ | ✗ | ✓ | ✗ | ✗ | ✓ | ✗ | ✗ |
| `privatized` | ✗ | ✗ | ✓ | ✗ | ✗ | ✓ | ✗ | ✗ |

**Notes:**
- Gogs does not send repository lifecycle webhooks.  The `repository` event is never
  emitted for `gogs`.
- GitBucket only emits repository events for create and delete, and only in newer
  versions.
- `changes` for `renamed`: Gitea-family includes a `changes` object with the old name.
  GitLab sends separate `rename` events with before/after fields.  Azure DevOps sends
  rename notifications via the service hook but without a structured `changes` payload.
- Backends not listed (sourcehut, pagure, kallithea, etc.) do not emit repository
  lifecycle events.  Confusio cannot generate `repository` events from these backends.

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

| Action | gitea-family | gogs | gitlab | bitbucket | bitbucket-dc | github | gitbucket | azuredevops | pagure |
|--------|---|---|---|---|---|---|---|---|---|
| `opened` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `closed` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `reopened` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `edited` | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ | ✓ |
| `labeled` | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✗ | ✓ |
| `unlabeled` | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✗ | ✓ |
| `assigned` | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ |
| `unassigned` | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ |

**Notes:**
- `labels`: Bitbucket Cloud includes label names but not label colors or IDs.
  Bitbucket Datacenter has limited label support depending on version.
- `assignees`: Bitbucket Cloud does not support issue assignees in webhooks.
- `closed_at`: Azure DevOps includes a resolution date but the format differs;
  confusio normalizes to ISO 8601.
- `edited` action: For most backends, the edit event does not include a `changes`
  object (before/after values).  GitHub and GitLab include `changes`; others do not.
  Confusio emits `changes: {}` when not available.
- Backends not listed (sourcehut, gerrit, harness, rhodecode, etc.) do not emit
  issue lifecycle events.

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

| Action | gitea-family | gogs | gitlab | bitbucket | bitbucket-dc | github | gitbucket | pagure |
|--------|---|---|---|---|---|---|---|---|
| `created` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `edited` | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `deleted` | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✗ |

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

| Action | gitea-family | gogs | gitlab | bitbucket | bitbucket-dc | github | gitbucket | azuredevops | pagure |
|--------|---|---|---|---|---|---|---|---|---|
| `opened` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `closed` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `reopened` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| `synchronize` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `edited` | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ | ~ |
| `labeled` | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ |
| `unlabeled` | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ |
| `assigned` | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ |
| `unassigned` | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ |
| `review_requested` | ✓ | ✗ | ✓ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ |
| `review_request_removed` | ✓ | ✗ | ✓ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ |

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

---

### `pull_request_review`

Triggered when a review is submitted or dismissed on a pull request.

| GitHub field | gitea-family | gitlab | bitbucket-dc | github | All others |
|---|---|---|---|---|---|
| `review.id` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `review.body` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `review.state` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `review.html_url` | ✓ | ✓ | ~ | ✓ | ✗ |
| `review.user` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `review.submitted_at` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `pull_request` | ✓ | ✓ | ✓ | ✓ | ✗ |

#### `review.state` mapping

| Forge state | GitHub `review.state` |
|-------------|----------------------|
| Gitea `APPROVED` | `"approved"` |
| Gitea `REQUEST_CHANGES` | `"changes_requested"` |
| Gitea `COMMENT` | `"commented"` |
| GitLab `approved` | `"approved"` |
| GitLab `unapproved` | `"dismissed"` |
| GitLab `commented` | `"commented"` |
| Bitbucket DC `APPROVED` | `"approved"` |
| Bitbucket DC `NEEDS_WORK` | `"changes_requested"` |

#### Supported actions

| Action | gitea-family | gitlab | bitbucket-dc | github |
|--------|---|---|---|---|
| `submitted` | ✓ | ✓ | ✓ | ✓ |
| `dismissed` | ~ | ✓ | ✗ | ✓ |

**Notes:**
- `pull_request_review` events require the forge to have a native review system.
  Bitbucket Cloud, Gogs, GitBucket, Azure DevOps, and most self-hosted forges do not
  emit review events.  The event is never generated for these backends.
- `dismissed` action: Gitea marks a dismissed review by changing state; confusio
  synthesizes the `dismissed` action from a state transition to `dismissed`.  GitLab
  supports explicit dismissal.  Bitbucket Datacenter does not.
- `review.html_url`: Bitbucket Datacenter does not provide a direct URL to the review;
  confusio constructs an approximate URL from the PR URL.

---

### `pull_request_review_comment`

Triggered when a comment is added, edited, or deleted on a pull request review diff.

| GitHub field | gitea-family | gitlab | github | All others |
|---|---|---|---|---|
| `comment.id` | ✓ | ✓ | ✓ | ✗ |
| `comment.body` | ✓ | ✓ | ✓ | ✗ |
| `comment.path` | ✓ | ✓ | ✓ | ✗ |
| `comment.position` | ~ | ~ | ✓ | ✗ |
| `comment.original_position` | ~ | ~ | ✓ | ✗ |
| `comment.diff_hunk` | ✓ | ✓ | ✓ | ✗ |
| `comment.commit_id` | ✓ | ✓ | ✓ | ✗ |
| `comment.original_commit_id` | ~ | ~ | ✓ | ✗ |
| `comment.pull_request_review_id` | ✓ | ✓ | ✓ | ✗ |
| `comment.user` | ✓ | ✓ | ✓ | ✗ |
| `comment.html_url` | ✓ | ✓ | ✓ | ✗ |
| `comment.created_at` | ✓ | ✓ | ✓ | ✗ |
| `comment.updated_at` | ✓ | ✓ | ✓ | ✗ |
| `pull_request` | ✓ | ✓ | ✓ | ✗ |

#### Supported actions

| Action | gitea-family | gitlab | github |
|--------|---|---|---|
| `created` | ✓ | ✓ | ✓ |
| `edited` | ✓ | ✓ | ✓ |
| `deleted` | ✓ | ✓ | ✓ |

**Notes:**
- `comment.position`: GitHub uses a position index within the diff hunk.  Gitea and
  GitLab use line numbers instead.  Confusio maps the line number to `position` as a
  best-effort approximation; the value may not match GitHub's exact position encoding.
  Stub: `null` when approximation is not possible.
- `comment.original_position`: The position in the original diff before any force-pushes.
  Gitea and GitLab provide line-number equivalents; confusio applies the same approximation
  as `position`.  Stub: same as `position` when unavailable.
- `comment.original_commit_id`: The commit SHA at which the comment was originally placed,
  before any subsequent force-push moved the head.  Gitea and GitLab provide this in some
  versions; confusio falls back to `commit_id` when absent.
- `comment.pull_request_review_id`: The enclosing review's ID.  Both Gitea and GitLab
  include this in their review comment payloads.
- Most forges do not expose diff-level review comments in webhooks.  Backends not
  listed always emit `✗` for this event.

---

### `commit_comment`

Triggered when a comment is created directly on a commit (not a PR or review).

| GitHub field | gitea-family | gogs | gitlab | github | gitbucket | All others |
|---|---|---|---|---|---|---|
| `comment.id` | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| `comment.body` | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| `comment.commit_id` | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| `comment.path` | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| `comment.position` | ~ | ~ | ~ | ✓ | ✓ | ✗ |
| `comment.line` | ~ | ~ | ~ | ✓ | ✓ | ✗ |
| `comment.user` | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| `comment.html_url` | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| `comment.created_at` | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| `comment.updated_at` | ✓ | ~ | ✓ | ✓ | ✓ | ✗ |

**Notes:**
- `position` and `line`: Gitea, Gogs, and GitLab use line-number references; confusio maps
  these to `position` and `line` with a note that the encoding differs from GitHub's.
  Stub: `null` when not available.
- `comment.updated_at`: Gogs webhook payloads do not always include an update timestamp;
  confusio falls back to `created_at` when `updated_at` is absent.
- Backends not listed (Bitbucket, Azure DevOps, etc.) do not emit commit comment events.

---

### `release`

Triggered on release lifecycle events.

#### Release object fields

| GitHub field | gitea-family | gitlab | github | gitbucket | All others |
|---|---|---|---|---|---|
| `release.id` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `release.tag_name` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `release.name` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `release.body` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `release.draft` | ✓ | ✗ | ✓ | ✓ | ✗ |
| `release.prerelease` | ✓ | ~ | ✓ | ✓ | ✗ |
| `release.html_url` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `release.tarball_url` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `release.zipball_url` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `release.author` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `release.created_at` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `release.published_at` | ✓ | ✓ | ✓ | ✓ | ✗ |

#### Supported actions

| Action | gitea-family | gitlab | github | gitbucket |
|--------|---|---|---|---|
| `published` | ✓ | ✓ | ✓ | ✓ |
| `edited` | ✓ | ✓ | ✓ | ✗ |
| `deleted` | ✓ | ✓ | ✓ | ✓ |
| `prereleased` | ✓ | ~ | ✓ | ✗ |

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
- **Gogs**: Gogs has limited and version-dependent release webhook support.  Early Gogs
  versions do not fire release events at all; later versions fire `published` and `deleted`
  only.  Gogs is grouped under "All others" (`✗`) in the table above; operators should
  verify their Gogs version supports release webhooks before relying on this event.
- Backends not listed (Bitbucket, Azure DevOps, etc.) do not emit release lifecycle events.

---

### `status`

Triggered when a commit status is created or updated.  This event is in the CI/CD category:
it carries the result of an external CI, security scan, or deployment check against a specific
commit SHA.

| GitHub field | github | gitbucket | gitlab | gitea-family | All others |
|---|---|---|---|---|---|
| `id` | ✓ | ✓ | ~ | ~ | ✗ |
| `sha` | ✓ | ✓ | ✓ | ~ | ✗ |
| `name` | ✓ | ✓ | ~ | ~ | ✗ |
| `state` | ✓ | ✓ | ✓ | ~ | ✗ |
| `description` | ✓ | ✓ | ~ | ~ | ✗ |
| `target_url` | ✓ | ✓ | ✓ | ~ | ✗ |
| `context` | ✓ | ✓ | ~ | ~ | ✗ |
| `created_at` | ✓ | ✓ | ✓ | ~ | ✗ |
| `updated_at` | ✓ | ✓ | ✓ | ~ | ✗ |
| `commit` | ✓ | ✓ | ~ | ~ | ✗ |
| `branches` | ✓ | ✓ | ~ | ✗ | ✗ |

**`state` mapping:**

| Forge state | GitHub `state` |
|-------------|---------------|
| `success` / `passed` | `success` |
| `failure` / `failed` | `failure` |
| `error` / `cancelled` | `error` |
| `pending` / `running` | `pending` |

**Notes:**
- **GitHub / GitBucket**: Native `status` webhook events.  All fields present verbatim.
- **GitLab**: Pipeline events are mapped to `status`.  `id` is the pipeline ID.  `context` is
  synthesized as `"ci/<pipeline-name>"` or `"ci/<stage>/<job>"` for job-level events.  `name`
  is the repository full path.  `branches` is back-fetched via the REST API when the pipeline
  provides a `ref`; omitted on failure.
- **gitea-family**: Gitea does not emit a dedicated commit status webhook.  Confusio synthesizes
  `status` events from Gitea's workflow/actions events when available — the `~` symbol reflects
  that synthesis requires Gitea Actions to be enabled and does not fire for external CI that
  only sets commit statuses via the API.  `id` is the workflow run ID.  `branches` is not
  available and is emitted as `[]` (stub).
- Backends not listed (Bitbucket, Bitbucket DC, Azure DevOps, Pagure, etc.) do not produce
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
| `changes` | ✓ | ✓ | ✗ | ✗ | ✗ |

#### Supported actions

| Action | github | gitbucket | gitea-family | gitlab |
|--------|---|---|---|---|
| `added` | ✓ | ✓ | ✓ | ✓ |
| `removed` | ✓ | ✓ | ✓ | ✓ |
| `edited` | ✓ | ✗ | ✗ | ✗ |

**Notes:**
- `member.type`: gitea-family always emits `"User"` (teams are not surfaced here).  GitLab
  emits the member's role (`"Reporter"`, `"Developer"`, etc.) in the `type` field; confusio
  normalizes to `"User"`.
- `changes`: Only populated for the `edited` action on GitHub and GitBucket.  gitea-family and
  GitLab do not include permission change details; confusio emits `changes: {}`.
- GitLab org-level member events (project-group membership) are mapped to `member` with a
  synthetic `repository` constructed from the project path.
- Backends not listed do not emit collaborator lifecycle events.

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

| Action | gitea-family | gitlab | github | gitbucket |
|--------|---|---|---|---|
| `created` | ✓ | ✓ | ✓ | ✓ |
| `closed` | ✓ | ✓ | ✓ | ✓ |
| `opened` | ✓ | ✓ | ✓ | ✓ |
| `edited` | ✓ | ✓ | ✓ | ✓ |
| `deleted` | ✓ | ✗ | ✓ | ✓ |

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

| Action | gitea-family | gitlab | github | gitbucket |
|--------|---|---|---|---|
| `created` | ✓ | ✓ | ✓ | ✓ |
| `edited` | ✓ | ✓ | ✓ | ✓ |
| `deleted` | ✓ | ✗ | ✓ | ✓ |

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

### `ping`

The `ping` event is synthetic.  It is emitted by confusio itself — not translated from an
inbound forge event — when a new webhook target registration is confirmed.

No per-backend field coverage table applies: all `ping` fields are generated by confusio
regardless of the originating backend.

| Field | Source | Notes |
|-------|--------|-------|
| `zen` | Confusio | Drawn from confusio's own zen endpoint (`GET /zen`). |
| `hook_id` | Confusio | The confusio-assigned registration ID for the new target. |
| `hook.type` | Confusio | Always `"Repository"`. |
| `hook.id` | Confusio | Same as `hook_id`. |
| `hook.active` | Confusio | Always `true` at registration time. |
| `hook.events` | Confusio | The event filter list from the registration request, or `["*"]`. |
| `hook.config.url` | Confusio | The target's delivery URL. |
| `hook.config.content_type` | Confusio | Always `"json"`. |
| `hook.created_at` | Confusio | ISO 8601 timestamp of the registration. |
| `hook.updated_at` | Confusio | Same as `created_at` at registration time. |
| `repository` | Confusio | Constructed from confusio's view of the repository. |
| `sender` | Confusio | The confusio service user; `login` is `"confusio[bot]"`. |

**Notes:**
- Some forges also emit their own ping-equivalent on webhook creation (Gitea, GitHub,
  GitBucket).  Those inbound pings are consumed by confusio during webhook registration
  confirmation but are not forwarded to targets — confusio emits exactly one synthetic
  `ping` per registration regardless.

---

### CI/CD events beyond `status`

The events below are GitHub-native CI/CD events.  In GitHub-emulation shape, confusio can
only emit them when the originating backend is GitHub itself.  For all other backends, these
event families are **not available** in the emulation output; pipeline activity is instead
surfaced via the `status` event (see above).

| GitHub event | Emitted from GitHub backend | Emitted from other backends |
|---|---|---|
| `check_run` | ✓ pass-through | ✗ |
| `check_suite` | ✓ pass-through | ✗ |
| `workflow_run` | ✓ pass-through | ✗ |
| `workflow_job` | ✓ pass-through | ✗ |
| `deployment` | ✓ pass-through | ✗ |
| `deployment_status` | ✓ pass-through | ✗ |

For cross-forge CI/CD signal in confusio-normalized shape the `status` event provides a
consistent envelope regardless of backend.  Future work may add a `pipeline_run` event
family in the normalized model that exposes richer pipeline metadata (stages, jobs, artifacts)
beyond what `status` can express.

---

### Security events

No security event families are currently in scope for the GitHub-emulation output.
GitHub's `security_advisory`, `secret_scanning_alert`, `dependabot_alert`, and
`code_scanning_alert` events are GitHub-specific and have no cross-forge equivalents in
any backend confusio supports.

When the originating backend is GitHub itself, these events are passed through verbatim as
GitHub-emulation webhooks (no field translation needed).  For all other backends they are
silently dropped — there is no mapping target.

Future work may introduce confusio-normalized `security_finding` or `advisory` event
families for backends that expose vulnerability or secret-scanning data through their own
APIs (e.g. GitLab's security findings, Gitea's audit log).

---

### Org events

The only org-category event currently in the GitHub-emulation output is `member` (see above).
The following GitHub event families have no cross-forge mapping today:

| GitHub event | Status | Reason |
|---|---|---|
| `organization` | ✗ | Org lifecycle events (creation, deletion, rename) are not emitted by any non-GitHub forge as webhooks. |
| `membership` | ✗ | Team membership changes are not exposed as webhook events by Gitea, GitLab, or other backends. |
| `team` | ✗ | Team CRUD events are GitHub-specific. |
| `team_add` | ✗ | Repository-to-team addition events are GitHub-specific. |
| `org_block` | ✗ | No cross-forge equivalent. |

When the originating backend is GitHub, these events pass through verbatim.  For all other
backends they are silently dropped.

## Delivery Semantics

Every accepted inbound event is written to a durable outbox before any delivery
attempt begins.  The outbox guarantees at-least-once delivery: if confusio crashes or
is restarted between ingest and delivery, surviving events are retried on restart.

### Guarantee: at-least-once

Confusio guarantees that each event will be delivered **at least once** to each
matching target.  It does **not** guarantee exactly-once delivery.  Consumers must
be idempotent with respect to duplicate deliveries.

Duplicate deliveries arise in two scenarios:

1. **Crash after send, before acknowledgement** — Confusio sent the HTTP request but
   did not record the 2xx response before the process died.  On restart the delivery
   is retried from `pending`.
2. **Explicit replay** — An operator or consumer calls the replay API to re-send a
   previously delivered event.  Each replay creates a new delivery attempt with a new
   `X-GitHub-Delivery` / `X-Confusio-Delivery` UUID.

The `X-GitHub-Delivery` and `X-Confusio-Delivery` headers carry the **ingest-time**
delivery ID generated when the event first arrived.  This ID is stable across retries
for the same delivery attempt.  Each _replay_ generates a fresh UUID so consumers can
distinguish original deliveries from explicit re-sends by comparing IDs.

### Durable outbox

The outbox is a filesystem directory tree persisted to disk before any HTTP delivery
attempt.  On startup confusio scans the outbox for pending and in-flight deliveries and
enqueues them for retry.

**Directory layout:**

```
{outbox_dir}/
  events/
    {delivery_id}.json          ← event record (immutable after write)
  targets/
    {target_id}/
      {delivery_id}.json        ← per-target delivery state record
```

Both `{delivery_id}` and `{target_id}` are UUID v4 strings.

**Event record** (`events/{delivery_id}.json`):

```json
{
  "delivery":   "<uuid>",
  "ingested_at": "<iso8601>",
  "provider":   "<backend>",
  "event":      "<event-family>",
  "action":     "<action or null>",
  "github_payload":   { ... },
  "confusio_payload": { ... }
}
```

| Field | Description |
|-------|-------------|
| `delivery` | Ingest-time UUID v4; matches `X-GitHub-Delivery` / `X-Confusio-Delivery` for the first attempt |
| `ingested_at` | ISO 8601 UTC timestamp when confusio accepted the inbound request |
| `provider` | Originating backend (e.g. `"gitea"`) |
| `event` | Canonical event family name (e.g. `"issues"`) |
| `action` | Action within the family, or `null` for action-less events |
| `github_payload` | Pre-translated GitHub-emulation payload object |
| `confusio_payload` | Pre-translated confusio-normalized payload object |

Both payload variants are serialized at ingest time so that retries and replays
re-send the original translated payload, not a retranslation of a stale forge payload.

**Per-target delivery state record** (`targets/{target_id}/{delivery_id}.json`):

```json
{
  "delivery":     "<uuid>",
  "target_id":    "<uuid>",
  "status":       "pending",
  "attempts":     [],
  "next_attempt": "<iso8601 or null>"
}
```

| Field | Description |
|-------|-------------|
| `delivery` | Ingest-time delivery UUID |
| `target_id` | Target UUID |
| `status` | Current state — see [Delivery lifecycle](#delivery-lifecycle) |
| `attempts` | Array of attempt records (see below) |
| `next_attempt` | ISO 8601 UTC timestamp of the scheduled next attempt; `null` when not retrying |

**Attempt record** (one entry per HTTP delivery attempt):

```json
{
  "attempt_id":     "<uuid>",
  "attempted_at":   "<iso8601>",
  "duration_ms":    142,
  "response_status": 200,
  "response_body":  "<first 1024 bytes of response body>",
  "outcome":        "delivered"
}
```

| Field | Description |
|-------|-------------|
| `attempt_id` | UUID v4 unique to this attempt.  For automatic retries (attempts 1–8), `X-GitHub-Delivery` / `X-Confusio-Delivery` still carries the ingest-time `delivery` UUID — `attempt_id` is a per-attempt audit identifier only.  For explicit replays, a fresh UUID is generated and serves as both the `attempt_id` and the delivery header value, allowing consumers to distinguish replays from original deliveries; see [Replay a delivery](#replay-a-delivery). |
| `attempted_at` | ISO 8601 UTC timestamp when the HTTP request was sent |
| `duration_ms` | Round-trip time in milliseconds; `null` on connection failure |
| `response_status` | HTTP response status code; `null` on connection failure |
| `response_body` | First 1 024 bytes of the response body (for debugging); `null` on connection failure |
| `outcome` | `"delivered"`, `"error"`, `"timeout"`, or `"connection_error"` — see below |

**`outcome` values** capture the result of a single HTTP delivery attempt.  They are
distinct from the overall delivery `status`, which reflects whether more attempts will
follow.

| `outcome` value | Meaning | Retry follows? |
|-----------------|---------|---------------|
| `"delivered"` | Target returned a 2xx response | No — delivery state becomes `delivered` |
| `"error"` | Target returned a non-2xx response; see `response_status` | Yes, unless retry budget exhausted |
| `"timeout"` | No response received within the 10-second window | Yes, unless retry budget exhausted |
| `"connection_error"` | Network-level failure (DNS, refused connection, TLS) | Yes, unless retry budget exhausted |

The delivery `status` field in the parent state record reflects the aggregate:
`"retrying"` means the last attempt had a non-`"delivered"` outcome and a retry is
scheduled; `"failed"` means no further automatic retries will occur.

### Delivery lifecycle

Each per-target delivery state record transitions through the following states:

```
pending ──▶ in_flight ──▶ delivered   (2xx response)
                      ──▶ retrying    (non-2xx or timeout; attempts remain)
                      ──▶ failed      (max retries exhausted or event expired)
ignored                               (event filtered out for this target)
```

| State | Description |
|-------|-------------|
| `pending` | Queued; no attempt has been made yet |
| `in_flight` | HTTP request is in progress |
| `delivered` | Terminal success — target returned a 2xx response |
| `retrying` | Delivery failed; a retry is scheduled |
| `failed` | Terminal failure — max retries exhausted or event older than retention window |
| `ignored` | Terminal — event type did not match this target's filter; no delivery attempted |

**Terminal states** — `delivered`, `failed`, and `ignored` are final.  A delivery state
in a terminal state is not retried automatically.  The replay API can initiate a new
attempt regardless of the current state.

**In-flight on restart** — If confusio restarts while a delivery is `in_flight`, the
state reverts to `pending` on startup.  The previous in-flight attempt may or may not
have reached the target; this is the source of the at-least-once (not exactly-once)
guarantee.

### Success condition

A delivery attempt is considered **successful** if the target returns any HTTP 2xx
status code (`200`–`299`) within the response timeout.  The response body is captured
for inspection but its content is not validated.

### Failure conditions and retry triggers

A delivery attempt is marked as **failed** (and a retry scheduled) when any of the
following occur:

| Condition | Notes |
|-----------|-------|
| Connection refused or DNS failure | Network-level error; `duration_ms` is `null` |
| TLS handshake failure | Treated as a connection error |
| Response timeout exceeded | Default: 10 seconds per attempt |
| HTTP 3xx redirect | Confusio does not follow redirects; 3xx is treated as non-2xx |
| HTTP 4xx or 5xx response | Any non-2xx response triggers a retry |

**Redirect note:** Confusio intentionally does not follow HTTP redirects.  Redirect
loops and open-redirect attacks on delivery targets are prevented at the cost of
requiring operators to configure the final canonical URL.

### Retry schedule

Failed delivery attempts are retried with exponential backoff.  Jitter (±10 % of the
base delay) is added to spread load across targets that share a failure window.

| Attempt # | Base delay after failure | With ±10 % jitter |
|-----------|--------------------------|-------------------|
| 1 (initial) | — | — |
| 2 | 30 s | 27 s – 33 s |
| 3 | 1 min | 54 s – 66 s |
| 4 | 5 min | 4.5 min – 5.5 min |
| 5 | 30 min | 27 min – 33 min |
| 6 | 2 h | 1 h 48 min – 2 h 12 min |
| 7 | 8 h | 7 h 12 min – 8 h 48 min |
| 8 (final) | 24 h | 21 h 36 min – 26 h 24 min |

After the 8th attempt fails, the delivery state transitions to `failed`.  The event
record is retained in the outbox until the [retention window](#retention-and-pruning)
expires, and can be replayed manually.

**Maximum total elapsed time** from ingest to final failure: approximately 36 h at
the upper end of jitter.

**Retry budget override** — future work may allow per-target configuration of the
maximum retry count and schedule.  Until then, the schedule above applies to all targets.

### Retry budget

To prevent a single high-volume incident from consuming unbounded system resources,
confusio enforces a **per-target hourly retry budget**.  The budget limits how many
delivery attempts confusio will dispatch to a given target within a rolling 60-minute
window, across all events.

**Default limits:**

| Limit | Value | Notes |
|-------|-------|-------|
| Attempts per target per hour | 50 | Counted across all in-flight deliveries to that target |
| Attempts per target per day | 500 | Rolling 24-hour window |

When a target's hourly budget is exhausted, any pending retry for that target is held
without advancing its `next_attempt` timestamp until the budget refills.  If
`next_attempt` has already passed (the retry was due but could not fire), the field
retains the original scheduled time; the implementation re-checks the budget on each
scheduler tick and dispatches as soon as capacity is available.  Budget
consumption is recorded in a lightweight counter alongside the target state — it does
not affect the attempt records or `status` fields.  A `status` of `retrying` with a
`next_attempt` in the past indicates budget-hold.

**Budget and the retry schedule:** Budget exhaustion delays a retry but does not consume
the retry slot.  If attempt #4 is due at 14:00 but the hourly budget refills at 14:15,
the attempt fires at 14:15 and the slot is used normally.  Delays caused by budget
exhaustion are not reflected in the backoff schedule — the next delay after the attempt
is calculated from the original schedule, not from the delayed actual time.

**Budget counter persistence:** Budget counters are persisted in
`targets/{target_id}/budget.json`, updated atomically on every dispatched attempt and on
each scheduled hourly/daily refill tick.  Counters survive process restarts.  On restart
confusio reads the persisted counters and continues from the last saved state; no attempt
slot is lost or double-counted.

**Budget and circuit breaker:** Budget limits are checked before the circuit breaker
(see below).  A target with an open circuit does not consume budget, because no attempts
are dispatched.  When the circuit closes and paused retries resume, they are subject to
the current budget balance — if the budget is exhausted at that moment the retries are
held until it refills.  The budget counter is not reset when a circuit opens or closes;
the rolling window continues uninterrupted.

### Circuit breaker

Confusio applies a per-target circuit breaker to protect both confusio and persistently
failing targets from repeated futile delivery attempts.

**Threshold:** After **5 consecutive non-`"delivered"` outcomes** across any events for a
target, confusio opens the circuit for that target.

**Open circuit behaviour:**
- Existing `retrying` deliveries for the target are paused — `next_attempt` is cleared
  and a new field `circuit_open_until` is set on the target state record.
- New events arriving for the target are queued as `pending` but no delivery attempt is
  made immediately.
- The circuit remains open for **30 minutes**.

**Half-open probe:**
- After 30 minutes, confusio selects the oldest `pending` delivery for the target and
  dispatches a single probe attempt.
- If the probe succeeds (2xx): circuit closes, all `pending` deliveries resume their
  retry schedules, consecutive-failure counter resets to 0.
- If the probe fails: circuit stays open, `circuit_open_until` is advanced by another
  30 minutes, `consecutive_failures` increments.  After the circuit has opened,
  `consecutive_failures` continues incrementing on each failed probe but does not
  change the recovery behaviour — every failed probe simply extends the open window by
  30 minutes regardless of the counter's magnitude.  The counter is a diagnostic metric;
  confusio does not impose a secondary "give up" threshold.

**Target state record additions for circuit breaker:**

```json
{
  "circuit": "open",
  "circuit_open_until": "<iso8601>",
  "consecutive_failures": 7
}
```

| Field | Description |
|-------|-------------|
| `circuit` | `"closed"` (normal), `"open"` (blocking), or `"half_open"` (probe in progress) |
| `circuit_open_until` | ISO 8601 UTC timestamp when the circuit will move to `half_open`; `null` when `"closed"` |
| `consecutive_failures` | Count of consecutive non-`"delivered"` outcomes; resets to 0 on any success |

These fields are per-target (not per-delivery).  They are stored in a separate
`targets/{target_id}/circuit.json` file alongside the per-delivery state records.

**Circuit breaker and replay:**  Replays bypass the circuit breaker.  If an operator
calls `POST /webhooks/deliveries/{delivery_id}/redeliver` while the circuit is open,
the replay attempt is dispatched immediately.  A successful replay does **not** close
the circuit — only the automatic half-open probe can close it.  A failed replay does
**not** advance the consecutive-failure counter.

**Circuit breaker and the `GET /webhooks/targets/{target_id}` endpoint:**  The target
detail response (defined in the multi-target dispatch section) includes the current
`circuit` state and `circuit_open_until` timestamp so operators can diagnose delivery
pauses.

### Retention and pruning

Outbox records are retained for **72 hours** from `ingested_at`, regardless of delivery
state.  After 72 hours:

- Event records are eligible for pruning.
- Per-target delivery state records are pruned together with their event.
- Events that have not reached a terminal state by the 72-hour mark transition to
  `failed` and are pruned on the next cleanup pass.

Pruning runs on a background timer during normal operation and on startup.  Pruned
records are not recoverable — the replay API returns `404` for pruned delivery IDs.

**Retention window rationale:** 72 hours matches GitHub's own webhook delivery
retention, making it familiar to operators migrating consumers from GitHub.

### Response timeout

Each delivery attempt waits at most **10 seconds** for the target to respond.  If no
response is received within 10 seconds the attempt is recorded as a `"timeout"` outcome
and a retry is scheduled.

The 10-second limit applies to the full round trip (connection + TLS + headers +
body).  It is not separately configurable in the current design.

---

## Replay API

The replay API allows operators and consumers to inspect the delivery history of any
event in the retention window and to trigger additional delivery attempts.

All replay endpoints require **admin credentials** — the same authentication used for
the target registration surface.  Unauthenticated requests receive `401 Unauthorized`.

### Error response format

All replay API endpoints use a consistent JSON error body:

```json
{
  "error": "<machine-readable code>",
  "message": "<human-readable description>"
}
```

| HTTP status | `error` code | When |
|-------------|-------------|------|
| `400 Bad Request` | `"invalid_request"` | Request body is not valid JSON, or a required field has the wrong type |
| `400 Bad Request` | `"unknown_target"` | A UUID in `target_ids` does not match any registered target |
| `401 Unauthorized` | `"unauthorized"` | Missing or invalid admin credentials |
| `404 Not Found` | `"delivery_not_found"` | Delivery UUID does not exist or has been pruned from the outbox |
| `404 Not Found` | `"target_not_found"` | Target UUID does not exist |
| `429 Too Many Requests` | `"rate_limited"` | Admin API rate limit exceeded; `Retry-After` header is set |

**Example error response:**

```http
HTTP/1.1 404 Not Found
Content-Type: application/json

{
  "error": "delivery_not_found",
  "message": "Delivery 72d3162e-cc78-11e3-81ab-4c9367dc0958 not found. It may have been pruned after the 72-hour retention window."
}
```

### Base path

```
/webhooks/deliveries
```

### List recent deliveries

```
GET /webhooks/deliveries
```

Returns deliveries in reverse chronological order (newest first) across all targets.
Supports cursor-based pagination using the `cursor` and `per_page` query parameters.

**Query parameters:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `per_page` | `30` | Items per page; max `100` |
| `cursor` | _(start)_ | Opaque pagination cursor from a previous response's `next_cursor` |
| `event` | _(all)_ | Filter by event family name (e.g. `issues`) |
| `provider` | _(all)_ | Filter by originating backend (e.g. `gitea`) |
| `status` | _(all)_ | Filter by delivery state: `pending`, `in_flight`, `delivered`, `retrying`, `failed`, `ignored` |

**Response** (`200 OK`):

```json
{
  "deliveries": [
    {
      "delivery":     "<uuid>",
      "ingested_at":  "<iso8601>",
      "provider":     "<backend>",
      "event":        "<event-family>",
      "action":       "<action or null>",
      "target_count": 3,
      "delivered":    2,
      "failed":       0,
      "pending":      1
    }
  ],
  "next_cursor": "<opaque string or null>"
}
```

`next_cursor` is `null` when there are no further pages.

### Get a delivery

```
GET /webhooks/deliveries/{delivery_id}
```

Returns the full event record plus per-target delivery state for every registered target.

**Path parameters:**

| Parameter | Description |
|-----------|-------------|
| `delivery_id` | UUID v4; ingest-time delivery ID |

**Response** (`200 OK`):

```json
{
  "delivery":         "<uuid>",
  "ingested_at":      "<iso8601>",
  "provider":         "<backend>",
  "event":            "<event-family>",
  "action":           "<action or null>",
  "github_payload":   { ... },
  "confusio_payload": { ... },
  "targets": [
    {
      "target_id":    "<uuid>",
      "status":       "delivered",
      "next_attempt": null,
      "attempts": [
        {
          "attempt_id":      "<uuid>",
          "attempted_at":    "<iso8601>",
          "duration_ms":     142,
          "response_status": 200,
          "response_body":   "",
          "outcome":         "delivered"
        }
      ]
    }
  ]
}
```

**Error responses** (see [Error response format](#error-response-format) for body schema):

| Code | `error` code | When |
|------|-------------|------|
| `401 Unauthorized` | `"unauthorized"` | Missing or invalid admin credentials |
| `404 Not Found` | `"delivery_not_found"` | Delivery UUID unknown or pruned |

### List attempts for a target

```
GET /webhooks/deliveries/{delivery_id}/targets/{target_id}/attempts
```

Returns the attempt history for a single target.  Useful for inspecting retry progression
without the full delivery record.

**Response** (`200 OK`):

```json
{
  "delivery":  "<uuid>",
  "target_id": "<uuid>",
  "status":    "retrying",
  "attempts": [
    {
      "attempt_id":      "<uuid>",
      "attempted_at":    "<iso8601>",
      "duration_ms":     null,
      "response_status": null,
      "response_body":   null,
      "outcome":         "timeout"
    },
    {
      "attempt_id":      "<uuid>",
      "attempted_at":    "<iso8601>",
      "duration_ms":     5021,
      "response_status": 503,
      "response_body":   "Service Unavailable",
      "outcome":         "error"
    }
  ]
}
```

**Error responses** (see [Error response format](#error-response-format) for body schema):

| Code | `error` code | When |
|------|-------------|------|
| `401 Unauthorized` | `"unauthorized"` | Missing or invalid admin credentials |
| `404 Not Found` | `"delivery_not_found"` | Delivery UUID unknown or pruned |
| `404 Not Found` | `"target_not_found"` | Target UUID does not exist for this delivery |

### Replay a delivery

```
POST /webhooks/deliveries/{delivery_id}/redeliver
```

Triggers an immediate additional delivery attempt for all matching targets.  The
current `status` of each target does not matter — the replay schedules a new attempt
regardless of whether the delivery previously succeeded, failed, or was ignored.

Each replay attempt receives a **fresh UUID** as its `attempt_id`.  This ID is used as
the `X-GitHub-Delivery` / `X-Confusio-Delivery` header value for that attempt, allowing
consumers to distinguish replays from original deliveries.  The ingest-time delivery UUID
embedded in the event body (`id` field in the confusio-normalized shape) does **not**
change — it always identifies the original ingest event.

**Replay bypasses the circuit breaker and retry budget.**  The attempt is dispatched
immediately regardless of whether the target's circuit is open or its hourly budget is
exhausted.  See [Circuit breaker](#circuit-breaker) for how replay interacts with the
circuit state.

**Request body (optional):**

```json
{
  "target_ids": ["<uuid>", "<uuid>"]
}
```

If `target_ids` is provided, only the specified targets receive the replay.  If absent
or empty, all matching targets are re-delivered.

**Response** (`202 Accepted`):

```json
{
  "delivery":      "<uuid>",
  "replayed_to":   ["<uuid>", "<uuid>"],
  "attempt_ids":   ["<uuid>", "<uuid>"]
}
```

| Field | Description |
|-------|-------------|
| `delivery` | The original ingest-time delivery UUID |
| `replayed_to` | Target UUIDs that received the replay |
| `attempt_ids` | Attempt UUIDs generated for this replay, one per target in `replayed_to` order |

**Error responses** (see [Error response format](#error-response-format) for body schema):

| Code | `error` code | When |
|------|-------------|------|
| `400 Bad Request` | `"invalid_request"` | Request body is not valid JSON, or a field has the wrong type |
| `400 Bad Request` | `"unknown_target"` | A UUID in `target_ids` does not match any registered target |
| `401 Unauthorized` | `"unauthorized"` | Missing or invalid admin credentials |
| `404 Not Found` | `"delivery_not_found"` | Delivery UUID unknown or pruned |

Note: a target registered _after_ the event was ingested is still a valid `target_ids`
entry.  It has no prior delivery state record, so confusio creates one and dispatches the
attempt; this counts against neither the retry budget nor the retry schedule — it is
treated as a fresh first attempt.

**Interaction with pending retries:**  If a target's delivery is currently `in_flight`
(a scheduled retry is executing), the replay is accepted and dispatched as a separate
parallel attempt.  Both attempts proceed independently; if both succeed, both are
recorded in the attempt log and the delivery state remains `delivered`.  If the in-flight
retry succeeds first, the replay attempt still completes — the target may receive two
requests.  This is the expected at-least-once behaviour; consumers must be idempotent.

**Interaction with `retrying` state:**  If a target's delivery is `retrying` (an attempt
failed; the next retry is scheduled but not yet in-flight), the replay fires immediately
and the existing scheduled retry remains on its original schedule.  The next automatic
retry fires regardless of whether the replay succeeded.

**Replay of ignored events:** If a target previously received `ignored` for an event
(because the event type was outside its filter at ingest time), a replay will attempt
delivery regardless of the current filter configuration.  Operators can use this to
recover events that were misconfigured at subscription time.

**Replay of expired events:** If the event record has been pruned from the outbox
(> 72 hours), the delivery UUID returns `404` and replay is not possible.  The original
forge payload is not retained after pruning.

### Delivery list for a target

```
GET /webhooks/targets/{target_id}/deliveries
```

Returns deliveries in reverse chronological order for a single target.  Supports the
same query parameters as `GET /webhooks/deliveries` (except `status` refers to the
per-target state for this target).

**Response** (`200 OK`):

```json
{
  "deliveries": [
    {
      "delivery":        "<uuid>",
      "ingested_at":     "<iso8601>",
      "provider":        "<backend>",
      "event":           "<event-family>",
      "action":          "<action or null>",
      "status":          "delivered",
      "attempt_count":   1,
      "last_attempt_at": "<iso8601>"
    }
  ],
  "next_cursor": "<opaque string or null>"
}
```

**Error responses** (see [Error response format](#error-response-format) for body schema):

| Code | `error` code | When |
|------|-------------|------|
| `401 Unauthorized` | `"unauthorized"` | Missing or invalid admin credentials |
| `404 Not Found` | `"target_not_found"` | Target UUID does not exist |

---

### Edge cases

| Scenario | Behaviour |
|----------|-----------|
| Target URL unreachable at every attempt | Final attempt exhausted → `failed`; replay available while within retention window |
| Target registered after an event was ingested | The late-registered target does not receive events ingested before registration |
| Event pruned during a retry window | In-flight attempt may still proceed; on next scheduled retry the event is found pruned and the state transitions to `failed` |
| Replay requested for a `delivered` event | Accepted; attempt dispatched regardless of prior success; target may receive a duplicate |
| Two replays issued concurrently for the same target | Both are accepted; each generates a distinct `attempt_id`; the target receives two requests |
| Replay issued while target's retry is `in_flight` | Both proceed in parallel; both outcomes recorded; at-least-once behaviour — consumer must be idempotent |
| Replay issued while target's delivery is `retrying` | Replay fires immediately; scheduled retry fires on its original schedule; target may receive two requests |
| Hourly retry budget exhausted for a target | Pending retries are held without advancing `next_attempt`; next attempt fires when budget refills |
| Circuit opens mid-backoff | Remaining retries are paused; `next_attempt` is cleared; circuit probe fires after 30 minutes |
| Circuit probe succeeds | Circuit closes; all paused `pending` deliveries resume their retry schedules |
| Circuit probe fails | Circuit stays open; `circuit_open_until` advances by 30 minutes |
| Replay while circuit is open | Replay bypasses circuit; dispatched immediately; outcome does not affect circuit state |
| Hourly budget exhausted and circuit closes simultaneously | Retries resume from `pending` after circuit close but are immediately held by budget; they fire as soon as the budget refills in the rolling window |
| `target_ids` in replay includes a target registered after the event was ingested | The target has no delivery state record for this event; `redeliver` accepts the UUID, creates a new delivery state record for that target, and dispatches the attempt as if the target had been matched at ingest time |
| Replay with all matching targets in `ignored` state (no `target_ids` specified) | Accepted; `replayed_to` and `attempt_ids` contain all previously-ignored targets; each receives an attempt regardless of the filter that caused the original `ignored` outcome |
| Replay with explicit `target_ids` where every specified target is `ignored` | Same as above but limited to the specified subset |
| Budget counter file unreadable or corrupted on startup | Confusio treats counters as zero (fully refilled); the most conservative possible restart gives targets a clean window after a crash |
| Outbox directory not writable at ingest | Confusio rejects the inbound event with `500 Internal Server Error`; no partial write occurs |
| `github_payload` or `confusio_payload` too large to store | Payloads larger than 25 MiB are truncated at 25 MiB with a `"_truncated": true` sentinel field added at the top level |

## Multi-Target Dispatch and Configuration

Confusio delivers each inbound event to every matching **target** — an HTTP endpoint
registered by an operator.  Targets are independent: each has its own event-type filter,
shape preference, optional signing secret, and lifecycle state.

### Target resource

A target is a persistent object with the following fields:

```json
{
  "target_id":  "<uuid>",
  "url":        "https://example.com/webhook",
  "status":     "active",
  "events":     ["issues", "pull_request", "push"],
  "shape":      "github",
  "created_at": "<iso8601>",
  "updated_at": "<iso8601>"
}
```

| Field | Description |
|-------|-------------|
| `target_id` | UUID v4 assigned at creation; immutable |
| `url` | Delivery endpoint; must be an `https://` or `http://` absolute URL |
| `status` | Lifecycle state — see [Target lifecycle](#target-lifecycle) |
| `events` | Event-type filter — see [Event-type filter](#event-type-filter) |
| `shape` | Output shape: `"github"` or `"confusio"` — see [Shape selection](#shape-selection) |
| `created_at` | ISO 8601 UTC timestamp when the target was registered |
| `updated_at` | ISO 8601 UTC timestamp of the last modification |

The `secret` field (see [Outbound signatures](#outbound-signatures)) is **write-only** —
it is accepted on create and update but never returned in any response.

### Target lifecycle

Each target has a `status` field that controls its participation in fan-out and retry
dispatch.

| Status | Description |
|--------|-------------|
| `active` | Normal operation; receives new events and retries |
| `paused` | Excluded from fan-out for new events; existing scheduled retries are suspended (see below) |
| `deleted` | Soft-deleted; excluded from all fan-out; no new delivery records are created; existing records retained until retention window |

**Paused targets:** When a target is paused, confusio stops dispatching to it.  Events
ingested while the target is paused are not queued; they will not be delivered unless
explicitly replayed via the replay API after the target is resumed.  Deliveries that are
`in_flight` when the pause occurs may complete; if they fail, no retry is scheduled until
the target is resumed.  Deliveries that are `retrying` have their `next_attempt` cleared
and will resume their retry schedule when the target is resumed.  Circuit breaker and
retry budget state are preserved across pause/resume cycles.

**Deleted targets:** Deletion is soft.  The target record is marked `deleted` and
excluded from all fan-out and retry dispatch.  Existing delivery state records in the
outbox are retained until the 72-hour retention window expires; the replay API returns
their history but refuses new replay attempts for a deleted target.  The `target_id` is
never reused.

**Resuming a paused target:** Setting `status` back to `"active"` (via a PATCH request)
re-enables fan-out for new events.  Deliveries that were `retrying` when the target was
paused resume their retry schedules from where they left off.

### Event-type filter

The `events` field controls which event families are delivered to a target.

| Value | Meaning |
|-------|---------|
| `["*"]` | All event families (wildcard; this is the default) |
| `["issues", "pull_request"]` | Only the named event families |

Event family names match the GitHub event family identifiers used in `X-GitHub-Event`
(e.g., `"issues"`, `"push"`, `"pull_request"`, `"release"`).  The full list of supported
families is the set of event families specified in
[GitHub-Emulation Contract](#github-emulation-contract).

If an inbound event's family is **not** in the target's filter, confusio creates a
delivery state record with `status: "ignored"` for that target — no HTTP attempt is made.
The event remains replayable via the replay API for the 72-hour retention window, allowing
operators to recover events that arrived before a filter was corrected.

**Filter matching is case-sensitive and exact.**  Wildcards (`"*"`) must appear as the
sole element of the array; a mixed list like `["*", "push"]` is rejected with
`400 Bad Request`.

### Shape selection

The `shape` field selects which output format is sent to the target's `url`.

| Value | Description |
|-------|-------------|
| `"github"` | GitHub-emulation shape — headers and body byte-compatible with GitHub webhook format (default) |
| `"confusio"` | Confusio-normalized shape — confusio envelope and namespace; see [Normalized Confusio Event Model](#normalized-confusio-event-model) |

Shape is configured per target and applies to all events delivered to that target.
Changing the shape of an existing target (via PATCH) takes effect for all subsequent
delivery attempts, including retries of previously queued events.

**Shape and retry consistency:** If a target's shape is changed while a delivery is
`retrying`, the next retry attempt uses the new shape.  Both `github_payload` and
`confusio_payload` are stored in the outbox at ingest time, so the shape selection at
dispatch time determines which variant is sent — no retranslation is required.

### Outbound signatures

When a `secret` is configured on a target, confusio signs outbound delivery payloads
using **HMAC-SHA256**.  The signature is sent in the `X-Hub-Signature-256` header,
mirroring GitHub's outbound webhook signing scheme so consumers can verify payloads using
standard GitHub webhook libraries.

**Header format:**

```
X-Hub-Signature-256: sha256=<lowercase hex digest>
```

The HMAC is computed over the raw serialized request body (the JSON bytes as sent, before
any content encoding).  The secret is the HMAC key.

**Secret management:**

- The secret is accepted as a plain UTF-8 string in the `secret` field on create or
  update.
- The secret is stored at rest (implementation detail; key management is out of scope for
  this spec).
- The secret is **never returned** in any GET or list response.  The response object omits
  the field entirely — there is no placeholder or masked representation.
- To rotate a secret, PATCH the target with the new `secret` value.  The new secret takes
  effect on the next delivery attempt.
- To remove signing entirely, PATCH with `"secret": null`.

**Targets without a secret** receive no `X-Hub-Signature-256` header.

### Fan-out dispatch logic

When confusio successfully ingests and verifies an inbound event, it performs a
synchronous fan-out pass before returning the HTTP response to the forge.

**Fan-out steps:**

1. Load all targets with `status == "active"`.
2. For each active target:
   - Check if the event family matches the target's `events` filter.
   - **Match:** write `targets/{target_id}/{delivery_id}.json` with `status: "pending"`
     and enqueue for asynchronous delivery.
   - **No match:** write the state record with `status: "ignored"`.
3. Return `200 OK` (or `202 Accepted`) to the forge.  Delivery is asynchronous from this
   point.

**Paused and deleted targets** are skipped entirely during fan-out — no delivery state
record is created for them.  Events arriving during a pause period will not be delivered
to that target unless explicitly replayed after resumption.

**Fan-out atomicity:** All delivery state records for a single event are written before
the inbound response is returned.  If any write fails, confusio returns
`500 Internal Server Error` to the forge and does not create a partial set of records.
The forge will typically retry the inbound request; confusio re-processes it as a new
event with a new `delivery_id`.

**Fan-out ordering:** Each target's delivery proceeds independently.  No cross-target
ordering guarantee exists; delivery progress for one target has no effect on another.

---

### Admin API

All target management endpoints require **admin credentials** and are grouped under the
`/webhooks/targets` base path.  Unauthenticated requests receive `401 Unauthorized`.

#### Error response format

All admin API endpoints use the same error body format as the replay API:

```json
{
  "error":   "<machine-readable code>",
  "message": "<human-readable description>"
}
```

| HTTP status | `error` code | When |
|-------------|-------------|------|
| `400 Bad Request` | `"invalid_request"` | Request body is not valid JSON, a required field is missing, or a field has an invalid value |
| `400 Bad Request` | `"invalid_filter"` | `events` array contains unrecognized family names, or mixes `"*"` with named families |
| `400 Bad Request` | `"invalid_url"` | `url` is not a valid absolute HTTP(S) URL |
| `400 Bad Request` | `"invalid_status"` | `status` value is not a permitted transition for PATCH |
| `401 Unauthorized` | `"unauthorized"` | Missing or invalid admin credentials |
| `404 Not Found` | `"target_not_found"` | Target UUID does not exist or has been deleted |
| `409 Conflict` | `"target_deleted"` | Operation not permitted on a deleted target (e.g., replay attempt via replay API) |
| `429 Too Many Requests` | `"rate_limited"` | Admin API rate limit exceeded; `Retry-After` header is set |

#### Create a target

```
POST /webhooks/targets
```

**Request body:**

```json
{
  "url":    "https://example.com/webhook",
  "events": ["*"],
  "shape":  "github",
  "secret": "s3cr3t"
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `url` | Yes | Absolute `http://` or `https://` delivery endpoint URL |
| `events` | No | Event filter array; defaults to `["*"]` |
| `shape` | No | `"github"` or `"confusio"`; defaults to `"github"` |
| `secret` | No | HMAC signing secret; omit for unsigned delivery |

**Response** (`201 Created`):

```json
{
  "target_id":  "a2fb4a9c-1234-5678-abcd-000000000001",
  "url":        "https://example.com/webhook",
  "status":     "active",
  "events":     ["*"],
  "shape":      "github",
  "created_at": "2026-04-19T00:00:00Z",
  "updated_at": "2026-04-19T00:00:00Z"
}
```

`secret` is not present in the response.

**Error responses:**

| Code | `error` code | When |
|------|-------------|------|
| `400 Bad Request` | `"invalid_request"` | Missing `url` or invalid field value |
| `400 Bad Request` | `"invalid_filter"` | Malformed `events` array |
| `400 Bad Request` | `"invalid_url"` | `url` is not a valid absolute HTTP(S) URL |
| `401 Unauthorized` | `"unauthorized"` | Missing or invalid admin credentials |

#### List targets

```
GET /webhooks/targets
```

Returns all non-deleted targets in creation order.  Supports cursor-based pagination.

**Query parameters:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `per_page` | `30` | Items per page; max `100` |
| `cursor` | _(start)_ | Opaque pagination cursor from a previous response's `next_cursor` |
| `status` | _(all non-deleted)_ | Filter by status: `active` or `paused` |

**Response** (`200 OK`):

```json
{
  "targets": [
    {
      "target_id":  "<uuid>",
      "url":        "https://example.com/webhook",
      "status":     "active",
      "events":     ["*"],
      "shape":      "github",
      "created_at": "<iso8601>",
      "updated_at": "<iso8601>"
    }
  ],
  "next_cursor": null
}
```

Deleted targets are excluded from all list results.  Pagination cursors are stable across
additions and deletions.

**Error responses:**

| Code | `error` code | When |
|------|-------------|------|
| `401 Unauthorized` | `"unauthorized"` | Missing or invalid admin credentials |

#### Get a target

```
GET /webhooks/targets/{target_id}
```

Returns the full target record.  Returns `404` for deleted targets.

**Response** (`200 OK`): target object (same shape as each item in the list response).

**Error responses:**

| Code | `error` code | When |
|------|-------------|------|
| `401 Unauthorized` | `"unauthorized"` | Missing or invalid admin credentials |
| `404 Not Found` | `"target_not_found"` | Target UUID unknown or deleted |

#### Update a target

```
PATCH /webhooks/targets/{target_id}
```

Partial update — only fields included in the request body are modified.

**Request body** (all fields optional):

```json
{
  "url":    "https://new.example.com/webhook",
  "events": ["push", "issues"],
  "shape":  "confusio",
  "status": "paused",
  "secret": "new-secret"
}
```

| Field | Description |
|-------|-------------|
| `url` | New delivery endpoint URL |
| `events` | Replacement event filter (full replacement, not merge) |
| `shape` | New shape; takes effect on the next delivery attempt |
| `status` | Lifecycle transition: `"active"` or `"paused"`; `"deleted"` is not a valid PATCH value — use DELETE |
| `secret` | New HMAC signing secret; `null` removes signing |

**Response** (`200 OK`): updated target object (same shape as GET response).

**Error responses:**

| Code | `error` code | When |
|------|-------------|------|
| `400 Bad Request` | `"invalid_request"` | Invalid field value |
| `400 Bad Request` | `"invalid_filter"` | Malformed `events` array |
| `400 Bad Request` | `"invalid_url"` | Malformed `url` |
| `400 Bad Request` | `"invalid_status"` | `status` is not `"active"` or `"paused"` |
| `401 Unauthorized` | `"unauthorized"` | Missing or invalid admin credentials |
| `404 Not Found` | `"target_not_found"` | Target UUID unknown or deleted |

#### Delete a target

```
DELETE /webhooks/targets/{target_id}
```

Soft-deletes the target.  The target is immediately excluded from fan-out and retry
dispatch.  Existing delivery state records in the outbox are retained until the 72-hour
retention window expires and are still visible via the replay API delivery history
endpoints.  Replay is refused for deleted targets.

**Response** (`204 No Content`): empty body.

**Error responses:**

| Code | `error` code | When |
|------|-------------|------|
| `401 Unauthorized` | `"unauthorized"` | Missing or invalid admin credentials |
| `404 Not Found` | `"target_not_found"` | Target UUID unknown or already deleted |

---

### Edge cases

| Scenario | Behaviour |
|----------|-----------|
| Target paused while a delivery is `in_flight` | In-flight attempt may complete; if it fails, no retry is scheduled; delivery remains `retrying` (paused) until the target is resumed |
| Target paused while a delivery is `retrying` | `next_attempt` is cleared; retry is held until the target is resumed, then scheduled from where it left off |
| Target deleted while a delivery is `retrying` | Delivery transitions to `failed`; no further attempts; outbox record retained until retention window |
| Target URL updated while retries are pending | Next retry uses the new URL; previous attempt records retain the URL that was used at attempt time (implementation detail; URL is not stored per-attempt in this spec) |
| Shape changed while deliveries are retrying | Next retry uses the new shape variant from the outbox; consumers may observe a shape change mid-stream |
| Secret removed while retries are pending | Next retry is sent unsigned; `X-Hub-Signature-256` header is omitted |
| No active targets at ingest time | Fan-out writes zero records; the event is still written to the outbox; operators can register targets and replay within the 72-hour window |
| Target registered while a matching event is mid-retry | Late-registered target receives no delivery for that event; replay is required |
| `events: ["*"]` with a new event family added in a future confusio version | Wildcard filter automatically includes the new family; named-event-list filters do not |
| Replay attempted against a deleted target | `POST /webhooks/deliveries/{delivery_id}/redeliver` with a deleted `target_id` in `target_ids` returns `409 Conflict` with `"target_deleted"` |
| PATCH sets `status: "active"` on an already-active target | No-op; returns `200 OK` with the unchanged record |
| PATCH sets `status: "paused"` on an already-paused target | No-op; returns `200 OK` with the unchanged record |
