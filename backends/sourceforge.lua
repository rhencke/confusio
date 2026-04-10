-- SourceForge backend handler overrides.
if config.base_url == "" then
  config.base_url = "https://sourceforge.net"
end
backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, config.base_url .. "/rest/p")
    if ok and status == 200 then
      respond_json(200, {})
    else
      respond_json(503, {})
    end
  end,

  -- Issues -----------------------------------------------------------------------
  -- SourceForge uses the Allura ticket tracker, whose REST API shape differs
  -- significantly from GitHub Issues and is not currently mapped.
  -- All issues, labels, milestones, and assignees endpoints fall back to the
  -- default empty-list / 404 handlers defined in .init.lua.
}

-- Code scanning: SourceForge has no native code scanning API.
-- All code scanning endpoints fall back to the default handlers in .init.lua:
-- list endpoints return 200 empty, per-resource endpoints return 501.
