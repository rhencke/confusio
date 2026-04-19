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

| GitHub field | gitea-family | gogs | gitlab | bitbucket | bitbucket-dc | github | gitbucket | azuredevops | All others |
|---|---|---|---|---|---|---|---|---|---|
| `id` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `number` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `title` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `body` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `state` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `html_url` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `user` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `head.ref` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `head.sha` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `head.repo` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `base.ref` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `base.sha` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `base.repo` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `merged` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `merged_at` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `merge_commit_sha` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✗ |
| `merged_by` | ✓ | ✗ | ✓ | ✗ | ✗ | ✓ | ✗ | ~ | ✗ |
| `draft` | ✓ | ✗ | ✓ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ |
| `labels` | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ |
| `assignees` | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✗ | ✗ |
| `requested_reviewers` | ✓ | ✗ | ✓ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ |
| `created_at` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `updated_at` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |
| `closed_at` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ~ |

#### Supported actions by backend

| Action | gitea-family | gogs | gitlab | bitbucket | bitbucket-dc | github | gitbucket | azuredevops |
|--------|---|---|---|---|---|---|---|---|
| `opened` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `closed` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `reopened` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `synchronize` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `edited` | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ | ✓ |
| `labeled` | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✗ |
| `unlabeled` | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✗ |
| `assigned` | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✗ |
| `unassigned` | ✓ | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ✗ |
| `review_requested` | ✓ | ✗ | ✓ | ✗ | ✓ | ✓ | ✗ | ✗ |
| `review_request_removed` | ✓ | ✗ | ✓ | ✗ | ✓ | ✓ | ✗ | ✗ |

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
- Pagure uses "pull request" but its webhook payload differs significantly; confusio
  supports basic open/close/merge actions only.

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
| `comment.diff_hunk` | ✓ | ✓ | ✓ | ✗ |
| `comment.commit_id` | ✓ | ✓ | ✓ | ✗ |
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
- Most forges do not expose diff-level review comments in webhooks.  Backends not
  listed always emit `✗` for this event.

---

### `commit_comment`

Triggered when a comment is created directly on a commit (not a PR or review).

| GitHub field | gitea-family | gitlab | github | gitbucket | All others |
|---|---|---|---|---|---|
| `comment.id` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `comment.body` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `comment.commit_id` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `comment.path` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `comment.position` | ~ | ~ | ✓ | ✓ | ✗ |
| `comment.line` | ~ | ~ | ✓ | ✓ | ✗ |
| `comment.user` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `comment.html_url` | ✓ | ✓ | ✓ | ✓ | ✗ |
| `comment.created_at` | ✓ | ✓ | ✓ | ✓ | ✗ |

**Notes:**
- `position` and `line`: Gitea and GitLab use line-number references; confusio maps
  these to `position` and `line` with a note that the encoding differs from GitHub's.
- Backends not listed (Bitbucket, Azure DevOps, etc.) do not emit commit comment events.

## Delivery Semantics

_(Durable outbox design, retry backoff, replay API, and at-least-once guarantees are
specified in a subsequent section of this document.)_

## Multi-Target Dispatch and Configuration

_(Per-target filters, shape selection, and the admin registration surface are specified
in a subsequent section of this document.)_
