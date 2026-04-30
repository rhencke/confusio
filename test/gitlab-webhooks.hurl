# GitLab webhook normalizer tests.
#
# Exercises the five event families registered in backends/gitlab.lua.
# Trust-the-network mode (no webhook_secret_BACKEND CLI arg): signature headers omitted.
# All paths return 200 when a registered handler succeeds.

# ── Issue Hook: opened → 200 ──────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Issue Hook
{
  "object_kind": "issue",
  "user": {
    "id": 1,
    "name": "The Octocat",
    "username": "octocat",
    "avatar_url": "",
    "web_url": "http://localhost/octocat"
  },
  "project": {
    "id": 10,
    "name": "hello-world",
    "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20,
    "default_branch": "main"
  },
  "object_attributes": {
    "id": 1,
    "iid": 1,
    "title": "Found a bug",
    "description": "Something broke.",
    "state": "opened",
    "action": "open",
    "url": "http://localhost/octocat/hello-world/-/issues/1",
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T10:00:00Z",
    "closed_at": null
  },
  "labels": [],
  "assignees": [],
  "milestone": null
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Issues Hook: closed → 200 ─────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Issues Hook
{
  "object_kind": "issue",
  "user": {
    "id": 1, "name": "The Octocat", "username": "octocat",
    "avatar_url": "", "web_url": "http://localhost/octocat"
  },
  "project": {
    "id": 10, "name": "hello-world",
    "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20, "default_branch": "main"
  },
  "object_attributes": {
    "id": 1, "iid": 1, "title": "Found a bug",
    "description": "Something broke.", "state": "closed", "action": "close",
    "url": "http://localhost/octocat/hello-world/-/issues/1",
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T10:01:00Z",
    "closed_at": "2024-01-15T10:01:00Z"
  },
  "labels": [], "assignees": [], "milestone": null
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Issues Hook: unknown action → 200 + X-Confusio-Raw-Action ────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Issues Hook
{
  "object_kind": "issue",
  "user": {
    "id": 1, "name": "The Octocat", "username": "octocat",
    "avatar_url": "", "web_url": "http://localhost/octocat"
  },
  "project": {
    "id": 10, "name": "hello-world",
    "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20, "default_branch": "main"
  },
  "object_attributes": {
    "id": 1, "iid": 1, "title": "Found a bug",
    "description": "Something broke.", "state": "opened", "action": "confidential",
    "url": "http://localhost/octocat/hello-world/-/issues/1",
    "created_at": "2024-01-15T10:00:00Z", "updated_at": "2024-01-15T10:00:00Z",
    "closed_at": null
  },
  "labels": [], "assignees": [], "milestone": null
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"
header "X-Confusio-Raw-Action" == "confidential"

# ── Note Hook: created (on issue) → 200 ──────────────────────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Note Hook
{
  "object_kind": "note",
  "user": {
    "id": 2, "name": "Bob", "username": "bob",
    "avatar_url": "", "web_url": "http://localhost/bob"
  },
  "project": {
    "id": 10, "name": "hello-world",
    "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20, "default_branch": "main"
  },
  "object_attributes": {
    "id": 100,
    "note": "This is a comment.",
    "noteable_type": "Issue",
    "action": "create",
    "url": "http://localhost/octocat/hello-world/-/issues/1#note_100",
    "created_at": "2024-01-15T11:00:00Z",
    "updated_at": "2024-01-15T11:00:00Z"
  },
  "issue": {
    "id": 1, "iid": 1, "title": "Found a bug",
    "description": "Something broke.", "state": "opened",
    "author": {
      "id": 1, "name": "The Octocat", "username": "octocat",
      "avatar_url": "", "web_url": "http://localhost/octocat"
    },
    "assignees": [], "labels": [], "milestone": null,
    "user_notes_count": 1,
    "created_at": "2024-01-15T10:00:00Z", "updated_at": "2024-01-15T11:00:00Z",
    "closed_at": null, "web_url": "http://localhost/octocat/hello-world/-/issues/1"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Note Hook: deleted → 200 ──────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Note Hook
{
  "object_kind": "note",
  "user": {
    "id": 2, "name": "Bob", "username": "bob",
    "avatar_url": "", "web_url": "http://localhost/bob"
  },
  "project": {
    "id": 10, "name": "hello-world",
    "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20, "default_branch": "main"
  },
  "object_attributes": {
    "id": 100, "note": "This is a comment.", "noteable_type": "Issue",
    "action": "destroy",
    "url": "http://localhost/octocat/hello-world/-/issues/1#note_100",
    "created_at": "2024-01-15T11:00:00Z", "updated_at": "2024-01-15T11:05:00Z"
  },
  "issue": {
    "id": 1, "iid": 1, "title": "Found a bug", "description": "Something broke.",
    "state": "opened",
    "author": {
      "id": 1, "name": "The Octocat", "username": "octocat",
      "avatar_url": "", "web_url": "http://localhost/octocat"
    },
    "assignees": [], "labels": [], "milestone": null, "user_notes_count": 0,
    "created_at": "2024-01-15T10:00:00Z", "updated_at": "2024-01-15T11:05:00Z",
    "closed_at": null, "web_url": "http://localhost/octocat/hello-world/-/issues/1"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Note Hook: created (on merge request) → pull_request_review_comment ───────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Note Hook
{
  "object_kind": "note",
  "user": {
    "id": 3, "name": "Carol", "username": "carol",
    "avatar_url": "", "web_url": "http://localhost/carol"
  },
  "project": {
    "id": 10, "name": "hello-world",
    "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20, "default_branch": "main"
  },
  "object_attributes": {
    "id": 201, "note": "Nice change here.", "noteable_type": "MergeRequest",
    "action": "create",
    "url": "http://localhost/octocat/hello-world/-/merge_requests/7#note_201",
    "created_at": "2024-01-15T12:00:00Z",
    "updated_at": "2024-01-15T12:00:00Z",
    "position": {
      "new_path": "README.md", "old_path": "README.md", "new_line": 4,
      "head_sha": "abc123", "base_sha": "def456"
    }
  },
  "merge_request": {
    "id": 500, "iid": 7, "title": "Add new feature",
    "description": "This MR adds a new feature.", "state": "opened",
    "source_branch": "feature-branch", "target_branch": "main",
    "url": "http://localhost/octocat/hello-world/-/merge_requests/7",
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T12:00:00Z"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Note Hook: edited (on merge request) → pull_request_review_comment ────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Note Hook
{
  "object_kind": "note",
  "user": {
    "id": 3, "name": "Carol", "username": "carol",
    "avatar_url": "", "web_url": "http://localhost/carol"
  },
  "project": {
    "id": 10, "name": "hello-world",
    "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20, "default_branch": "main"
  },
  "object_attributes": {
    "id": 201, "note": "Nice change here, with polish.", "noteable_type": "MergeRequest",
    "action": "update",
    "url": "http://localhost/octocat/hello-world/-/merge_requests/7#note_201",
    "created_at": "2024-01-15T12:00:00Z",
    "updated_at": "2024-01-15T12:05:00Z",
    "position": {
      "new_path": "README.md", "old_path": "README.md", "new_line": 4,
      "head_sha": "abc123", "base_sha": "def456"
    }
  },
  "merge_request": {
    "id": 500, "iid": 7, "title": "Add new feature",
    "description": "This MR adds a new feature.", "state": "opened",
    "source_branch": "feature-branch", "target_branch": "main",
    "url": "http://localhost/octocat/hello-world/-/merge_requests/7",
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T12:05:00Z"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Note Hook: deleted (on merge request) → pull_request_review_comment ───────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Note Hook
{
  "object_kind": "note",
  "user": {
    "id": 3, "name": "Carol", "username": "carol",
    "avatar_url": "", "web_url": "http://localhost/carol"
  },
  "project": {
    "id": 10, "name": "hello-world",
    "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20, "default_branch": "main"
  },
  "object_attributes": {
    "id": 201, "note": "Nice change here, with polish.", "noteable_type": "MergeRequest",
    "action": "destroy",
    "url": "http://localhost/octocat/hello-world/-/merge_requests/7#note_201",
    "created_at": "2024-01-15T12:00:00Z",
    "updated_at": "2024-01-15T12:10:00Z",
    "position": {
      "new_path": "README.md", "old_path": "README.md", "new_line": 4,
      "head_sha": "abc123", "base_sha": "def456"
    }
  },
  "merge_request": {
    "id": 500, "iid": 7, "title": "Add new feature",
    "description": "This MR adds a new feature.", "state": "opened",
    "source_branch": "feature-branch", "target_branch": "main",
    "url": "http://localhost/octocat/hello-world/-/merge_requests/7",
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T12:10:00Z"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Label Hook: created → 200 ─────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Label Hook
{
  "object_kind": "label",
  "user": {
    "id": 1, "name": "The Octocat", "username": "octocat",
    "avatar_url": "", "web_url": "http://localhost/octocat"
  },
  "project": {
    "id": 10, "name": "hello-world",
    "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20, "default_branch": "main"
  },
  "object_attributes": {
    "id": 5,
    "title": "enhancement",
    "color": "#84b6eb",
    "description": "New feature or request",
    "action": "create",
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T10:00:00Z"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Label Hook: edited → 200 ──────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Label Hook
{
  "object_kind": "label",
  "user": {
    "id": 1, "name": "The Octocat", "username": "octocat",
    "avatar_url": "", "web_url": "http://localhost/octocat"
  },
  "project": {
    "id": 10, "name": "hello-world",
    "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20, "default_branch": "main"
  },
  "object_attributes": {
    "id": 5, "title": "enhancement", "color": "#0075ca",
    "description": "New feature or request", "action": "update",
    "created_at": "2024-01-15T10:00:00Z", "updated_at": "2024-01-15T10:01:00Z"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Milestone Hook: created → 200 ─────────────────────────────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Milestone Hook
{
  "object_kind": "milestone",
  "action": "create",
  "user": {
    "id": 1, "name": "The Octocat", "username": "octocat",
    "avatar_url": "", "web_url": "http://localhost/octocat"
  },
  "project": {
    "id": 10, "name": "hello-world",
    "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20, "default_branch": "main"
  },
  "object_attributes": {
    "id": 3,
    "iid": 1,
    "title": "v2.0",
    "description": "Second major release",
    "state": "active",
    "due_date": "2024-06-01",
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T10:00:00Z",
    "closed_at": null
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Milestone Hook: closed → 200 ──────────────────────────────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Milestone Hook
{
  "object_kind": "milestone",
  "user": {
    "id": 1, "name": "The Octocat", "username": "octocat",
    "avatar_url": "", "web_url": "http://localhost/octocat"
  },
  "project": {
    "id": 10, "name": "hello-world",
    "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20, "default_branch": "main"
  },
  "object_attributes": {
    "id": 3, "iid": 1, "title": "v2.0",
    "description": "Second major release", "state": "closed", "action": "close",
    "due_date": "2024-06-01",
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-06-01T10:00:00Z",
    "closed_at": "2024-06-01T10:00:00Z"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Merge Request Hook: opened → 200 ──────────────────────────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Merge Request Hook
{
  "object_kind": "merge_request",
  "event_type": "merge_request",
  "user": {
    "id": 2,
    "name": "Bob",
    "username": "bob",
    "avatar_url": "",
    "web_url": "http://localhost/bob"
  },
  "project": {
    "id": 10,
    "name": "hello-world",
    "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20,
    "default_branch": "main"
  },
  "object_attributes": {
    "id": 500,
    "iid": 7,
    "title": "Add new feature",
    "description": "This MR adds a new feature.",
    "state": "opened",
    "action": "open",
    "source_branch": "feature-branch",
    "target_branch": "main",
    "last_commit": {"id": "abc123"},
    "diff_refs": {"base_sha": "def456", "head_sha": "abc123", "start_sha": "def456"},
    "draft": false,
    "merge_status": "can_be_merged",
    "url": "http://localhost/octocat/hello-world/-/merge_requests/7",
    "merge_commit_sha": null,
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T10:00:00Z",
    "closed_at": null,
    "merged_at": null
  },
  "labels": [],
  "assignees": [],
  "reviewers": [],
  "changes": {}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Merge Request Hook: update with new commit → synchronize ──────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Merge Request Hook
{
  "object_kind": "merge_request",
  "event_type": "merge_request",
  "user": {
    "id": 2, "name": "Bob", "username": "bob",
    "avatar_url": "", "web_url": "http://localhost/bob"
  },
  "project": {
    "id": 10, "name": "hello-world",
    "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20, "default_branch": "main"
  },
  "object_attributes": {
    "id": 500, "iid": 7, "title": "Add new feature",
    "description": "This MR adds a new feature.",
    "state": "opened", "action": "update",
    "source_branch": "feature-branch", "target_branch": "main",
    "last_commit": {"id": "ghi789"},
    "diff_refs": {"base_sha": "def456", "head_sha": "ghi789", "start_sha": "def456"},
    "draft": false, "merge_status": "can_be_merged",
    "url": "http://localhost/octocat/hello-world/-/merge_requests/7",
    "merge_commit_sha": null,
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T10:05:00Z",
    "closed_at": null, "merged_at": null
  },
  "labels": [], "assignees": [], "reviewers": [],
  "changes": {
    "last_commit": {
      "previous": {"id": "abc123"},
      "current": {"id": "ghi789"}
    }
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Merge Request Hook: merge → closed ────────────────────────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Merge Request Hook
{
  "object_kind": "merge_request",
  "event_type": "merge_request",
  "user": {
    "id": 1, "name": "The Octocat", "username": "octocat",
    "avatar_url": "", "web_url": "http://localhost/octocat"
  },
  "project": {
    "id": 10, "name": "hello-world",
    "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20, "default_branch": "main"
  },
  "object_attributes": {
    "id": 500, "iid": 7, "title": "Add new feature",
    "description": "This MR adds a new feature.",
    "state": "merged", "action": "merge",
    "source_branch": "feature-branch", "target_branch": "main",
    "last_commit": {"id": "ghi789"},
    "diff_refs": {"base_sha": "def456", "head_sha": "ghi789", "start_sha": "def456"},
    "draft": false, "merge_status": "can_be_merged",
    "url": "http://localhost/octocat/hello-world/-/merge_requests/7",
    "merge_commit_sha": "jkl012",
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-16T09:00:00Z",
    "closed_at": "2024-01-16T09:00:00Z",
    "merged_at": "2024-01-16T09:00:00Z"
  },
  "labels": [], "assignees": [], "reviewers": [],
  "changes": {}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Merge Request Hook: update with label change → labeled ────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Merge Request Hook
{
  "object_kind": "merge_request",
  "event_type": "merge_request",
  "user": {
    "id": 1, "name": "The Octocat", "username": "octocat",
    "avatar_url": "", "web_url": "http://localhost/octocat"
  },
  "project": {
    "id": 10, "name": "hello-world",
    "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20, "default_branch": "main"
  },
  "object_attributes": {
    "id": 500, "iid": 7, "title": "Add new feature", "description": null,
    "state": "opened", "action": "update",
    "source_branch": "feature-branch", "target_branch": "main",
    "last_commit": {"id": "abc123"},
    "diff_refs": {"base_sha": "def456", "head_sha": "abc123", "start_sha": "def456"},
    "draft": false, "merge_status": "can_be_merged",
    "url": "http://localhost/octocat/hello-world/-/merge_requests/7",
    "merge_commit_sha": null,
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T10:02:00Z",
    "closed_at": null, "merged_at": null
  },
  "labels": [{"id": 5, "title": "bug", "color": "#d73a4a", "description": ""}],
  "assignees": [], "reviewers": [],
  "changes": {
    "labels": {
      "previous": [],
      "current": [{"id": 5, "title": "bug", "color": "#d73a4a", "description": ""}]
    }
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Merge Request Hook: update with reviewer → review_requested ───────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Merge Request Hook
{
  "object_kind": "merge_request",
  "event_type": "merge_request",
  "user": {
    "id": 1, "name": "The Octocat", "username": "octocat",
    "avatar_url": "", "web_url": "http://localhost/octocat"
  },
  "project": {
    "id": 10, "name": "hello-world",
    "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20, "default_branch": "main"
  },
  "object_attributes": {
    "id": 500, "iid": 7, "title": "Add new feature", "description": null,
    "state": "opened", "action": "update",
    "source_branch": "feature-branch", "target_branch": "main",
    "last_commit": {"id": "abc123"},
    "diff_refs": {"base_sha": "def456", "head_sha": "abc123", "start_sha": "def456"},
    "draft": false, "merge_status": "can_be_merged",
    "url": "http://localhost/octocat/hello-world/-/merge_requests/7",
    "merge_commit_sha": null,
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T10:03:00Z",
    "closed_at": null, "merged_at": null
  },
  "labels": [], "assignees": [],
  "reviewers": [{"id": 3, "name": "Carol", "username": "carol", "avatar_url": "", "web_url": "http://localhost/carol"}],
  "changes": {
    "reviewers": {
      "previous": [],
      "current": [{"id": 3, "name": "Carol", "username": "carol", "avatar_url": "", "web_url": "http://localhost/carol"}]
    }
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Merge Request Hook: approved → pull_request_review: submitted (APPROVED) ──

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Merge Request Hook
{
  "object_kind": "merge_request",
  "event_type": "merge_request",
  "user": {
    "id": 3, "name": "Carol", "username": "carol",
    "avatar_url": "", "web_url": "http://localhost/carol"
  },
  "project": {
    "id": 10, "name": "hello-world",
    "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20, "default_branch": "main"
  },
  "object_attributes": {
    "id": 500, "iid": 7, "title": "Add new feature", "description": null,
    "state": "opened", "action": "approved",
    "source_branch": "feature-branch", "target_branch": "main",
    "last_commit": {"id": "abc123"},
    "diff_refs": {"base_sha": "def456", "head_sha": "abc123", "start_sha": "def456"},
    "draft": false, "merge_status": "can_be_merged",
    "url": "http://localhost/octocat/hello-world/-/merge_requests/7",
    "merge_commit_sha": null,
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T10:05:00Z",
    "closed_at": null, "merged_at": null
  },
  "labels": [], "assignees": [], "reviewers": [],
  "changes": {}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Merge Request Hook: unapproved → pull_request_review: dismissed ───────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Merge Request Hook
{
  "object_kind": "merge_request",
  "event_type": "merge_request",
  "user": {
    "id": 3, "name": "Carol", "username": "carol",
    "avatar_url": "", "web_url": "http://localhost/carol"
  },
  "project": {
    "id": 10, "name": "hello-world",
    "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20, "default_branch": "main"
  },
  "object_attributes": {
    "id": 500, "iid": 7, "title": "Add new feature", "description": null,
    "state": "opened", "action": "unapproved",
    "source_branch": "feature-branch", "target_branch": "main",
    "last_commit": {"id": "abc123"},
    "diff_refs": {"base_sha": "def456", "head_sha": "abc123", "start_sha": "def456"},
    "draft": false, "merge_status": "can_be_merged",
    "url": "http://localhost/octocat/hello-world/-/merge_requests/7",
    "merge_commit_sha": null,
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T10:06:00Z",
    "closed_at": null, "merged_at": null
  },
  "labels": [], "assignees": [], "reviewers": [],
  "changes": {}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Merge Request Hook: unknown action → 200 + X-Confusio-Raw-Action ─────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Merge Request Hook
{
  "object_kind": "merge_request",
  "event_type": "merge_request",
  "user": {
    "id": 1, "name": "The Octocat", "username": "octocat",
    "avatar_url": "", "web_url": "http://localhost/octocat"
  },
  "project": {
    "id": 10, "name": "hello-world",
    "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20, "default_branch": "main"
  },
  "object_attributes": {
    "id": 500, "iid": 7, "title": "Add new feature", "description": null,
    "state": "opened", "action": "approval_rules_updated",
    "source_branch": "feature-branch", "target_branch": "main",
    "last_commit": {"id": "abc123"},
    "diff_refs": {"base_sha": "def456", "head_sha": "abc123", "start_sha": "def456"},
    "draft": false, "merge_status": "can_be_merged",
    "url": "http://localhost/octocat/hello-world/-/merge_requests/7",
    "merge_commit_sha": null,
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T10:04:00Z",
    "closed_at": null, "merged_at": null
  },
  "labels": [], "assignees": [], "reviewers": [],
  "changes": {}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"
header "X-Confusio-Raw-Action" == "approval_rules_updated"

# ── Pipeline Hook: completed/success → 200 ────────────────────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Pipeline Hook
{
  "object_kind": "pipeline",
  "object_attributes": {
    "id": 31, "iid": 10,
    "ref": "main", "tag": false,
    "sha": "abc123def456abc123def456abc123def456abc123",
    "before_sha": "def456",
    "source": "push",
    "status": "success",
    "detailed_status": "passed",
    "stages": ["build", "test"],
    "created_at": "2024-01-15T10:00:00Z",
    "started_at": "2024-01-15T10:01:00Z",
    "finished_at": "2024-01-15T10:05:00Z",
    "updated_at": "2024-01-15T10:05:00Z",
    "duration": 240, "queued_duration": 10,
    "variables": [],
    "url": "http://localhost/octocat/hello-world/-/pipelines/31"
  },
  "merge_request": null,
  "user": {
    "id": 1, "name": "The Octocat", "username": "octocat",
    "avatar_url": "", "web_url": "http://localhost/octocat"
  },
  "project": {
    "id": 10, "name": "hello-world",
    "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20, "default_branch": "main"
  },
  "commit": {
    "id": "abc123def456abc123def456abc123def456abc123",
    "message": "Update readme\n", "title": "Update readme",
    "timestamp": "2024-01-15T09:59:00Z",
    "url": "http://localhost/octocat/hello-world/-/commit/abc123def456",
    "author": {"name": "The Octocat", "email": "octocat@example.com"}
  },
  "source_pipeline": null
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Pipeline Hook: running → 200 ──────────────────────────────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Pipeline Hook
{
  "object_kind": "pipeline",
  "object_attributes": {
    "id": 32, "iid": 11,
    "ref": "feature", "tag": false,
    "sha": "deadbeefdeadbeef",
    "before_sha": "000000",
    "source": "push",
    "status": "running",
    "detailed_status": "running",
    "stages": ["build"],
    "created_at": "2024-01-15T11:00:00Z",
    "started_at": "2024-01-15T11:01:00Z",
    "finished_at": null,
    "updated_at": "2024-01-15T11:01:00Z",
    "duration": null, "queued_duration": 5,
    "variables": [],
    "url": "http://localhost/octocat/hello-world/-/pipelines/32"
  },
  "merge_request": null,
  "user": {
    "id": 2, "name": "Bob", "username": "bob",
    "avatar_url": "", "web_url": "http://localhost/bob"
  },
  "project": {
    "id": 10, "name": "hello-world",
    "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20, "default_branch": "main"
  },
  "commit": {
    "id": "deadbeefdeadbeef", "message": "Add feature", "title": "Add feature",
    "timestamp": "2024-01-15T10:59:00Z",
    "url": "", "author": {"name": "Bob", "email": "bob@example.com"}
  },
  "source_pipeline": null
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Pipeline Hook: pending → 200 ──────────────────────────────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Pipeline Hook
{
  "object_kind": "pipeline",
  "object_attributes": {
    "id": 33, "iid": 12,
    "ref": "main", "tag": false,
    "sha": "cafebabe",
    "before_sha": "000000",
    "source": "web",
    "status": "pending",
    "detailed_status": "pending",
    "stages": ["build"],
    "created_at": "2024-01-15T12:00:00Z",
    "started_at": null,
    "finished_at": null,
    "updated_at": "2024-01-15T12:00:00Z",
    "duration": null, "queued_duration": null,
    "variables": [],
    "url": "http://localhost/octocat/hello-world/-/pipelines/33"
  },
  "merge_request": null,
  "user": {
    "id": 1, "name": "The Octocat", "username": "octocat",
    "avatar_url": "", "web_url": "http://localhost/octocat"
  },
  "project": {
    "id": 10, "name": "hello-world",
    "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20, "default_branch": "main"
  },
  "commit": {
    "id": "cafebabe", "message": "Manual trigger", "title": "Manual trigger",
    "timestamp": "2024-01-15T11:59:00Z",
    "url": "", "author": {"name": "The Octocat", "email": "octocat@example.com"}
  },
  "source_pipeline": null
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Pipeline Hook: unknown status → 200 + X-Confusio-Raw-Action ───────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Pipeline Hook
{
  "object_kind": "pipeline",
  "object_attributes": {
    "id": 34, "iid": 13,
    "ref": "main", "tag": false,
    "sha": "abc123",
    "before_sha": "000000",
    "source": "push",
    "status": "blocked",
    "detailed_status": "blocked",
    "stages": [],
    "created_at": "2024-01-15T13:00:00Z",
    "started_at": null, "finished_at": null,
    "updated_at": "2024-01-15T13:00:00Z",
    "duration": null, "queued_duration": null,
    "variables": [],
    "url": "http://localhost/octocat/hello-world/-/pipelines/34"
  },
  "merge_request": null,
  "user": {
    "id": 1, "name": "The Octocat", "username": "octocat",
    "avatar_url": "", "web_url": "http://localhost/octocat"
  },
  "project": {
    "id": 10, "name": "hello-world",
    "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20, "default_branch": "main"
  },
  "commit": {
    "id": "abc123", "message": "Blocked run", "title": "Blocked run",
    "timestamp": "2024-01-15T12:59:00Z",
    "url": "", "author": {"name": "The Octocat", "email": "octocat@example.com"}
  },
  "source_pipeline": null
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"
header "X-Confusio-Raw-Action" == "blocked"

# ── Job Hook: completed/success → 200 ────────────────────────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Job Hook
{
  "object_kind": "build",
  "ref": "main", "tag": false,
  "before_sha": "def456",
  "sha": "abc123def456abc123def456abc123def456abc123",
  "build_id": 456, "build_name": "build-job", "build_stage": "build",
  "build_status": "success",
  "build_allow_failure": false,
  "build_created_at": "2024-01-15T10:01:00Z",
  "build_started_at": "2024-01-15T10:02:00Z",
  "build_finished_at": "2024-01-15T10:04:00Z",
  "build_duration": 120.5, "build_queued_duration": 5.2,
  "build_failure_reason": null,
  "pipeline_id": 31,
  "runner": {
    "id": 1, "description": "runner-1",
    "runner_type": "instance_type", "tags": ["ubuntu-latest"]
  },
  "project_id": 10,
  "project_name": "The Octocat / hello-world",
  "user": {
    "id": 1, "name": "The Octocat", "username": "octocat",
    "avatar_url": "", "web_url": "http://localhost/octocat"
  },
  "commit": {
    "id": 31, "sha": "abc123def456abc123def456abc123def456abc123",
    "message": "Update readme", "author_name": "The Octocat",
    "author_email": "octocat@example.com",
    "status": "success", "duration": 240,
    "started_at": "2024-01-15T10:01:00Z",
    "finished_at": "2024-01-15T10:05:00Z"
  },
  "repository": {
    "name": "hello-world",
    "url": "git@localhost:octocat/hello-world.git",
    "description": "",
    "homepage": "http://localhost/octocat/hello-world"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Job Hook: running → 200 ───────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Job Hook
{
  "object_kind": "build",
  "ref": "feature", "tag": false,
  "before_sha": "000000",
  "sha": "deadbeef",
  "build_id": 457, "build_name": "test-job", "build_stage": "test",
  "build_status": "running",
  "build_allow_failure": false,
  "build_created_at": "2024-01-15T11:01:00Z",
  "build_started_at": "2024-01-15T11:02:00Z",
  "build_finished_at": null,
  "build_duration": null, "build_queued_duration": 3.0,
  "build_failure_reason": null,
  "pipeline_id": 32,
  "runner": {
    "id": 2, "description": "runner-2",
    "runner_type": "instance_type", "tags": []
  },
  "project_id": 10,
  "project_name": "The Octocat / hello-world",
  "user": {
    "id": 2, "name": "Bob", "username": "bob",
    "avatar_url": "", "web_url": "http://localhost/bob"
  },
  "commit": {
    "id": 32, "sha": "deadbeef",
    "message": "Add feature", "author_name": "Bob",
    "author_email": "bob@example.com",
    "status": "running", "duration": null,
    "started_at": "2024-01-15T11:01:00Z", "finished_at": null
  },
  "repository": {
    "name": "hello-world",
    "url": "git@localhost:octocat/hello-world.git",
    "description": "",
    "homepage": "http://localhost/octocat/hello-world"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Job Hook: pending → 200 ───────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Job Hook
{
  "object_kind": "build",
  "ref": "main", "tag": false,
  "before_sha": "000000",
  "sha": "cafebabe",
  "build_id": 458, "build_name": "deploy-job", "build_stage": "deploy",
  "build_status": "pending",
  "build_allow_failure": false,
  "build_created_at": "2024-01-15T12:01:00Z",
  "build_started_at": null,
  "build_finished_at": null,
  "build_duration": null, "build_queued_duration": null,
  "build_failure_reason": null,
  "pipeline_id": 33,
  "runner": null,
  "project_id": 10,
  "project_name": "The Octocat / hello-world",
  "user": {
    "id": 1, "name": "The Octocat", "username": "octocat",
    "avatar_url": "", "web_url": "http://localhost/octocat"
  },
  "commit": {
    "id": 33, "sha": "cafebabe",
    "message": "Deploy", "author_name": "The Octocat",
    "author_email": "octocat@example.com",
    "status": "pending", "duration": null,
    "started_at": null, "finished_at": null
  },
  "repository": {
    "name": "hello-world",
    "url": "git@localhost:octocat/hello-world.git",
    "description": "",
    "homepage": "http://localhost/octocat/hello-world"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Job Hook: unknown status → 200 + X-Confusio-Raw-Action ───────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Job Hook
{
  "object_kind": "build",
  "ref": "main", "tag": false,
  "before_sha": "000000",
  "sha": "abc123",
  "build_id": 459, "build_name": "lint-job", "build_stage": "lint",
  "build_status": "stale",
  "build_allow_failure": true,
  "build_created_at": "2024-01-15T13:01:00Z",
  "build_started_at": null,
  "build_finished_at": null,
  "build_duration": null, "build_queued_duration": null,
  "build_failure_reason": null,
  "pipeline_id": 34,
  "runner": null,
  "project_id": 10,
  "project_name": "The Octocat / hello-world",
  "user": {
    "id": 1, "name": "The Octocat", "username": "octocat",
    "avatar_url": "", "web_url": "http://localhost/octocat"
  },
  "commit": {
    "id": 34, "sha": "abc123",
    "message": "Lint check", "author_name": "The Octocat",
    "author_email": "octocat@example.com",
    "status": "stale", "duration": null,
    "started_at": null, "finished_at": null
  },
  "repository": {
    "name": "hello-world",
    "url": "git@localhost:octocat/hello-world.git",
    "description": "",
    "homepage": "http://localhost/octocat/hello-world"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"
header "X-Confusio-Raw-Action" == "stale"

# ── Project Hook: project_create → repository created ────────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Project Hook
{
  "event_name": "project_create",
  "created_at": "2024-10-07T10:43:48Z",
  "updated_at": "2024-10-07T10:43:48Z",
  "name": "hello-world",
  "path": "hello-world",
  "path_with_namespace": "octocat/hello-world",
  "project_id": 22,
  "project_namespace_id": 32,
  "owners": [{"name": "Alice Smith", "email": "alice@example.com"}],
  "project_visibility": "private"
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Project Hook: project_destroy → repository deleted ───────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Project Hook
{
  "event_name": "project_destroy",
  "created_at": "2024-10-07T10:43:48Z",
  "updated_at": "2024-10-07T10:43:48Z",
  "name": "hello-world",
  "path": "hello-world",
  "path_with_namespace": "octocat/hello-world",
  "project_id": 22,
  "project_namespace_id": 32,
  "owners": [{"name": "Alice Smith", "email": "alice@example.com"}],
  "project_visibility": "private"
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Subgroup Hook: subgroup_create → organization created ────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Subgroup Hook
{
  "event_name": "subgroup_create",
  "created_at": "2021-01-20T09:40:12Z",
  "updated_at": "2021-01-20T09:40:12Z",
  "name": "subgroup1",
  "path": "subgroup1",
  "full_path": "group1/subgroup1",
  "group_id": 10,
  "parent_group_id": 7,
  "parent_name": "group1",
  "parent_path": "group1",
  "parent_full_path": "group1"
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Subgroup Hook: subgroup_destroy → organization deleted ───────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Subgroup Hook
{
  "event_name": "subgroup_destroy",
  "created_at": "2021-01-20T09:40:12Z",
  "updated_at": "2021-01-20T09:40:12Z",
  "name": "subgroup1",
  "path": "subgroup1",
  "full_path": "group1/subgroup1",
  "group_id": 10,
  "parent_group_id": 7,
  "parent_name": "group1",
  "parent_path": "group1",
  "parent_full_path": "group1"
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Member Hook: user_add_to_group → membership added ────────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Member Hook
{
  "created_at": "2020-12-11T04:57:22Z",
  "updated_at": "2020-12-11T04:57:22Z",
  "group_name": "Engineering",
  "group_path": "engineering",
  "group_id": 100,
  "user_username": "bob",
  "user_name": "Bob Smith",
  "user_email": "bob@example.com",
  "user_id": 64,
  "group_access": "Guest",
  "group_plan": null,
  "expires_at": "2020-12-14T00:00:00Z",
  "event_name": "user_add_to_group"
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Member Hook: user_update_for_team → member edited ────────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Member Hook
{
  "created_at": "2012-07-21T07:30:56Z",
  "updated_at": "2012-07-21T07:38:22Z",
  "event_name": "user_update_for_team",
  "access_level": "Maintainer",
  "project_id": 74,
  "project_name": "hello-world",
  "project_path": "hello-world",
  "project_path_with_namespace": "octocat/hello-world",
  "project_visibility": "private",
  "user_email": "bob@example.com",
  "user_name": "Bob Smith",
  "user_username": "bob",
  "user_id": 64
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Push Hook: branch push with commits → 200 (push event) ───────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Push Hook
{
  "object_kind": "push",
  "event_name": "push",
  "before": "95790bf891e76fee5db5ef17d2523a6f6e048239",
  "after":  "da1560886d4f094c3e6c9ef40349f7d38b5d27d0",
  "ref": "refs/heads/main",
  "checkout_sha": "da1560886d4f094c3e6c9ef40349f7d38b5d27d0",
  "user_id": 4,
  "user_name": "Alice Smith",
  "user_username": "alice",
  "user_email": "alice@example.com",
  "user_avatar": "",
  "project_id": 15,
  "project": {
    "id": 15, "name": "hello-world", "description": "My first repo",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "namespace": "octocat", "visibility_level": 20,
    "path_with_namespace": "octocat/hello-world",
    "default_branch": "main",
    "homepage": "http://localhost/octocat/hello-world"
  },
  "commits": [
    {
      "id": "da1560886d4f094c3e6c9ef40349f7d38b5d27d0",
      "message": "Fix login bug",
      "timestamp": "2024-01-15T10:00:00+00:00",
      "url": "http://localhost/octocat/hello-world/commit/da1560886d4f094c3e6c9ef40349f7d38b5d27d0",
      "author": {"name": "Alice Smith", "email": "alice@example.com"},
      "added": [], "modified": ["README.md"], "removed": []
    }
  ],
  "total_commits_count": 1,
  "repository": {
    "name": "hello-world",
    "url": "git@localhost:octocat/hello-world.git",
    "description": "My first repo",
    "homepage": "http://localhost/octocat/hello-world"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Push Hook: before = zero SHA → 200 (create event, branch created) ─────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Push Hook
{
  "object_kind": "push",
  "event_name": "push",
  "before": "0000000000000000000000000000000000000000",
  "after":  "da1560886d4f094c3e6c9ef40349f7d38b5d27d0",
  "ref": "refs/heads/feature-branch",
  "checkout_sha": "da1560886d4f094c3e6c9ef40349f7d38b5d27d0",
  "user_id": 5,
  "user_name": "Bob Jones",
  "user_username": "bob",
  "user_email": "bob@example.com",
  "user_avatar": "",
  "project_id": 15,
  "project": {
    "id": 15, "name": "hello-world", "description": "My first repo",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "namespace": "octocat", "visibility_level": 20,
    "path_with_namespace": "octocat/hello-world",
    "default_branch": "main",
    "homepage": "http://localhost/octocat/hello-world"
  },
  "commits": [],
  "total_commits_count": 0,
  "repository": {
    "name": "hello-world",
    "url": "git@localhost:octocat/hello-world.git",
    "description": "My first repo",
    "homepage": "http://localhost/octocat/hello-world"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Push Hook: after = zero SHA → 200 (delete event, branch deleted) ──────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Push Hook
{
  "object_kind": "push",
  "event_name": "push",
  "before": "95790bf891e76fee5db5ef17d2523a6f6e048239",
  "after":  "0000000000000000000000000000000000000000",
  "ref": "refs/heads/stale-branch",
  "checkout_sha": null,
  "user_id": 5,
  "user_name": "Bob Jones",
  "user_username": "bob",
  "user_email": "bob@example.com",
  "user_avatar": "",
  "project_id": 15,
  "project": {
    "id": 15, "name": "hello-world", "description": "My first repo",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "namespace": "octocat", "visibility_level": 20,
    "path_with_namespace": "octocat/hello-world",
    "default_branch": "main",
    "homepage": "http://localhost/octocat/hello-world"
  },
  "commits": [],
  "total_commits_count": 0,
  "repository": {
    "name": "hello-world",
    "url": "git@localhost:octocat/hello-world.git",
    "description": "My first repo",
    "homepage": "http://localhost/octocat/hello-world"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Release Hook: create → published ──────────────────────────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Release Hook
{
  "object_kind": "release",
  "id": 1,
  "created_at": "2024-01-15T10:00:00Z",
  "description": "First release",
  "name": "Release 1.0.0",
  "released_at": "2024-01-15T10:00:00Z",
  "tag": "v1.0.0",
  "url": "http://localhost/octocat/hello-world/-/releases/v1.0.0",
  "action": "create",
  "project": {
    "id": 10, "name": "hello-world", "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20, "default_branch": "main"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Release Hook: update → edited ─────────────────────────────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Release Hook
{
  "object_kind": "release",
  "id": 1,
  "created_at": "2024-01-15T10:00:00Z",
  "description": "First release (updated)",
  "name": "Release 1.0.0",
  "released_at": "2024-01-15T10:00:00Z",
  "tag": "v1.0.0",
  "url": "http://localhost/octocat/hello-world/-/releases/v1.0.0",
  "action": "update",
  "project": {
    "id": 10, "name": "hello-world", "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20, "default_branch": "main"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Release Hook: delete → deleted ────────────────────────────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Release Hook
{
  "object_kind": "release",
  "id": 1,
  "created_at": "2024-01-15T10:00:00Z",
  "description": "First release",
  "name": "Release 1.0.0",
  "released_at": "2024-01-15T10:00:00Z",
  "tag": "v1.0.0",
  "url": "http://localhost/octocat/hello-world/-/releases/v1.0.0",
  "action": "delete",
  "project": {
    "id": 10, "name": "hello-world", "path_with_namespace": "octocat/hello-world",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "visibility_level": 20, "default_branch": "main"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Tag Push Hook: before = zero SHA → 200 (create event, tag created) ───────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Tag Push Hook
{
  "object_kind": "tag_push",
  "event_name": "tag_push",
  "before": "0000000000000000000000000000000000000000",
  "after":  "da1560886d4f094c3e6c9ef40349f7d38b5d27d0",
  "ref": "refs/tags/v1.0.0",
  "checkout_sha": "da1560886d4f094c3e6c9ef40349f7d38b5d27d0",
  "user_id": 4,
  "user_name": "Alice Smith",
  "user_username": "alice",
  "user_email": "alice@example.com",
  "user_avatar": "",
  "project_id": 15,
  "project": {
    "id": 15, "name": "hello-world", "description": "My first repo",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "namespace": "octocat", "visibility_level": 20,
    "path_with_namespace": "octocat/hello-world",
    "default_branch": "main",
    "homepage": "http://localhost/octocat/hello-world"
  },
  "commits": [],
  "total_commits_count": 0,
  "repository": {
    "name": "hello-world",
    "url": "git@localhost:octocat/hello-world.git",
    "description": "My first repo",
    "homepage": "http://localhost/octocat/hello-world"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Tag Push Hook: after = zero SHA → 200 (delete event, tag deleted) ─────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Tag Push Hook
{
  "object_kind": "tag_push",
  "event_name": "tag_push",
  "before": "da1560886d4f094c3e6c9ef40349f7d38b5d27d0",
  "after":  "0000000000000000000000000000000000000000",
  "ref": "refs/tags/v0.9.0",
  "checkout_sha": null,
  "user_id": 4,
  "user_name": "Alice Smith",
  "user_username": "alice",
  "user_email": "alice@example.com",
  "user_avatar": "",
  "project_id": 15,
  "project": {
    "id": 15, "name": "hello-world", "description": "My first repo",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "namespace": "octocat", "visibility_level": 20,
    "path_with_namespace": "octocat/hello-world",
    "default_branch": "main",
    "homepage": "http://localhost/octocat/hello-world"
  },
  "commits": [],
  "total_commits_count": 0,
  "repository": {
    "name": "hello-world",
    "url": "git@localhost:octocat/hello-world.git",
    "description": "My first repo",
    "homepage": "http://localhost/octocat/hello-world"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Wiki Page Hook: create → gollum page created ──────────────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Wiki Page Hook
{
  "object_kind": "wiki_page",
  "user": {
    "id": 4, "name": "Alice Smith", "username": "alice",
    "avatar_url": "", "web_url": "http://localhost/alice"
  },
  "project": {
    "id": 15, "name": "hello-world", "description": "My first repo",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "namespace": "octocat", "visibility_level": 20,
    "path_with_namespace": "octocat/hello-world",
    "default_branch": "main"
  },
  "object_attributes": {
    "title": "Home",
    "slug": "home",
    "url": "http://localhost/octocat/hello-world/-/wikis/home",
    "version_id": "abc123",
    "message": "Create Home",
    "action": "create"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Wiki Page Hook: update → gollum page edited ───────────────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Wiki Page Hook
{
  "object_kind": "wiki_page",
  "user": {
    "id": 4, "name": "Alice Smith", "username": "alice",
    "avatar_url": "", "web_url": "http://localhost/alice"
  },
  "project": {
    "id": 15, "name": "hello-world", "description": "My first repo",
    "web_url": "http://localhost/octocat/hello-world",
    "git_ssh_url": "git@localhost:octocat/hello-world.git",
    "git_http_url": "http://localhost/octocat/hello-world.git",
    "namespace": "octocat", "visibility_level": 20,
    "path_with_namespace": "octocat/hello-world",
    "default_branch": "main"
  },
  "object_attributes": {
    "title": "Home",
    "slug": "home",
    "url": "http://localhost/octocat/hello-world/-/wikis/home",
    "version_id": "def456",
    "message": "Update Home",
    "action": "update"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"
