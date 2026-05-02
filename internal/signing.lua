-- Outbound delivery signing for GitHub-emulation and backend-native shapes.
--
-- sign_github(secret, body)
--   Computes the GitHub-emulation delivery signatures.
--   Returns (sha256_value, sha1_value) — both are complete header value strings —
--   or (nil, nil) when no secret is configured.
--     X-Hub-Signature-256: <sha256_value>
--     X-Hub-Signature:     <sha1_value>
--
-- sign_for_backend(backend, secret, body)
--   Returns a Lua table of signature headers appropriate for the given backend's
--   native webhook scheme.  Returns an empty table {} when no secret is configured.
--   The signing scheme matches what verify_signature in internal/webhooks.lua expects
--   for each backend — both must stay in sync when new backends are added.
--
-- Globals exported:
--   sign_github, sign_for_backend

local function to_hex(bytes)
  local hex = {}
  for i = 1, #bytes do
    hex[i] = string.format("%02x", bytes:byte(i))
  end
  return table.concat(hex)
end

local function hmac_hex(alg, secret, msg)
  return to_hex(GetCryptoHash(alg, msg, secret)) -- luacheck: globals GetCryptoHash
end

-- sign_github(secret, body) computes both GitHub-emulation delivery signatures.
-- Consumers verify with X-Hub-Signature-256; X-Hub-Signature is legacy compat only.
function sign_github(secret, body) -- luacheck: globals sign_github
  if not secret or secret == "" then
    return nil, nil
  end
  return "sha256=" .. hmac_hex("sha256", secret, body), "sha1=" .. hmac_hex("sha1", secret, body)
end

-- sign_for_backend(backend, secret, body) returns a table of signature headers
-- using the native webhook scheme for the given backend.
-- Returns {} (empty table) when no secret is configured.
function sign_for_backend(backend, secret, body) -- luacheck: globals sign_for_backend
  if not secret or secret == "" then
    return {}
  end
  if backend == "gitea" or backend == "forgejo" or backend == "codeberg" then
    return { ["X-Gitea-Signature"] = hmac_hex("sha256", secret, body) }
  elseif backend == "gogs" or backend == "notabug" then
    return { ["X-Gogs-Signature"] = hmac_hex("sha256", secret, body) }
  elseif backend == "gitlab" then
    return { ["X-Gitlab-Token"] = secret }
  elseif backend == "bitbucket" or backend == "bitbucket_datacenter" then
    return { ["X-Hub-Signature"] = "sha256=" .. hmac_hex("sha256", secret, body) }
  elseif backend == "gitbucket" then
    return { ["X-Hub-Signature"] = "sha1=" .. hmac_hex("sha1", secret, body) }
  elseif backend == "launchpad" then
    return { ["X-Hub-Signature"] = "sha1=" .. hmac_hex("sha1", secret, body) }
  elseif backend == "phabricator" then
    return { ["X-Phabricator-Webhook-Signature"] = hmac_hex("sha256", secret, body) }
  elseif backend == "pagure" then
    return {
      ["X-Pagure-Signature-256"] = hmac_hex("sha256", secret, body),
      ["X-Pagure-Signature"] = hmac_hex("sha512", secret, body),
    }
  elseif backend == "harness" then
    return { ["X-Harness-Token"] = secret }
  elseif backend == "onedev" then
    return { ["X-OneDev-Signature"] = secret }
  elseif backend == "gerrit" or backend == "radicle" then
    return { ["Authorization"] = secret }
  elseif backend == "gitblit" then
    return { ["X-Gitblit-Token"] = secret }
  elseif backend == "rhodecode" then
    return { ["X-RhodeCode-Signature"] = secret }
  elseif backend == "sourceforge" then
    return { ["X-Allura-Signature"] = "sha1=" .. hmac_hex("sha1", secret, body) }
  elseif backend == "tuleap" then
    return { ["X-Tuleap-Webhook-Secret"] = secret }
  elseif backend == "azuredevops" then
    return { ["Authorization"] = "Basic " .. EncodeBase64(secret) } -- luacheck: globals EncodeBase64
  elseif backend == "confusio" then
    local ts = tostring(os.time())
    local basestring = "v1:" .. ts .. ":" .. body
    return {
      ["X-Confusio-Signature-256"] = "sha256="
        .. hmac_hex("sha256", secret, basestring)
        .. ", v=1, ts="
        .. ts,
    }
  else
    -- Default (unknown/github/sourcehut/etc.): GitHub-style dual signatures.
    return {
      ["X-Hub-Signature-256"] = "sha256=" .. hmac_hex("sha256", secret, body),
      ["X-Hub-Signature"] = "sha1=" .. hmac_hex("sha1", secret, body),
    }
  end
end
