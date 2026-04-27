# Startup event synthesis delivery test — run by Phase 27 in test-unit.sh.
#
# Verifies that confusio synthesizes installation.created and
# installation_repositories.added at startup and delivers them to the configured
# outbound target before accepting any inbound connections.
#
# The harness TCP-waits until confusio is listening — by that point both startup
# events have already landed in the delivery target.  This file queries the log
# without resetting first, so both events are visible.
#
# Two {{variables}} are injected by the harness:
#   {{host}}   — confusio  (port 18080)
#   {{target}} — mock delivery target (port 18082, started with -u)
#
# Note: no /reset is called before the assertions.  The delivery log contains
# exactly the two events synthesized at startup.

# ── installation: created (synthesized at startup) ────────────────────────────
# ── installation_repositories: added (synthesized at startup) ─────────────────

GET http://{{target}}/deliveries

HTTP 200
[Asserts]
jsonpath "$" count == 2
jsonpath "$[0].github_event" == "installation"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
jsonpath "$[1].github_event" == "installation_repositories"
jsonpath "$[1].github_delivery" isString
jsonpath "$[1].user_agent" contains "confusio"
