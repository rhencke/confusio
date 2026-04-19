# GitLab webhook normalizer tests.
#
# Exercises the four event families registered in backends/gitlab.lua.
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
