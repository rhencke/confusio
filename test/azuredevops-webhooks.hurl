# Azure DevOps webhook normalizer tests — run by test-unit-azuredevops.
#
# ADO embeds the event type in payload.eventType (no event-type header).
# Trust-the-network mode (no webhook_secret_BACKEND CLI arg): Authorization header omitted.
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

# ── git.pullrequest.reviewervote (vote=10, approved) → pull_request_review / submitted / APPROVED

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
{
  "subscriptionId": "sub-1",
  "notificationId": 9,
  "id": "evt-9",
  "eventType": "git.pullrequest.reviewervote",
  "resource": {
    "reviewerUrl": "",
    "vote": 10,
    "reviewer": {
      "displayName": "Alice",
      "uniqueName": "alice",
      "id": "user-id-alice",
      "imageUrl": "",
      "isContainer": false
    },
    "pullRequest": {
      "pullRequestId": 42,
      "title": "Add feature X",
      "description": "This PR adds feature X.",
      "status": "active",
      "isDraft": false,
      "sourceRefName": "refs/heads/feature-x",
      "targetRefName": "refs/heads/main",
      "createdBy": {"displayName": "Bob", "uniqueName": "bob"},
      "creationDate": "2024-01-15T12:00:00Z",
      "lastMergeSourceCommit": {"commitId": "abc123"},
      "lastMergeTargetCommit": {"commitId": "def456"},
      "repository": {}
    }
  },
  "createdDate": "2024-01-15T13:00:00Z"
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── git.pullrequest.reviewervote (vote=-10, rejected) → pull_request_review / submitted / CHANGES_REQUESTED

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
{
  "subscriptionId": "sub-1",
  "notificationId": 10,
  "id": "evt-10",
  "eventType": "git.pullrequest.reviewervote",
  "resource": {
    "reviewerUrl": "",
    "vote": -10,
    "reviewer": {
      "displayName": "Alice",
      "uniqueName": "alice",
      "id": "user-id-alice",
      "imageUrl": "",
      "isContainer": false
    },
    "pullRequest": {
      "pullRequestId": 42,
      "title": "Add feature X",
      "description": "This PR adds feature X.",
      "status": "active",
      "isDraft": false,
      "sourceRefName": "refs/heads/feature-x",
      "targetRefName": "refs/heads/main",
      "createdBy": {"displayName": "Bob", "uniqueName": "bob"},
      "creationDate": "2024-01-15T12:00:00Z",
      "lastMergeSourceCommit": {"commitId": "abc123"},
      "lastMergeTargetCommit": {"commitId": "def456"},
      "repository": {}
    }
  },
  "createdDate": "2024-01-15T13:05:00Z"
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── git.pullrequest.reviewervote (vote=0, reset) → pull_request_review / dismissed / DISMISSED

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
{
  "subscriptionId": "sub-1",
  "notificationId": 11,
  "id": "evt-11",
  "eventType": "git.pullrequest.reviewervote",
  "resource": {
    "reviewerUrl": "",
    "vote": 0,
    "reviewer": {
      "displayName": "Alice",
      "uniqueName": "alice",
      "id": "user-id-alice",
      "imageUrl": "",
      "isContainer": false
    },
    "pullRequest": {
      "pullRequestId": 42,
      "title": "Add feature X",
      "description": "This PR adds feature X.",
      "status": "active",
      "isDraft": false,
      "sourceRefName": "refs/heads/feature-x",
      "targetRefName": "refs/heads/main",
      "createdBy": {"displayName": "Bob", "uniqueName": "bob"},
      "creationDate": "2024-01-15T12:00:00Z",
      "lastMergeSourceCommit": {"commitId": "abc123"},
      "lastMergeTargetCommit": {"commitId": "def456"},
      "repository": {}
    }
  },
  "createdDate": "2024-01-15T13:10:00Z"
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── build.complete (succeeded) → workflow_run / completed / success ───────────

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
{
  "subscriptionId": "sub-1",
  "notificationId": 20,
  "id": "evt-20",
  "eventType": "build.complete",
  "resource": {
    "id": 1001,
    "buildNumber": "20240115.1",
    "status": "completed",
    "result": "succeeded",
    "queueTime": "2024-01-15T10:00:00Z",
    "startTime": "2024-01-15T10:01:00Z",
    "finishTime": "2024-01-15T10:05:00Z",
    "url": "https://dev.azure.com/org/project/_apis/build/builds/1001",
    "_links": {
      "web": {"href": "https://dev.azure.com/org/project/_build/results?buildId=1001"}
    },
    "definition": {"id": 1, "name": "CI Pipeline"},
    "sourceBranch": "refs/heads/main",
    "sourceVersion": "abc123def456abc123def456abc123def456abc123",
    "requestedBy": {"displayName": "The Octocat", "uniqueName": "octocat"},
    "requestedFor": {"displayName": "The Octocat", "uniqueName": "octocat"},
    "repository": {}
  },
  "createdDate": "2024-01-15T10:05:00Z"
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── build.complete (failed) → workflow_run / completed / failure ───────────────

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
{
  "subscriptionId": "sub-1",
  "notificationId": 21,
  "id": "evt-21",
  "eventType": "build.complete",
  "resource": {
    "id": 1002,
    "buildNumber": "20240115.2",
    "status": "completed",
    "result": "failed",
    "queueTime": "2024-01-15T11:00:00Z",
    "startTime": "2024-01-15T11:01:00Z",
    "finishTime": "2024-01-15T11:04:00Z",
    "url": "https://dev.azure.com/org/project/_apis/build/builds/1002",
    "_links": {
      "web": {"href": "https://dev.azure.com/org/project/_build/results?buildId=1002"}
    },
    "definition": {"id": 1, "name": "CI Pipeline"},
    "sourceBranch": "refs/heads/feature",
    "sourceVersion": "deadbeefdeadbeef",
    "requestedBy": {"displayName": "Bob", "uniqueName": "bob"},
    "requestedFor": {"displayName": "Bob", "uniqueName": "bob"},
    "repository": {}
  },
  "createdDate": "2024-01-15T11:04:00Z"
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── git.push (regular push) → push / push ─────────────────────────────────────

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
{
  "subscriptionId": "sub-1",
  "notificationId": 30,
  "id": "evt-30",
  "eventType": "git.push",
  "resource": {
    "repository": {
      "id": "repo-id-001", "name": "hello-world",
      "remoteUrl": "https://dev.azure.com/octocat/hello-world/_git/hello-world",
      "defaultBranch": "refs/heads/main", "isPrivate": false,
      "project": {"id": "proj-id-001", "name": "octocat"}
    },
    "refUpdates": [
      {
        "name": "refs/heads/main",
        "oldObjectId": "6dcb09b5b57875f334f61aebed695e2e4193db5e",
        "newObjectId": "f1d2d2f924e986ac86fdf7b36c94bcdf32beec15"
      }
    ],
    "commits": [
      {
        "commitId": "f1d2d2f924e986ac86fdf7b36c94bcdf32beec15",
        "comment": "Update readme",
        "author": {"name": "Bob Jones", "email": "bob@example.com", "date": "2024-01-15T10:00:00Z"},
        "committer": {"name": "Bob Jones", "email": "bob@example.com", "date": "2024-01-15T10:00:00Z"}
      }
    ],
    "pushedBy": {"displayName": "Bob Jones", "uniqueName": "bob@example.com"},
    "pushId": 1
  },
  "createdDate": "2024-01-15T10:00:00Z"
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── git.push (oldObjectId = zero) → create / create ───────────────────────────

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
{
  "subscriptionId": "sub-1",
  "notificationId": 31,
  "id": "evt-31",
  "eventType": "git.push",
  "resource": {
    "repository": {
      "id": "repo-id-001", "name": "hello-world",
      "remoteUrl": "https://dev.azure.com/octocat/hello-world/_git/hello-world",
      "defaultBranch": "refs/heads/main", "isPrivate": false,
      "project": {"id": "proj-id-001", "name": "octocat"}
    },
    "refUpdates": [
      {
        "name": "refs/heads/feature-branch",
        "oldObjectId": "0000000000000000000000000000000000000000",
        "newObjectId": "da1560886d4f094c3e6c9ef40349f7d38b5d27d0"
      }
    ],
    "commits": [],
    "pushedBy": {"displayName": "Bob Jones", "uniqueName": "bob@example.com"},
    "pushId": 2
  },
  "createdDate": "2024-01-15T11:00:00Z"
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── git.push (newObjectId = zero) → delete / delete ───────────────────────────

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
{
  "subscriptionId": "sub-1",
  "notificationId": 32,
  "id": "evt-32",
  "eventType": "git.push",
  "resource": {
    "repository": {
      "id": "repo-id-001", "name": "hello-world",
      "remoteUrl": "https://dev.azure.com/octocat/hello-world/_git/hello-world",
      "defaultBranch": "refs/heads/main", "isPrivate": false,
      "project": {"id": "proj-id-001", "name": "octocat"}
    },
    "refUpdates": [
      {
        "name": "refs/heads/stale-branch",
        "oldObjectId": "95790bf891e76fee5db5ef17d2523a6f6e048239",
        "newObjectId": "0000000000000000000000000000000000000000"
      }
    ],
    "commits": [],
    "pushedBy": {"displayName": "Bob Jones", "uniqueName": "bob@example.com"},
    "pushId": 3
  },
  "createdDate": "2024-01-15T12:00:00Z"
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# ── build.complete (canceled) → workflow_run / completed / cancelled ───────────

POST http://{{host}}/webhooks/azuredevops
Content-Type: application/json
{
  "subscriptionId": "sub-1",
  "notificationId": 22,
  "id": "evt-22",
  "eventType": "build.complete",
  "resource": {
    "id": 1003,
    "buildNumber": "20240115.3",
    "status": "completed",
    "result": "canceled",
    "queueTime": "2024-01-15T12:00:00Z",
    "startTime": "2024-01-15T12:01:00Z",
    "finishTime": "2024-01-15T12:02:00Z",
    "url": "https://dev.azure.com/org/project/_apis/build/builds/1003",
    "_links": {
      "web": {"href": "https://dev.azure.com/org/project/_build/results?buildId=1003"}
    },
    "definition": {"id": 2, "name": "Deploy Pipeline"},
    "sourceBranch": "refs/heads/main",
    "sourceVersion": "cafebabecafebabe",
    "requestedBy": {"displayName": "Alice", "uniqueName": "alice"},
    "requestedFor": {"displayName": "Alice", "uniqueName": "alice"},
    "repository": {}
  },
  "createdDate": "2024-01-15T12:02:00Z"
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"
