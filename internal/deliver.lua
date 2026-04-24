-- Outbound HTTP delivery for the webhook dispatcher.
--
-- deliver_attempt(delivery_id) performs one HTTP delivery attempt.
-- It looks up the delivery record, the originating event, and the target;
-- serialises the body for the target's shape; signs it if a secret is
-- configured; and POSTs to the target URL.
--
-- The delivery record is updated with the outcome:
--   2xx              → status "delivered", attempt_count++
--   5xx or 429       → status "retrying",  next_attempt_at = now (eligible immediately)
--   other 4xx        → status "failed",    attempt_count++
--   network error    → status "retrying",  next_attempt_at = now
--
-- The retry scheduler (a later module) replaces next_attempt_at with a
-- proper exponential-backoff value.  Setting it to now here ensures records
-- are immediately visible to outbox_pending_retries until the scheduler runs.
--
-- Globals exported:
--   deliver_attempt(delivery_id) → ok, http_status_or_nil, error_or_nil

-- _deliver_headers: builds the outbound request headers table.
-- For "github" shape: X-GitHub-Event, X-GitHub-Delivery, and Hub-Signature headers.
-- For "confusio" shape: X-Confusio-Event/Source/Delivery and Confusio-Signature header.
local function _deliver_headers(event, delivery, shape, secret, body)
  local headers = {
    ["Content-Type"] = "application/json",
    ["User-Agent"] = "confusio/1.0",
  }
  if shape == "confusio" then
    headers["X-Confusio-Event"] = event.event_type
    headers["X-Confusio-Source"] = event.backend
    headers["X-Confusio-Delivery"] = delivery.delivery_id
    local sig = sign_confusio(secret, body, os.time())
    if sig ~= nil then
      headers["X-Confusio-Signature-256"] = sig
    end
  else
    -- "github" shape (default and fallback)
    headers["X-GitHub-Event"] = event.event_type
    headers["X-GitHub-Delivery"] = delivery.delivery_id
    local sig256, sig1 = sign_github(secret, body)
    if sig256 ~= nil then
      headers["X-Hub-Signature-256"] = sig256
      headers["X-Hub-Signature"] = sig1
    end
  end
  return headers
end

-- deliver_attempt: performs one HTTP POST delivery for the given delivery_id.
-- Updates the delivery record with the attempt result.
-- Returns (ok, http_status_or_nil, error_or_nil):
--   ok=true  — delivery succeeded (HTTP 2xx)
--   ok=false — delivery failed; http_status is nil on network/lookup error
function deliver_attempt(delivery_id) -- luacheck: globals deliver_attempt
  local delivery = outbox_get_delivery(delivery_id)
  if delivery == nil then
    return false, nil, "delivery not found"
  end
  local event = outbox_get_event(delivery.event_id)
  if event == nil then
    return false, nil, "event not found"
  end
  local target = target_get(delivery.target_id)
  if target == nil then
    outbox_update_delivery(delivery_id, {
      status = "failed",
      attempt_count = delivery.attempt_count + 1,
      last_error = "target not found or deleted",
    })
    return false, nil, "target not found or deleted"
  end
  local secret = target_get_secret(delivery.target_id)
  local body = fanout_body(event.backend, event.event_type, event.payload, target.shape)
  local hdrs = _deliver_headers(event, delivery, target.shape, secret, body)
  local new_count = delivery.attempt_count + 1
  local pcall_ok, result, _resp_hdrs, _resp_body =
    pcall(Fetch, target.url, { method = "POST", body = body, headers = hdrs })
  if not pcall_ok then
    -- result is the error message from pcall
    local err = tostring(result)
    outbox_update_delivery(delivery_id, {
      status = "retrying",
      attempt_count = new_count,
      next_attempt_at = now_iso8601(),
      last_http_status = nil,
      last_error = err,
    })
    return false, nil, err
  end
  -- result is the integer HTTP status code
  local http_status = result
  if http_status >= 200 and http_status < 300 then
    outbox_update_delivery(delivery_id, {
      status = "delivered",
      attempt_count = new_count,
      last_http_status = http_status,
      last_error = nil,
    })
    return true, http_status, nil
  elseif http_status == 429 or http_status >= 500 then
    local err = "HTTP " .. tostring(http_status)
    outbox_update_delivery(delivery_id, {
      status = "retrying",
      attempt_count = new_count,
      next_attempt_at = now_iso8601(),
      last_http_status = http_status,
      last_error = err,
    })
    return false, http_status, err
  else
    local err = "HTTP " .. tostring(http_status)
    outbox_update_delivery(delivery_id, {
      status = "failed",
      attempt_count = new_count,
      last_http_status = http_status,
      last_error = err,
    })
    return false, http_status, err
  end
end
