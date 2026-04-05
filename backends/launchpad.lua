-- Launchpad backend handler overrides.
if config.base_url == "" then
  config.base_url = "https://api.launchpad.net"
end
backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, config.base_url .. "/devel/")
    if ok and status == 200 then
      respond_json(200, "OK", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,
}
