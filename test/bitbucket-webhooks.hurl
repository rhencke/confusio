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

# ── pullrequest:created → pull_request / opened ──────────────────────────────

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: pullrequest:created
{
  "actor": {
    "nickname": "bob",
    "display_name": "Bob",
    "account_id": "def456",
    "links": {"avatar": {"href": ""}, "html": {"href": ""}}
  },
  "pullrequest": {
    "id": 7,
    "title": "Add new feature",
    "description": "This PR adds a new feature.",
    "state": "OPEN",
    "author": {
      "nickname": "bob", "display_name": "Bob", "account_id": "def456",
      "links": {"avatar": {"href": ""}, "html": {"href": ""}}
    },
    "source": {
      "branch": {"name": "feature-branch"},
      "commit": {"hash": "abc123"},
      "repository": {
        "full_name": "octocat/hello-world",
        "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world"}}
      }
    },
    "destination": {
      "branch": {"name": "main"},
      "commit": {"hash": "def456"},
      "repository": {
        "full_name": "octocat/hello-world",
        "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world"}}
      }
    },
    "created_on": "2024-01-15T10:00:00Z",
    "updated_on": "2024-01-15T10:00:00Z",
    "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world/pull-requests/7"}}
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

# ── pullrequest:updated → pull_request / synchronize ─────────────────────────
# BB Cloud fires pullrequest:updated for sync, edit, and reopen; we map to
# synchronize (most common case; distinguishing requires state tracking).

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: pullrequest:updated
{
  "actor": {
    "nickname": "bob",
    "display_name": "Bob",
    "account_id": "def456",
    "links": {"avatar": {"href": ""}, "html": {"href": ""}}
  },
  "pullrequest": {
    "id": 7,
    "title": "Add new feature",
    "description": "This PR adds a new feature.",
    "state": "OPEN",
    "author": {
      "nickname": "bob", "display_name": "Bob", "account_id": "def456",
      "links": {"avatar": {"href": ""}, "html": {"href": ""}}
    },
    "source": {
      "branch": {"name": "feature-branch"},
      "commit": {"hash": "bbb222"},
      "repository": {
        "full_name": "octocat/hello-world",
        "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world"}}
      }
    },
    "destination": {
      "branch": {"name": "main"},
      "commit": {"hash": "def456"},
      "repository": {
        "full_name": "octocat/hello-world",
        "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world"}}
      }
    },
    "created_on": "2024-01-15T10:00:00Z",
    "updated_on": "2024-01-15T10:05:00Z",
    "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world/pull-requests/7"}}
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

# ── pullrequest:fulfilled → pull_request / closed (merged) ───────────────────

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: pullrequest:fulfilled
{
  "actor": {
    "nickname": "alice",
    "display_name": "Alice",
    "account_id": "abc123",
    "links": {"avatar": {"href": ""}, "html": {"href": ""}}
  },
  "pullrequest": {
    "id": 7,
    "title": "Add new feature",
    "description": "This PR adds a new feature.",
    "state": "MERGED",
    "author": {
      "nickname": "bob", "display_name": "Bob", "account_id": "def456",
      "links": {"avatar": {"href": ""}, "html": {"href": ""}}
    },
    "closed_by": {
      "nickname": "alice", "display_name": "Alice", "account_id": "abc123",
      "links": {"avatar": {"href": ""}, "html": {"href": ""}}
    },
    "merge_commit": {"hash": "ccc333"},
    "source": {
      "branch": {"name": "feature-branch"},
      "commit": {"hash": "bbb222"},
      "repository": {
        "full_name": "octocat/hello-world",
        "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world"}}
      }
    },
    "destination": {
      "branch": {"name": "main"},
      "commit": {"hash": "def456"},
      "repository": {
        "full_name": "octocat/hello-world",
        "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world"}}
      }
    },
    "created_on": "2024-01-15T10:00:00Z",
    "updated_on": "2024-01-15T10:10:00Z",
    "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world/pull-requests/7"}}
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

# ── pullrequest:rejected → pull_request / closed (declined) ──────────────────

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: pullrequest:rejected
{
  "actor": {
    "nickname": "alice",
    "display_name": "Alice",
    "account_id": "abc123",
    "links": {"avatar": {"href": ""}, "html": {"href": ""}}
  },
  "pullrequest": {
    "id": 8,
    "title": "Bad idea",
    "description": "",
    "state": "DECLINED",
    "author": {
      "nickname": "bob", "display_name": "Bob", "account_id": "def456",
      "links": {"avatar": {"href": ""}, "html": {"href": ""}}
    },
    "source": {
      "branch": {"name": "bad-idea"},
      "commit": {"hash": "aaa111"},
      "repository": {
        "full_name": "octocat/hello-world",
        "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world"}}
      }
    },
    "destination": {
      "branch": {"name": "main"},
      "commit": {"hash": "def456"},
      "repository": {
        "full_name": "octocat/hello-world",
        "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world"}}
      }
    },
    "created_on": "2024-01-15T09:00:00Z",
    "updated_on": "2024-01-15T10:15:00Z",
    "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world/pull-requests/8"}}
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

# ── pullrequest:approved → pull_request_review / submitted / APPROVED ─────────

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: pullrequest:approved
{
  "actor": {
    "nickname": "alice",
    "display_name": "Alice",
    "account_id": "abc123",
    "links": {"avatar": {"href": ""}, "html": {"href": ""}}
  },
  "approval": {
    "date": "2024-01-15T10:30:00Z",
    "user": {
      "nickname": "alice",
      "display_name": "Alice",
      "account_id": "abc123",
      "links": {"avatar": {"href": ""}, "html": {"href": ""}}
    }
  },
  "pullrequest": {
    "id": 7,
    "title": "Add new feature",
    "description": "This PR adds a new feature.",
    "state": "OPEN",
    "author": {
      "nickname": "bob", "display_name": "Bob", "account_id": "def456",
      "links": {"avatar": {"href": ""}, "html": {"href": ""}}
    },
    "source": {
      "branch": {"name": "feature-branch"},
      "commit": {"hash": "abc123"},
      "repository": {
        "full_name": "octocat/hello-world",
        "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world"}}
      }
    },
    "destination": {
      "branch": {"name": "main"},
      "commit": {"hash": "def456"},
      "repository": {
        "full_name": "octocat/hello-world",
        "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world"}}
      }
    },
    "created_on": "2024-01-15T10:00:00Z",
    "updated_on": "2024-01-15T10:30:00Z",
    "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world/pull-requests/7"}}
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
jsonpath "$.event" == "pull_request_review"
jsonpath "$.action" == "submitted"
jsonpath "$.data.review.state" == "APPROVED"
jsonpath "$.data.review.user.login" == "alice"
jsonpath "$.data.review.submitted_at" == "2024-01-15T10:30:00Z"
jsonpath "$.data.pull_request.number" == 7
jsonpath "$.data.sender.login" == "alice"

# ── pullrequest:unapproved → pull_request_review / dismissed / DISMISSED ──────

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: pullrequest:unapproved
{
  "actor": {
    "nickname": "alice",
    "display_name": "Alice",
    "account_id": "abc123",
    "links": {"avatar": {"href": ""}, "html": {"href": ""}}
  },
  "approval": {
    "date": "2024-01-15T10:45:00Z",
    "user": {
      "nickname": "alice",
      "display_name": "Alice",
      "account_id": "abc123",
      "links": {"avatar": {"href": ""}, "html": {"href": ""}}
    }
  },
  "pullrequest": {
    "id": 7,
    "title": "Add new feature",
    "description": "This PR adds a new feature.",
    "state": "OPEN",
    "author": {
      "nickname": "bob", "display_name": "Bob", "account_id": "def456",
      "links": {"avatar": {"href": ""}, "html": {"href": ""}}
    },
    "source": {
      "branch": {"name": "feature-branch"},
      "commit": {"hash": "abc123"},
      "repository": {
        "full_name": "octocat/hello-world",
        "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world"}}
      }
    },
    "destination": {
      "branch": {"name": "main"},
      "commit": {"hash": "def456"},
      "repository": {
        "full_name": "octocat/hello-world",
        "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world"}}
      }
    },
    "created_on": "2024-01-15T10:00:00Z",
    "updated_on": "2024-01-15T10:45:00Z",
    "links": {"html": {"href": "https://bitbucket.org/octocat/hello-world/pull-requests/7"}}
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
jsonpath "$.event" == "pull_request_review"
jsonpath "$.action" == "dismissed"
jsonpath "$.data.review.state" == "DISMISSED"
jsonpath "$.data.review.user.login" == "alice"
jsonpath "$.data.review.submitted_at" == "2024-01-15T10:45:00Z"
jsonpath "$.data.pull_request.number" == 7
jsonpath "$.data.sender.login" == "alice"
