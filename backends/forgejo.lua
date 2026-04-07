-- Forgejo is API-compatible with Gitea v1 — delegate to the Gitea backend.
if config.base_url == "" then
  config.base_url = "https://codeberg.org"
end
dofile("/zip/backends/gitea.lua")

-- Code scanning: Forgejo has no native code scanning API.
-- List endpoints return empty collections; per-resource endpoints return 501.
local _b = backend_impl

_b.list_org_code_scanning_alerts = function(_org)
  respond_json(200, {})
end

_b.list_repo_code_scanning_alerts = function(_owner, _repo)
  respond_json(200, {})
end

_b.list_code_scanning_alert_instances = function(_owner, _repo, _alert_number)
  respond_json(200, {})
end

_b.list_code_scanning_analyses = function(_owner, _repo)
  respond_json(200, {})
end
