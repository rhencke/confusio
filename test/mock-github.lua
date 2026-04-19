-- Mock GitHub API server.
-- GitHub webhook tests send payloads directly to confusio; the upstream API is
-- not called during webhook normalisation.  This mock provides a minimal 200
-- response for any request confusio might make at startup.
function OnHttpRequest()
  SetStatus(200, "OK")
  SetHeader("Content-Type", "application/json")
  Write("{}")
end
