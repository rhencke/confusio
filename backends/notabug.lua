-- NotABug runs Gogs, which is API-compatible with Gitea v1 — delegate.
if config.base_url == "" then
  config.base_url = "https://notabug.org"
end
dofile("/zip/backends/gitea.lua")

-- Gogs does not have a gitignores, packages, or Actions API; clear inherited
-- Gitea handlers so the routes fall back to their .init.lua defaults (404,
-- empty list, or 501).
for k in pairs(backend_impl) do
  if k:find("gitignore") or k:find("_package") or k:find("_actions_") then
    backend_impl[k] = nil
  end
end
