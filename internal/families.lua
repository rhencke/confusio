-- Provider-family metadata (global).
--
-- provider_families   — authoritative source for backend, mock, and test reuse

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
