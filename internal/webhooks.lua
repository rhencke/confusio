-- Webhook receive pipeline: handles POST /webhooks/{backend}.
--
-- Processing stages:
--   1. Route    — extract backend name from path; 404 for unknown backend
--   2. Method   — POST only; 405 for other methods
--   3. Format   — Content-Type must be application/json; 400 otherwise
--   4. Verify   — backend-specific signature checked against raw body; 401 on failure
--   5. Dispatch — decoded payload passed to app.backend.webhooks[event]; 422 for unknown
--   6. Respond  — 200 on success
--
-- Auth bypass: /webhooks/* paths skip the auth gate in make_dispatcher entirely.
-- Forge webhook deliveries carry their own authentication (signature headers or
-- tokens); requiring an Authorization header would break every real forge integration.
--
-- Signature verification is performed before any JSON decoding.  The raw request
-- body bytes are buffered by GetBody() for HMAC computation, then decoded separately.
--
-- make_webhook_receiver(a) — factory; returns the closure installed as
--   a.webhook_receiver by .init.lua after dispatching load.
--
-- Globals exported:
--   make_webhook_receiver   — builder factory; called once at startup

-- KNOWN_BACKENDS maps path segment to true for all recognised inbound sources.
-- Requests with an unrecognised segment return 404.
-- Includes the 24 forge backends plus "confusio" for cross-instance forwarding.
local KNOWN_BACKENDS = {
  azuredevops = true,
  bitbucket = true,
  bitbucket_datacenter = true,
  codeberg = true,
  codecommit = true,
  confusio = true,
  forgejo = true,
  gerrit = true,
  gitblit = true,
  gitbucket = true,
  gitea = true,
  gitlab = true,
  gogs = true,
  harness = true,
  kallithea = true,
  launchpad = true,
  notabug = true,
  onedev = true,
  pagure = true,
  phabricator = true,
  radicle = true,
  rhodecode = true,
  sourceforge = true,
  sourcehut = true,
  tuleap = true,
}

-- REPLAY_WINDOW_SECS is the maximum age (and future skew) allowed for a
-- confusio-normalized inbound delivery timestamp.  Requests with a timestamp
-- outside this window are rejected to prevent replay attacks.
local REPLAY_WINDOW_SECS = 300

-- to_hex(bytes) converts raw binary bytes to a lowercase hex string.
local function to_hex(bytes)
  local hex = {}
  for i = 1, #bytes do
    hex[i] = string.format("%02x", bytes:byte(i))
  end
  return table.concat(hex)
end

-- ct_equal(a, b) is a constant-time string equality check.
-- Prevents timing oracle attacks on secret and digest comparisons.
-- Returns false immediately when lengths differ (length is not a secret).
local function ct_equal(a, b)
  if type(a) ~= "string" or type(b) ~= "string" then
    return false
  end
  if #a ~= #b then
    return false
  end
  local r = 0
  for i = 1, #a do
    r = r | (a:byte(i) ~ b:byte(i))
  end
  return r == 0
end

-- hmac_hex(alg, secret, body) computes HMAC and returns lowercase hex.
-- alg: "sha1" | "sha256" | "sha512"  (passed to GetCryptoHash)
-- GetCryptoHash(alg, msg, key) computes HMAC when the third argument is present.
local function hmac_hex(alg, secret, body)
  return to_hex(GetCryptoHash(alg, body, secret)) -- luacheck: globals GetCryptoHash
end

-- verify_signature(backend, secret, body[, now]) authenticates the inbound request
-- using the backend-native scheme.  Returns true on success, false on failure.
-- When secret is nil or "" (trust-the-network mode) all requests are accepted.
-- Rejection occurs before any JSON parsing; unverified payloads are not decoded.
-- now: current Unix epoch seconds; defaults to os.time().  Exposed for testing.
local function verify_signature(backend, secret, body, now)
  now = now or os.time()
  -- Gitea family: X-Gitea-Signature, HMAC-SHA256, no prefix
  -- notabug uses the same Gitea-derived scheme.
  if
    backend == "gitea"
    or backend == "forgejo"
    or backend == "codeberg"
    or backend == "notabug"
  then
    if not secret or secret == "" then
      return true
    end
    local sig = GetHeader("X-Gitea-Signature")
    if not sig then
      return false
    end
    return ct_equal(hmac_hex("sha256", secret, body), sig)

  -- Gogs: X-Gogs-Signature, HMAC-SHA256, no prefix
  elseif backend == "gogs" then
    if not secret or secret == "" then
      return true
    end
    local sig = GetHeader("X-Gogs-Signature")
    if not sig then
      return false
    end
    return ct_equal(hmac_hex("sha256", secret, body), sig)

  -- GitLab: X-Gitlab-Token, verbatim shared token (no body hashing)
  elseif backend == "gitlab" then
    if not secret or secret == "" then
      return true
    end
    local tok = GetHeader("X-Gitlab-Token")
    if not tok then
      return false
    end
    return ct_equal(secret, tok)

  -- GitHub: X-Hub-Signature-256, HMAC-SHA256, prefix "sha256="
  elseif backend == "github" then
    if not secret or secret == "" then
      return true
    end
    local sig = GetHeader("X-Hub-Signature-256")
    if not sig then
      return false
    end
    return ct_equal("sha256=" .. hmac_hex("sha256", secret, body), sig)

  -- Bitbucket Cloud + Bitbucket Datacenter: X-Hub-Signature, HMAC-SHA256, prefix "sha256="
  elseif backend == "bitbucket" or backend == "bitbucket_datacenter" then
    if not secret or secret == "" then
      return true
    end
    local sig = GetHeader("X-Hub-Signature")
    if not sig then
      return false
    end
    return ct_equal("sha256=" .. hmac_hex("sha256", secret, body), sig)

  -- GitBucket: X-Hub-Signature, HMAC-SHA1, prefix "sha1=" (GitHub legacy compat)
  elseif backend == "gitbucket" then
    if not secret or secret == "" then
      return true
    end
    local sig = GetHeader("X-Hub-Signature")
    if not sig then
      return false
    end
    return ct_equal("sha1=" .. hmac_hex("sha1", secret, body), sig)

  -- Phabricator: X-Phabricator-Webhook-Signature, HMAC-SHA256, no prefix
  elseif backend == "phabricator" then
    if not secret or secret == "" then
      return true
    end
    local sig = GetHeader("X-Phabricator-Webhook-Signature")
    if not sig then
      return false
    end
    return ct_equal(hmac_hex("sha256", secret, body), sig)

  -- Pagure: prefers X-Pagure-Signature-256 (HMAC-SHA256); falls back to
  --         X-Pagure-Signature (HMAC-SHA512) on older instances.
  --         When both headers are present, both must verify.
  elseif backend == "pagure" then
    if not secret or secret == "" then
      return true
    end
    local sig256 = GetHeader("X-Pagure-Signature-256")
    local sig512 = GetHeader("X-Pagure-Signature")
    if sig256 then
      if not ct_equal(hmac_hex("sha256", secret, body), sig256) then
        return false
      end
      if sig512 then
        return ct_equal(hmac_hex("sha512", secret, body), sig512)
      end
      return true
    elseif sig512 then
      return ct_equal(hmac_hex("sha512", secret, body), sig512)
    else
      return false
    end

  -- Harness: X-Harness-Token, verbatim shared token
  elseif backend == "harness" then
    if not secret or secret == "" then
      return true
    end
    local tok = GetHeader("X-Harness-Token")
    if not tok then
      return false
    end
    return ct_equal(secret, tok)

  -- OneDev: Authorization: Bearer <secret>
  elseif backend == "onedev" then
    if not secret or secret == "" then
      return true
    end
    local auth = GetHeader("Authorization")
    if not auth then
      return false
    end
    local bearer = auth:match("^[Bb]earer (.+)$")
    if not bearer then
      return false
    end
    return ct_equal(secret, bearer)

  -- Radicle: Authorization header, raw verbatim token (no Bearer/Basic prefix)
  elseif backend == "radicle" then
    if not secret or secret == "" then
      return true
    end
    local auth = GetHeader("Authorization")
    if not auth then
      return false
    end
    return ct_equal(secret, auth)

  -- Gerrit: Authorization header, verbatim shared token or Basic auth
  elseif backend == "gerrit" then
    if not secret or secret == "" then
      return true
    end
    local auth = GetHeader("Authorization")
    if not auth then
      return false
    end
    return ct_equal(secret, auth)

  -- Gitblit: X-Gitblit-Token, verbatim shared token
  elseif backend == "gitblit" then
    if not secret or secret == "" then
      return true
    end
    local tok = GetHeader("X-Gitblit-Token")
    if not tok then
      return false
    end
    return ct_equal(secret, tok)

  -- RhodeCode: X-RhodeCode-Signature, verbatim shared token
  elseif backend == "rhodecode" then
    if not secret or secret == "" then
      return true
    end
    local tok = GetHeader("X-RhodeCode-Signature")
    if not tok then
      return false
    end
    return ct_equal(secret, tok)

  -- SourceForge: X-Sourceforge-Webhook-Secret, verbatim shared token
  elseif backend == "sourceforge" then
    if not secret or secret == "" then
      return true
    end
    local tok = GetHeader("X-Sourceforge-Webhook-Secret")
    if not tok then
      return false
    end
    return ct_equal(secret, tok)

  -- Tuleap: X-Tuleap-Webhook-Secret, verbatim shared token
  elseif backend == "tuleap" then
    if not secret or secret == "" then
      return true
    end
    local tok = GetHeader("X-Tuleap-Webhook-Secret")
    if not tok then
      return false
    end
    return ct_equal(secret, tok)

  -- Azure DevOps: Authorization: Basic base64(username:password)
  -- secret = configured "username:password" string
  elseif backend == "azuredevops" then
    if not secret or secret == "" then
      return true
    end
    local auth = GetHeader("Authorization")
    if not auth then
      return false
    end
    local b64 = auth:match("^[Bb]asic (.+)$")
    if not b64 then
      return false
    end
    local ok_dec, decoded = pcall(DecodeBase64, b64)
    if not ok_dec then
      return false
    end
    return ct_equal(secret, decoded)

  -- Kallithea: authentication token may be embedded in the JSON body.
  -- Exception to the verify-before-parse rule: the body is decoded only to
  -- extract the token, then re-used for event processing.
  elseif backend == "kallithea" then
    if not secret or secret == "" then
      return true
    end
    local ok_parse, parsed = pcall(DecodeJson, body)
    if not ok_parse or type(parsed) ~= "table" then
      return false
    end
    local tok = parsed.secret or (parsed.data and parsed.data.secret)
    if not tok then
      return false
    end
    return ct_equal(secret, tostring(tok))

  -- Confusio-normalized: X-Confusio-Signature-256, HMAC-SHA256 with timestamp.
  -- Header format: "sha256=<hex>, v=1, ts=<unix>"
  -- HMAC basestring: "v1:<ts>:<body>"
  -- Replay window: REPLAY_WINDOW_SECS (5 minutes).  Timestamps outside the window
  -- are rejected even if the HMAC is correct, preventing capture-and-replay.
  elseif backend == "confusio" then
    if not secret or secret == "" then
      return true
    end
    local sig_hdr = GetHeader("X-Confusio-Signature-256")
    if not sig_hdr then
      return false
    end
    local hex, ts_str = sig_hdr:match("^sha256=([0-9a-f]+), v=1, ts=(%d+)$")
    if not hex or not ts_str then
      return false
    end
    local ts = tonumber(ts_str)
    if not ts then
      return false
    end
    if math.abs(now - ts) > REPLAY_WINDOW_SECS then
      return false
    end
    local basestring = "v1:" .. ts_str .. ":" .. body
    return ct_equal(hmac_hex("sha256", secret, basestring), hex)

  -- CodeCommit (SNS X.509), Sourcehut (ed25519), Launchpad (OpenPGP):
  -- Complex asymmetric and platform-managed schemes not yet implemented.
  -- Trust-the-network when no secret configured; reject otherwise so operators
  -- restrict access via network policy until full verification ships.
  elseif backend == "codecommit" or backend == "sourcehut" or backend == "launchpad" then
    return not secret or secret == ""
  else
    return false
  end
end

-- event_header(backend) returns the value of the backend's event-type header,
-- or nil when the backend embeds the event type in the body instead.
-- Callers that receive nil should pass the decoded payload to the normaliser
-- and let the registered webhook handler extract the event family.
local function event_header(backend)
  -- Gitea family + gogs: X-Gitea-Event
  if
    backend == "gitea"
    or backend == "forgejo"
    or backend == "codeberg"
    or backend == "notabug"
    or backend == "gogs"
  then
    return GetHeader("X-Gitea-Event")

  -- GitLab: X-Gitlab-Event
  elseif backend == "gitlab" then
    return GetHeader("X-Gitlab-Event")

  -- GitHub + GitBucket (GitHub API-compatible): X-GitHub-Event
  elseif backend == "github" or backend == "gitbucket" then
    return GetHeader("X-GitHub-Event")

  -- Bitbucket Cloud + Bitbucket Datacenter: X-Event-Key
  elseif backend == "bitbucket" or backend == "bitbucket_datacenter" then
    return GetHeader("X-Event-Key")

  -- Pagure: X-Pagure-Event
  elseif backend == "pagure" then
    return GetHeader("X-Pagure-Event")

  -- Confusio-normalized: X-Confusio-Event
  elseif backend == "confusio" then
    return GetHeader("X-Confusio-Event")

  -- Remaining backends embed the event type in the body.
  -- The registered normaliser is responsible for extracting it.
  else
    return nil
  end
end

function make_webhook_receiver(a) -- luacheck: globals make_webhook_receiver
  return function()
    -- Route: path must be /webhooks/{backend} with no trailing segments.
    local backend = GetPath():match("^/webhooks/([^/]+)$")
    if not backend or not KNOWN_BACKENDS[backend] then
      respond_json(404, { message = "Not Found" })
      return
    end

    -- Method: POST only.
    if GetMethod() ~= "POST" then
      respond_json(405, { message = "Method Not Allowed" })
      return
    end

    -- Content-Type: must include application/json.
    local ct = GetHeader("Content-Type") or ""
    if not ct:find("application/json", 1, true) then
      respond_json(400, { message = "Content-Type must be application/json" })
      return
    end

    -- Buffer raw body bytes.  HMAC verification operates on the raw bytes
    -- before any JSON decoding.
    local body = GetBody() or ""

    -- Signature verification using backend-native scheme.
    -- webhook_secrets is keyed by backend name; absent key → empty string
    -- (trust-the-network mode: all requests accepted).
    local secrets = a.config.webhook_secrets or {}
    local secret = secrets[backend] or ""
    if not verify_signature(backend, secret, body) then
      respond_json(401, { message = "Signature verification failed" })
      return
    end

    -- Decode JSON body.
    local ok_parse, payload = pcall(DecodeJson, body)
    if not ok_parse or type(payload) ~= "table" then
      respond_json(400, { message = "Invalid JSON body" })
      return
    end

    -- Determine canonical event name.
    -- For header-based backends: read the event-type header.
    -- For body-based backends:   the normaliser extracts it; pass nil here and
    --                            let the normaliser-registered handler decide.
    local ev = event_header(backend)

    -- No event-type header and no registered body-event handler → 422.
    if ev == nil and not next(a.backend.webhooks) then
      respond_json(422, { message = "No webhook handlers registered" })
      return
    end

    -- Dispatch to the registered normaliser for this event type.
    local handler = ev and a.backend.webhooks[ev]
    if not handler then
      if ev then
        respond_json(422, { message = "Unrecognised event type: " .. ev })
      else
        respond_json(422, { message = "No webhook handler registered for this backend" })
      end
      return
    end

    local internal_event, err = handler(payload)
    if not internal_event then
      respond_json(422, { message = err or "Normalisation failed" })
      return
    end

    respond_json(200, { message = "accepted" })
  end
end
