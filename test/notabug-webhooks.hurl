# NotABug webhook normalizer tests — run by test-unit-notabug.
#
# NotABug runs Gogs and shares the Gitea backend implementation while registering only native
# Gogs webhook event families. These smoke tests cover the inline native
# events that existed before the fixture-backed delivery tests.
# Trust-the-network mode (no webhook_secret_BACKEND CLI arg): signature headers omitted.
# All paths return 200 when a registered handler succeeds.

# ── issues: known action → 200 ───────────────────────────────────────────────

POST http://{{host}}/webhooks/notabug
Content-Type: application/json
X-Gogs-Event: issues
{
  "action": "opened",
  "issue": {
    "id": 1,
    "number": 1,
    "title": "Bug report",
    "body": "Something is broken",
    "state": "open",
    "html_url": "http://localhost/octocat/hello-world/issues/1",
    "user": {"id": 1, "login": "alice", "avatar_url": "", "html_url": ""},
    "labels": [],
    "assignees": [],
    "milestone": null,
    "created": "2024-01-15T10:00:00Z",
    "updated": "2024-01-15T10:00:00Z",
    "closed": null
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

# ── issues: label_updated → labeled (action normalisation) ───────────────────

POST http://{{host}}/webhooks/notabug
Content-Type: application/json
X-Gogs-Event: issues
{
  "action": "label_updated",
  "issue": {
    "id": 1, "number": 1, "title": "Bug report", "body": null,
    "state": "open", "html_url": "http://localhost/octocat/hello-world/issues/1",
    "user": {"id": 1, "login": "alice", "avatar_url": "", "html_url": ""},
    "labels": [{"id": 5, "name": "bug", "color": "#d73a4a", "url": ""}],
    "assignees": [], "milestone": null,
    "created": "2024-01-15T10:00:00Z", "updated": "2024-01-15T10:00:01Z", "closed": null
  },
  "label": {"id": 5, "name": "bug", "color": "#d73a4a", "url": ""},
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

# ── issues: unknown action → 200 + X-Confusio-Raw-Action sidecar header ──────

POST http://{{host}}/webhooks/notabug
Content-Type: application/json
X-Gogs-Event: issues
{
  "action": "milestone_changed",
  "issue": {
    "id": 1, "number": 1, "title": "Bug", "body": null, "state": "open",
    "html_url": "http://localhost/octocat/hello-world/issues/1",
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
header "X-Confusio-Raw-Action" == "milestone_changed"

# ── issue_comment: created → 200 ─────────────────────────────────────────────

POST http://{{host}}/webhooks/notabug
Content-Type: application/json
X-Gogs-Event: issue_comment
{
  "action": "created",
  "issue": {
    "id": 1, "number": 1, "title": "Bug report", "body": "Something broke",
    "state": "open", "html_url": "http://localhost/octocat/hello-world/issues/1",
    "user": {"id": 1, "login": "alice", "avatar_url": "", "html_url": ""},
    "labels": [], "assignees": [], "milestone": null,
    "created": "2024-01-15T10:00:00Z", "updated": "2024-01-15T10:00:00Z", "closed": null
  },
  "comment": {
    "id": 42,
    "body": "Confirmed, I can reproduce this.",
    "html_url": "http://localhost/octocat/hello-world/issues/1#issuecomment-42",
    "user": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""},
    "created": "2024-01-15T11:00:00Z",
    "updated": "2024-01-15T11:00:00Z"
  },
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "sender": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pull_request: opened → 200 ────────────────────────────────────────────────

POST http://{{host}}/webhooks/notabug
Content-Type: application/json
X-Gogs-Event: pull_request
{
  "action": "opened",
  "number": 7,
  "pull_request": {
    "id": 500,
    "number": 7,
    "title": "Add new feature",
    "body": "This PR adds a new feature.",
    "state": "open",
    "draft": false,
    "html_url": "http://localhost/octocat/hello-world/pulls/7",
    "url": "http://localhost/api/v1/repos/octocat/hello-world/pulls/7",
    "user": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""},
    "head": {
      "ref": "feature-branch",
      "sha": "abc123",
      "repo": {
        "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
        "private": false, "html_url": "http://localhost/octocat/hello-world",
        "fork": false, "default_branch": "main",
        "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
      }
    },
    "base": {
      "ref": "main",
      "sha": "def456",
      "repo": {
        "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
        "private": false, "html_url": "http://localhost/octocat/hello-world",
        "fork": false, "default_branch": "main",
        "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
      }
    },
    "labels": [],
    "assignees": [],
    "requested_reviewers": [],
    "merged": false,
    "merged_at": null,
    "merge_commit_sha": null,
    "merged_by": null,
    "created": "2024-01-15T10:00:00Z",
    "updated": "2024-01-15T10:00:00Z",
    "closed": null
  },
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "sender": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pull_request: synchronize → 200 (commit pushed to PR branch) ─────────────

POST http://{{host}}/webhooks/notabug
Content-Type: application/json
X-Gogs-Event: pull_request
{
  "action": "synchronize",
  "number": 7,
  "pull_request": {
    "id": 500, "number": 7, "title": "Add new feature", "body": "This PR adds a new feature.",
    "state": "open", "draft": false,
    "html_url": "http://localhost/octocat/hello-world/pulls/7",
    "url": "http://localhost/api/v1/repos/octocat/hello-world/pulls/7",
    "user": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""},
    "head": {"ref": "feature-branch", "sha": "ghi789", "repo": null},
    "base": {"ref": "main", "sha": "def456", "repo": null},
    "labels": [], "assignees": [], "requested_reviewers": [],
    "merged": false, "merged_at": null, "merge_commit_sha": null, "merged_by": null,
    "created": "2024-01-15T10:00:00Z",
    "updated": "2024-01-15T10:05:00Z",
    "closed": null
  },
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "sender": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pull_request: closed (merged) → 200 ──────────────────────────────────────

POST http://{{host}}/webhooks/notabug
Content-Type: application/json
X-Gogs-Event: pull_request
{
  "action": "closed",
  "number": 7,
  "pull_request": {
    "id": 500, "number": 7, "title": "Add new feature", "body": "This PR adds a new feature.",
    "state": "closed", "draft": false,
    "html_url": "http://localhost/octocat/hello-world/pulls/7",
    "url": "http://localhost/api/v1/repos/octocat/hello-world/pulls/7",
    "user": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""},
    "head": {"ref": "feature-branch", "sha": "ghi789", "repo": null},
    "base": {"ref": "main", "sha": "def456", "repo": null},
    "labels": [], "assignees": [], "requested_reviewers": [],
    "merged": true,
    "merged_at": "2024-01-16T09:00:00Z",
    "merge_commit_sha": "jkl012",
    "merged_by": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""},
    "created": "2024-01-15T10:00:00Z",
    "updated": "2024-01-16T09:00:00Z",
    "closed": "2024-01-16T09:00:00Z"
  },
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "sender": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pull_request: labeled → 200 (with label field in data) ───────────────────

POST http://{{host}}/webhooks/notabug
Content-Type: application/json
X-Gogs-Event: pull_request
{
  "action": "labeled",
  "number": 7,
  "pull_request": {
    "id": 500, "number": 7, "title": "Add new feature", "body": null,
    "state": "open", "draft": false,
    "html_url": "http://localhost/octocat/hello-world/pulls/7",
    "url": "",
    "user": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""},
    "head": {"ref": "feature-branch", "sha": "ghi789", "repo": null},
    "base": {"ref": "main", "sha": "def456", "repo": null},
    "labels": [{"id": 5, "name": "bug", "color": "#d73a4a", "url": ""}],
    "assignees": [], "requested_reviewers": [],
    "merged": false, "merged_at": null, "merge_commit_sha": null, "merged_by": null,
    "created": "2024-01-15T10:00:00Z",
    "updated": "2024-01-15T10:02:00Z",
    "closed": null
  },
  "label": {"id": 5, "name": "bug", "color": "#d73a4a", "url": ""},
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "sender": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pull_request: review_requested → 200 (with requested_reviewer) ───────────

POST http://{{host}}/webhooks/notabug
Content-Type: application/json
X-Gogs-Event: pull_request
{
  "action": "review_requested",
  "number": 7,
  "pull_request": {
    "id": 500, "number": 7, "title": "Add new feature", "body": null,
    "state": "open", "draft": false,
    "html_url": "http://localhost/octocat/hello-world/pulls/7",
    "url": "",
    "user": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""},
    "head": {"ref": "feature-branch", "sha": "ghi789", "repo": null},
    "base": {"ref": "main", "sha": "def456", "repo": null},
    "labels": [], "assignees": [],
    "requested_reviewers": [{"id": 3, "login": "carol", "avatar_url": "", "html_url": ""}],
    "merged": false, "merged_at": null, "merge_commit_sha": null, "merged_by": null,
    "created": "2024-01-15T10:00:00Z",
    "updated": "2024-01-15T10:03:00Z",
    "closed": null
  },
  "requested_reviewer": {"id": 3, "login": "carol", "avatar_url": "", "html_url": ""},
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "sender": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pull_request: unknown action → 200 + X-Confusio-Raw-Action sidecar ───────

POST http://{{host}}/webhooks/notabug
Content-Type: application/json
X-Gogs-Event: pull_request
{
  "action": "auto_merged",
  "number": 7,
  "pull_request": {
    "id": 500, "number": 7, "title": "Add new feature", "body": null,
    "state": "closed", "draft": false,
    "html_url": "http://localhost/octocat/hello-world/pulls/7",
    "url": "",
    "user": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""},
    "head": {"ref": "feature-branch", "sha": "ghi789", "repo": null},
    "base": {"ref": "main", "sha": "def456", "repo": null},
    "labels": [], "assignees": [], "requested_reviewers": [],
    "merged": false, "merged_at": null, "merge_commit_sha": null, "merged_by": null,
    "created": "2024-01-15T10:00:00Z",
    "updated": "2024-01-15T10:00:00Z",
    "closed": null
  },
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "sender": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"
header "X-Confusio-Raw-Action" == "auto_merged"
