# Bitbucket Cloud webhook normalizer tests — run by test-unit-bitbucket.
#
# Bitbucket Cloud uses X-Event-Key header.  Issue events are only available
# for Cloud (Bitbucket DC has no native issue tracker).
# Trust-the-network mode (no CONFUSIO_WEBHOOK_SECRETS): signature headers omitted.

# ── issue:created → issues / opened ──────────────────────────────────────────

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: issue:created
{
  "actor": {
    "nickname": "alice",
    "display_name": "Alice",
    "account_id": "abc123",
    "links": {"avatar": {"href": ""}, "html": {"href": ""}}
  },
  "issue": {
    "id": 1,
    "title": "Found a bug",
    "content": {"raw": "Something broke."},
    "state": "open",
    "priority": "major",
    "kind": "bug",
    "reporter": {
      "nickname": "alice", "display_name": "Alice", "account_id": "abc123",
      "type": "user", "links": {"avatar": {"href": ""}, "html": {"href": ""}}
    },
    "assignee": null,
    "milestone": null,
    "created_on": "2024-01-15T10:00:00Z",
    "updated_on": "2024-01-15T10:00:00Z",
    "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world/issues/1"}}
  },
  "repository": {
    "full_name": "octocat/hello-world",
    "name": "hello-world",
    "slug": "hello-world",
    "is_private": false,
    "owner": {
      "nickname": "octocat", "display_name": "The Octocat", "account_id": "xyz789",
      "type": "user", "links": {"avatar": {"href": ""}, "html": {"href": ""}}
    },
    "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world"}}
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── issue:updated (status: open → resolved) → issues / closed ────────────────

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: issue:updated
{
  "actor": {
    "nickname": "alice",
    "display_name": "Alice",
    "account_id": "abc123",
    "links": {"avatar": {"href": ""}, "html": {"href": ""}}
  },
  "issue": {
    "id": 1,
    "title": "Found a bug",
    "content": {"raw": "Something broke."},
    "state": "resolved",
    "priority": "major",
    "kind": "bug",
    "reporter": {
      "nickname": "alice", "display_name": "Alice", "account_id": "abc123",
      "type": "user", "links": {"avatar": {"href": ""}, "html": {"href": ""}}
    },
    "assignee": null,
    "milestone": null,
    "created_on": "2024-01-15T10:00:00Z",
    "updated_on": "2024-01-15T10:05:00Z",
    "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world/issues/1"}}
  },
  "repository": {
    "full_name": "octocat/hello-world",
    "name": "hello-world",
    "slug": "hello-world",
    "is_private": false,
    "owner": {
      "nickname": "octocat", "display_name": "The Octocat", "account_id": "xyz789",
      "type": "user", "links": {"avatar": {"href": ""}, "html": {"href": ""}}
    },
    "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world"}}
  },
  "changes": {
    "status": {"new": "resolved", "old": "open"}
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── issue:updated (status: resolved → open) → issues / reopened ──────────────

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: issue:updated
{
  "actor": {
    "nickname": "alice",
    "display_name": "Alice",
    "account_id": "abc123",
    "links": {"avatar": {"href": ""}, "html": {"href": ""}}
  },
  "issue": {
    "id": 1,
    "title": "Found a bug",
    "content": {"raw": "Something broke."},
    "state": "open",
    "priority": "major",
    "kind": "bug",
    "reporter": {
      "nickname": "alice", "display_name": "Alice", "account_id": "abc123",
      "type": "user", "links": {"avatar": {"href": ""}, "html": {"href": ""}}
    },
    "assignee": null,
    "milestone": null,
    "created_on": "2024-01-15T10:00:00Z",
    "updated_on": "2024-01-15T10:10:00Z",
    "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world/issues/1"}}
  },
  "repository": {
    "full_name": "octocat/hello-world",
    "name": "hello-world",
    "slug": "hello-world",
    "is_private": false,
    "owner": {
      "nickname": "octocat", "display_name": "The Octocat", "account_id": "xyz789",
      "type": "user", "links": {"avatar": {"href": ""}, "html": {"href": ""}}
    },
    "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world"}}
  },
  "changes": {
    "status": {"new": "open", "old": "resolved"}
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── issue:updated (title change, no status change) → issues / edited ──────────

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: issue:updated
{
  "actor": {
    "nickname": "alice",
    "display_name": "Alice",
    "account_id": "abc123",
    "links": {"avatar": {"href": ""}, "html": {"href": ""}}
  },
  "issue": {
    "id": 1,
    "title": "Found a nasty bug",
    "content": {"raw": "Something broke."},
    "state": "open",
    "priority": "critical",
    "kind": "bug",
    "reporter": {
      "nickname": "alice", "display_name": "Alice", "account_id": "abc123",
      "type": "user", "links": {"avatar": {"href": ""}, "html": {"href": ""}}
    },
    "assignee": null,
    "milestone": null,
    "created_on": "2024-01-15T10:00:00Z",
    "updated_on": "2024-01-15T10:15:00Z",
    "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world/issues/1"}}
  },
  "repository": {
    "full_name": "octocat/hello-world",
    "name": "hello-world",
    "slug": "hello-world",
    "is_private": false,
    "owner": {
      "nickname": "octocat", "display_name": "The Octocat", "account_id": "xyz789",
      "type": "user", "links": {"avatar": {"href": ""}, "html": {"href": ""}}
    },
    "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world"}}
  },
  "changes": {
    "title": {"new": "Found a nasty bug", "old": "Found a bug"},
    "priority": {"new": "critical", "old": "major"}
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── issue:comment_created → issue_comment / created ───────────────────────────

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: issue:comment_created
{
  "actor": {
    "nickname": "bob",
    "display_name": "Bob",
    "account_id": "def456",
    "links": {"avatar": {"href": ""}, "html": {"href": ""}}
  },
  "comment": {
    "id": 42,
    "content": {"raw": "Confirmed, I can reproduce this."},
    "created_on": "2024-01-15T11:00:00Z",
    "updated_on": "2024-01-15T11:00:00Z",
    "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world/issues/1/_/diff#comment-42"}}
  },
  "issue": {
    "id": 1,
    "title": "Found a bug",
    "content": {"raw": "Something broke."},
    "state": "open",
    "priority": "major",
    "kind": "bug",
    "reporter": {
      "nickname": "alice", "display_name": "Alice", "account_id": "abc123",
      "type": "user", "links": {"avatar": {"href": ""}, "html": {"href": ""}}
    },
    "assignee": null,
    "milestone": null,
    "created_on": "2024-01-15T10:00:00Z",
    "updated_on": "2024-01-15T10:00:00Z",
    "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world/issues/1"}}
  },
  "repository": {
    "full_name": "octocat/hello-world",
    "name": "hello-world",
    "slug": "hello-world",
    "is_private": false,
    "owner": {
      "nickname": "octocat", "display_name": "The Octocat", "account_id": "xyz789",
      "type": "user", "links": {"avatar": {"href": ""}, "html": {"href": ""}}
    },
    "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world"}}
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"
