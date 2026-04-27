-- Startup event synthesis.
--
-- When confusio starts with a backend configured and outbound targets registered,
-- emits two installation lifecycle events to all matching targets:
--
--   installation/created              — confusio came online for the configured backend
--   installation_repositories/added  — all repositories on the backend are accessible
--                                       (repository_selection = "all")
--
-- These events give GitHub-App-aware consumers a lifecycle signal without requiring
-- the forge to support an App installation model natively.
--
-- Globals consumed (must be loaded before this file is evaluated):
--   fanout_dispatch   — from internal/fanout.lua
--
-- Globals exported:
--   synthesize_startup_events

-- make_confusio_installation: builds a minimal GitHub-compatible installation object
-- representing confusio acting as a GitHub App for the given backend.
local function make_confusio_installation(backend, base_url, now_str)
  return {
    id = 0,
    app_id = 0,
    app_slug = "confusio",
    target_type = "User",
    target_id = 0,
    account = {
      login = backend,
      id = 0,
      node_id = "",
      avatar_url = "",
      gravatar_id = "",
      url = base_url,
      html_url = base_url,
      type = "Bot",
      site_admin = false,
    },
    repository_selection = "all",
    access_tokens_url = "",
    repositories_url = "",
    html_url = "",
    permissions = {},
    events = {},
    created_at = now_str,
    updated_at = now_str,
    has_multiple_single_files = false,
    single_file_paths = {},
  }
end

-- make_confusio_sender: builds a minimal GitHub-compatible sender object
-- for confusio-synthesized installation events.
local function make_confusio_sender()
  return {
    login = "confusio",
    id = 0,
    node_id = "",
    avatar_url = "",
    gravatar_id = "",
    url = "",
    html_url = "",
    type = "Bot",
    site_admin = false,
  }
end

-- synthesize_startup_events(backend, base_url): fires installation.created and
-- installation_repositories.added to all registered fanout targets.
--
-- When backend is "" or no targets are registered, fanout_dispatch returns 0
-- immediately without attempting delivery.
--
-- installation/created uses action "created" to signal that confusio came online.
-- installation_repositories/added uses repository_selection "all" and empty
-- repositories_added/removed arrays to indicate confusio proxies all repos.
function synthesize_startup_events(backend, base_url) -- luacheck: globals synthesize_startup_events
  if backend == "" then
    return
  end
  local now_str = os.date("!%Y-%m-%dT%H:%M:%SZ")
  local installation = make_confusio_installation(backend, base_url, now_str)
  local sender = make_confusio_sender()

  -- installation.created: confusio came online for the configured backend.
  fanout_dispatch(backend, "installation", {
    action = "created",
    installation = installation,
    repositories = {},
    sender = sender,
  })

  -- installation_repositories.added: repository_selection="all" with empty arrays
  -- indicates all repositories on the backend are now accessible via confusio.
  fanout_dispatch(backend, "installation_repositories", {
    action = "added",
    installation = installation,
    repository_selection = "all",
    repositories_added = {},
    repositories_removed = {},
    sender = sender,
  })
end
