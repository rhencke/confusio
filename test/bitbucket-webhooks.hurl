# Bitbucket Cloud webhook normalizer tests — run by test-unit-bitbucket.
#
# Bitbucket Cloud uses X-Event-Key header.  Issue events are only available
# for Cloud (Bitbucket DC has no native issue tracker).
# Trust-the-network mode (no webhook_secret_BACKEND CLI arg): signature headers omitted.

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

# ── repo:commit_comment_created → commit_comment / created ───────────────────

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: repo:commit_comment_created
{
  "actor": {
    "nickname": "bob",
    "display_name": "Bob",
    "account_id": "def456",
    "links": {"avatar": {"href": ""}, "html": {"href": ""}}
  },
  "comment": {
    "id": 303,
    "content": {"raw": "Nit: this should use the shared helper."},
    "created_on": "2024-01-15T10:40:00Z",
    "updated_on": "2024-01-15T10:40:00Z",
    "user": {
      "nickname": "bob", "display_name": "Bob", "account_id": "def456",
      "links": {"avatar": {"href": ""}, "html": {"href": ""}}
    },
    "inline": {"path": "src/main.lua", "to": 42},
    "links": {
      "html": {
        "href": "https://bitbucket.org/octocat/hello-world/commits/abc1234567890abcdef1234567890abcdef12345#comment-303"
      }
    }
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

# ── repo:commit_status_created → status / success ────────────────────────────

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: repo:commit_status_created
{
  "actor": {
    "nickname": "octocat",
    "display_name": "The Octocat",
    "account_id": "xyz789",
    "links": {"avatar": {"href": ""}, "html": {"href": ""}}
  },
  "commit_status": {
    "state": "SUCCESSFUL",
    "key": "ci/build",
    "description": "Build passed",
    "url": "https://ci.example.com/builds/42",
    "name": "My CI",
    "created_on": "2024-01-15T10:05:00+00:00",
    "updated_on": "2024-01-15T10:05:00+00:00",
    "links": {
      "commit": {
        "href": "https://api.bitbucket.org/2.0/repositories/octocat/hello-world/commit/abc123def456"
      },
      "self": {"href": "https://api.bitbucket.org/2.0/repositories/octocat/hello-world/commit/abc123def456/statuses/build/ci-build"}
    }
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

# ── repo:commit_status_updated → status / pending ─────────────────────────────

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: repo:commit_status_updated
{
  "actor": {
    "nickname": "bob",
    "display_name": "Bob",
    "account_id": "def456",
    "links": {"avatar": {"href": ""}, "html": {"href": ""}}
  },
  "commit_status": {
    "state": "INPROGRESS",
    "key": "ci/test",
    "description": "Running tests...",
    "url": "https://ci.example.com/builds/43",
    "name": "My CI",
    "created_on": "2024-01-15T11:00:00+00:00",
    "updated_on": "2024-01-15T11:01:00+00:00",
    "links": {
      "commit": {
        "href": "https://api.bitbucket.org/2.0/repositories/octocat/hello-world/commit/deadbeef"
      },
      "self": {"href": ""}
    }
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

# ── repo:commit_status_updated → status / failure ─────────────────────────────

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: repo:commit_status_updated
{
  "actor": {
    "nickname": "octocat",
    "display_name": "The Octocat",
    "account_id": "xyz789",
    "links": {"avatar": {"href": ""}, "html": {"href": ""}}
  },
  "commit_status": {
    "state": "FAILED",
    "key": "ci/build",
    "description": "Build failed",
    "url": "https://ci.example.com/builds/44",
    "name": "My CI",
    "created_on": "2024-01-15T12:00:00+00:00",
    "updated_on": "2024-01-15T12:05:00+00:00",
    "links": {
      "commit": {
        "href": "https://api.bitbucket.org/2.0/repositories/octocat/hello-world/commit/cafebabe"
      },
      "self": {"href": ""}
    }
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

# ── repo:push: regular branch push → 200 (push event) ────────────────────────

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: repo:push
{
  "actor": {
    "nickname": "alice",
    "display_name": "Alice Smith",
    "account_id": "acct-alice",
    "links": {"avatar": {"href": ""}, "html": {"href": ""}}
  },
  "push": {
    "changes": [
      {
        "new": {
          "type": "branch",
          "name": "main",
          "target": {
            "hash": "da1560886d4f094c3e6c9ef40349f7d38b5d27d0",
            "message": "Fix login bug",
            "date": "2024-01-15T10:00:00+00:00",
            "author": {
              "raw": "Alice Smith <alice@example.com>",
              "user": {"nickname": "alice", "display_name": "Alice Smith", "account_id": "acct-alice",
                       "links": {"avatar": {"href": ""}, "html": {"href": ""}}}
            },
            "parents": [{"hash": "95790bf891e76fee5db5ef17d2523a6f6e048239"}],
            "links": {"html": {"href": ""}}
          },
          "links": {"html": {"href": ""}}
        },
        "old": {
          "type": "branch",
          "name": "main",
          "target": {"hash": "95790bf891e76fee5db5ef17d2523a6f6e048239"}
        },
        "created": false,
        "closed": false,
        "forced": false,
        "truncated": false,
        "commits": [
          {
            "hash": "da1560886d4f094c3e6c9ef40349f7d38b5d27d0",
            "message": "Fix login bug",
            "date": "2024-01-15T10:00:00+00:00",
            "author": {
              "raw": "Alice Smith <alice@example.com>",
              "user": {"nickname": "alice", "display_name": "Alice Smith", "account_id": "acct-alice",
                       "links": {"avatar": {"href": ""}, "html": {"href": ""}}}
            },
            "parents": [{"hash": "95790bf891e76fee5db5ef17d2523a6f6e048239"}],
            "links": {"html": {"href": ""}}
          }
        ],
        "links": {"html": {"href": "http://localhost/octocat/hello-world/compare"}, "diff": {"href": ""}}
      }
    ]
  },
  "repository": {
    "full_name": "octocat/hello-world", "name": "hello-world", "slug": "hello-world",
    "is_private": false, "description": "My first repo",
    "mainbranch": {"name": "main"},
    "owner": {"nickname": "octocat", "display_name": "The Octocat", "account_id": "owner-id",
              "type": "user", "links": {"avatar": {"href": ""}, "html": {"href": ""}}},
    "links": {"html": {"href": "http://localhost/octocat/hello-world"}, "self": {"href": ""}}
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── repo:push: created=true → 200 (create event, branch created) ─────────────

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: repo:push
{
  "actor": {
    "nickname": "bob",
    "display_name": "Bob Jones",
    "account_id": "acct-bob",
    "links": {"avatar": {"href": ""}, "html": {"href": ""}}
  },
  "push": {
    "changes": [
      {
        "new": {
          "type": "branch",
          "name": "feature-branch",
          "target": {
            "hash": "da1560886d4f094c3e6c9ef40349f7d38b5d27d0",
            "date": "2024-01-15T11:00:00+00:00",
            "author": {"raw": "Bob Jones <bob@example.com>",
                       "user": {"nickname": "bob", "display_name": "Bob Jones", "account_id": "acct-bob",
                                "links": {"avatar": {"href": ""}, "html": {"href": ""}}}},
            "parents": [],
            "links": {"html": {"href": ""}}
          },
          "links": {"html": {"href": ""}}
        },
        "old": null,
        "created": true,
        "closed": false,
        "forced": false,
        "truncated": false,
        "commits": [],
        "links": {"html": {"href": ""}, "diff": {"href": ""}}
      }
    ]
  },
  "repository": {
    "full_name": "octocat/hello-world", "name": "hello-world", "slug": "hello-world",
    "is_private": false, "description": "My first repo",
    "mainbranch": {"name": "main"},
    "owner": {"nickname": "octocat", "display_name": "The Octocat", "account_id": "owner-id",
              "type": "user", "links": {"avatar": {"href": ""}, "html": {"href": ""}}},
    "links": {"html": {"href": "http://localhost/octocat/hello-world"}, "self": {"href": ""}}
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── repo:push: closed=true → 200 (delete event, branch deleted) ──────────────

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: repo:push
{
  "actor": {
    "nickname": "bob",
    "display_name": "Bob Jones",
    "account_id": "acct-bob",
    "links": {"avatar": {"href": ""}, "html": {"href": ""}}
  },
  "push": {
    "changes": [
      {
        "new": null,
        "old": {
          "type": "branch",
          "name": "stale-branch",
          "target": {"hash": "95790bf891e76fee5db5ef17d2523a6f6e048239"}
        },
        "created": false,
        "closed": true,
        "forced": false,
        "truncated": false,
        "commits": [],
        "links": {"html": {"href": ""}, "diff": {"href": ""}}
      }
    ]
  },
  "repository": {
    "full_name": "octocat/hello-world", "name": "hello-world", "slug": "hello-world",
    "is_private": false, "description": "My first repo",
    "mainbranch": {"name": "main"},
    "owner": {"nickname": "octocat", "display_name": "The Octocat", "account_id": "owner-id",
              "type": "user", "links": {"avatar": {"href": ""}, "html": {"href": ""}}},
    "links": {"html": {"href": "http://localhost/octocat/hello-world"}, "self": {"href": ""}}
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── repo:fork → 200 ───────────────────────────────────────────────────────────

POST http://{{host}}/webhooks/bitbucket
Content-Type: application/json
X-Event-Key: repo:fork
{
  "actor": {
    "nickname": "bob",
    "display_name": "Bob Jones",
    "account_id": "acct-bob",
    "links": {"avatar": {"href": ""}, "html": {"href": ""}}
  },
  "fork": {
    "full_name": "bob/hello-world", "name": "hello-world", "slug": "hello-world",
    "is_private": false, "description": "My first repo",
    "mainbranch": {"name": "main"},
    "parent": {"full_name": "octocat/hello-world"},
    "owner": {"nickname": "bob", "display_name": "Bob Jones", "account_id": "acct-bob",
              "type": "user", "links": {"avatar": {"href": ""}, "html": {"href": "http://localhost/bob"}}},
    "links": {"html": {"href": "http://localhost/bob/hello-world"}, "self": {"href": ""}}
  },
  "repository": {
    "full_name": "octocat/hello-world", "name": "hello-world", "slug": "hello-world",
    "is_private": false, "description": "My first repo",
    "mainbranch": {"name": "main"},
    "owner": {"nickname": "octocat", "display_name": "The Octocat", "account_id": "owner-id",
              "type": "user", "links": {"avatar": {"href": ""}, "html": {"href": ""}}},
    "links": {"html": {"href": "http://localhost/octocat/hello-world"}, "self": {"href": ""}}
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"
