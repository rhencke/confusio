-- Kallithea backend handler overrides.
backend_impl = {
  get_root = function()
    proxy_health_check(pcall(Fetch, config.base_url .. "/_admin/api", make_fetch_opts("bearer")))
  end,

  -- Issues -----------------------------------------------------------------------
  -- Kallithea has no native issue tracker.
  -- All issues, labels, milestones, and assignees endpoints fall back to the
  -- default empty-list / 404 handlers defined in .init.lua.
}
