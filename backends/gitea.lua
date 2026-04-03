-- Gitea backend handler overrides.
-- Loaded by .init.lua when config.backend == "gitea".
-- Only endpoints that behave differently from the default need to be listed here.
backend_impl = {
  root = function()
    local ok, status = pcall(Fetch, config.base_url .. "/api/v1/version")
    if ok and status == 200 then respond_json(200, "OK", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,
}
