-- Gogs is API-compatible with Gitea v1 — delegate to the Gitea backend.
if config.base_url == "" then config.base_url = "https://try.gogs.io" end
dofile("/zip/backends/gitea.lua")
