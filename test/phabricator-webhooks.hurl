# Phabricator webhook dispatch scaffolding.
#
# Phabricator sends a generic webhook envelope.  The receiver extracts the
# native object family from object.type, or from the object PHID prefix when
# type is absent, then dispatches to the backend's registered handler.

# Known object.type reaches the Phabricator handler registry.
POST http://{{host}}/webhooks/phabricator
Content-Type: application/json
{
  "object": {
    "type": "TASK",
    "phid": "PHID-TASK-abcd"
  },
  "transactions": [
    {
      "phid": "PHID-XACT-TASK-abcd"
    }
  ]
}

HTTP 422
[Asserts]
jsonpath "$.message" == "Phabricator webhook event not implemented: issues"

# Missing object.type falls back to the PHID prefix.
POST http://{{host}}/webhooks/phabricator
Content-Type: application/json
{
  "object": {
    "phid": "PHID-DREV-abcd"
  },
  "transactions": [
    {
      "phid": "PHID-XACT-DREV-abcd"
    }
  ]
}

HTTP 422
[Asserts]
jsonpath "$.message" == "Phabricator webhook event not implemented: pull_request"

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
