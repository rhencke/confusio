-- Mock outbound webhook delivery target.
--
-- Records every incoming POST delivery in memory.  Must be started with -u
-- (uniprocess mode) so the Lua state persists between requests:
--   sh mock-target.com -p <port> -u
--
-- Endpoints:
--   POST /reset        — clear the delivery list (call between test cases)
--   GET  /deliveries   — return all recorded deliveries as a JSON array
--   POST <any other>   — record the delivery; return 200 {"message":"accepted"}

local deliveries = {}

function OnHttpRequest()
  local method = GetMethod()
  local path = GetPath()

  -- Reset: clear recorded deliveries.
  if method == "POST" and path == "/reset" then
    deliveries = {}
    SetHeader("Content-Type", "application/json")
    Write('{"count":0}')
    return
  end

  -- Query: return all recorded deliveries as a JSON array.
  if method == "GET" and path == "/deliveries" then
    SetHeader("Content-Type", "application/json")
    if #deliveries == 0 then
      Write("[]")
    else
      Write(EncodeJson(deliveries)) -- luacheck: globals EncodeJson
    end
    return
  end

  -- Record: capture an incoming delivery POST.
  -- confusio's deliver.lua sends X-GitHub-Event/X-GitHub-Delivery for the
  -- default "github" shape, or X-Confusio-* headers for the "confusio" shape.
  if method == "POST" then
    local body = GetBody() -- luacheck: globals GetBody
    local ok_body, body_json = pcall(DecodeJson, body or "") -- luacheck: globals DecodeJson
    local entry = {
      path = path,
      user_agent = GetHeader("User-Agent") or "", -- luacheck: globals GetHeader
      github_event = GetHeader("X-GitHub-Event") or "",
      github_delivery = GetHeader("X-GitHub-Delivery") or "",
      confusio_event = GetHeader("X-Confusio-Event") or "",
      confusio_source = GetHeader("X-Confusio-Source") or "",
      confusio_delivery = GetHeader("X-Confusio-Delivery") or "",
      hub_signature_256 = GetHeader("X-Hub-Signature-256") or "",
      hub_signature = GetHeader("X-Hub-Signature") or "",
      body = body or "",
      body_json = ok_body and body_json or nil,
    }
    deliveries[#deliveries + 1] = entry
    SetHeader("Content-Type", "application/json")
    Write('{"message":"accepted"}')
    return
  end

  SetStatus(404, "Not Found") -- luacheck: globals SetStatus
  SetHeader("Content-Type", "application/json")
  Write('{"message":"Not Found"}')
end
