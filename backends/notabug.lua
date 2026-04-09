-- NotABug runs Gogs, which is API-compatible with Gitea v1 — delegate.
if config.base_url == "" then
  config.base_url = "https://notabug.org"
end
dofile("/zip/backends/gitea.lua")

-- NotABug's Gogs instance does not expose the /gitignores API.
backend_impl.get_gitignore_templates = function()
  respond_json(404, { message = "Not Found" })
end
backend_impl.get_gitignore_template = function(_name)
  respond_json(404, { message = "Not Found" })
end

-- Gogs does not have a packages or Actions API; clear inherited Gitea handlers
-- so the routes fall back to their .init.lua defaults (empty list or 501).
for k in pairs(backend_impl) do
  if k:find("_package") or k:find("_actions_") then
    backend_impl[k] = nil
  end
end
