-- Mock RhodeCode server.
--
-- Confusio's RhodeCode backend only probes /_admin/api at startup today.  Keep
-- that health route explicit, and provide webhook-shaped mock routes for
-- fixture/delivery tests without making every unrelated REST path look valid.

local function json(status, reason, body)
  SetStatus(status, reason)
  SetHeader("Content-Type", "application/json")
  Write(body)
end

local function decoded_body()
  local raw = GetBody() or "" -- luacheck: globals GetBody
  local ok, payload = pcall(DecodeJson, raw) -- luacheck: globals DecodeJson
  if ok and type(payload) == "table" then
    return payload
  end
  return nil
end

local function rhodecode_event(payload)
  payload = payload or {}
  local pr_action = payload.action
  return payload.event
    or payload.event_type
    or payload.hook
    or payload.hook_type
    or payload.hook_name
    or (payload.pull_request and ((pr_action == "closed" or pr_action == "merged") and "CLOSE_PULLREQUEST_HOOK" or "CREATE_PULLREQUEST_HOOK"))
    or (payload.refs and "PUSH_HOOK")
    or ""
end

local function webhook_response(payload)
  local event = rhodecode_event(payload)
  if event == "" then
    return json(422, "Unprocessable Entity", '{"message":"unknown RhodeCode webhook fixture"}')
  end
  json(
    200,
    "OK",
    EncodeJson({ -- luacheck: globals EncodeJson
      message = "accepted",
      event = event,
    })
  )
end

function OnHttpRequest()
  local method = GetMethod()
  local path = GetPath()

  -- Health check used by backends/rhodecode.lua.
  if method == "GET" and path == "/_admin/api" then
    return json(200, "OK", '{"rhodecode_version":"5.11.4","status":"ok"}')
  end

  -- Minimal RhodeCode-style webhook administration surface for tests that need
  -- the upstream mock to behave like a webhook-aware server.
  if path == "/_admin/api/webhooks" and method == "GET" then
    return json(
      200,
      "OK",
      '{"webhooks":[{"id":1,"url":"https://example.com/hook",'
        .. '"events":["PUSH_HOOK","CREATE_PULLREQUEST_HOOK","CLOSE_PULLREQUEST_HOOK",'
        .. '"CREATE_REPO_HOOK","DELETE_REPO_HOOK"],"active":true}]}'
    )
  elseif path == "/_admin/api/webhooks" and method == "POST" then
    return json(
      201,
      "Created",
      '{"id":2,"url":"https://example.com/new-hook",'
        .. '"events":["PUSH_HOOK","CREATE_PULLREQUEST_HOOK"],"active":true}'
    )
  elseif path == "/_admin/api/webhooks/1" and method == "GET" then
    return json(
      200,
      "OK",
      '{"id":1,"url":"https://example.com/hook",'
        .. '"events":["PUSH_HOOK","CREATE_PULLREQUEST_HOOK","CLOSE_PULLREQUEST_HOOK"],'
        .. '"active":true}'
    )
  elseif path == "/_admin/api/webhooks/1" and method == "PUT" then
    return json(
      200,
      "OK",
      '{"id":1,"url":"https://example.com/updated-hook",'
        .. '"events":["PUSH_HOOK","CREATE_REPO_HOOK","DELETE_REPO_HOOK"],"active":true}'
    )
  elseif path == "/_admin/api/webhooks/1" and method == "DELETE" then
    SetStatus(204, "No Content")
    return
  end

  -- Direct mock webhook receiver.  The real receive pipeline lives in
  -- confusio, but keeping this route here makes fixture-driven mock tests
  -- possible without the old "200 for everything" behavior.
  if method == "POST" and path == "/webhooks/rhodecode" then
    local payload = decoded_body()
    if not payload then
      return json(400, "Bad Request", '{"message":"invalid JSON"}')
    end
    return webhook_response(payload)
  end

  json(404, "Not Found", '{"message":"Not Found"}')
end
