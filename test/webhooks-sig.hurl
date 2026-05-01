# Webhook signature verification — integration tests with real HMAC.
#
# Run by Phase 4 in test-unit.sh with webhook_secret_file_BACKEND CLI args configured.
# Variables injected by the test script (computed via openssl at runtime):
#   gitea_sig   — HMAC-SHA256("{}", secret) as hex (for X-Gitea-Signature)
#   gitlab_tok  — the shared secret verbatim (for X-Gitlab-Token)
#   bb_sig      — "sha256=<hex>" (for X-Hub-Signature on bitbucket and bitbucket_datacenter)
#   gb_sig      — "sha1=<hex>" (for X-Hub-Signature on gitbucket)
#   azuredevops_basic — base64("fido:webhooksecret") for Authorization: Basic
#   gerrit_tok  — the shared secret verbatim or as Bearer token (for Authorization)
#   gerrit_basic — base64("webhooksecret") for Authorization: Basic
#   kallithea — shared secret is embedded in the request body
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
