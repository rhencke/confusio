-- NotABug runs Gogs, which is API-compatible with Gitea v1.  Family metadata
-- (including which features Gogs lacks) is declared in provider_families.
if config.base_url == "" then
  config.base_url = provider_families.gitea.aliases[config.backend].default_url
end
dofile("/zip/backends/gitea.lua")
