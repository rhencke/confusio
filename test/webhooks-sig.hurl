# Webhook signature verification — integration tests with real HMAC.
#
# Run by Phase 4 in test-unit.sh with webhook_secret_file_BACKEND CLI args configured.
# Variables injected by the test script (computed via openssl at runtime):
#   gitea_sig   — HMAC-SHA256("{}", secret) as hex (for X-Gitea-Signature)
#   gitlab_tok  — the shared secret verbatim (for X-Gitlab-Token)
#   bb_sig      — "sha256=<hex>" (for X-Hub-Signature on bitbucket and bitbucket_datacenter)
#   gb_sig      — "sha1=<hex>" (for X-Hub-Signature on gitbucket)
#   launchpad_sig — "sha1=<hex>" (for X-Hub-Signature on launchpad)
#   sourceforge_sig — "sha1=<hex>" (for X-Allura-Signature on sourceforge)
#   phabricator_sig — HMAC-SHA256("{}", secret) as hex (for X-Phabricator-Webhook-Signature)
#   azuredevops_basic — base64("fido:webhooksecret") for Authorization: Basic
#   gerrit_tok  — the shared secret verbatim or as Bearer token (for Authorization)
#   gerrit_basic — base64("webhooksecret") for Authorization: Basic
#   onedev_tok — the shared secret verbatim (for X-OneDev-Signature)
#   radicle_tok — the shared secret verbatim (for Authorization)
#   kallithea — shared secret is embedded in the request body
#   sourcehut_sig — Ed25519("{}") as base64 (for X-Payload-Signature)
#   tuleap_tok — the shared secret verbatim (for X-Tuleap-Webhook-Secret)
#   confusio_sig — "sha256=<hex>, v=1, ts=<ts>" (for X-Confusio-Signature-256)
#
# Convention: valid credential → 422 (verification passed; no handlers registered
#             means the request was accepted); invalid → 401.

# ── gitea: X-Gitea-Signature, HMAC-SHA256, no prefix ─────────────────────────

# Valid signature → passes verification (422 = accepted, no handlers)
POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Signature: {{gitea_sig}}
{}

HTTP 422
[Asserts]
jsonpath "$.message" == "No webhook handlers registered"

# Bad signature → 401 signature verification failed
POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Signature: deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# Missing signature header → 401
POST http://{{host}}/webhooks/gitea
Content-Type: application/json
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# sha256= prefix is not accepted by Gitea's native header format
POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Signature: sha256={{gitea_sig}}
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# ── forgejo: X-Gitea-Signature, HMAC-SHA256, no prefix ──────────────────────

# Valid signature → passes verification (422 = accepted, no handlers)
POST http://{{host}}/webhooks/forgejo
Content-Type: application/json
X-Gitea-Signature: {{gitea_sig}}
{}

HTTP 422
[Asserts]
jsonpath "$.message" == "No webhook handlers registered"

# Bad signature → 401 signature verification failed
POST http://{{host}}/webhooks/forgejo
Content-Type: application/json
X-Gitea-Signature: deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# Missing signature header → 401
POST http://{{host}}/webhooks/forgejo
Content-Type: application/json
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# ── codeberg: X-Gitea-Signature, HMAC-SHA256, no prefix ──────────────────────

# Valid signature → passes verification (422 = accepted, no handlers)
POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Signature: {{gitea_sig}}
{}

HTTP 422
[Asserts]
jsonpath "$.message" == "No webhook handlers registered"

# Bad signature → 401 signature verification failed
POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
X-Gitea-Signature: deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# Missing signature header → 401
POST http://{{host}}/webhooks/codeberg
Content-Type: application/json
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# ── gitlab: X-Gitlab-Token, verbatim shared token ────────────────────────────

# Valid token → passes verification (422)
POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Token: {{gitlab_tok}}
{}

HTTP 422
[Asserts]
jsonpath "$.message" == "No webhook handlers registered"

# Bad token → 401
POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Token: wrongtoken
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# Missing token header → 401
POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# ── bitbucket: X-Hub-Signature, HMAC-SHA256, sha256= prefix ──────────────────

# Valid signature → passes verification (422)
POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Hub-Signature: {{bb_sig}}
{}

HTTP 422
[Asserts]
jsonpath "$.message" == "No webhook handlers registered"

# Bad signature → 401
POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Hub-Signature: sha256=deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# ── bitbucket_datacenter: X-Hub-Signature, HMAC-SHA256, sha256= prefix ───────

# Valid signature → passes verification (422)
POST http://{{host}}/webhooks/bitbucket_datacenter
Content-Type: application/json
X-Hub-Signature: {{bb_sig}}
{}

HTTP 422
[Asserts]
jsonpath "$.message" == "No webhook handlers registered"

# Bad signature → 401
POST http://{{host}}/webhooks/bitbucket_datacenter
Content-Type: application/json
X-Hub-Signature: sha256=deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# Missing signature header → 401
POST http://{{host}}/webhooks/bitbucket_datacenter
Content-Type: application/json
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# ── gitbucket: X-Hub-Signature, HMAC-SHA1, sha1= prefix ──────────────────────

# Valid signature → passes verification (422)
POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-Hub-Signature: {{gb_sig}}
{}

HTTP 422
[Asserts]
jsonpath "$.message" == "No webhook handlers registered"

# Bad signature → 401
POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-Hub-Signature: sha1=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# ── launchpad: X-Hub-Signature, HMAC-SHA1, sha1= prefix ─────────────────────

# Valid signature → passes verification (422)
POST http://{{host}}/webhooks/launchpad
Content-Type: application/json
X-Hub-Signature: {{launchpad_sig}}
{}

HTTP 422
[Asserts]
jsonpath "$.message" == "No webhook handlers registered"

# Bad signature → 401
POST http://{{host}}/webhooks/launchpad
Content-Type: application/json
X-Hub-Signature: sha1=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# Missing signature header → 401
POST http://{{host}}/webhooks/launchpad
Content-Type: application/json
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# ── phabricator: X-Phabricator-Webhook-Signature, HMAC-SHA256, no prefix ────

# Valid signature → passes verification (422)
POST http://{{host}}/webhooks/phabricator
Content-Type: application/json
X-Phabricator-Webhook-Signature: {{phabricator_sig}}
{}

HTTP 422
[Asserts]
jsonpath "$.message" == "No webhook handlers registered"

# Bad signature → 401
POST http://{{host}}/webhooks/phabricator
Content-Type: application/json
X-Phabricator-Webhook-Signature: deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# Missing signature header → 401
POST http://{{host}}/webhooks/phabricator
Content-Type: application/json
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# ── pagure: X-Pagure-Signature-256 SHA-256, X-Pagure-Signature SHA-512 ───────

# Valid SHA-256 signature → passes verification (422)
POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Signature-256: {{pagure_sig_256}}
{}

HTTP 422
[Asserts]
jsonpath "$.message" == "No webhook handlers registered"

# Valid SHA-512 signature → passes verification (422)
POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Signature: {{pagure_sig_512}}
{}

HTTP 422
[Asserts]
jsonpath "$.message" == "No webhook handlers registered"

# Both valid signatures → passes verification (422)
POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Signature-256: {{pagure_sig_256}}
X-Pagure-Signature: {{pagure_sig_512}}
{}

HTTP 422
[Asserts]
jsonpath "$.message" == "No webhook handlers registered"

# Bad SHA-256 signature → 401
POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Signature-256: deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# Bad SHA-512 signature paired with valid SHA-256 → 401
POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Signature-256: {{pagure_sig_256}}
X-Pagure-Signature: deadbeef
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# Missing signature header → 401
POST http://{{host}}/webhooks/pagure
Content-Type: application/json
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# ── azuredevops: Authorization: Basic base64(username:password) ──────────────

# Valid Basic credentials → passes verification (422)
POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
Authorization: Basic {{azuredevops_basic}}
{}

HTTP 422
[Asserts]
jsonpath "$.message" == "No webhook handlers registered"

# Bad Basic credentials → 401
POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
Authorization: Basic YmFkOmNyZWRz
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# Missing Authorization header → 401
POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# ── gerrit: Authorization raw, Bearer, or Basic shared secret ────────────────

# Valid raw Authorization token → passes verification (422)
POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
Authorization: {{gerrit_tok}}
{}

HTTP 422
[Asserts]
jsonpath "$.message" == "No webhook handlers registered"

# Valid Bearer token → passes verification (422)
POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
Authorization: Bearer {{gerrit_tok}}
{}

HTTP 422
[Asserts]
jsonpath "$.message" == "No webhook handlers registered"

# Valid Basic credentials → passes verification (422)
POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
Authorization: Basic {{gerrit_basic}}
{}

HTTP 422
[Asserts]
jsonpath "$.message" == "No webhook handlers registered"

# Bad Authorization token → 401
POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
Authorization: Bearer wrongtoken
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# Missing Authorization header → 401
POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# ── onedev: X-OneDev-Signature, verbatim shared token ────────────────────────

# Valid token → passes verification (422)
POST http://{{host}}/webhooks/onedev
Content-Type: application/json
X-OneDev-Signature: {{onedev_tok}}
{}

HTTP 422
[Asserts]
jsonpath "$.message" == "No webhook handlers registered"

# Bad token → 401
POST http://{{host}}/webhooks/onedev
Content-Type: application/json
X-OneDev-Signature: wrongtoken
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# Bearer Authorization is not OneDev's native webhook signature → 401
POST http://{{host}}/webhooks/onedev
Content-Type: application/json
Authorization: Bearer {{onedev_tok}}
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# Missing signature header → 401
POST http://{{host}}/webhooks/onedev
Content-Type: application/json
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# ── radicle: Authorization raw shared secret, event_type in body ─────────────

# Valid raw Authorization token and event_type → passes verification and extracts event
POST http://{{host}}/webhooks/radicle
Content-Type: application/json
Authorization: {{radicle_tok}}
{
  "request": "trigger",
  "version": 1,
  "event_type": "push"
}

HTTP 422
[Asserts]
jsonpath "$.message" == "Unrecognised event type: push"

# Bad Authorization token → 401
POST http://{{host}}/webhooks/radicle
Content-Type: application/json
Authorization: wrongtoken
{
  "request": "trigger",
  "version": 1,
  "event_type": "push"
}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# Bearer Authorization is not Radicle's native webhook signature → 401
POST http://{{host}}/webhooks/radicle
Content-Type: application/json
Authorization: Bearer {{radicle_tok}}
{
  "request": "trigger",
  "version": 1,
  "event_type": "push"
}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# Missing Authorization header → 401
POST http://{{host}}/webhooks/radicle
Content-Type: application/json
{
  "request": "trigger",
  "version": 1,
  "event_type": "push"
}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# ── kallithea: body-embedded shared secret ───────────────────────────────────

# Valid root secret → passes verification (422)
POST http://{{host}}/webhooks/kallithea
Content-Type: application/json
{
  "secret": "webhooksecret"
}

HTTP 422
[Asserts]
jsonpath "$.message" == "No webhook handlers registered"

# Valid nested webhook token → passes verification (422)
POST http://{{host}}/webhooks/kallithea
Content-Type: application/json
{
  "payload": {
    "webhook_token": "webhooksecret"
  }
}

HTTP 422
[Asserts]
jsonpath "$.message" == "No webhook handlers registered"

# Bad body secret → 401
POST http://{{host}}/webhooks/kallithea
Content-Type: application/json
{
  "secret": "wrongtoken"
}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# Missing body secret → 401
POST http://{{host}}/webhooks/kallithea
Content-Type: application/json
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# ── sourceforge: X-Allura-Signature, HMAC-SHA1, sha1= prefix ────────────────

# Valid signature → passes verification (422)
POST http://{{host}}/webhooks/sourceforge
Content-Type: application/json
X-Allura-Signature: {{sourceforge_sig}}
{}

HTTP 422
[Asserts]
jsonpath "$.message" == "No webhook handlers registered"

# Bad signature → 401
POST http://{{host}}/webhooks/sourceforge
Content-Type: application/json
X-Allura-Signature: sha1=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# Legacy shared-secret header is not Allura's native webhook signature → 401
POST http://{{host}}/webhooks/sourceforge
Content-Type: application/json
X-Sourceforge-Webhook-Secret: webhooksecret
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# Missing signature header → 401
POST http://{{host}}/webhooks/sourceforge
Content-Type: application/json
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# ── rhodecode: X-RhodeCode-Signature, verbatim shared token ─────────────────

# Valid token → passes verification (422)
POST http://{{host}}/webhooks/rhodecode
Content-Type: application/json
X-RhodeCode-Signature: {{rhodecode_tok}}
{}

HTTP 422
[Asserts]
jsonpath "$.message" == "No webhook handlers registered"

# Bad token → 401
POST http://{{host}}/webhooks/rhodecode
Content-Type: application/json
X-RhodeCode-Signature: wrongtoken
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# Missing token header → 401
POST http://{{host}}/webhooks/rhodecode
Content-Type: application/json
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# ── tuleap: X-Tuleap-Webhook-Secret, verbatim shared token ──────────────────

# Valid token → passes verification (422)
POST http://{{host}}/webhooks/tuleap
Content-Type: application/x-www-form-urlencoded
X-Tuleap-Webhook-Secret: {{tuleap_tok}}
`payload=%7B%7D`

HTTP 422
[Asserts]
jsonpath "$.message" == "No webhook handlers registered"

# Bad token → 401
POST http://{{host}}/webhooks/tuleap
Content-Type: application/x-www-form-urlencoded
X-Tuleap-Webhook-Secret: wrongtoken
`payload=%7B%7D`

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# Missing token header → 401
POST http://{{host}}/webhooks/tuleap
Content-Type: application/x-www-form-urlencoded
`payload=%7B%7D`

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# ── codecommit: configured verification requires valid signed SNS bodies ────

# Unsigned or malformed SNS bodies reject when CodeCommit verification is enabled.
POST http://{{host}}/webhooks/codecommit
Content-Type: application/json
X-Amz-Sns-Message-Type: Notification
X-Amz-Sns-Signature: placeholder
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# ── sourcehut: X-Payload-Signature, Ed25519 detached signature ───────────────

# Valid signature → passes verification (422)
POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
X-Payload-Signature: {{sourcehut_sig}}
{}

HTTP 422
[Asserts]
jsonpath "$.message" == "No webhook handlers registered"

# Bad signature → 401
POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
X-Payload-Signature: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# Missing signature header → 401
POST http://{{host}}/webhooks/sourcehut
Content-Type: application/json
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"

# ── confusio: X-Confusio-Signature-256, HMAC-SHA256 with timestamp ───────────
# HMAC basestring is "v1:<ts>:<body>"; ts embedded in header as ts=<unix>.

# Valid signature with fresh timestamp → passes verification (422)
POST http://{{host}}/webhooks/confusio
Content-Type: application/json
X-Confusio-Signature-256: {{confusio_sig}}
{}

HTTP 422
[Asserts]
jsonpath "$.message" == "No webhook handlers registered"

# Stale past timestamp (year 2001) → 401 replay rejected
POST http://{{host}}/webhooks/confusio
Content-Type: application/json
X-Confusio-Signature-256: sha256=edc699fb5ca33c226f8ececeb563e81267b9199db0a45999e7960eb9f53add98, v=1, ts=980000000
{}

HTTP 401
[Asserts]
jsonpath "$.message" == "Signature verification failed"
