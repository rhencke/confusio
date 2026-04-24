# Bitbucket Data Center webhook normalizer tests — run by test-unit-bitbucket_datacenter.
#
# BBS uses X-Event-Key header.  PR events are the primary event type supported
# (BBS has no native issue tracker).
# Trust-the-network mode (no CONFUSIO_WEBHOOK_SECRETS): signature headers omitted.

# ── pr:opened → pull_request / opened ────────────────────────────────────────

POST http://{{host}}/webhooks/bitbucket_datacenter
Content-Type: application/json
X-Event-Key: pr:opened
{
  "actor": {
    "name": "bob",
    "id": 2,
    "slug": "bob",
    "displayName": "Bob",
    "emailAddress": "bob@example.com",
    "links": {"self": [{"href": ""}]}
  },
  "pullRequest": {
    "id": 7,
    "title": "Add new feature",
    "description": "This PR adds a new feature.",
    "state": "OPEN",
    "author": {
      "user": {
        "name": "bob", "id": 2, "slug": "bob",
        "displayName": "Bob", "emailAddress": "bob@example.com",
        "links": {"self": [{"href": ""}]}
      },
      "role": "AUTHOR", "approved": false, "status": "UNAPPROVED"
    },
    "fromRef": {
      "id": "refs/heads/feature-branch",
      "displayId": "feature-branch",
      "latestCommit": "abc123",
      "repository": {
        "id": 100, "slug": "hello-world", "name": "hello-world",
        "public": true,
        "project": {"id": 10, "key": "OCTOCAT", "name": "Octocat", "type": "NORMAL"},
        "links": {"self": [{"href": "http://localhost/projects/OCTOCAT/repos/hello-world/browse"}]}
      }
    },
    "toRef": {
      "id": "refs/heads/main",
      "displayId": "main",
      "latestCommit": "def456",
      "repository": {
        "id": 100, "slug": "hello-world", "name": "hello-world",
        "public": true,
        "project": {"id": 10, "key": "OCTOCAT", "name": "Octocat", "type": "NORMAL"},
        "links": {"self": [{"href": "http://localhost/projects/OCTOCAT/repos/hello-world/browse"}]}
      }
    },
    "reviewers": [],
    "createdDate": 1705312800000,
    "updatedDate": 1705312800000,
    "links": {"self": [{"href": "http://localhost/projects/OCTOCAT/repos/hello-world/pull-requests/7"}]}
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pr:modified → pull_request / edited ──────────────────────────────────────
# pr:modified fires on title/description changes and reopen; maps to "edited"
# (reopen is indistinguishable without state tracking).

POST http://{{host}}/webhooks/bitbucket_datacenter
Content-Type: application/json
X-Event-Key: pr:modified
{
  "actor": {
    "name": "bob",
    "id": 2,
    "slug": "bob",
    "displayName": "Bob",
    "emailAddress": "bob@example.com",
    "links": {"self": [{"href": ""}]}
  },
  "pullRequest": {
    "id": 7,
    "title": "Add new feature (updated title)",
    "description": "Updated description.",
    "state": "OPEN",
    "author": {
      "user": {
        "name": "bob", "id": 2, "slug": "bob",
        "displayName": "Bob", "emailAddress": "bob@example.com",
        "links": {"self": [{"href": ""}]}
      },
      "role": "AUTHOR", "approved": false, "status": "UNAPPROVED"
    },
    "fromRef": {
      "id": "refs/heads/feature-branch",
      "displayId": "feature-branch",
      "latestCommit": "abc123",
      "repository": {
        "id": 100, "slug": "hello-world", "name": "hello-world",
        "public": true,
        "project": {"id": 10, "key": "OCTOCAT", "name": "Octocat", "type": "NORMAL"},
        "links": {"self": [{"href": "http://localhost/projects/OCTOCAT/repos/hello-world/browse"}]}
      }
    },
    "toRef": {
      "id": "refs/heads/main",
      "displayId": "main",
      "latestCommit": "def456",
      "repository": {
        "id": 100, "slug": "hello-world", "name": "hello-world",
        "public": true,
        "project": {"id": 10, "key": "OCTOCAT", "name": "Octocat", "type": "NORMAL"},
        "links": {"self": [{"href": "http://localhost/projects/OCTOCAT/repos/hello-world/browse"}]}
      }
    },
    "reviewers": [],
    "createdDate": 1705312800000,
    "updatedDate": 1705316400000,
    "links": {"self": [{"href": "http://localhost/projects/OCTOCAT/repos/hello-world/pull-requests/7"}]}
  },
  "previousTitle": "Add new feature"
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pr:from_ref_updated → pull_request / synchronize ─────────────────────────

POST http://{{host}}/webhooks/bitbucket_datacenter
Content-Type: application/json
X-Event-Key: pr:from_ref_updated
{
  "actor": {
    "name": "bob",
    "id": 2,
    "slug": "bob",
    "displayName": "Bob",
    "emailAddress": "bob@example.com",
    "links": {"self": [{"href": ""}]}
  },
  "pullRequest": {
    "id": 7,
    "title": "Add new feature",
    "description": "This PR adds a new feature.",
    "state": "OPEN",
    "author": {
      "user": {
        "name": "bob", "id": 2, "slug": "bob",
        "displayName": "Bob", "emailAddress": "bob@example.com",
        "links": {"self": [{"href": ""}]}
      },
      "role": "AUTHOR", "approved": false, "status": "UNAPPROVED"
    },
    "fromRef": {
      "id": "refs/heads/feature-branch",
      "displayId": "feature-branch",
      "latestCommit": "bbb222",
      "repository": {
        "id": 100, "slug": "hello-world", "name": "hello-world",
        "public": true,
        "project": {"id": 10, "key": "OCTOCAT", "name": "Octocat", "type": "NORMAL"},
        "links": {"self": [{"href": "http://localhost/projects/OCTOCAT/repos/hello-world/browse"}]}
      }
    },
    "toRef": {
      "id": "refs/heads/main",
      "displayId": "main",
      "latestCommit": "def456",
      "repository": {
        "id": 100, "slug": "hello-world", "name": "hello-world",
        "public": true,
        "project": {"id": 10, "key": "OCTOCAT", "name": "Octocat", "type": "NORMAL"},
        "links": {"self": [{"href": "http://localhost/projects/OCTOCAT/repos/hello-world/browse"}]}
      }
    },
    "reviewers": [],
    "createdDate": 1705312800000,
    "updatedDate": 1705318000000,
    "links": {"self": [{"href": "http://localhost/projects/OCTOCAT/repos/hello-world/pull-requests/7"}]}
  },
  "previousFromHash": "abc123"
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pr:reviewer:updated (added) → pull_request / review_requested ────────────

POST http://{{host}}/webhooks/bitbucket_datacenter
Content-Type: application/json
X-Event-Key: pr:reviewer:updated
{
  "actor": {
    "name": "alice",
    "id": 1,
    "slug": "alice",
    "displayName": "Alice",
    "emailAddress": "alice@example.com",
    "links": {"self": [{"href": ""}]}
  },
  "pullRequest": {
    "id": 7,
    "title": "Add new feature",
    "description": "This PR adds a new feature.",
    "state": "OPEN",
    "author": {
      "user": {
        "name": "bob", "id": 2, "slug": "bob",
        "displayName": "Bob", "emailAddress": "bob@example.com",
        "links": {"self": [{"href": ""}]}
      },
      "role": "AUTHOR", "approved": false, "status": "UNAPPROVED"
    },
    "fromRef": {
      "id": "refs/heads/feature-branch",
      "displayId": "feature-branch",
      "latestCommit": "abc123",
      "repository": {
        "id": 100, "slug": "hello-world", "name": "hello-world",
        "public": true,
        "project": {"id": 10, "key": "OCTOCAT", "name": "Octocat", "type": "NORMAL"},
        "links": {"self": [{"href": "http://localhost/projects/OCTOCAT/repos/hello-world/browse"}]}
      }
    },
    "toRef": {
      "id": "refs/heads/main",
      "displayId": "main",
      "latestCommit": "def456",
      "repository": {
        "id": 100, "slug": "hello-world", "name": "hello-world",
        "public": true,
        "project": {"id": 10, "key": "OCTOCAT", "name": "Octocat", "type": "NORMAL"},
        "links": {"self": [{"href": "http://localhost/projects/OCTOCAT/repos/hello-world/browse"}]}
      }
    },
    "reviewers": [
      {
        "user": {
          "name": "alice", "id": 1, "slug": "alice",
          "displayName": "Alice", "emailAddress": "alice@example.com",
          "links": {"self": [{"href": ""}]}
        },
        "role": "REVIEWER", "approved": false, "status": "UNAPPROVED"
      }
    ],
    "createdDate": 1705312800000,
    "updatedDate": 1705319000000,
    "links": {"self": [{"href": "http://localhost/projects/OCTOCAT/repos/hello-world/pull-requests/7"}]}
  },
  "addedReviewers": [
    {
      "name": "alice", "id": 1, "slug": "alice",
      "displayName": "Alice", "emailAddress": "alice@example.com",
      "links": {"self": [{"href": ""}]}
    }
  ],
  "removedReviewers": []
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pr:merged → pull_request / closed ────────────────────────────────────────

POST http://{{host}}/webhooks/bitbucket_datacenter
Content-Type: application/json
X-Event-Key: pr:merged
{
  "actor": {
    "name": "alice",
    "id": 1,
    "slug": "alice",
    "displayName": "Alice",
    "emailAddress": "alice@example.com",
    "links": {"self": [{"href": ""}]}
  },
  "pullRequest": {
    "id": 7,
    "title": "Add new feature",
    "description": "This PR adds a new feature.",
    "state": "MERGED",
    "author": {
      "user": {
        "name": "bob", "id": 2, "slug": "bob",
        "displayName": "Bob", "emailAddress": "bob@example.com",
        "links": {"self": [{"href": ""}]}
      },
      "role": "AUTHOR", "approved": false, "status": "UNAPPROVED"
    },
    "fromRef": {
      "id": "refs/heads/feature-branch",
      "displayId": "feature-branch",
      "latestCommit": "abc123",
      "repository": {
        "id": 100, "slug": "hello-world", "name": "hello-world",
        "public": true,
        "project": {"id": 10, "key": "OCTOCAT", "name": "Octocat", "type": "NORMAL"},
        "links": {"self": [{"href": "http://localhost/projects/OCTOCAT/repos/hello-world/browse"}]}
      }
    },
    "toRef": {
      "id": "refs/heads/main",
      "displayId": "main",
      "latestCommit": "def456",
      "repository": {
        "id": 100, "slug": "hello-world", "name": "hello-world",
        "public": true,
        "project": {"id": 10, "key": "OCTOCAT", "name": "Octocat", "type": "NORMAL"},
        "links": {"self": [{"href": "http://localhost/projects/OCTOCAT/repos/hello-world/browse"}]}
      }
    },
    "reviewers": [],
    "createdDate": 1705312800000,
    "updatedDate": 1705320000000,
    "links": {"self": [{"href": "http://localhost/projects/OCTOCAT/repos/hello-world/pull-requests/7"}]}
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── pr:reviewer:approved → pull_request_review / submitted / APPROVED ─────────

POST http://{{host}}/webhooks/bitbucket_datacenter
Content-Type: application/json
X-Event-Key: pr:reviewer:approved
{
  "actor": {
    "name": "alice",
    "id": 1,
    "slug": "alice",
    "displayName": "Alice",
    "emailAddress": "alice@example.com",
    "links": {"self": [{"href": ""}]}
  },
  "participant": {
    "user": {
      "name": "alice",
      "id": 1,
      "slug": "alice",
      "displayName": "Alice",
      "emailAddress": "alice@example.com",
      "links": {"self": [{"href": ""}]}
    },
    "role": "REVIEWER",
    "approved": true,
    "status": "APPROVED"
  },
  "previousStatus": "UNAPPROVED",
  "pullRequest": {
    "id": 7,
    "title": "Add new feature",
    "description": "This PR adds a new feature.",
    "state": "OPEN",
    "author": {
      "user": {
        "name": "bob", "id": 2, "slug": "bob",
        "displayName": "Bob", "emailAddress": "bob@example.com",
        "links": {"self": [{"href": ""}]}
      },
      "role": "AUTHOR", "approved": false, "status": "UNAPPROVED"
    },
    "fromRef": {
      "id": "refs/heads/feature-branch",
      "displayId": "feature-branch",
      "latestCommit": "abc123",
      "repository": {
        "id": 100, "slug": "hello-world", "name": "hello-world",
        "public": true,
        "project": {"id": 10, "key": "OCTOCAT", "name": "Octocat", "type": "NORMAL"},
        "links": {"self": [{"href": "http://localhost/projects/OCTOCAT/repos/hello-world/browse"}]}
      }
    },
    "toRef": {
      "id": "refs/heads/main",
      "displayId": "main",
      "latestCommit": "def456",
      "repository": {
        "id": 100, "slug": "hello-world", "name": "hello-world",
        "public": true,
        "project": {"id": 10, "key": "OCTOCAT", "name": "Octocat", "type": "NORMAL"},
        "links": {"self": [{"href": "http://localhost/projects/OCTOCAT/repos/hello-world/browse"}]}
      }
    },
    "reviewers": [
      {
        "user": {
          "name": "alice", "id": 1, "slug": "alice",
          "displayName": "Alice", "emailAddress": "alice@example.com",
          "links": {"self": [{"href": ""}]}
        },
        "role": "REVIEWER", "approved": true, "status": "APPROVED"
      }
    ],
    "createdDate": 1705312800000,
    "updatedDate": 1705315800000,
    "links": {"self": [{"href": "http://localhost/projects/OCTOCAT/repos/hello-world/pull-requests/7"}]}
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"
jsonpath "$.event" == "pull_request_review"
jsonpath "$.action" == "submitted"
jsonpath "$.data.review.state" == "APPROVED"
jsonpath "$.data.review.user.login" == "alice"
jsonpath "$.data.pull_request.number" == 7
jsonpath "$.data.sender.login" == "alice"

# ── pr:reviewer:needs_work → pull_request_review / submitted / CHANGES_REQUESTED

POST http://{{host}}/webhooks/bitbucket_datacenter
Content-Type: application/json
X-Event-Key: pr:reviewer:needs_work
{
  "actor": {
    "name": "alice",
    "id": 1,
    "slug": "alice",
    "displayName": "Alice",
    "emailAddress": "alice@example.com",
    "links": {"self": [{"href": ""}]}
  },
  "participant": {
    "user": {
      "name": "alice",
      "id": 1,
      "slug": "alice",
      "displayName": "Alice",
      "emailAddress": "alice@example.com",
      "links": {"self": [{"href": ""}]}
    },
    "role": "REVIEWER",
    "approved": false,
    "status": "NEEDS_WORK"
  },
  "previousStatus": "APPROVED",
  "pullRequest": {
    "id": 7,
    "title": "Add new feature",
    "description": "This PR adds a new feature.",
    "state": "OPEN",
    "author": {
      "user": {
        "name": "bob", "id": 2, "slug": "bob",
        "displayName": "Bob", "emailAddress": "bob@example.com",
        "links": {"self": [{"href": ""}]}
      },
      "role": "AUTHOR", "approved": false, "status": "UNAPPROVED"
    },
    "fromRef": {
      "id": "refs/heads/feature-branch",
      "displayId": "feature-branch",
      "latestCommit": "abc123",
      "repository": {
        "id": 100, "slug": "hello-world", "name": "hello-world",
        "public": true,
        "project": {"id": 10, "key": "OCTOCAT", "name": "Octocat", "type": "NORMAL"},
        "links": {"self": [{"href": "http://localhost/projects/OCTOCAT/repos/hello-world/browse"}]}
      }
    },
    "toRef": {
      "id": "refs/heads/main",
      "displayId": "main",
      "latestCommit": "def456",
      "repository": {
        "id": 100, "slug": "hello-world", "name": "hello-world",
        "public": true,
        "project": {"id": 10, "key": "OCTOCAT", "name": "Octocat", "type": "NORMAL"},
        "links": {"self": [{"href": "http://localhost/projects/OCTOCAT/repos/hello-world/browse"}]}
      }
    },
    "reviewers": [
      {
        "user": {
          "name": "alice", "id": 1, "slug": "alice",
          "displayName": "Alice", "emailAddress": "alice@example.com",
          "links": {"self": [{"href": ""}]}
        },
        "role": "REVIEWER", "approved": false, "status": "NEEDS_WORK"
      }
    ],
    "createdDate": 1705312800000,
    "updatedDate": 1705316400000,
    "links": {"self": [{"href": "http://localhost/projects/OCTOCAT/repos/hello-world/pull-requests/7"}]}
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"
jsonpath "$.event" == "pull_request_review"
jsonpath "$.action" == "submitted"
jsonpath "$.data.review.state" == "CHANGES_REQUESTED"
jsonpath "$.data.review.user.login" == "alice"
jsonpath "$.data.pull_request.number" == 7
jsonpath "$.data.sender.login" == "alice"
