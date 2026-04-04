-- Stub mock for backends that only need a reachable health-check endpoint.
-- Returns 200 for all requests; the confusio backend checks a path-specific
-- URL, but we don't need to validate auth or path here.
function OnHttpRequest()
  SetStatus(200, "OK")
end
