# Pagure webhook normalizer tests — run by test-unit-pagure.
#
# Pagure uses X-Pagure-Event header.  Payload envelope: {topic, msg: {issue,
# project, agent, [comment]}}.
# Trust-the-network mode (no CONFUSIO_WEBHOOK_SECRETS): X-Pagure-Token omitted.

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
