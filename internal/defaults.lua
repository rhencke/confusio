-- Default stub handlers for every endpoint group.
--
-- All handlers are collected into the global `defaults` table so the catalog
-- can reference them as defaults.empty_list, defaults.make_empty_collection("runners"),
-- etc.  None of these become individual globals; `defaults` is the only export.

local function empty_list()
  set_preamble()
  Write("[]")
end

-- Default handler for search endpoints: backends without native support return an
-- empty but valid GitHub search result envelope.
local function search_empty()
  set_preamble()
  Write('{"total_count":0,"incomplete_results":false,"items":[]}')
end

-- Default handler for GET /rate_limit: no provider has a GitHub-compatible rate
-- limit API, so confusio returns a partial response with just the `rate` key.
-- limit=999999 means "effectively unlimited"; reset is set one hour ahead of now.
local function rate_limit_response()
  local limit = 999999
  local reset = os.time() + 3600
  respond_json(200, {
    rate = { limit = limit, used = 0, remaining = limit, reset = reset },
  })
end

-- Default handlers for interaction-limits: no backend has a native interactions API.
-- GET returns {} (no restrictions in effect).
-- PUT echoes the provided limit back (acknowledged but not enforced).
-- DELETE returns 204 (no restrictions to remove).
local function interaction_limits_empty()
  set_preamble()
  Write("{}")
end

local function interaction_limits_put()
  local body = DecodeJson(GetBody() or "{}") or {}
  respond_json(200, body)
end

local function interaction_limits_delete()
  set_preamble(204)
end

-- Default handlers for migrations: no backend exposes GitHub-compatible migration APIs.
-- POST (start migration) returns 501 Not Implemented.
-- Per-resource endpoints (GET/DELETE on a specific migration) return 404.
-- Source import endpoints were deprecated by GitHub in May 2023; returns 410 Gone.
local function migrations_not_supported()
  respond_json(501, { message = "Migrations are not supported by this backend." })
end

local function migration_not_found()
  respond_json(404, { message = "Not Found" })
end

local function source_import_gone()
  respond_json(410, { message = "Importing via GitHub API is deprecated." })
end

-- Default handler for code-scanning endpoints: no backend has a native code scanning API.
-- Returns 501 Not Implemented with a descriptive message.
local function code_scanning_not_implemented()
  respond_json(501, { message = "Code scanning is not supported by this backend." })
end

-- Default handler for code-scanning list endpoints: returns an empty collection (200).
-- Per-resource endpoints use code_scanning_not_implemented (501) as their default.
local function code_scanning_list_empty()
  respond_json(200, {})
end

-- Default handlers for secret-scanning endpoints: no backend has a native secret scanning API.
-- Returns 501 Not Implemented with a descriptive message.
local function secret_scanning_not_implemented()
  respond_json(501, { message = "Secret scanning is not supported by this backend." })
end

-- Default handler for secret-scanning list endpoints: returns an empty collection (200).
-- Per-resource and mutation endpoints use secret_scanning_not_implemented (501) as their default.
local function secret_scanning_list_empty()
  respond_json(200, {})
end

-- Default handlers for Dependabot endpoints: most backends have no native Dependabot API.
-- Alert list endpoints return empty arrays (200); per-resource and mutation endpoints return 501.
-- Secrets list endpoints use make_empty_collection (defined below) for proper envelope format.
local function dependabot_not_implemented()
  respond_json(501, { message = "Dependabot is not supported by this backend." })
end

local function dependabot_list_empty()
  respond_json(200, {})
end

-- Default handler for Pages endpoints: no backend has a native GitHub Pages API.
-- Returns 501 Not Implemented with a descriptive message.
local function pages_not_implemented()
  respond_json(501, { message = "Pages is not supported by this backend." })
end

-- Default handler for Markdown endpoints: backends that support native markdown
-- rendering override these. Falls back to 501 Not Implemented.
local function markdown_not_implemented()
  respond_json(501, { message = "Markdown rendering is not supported by this backend." })
end

-- Default handlers for Actions endpoints: no backend has a native GitHub Actions-compatible API.
-- List endpoints use make_empty_collection to return a valid GitHub Actions envelope.
-- Per-resource and mutation endpoints return 501 Not Implemented.
local function actions_not_implemented()
  respond_json(501, { message = "Actions is not supported by this backend." })
end

-- Factory for Actions list endpoints: returns a handler that writes
-- {"total_count":0,"<key>":[]}, where key is the GitHub API collection name.
local function make_empty_collection(key)
  return function()
    set_preamble()
    Write('{"total_count":0,"' .. key .. '":[]}')
  end
end

-- Default handler for Git database endpoints: backends that have a native low-level
-- git object API override these. Falls back to 501 Not Implemented.
local function git_not_implemented()
  respond_json(501, { message = "Git database API is not supported by this backend." })
end

-- Default handler for Licenses endpoints: backends that have a native license
-- template API override these. Falls back to 501 Not Implemented.
local function licenses_not_implemented()
  respond_json(501, { message = "Licenses API is not supported by this backend." })
end

-- Default handler for Dependency Graph endpoints: backends that have a native
-- dependency graph API override these. Falls back to 501 Not Implemented.
local function dependency_graph_not_implemented()
  respond_json(501, { message = "Dependency graph is not supported by this backend." })
end

-- Default handlers for Projects endpoints: most backends have no native Projects API.
-- List endpoints return empty arrays (200); per-resource and mutation endpoints return 501.
local function projects_not_implemented()
  respond_json(501, { message = "Projects is not supported by this backend." })
end

local function projects_list_empty()
  respond_json(200, {})
end

-- Default handlers for Gists endpoints: most backends have no native gist API.
-- List endpoints return empty arrays (200); per-resource and mutation endpoints return 501.
local function gists_not_implemented()
  respond_json(501, { message = "Gists are not supported by this backend." })
end

-- Default handlers for Activity endpoints: event feeds, notifications, starring, and watching.
-- List endpoints return empty arrays (200); per-resource and mutation endpoints return 501.
local function activity_not_implemented()
  respond_json(501, { message = "This activity endpoint is not supported by this backend." })
end

local function activity_list_empty()
  set_preamble()
  Write("[]")
end

-- Default handlers for Reactions endpoints (commit comments, issue comments, issues, PR comments, releases).
-- List endpoints return empty arrays (200); create and delete endpoints return 501.
local function reactions_not_implemented()
  respond_json(501, { message = "Reactions are not supported by this backend." })
end

-- Default handlers for GET /zen, GET /octocat, GET /versions, GET /meta.
-- These endpoints are fully self-contained and do not call any backend.
local ZEN_QUOTES = {
  "A good dog does not need to understand the command.",
  "Fetch once; cache twice.",
  "The loyal dog returns what it is given.",
  "Sit. Stay. Commit.",
  "Every good boy deserves a response.",
  "Bark less, ship more.",
  "The dog who chases two rabbits catches neither.",
  "A wagging tail costs nothing.",
  "Treat the happy path as you would a good dog: reward it.",
  "Even the best dog buries things it cannot yet use.",
  "You cannot teach an old dog new protocols.",
  "The dog does not judge the bone.",
  "Roll over. Roll back.",
}
math.randomseed(os.time())
local function zen_response()
  set_preamble("text/plain;charset=utf-8")
  Write(ZEN_QUOTES[math.random(#ZEN_QUOTES)])
end

local function octocat_response()
  set_preamble("application/octocat-stream")
  Write("🐙🐱")
end

local function versions_response()
  set_preamble()
  Write('["2022-11-28"]')
end

-- meta_response returns a minimal but valid GitHub /meta structure.
-- IP range arrays are empty since confusio is not GitHub infrastructure.
local function meta_response()
  set_preamble()
  Write(
    '{"verifiable_password_authentication":false'
      .. ',"ssh_key_fingerprints":{}'
      .. ',"ssh_keys":[]'
      .. ',"hooks":[]'
      .. ',"web":[]'
      .. ',"api":[]'
      .. ',"git":[]'
      .. ',"packages":[]'
      .. ',"pages":[]'
      .. ',"importer":[]'
      .. ',"actions":[]'
      .. ',"dependabot":[]'
      .. ',"github_enterprise_importer":[]'
      .. ',"domains":{"website":[],"codespaces":[],"copilot":[],"packages":[]}}'
  )
end

local function teapot_response()
  set_preamble(418, "text/plain;charset=utf-8")
  Write("I'm a teapot.")
end

defaults = { -- luacheck: globals defaults
  empty_list = empty_list,
  search_empty = search_empty,
  rate_limit_response = rate_limit_response,
  interaction_limits_empty = interaction_limits_empty,
  interaction_limits_put = interaction_limits_put,
  interaction_limits_delete = interaction_limits_delete,
  migrations_not_supported = migrations_not_supported,
  migration_not_found = migration_not_found,
  source_import_gone = source_import_gone,
  code_scanning_not_implemented = code_scanning_not_implemented,
  code_scanning_list_empty = code_scanning_list_empty,
  secret_scanning_not_implemented = secret_scanning_not_implemented,
  secret_scanning_list_empty = secret_scanning_list_empty,
  dependabot_not_implemented = dependabot_not_implemented,
  dependabot_list_empty = dependabot_list_empty,
  pages_not_implemented = pages_not_implemented,
  markdown_not_implemented = markdown_not_implemented,
  actions_not_implemented = actions_not_implemented,
  make_empty_collection = make_empty_collection,
  git_not_implemented = git_not_implemented,
  licenses_not_implemented = licenses_not_implemented,
  dependency_graph_not_implemented = dependency_graph_not_implemented,
  projects_not_implemented = projects_not_implemented,
  projects_list_empty = projects_list_empty,
  gists_not_implemented = gists_not_implemented,
  activity_not_implemented = activity_not_implemented,
  activity_list_empty = activity_list_empty,
  reactions_not_implemented = reactions_not_implemented,
  zen_response = zen_response,
  octocat_response = octocat_response,
  versions_response = versions_response,
  meta_response = meta_response,
  teapot_response = teapot_response,
}
