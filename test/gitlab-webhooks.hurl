# GitLab webhook normalizer tests.
#
# Exercises the five event families registered in backends/gitlab.lua.
# Trust-the-network mode (no CONFUSIO_WEBHOOK_SECRETS): signature headers omitted.
# All paths return 200 when a registered handler succeeds.

# ── Issues Hook: opened → 200 ─────────────────────────────────────────────────

POST http://{{host}}/webhooks/gitlab
Content-Type: application/json
X-Gitlab-Event: Issues Hook
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
    "action": "create",
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
    "state": "opened", "action": "attention_required",
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
header "X-Confusio-Raw-Action" == "attention_required"

# ── Merge Request Hook: approved → pull_request_review submitted/approved ──────

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
    "updated_at": "2024-01-15T12:00:00Z",
    "closed_at": null, "merged_at": null
  },
  "labels": [], "assignees": [], "reviewers": [],
  "changes": {}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Merge Request Hook: unapproved → pull_request_review dismissed ────────────

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
    "updated_at": "2024-01-15T12:05:00Z",
    "closed_at": null, "merged_at": null
  },
  "labels": [], "assignees": [], "reviewers": [],
  "changes": {}
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Note Hook: DiffNote on MR (created) → pull_request_review_comment ─────────

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
    "id": 200,
    "note": "Nice change here.",
    "noteable_type": "MergeRequest",
    "type": "DiffNote",
    "action": "create",
    "discussion_id": "87805b7c09016a7058e91bdbe7b29d1f284a39e5",
    "position": {
      "base_sha": "def456",
      "start_sha": "def456",
      "head_sha": "abc123",
      "old_path": "README.md",
      "new_path": "README.md",
      "position_type": "text",
      "old_line": null,
      "new_line": 5
    },
    "url": "http://localhost/octocat/hello-world/-/merge_requests/7#note_200",
    "created_at": "2024-01-15T12:10:00Z",
    "updated_at": "2024-01-15T12:10:00Z"
  },
  "merge_request": {
    "id": 500, "iid": 7,
    "title": "Add new feature",
    "description": null,
    "state": "opened",
    "source_branch": "feature-branch",
    "target_branch": "main",
    "draft": false,
    "merge_status": "can_be_merged",
    "diff_refs": {"base_sha": "def456", "head_sha": "abc123", "start_sha": "def456"},
    "web_url": "http://localhost/octocat/hello-world/-/merge_requests/7",
    "author": {
      "id": 2, "name": "Bob", "username": "bob",
      "avatar_url": "", "web_url": "http://localhost/bob"
    }
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Note Hook: DiffNote on MR (deleted) → pull_request_review_comment ─────────

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
    "id": 200, "note": "Nice change here.",
    "noteable_type": "MergeRequest", "type": "DiffNote",
    "action": "destroy",
    "discussion_id": "87805b7c09016a7058e91bdbe7b29d1f284a39e5",
    "position": {
      "base_sha": "def456", "start_sha": "def456", "head_sha": "abc123",
      "old_path": "README.md", "new_path": "README.md",
      "position_type": "text", "old_line": null, "new_line": 5
    },
    "url": "http://localhost/octocat/hello-world/-/merge_requests/7#note_200",
    "created_at": "2024-01-15T12:10:00Z", "updated_at": "2024-01-15T12:11:00Z"
  },
  "merge_request": {
    "id": 500, "iid": 7, "title": "Add new feature", "description": null,
    "state": "opened", "source_branch": "feature-branch", "target_branch": "main",
    "draft": false, "merge_status": "can_be_merged",
    "diff_refs": {"base_sha": "def456", "head_sha": "abc123", "start_sha": "def456"},
    "web_url": "http://localhost/octocat/hello-world/-/merge_requests/7",
    "author": {
      "id": 2, "name": "Bob", "username": "bob",
      "avatar_url": "", "web_url": "http://localhost/bob"
    }
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── Note Hook: DiffNote on MR (unknown action) → 200 + X-Confusio-Raw-Action ──

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
    "id": 201, "note": "Resolved.",
    "noteable_type": "MergeRequest", "type": "DiffNote",
    "action": "resolved",
    "discussion_id": "87805b7c09016a7058e91bdbe7b29d1f284a39e5",
    "position": {
      "base_sha": "def456", "start_sha": "def456", "head_sha": "abc123",
      "old_path": "README.md", "new_path": "README.md",
      "position_type": "text", "old_line": null, "new_line": 5
    },
    "url": "http://localhost/octocat/hello-world/-/merge_requests/7#note_201",
    "created_at": "2024-01-15T12:10:00Z", "updated_at": "2024-01-15T12:12:00Z"
  },
  "merge_request": {
    "id": 500, "iid": 7, "title": "Add new feature", "description": null,
    "state": "opened", "source_branch": "feature-branch", "target_branch": "main",
    "draft": false, "merge_status": "can_be_merged",
    "diff_refs": {"base_sha": "def456", "head_sha": "abc123", "start_sha": "def456"},
    "web_url": "http://localhost/octocat/hello-world/-/merge_requests/7",
    "author": {
      "id": 2, "name": "Bob", "username": "bob",
      "avatar_url": "", "web_url": "http://localhost/bob"
    }
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"
header "X-Confusio-Raw-Action" == "resolved"
