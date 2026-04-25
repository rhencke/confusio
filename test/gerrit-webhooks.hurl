# Gerrit webhook normalizer tests — run by test-unit-gerrit.
#
# Gerrit uses a shared secret in the Authorization header (Bearer or Basic).
# Trust-the-network mode (no webhook_secret_BACKEND CLI arg): Authorization header omitted.
# Event type is determined from the body field `type`.

# ── comment-added with Code-Review +2 → pull_request_review / submitted / APPROVED ──

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
{
  "type": "comment-added",
  "change": {
    "_number": 42,
    "project": "octocat/hello-world",
    "branch": "main",
    "subject": "Add new feature",
    "owner": {
      "_account_id": 2,
      "username": "bob",
      "name": "Bob",
      "email": "bob@example.com"
    },
    "wip": false,
    "created": "2024-01-15T10:00:00Z",
    "updated": "2024-01-15T14:00:00Z"
  },
  "patchSet": {
    "number": 3,
    "revision": "abc123def456",
    "createdOn": 1705324800
  },
  "author": {
    "_account_id": 1,
    "username": "alice",
    "name": "Alice",
    "email": "alice@example.com"
  },
  "approvals": [
    {
      "type": "Code-Review",
      "description": "Code-Review",
      "value": "+2",
      "oldValue": "0"
    }
  ],
  "comment": "Looks great, ship it!"
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── comment-added with Code-Review -2 → pull_request_review / submitted / CHANGES_REQUESTED ──

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
{
  "type": "comment-added",
  "change": {
    "_number": 42,
    "project": "octocat/hello-world",
    "branch": "main",
    "subject": "Add new feature",
    "owner": {
      "_account_id": 2,
      "username": "bob",
      "name": "Bob",
      "email": "bob@example.com"
    },
    "wip": false,
    "created": "2024-01-15T10:00:00Z",
    "updated": "2024-01-15T15:00:00Z"
  },
  "patchSet": {
    "number": 3,
    "revision": "abc123def456",
    "createdOn": 1705328400
  },
  "author": {
    "_account_id": 1,
    "username": "alice",
    "name": "Alice",
    "email": "alice@example.com"
  },
  "approvals": [
    {
      "type": "Code-Review",
      "description": "Code-Review",
      "value": "-2",
      "oldValue": "+2"
    }
  ],
  "comment": "This needs significant changes before I can approve."
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── comment-added with Code-Review 0 → pull_request_review / submitted / COMMENTED ──

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
{
  "type": "comment-added",
  "change": {
    "_number": 43,
    "project": "octocat/hello-world",
    "branch": "main",
    "subject": "Fix the bug",
    "owner": {
      "_account_id": 2,
      "username": "bob",
      "name": "Bob",
      "email": "bob@example.com"
    },
    "wip": false,
    "created": "2024-01-16T09:00:00Z",
    "updated": "2024-01-16T11:00:00Z"
  },
  "patchSet": {
    "number": 1,
    "revision": "deadbeef1234",
    "createdOn": 1705399200
  },
  "author": {
    "_account_id": 3,
    "username": "carol",
    "name": "Carol",
    "email": "carol@example.com"
  },
  "approvals": [
    {
      "type": "Code-Review",
      "description": "Code-Review",
      "value": "0",
      "oldValue": "0"
    }
  ],
  "comment": "Left some inline comments, please take a look."
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── comment-added with no approvals → pull_request_review / submitted / COMMENTED ──

POST http://{{host}}/webhooks/gerrit
Content-Type: application/json
{
  "type": "comment-added",
  "change": {
    "_number": 44,
    "project": "octocat/hello-world",
    "branch": "feature",
    "subject": "Refactor module",
    "owner": {
      "_account_id": 2,
      "username": "bob",
      "name": "Bob",
      "email": "bob@example.com"
    },
    "wip": false,
    "created": "2024-01-17T09:00:00Z",
    "updated": "2024-01-17T10:00:00Z"
  },
  "patchSet": {
    "number": 2,
    "revision": "cafebabe5678",
    "createdOn": 1705485600
  },
  "author": {
    "_account_id": 4,
    "username": "dave",
    "name": "Dave",
    "email": "dave@example.com"
  },
  "approvals": [],
  "comment": "Just a general comment, no score."
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"
