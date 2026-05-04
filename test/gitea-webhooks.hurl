# Gitea webhook normalizer tests — run by Phase 5 in test-unit.sh.
#
# Exercises the five event families registered in backends/gitea.lua.
# Trust-the-network mode (no webhook_secret_BACKEND CLI arg): signature headers omitted.
# All paths return 200 when a registered handler succeeds.

# ── provider binding: other known webhook providers are absent ───────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Issue Hook
{}

HTTP 404
[Asserts]
jsonpath "$.message" == "Not Found"

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

# ── merge_group: non-native → 422 ─────────────────────────────────────────────

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

HTTP 422
[Asserts]
jsonpath "$.message" == "Unrecognised event type: merge_group"

# ── merge_group: destroyed (reason: merged) → 422 ─────────────────────────────

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

HTTP 422
[Asserts]
jsonpath "$.message" == "Unrecognised event type: merge_group"

# ── merge_group: destroyed (reason: dequeued) → 422 ──────────────────────────

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

HTTP 422
[Asserts]
jsonpath "$.message" == "Unrecognised event type: merge_group"

# ── merge_group: unknown action → 422 ─────────────────────────────────────────

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

HTTP 422
[Asserts]
jsonpath "$.message" == "Unrecognised event type: merge_group"

# ── pull_request_review: submitted (APPROVED) → 200 ──────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request_review
{
  "action": "submitted",
  "review": {
    "id": 42,
    "type": "APPROVED",
    "body": "LGTM!",
    "submitted_at": "2024-01-15T11:00:00Z",
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
    "created": "2024-01-15T10:00:00Z",
    "updated": "2024-01-15T11:00:00Z",
    "closed": null
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

# ── pull_request_review: submitted (CHANGES_REQUESTED via Gitea REJECT) → 200 ─

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request_review
{
  "action": "submitted",
  "review": {
    "id": 43,
    "type": "REJECT",
    "body": "Please fix the tests.",
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
    "created": "2024-01-15T10:00:00Z",
    "updated": "2024-01-15T12:00:00Z",
    "closed": null
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

# ── pull_request_review: edited → 200 ─────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request_review
{
  "action": "edited",
  "review": {
    "id": 42,
    "type": "APPROVED",
    "body": "LGTM! (updated)",
    "submitted_at": "2024-01-15T11:00:00Z",
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
    "created": "2024-01-15T10:00:00Z",
    "updated": "2024-01-15T11:30:00Z",
    "closed": null
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

# ── pull_request_review: dismissed → 200 ──────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: pull_request_review
{
  "action": "dismissed",
  "review": {
    "id": 42,
    "type": "DISMISSED",
    "body": "",
    "submitted_at": "2024-01-15T11:00:00Z",
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
    "created": "2024-01-15T10:00:00Z",
    "updated": "2024-01-15T13:00:00Z",
    "closed": null
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
  "action": "converted_to_draft",
  "review": {
    "id": 44,
    "type": "COMMENT",
    "body": "Looks interesting.",
    "submitted_at": "2024-01-15T14:00:00Z",
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
    "created": "2024-01-15T10:00:00Z",
    "updated": "2024-01-15T14:00:00Z",
    "closed": null
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
header "X-Confusio-Raw-Action" == "converted_to_draft"

# ── workflow_run: completed → 200 ────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: workflow_run
{
  "action": "completed",
  "workflow_run": {
    "id": 1001, "name": "CI", "head_branch": "main", "head_sha": "abc123def456",
    "run_number": 42, "event": "push", "display_title": "Update readme",
    "status": "completed", "conclusion": "success", "workflow_id": 1,
    "url": "http://localhost/octocat/hello-world/actions/runs/1001",
    "html_url": "http://localhost/octocat/hello-world/actions/runs/1001",
    "pull_requests": [], "run_attempt": 1, "referenced_workflows": [],
    "created_at": "2024-01-15T10:00:00Z", "updated_at": "2024-01-15T10:05:00Z",
    "actor": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""},
    "triggering_actor": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "workflow": {
    "id": 1, "name": "CI", "path": ".gitea/workflows/ci.yml", "state": "active",
    "url": "http://localhost/octocat/hello-world/actions/workflows/ci.yml",
    "html_url": "http://localhost/octocat/hello-world/actions/workflows/ci.yml",
    "badge_url": "", "created_at": "2024-01-01T00:00:00Z", "updated_at": "2024-01-01T00:00:00Z"
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

# ── workflow_run: requested → 200 ────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: workflow_run
{
  "action": "requested",
  "workflow_run": {
    "id": 1002, "name": "CI", "head_branch": "feature", "head_sha": "deadbeef",
    "run_number": 43, "event": "push", "display_title": "Add feature",
    "status": "queued", "conclusion": null, "workflow_id": 1,
    "url": "http://localhost/octocat/hello-world/actions/runs/1002",
    "html_url": "http://localhost/octocat/hello-world/actions/runs/1002",
    "pull_requests": [], "run_attempt": 1, "referenced_workflows": [],
    "created_at": "2024-01-15T11:00:00Z", "updated_at": "2024-01-15T11:00:00Z",
    "actor": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""},
    "triggering_actor": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""}
  },
  "workflow": {
    "id": 1, "name": "CI", "path": ".gitea/workflows/ci.yml", "state": "active",
    "url": "", "html_url": "", "badge_url": "",
    "created_at": "2024-01-01T00:00:00Z", "updated_at": "2024-01-01T00:00:00Z"
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

# ── workflow_run: unknown action → 200 + X-Confusio-Raw-Action sidecar ───────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: workflow_run
{
  "action": "cancelled",
  "workflow_run": {
    "id": 1003, "name": "CI", "head_branch": "main", "head_sha": "abc123",
    "run_number": 44, "event": "push", "display_title": "Hotfix",
    "status": "completed", "conclusion": "cancelled", "workflow_id": 1,
    "url": "", "html_url": "", "pull_requests": [], "run_attempt": 1,
    "referenced_workflows": [],
    "created_at": "2024-01-15T12:00:00Z", "updated_at": "2024-01-15T12:01:00Z",
    "actor": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""},
    "triggering_actor": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "workflow": {
    "id": 1, "name": "CI", "path": ".gitea/workflows/ci.yml", "state": "active",
    "url": "", "html_url": "", "badge_url": "",
    "created_at": "2024-01-01T00:00:00Z", "updated_at": "2024-01-01T00:00:00Z"
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
header "X-Confusio-Raw-Action" == "cancelled"

# ── workflow_job: completed → 200 ─────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: workflow_job
{
  "action": "completed",
  "workflow_job": {
    "id": 2001, "run_id": 1001, "run_attempt": 1,
    "run_url": "http://localhost/octocat/hello-world/actions/runs/1001",
    "name": "build", "head_sha": "abc123def456",
    "url": "http://localhost/octocat/hello-world/actions/runs/1001/jobs/2001",
    "html_url": "http://localhost/octocat/hello-world/actions/runs/1001/jobs/2001",
    "status": "completed", "conclusion": "success",
    "started_at": "2024-01-15T10:01:00Z", "completed_at": "2024-01-15T10:04:00Z",
    "steps": [
      {
        "name": "Set up job", "status": "completed", "conclusion": "success",
        "number": 1,
        "started_at": "2024-01-15T10:01:00Z", "completed_at": "2024-01-15T10:02:00Z"
      }
    ],
    "labels": ["ubuntu-latest"], "runner_id": 1, "runner_name": "runner-1"
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

# ── workflow_job: queued → 200 ────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: workflow_job
{
  "action": "queued",
  "workflow_job": {
    "id": 2002, "run_id": 1002, "run_attempt": 1,
    "run_url": "http://localhost/octocat/hello-world/actions/runs/1002",
    "name": "test", "head_sha": "deadbeef",
    "url": "", "html_url": "",
    "status": "queued", "conclusion": null,
    "started_at": null, "completed_at": null,
    "steps": [], "labels": [], "runner_id": null, "runner_name": ""
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

# ── workflow_job: unknown action → 200 + X-Confusio-Raw-Action sidecar ────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: workflow_job
{
  "action": "skipped",
  "workflow_job": {
    "id": 2003, "run_id": 1003, "run_attempt": 1,
    "run_url": "", "name": "lint", "head_sha": "abc123",
    "url": "", "html_url": "",
    "status": "completed", "conclusion": "skipped",
    "started_at": null, "completed_at": null,
    "steps": [], "labels": [], "runner_id": null, "runner_name": ""
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
header "X-Confusio-Raw-Action" == "skipped"

# ── status: success → 200 ─────────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: status
{
  "id": 501,
  "sha": "abc123def456abc123def456abc123def456abc123",
  "state": "success",
  "target_url": "https://ci.example.com/builds/99",
  "context": "ci/build",
  "description": "Build passed",
  "branches": [
    {
      "name": "main",
      "commit": {"id": "abc123def456abc123def456abc123def456abc123", "url": ""},
      "protected": false
    }
  ],
  "commit": {"id": "abc123def456abc123def456abc123def456abc123", "message": "Update readme"},
  "created_at": "2024-01-15T10:05:00Z",
  "updated_at": "2024-01-15T10:05:00Z",
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

# ── status: pending → 200 ─────────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: status
{
  "id": 502,
  "sha": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
  "state": "pending",
  "target_url": null,
  "context": "ci/test",
  "description": "Running tests...",
  "branches": [
    {
      "name": "feature",
      "commit": {"id": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef", "url": ""},
      "protected": false
    }
  ],
  "commit": {"id": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef", "message": "Add feature"},
  "created_at": "2024-01-15T11:00:00Z",
  "updated_at": "2024-01-15T11:00:00Z",
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

# ── status: failure → 200 ─────────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: status
{
  "id": 503,
  "sha": "cafebabecafebabecafebabecafebabecafebabe",
  "state": "failure",
  "target_url": "https://ci.example.com/builds/101",
  "context": "ci/build",
  "description": "Build failed",
  "branches": [],
  "commit": null,
  "created_at": "2024-01-15T12:00:00Z",
  "updated_at": "2024-01-15T12:01:00Z",
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

# ── status: error → 200 ───────────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: status
{
  "id": 504,
  "sha": "feedfacefeedfacefeedfacefeedfacefeedface",
  "state": "error",
  "target_url": "https://ci.example.com/builds/102",
  "context": "ci/build",
  "description": "Build errored",
  "branches": [],
  "commit": null,
  "created_at": "2024-01-15T12:00:00Z",
  "updated_at": "2024-01-15T12:01:00Z",
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

# ── push: branch push with commits → 200 ─────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: push
{
  "ref": "refs/heads/main",
  "before": "abc123def456abc123def456abc123def456abc1",
  "after":  "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
  "created": false,
  "deleted": false,
  "forced":  false,
  "compare_url": "http://localhost/octocat/hello-world/compare/abc123...deadbeef",
  "commits": [
    {
      "id": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
      "message": "Fix bug",
      "timestamp": "2024-01-15T10:00:00Z",
      "url": "http://localhost/octocat/hello-world/commit/deadbeef",
      "author":    {"name": "Alice", "email": "alice@example.com", "username": "alice"},
      "committer": {"name": "Alice", "email": "alice@example.com", "username": "alice"},
      "added": [], "removed": [], "modified": ["README.md"]
    }
  ],
  "head_commit": {
    "id": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
    "message": "Fix bug",
    "timestamp": "2024-01-15T10:00:00Z",
    "url": "http://localhost/octocat/hello-world/commit/deadbeef",
    "author":    {"name": "Alice", "email": "alice@example.com", "username": "alice"},
    "committer": {"name": "Alice", "email": "alice@example.com", "username": "alice"},
    "added": [], "removed": [], "modified": ["README.md"]
  },
  "pusher": {"id": 1, "login": "alice", "email": "alice@example.com", "avatar_url": "", "html_url": ""},
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

# ── push: branch deletion (after = zero SHA, deleted = true) → 200 ───────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: push
{
  "ref": "refs/heads/stale-branch",
  "before": "abc123def456abc123def456abc123def456abc1",
  "after":  "0000000000000000000000000000000000000000",
  "created": false,
  "deleted": true,
  "forced":  false,
  "compare_url": "",
  "commits": [],
  "head_commit": null,
  "pusher": {"id": 1, "login": "alice", "email": "alice@example.com", "avatar_url": "", "html_url": ""},
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

# ── push: force push (forced = true) → 200 ────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: push
{
  "ref": "refs/heads/main",
  "before": "abc123def456abc123def456abc123def456abc1",
  "after":  "cafebabecafebabecafebabecafebabecafebabe",
  "created": false,
  "deleted": false,
  "forced":  true,
  "compare_url": "http://localhost/octocat/hello-world/compare/abc123...cafebabe",
  "commits": [
    {
      "id": "cafebabecafebabecafebabecafebabecafebabe",
      "message": "Amend: reword commit",
      "timestamp": "2024-01-15T11:00:00Z",
      "url": "http://localhost/octocat/hello-world/commit/cafebabe",
      "author":    {"name": "Bob", "email": "bob@example.com", "username": "bob"},
      "committer": {"name": "Bob", "email": "bob@example.com", "username": "bob"},
      "added": [], "removed": [], "modified": []
    }
  ],
  "head_commit": {
    "id": "cafebabecafebabecafebabecafebabecafebabe",
    "message": "Amend: reword commit",
    "timestamp": "2024-01-15T11:00:00Z",
    "url": "http://localhost/octocat/hello-world/commit/cafebabe",
    "author":    {"name": "Bob", "email": "bob@example.com", "username": "bob"},
    "committer": {"name": "Bob", "email": "bob@example.com", "username": "bob"},
    "added": [], "removed": [], "modified": []
  },
  "pusher": {"id": 2, "login": "bob", "email": "bob@example.com", "avatar_url": "", "html_url": ""},
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

# ── push: tag push (ref = refs/tags/…, created = true) → 200 ─────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: push
{
  "ref": "refs/tags/v1.0.0",
  "before": "0000000000000000000000000000000000000000",
  "after":  "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
  "created": true,
  "deleted": false,
  "forced":  false,
  "compare_url": "",
  "commits": [],
  "head_commit": {
    "id": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
    "message": "Release v1.0.0",
    "timestamp": "2024-01-15T12:00:00Z",
    "url": "http://localhost/octocat/hello-world/commit/deadbeef",
    "author":    {"name": "Alice", "email": "alice@example.com", "username": "alice"},
    "committer": {"name": "Alice", "email": "alice@example.com", "username": "alice"},
    "added": [], "removed": [], "modified": []
  },
  "pusher": {"id": 1, "login": "alice", "email": "alice@example.com", "avatar_url": "", "html_url": ""},
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

# ── create: branch created → 200 ─────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: create
{
  "ref": "feature-branch",
  "ref_type": "branch",
  "sha": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "description": "A friendly repo",
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "sender": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── create: tag created → 200 ────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: create
{
  "ref": "v2.0.0",
  "ref_type": "tag",
  "sha": "cafebabecafebabecafebabecafebabecafebabe",
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "description": null,
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "sender": {"id": 1, "login": "alice", "avatar_url": "", "html_url": ""}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── delete: branch deleted → 200 ─────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: delete
{
  "ref": "stale-branch",
  "ref_type": "branch",
  "sha": "abc123def456abc123def456abc123def456abc1",
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "description": "A friendly repo",
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "sender": {"id": 1, "login": "alice", "avatar_url": "", "html_url": ""}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── delete: tag deleted → 200 ────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: delete
{
  "ref": "v0.9.0",
  "ref_type": "tag",
  "sha": "abc123def456abc123def456abc123def456abc1",
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "description": null,
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "sender": {"id": 1, "login": "alice", "avatar_url": "", "html_url": ""}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── fork: repository forked → 200 ────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: fork
{
  "forkee": {
    "id": 200,
    "name": "hello-world",
    "full_name": "bob/hello-world",
    "private": false,
    "html_url": "http://localhost/bob/hello-world",
    "description": "Fork of octocat/hello-world",
    "fork": true,
    "default_branch": "main",
    "owner": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""}
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

# ── security_and_analysis: non-native → 422 ──────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: security_and_analysis
{
  "changes": {
    "from": {
      "security_and_analysis": {
        "advanced_security": {"status": "disabled"}
      }
    }
  },
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""},
    "security_and_analysis": {"advanced_security": {"status": "enabled"}}
  },
  "sender": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
}

HTTP 422
[Asserts]
jsonpath "$.message" == "Unrecognised event type: security_and_analysis"

# ── star: created → 422 ───────────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: star
{
  "action": "created",
  "starred_at": "2024-01-15T10:00:00Z",
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "sender": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""}
}

HTTP 422
[Asserts]
jsonpath "$.message" == "Unrecognised event type: star"

# ── star: deleted → 422 ───────────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: star
{
  "action": "deleted",
  "starred_at": null,
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "sender": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""}
}

HTTP 422
[Asserts]
jsonpath "$.message" == "Unrecognised event type: star"

# ── star: unknown action → 422 ────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: star
{
  "action": "bookmarked",
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "sender": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""}
}

HTTP 422
[Asserts]
jsonpath "$.message" == "Unrecognised event type: star"

# ── watch: started → 422 ──────────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: watch
{
  "action": "started",
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "sender": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""}
}

HTTP 422
[Asserts]
jsonpath "$.message" == "Unrecognised event type: watch"

# ── watch: unknown action → 422 ───────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: watch
{
  "action": "stopped",
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "sender": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""}
}

HTTP 422
[Asserts]
jsonpath "$.message" == "Unrecognised event type: watch"

# ── discussion: created → 422 ────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: discussion
{
  "action": "created",
  "discussion": {
    "id": 1, "number": 1, "title": "How do I configure X?",
    "body": "I'm trying to configure X but can't figure it out.",
    "state": "open", "html_url": "http://localhost/octocat/hello-world/issues/1",
    "locked": false, "comments": 0,
    "user": {"id": 1, "login": "alice", "avatar_url": "", "html_url": ""},
    "labels": [],
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

HTTP 422
[Asserts]
jsonpath "$.message" == "Unrecognised event type: discussion"

# ── discussion: labeled → 422 ─────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: discussion
{
  "action": "labeled",
  "discussion": {
    "id": 1, "number": 1, "title": "How do I configure X?", "body": null,
    "state": "open", "html_url": "http://localhost/octocat/hello-world/issues/1",
    "locked": false, "comments": 0,
    "user": {"id": 1, "login": "alice", "avatar_url": "", "html_url": ""},
    "labels": [{"id": 5, "name": "question", "color": "#d876e3", "url": ""}],
    "created": "2024-01-15T10:00:00Z", "updated": "2024-01-15T10:01:00Z", "closed": null
  },
  "label": {"id": 5, "name": "question", "color": "#d876e3", "url": ""},
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "sender": {"id": 1, "login": "alice", "avatar_url": "", "html_url": ""}
}

HTTP 422
[Asserts]
jsonpath "$.message" == "Unrecognised event type: discussion"

# ── discussion: unknown action → 422 ──────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: discussion
{
  "action": "pinned",
  "discussion": {
    "id": 1, "number": 1, "title": "How do I configure X?", "body": null,
    "state": "open", "html_url": "http://localhost/octocat/hello-world/issues/1",
    "locked": false, "comments": 0,
    "user": {"id": 1, "login": "alice", "avatar_url": "", "html_url": ""},
    "labels": [],
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

HTTP 422
[Asserts]
jsonpath "$.message" == "Unrecognised event type: discussion"

# ── discussion_comment: created → 422 ─────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: discussion_comment
{
  "action": "created",
  "discussion": {
    "id": 1, "number": 1, "title": "How do I configure X?",
    "body": "I'm trying to configure X but can't figure it out.",
    "state": "open", "html_url": "http://localhost/octocat/hello-world/issues/1",
    "locked": false, "comments": 1,
    "user": {"id": 1, "login": "alice", "avatar_url": "", "html_url": ""},
    "labels": [],
    "created": "2024-01-15T10:00:00Z", "updated": "2024-01-15T10:05:00Z", "closed": null
  },
  "comment": {
    "id": 42, "discussion_id": 1,
    "body": "Try setting the X option in the config.",
    "html_url": "http://localhost/octocat/hello-world/issues/1#issuecomment-42",
    "user": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""},
    "created": "2024-01-15T10:05:00Z", "updated": "2024-01-15T10:05:00Z"
  },
  "repository": {
    "id": 100, "name": "hello-world", "full_name": "octocat/hello-world",
    "private": false, "html_url": "http://localhost/octocat/hello-world",
    "fork": false, "default_branch": "main",
    "owner": {"id": 1, "login": "octocat", "avatar_url": "", "html_url": ""}
  },
  "sender": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""}
}

HTTP 422
[Asserts]
jsonpath "$.message" == "Unrecognised event type: discussion_comment"

# ── ping: non-native → 422 ────────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: ping
file,fixtures/webhooks/gitea/ping.json;

HTTP 422
[Asserts]
jsonpath "$.message" == "Unrecognised event type: ping"
