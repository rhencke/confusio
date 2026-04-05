-- SourceForge backend handler overrides.
if config.base_url == "" then config.base_url = "https://sourceforge.net" end
backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, config.base_url .. "/rest/p")
    if ok and status == 200 then respond_json(200, "OK", {})
    else respond_json(503, "Service Unavailable", {}) end
  end,
}
