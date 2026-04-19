-- Outbound delivery signing for GitHub-emulation and confusio-normalized shapes.
--
-- sign_github(secret, body)
--   Computes the GitHub-emulation delivery signatures.
--   Returns (sha256_value, sha1_value) — both are complete header value strings —
--   or (nil, nil) when no secret is configured.
--     X-Hub-Signature-256: <sha256_value>
--     X-Hub-Signature:     <sha1_value>
--
-- sign_confusio(secret, body, timestamp)
--   Computes the confusio-normalized delivery signature.
--   timestamp is Unix epoch seconds (integer); it is folded into the HMAC
--   basestring ("v1:<ts>:<body>") so that replaying an old delivery with a valid
--   body but a stale timestamp produces a different digest.
--   Returns the complete X-Confusio-Signature-256 header value string ("sha256=<hex>,
--   v=1, ts=<ts>"), or nil when no secret is configured.
--
-- Globals exported:
--   sign_github, sign_confusio

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

-- sign_confusio(secret, body, timestamp) computes the confusio-normalized delivery
-- signature.  The HMAC basestring is "v1:<timestamp>:<body>"; the v=1 and ts=<ts>
-- fields in the header value allow consumers to extract and verify the timestamp
-- without a second parse pass.
function sign_confusio(secret, body, timestamp) -- luacheck: globals sign_confusio
  if not secret or secret == "" then
    return nil
  end
  local ts = tostring(timestamp)
  local basestring = "v1:" .. ts .. ":" .. body
  return "sha256=" .. hmac_hex("sha256", secret, basestring) .. ", v=1, ts=" .. ts
end
