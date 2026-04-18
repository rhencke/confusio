-- SourceForge backend handler overrides.
if config.base_url == "" then
  config.base_url = "https://sourceforge.net"
end
local b = make_backend_builder()
b:rest("get_root", function()
  proxy_health_check(pcall(Fetch, config.base_url .. "/rest/p"))
end)

-- Issues -----------------------------------------------------------------------
-- SourceForge uses the Allura ticket tracker, whose REST API shape differs
-- significantly from GitHub Issues and is not currently mapped.
-- All issues, labels, milestones, and assignees endpoints fall back to the
-- default empty-list / 404 handlers defined in .init.lua.

b:build()
