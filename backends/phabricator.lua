-- Phabricator backend handler overrides.
backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, config.base_url .. "/api/conduit.ping")
    if ok and status == 200 then respond_json(200, "OK", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,
}
