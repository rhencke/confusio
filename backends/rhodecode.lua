-- RhodeCode backend handler overrides.
backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, config.base_url .. "/_admin/api", make_fetch_opts("bearer"))
    if ok and status == 200 then
      respond_json(200, "OK", {})
    else
      respond_json(503, "Service Unavailable", {})
    end
  end,
}
