# Gitea webhook normalizer tests — run by Phase 5 in test-unit.sh.
#
# Exercises the five event families registered in backends/gitea.lua.
# Trust-the-network mode (no CONFUSIO_WEBHOOK_SECRETS): signature headers omitted.
# All paths return 200 when a registered handler succeeds.

# ── issues: known action → 200 ───────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: issues
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

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: issues
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

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: issues
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

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: issue_comment
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

# ── label: created → 200 ─────────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: label
{
  "action": "created",
  "label": {
    "id": 5,
    "name": "enhancement",
    "color": "#a2eeef",
    "description": "New feature or request",
    "url": "http://localhost/octocat/hello-world/labels/5"
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

# ── label: edited → 200 (with changes) ───────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: label
{
  "action": "edited",
  "label": {
    "id": 5, "name": "enhancement", "color": "#0075ca",
    "description": "New feature or request",
    "url": "http://localhost/octocat/hello-world/labels/5"
  },
  "changes": {"color": {"from": "#a2eeef"}},
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

# ── milestone: created → 200 ──────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: milestone
{
  "action": "created",
  "milestone": {
    "id": 3,
    "title": "v2.0",
    "description": "Version 2 release",
    "state": "open",
    "open_issues": 0,
    "closed_issues": 0,
    "due_on": "2024-06-01T00:00:00Z",
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T10:00:00Z",
    "closed_at": null
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

# ── milestone: deleted → 200 ──────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: milestone
{
  "action": "deleted",
  "milestone": {
    "id": 3, "title": "v2.0", "description": null, "state": "open",
    "open_issues": 0, "closed_issues": 0, "due_on": null,
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T10:00:00Z",
    "closed_at": null
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

# ── pull_request: opened → 200 ────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request
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

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request
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

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request
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

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request
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

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request
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

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request
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

# ── merge_group: checks_requested → 200 ───────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: merge_group
{
  "action": "checks_requested",
  "merge_group": {
    "head_sha": "abc123def456abc123def456abc123def456abc1",
    "head_ref": "refs/heads/gh-readonly-queue/main/pr-7-abc123",
    "base_sha": "def456abc123def456abc123def456abc123def4",
    "base_ref": "refs/heads/main",
    "head_commit": {
      "id": "abc123def456abc123def456abc123def456abc1",
      "tree_id": "1234567890abcdef1234567890abcdef12345678",
      "message": "Add new feature (#7)",
      "timestamp": "2024-01-15T10:00:00Z",
      "author": {"name": "Bob", "email": "bob@example.com"},
      "committer": {"name": "GitHub", "email": "noreply@github.com"}
    }
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

# ── merge_group: destroyed (reason: merged) → 200 ─────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: merge_group
{
  "action": "destroyed",
  "reason": "merged",
  "merge_group": {
    "head_sha": "abc123def456abc123def456abc123def456abc1",
    "head_ref": "refs/heads/gh-readonly-queue/main/pr-7-abc123",
    "base_sha": "def456abc123def456abc123def456abc123def4",
    "base_ref": "refs/heads/main",
    "head_commit": {
      "id": "abc123def456abc123def456abc123def456abc1",
      "tree_id": "1234567890abcdef1234567890abcdef12345678",
      "message": "Add new feature (#7)",
      "timestamp": "2024-01-15T10:00:00Z",
      "author": {"name": "Bob", "email": "bob@example.com"},
      "committer": {"name": "GitHub", "email": "noreply@github.com"}
    }
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

# ── merge_group: destroyed (reason: dequeued) → 200 ──────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: merge_group
{
  "action": "destroyed",
  "reason": "dequeued",
  "merge_group": {
    "head_sha": "abc123def456abc123def456abc123def456abc1",
    "head_ref": "refs/heads/gh-readonly-queue/main/pr-7-abc123",
    "base_sha": "def456abc123def456abc123def456abc123def4",
    "base_ref": "refs/heads/main",
    "head_commit": {
      "id": "abc123def456abc123def456abc123def456abc1",
      "tree_id": "1234567890abcdef1234567890abcdef12345678",
      "message": "Add new feature (#7)",
      "timestamp": "2024-01-15T10:00:00Z",
      "author": {"name": "Bob", "email": "bob@example.com"},
      "committer": {"name": "GitHub", "email": "noreply@github.com"}
    }
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

# ── merge_group: unknown action → 200 + X-Confusio-Raw-Action sidecar ─────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: merge_group
{
  "action": "queued",
  "merge_group": {
    "head_sha": "abc123def456abc123def456abc123def456abc1",
    "head_ref": "refs/heads/gh-readonly-queue/main/pr-7-abc123",
    "base_sha": "def456abc123def456abc123def456abc123def4",
    "base_ref": "refs/heads/main",
    "head_commit": {
      "id": "abc123def456abc123def456abc123def456abc1",
      "tree_id": "1234567890abcdef1234567890abcdef12345678",
      "message": "Add new feature (#7)",
      "timestamp": "2024-01-15T10:00:00Z",
      "author": {"name": "Bob", "email": "bob@example.com"},
      "committer": {"name": "GitHub", "email": "noreply@github.com"}
    }
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
header "X-Confusio-Raw-Action" == "queued"

# ── pull_request_review: submitted (APPROVED) → 200 ──────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request_review
{
  "action": "submitted",
  "review": {
    "id": 10,
    "type": "APPROVED",
    "state": "APPROVED",
    "body": "LGTM!",
    "submitted_at": "2024-01-15T12:00:00Z",
    "user": {"id": 3, "login": "carol", "avatar_url": "", "html_url": ""}
  },
  "pull_request": {
    "id": 500, "number": 7, "title": "Add new feature", "body": null,
    "state": "open", "draft": false,
    "html_url": "http://localhost/octocat/hello-world/pulls/7",
    "url": "",
    "user": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""},
    "head": {"ref": "feature-branch", "sha": "abc123", "repo": null},
    "base": {"ref": "main", "sha": "def456", "repo": null},
    "labels": [], "assignees": [], "requested_reviewers": [],
    "merged": false, "merged_at": null, "merge_commit_sha": null, "merged_by": null,
    "created": "2024-01-15T10:00:00Z", "updated": "2024-01-15T10:00:00Z", "closed": null
  },
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "sender": {"id": 3, "login": "carol", "avatar_url": "", "html_url": ""}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pull_request_review: submitted (REQUEST_CHANGES) → 200 (state normalised) ─

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request_review
{
  "action": "submitted",
  "review": {
    "id": 11,
    "type": "REQUEST_CHANGES",
    "state": "REQUEST_CHANGES",
    "body": "Please address these issues.",
    "submitted_at": "2024-01-15T12:01:00Z",
    "user": {"id": 3, "login": "carol", "avatar_url": "", "html_url": ""}
  },
  "pull_request": {
    "id": 500, "number": 7, "title": "Add new feature", "body": null,
    "state": "open", "draft": false,
    "html_url": "http://localhost/octocat/hello-world/pulls/7",
    "url": "",
    "user": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""},
    "head": {"ref": "feature-branch", "sha": "abc123", "repo": null},
    "base": {"ref": "main", "sha": "def456", "repo": null},
    "labels": [], "assignees": [], "requested_reviewers": [],
    "merged": false, "merged_at": null, "merge_commit_sha": null, "merged_by": null,
    "created": "2024-01-15T10:00:00Z", "updated": "2024-01-15T10:00:00Z", "closed": null
  },
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "sender": {"id": 3, "login": "carol", "avatar_url": "", "html_url": ""}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pull_request_review: dismissed → 200 ─────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request_review
{
  "action": "dismissed",
  "review": {
    "id": 10,
    "type": "DISMISSED",
    "state": "DISMISSED",
    "body": "",
    "submitted_at": "2024-01-15T12:05:00Z",
    "user": {"id": 3, "login": "carol", "avatar_url": "", "html_url": ""}
  },
  "pull_request": {
    "id": 500, "number": 7, "title": "Add new feature", "body": null,
    "state": "open", "draft": false,
    "html_url": "http://localhost/octocat/hello-world/pulls/7",
    "url": "",
    "user": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""},
    "head": {"ref": "feature-branch", "sha": "abc123", "repo": null},
    "base": {"ref": "main", "sha": "def456", "repo": null},
    "labels": [], "assignees": [], "requested_reviewers": [],
    "merged": false, "merged_at": null, "merge_commit_sha": null, "merged_by": null,
    "created": "2024-01-15T10:00:00Z", "updated": "2024-01-15T10:00:00Z", "closed": null
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

# ── pull_request_review: unknown action → 200 + X-Confusio-Raw-Action sidecar ─

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request_review
{
  "action": "pending",
  "review": {
    "id": 12, "type": "COMMENT", "state": "COMMENT", "body": "",
    "submitted_at": "2024-01-15T12:06:00Z",
    "user": {"id": 3, "login": "carol", "avatar_url": "", "html_url": ""}
  },
  "pull_request": {
    "id": 500, "number": 7, "title": "Add new feature", "body": null,
    "state": "open", "draft": false,
    "html_url": "http://localhost/octocat/hello-world/pulls/7",
    "url": "",
    "user": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""},
    "head": {"ref": "feature-branch", "sha": "abc123", "repo": null},
    "base": {"ref": "main", "sha": "def456", "repo": null},
    "labels": [], "assignees": [], "requested_reviewers": [],
    "merged": false, "merged_at": null, "merge_commit_sha": null, "merged_by": null,
    "created": "2024-01-15T10:00:00Z", "updated": "2024-01-15T10:00:00Z", "closed": null
  },
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "sender": {"id": 3, "login": "carol", "avatar_url": "", "html_url": ""}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"
header "X-Confusio-Raw-Action" == "pending"

# ── pull_request_review_comment: created → 200 ───────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request_review_comment
{
  "action": "created",
  "comment": {
    "id": 50,
    "body": "Nice change here.",
    "path": "README.md",
    "diff_hunk": "@@ -1,3 +1,4 @@\n context\n+new line\n context",
    "line": 2,
    "original_line": 2,
    "commit_id": "abc123abc123",
    "original_commit_id": "abc123abc123",
    "user": {"id": 3, "login": "carol", "avatar_url": "", "html_url": ""},
    "created_at": "2024-01-15T12:10:00Z",
    "updated_at": "2024-01-15T12:10:00Z"
  },
  "pull_request": {
    "id": 500, "number": 7, "title": "Add new feature", "body": null,
    "state": "open", "draft": false,
    "html_url": "http://localhost/octocat/hello-world/pulls/7",
    "url": "",
    "user": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""},
    "head": {"ref": "feature-branch", "sha": "abc123", "repo": null},
    "base": {"ref": "main", "sha": "def456", "repo": null},
    "labels": [], "assignees": [], "requested_reviewers": [],
    "merged": false, "merged_at": null, "merge_commit_sha": null, "merged_by": null,
    "created": "2024-01-15T10:00:00Z", "updated": "2024-01-15T10:00:00Z", "closed": null
  },
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "sender": {"id": 3, "login": "carol", "avatar_url": "", "html_url": ""}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pull_request_review_comment: deleted → 200 ───────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request_review_comment
{
  "action": "deleted",
  "comment": {
    "id": 50, "body": "Nice change here.", "path": "README.md",
    "diff_hunk": "@@ -1,3 +1,4 @@", "line": 2, "original_line": 2,
    "commit_id": "abc123abc123", "original_commit_id": "abc123abc123",
    "user": {"id": 3, "login": "carol", "avatar_url": "", "html_url": ""},
    "created_at": "2024-01-15T12:10:00Z", "updated_at": "2024-01-15T12:11:00Z"
  },
  "pull_request": {
    "id": 500, "number": 7, "title": "Add new feature", "body": null,
    "state": "open", "draft": false,
    "html_url": "http://localhost/octocat/hello-world/pulls/7",
    "url": "",
    "user": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""},
    "head": {"ref": "feature-branch", "sha": "abc123", "repo": null},
    "base": {"ref": "main", "sha": "def456", "repo": null},
    "labels": [], "assignees": [], "requested_reviewers": [],
    "merged": false, "merged_at": null, "merge_commit_sha": null, "merged_by": null,
    "created": "2024-01-15T10:00:00Z", "updated": "2024-01-15T10:00:00Z", "closed": null
  },
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "sender": {"id": 3, "login": "carol", "avatar_url": "", "html_url": ""}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pull_request_review_comment: unknown action → 200 + X-Confusio-Raw-Action ─

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request_review_comment
{
  "action": "resolved",
  "comment": {
    "id": 50, "body": "Resolved.", "path": "README.md",
    "diff_hunk": "@@ -1,3 +1,4 @@", "line": 2, "original_line": 2,
    "commit_id": "abc123abc123", "original_commit_id": "abc123abc123",
    "user": {"id": 3, "login": "carol", "avatar_url": "", "html_url": ""},
    "created_at": "2024-01-15T12:10:00Z", "updated_at": "2024-01-15T12:12:00Z"
  },
  "pull_request": {
    "id": 500, "number": 7, "title": "Add new feature", "body": null,
    "state": "open", "draft": false,
    "html_url": "http://localhost/octocat/hello-world/pulls/7",
    "url": "",
    "user": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""},
    "head": {"ref": "feature-branch", "sha": "abc123", "repo": null},
    "base": {"ref": "main", "sha": "def456", "repo": null},
    "labels": [], "assignees": [], "requested_reviewers": [],
    "merged": false, "merged_at": null, "merge_commit_sha": null, "merged_by": null,
    "created": "2024-01-15T10:00:00Z", "updated": "2024-01-15T10:00:00Z", "closed": null
  },
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "sender": {"id": 3, "login": "carol", "avatar_url": "", "html_url": ""}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"
header "X-Confusio-Raw-Action" == "resolved"
