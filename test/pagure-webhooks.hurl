# Pagure webhook normalizer tests — run by test-unit-pagure.
#
# Pagure uses X-Pagure-Event header.  Payload envelope: {topic, msg: {issue,
# project, agent, [comment]}}.
# Trust-the-network mode (no webhook_secret_BACKEND CLI arg): X-Pagure-Token omitted.

# ── issue.new → issues / opened ──────────────────────────────────────────────

POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Event: issue.new
{
  "topic": "issue.new",
  "msg": {
    "issue": {
      "id": 1,
      "title": "Found a bug",
      "content": "Something broke.",
      "status": "Open",
      "user": {"name": "alice", "fullname": "Alice", "url_path": "user/alice", "avatar_url": ""},
      "assignee": null,
      "tags": [],
      "date_created": "1705312800",
      "last_updated": "1705312800",
      "full_url": "octocat/hello-world/issue/1"
    },
    "project": {
      "id": 100,
      "name": "hello-world",
      "namespace": "octocat",
      "fullname": "octocat/hello-world",
      "url_path": "octocat/hello-world",
      "full_url": "http://localhost/octocat/hello-world",
      "private": false,
      "user": {"name": "octocat", "url_path": "user/octocat"}
    },
    "agent": "alice"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── issue.edit → issues / edited ─────────────────────────────────────────────

POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Event: issue.edit
{
  "topic": "issue.edit",
  "msg": {
    "issue": {
      "id": 1,
      "title": "Found a nasty bug",
      "content": "Something broke badly.",
      "status": "Open",
      "user": {"name": "alice", "fullname": "Alice", "url_path": "user/alice", "avatar_url": ""},
      "assignee": null,
      "tags": [],
      "date_created": "1705312800",
      "last_updated": "1705316400",
      "full_url": "octocat/hello-world/issue/1"
    },
    "project": {
      "id": 100,
      "name": "hello-world",
      "namespace": "octocat",
      "fullname": "octocat/hello-world",
      "url_path": "octocat/hello-world",
      "full_url": "http://localhost/octocat/hello-world",
      "private": false,
      "user": {"name": "octocat", "url_path": "user/octocat"}
    },
    "agent": "alice"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── issue.status.change (Open → Closed) → issues / closed ────────────────────

POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Event: issue.status.change
{
  "topic": "issue.status.change",
  "msg": {
    "issue": {
      "id": 1,
      "title": "Found a bug",
      "content": "Something broke.",
      "status": "Closed",
      "user": {"name": "alice", "fullname": "Alice", "url_path": "user/alice", "avatar_url": ""},
      "assignee": null,
      "tags": [],
      "date_created": "1705312800",
      "last_updated": "1705320000",
      "full_url": "octocat/hello-world/issue/1"
    },
    "project": {
      "id": 100,
      "name": "hello-world",
      "namespace": "octocat",
      "fullname": "octocat/hello-world",
      "url_path": "octocat/hello-world",
      "full_url": "http://localhost/octocat/hello-world",
      "private": false,
      "user": {"name": "octocat", "url_path": "user/octocat"}
    },
    "agent": "alice"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── issue.status.change (Closed → Open) → issues / reopened ──────────────────

POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Event: issue.status.change
{
  "topic": "issue.status.change",
  "msg": {
    "issue": {
      "id": 1,
      "title": "Found a bug",
      "content": "Something broke.",
      "status": "Open",
      "user": {"name": "alice", "fullname": "Alice", "url_path": "user/alice", "avatar_url": ""},
      "assignee": null,
      "tags": [],
      "date_created": "1705312800",
      "last_updated": "1705323600",
      "full_url": "octocat/hello-world/issue/1"
    },
    "project": {
      "id": 100,
      "name": "hello-world",
      "namespace": "octocat",
      "fullname": "octocat/hello-world",
      "url_path": "octocat/hello-world",
      "full_url": "http://localhost/octocat/hello-world",
      "private": false,
      "user": {"name": "octocat", "url_path": "user/octocat"}
    },
    "agent": "alice"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── issue.comment.added → issue_comment / created ────────────────────────────

POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Event: issue.comment.added
{
  "topic": "issue.comment.added",
  "msg": {
    "issue": {
      "id": 1,
      "title": "Found a bug",
      "content": "Something broke.",
      "status": "Open",
      "user": {"name": "alice", "fullname": "Alice", "url_path": "user/alice", "avatar_url": ""},
      "assignee": null,
      "tags": [],
      "date_created": "1705312800",
      "last_updated": "1705327200",
      "full_url": "octocat/hello-world/issue/1"
    },
    "comment": {
      "id": 42,
      "comment": "Confirmed, I can reproduce this.",
      "user": {"name": "bob", "fullname": "Bob", "url_path": "user/bob", "avatar_url": ""},
      "date_created": "1705327200"
    },
    "project": {
      "id": 100,
      "name": "hello-world",
      "namespace": "octocat",
      "fullname": "octocat/hello-world",
      "url_path": "octocat/hello-world",
      "full_url": "http://localhost/octocat/hello-world",
      "private": false,
      "user": {"name": "octocat", "url_path": "user/octocat"}
    },
    "agent": "bob"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pull-request.new → pull_request / opened ─────────────────────────────────

POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Event: pull-request.new
{
  "topic": "pull-request.new",
  "msg": {
    "pullrequest": {
      "id": 7,
      "title": "Add feature X",
      "initial_comment": "This PR adds feature X.",
      "status": "Open",
      "branch": "main",
      "branch_from": "feature-x",
      "repo_from": {
        "id": 101,
        "name": "hello-world",
        "fullname": "alice/hello-world"
      },
      "user": {"name": "alice", "fullname": "Alice", "url_path": "user/alice", "avatar_url": ""},
      "date_created": "1705312800",
      "last_updated": "1705312800",
      "commit_start": "abc123",
      "commit_stop": "def456",
      "full_url": "octocat/hello-world/pull-request/7"
    },
    "project": {
      "id": 100,
      "name": "hello-world",
      "namespace": "octocat",
      "fullname": "octocat/hello-world",
      "url_path": "octocat/hello-world",
      "full_url": "http://localhost/octocat/hello-world",
      "private": false,
      "user": {"name": "octocat", "url_path": "user/octocat"}
    },
    "agent": "alice"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pull-request.updated → pull_request / synchronize ────────────────────────

POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Event: pull-request.updated
{
  "topic": "pull-request.updated",
  "msg": {
    "pullrequest": {
      "id": 7,
      "title": "Add feature X",
      "initial_comment": "This PR adds feature X.",
      "status": "Open",
      "branch": "main",
      "branch_from": "feature-x",
      "repo_from": {
        "id": 101,
        "name": "hello-world",
        "fullname": "alice/hello-world"
      },
      "user": {"name": "alice", "fullname": "Alice", "url_path": "user/alice", "avatar_url": ""},
      "date_created": "1705312800",
      "last_updated": "1705316400",
      "commit_start": "abc123",
      "commit_stop": "ghi789",
      "full_url": "octocat/hello-world/pull-request/7"
    },
    "project": {
      "id": 100,
      "name": "hello-world",
      "namespace": "octocat",
      "fullname": "octocat/hello-world",
      "url_path": "octocat/hello-world",
      "full_url": "http://localhost/octocat/hello-world",
      "private": false,
      "user": {"name": "octocat", "url_path": "user/octocat"}
    },
    "agent": "alice"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── git.receive (regular push) → push / push ─────────────────────────────────

POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Event: git.receive
{
  "topic": "pagure.git.receive",
  "msg": {
    "agent": "bob",
    "repo": {
      "id": 100, "name": "hello-world", "namespace": "octocat",
      "fullname": "octocat/hello-world", "url_path": "octocat/hello-world",
      "full_url": "http://localhost/octocat/hello-world",
      "description": "My first repo", "default_branch": "main", "private": false,
      "user": {"name": "octocat", "url_path": "user/octocat"}
    },
    "branch": "refs/heads/main",
    "start_commit": "6dcb09b5b57875f334f61aebed695e2e4193db5e",
    "end_commit": "f1d2d2f924e986ac86fdf7b36c94bcdf32beec15",
    "forced": false,
    "total_commits": 1,
    "commits": [
      {
        "id": "f1d2d2f924e986ac86fdf7b36c94bcdf32beec15",
        "message": "Update readme",
        "author": {"name": "Bob Jones", "email": "bob@example.com"},
        "date_utc": "2024-01-15T10:00:00Z"
      }
    ]
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── git.receive (start_commit = zero) → create / create ───────────────────────

POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Event: git.receive
{
  "topic": "pagure.git.receive",
  "msg": {
    "agent": "bob",
    "repo": {
      "id": 100, "name": "hello-world", "namespace": "octocat",
      "fullname": "octocat/hello-world", "url_path": "octocat/hello-world",
      "full_url": "http://localhost/octocat/hello-world",
      "description": "My first repo", "default_branch": "main", "private": false,
      "user": {"name": "octocat", "url_path": "user/octocat"}
    },
    "branch": "refs/heads/feature-branch",
    "start_commit": "0000000000000000000000000000000000000000",
    "end_commit": "da1560886d4f094c3e6c9ef40349f7d38b5d27d0",
    "forced": false,
    "total_commits": 0,
    "commits": []
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── git.receive (end_commit = zero) → delete / delete ─────────────────────────

POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Event: git.receive
{
  "topic": "pagure.git.receive",
  "msg": {
    "agent": "bob",
    "repo": {
      "id": 100, "name": "hello-world", "namespace": "octocat",
      "fullname": "octocat/hello-world", "url_path": "octocat/hello-world",
      "full_url": "http://localhost/octocat/hello-world",
      "description": "My first repo", "default_branch": "main", "private": false,
      "user": {"name": "octocat", "url_path": "user/octocat"}
    },
    "branch": "refs/heads/stale-branch",
    "start_commit": "95790bf891e76fee5db5ef17d2523a6f6e048239",
    "end_commit": "0000000000000000000000000000000000000000",
    "forced": false,
    "total_commits": 0,
    "commits": []
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── project.forked → fork / fork ──────────────────────────────────────────────

POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Event: project.forked
{
  "topic": "pagure.project.forked",
  "msg": {
    "agent": "bob",
    "project": {
      "id": 100, "name": "hello-world", "namespace": "octocat",
      "fullname": "octocat/hello-world", "url_path": "octocat/hello-world",
      "full_url": "http://localhost/octocat/hello-world",
      "description": "My first repo", "default_branch": "main", "private": false,
      "user": {"name": "octocat", "url_path": "user/octocat"}
    },
    "fork": {
      "id": 101, "name": "hello-world", "namespace": null,
      "fullname": "forks/bob/hello-world", "url_path": "fork/bob/hello-world",
      "full_url": "http://localhost/fork/bob/hello-world",
      "description": "My first repo", "default_branch": "main", "private": false,
      "parent": {"fullname": "octocat/hello-world"},
      "user": {"name": "bob", "url_path": "user/bob"}
    }
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pull-request.closed (merged) → pull_request / closed ─────────────────────

POST http://{{host}}/webhooks/pagure
Content-Type: application/json
X-Pagure-Event: pull-request.closed
{
  "topic": "pull-request.closed",
  "msg": {
    "pullrequest": {
      "id": 7,
      "title": "Add feature X",
      "initial_comment": "This PR adds feature X.",
      "status": "Merged",
      "branch": "main",
      "branch_from": "feature-x",
      "repo_from": {
        "id": 101,
        "name": "hello-world",
        "fullname": "alice/hello-world"
      },
      "user": {"name": "alice", "fullname": "Alice", "url_path": "user/alice", "avatar_url": ""},
      "date_created": "1705312800",
      "last_updated": "1705320000",
      "commit_start": "abc123",
      "commit_stop": "def456",
      "full_url": "octocat/hello-world/pull-request/7"
    },
    "project": {
      "id": 100,
      "name": "hello-world",
      "namespace": "octocat",
      "fullname": "octocat/hello-world",
      "url_path": "octocat/hello-world",
      "full_url": "http://localhost/octocat/hello-world",
      "private": false,
      "user": {"name": "octocat", "url_path": "user/octocat"}
    },
    "agent": "octocat"
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"
