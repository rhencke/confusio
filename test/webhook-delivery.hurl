# Outbound webhook delivery end-to-end test — run by Phase 6 in test-unit.sh.
#
# Verifies that confusio receives an inbound webhook event, normalises it, and
# forwards it synchronously to the configured outbound delivery target.
#
# Two {{variables}} are injected by the harness:
#   {{host}}   — confusio  (port 18080)
#   {{target}} — mock delivery target (port 18082, started with -u)
#
# Flow:
#   1. Reset the delivery target log (fresh state)
#   2. POST a Gitea issues event to confusio → expect 200
#   3. Query the delivery target → expect exactly one forwarded delivery

# ── reset: clear the delivery log ─────────────────────────────────────────────

POST http://{{target}}/reset
{}

HTTP 200

# ── send an inbound Gitea issues event to confusio ────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: issues
{
  "action": "opened",
  "issue": {
    "id": 1, "number": 1, "title": "Test issue", "body": null,
    "state": "open", "html_url": "http://localhost/octocat/hello-world/issues/1",
    "user": {"id": 1, "login": "alice", "avatar_url": "", "html_url": ""},
    "labels": [], "assignees": [], "milestone": null,
    "created": "2024-01-15T10:00:00Z", "updated": "2024-01-15T10:00:00Z", "closed": null
  },
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "sender": {"id": 1, "login": "alice", "avatar_url": "", "html_url": ""}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── verify the delivery target recorded exactly one forwarded delivery ─────────

GET http://{{target}}/deliveries

HTTP 200
[Asserts]
jsonpath "$" count == 1
jsonpath "$[0].github_event" == "issues"
jsonpath "$[0].github_delivery" isString
jsonpath "$[0].user_agent" contains "confusio"
