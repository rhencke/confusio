-- NotABug runs Gogs, which is API-compatible with Gitea v1 — delegate.
if config.base_url == "" then
  config.base_url = "https://notabug.org"
end
dofile("/zip/backends/gitea.lua")
