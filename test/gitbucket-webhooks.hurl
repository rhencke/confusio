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

# ── code_scanning_alert: created → 200 ────────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: code_scanning_alert
{
  "action": "created",
  "alert": {
    "number": 1, "state": "open",
    "dismissed_by": null, "dismissed_at": null, "dismissed_reason": null,
    "rule": {"id": "js/path-injection", "severity": "error", "description": "Path injection"},
    "tool": {"name": "CodeQL", "version": "2.9.0"},
    "most_recent_instance": {
      "ref": "refs/heads/main", "state": "open",
      "commit_sha": "abc123def456abc123def456abc123def456abc1",
      "message": {"text": "User input flows to path construction."},
      "location": {"path": "src/server.js", "start_line": 42, "end_line": 42}
    },
    "html_url": "http://localhost/octocat/hello-world/security/code-scanning/1",
    "created_at": "2024-01-15T10:00:00Z", "updated_at": "2024-01-15T10:00:00Z"
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

# ── code_scanning_alert: fixed → 200 ──────────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: code_scanning_alert
{
  "action": "fixed",
  "alert": {
    "number": 1, "state": "fixed",
    "dismissed_by": null, "dismissed_at": null, "dismissed_reason": null,
    "rule": {"id": "js/path-injection", "severity": "error", "description": "Path injection"},
    "tool": {"name": "CodeQL", "version": "2.9.0"},
    "most_recent_instance": {
      "ref": "refs/heads/main", "state": "fixed",
      "commit_sha": "def456abc123def456abc123def456abc123def4",
      "message": {"text": "User input flows to path construction."},
      "location": {"path": "src/server.js", "start_line": 42, "end_line": 42}
    },
    "html_url": "http://localhost/octocat/hello-world/security/code-scanning/1",
    "created_at": "2024-01-15T10:00:00Z", "updated_at": "2024-01-16T08:00:00Z"
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

# ── code_scanning_alert: unknown action → 200 + X-Confusio-Raw-Action ─────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: code_scanning_alert
{
  "action": "auto_closed",
  "alert": {
    "number": 2, "state": "closed",
    "dismissed_by": null, "dismissed_at": null, "dismissed_reason": null,
    "rule": {"id": "js/path-injection", "severity": "error", "description": "Path injection"},
    "tool": {"name": "CodeQL", "version": "2.9.0"},
    "html_url": "http://localhost/octocat/hello-world/security/code-scanning/2",
    "created_at": "2024-01-15T10:00:00Z", "updated_at": "2024-01-15T11:00:00Z"
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
header "X-Confusio-Raw-Action" == "auto_closed"

# ── dependabot_alert: created → 200 ───────────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: dependabot_alert
{
  "action": "created",
  "alert": {
    "number": 1, "state": "open",
    "dependency": {
      "package": {"ecosystem": "npm", "name": "lodash"},
      "manifest_path": "package-lock.json", "scope": "runtime"
    },
    "security_advisory": {
      "ghsa_id": "GHSA-xx99-1234-5678", "cve_id": "CVE-2021-23337",
      "summary": "Prototype Pollution in lodash", "severity": "high",
      "identifiers": [{"type": "GHSA", "value": "GHSA-xx99-1234-5678"}],
      "references": [], "vulnerabilities": [],
      "published_at": "2021-02-15T00:00:00Z", "updated_at": "2021-02-15T00:00:00Z",
      "withdrawn_at": null
    },
    "security_vulnerability": {
      "package": {"ecosystem": "npm", "name": "lodash"},
      "severity": "high", "vulnerable_version_range": "< 4.17.21",
      "first_patched_version": {"identifier": "4.17.21"}
    },
    "url": "http://localhost/api/v3/repos/octocat/hello-world/dependabot/alerts/1",
    "html_url": "http://localhost/octocat/hello-world/security/dependabot/1",
    "created_at": "2024-01-15T10:00:00Z", "updated_at": "2024-01-15T10:00:00Z",
    "dismissed_at": null, "dismissed_by": null, "dismissed_reason": null,
    "dismissed_comment": null, "fixed_at": null, "auto_dismissed_at": null
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

# ── dependabot_alert: dismissed → 200 ─────────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: dependabot_alert
{
  "action": "dismissed",
  "alert": {
    "number": 1, "state": "dismissed",
    "dependency": {
      "package": {"ecosystem": "npm", "name": "lodash"},
      "manifest_path": "package-lock.json", "scope": "runtime"
    },
    "security_advisory": {
      "ghsa_id": "GHSA-xx99-1234-5678", "cve_id": "CVE-2021-23337",
      "summary": "Prototype Pollution in lodash", "severity": "high",
      "identifiers": [{"type": "GHSA", "value": "GHSA-xx99-1234-5678"}],
      "references": [], "vulnerabilities": [],
      "published_at": "2021-02-15T00:00:00Z", "updated_at": "2021-02-15T00:00:00Z",
      "withdrawn_at": null
    },
    "security_vulnerability": {
      "package": {"ecosystem": "npm", "name": "lodash"},
      "severity": "high", "vulnerable_version_range": "< 4.17.21",
      "first_patched_version": {"identifier": "4.17.21"}
    },
    "url": "http://localhost/api/v3/repos/octocat/hello-world/dependabot/alerts/1",
    "html_url": "http://localhost/octocat/hello-world/security/dependabot/1",
    "created_at": "2024-01-15T10:00:00Z", "updated_at": "2024-01-16T10:00:00Z",
    "dismissed_at": "2024-01-16T10:00:00Z",
    "dismissed_by": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""},
    "dismissed_reason": "tolerable_risk", "dismissed_comment": "Risk accepted.",
    "fixed_at": null, "auto_dismissed_at": null
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

# ── dependabot_alert: unknown action → 200 + X-Confusio-Raw-Action ────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: dependabot_alert
{
  "action": "scope_changed",
  "alert": {
    "number": 1, "state": "open",
    "dependency": {
      "package": {"ecosystem": "npm", "name": "lodash"},
      "manifest_path": "package-lock.json", "scope": "development"
    },
    "security_advisory": {
      "ghsa_id": "GHSA-xx99-1234-5678", "cve_id": "CVE-2021-23337",
      "summary": "Prototype Pollution in lodash", "severity": "high",
      "identifiers": [], "references": [], "vulnerabilities": [],
      "published_at": "2021-02-15T00:00:00Z", "updated_at": "2021-02-15T00:00:00Z",
      "withdrawn_at": null
    },
    "security_vulnerability": {
      "package": {"ecosystem": "npm", "name": "lodash"},
      "severity": "high", "vulnerable_version_range": "< 4.17.21",
      "first_patched_version": {"identifier": "4.17.21"}
    },
    "url": "http://localhost/api/v3/repos/octocat/hello-world/dependabot/alerts/1",
    "html_url": "http://localhost/octocat/hello-world/security/dependabot/1",
    "created_at": "2024-01-15T10:00:00Z", "updated_at": "2024-01-15T10:30:00Z",
    "dismissed_at": null, "dismissed_by": null, "dismissed_reason": null,
    "dismissed_comment": null, "fixed_at": null, "auto_dismissed_at": null
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
header "X-Confusio-Raw-Action" == "scope_changed"

# ── secret_scanning_alert: created → 200 ──────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: secret_scanning_alert
{
  "action": "created",
  "alert": {
    "number": 1, "state": "open",
    "secret_type": "github_personal_access_token",
    "secret_type_display_name": "GitHub Personal Access Token",
    "resolution": null, "resolved_by": null, "resolved_at": null,
    "html_url": "http://localhost/octocat/hello-world/security/secret-scanning/1",
    "created_at": "2024-01-15T10:00:00Z", "updated_at": "2024-01-15T10:00:00Z"
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

# ── secret_scanning_alert: resolved → 200 ─────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: secret_scanning_alert
{
  "action": "resolved",
  "alert": {
    "number": 1, "state": "resolved",
    "secret_type": "github_personal_access_token",
    "secret_type_display_name": "GitHub Personal Access Token",
    "resolution": "false_positive",
    "resolved_by": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""},
    "resolved_at": "2024-01-16T09:00:00Z",
    "html_url": "http://localhost/octocat/hello-world/security/secret-scanning/1",
    "created_at": "2024-01-15T10:00:00Z", "updated_at": "2024-01-16T09:00:00Z"
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

# ── secret_scanning_alert: unknown action → 200 + X-Confusio-Raw-Action ───────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: secret_scanning_alert
{
  "action": "revoked",
  "alert": {
    "number": 1, "state": "open",
    "secret_type": "github_personal_access_token",
    "secret_type_display_name": "GitHub Personal Access Token",
    "resolution": null, "resolved_by": null, "resolved_at": null,
    "html_url": "http://localhost/octocat/hello-world/security/secret-scanning/1",
    "created_at": "2024-01-15T10:00:00Z", "updated_at": "2024-01-15T11:00:00Z"
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
header "X-Confusio-Raw-Action" == "revoked"

# ── secret_scanning_alert_location: created → 200 ─────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: secret_scanning_alert_location
{
  "action": "created",
  "alert": {
    "number": 1, "state": "open",
    "secret_type": "github_personal_access_token",
    "secret_type_display_name": "GitHub Personal Access Token",
    "resolution": null, "resolved_by": null, "resolved_at": null,
    "html_url": "http://localhost/octocat/hello-world/security/secret-scanning/1",
    "created_at": "2024-01-15T10:00:00Z", "updated_at": "2024-01-15T10:00:00Z"
  },
  "location": {
    "type": "commit",
    "details": {
      "path": "src/config.js", "start_line": 12, "end_line": 12,
      "blob_sha": "abc123def456abc123def456abc123def456abc1",
      "commit_sha": "abc123def456abc123def456abc123def456abc1"
    }
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

# ── secret_scanning_alert_location: unknown action → 200 + X-Confusio-Raw-Action

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: secret_scanning_alert_location
{
  "action": "updated",
  "alert": {
    "number": 1, "state": "open",
    "secret_type": "github_personal_access_token",
    "secret_type_display_name": "GitHub Personal Access Token",
    "resolution": null, "resolved_by": null, "resolved_at": null,
    "html_url": "http://localhost/octocat/hello-world/security/secret-scanning/1",
    "created_at": "2024-01-15T10:00:00Z", "updated_at": "2024-01-15T10:30:00Z"
  },
  "location": {
    "type": "commit",
    "details": {
      "path": "src/config.js", "start_line": 12, "end_line": 12,
      "blob_sha": "abc123def456abc123def456abc123def456abc1",
      "commit_sha": "abc123def456abc123def456abc123def456abc1"
    }
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
header "X-Confusio-Raw-Action" == "updated"

# ── security_advisory: published → 200 ────────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: security_advisory
{
  "action": "published",
  "security_advisory": {
    "ghsa_id": "GHSA-xx99-1234-5678", "cve_id": "CVE-2024-12345",
    "summary": "Command injection in example-package",
    "severity": "high",
    "cvss": {"score": 7.8, "vector_string": "CVSS:3.1/AV:L/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:H"},
    "cwes": [],
    "identifiers": [{"type": "CVE", "value": "CVE-2024-12345"}],
    "references": [],
    "published_at": "2024-01-15T10:00:00Z", "updated_at": "2024-01-15T10:00:00Z",
    "withdrawn_at": null, "vulnerabilities": []
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

# ── security_advisory: withdrawn → 200 ────────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: security_advisory
{
  "action": "withdrawn",
  "security_advisory": {
    "ghsa_id": "GHSA-xx99-1234-5678", "cve_id": "CVE-2024-12345",
    "summary": "Command injection in example-package",
    "severity": "high",
    "cvss": {"score": 7.8, "vector_string": "CVSS:3.1/AV:L/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:H"},
    "cwes": [],
    "identifiers": [{"type": "CVE", "value": "CVE-2024-12345"}],
    "references": [],
    "published_at": "2024-01-15T10:00:00Z", "updated_at": "2024-01-16T12:00:00Z",
    "withdrawn_at": "2024-01-16T12:00:00Z", "vulnerabilities": []
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

# ── security_advisory: unknown action → 200 + X-Confusio-Raw-Action ──────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: security_advisory
{
  "action": "revised",
  "security_advisory": {
    "ghsa_id": "GHSA-xx99-1234-5678", "cve_id": "CVE-2024-12345",
    "summary": "Command injection in example-package",
    "severity": "high",
    "cvss": {"score": 7.8, "vector_string": "CVSS:3.1/AV:L/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:H"},
    "cwes": [],
    "identifiers": [],
    "references": [],
    "published_at": "2024-01-15T10:00:00Z", "updated_at": "2024-01-15T11:00:00Z",
    "withdrawn_at": null, "vulnerabilities": []
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
header "X-Confusio-Raw-Action" == "revised"

# ── repository_advisory: published → 200 ──────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: repository_advisory
{
  "action": "published",
  "repository_advisory": {
    "ghsa_id": "GHSA-yy88-4321-8765",
    "cve_id": null,
    "summary": "Buffer overflow in hello-world",
    "severity": "medium",
    "state": "published",
    "vulnerabilities": [],
    "cvss": {"score": 6.5, "vector_string": "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:N/A:L"},
    "credits": [],
    "published_at": "2024-01-15T10:00:00Z", "updated_at": "2024-01-15T10:00:00Z",
    "withdrawn_at": null
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

# ── repository_advisory: reported → 200 ───────────────────────────────────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: repository_advisory
{
  "action": "reported",
  "repository_advisory": {
    "ghsa_id": "GHSA-yy88-4321-8765",
    "cve_id": null,
    "summary": "Buffer overflow in hello-world",
    "severity": "medium",
    "state": "reported",
    "vulnerabilities": [],
    "cvss": {"score": 6.5, "vector_string": "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:N/A:L"},
    "credits": [],
    "published_at": null, "updated_at": "2024-01-16T11:00:00Z",
    "withdrawn_at": null
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

# ── repository_advisory: unknown action → 200 + X-Confusio-Raw-Action ─────────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: repository_advisory
{
  "action": "withdrawn",
  "repository_advisory": {
    "ghsa_id": "GHSA-yy88-4321-8765",
    "cve_id": null,
    "summary": "Buffer overflow in hello-world",
    "severity": "medium",
    "state": "withdrawn",
    "vulnerabilities": [],
    "cvss": {"score": 6.5, "vector_string": "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:N/A:L"},
    "credits": [],
    "published_at": "2024-01-15T10:00:00Z", "updated_at": "2024-01-15T12:00:00Z",
    "withdrawn_at": "2024-01-15T12:00:00Z"
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
header "X-Confusio-Raw-Action" == "withdrawn"

# ── repository_vulnerability_alert: create → emits dependabot_alert:created ───

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: repository_vulnerability_alert
{
  "action": "create",
  "alert": {
    "id": 1,
    "affected_range": "< 4.17.21",
    "affected_package_name": "lodash",
    "external_reference": "https://nvd.nist.gov/vuln/detail/CVE-2021-23337",
    "external_identifier": "CVE-2021-23337",
    "fixed_in": "4.17.21",
    "dismisser": null, "dismiss_reason": null, "dismissed_at": null
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

# ── repository_vulnerability_alert: dismiss → emits dependabot_alert:dismissed ─

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: repository_vulnerability_alert
{
  "action": "dismiss",
  "alert": {
    "id": 1,
    "affected_range": "< 4.17.21",
    "affected_package_name": "lodash",
    "external_reference": "https://nvd.nist.gov/vuln/detail/CVE-2021-23337",
    "external_identifier": "CVE-2021-23337",
    "fixed_in": "4.17.21",
    "dismisser": {"id": 2, "login": "bob", "avatar_url": "", "html_url": ""},
    "dismiss_reason": "tolerable_risk",
    "dismissed_at": "2024-01-16T10:00:00Z"
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

# ── repository_vulnerability_alert: unknown action → X-Confusio-Raw-Action ────

POST http://{{host}}/webhooks/gitbucket
Content-Type: application/json
X-GitHub-Event: repository_vulnerability_alert
{
  "action": "auto_dismissed",
  "alert": {
    "id": 1,
    "affected_range": "< 4.17.21",
    "affected_package_name": "lodash",
    "external_reference": "https://nvd.nist.gov/vuln/detail/CVE-2021-23337",
    "external_identifier": "CVE-2021-23337",
    "fixed_in": "4.17.21",
    "dismisser": null, "dismiss_reason": null, "dismissed_at": null
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
header "X-Confusio-Raw-Action" == "auto_dismissed"
