# Startup event synthesis delivery test — "confusio" shape — run by Phase 28 in test-unit.sh.
#
# Same as webhook-delivery-startup.hurl but with webhook_target_shape=confusio.
# Verifies that synthesized startup events use X-Confusio-* headers instead of
# X-GitHub-* headers and that X-Confusio-Source identifies the configured backend.
#
# Two {{variables}} are injected by the harness:
#   {{host}}   — confusio  (port 18080)
#   {{target}} — mock delivery target (port 18082, started with -u)

# ── installation: created (confusio shape) ────────────────────────────────────
# ── installation_repositories: added (confusio shape) ────────────────────────

GET http://{{target}}/deliveries

HTTP 200
[Asserts]
jsonpath "$" count == 2
jsonpath "$[0].confusio_event" == "installation"
jsonpath "$[0].confusio_source" == "gitea"
jsonpath "$[0].confusio_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[0].github_event" == ""
jsonpath "$[1].confusio_event" == "installation_repositories"
jsonpath "$[1].confusio_source" == "gitea"
jsonpath "$[1].confusio_delivery" isString
jsonpath "$[1].user_agent" contains "confusio"
jsonpath "$[1].github_event" == ""
