-- Provider-family metadata and family-backend loader (global).
--
-- provider_families   — authoritative source for backend, mock, and test reuse
-- load_family_backend — called by alias backends to inherit a root family implementation

-- Provider-family metadata (global: backends/<name>.lua can read at startup).
-- Authoritative source for backend, mock, and test reuse relationships.
-- The table key is the root backend name (the canonical family implementation).
-- Each alias entry declares:
--   default_url  string — backend default when no base_url is given
--   strip        table  — Lua patterns; backend_impl keys matching any are
--                         cleared after inheriting from the root implementation,
--                         because those features are absent from this variant
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
-- supplied one, loads the root backend via dofile, then clears any backend_impl
-- keys whose names match the alias's strip patterns (features absent from this
-- variant).
function load_family_backend(root)
  local family = provider_families[root]
  assert(family, "unknown provider family: " .. root)
  local alias = family.aliases[config.backend]
  assert(alias, config.backend .. " is not an alias in the " .. root .. " family")
  if config.base_url == "" then
    config.base_url = alias.default_url
  end
  dofile("/zip/backends/" .. root .. ".lua")
  for _, pattern in ipairs(alias.strip or {}) do
    for k in pairs(backend_impl) do
      if k:find(pattern) then
        backend_impl[k] = nil
      end
    end
  end
end
