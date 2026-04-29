-- Outbound HTTP delivery (fire-and-record).
--
-- deliver_fire(target, backend, event_type, payload[, internal_event, translators]) performs one HTTP POST
-- to target.url.  No retry, no circuit breaker.  The outcome is logged
-- (HTTP status or error) and the function returns immediately.
--
-- target is a table with fields:
--   name              (string)  — logical target name
--   url               (string)  — destination endpoint
--   shape             (string)  — "github" (default) or "confusio"
--   secret            (string)  — optional HMAC signing secret
--   delivery_log_path (string)  — structured delivery-attempt log path
--
-- Globals exported:
--   deliver_fire(target, backend, event_type, payload[, internal_event, translators]) → ok, http_status_or_nil, error_or_nil

-- _deliver_headers: builds the outbound request headers table.
-- For "github" shape: X-GitHub-Event, X-GitHub-Delivery, and provider-native signature headers.
-- For "confusio" shape: X-Confusio-Event/Source/Delivery and provider-native signature headers.
local function _deliver_headers(backend, event_type, delivery_id, shape, body, secret)
  local headers = {
    ["Content-Type"] = "application/json",
    ["User-Agent"] = "confusio/1.0",
  }
  if shape == "confusio" then
    headers["X-Confusio-Event"] = event_type
    headers["X-Confusio-Source"] = backend
    headers["X-Confusio-Delivery"] = delivery_id
  else
    -- "github" shape (default and fallback)
    headers["X-GitHub-Event"] = event_type
    headers["X-GitHub-Delivery"] = delivery_id
  end
  local sig_hdrs = sign_for_backend(backend, secret or "", body) -- luacheck: globals sign_for_backend
  for k, v in pairs(sig_hdrs) do
    headers[k] = v
  end
  return headers
end

local function append_delivery_attempt_log(
  target,
  backend,
  event_type,
  delivery_id,
  http_status,
  duration_ms,
  err
)
  local path = target.delivery_log_path or ""
  if path == "" then
    return
  end

  local record = {
    timestamp = now_iso8601(), -- luacheck: globals now_iso8601
    target_name = target.name or "default",
    event_type = event_type,
    delivery_id = delivery_id,
    backend = backend,
    status_code = http_status,
    latency_ms = duration_ms,
    error = err,
  }
  local line = EncodeJson(record) .. "\n" -- luacheck: globals EncodeJson
  local ok_append, append_err = pcall(function()
    local f = assert(io.open(path, "a"))
    f:write(line)
    f:close()
  end)
  if not ok_append then
    Log( -- luacheck: globals Log kLogWarn
      kLogWarn,
      string.format("deliver: log_path=%s error=%s", path, tostring(append_err))
    )
  end
end

-- deliver_fire: performs one HTTP POST delivery to target.url.
-- Logs the outcome (status, duration, error) and returns immediately.
-- No retry, no circuit breaker.
-- Returns (ok, http_status_or_nil, error_or_nil):
--   ok=true  — delivery succeeded (HTTP 2xx)
--   ok=false — delivery failed; http_status is nil on network error
function deliver_fire(target, backend, event_type, payload, internal_event, translators) -- luacheck: globals deliver_fire
  local t0 = os.clock()
  local delivery_id = make_uuid() -- luacheck: globals make_uuid
  local body = fanout_body( -- luacheck: globals fanout_body
    backend,
    event_type,
    payload,
    target.shape,
    internal_event,
    translators,
    { id = delivery_id }
  )
  local hdrs = _deliver_headers(backend, event_type, delivery_id, target.shape, body, target.secret)

  local pcall_ok, result = pcall(Fetch, target.url, { -- luacheck: globals Fetch
    method = "POST",
    body = body,
    headers = hdrs,
  })

  local duration_ms = math.floor((os.clock() - t0) * 1000)

  if not pcall_ok then
    local err = tostring(result)
    append_delivery_attempt_log(target, backend, event_type, delivery_id, nil, duration_ms, err)
    Log( -- luacheck: globals Log kLogWarn
      kLogWarn,
      string.format(
        "deliver: url=%s event=%s duration=%dms error=%s",
        target.url,
        event_type,
        duration_ms,
        err
      )
    )
    return false, nil, err
  end

  local http_status = result
  local ok = http_status >= 200 and http_status < 300
  append_delivery_attempt_log(
    target,
    backend,
    event_type,
    delivery_id,
    http_status,
    duration_ms,
    nil
  )
  Log(
    ok and kLogVerbose or kLogWarn, -- luacheck: globals kLogVerbose
    string.format(
      "deliver: url=%s event=%s status=%d duration=%dms",
      target.url,
      event_type,
      http_status,
      duration_ms
    )
  )
  return ok, http_status, nil
end
