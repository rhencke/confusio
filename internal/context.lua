-- Application context constructor.
--
-- make_app(cfg) returns the single app context table for the process lifetime.
-- Fields are populated by .init.lua after the backend loads.
--
-- Fields:
--   config          — backend config table (same object as the global `config`)
--   backend         — backend runtime object:
--     backend.rest          — REST handler registry; keyed by handler name
--                             (e.g. "get_repo"); set by b:build() via make_backend_builder.
--                             After the catalog loads, missing keys fall through
--                             to catalog-derived rest_defaults via __index.
--     backend.graphql       — GraphQL resolver registry; keyed by resolver key
--                             (e.g. "Query.viewer", "node.Repository");
--                             wired to the graphql_resolvers global in .init.lua
--     backend.capabilities  — provider capability modules; keyed by domain name
--                             (e.g. "repos", "users", "issues"); each value is a
--                             table of named operations (e.g. { get, list, ... }).
--                             Both REST handlers and GraphQL resolvers call into
--                             these to avoid duplicating fetch + translate + error logic.
--     backend.webhooks      — inbound webhook event handler registry; keyed by event name
--                             (e.g. "push", "issues"); set by b:build() via make_backend_builder.
--                             The receiver pipeline calls backend.webhooks[event](raw_payload)
--                             to normalise a forge event into confusio's internal event model.
--     backend.webhook_translators — normalized outbound translator registry; keyed by
--                             internal event name. Confusio-shape delivery calls these
--                             with (internal_event, fields) and falls back to the shared
--                             envelope factory when no event-specific translator exists.
--     backend.webhook_github_translators — GitHub-shape outbound translator registry;
--                             keyed by internal event name. GitHub-shape delivery calls
--                             these with (internal_event, fields) and falls back to the
--                             original provider payload when no translator exists.
--   webhook_receiver  — webhook receive pipeline; function(); installed by .init.lua after
--                       make_webhook_receiver(app) is called.  Handles POST /webhooks/{backend}:
--                       signature verification, event dispatch, and response.  nil until wired.
--   allow_anonymous — auth-gate flag; true means unauthenticated requests are allowed

function make_app(cfg) -- luacheck: globals make_app
  return {
    config = cfg,
    backend = {
      rest = {},
      graphql = {},
      capabilities = {},
      webhooks = {},
      webhook_translators = {},
      webhook_github_translators = {},
    },
    allow_anonymous = true,
  }
end
