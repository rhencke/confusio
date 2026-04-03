-- Gogs backend handler overrides.
backend_impl = {
  root = function()
    local ok, status = pcall(Fetch, config.base_url .. "/api/v1/version", make_fetch_opts("token"))
    if ok and status == 200 then respond_json(200, "OK", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,
  emojis = function() respond_json(404, "Not Found", { message = "Not Found" }) end,
}
