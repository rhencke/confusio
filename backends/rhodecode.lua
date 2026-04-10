-- RhodeCode backend handler overrides.
backend_impl = {
  get_root = function()
    local ok, status = pcall(Fetch, config.base_url .. "/_admin/api", make_fetch_opts("bearer"))
    if ok and status == 200 then
      respond_json(200, {})
    else
      respond_json(503, {})
    end
  end,

  -- Issues -----------------------------------------------------------------------
  -- RhodeCode has no native issue tracker; it integrates with external trackers
  -- such as JIRA. All issues, labels, milestones, and assignees endpoints fall
  -- back to the default empty-list / 404 handlers defined in .init.lua.
}
