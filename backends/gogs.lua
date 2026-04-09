-- Gogs is API-compatible with Gitea v1 — delegate to the Gitea backend.
if config.base_url == "" then
  config.base_url = "https://try.gogs.io"
end
dofile("/zip/backends/gitea.lua")

-- Gogs does not have a packages or Actions API; clear inherited Gitea handlers
-- so the routes fall back to their .init.lua defaults (empty list or 501).
for k in pairs(backend_impl) do
  if k:find("_package") or k:find("_actions_") then
    backend_impl[k] = nil
  end
end
