# Azure DevOps webhook normalizer tests — run by test-unit-azuredevops.
#
# ADO embeds the event type in payload.eventType (no event-type header).
# Trust-the-network mode (no CONFUSIO_WEBHOOK_SECRETS): Authorization header omitted.
# Repository field is empty ({}) since ADO work items are not repo-scoped.

# ── workitem.created → issues / opened ───────────────────────────────────────

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
{
  "subscriptionId": "sub-1",
  "notificationId": 1,
  "id": "evt-1",
  "eventType": "workitem.created",
  "resource": {
    "id": 1,
    "rev": 1,
    "workItemType": "Issue",
    "fields": {
      "System.Title": "Found a bug",
      "System.State": "New",
      "System.Description": "Something broke.",
      "System.CreatedDate": "2024-01-15T10:00:00Z",
      "System.ChangedDate": "2024-01-15T10:00:00Z",
      "System.CreatedBy": {"displayName": "Alice", "uniqueName": "alice"},
      "System.ChangedBy": {"displayName": "Alice", "uniqueName": "alice"}
    }
  },
  "createdDate": "2024-01-15T10:00:00Z"
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── workitem.updated (state: Active → Resolved) → issues / closed ─────────────

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
{
  "subscriptionId": "sub-1",
  "notificationId": 2,
  "id": "evt-2",
  "eventType": "workitem.updated",
  "resource": {
    "id": 1,
    "workItemType": "Issue",
    "fields": {
      "System.State": {"newValue": "Resolved", "oldValue": "Active"},
      "System.ChangedDate": {"newValue": "2024-01-15T10:05:00Z", "oldValue": "2024-01-15T10:00:00Z"}
    },
    "revision": {
      "id": 1,
      "rev": 2,
      "fields": {
        "System.Title": "Found a bug",
        "System.State": "Resolved",
        "System.Description": "Something broke.",
        "System.CreatedDate": "2024-01-15T10:00:00Z",
        "System.ChangedDate": "2024-01-15T10:05:00Z",
        "System.CreatedBy": {"displayName": "Alice", "uniqueName": "alice"},
        "System.ChangedBy": {"displayName": "Alice", "uniqueName": "alice"}
      }
    }
  },
  "createdDate": "2024-01-15T10:05:00Z"
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── workitem.updated (state: Resolved → Active) → issues / reopened ──────────

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
{
  "subscriptionId": "sub-1",
  "notificationId": 3,
  "id": "evt-3",
  "eventType": "workitem.updated",
  "resource": {
    "id": 1,
    "workItemType": "Issue",
    "fields": {
      "System.State": {"newValue": "Active", "oldValue": "Resolved"},
      "System.ChangedDate": {"newValue": "2024-01-15T10:10:00Z", "oldValue": "2024-01-15T10:05:00Z"}
    },
    "revision": {
      "id": 1,
      "rev": 3,
      "fields": {
        "System.Title": "Found a bug",
        "System.State": "Active",
        "System.Description": "Something broke.",
        "System.CreatedDate": "2024-01-15T10:00:00Z",
        "System.ChangedDate": "2024-01-15T10:10:00Z",
        "System.CreatedBy": {"displayName": "Alice", "uniqueName": "alice"},
        "System.ChangedBy": {"displayName": "Alice", "uniqueName": "alice"}
      }
    }
  },
  "createdDate": "2024-01-15T10:10:00Z"
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── workitem.updated (title change, no state change) → issues / edited ────────

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
{
  "subscriptionId": "sub-1",
  "notificationId": 4,
  "id": "evt-4",
  "eventType": "workitem.updated",
  "resource": {
    "id": 1,
    "workItemType": "Issue",
    "fields": {
      "System.Title": {"newValue": "Found a nasty bug", "oldValue": "Found a bug"},
      "System.ChangedDate": {"newValue": "2024-01-15T10:15:00Z", "oldValue": "2024-01-15T10:00:00Z"}
    },
    "revision": {
      "id": 1,
      "rev": 4,
      "fields": {
        "System.Title": "Found a nasty bug",
        "System.State": "Active",
        "System.Description": "Something broke.",
        "System.CreatedDate": "2024-01-15T10:00:00Z",
        "System.ChangedDate": "2024-01-15T10:15:00Z",
        "System.CreatedBy": {"displayName": "Alice", "uniqueName": "alice"},
        "System.ChangedBy": {"displayName": "Alice", "uniqueName": "alice"}
      }
    }
  },
  "createdDate": "2024-01-15T10:15:00Z"
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── workitem.commented → issue_comment / created ──────────────────────────────

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
{
  "subscriptionId": "sub-1",
  "notificationId": 5,
  "id": "evt-5",
  "eventType": "workitem.commented",
  "resource": {
    "id": 42,
    "workItemId": 1,
    "text": "Confirmed, I can reproduce this.",
    "revisedDate": "2024-01-15T11:00:00Z",
    "revisedBy": {"displayName": "Bob", "uniqueName": "bob"}
  },
  "createdDate": "2024-01-15T11:00:00Z"
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── git.pullrequest.created → pull_request / opened ──────────────────────────

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
{
  "subscriptionId": "sub-1",
  "notificationId": 6,
  "id": "evt-6",
  "eventType": "git.pullrequest.created",
  "resource": {
    "pullRequestId": 42,
    "title": "Add feature X",
    "description": "This PR adds feature X.",
    "status": "active",
    "isDraft": false,
    "sourceRefName": "refs/heads/feature-x",
    "targetRefName": "refs/heads/main",
    "createdBy": {"displayName": "Alice", "uniqueName": "alice"},
    "creationDate": "2024-01-15T12:00:00Z",
    "lastMergeSourceCommit": {"commitId": "abc123"},
    "lastMergeTargetCommit": {"commitId": "def456"},
    "repository": {}
  },
  "createdDate": "2024-01-15T12:00:00Z"
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── git.pullrequest.updated (completed) → pull_request / closed ───────────────

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
{
  "subscriptionId": "sub-1",
  "notificationId": 7,
  "id": "evt-7",
  "eventType": "git.pullrequest.updated",
  "resource": {
    "pullRequestId": 42,
    "title": "Add feature X",
    "description": "This PR adds feature X.",
    "status": "completed",
    "isDraft": false,
    "sourceRefName": "refs/heads/feature-x",
    "targetRefName": "refs/heads/main",
    "createdBy": {"displayName": "Alice", "uniqueName": "alice"},
    "creationDate": "2024-01-15T12:00:00Z",
    "closedDate": "2024-01-15T13:00:00Z",
    "lastMergeSourceCommit": {"commitId": "abc123"},
    "lastMergeTargetCommit": {"commitId": "def456"},
    "repository": {}
  },
  "createdDate": "2024-01-15T13:00:00Z"
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── git.pullrequest.updated (push/synchronize) → pull_request / synchronize ───

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
{
  "subscriptionId": "sub-1",
  "notificationId": 8,
  "id": "evt-8",
  "eventType": "git.pullrequest.updated",
  "resource": {
    "pullRequestId": 42,
    "title": "Add feature X",
    "description": "This PR adds feature X.",
    "status": "active",
    "isDraft": false,
    "sourceRefName": "refs/heads/feature-x",
    "targetRefName": "refs/heads/main",
    "createdBy": {"displayName": "Alice", "uniqueName": "alice"},
    "creationDate": "2024-01-15T12:00:00Z",
    "lastMergeSourceCommit": {"commitId": "bbb999"},
    "lastMergeTargetCommit": {"commitId": "def456"},
    "repository": {}
  },
  "createdDate": "2024-01-15T12:30:00Z"
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"
