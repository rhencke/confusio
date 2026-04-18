-- Provider-family metadata and family-backend loader (global).
--
-- provider_families   — authoritative source for backend, mock, and test reuse
-- load_family_backend — called by alias backends to inherit a root family implementation

-- Provider-family metadata (global: backends/<name>.lua can read at startup).
-- Authoritative source for backend, mock, and test reuse relationships.
-- The table key is the root backend name (the canonical family implementation).
-- Each alias entry declares:
--   default_url  string — backend default when no base_url is given
--   strip        table  — Lua patterns; REST handler keys matching any pattern are
--                         excluded when the root builder calls b:build(), because
--                         those features are absent from this alias variant
provider_families = {
  gitea = {
    aliases = {
      forgejo = { default_url = "https://codeberg.org" },
      codeberg = { default_url = "https://codeberg.org" },
      gogs = { default_url = "https://try.gogs.io", strip = { "_package", "_actions_" } },
      notabug = {
        default_url = "https://notabug.org",
        strip = { "gitignore", "_package", "_actions_" },
      },
    },
  },
}

-- load_family_backend is global: alias backends call it to inherit a family
-- implementation.  Looks up config.backend in provider_families[root].aliases,
-- sets config.base_url from the alias's default_url when the user hasn't
-- supplied one, then loads the root backend via dofile.
--
-- Strip patterns are declared declaratively: before loading the root backend,
-- app._family_strip is set to the alias's strip list.  The root backend's
-- builder reads app._family_strip in b:build() and excludes REST handler keys
-- whose names match any pattern.  app._family_strip is cleared after dofile
-- returns.
function load_family_backend(root)
  local family = provider_families[root]
  assert(family, "unknown provider family: " .. root)
  local alias = family.aliases[config.backend]
  assert(alias, config.backend .. " is not an alias in the " .. root .. " family")
  if config.base_url == "" then
    config.base_url = alias.default_url
  end
  -- Declare strip patterns before loading the root backend so the builder can
  -- apply them inside b:build() rather than mutating app.backend_impl afterward.
  app._family_strip = alias.strip
  dofile("/zip/backends/" .. root .. ".lua")
  app._family_strip = nil
end
