# Phabricator webhook dispatch scaffolding.
#
# Phabricator sends a generic webhook envelope.  The receiver extracts the
# native object family from object.type, or from the object PHID prefix when
# type is absent, then dispatches to the backend's registered handler.

# Known TASK object.type reaches the Phabricator Maniphest handler.
POST http://{{host}}/webhooks/phabricator
Content-Type: application/json
{
  "object": {
    "type": "TASK",
    "id": 123,
    "phid": "PHID-TASK-abcd",
    "fields": {
      "name": "Fix the task",
      "status": {
        "value": "open"
      }
    }
  },
  "transactions": [
    {
      "type": "title",
      "phid": "PHID-XACT-TASK-abcd"
    }
  ]
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# Missing object.type falls back to the PHID prefix and reaches Differential.
POST http://{{host}}/webhooks/phabricator
Content-Type: application/json
{
  "object": {
    "id": 45,
    "phid": "PHID-DREV-abcd",
    "fields": {
      "title": "Review this change",
      "status": {
        "value": "needs-review"
      }
    }
  },
  "transactions": [
    {
      "type": "core:create",
      "phid": "PHID-XACT-DREV-abcd"
    }
  ]
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# Diffusion commit PHID-prefix payloads reach the push translator.
POST http://{{host}}/webhooks/phabricator
Content-Type: application/json
{
  "object": {
    "phid": "PHID-CMIT-abcd",
    "fields": {
      "identifier": "abcdef123456",
      "message": "Push through Diffusion",
      "branch": "main"
    }
  },
  "repository": {
    "fields": {
      "name": "confusio",
      "shortName": "confusio"
    }
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# Harbormaster build payloads translate to workflow_run events.
POST http://{{host}}/webhooks/phabricator
Content-Type: application/json
{
  "object": {
    "type": "HMBD",
    "id": 7,
    "phid": "PHID-HMBD-abcd",
    "fields": {
      "name": "unit tests",
      "buildStatus": {
        "value": "passed"
      },
      "commitIdentifier": "abcdef123456",
      "dateCreated": 1710000000,
      "dateModified": 1710000300
    }
  },
  "repository": {
    "fields": {
      "name": "confusio",
      "shortName": "confusio"
    }
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# Harbormaster build target payloads translate to workflow_job events.
POST http://{{host}}/webhooks/phabricator
Content-Type: application/json
{
  "object": {
    "type": "HMBT",
    "id": 9,
    "phid": "PHID-HMBT-abcd",
    "fields": {
      "name": "lint",
      "buildStatus": {
        "value": "failed"
      },
      "commitIdentifier": "abcdef123456",
      "dateCreated": 1710000000,
      "dateModified": 1710000300
    }
  },
  "repository": {
    "fields": {
      "name": "confusio",
      "shortName": "confusio"
    }
  }
}

HTTP 200
[Asserts]
jsonpath "$.message" == "accepted"

# Unknown object families remain explicit 422s.
POST http://{{host}}/webhooks/phabricator
Content-Type: application/json
{
  "object": {
    "type": "WIKI",
    "phid": "PHID-WIKI-abcd"
  }
}

HTTP 422
[Asserts]
jsonpath "$.message" == "Unrecognised event type: WIKI"
