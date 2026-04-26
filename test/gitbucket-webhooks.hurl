# GitBucket webhook normalizer tests — run by test-unit-gitbucket.
#
# GitBucket emits GitHub-compatible payloads, so action names are
# identity-mapped (same map as the GitHub backend).  Uses X-GitHub-Event
# header, same as GitHub.
# Trust-the-network mode (no webhook_secret_BACKEND CLI arg): signature headers omitted.

# ── issues: opened → 200 ─────────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: issues
{
  "action": "opened",
  "issue": {
    "id": 1,
    "node_id": "",
    "number": 1,
    "title": "Found a bug",
    "body": "Something broke.",
    "state": "open",
    "html_url": "http://localhost/octocat/hello-world/issues/1",
    "url": "http://localhost/octocat/hello-world/issues/1",
    "user": {
      "login": "octocat", "id": 1, "node_id": "", "avatar_url": "",
      "url": "", "html_url": "", "type": "User"
    },
    "labels": [],
    "assignees": [],
    "milestone": null,
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T10:00:00Z",
    "closed_at": null
  },
  "repository": {
    "id": 1, "node_id": "", "name": "hello-world",
    "full_name": "octocat/hello-world", "private": false,
    "owner": {
      "login": "octocat", "id": 1, "node_id": "", "avatar_url": "",
      "url": "", "html_url": "", "type": "User"
    },
    "html_url": "http://localhost/octocat/hello-world",
    "description": "", "fork": false, "url": "",
    "clone_url": "", "homepage": "", "default_branch": "main",
    "visibility": "public"
  },
  "sender": {
    "login": "octocat", "id": 1, "node_id": "", "avatar_url": "",
    "url": "", "html_url": "", "type": "User"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── issues: labeled → 200 ────────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: issues
{
  "action": "labeled",
  "issue": {
    "id": 1, "node_id": "", "number": 1, "title": "Found a bug",
    "body": "Something broke.", "state": "open",
    "html_url": "http://localhost/octocat/hello-world/issues/1",
    "url": "http://localhost/octocat/hello-world/issues/1",
    "user": {
      "login": "octocat", "id": 1, "node_id": "", "avatar_url": "",
      "url": "", "html_url": "", "type": "User"
    },
    "labels": [{"id": 5, "node_id": "", "name": "bug", "color": "d73a4a", "url": ""}],
    "assignees": [], "milestone": null,
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T10:00:01Z",
    "closed_at": null
  },
  "label": {"id": 5, "node_id": "", "name": "bug", "color": "d73a4a", "url": ""},
  "repository": {
    "id": 1, "node_id": "", "name": "hello-world",
    "full_name": "octocat/hello-world", "private": false,
    "owner": {
      "login": "octocat", "id": 1, "node_id": "", "avatar_url": "",
      "url": "", "html_url": "", "type": "User"
    },
    "html_url": "http://localhost/octocat/hello-world",
    "description": "", "fork": false, "url": "",
    "clone_url": "", "homepage": "", "default_branch": "main",
    "visibility": "public"
  },
  "sender": {
    "login": "octocat", "id": 1, "node_id": "", "avatar_url": "",
    "url": "", "html_url": "", "type": "User"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── issues: unknown action → 200 + X-Confusio-Raw-Action ─────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: issues
{
  "action": "auto_closed",
  "issue": {
    "id": 1, "node_id": "", "number": 1, "title": "Found a bug",
    "body": "Something broke.", "state": "closed",
    "html_url": "http://localhost/octocat/hello-world/issues/1",
    "url": "http://localhost/octocat/hello-world/issues/1",
    "user": {
      "login": "octocat", "id": 1, "node_id": "", "avatar_url": "",
      "url": "", "html_url": "", "type": "User"
    },
    "labels": [], "assignees": [], "milestone": null,
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T10:00:05Z",
    "closed_at": "2024-01-15T10:00:05Z"
  },
  "repository": {
    "id": 1, "node_id": "", "name": "hello-world",
    "full_name": "octocat/hello-world", "private": false,
    "owner": {
      "login": "octocat", "id": 1, "node_id": "", "avatar_url": "",
      "url": "", "html_url": "", "type": "User"
    },
    "html_url": "http://localhost/octocat/hello-world",
    "description": "", "fork": false, "url": "",
    "clone_url": "", "homepage": "", "default_branch": "main",
    "visibility": "public"
  },
  "sender": {
    "login": "octocat", "id": 1, "node_id": "", "avatar_url": "",
    "url": "", "html_url": "", "type": "User"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"
header "X-Confusio-Raw-Action" == "auto_closed"

# ── issue_comment: created → 200 ─────────────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: issue_comment
{
  "action": "created",
  "issue": {
    "id": 1, "node_id": "", "number": 1, "title": "Found a bug",
    "body": "Something broke.", "state": "open",
    "html_url": "http://localhost/octocat/hello-world/issues/1",
    "url": "http://localhost/octocat/hello-world/issues/1",
    "user": {
      "login": "octocat", "id": 1, "node_id": "", "avatar_url": "",
      "url": "", "html_url": "", "type": "User"
    },
    "labels": [], "assignees": [], "milestone": null,
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T11:00:00Z",
    "closed_at": null
  },
  "comment": {
    "id": 42, "node_id": "",
    "body": "Confirmed, I can reproduce this.",
    "html_url": "http://localhost/octocat/hello-world/issues/1#issuecomment-42",
    "url": "http://localhost/octocat/hello-world/issues/comments/42",
    "user": {
      "login": "bob", "id": 2, "node_id": "", "avatar_url": "",
      "url": "", "html_url": "", "type": "User"
    },
    "created_at": "2024-01-15T11:00:00Z",
    "updated_at": "2024-01-15T11:00:00Z"
  },
  "repository": {
    "id": 1, "node_id": "", "name": "hello-world",
    "full_name": "octocat/hello-world", "private": false,
    "owner": {
      "login": "octocat", "id": 1, "node_id": "", "avatar_url": "",
      "url": "", "html_url": "", "type": "User"
    },
    "html_url": "http://localhost/octocat/hello-world",
    "description": "", "fork": false, "url": "",
    "clone_url": "", "homepage": "", "default_branch": "main",
    "visibility": "public"
  },
  "sender": {
    "login": "bob", "id": 2, "node_id": "", "avatar_url": "",
    "url": "", "html_url": "", "type": "User"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── label: created → 200 ─────────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: label
{
  "action": "created",
  "label": {
    "id": 5, "node_id": "",
    "name": "enhancement",
    "color": "a2eeef",
    "default": false,
    "description": "New feature or request",
    "url": "http://localhost/octocat/hello-world/labels/enhancement"
  },
  "repository": {
    "id": 1, "node_id": "", "name": "hello-world",
    "full_name": "octocat/hello-world", "private": false,
    "owner": {
      "login": "octocat", "id": 1, "node_id": "", "avatar_url": "",
      "url": "", "html_url": "", "type": "User"
    },
    "html_url": "http://localhost/octocat/hello-world",
    "description": "", "fork": false, "url": "",
    "clone_url": "", "homepage": "", "default_branch": "main",
    "visibility": "public"
  },
  "sender": {
    "login": "octocat", "id": 1, "node_id": "", "avatar_url": "",
    "url": "", "html_url": "", "type": "User"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── label: edited → 200 ──────────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: label
{
  "action": "edited",
  "label": {
    "id": 5, "node_id": "",
    "name": "enhancement", "color": "0075ca",
    "default": false, "description": "New feature or request",
    "url": "http://localhost/octocat/hello-world/labels/enhancement"
  },
  "changes": {"color": {"from": "a2eeef"}},
  "repository": {
    "id": 1, "node_id": "", "name": "hello-world",
    "full_name": "octocat/hello-world", "private": false,
    "owner": {
      "login": "octocat", "id": 1, "node_id": "", "avatar_url": "",
      "url": "", "html_url": "", "type": "User"
    },
    "html_url": "http://localhost/octocat/hello-world",
    "description": "", "fork": false, "url": "",
    "clone_url": "", "homepage": "", "default_branch": "main",
    "visibility": "public"
  },
  "sender": {
    "login": "octocat", "id": 1, "node_id": "", "avatar_url": "",
    "url": "", "html_url": "", "type": "User"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── milestone: created → 200 ──────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: milestone
{
  "action": "created",
  "milestone": {
    "id": 3, "node_id": "", "number": 1,
    "title": "v2.0", "description": "Second major release",
    "state": "open",
    "html_url": "http://localhost/octocat/hello-world/milestone/1",
    "url": "http://localhost/octocat/hello-world/milestones/1",
    "open_issues": 0, "closed_issues": 0,
    "due_on": "2024-06-01T00:00:00Z",
    "creator": {
      "login": "octocat", "id": 1, "node_id": "", "avatar_url": "",
      "url": "", "html_url": "", "type": "User"
    },
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T10:00:00Z",
    "closed_at": null
  },
  "repository": {
    "id": 1, "node_id": "", "name": "hello-world",
    "full_name": "octocat/hello-world", "private": false,
    "owner": {
      "login": "octocat", "id": 1, "node_id": "", "avatar_url": "",
      "url": "", "html_url": "", "type": "User"
    },
    "html_url": "http://localhost/octocat/hello-world",
    "description": "", "fork": false, "url": "",
    "clone_url": "", "homepage": "", "default_branch": "main",
    "visibility": "public"
  },
  "sender": {
    "login": "octocat", "id": 1, "node_id": "", "avatar_url": "",
    "url": "", "html_url": "", "type": "User"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── milestone: closed → 200 ───────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: milestone
{
  "action": "closed",
  "milestone": {
    "id": 3, "node_id": "", "number": 1,
    "title": "v2.0", "description": "Second major release",
    "state": "closed",
    "html_url": "http://localhost/octocat/hello-world/milestone/1",
    "url": "http://localhost/octocat/hello-world/milestones/1",
    "open_issues": 0, "closed_issues": 5,
    "due_on": "2024-06-01T00:00:00Z",
    "creator": {
      "login": "octocat", "id": 1, "node_id": "", "avatar_url": "",
      "url": "", "html_url": "", "type": "User"
    },
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-06-01T10:00:00Z",
    "closed_at": "2024-06-01T10:00:00Z"
  },
  "repository": {
    "id": 1, "node_id": "", "name": "hello-world",
    "full_name": "octocat/hello-world", "private": false,
    "owner": {
      "login": "octocat", "id": 1, "node_id": "", "avatar_url": "",
      "url": "", "html_url": "", "type": "User"
    },
    "html_url": "http://localhost/octocat/hello-world",
    "description": "", "fork": false, "url": "",
    "clone_url": "", "homepage": "", "default_branch": "main",
    "visibility": "public"
  },
  "sender": {
    "login": "octocat", "id": 1, "node_id": "", "avatar_url": "",
    "url": "", "html_url": "", "type": "User"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pull_request: opened → 200 ────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: pull_request
{
  "action": "opened",
  "number": 7,
  "pull_request": {
    "id": 500,
    "node_id": "",
    "number": 7,
    "title": "Add new feature",
    "body": "This PR adds a new feature.",
    "state": "open",
    "draft": false,
    "html_url": "http://localhost/octocat/hello-world/pull/7",
    "url": "http://localhost/api/v3/repos/octocat/hello-world/pulls/7",
    "user": {
      "login": "bob", "id": 2, "node_id": "", "avatar_url": "",
      "url": "", "html_url": "", "type": "User"
    },
    "head": {
      "ref": "feature-branch", "sha": "abc123",
      "repo": {
        "id": 1, "node_id": "", "name": "hello-world",
        "full_name": "octocat/hello-world", "private": false,
        "owner": {
          "login": "octocat", "id": 1, "node_id": "", "avatar_url": "",
          "url": "", "html_url": "", "type": "User"
        },
        "html_url": "http://localhost/octocat/hello-world",
        "description": "", "fork": false, "url": "",
        "clone_url": "", "homepage": "", "default_branch": "main",
        "visibility": "public"
      }
    },
    "base": {
      "ref": "main", "sha": "def456",
      "repo": {
        "id": 1, "node_id": "", "name": "hello-world",
        "full_name": "octocat/hello-world", "private": false,
        "owner": {
          "login": "octocat", "id": 1, "node_id": "", "avatar_url": "",
          "url": "", "html_url": "", "type": "User"
        },
        "html_url": "http://localhost/octocat/hello-world",
        "description": "", "fork": false, "url": "",
        "clone_url": "", "homepage": "", "default_branch": "main",
        "visibility": "public"
      }
    },
    "labels": [],
    "assignees": [],
    "requested_reviewers": [],
    "merged": false,
    "merged_at": null,
    "merge_commit_sha": null,
    "merged_by": null,
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T10:00:00Z",
    "closed_at": null
  },
  "repository": {
    "id": 1, "node_id": "", "name": "hello-world",
    "full_name": "octocat/hello-world", "private": false,
    "owner": {
      "login": "octocat", "id": 1, "node_id": "", "avatar_url": "",
      "url": "", "html_url": "", "type": "User"
    },
    "html_url": "http://localhost/octocat/hello-world",
    "description": "", "fork": false, "url": "",
    "clone_url": "", "homepage": "", "default_branch": "main",
    "visibility": "public"
  },
  "sender": {
    "login": "bob", "id": 2, "node_id": "", "avatar_url": "",
    "url": "", "html_url": "", "type": "User"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pull_request: synchronize → 200 (commit pushed to PR branch) ─────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: pull_request
{
  "action": "synchronize",
  "number": 7,
  "pull_request": {
    "id": 500, "node_id": "", "number": 7,
    "title": "Add new feature", "body": "This PR adds a new feature.",
    "state": "open", "draft": false,
    "html_url": "http://localhost/octocat/hello-world/pull/7",
    "url": "http://localhost/api/v3/repos/octocat/hello-world/pulls/7",
    "user": {"login": "bob", "id": 2, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "head": {"ref": "feature-branch", "sha": "ghi789", "repo": null},
    "base": {"ref": "main", "sha": "def456", "repo": null},
    "labels": [], "assignees": [], "requested_reviewers": [],
    "merged": false, "merged_at": null, "merge_commit_sha": null, "merged_by": null,
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T10:05:00Z",
    "closed_at": null
  },
  "repository": {
    "id": 1, "node_id": "", "name": "hello-world",
    "full_name": "octocat/hello-world", "private": false,
    "owner": {"login": "octocat", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "html_url": "http://localhost/octocat/hello-world",
    "description": "", "fork": false, "url": "",
    "clone_url": "", "homepage": "", "default_branch": "main",
    "visibility": "public"
  },
  "sender": {"login": "bob", "id": 2, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pull_request: closed (merged) → 200 ──────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: pull_request
{
  "action": "closed",
  "number": 7,
  "pull_request": {
    "id": 500, "node_id": "", "number": 7,
    "title": "Add new feature", "body": "This PR adds a new feature.",
    "state": "closed", "draft": false,
    "html_url": "http://localhost/octocat/hello-world/pull/7",
    "url": "http://localhost/api/v3/repos/octocat/hello-world/pulls/7",
    "user": {"login": "bob", "id": 2, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "head": {"ref": "feature-branch", "sha": "ghi789", "repo": null},
    "base": {"ref": "main", "sha": "def456", "repo": null},
    "labels": [], "assignees": [], "requested_reviewers": [],
    "merged": true,
    "merged_at": "2024-01-16T09:00:00Z",
    "merge_commit_sha": "jkl012",
    "merged_by": {"login": "octocat", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-16T09:00:00Z",
    "closed_at": "2024-01-16T09:00:00Z"
  },
  "repository": {
    "id": 1, "node_id": "", "name": "hello-world",
    "full_name": "octocat/hello-world", "private": false,
    "owner": {"login": "octocat", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "html_url": "http://localhost/octocat/hello-world",
    "description": "", "fork": false, "url": "",
    "clone_url": "", "homepage": "", "default_branch": "main",
    "visibility": "public"
  },
  "sender": {"login": "octocat", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pull_request: labeled → 200 (with label field in data) ───────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: pull_request
{
  "action": "labeled",
  "number": 7,
  "pull_request": {
    "id": 500, "node_id": "", "number": 7,
    "title": "Add new feature", "body": null,
    "state": "open", "draft": false,
    "html_url": "http://localhost/octocat/hello-world/pull/7",
    "url": "http://localhost/api/v3/repos/octocat/hello-world/pulls/7",
    "user": {"login": "bob", "id": 2, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "head": {"ref": "feature-branch", "sha": "ghi789", "repo": null},
    "base": {"ref": "main", "sha": "def456", "repo": null},
    "labels": [{"id": 5, "node_id": "", "name": "bug", "color": "d73a4a", "url": ""}],
    "assignees": [], "requested_reviewers": [],
    "merged": false, "merged_at": null, "merge_commit_sha": null, "merged_by": null,
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T10:02:00Z",
    "closed_at": null
  },
  "label": {"id": 5, "node_id": "", "name": "bug", "color": "d73a4a", "url": ""},
  "repository": {
    "id": 1, "node_id": "", "name": "hello-world",
    "full_name": "octocat/hello-world", "private": false,
    "owner": {"login": "octocat", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "html_url": "http://localhost/octocat/hello-world",
    "description": "", "fork": false, "url": "",
    "clone_url": "", "homepage": "", "default_branch": "main",
    "visibility": "public"
  },
  "sender": {"login": "octocat", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pull_request: review_requested → 200 (with requested_reviewer) ───────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: pull_request
{
  "action": "review_requested",
  "number": 7,
  "pull_request": {
    "id": 500, "node_id": "", "number": 7,
    "title": "Add new feature", "body": null,
    "state": "open", "draft": false,
    "html_url": "http://localhost/octocat/hello-world/pull/7",
    "url": "http://localhost/api/v3/repos/octocat/hello-world/pulls/7",
    "user": {"login": "bob", "id": 2, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "head": {"ref": "feature-branch", "sha": "ghi789", "repo": null},
    "base": {"ref": "main", "sha": "def456", "repo": null},
    "labels": [], "assignees": [],
    "requested_reviewers": [
      {"login": "carol", "id": 3, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"}
    ],
    "merged": false, "merged_at": null, "merge_commit_sha": null, "merged_by": null,
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T10:03:00Z",
    "closed_at": null
  },
  "requested_reviewer": {
    "login": "carol", "id": 3, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"
  },
  "repository": {
    "id": 1, "node_id": "", "name": "hello-world",
    "full_name": "octocat/hello-world", "private": false,
    "owner": {"login": "octocat", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "html_url": "http://localhost/octocat/hello-world",
    "description": "", "fork": false, "url": "",
    "clone_url": "", "homepage": "", "default_branch": "main",
    "visibility": "public"
  },
  "sender": {"login": "octocat", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pull_request: unknown action → 200 + X-Confusio-Raw-Action ───────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: pull_request
{
  "action": "auto_merged",
  "number": 7,
  "pull_request": {
    "id": 500, "node_id": "", "number": 7,
    "title": "Add new feature", "body": null,
    "state": "closed", "draft": false,
    "html_url": "http://localhost/octocat/hello-world/pull/7",
    "url": "http://localhost/api/v3/repos/octocat/hello-world/pulls/7",
    "user": {"login": "bob", "id": 2, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "head": {"ref": "feature-branch", "sha": "ghi789", "repo": null},
    "base": {"ref": "main", "sha": "def456", "repo": null},
    "labels": [], "assignees": [], "requested_reviewers": [],
    "merged": false, "merged_at": null, "merge_commit_sha": null, "merged_by": null,
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T10:00:00Z",
    "closed_at": null
  },
  "repository": {
    "id": 1, "node_id": "", "name": "hello-world",
    "full_name": "octocat/hello-world", "private": false,
    "owner": {"login": "octocat", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "html_url": "http://localhost/octocat/hello-world",
    "description": "", "fork": false, "url": "",
    "clone_url": "", "homepage": "", "default_branch": "main",
    "visibility": "public"
  },
  "sender": {"login": "bob", "id": 2, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"
header "X-Confusio-Raw-Action" == "auto_merged"

# ── pull_request_review: submitted (approved) → 200 ──────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: pull_request_review
{
  "action": "submitted",
  "review": {
    "id": 80,
    "node_id": "",
    "user": {"login": "alice", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "body": "Looks good to me!",
    "state": "APPROVED",
    "submitted_at": "2024-01-15T14:00:00Z",
    "html_url": "http://localhost/octocat/hello-world/pull/7#pullrequestreview-80",
    "pull_request_url": "http://localhost/api/v3/repos/octocat/hello-world/pulls/7"
  },
  "pull_request": {
    "id": 500, "node_id": "", "number": 7,
    "title": "Add new feature", "body": "", "state": "open",
    "draft": false, "html_url": "http://localhost/octocat/hello-world/pull/7",
    "url": "http://localhost/api/v3/repos/octocat/hello-world/pulls/7",
    "user": {"login": "bob", "id": 2, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "head": {"ref": "feature-branch", "sha": "abc123", "repo": null},
    "base": {"ref": "main", "sha": "def456", "repo": null},
    "created_at": "2024-01-15T10:00:00Z", "updated_at": "2024-01-15T14:00:00Z", "closed_at": null
  },
  "repository": {
    "id": 1, "node_id": "", "name": "hello-world",
    "full_name": "octocat/hello-world", "private": false,
    "owner": {"login": "octocat", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "html_url": "http://localhost/octocat/hello-world",
    "description": "", "fork": false, "url": "",
    "clone_url": "", "homepage": "", "default_branch": "main",
    "visibility": "public"
  },
  "sender": {"login": "alice", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pull_request_review: submitted (changes_requested) → 200 ─────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: pull_request_review
{
  "action": "submitted",
  "review": {
    "id": 81,
    "node_id": "",
    "user": {"login": "alice", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "body": "Please fix the edge cases.",
    "state": "CHANGES_REQUESTED",
    "submitted_at": "2024-01-15T15:00:00Z",
    "html_url": "http://localhost/octocat/hello-world/pull/7#pullrequestreview-81",
    "pull_request_url": "http://localhost/api/v3/repos/octocat/hello-world/pulls/7"
  },
  "pull_request": {
    "id": 500, "node_id": "", "number": 7,
    "title": "Add new feature", "body": "", "state": "open",
    "draft": false, "html_url": "http://localhost/octocat/hello-world/pull/7",
    "url": "http://localhost/api/v3/repos/octocat/hello-world/pulls/7",
    "user": {"login": "bob", "id": 2, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "head": {"ref": "feature-branch", "sha": "abc123", "repo": null},
    "base": {"ref": "main", "sha": "def456", "repo": null},
    "created_at": "2024-01-15T10:00:00Z", "updated_at": "2024-01-15T15:00:00Z", "closed_at": null
  },
  "repository": {
    "id": 1, "node_id": "", "name": "hello-world",
    "full_name": "octocat/hello-world", "private": false,
    "owner": {"login": "octocat", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "html_url": "http://localhost/octocat/hello-world",
    "description": "", "fork": false, "url": "",
    "clone_url": "", "homepage": "", "default_branch": "main",
    "visibility": "public"
  },
  "sender": {"login": "alice", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pull_request_review: dismissed → 200 ─────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: pull_request_review
{
  "action": "dismissed",
  "review": {
    "id": 80,
    "node_id": "",
    "user": {"login": "alice", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "body": "",
    "state": "DISMISSED",
    "submitted_at": "2024-01-15T16:00:00Z",
    "html_url": "http://localhost/octocat/hello-world/pull/7#pullrequestreview-80",
    "pull_request_url": "http://localhost/api/v3/repos/octocat/hello-world/pulls/7"
  },
  "pull_request": {
    "id": 500, "node_id": "", "number": 7,
    "title": "Add new feature", "body": "", "state": "open",
    "draft": false, "html_url": "http://localhost/octocat/hello-world/pull/7",
    "url": "http://localhost/api/v3/repos/octocat/hello-world/pulls/7",
    "user": {"login": "bob", "id": 2, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "head": {"ref": "feature-branch", "sha": "abc123", "repo": null},
    "base": {"ref": "main", "sha": "def456", "repo": null},
    "created_at": "2024-01-15T10:00:00Z", "updated_at": "2024-01-15T16:00:00Z", "closed_at": null
  },
  "repository": {
    "id": 1, "node_id": "", "name": "hello-world",
    "full_name": "octocat/hello-world", "private": false,
    "owner": {"login": "octocat", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "html_url": "http://localhost/octocat/hello-world",
    "description": "", "fork": false, "url": "",
    "clone_url": "", "homepage": "", "default_branch": "main",
    "visibility": "public"
  },
  "sender": {"login": "bob", "id": 2, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── push: branch push with commits → 200 ─────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: push
{
  "ref": "refs/heads/main",
  "before": "abc123def456abc123def456abc123def456abc1",
  "after":  "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
  "created": false,
  "deleted": false,
  "forced":  false,
  "compare": "http://localhost/octocat/hello-world/compare/abc123...deadbeef",
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
  "pusher": {"name": "alice", "email": "alice@example.com"},
  "repository": {
    "id": 1, "node_id": "", "name": "hello-world",
    "full_name": "octocat/hello-world", "private": false,
    "owner": {"login": "octocat", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "html_url": "http://localhost/octocat/hello-world",
    "description": "", "fork": false, "url": "",
    "clone_url": "", "homepage": "", "default_branch": "main",
    "visibility": "public"
  },
  "sender": {"login": "alice", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── push: branch deletion (after = zero SHA, deleted = true) → 200 ───────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: push
{
  "ref": "refs/heads/stale-branch",
  "before": "abc123def456abc123def456abc123def456abc1",
  "after":  "0000000000000000000000000000000000000000",
  "created": false,
  "deleted": true,
  "forced":  false,
  "compare": "",
  "commits": [],
  "head_commit": null,
  "pusher": {"name": "alice", "email": "alice@example.com"},
  "repository": {
    "id": 1, "node_id": "", "name": "hello-world",
    "full_name": "octocat/hello-world", "private": false,
    "owner": {"login": "octocat", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "html_url": "http://localhost/octocat/hello-world",
    "description": "", "fork": false, "url": "",
    "clone_url": "", "homepage": "", "default_branch": "main",
    "visibility": "public"
  },
  "sender": {"login": "alice", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── create: branch created → 200 ─────────────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: create
{
  "ref": "feature-branch",
  "ref_type": "branch",
  "master_branch": "main",
  "description": "A friendly repo",
  "pusher_type": "user",
  "repository": {
    "id": 1, "node_id": "", "name": "hello-world",
    "full_name": "octocat/hello-world", "private": false,
    "owner": {"login": "octocat", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "html_url": "http://localhost/octocat/hello-world",
    "description": "A friendly repo", "fork": false, "url": "",
    "clone_url": "", "homepage": "", "default_branch": "main",
    "visibility": "public"
  },
  "sender": {"login": "bob", "id": 2, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── create: tag created → 200 ────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: create
{
  "ref": "v2.0.0",
  "ref_type": "tag",
  "master_branch": "main",
  "description": "A friendly repo",
  "pusher_type": "user",
  "repository": {
    "id": 1, "node_id": "", "name": "hello-world",
    "full_name": "octocat/hello-world", "private": false,
    "owner": {"login": "octocat", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "html_url": "http://localhost/octocat/hello-world",
    "description": "A friendly repo", "fork": false, "url": "",
    "clone_url": "", "homepage": "", "default_branch": "main",
    "visibility": "public"
  },
  "sender": {"login": "alice", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── delete: branch deleted → 200 ─────────────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: delete
{
  "ref": "stale-branch",
  "ref_type": "branch",
  "master_branch": "main",
  "description": "A friendly repo",
  "pusher_type": "user",
  "repository": {
    "id": 1, "node_id": "", "name": "hello-world",
    "full_name": "octocat/hello-world", "private": false,
    "owner": {"login": "octocat", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "html_url": "http://localhost/octocat/hello-world",
    "description": "A friendly repo", "fork": false, "url": "",
    "clone_url": "", "homepage": "", "default_branch": "main",
    "visibility": "public"
  },
  "sender": {"login": "bob", "id": 2, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── release: published → 200 ─────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: release
{
  "action": "published",
  "release": {
    "id": 1, "tag_name": "v1.0.0", "name": "Release 1.0.0", "body": "First release",
    "draft": false, "prerelease": false,
    "html_url": "http://localhost/octocat/hello-world/releases/tag/v1.0.0",
    "tarball_url": "http://localhost/octocat/hello-world/archive/v1.0.0.tar.gz",
    "zipball_url": "http://localhost/octocat/hello-world/archive/v1.0.0.zip",
    "author": {"id": 1, "login": "alice", "avatar_url": "", "html_url": ""},
    "created_at": "2024-01-15T10:00:00Z", "published_at": "2024-01-15T10:00:00Z"
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

# ── release: edited → 200 ─────────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: release
{
  "action": "edited",
  "release": {
    "id": 1, "tag_name": "v1.0.0", "name": "Release 1.0.0 (edited)", "body": "First release (edited)",
    "draft": false, "prerelease": false,
    "html_url": "http://localhost/octocat/hello-world/releases/tag/v1.0.0",
    "tarball_url": "http://localhost/octocat/hello-world/archive/v1.0.0.tar.gz",
    "zipball_url": "http://localhost/octocat/hello-world/archive/v1.0.0.zip",
    "author": {"id": 1, "login": "alice", "avatar_url": "", "html_url": ""},
    "created_at": "2024-01-15T10:00:00Z", "published_at": "2024-01-15T10:00:00Z"
  },
  "changes": {},
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

# ── release: deleted → 200 ────────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: release
{
  "action": "deleted",
  "release": {
    "id": 1, "tag_name": "v1.0.0", "name": "Release 1.0.0", "body": "First release",
    "draft": false, "prerelease": false,
    "html_url": "http://localhost/octocat/hello-world/releases/tag/v1.0.0",
    "tarball_url": "http://localhost/octocat/hello-world/archive/v1.0.0.tar.gz",
    "zipball_url": "http://localhost/octocat/hello-world/archive/v1.0.0.zip",
    "author": {"id": 1, "login": "alice", "avatar_url": "", "html_url": ""},
    "created_at": "2024-01-15T10:00:00Z", "published_at": "2024-01-15T10:00:00Z"
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

# ── fork: repository forked → 200 ─────────────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: fork
{
  "forkee": {
    "id": 2, "node_id": "", "name": "hello-world",
    "full_name": "bob/hello-world", "private": false,
    "owner": {"login": "bob", "id": 2, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "html_url": "http://localhost/bob/hello-world",
    "description": "A friendly repo", "fork": true, "url": "",
    "clone_url": "", "homepage": "", "default_branch": "main",
    "visibility": "public"
  },
  "repository": {
    "id": 1, "node_id": "", "name": "hello-world",
    "full_name": "octocat/hello-world", "private": false,
    "owner": {"login": "octocat", "id": 1, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"},
    "html_url": "http://localhost/octocat/hello-world",
    "description": "A friendly repo", "fork": false, "url": "",
    "clone_url": "", "homepage": "", "default_branch": "main",
    "visibility": "public"
  },
  "sender": {"login": "bob", "id": 2, "node_id": "", "avatar_url": "", "url": "", "html_url": "", "type": "User"}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"
