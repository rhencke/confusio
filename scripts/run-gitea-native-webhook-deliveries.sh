#!/usr/bin/env bash
# Run Gitea native webhook delivery checks from a fixture manifest.
#
# Usage:
#   scripts/run-gitea-native-webhook-deliveries.sh HOST TARGET [HURL]
#
# HOST and TARGET use host:port form, matching the variables in the existing
# webhook-delivery*.hurl files.  By default the harness skips rows whose fixture
# file has not been added yet; set STRICT_NATIVE_FIXTURES=1 to fail instead.
# Set GITEA_NATIVE_DELIVERY_SHAPE=confusio to assert normalized delivery shape.
# Set GITEA_NATIVE_DELIVERY_MANIFEST=/path/to/manifest.tsv to run a subset.

set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "usage: $0 HOST TARGET [HURL]" >&2
  exit 2
fi

HOST="$1"
TARGET="$2"
HURL="${3:-hurl}"
SHAPE="${GITEA_NATIVE_DELIVERY_SHAPE:-github}"

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MANIFEST="${GITEA_NATIVE_DELIVERY_MANIFEST:-$ROOT/test/fixtures/webhooks/gitea/native-delivery.tsv}"
TMP=$(mktemp "$ROOT/test/.gitea-native-delivery.XXXXXX.hurl")
trap 'rm -f "$TMP"' EXIT

while IFS='|' read -r native_event github_event fixture note normalized_type; do
  case "${native_event:-}" in
    "" | "#"*) continue ;;
  esac

  fixture_path="$ROOT/test/fixtures/webhooks/gitea/$fixture"
  if [ ! -f "$fixture_path" ]; then
    if [ "${STRICT_NATIVE_FIXTURES:-}" = "1" ]; then
      echo "missing Gitea native webhook fixture: $fixture" >&2
      exit 1
    fi
    echo "skip missing fixture: $fixture ($native_event $note)" >&2
    continue
  fi

  cat > "$TMP" <<EOF
POST http://{{target}}/reset
{}
HTTP 200

POST http://{{host}}/webhooks/gitea
Content-Type: application/json
X-Gitea-Event: $native_event
file,fixtures/webhooks/gitea/$fixture;
HTTP 200
[Asserts]
jsonpath "\$.message" == "accepted"

GET http://{{target}}/deliveries
HTTP 200
[Asserts]
jsonpath "\$" count == 1
EOF

  if [ "$SHAPE" = "confusio" ]; then
    if [ -z "${normalized_type:-}" ]; then
      echo "missing normalized type for Gitea native webhook fixture: $fixture" >&2
      exit 1
    fi
    cat >> "$TMP" <<EOF
jsonpath "\$[0].confusio_event" == "$github_event"
jsonpath "\$[0].confusio_source" == "gitea"
jsonpath "\$[0].confusio_delivery" isString
jsonpath "\$[0].github_event" == ""
jsonpath "\$[0].body_json.id" isString
jsonpath "\$[0].body_json.type" == "$normalized_type"
jsonpath "\$[0].user_agent" contains "confusio"
EOF
  else
    cat >> "$TMP" <<EOF
jsonpath "\$[0].github_event" == "$github_event"
jsonpath "\$[0].github_delivery" isString
jsonpath "\$[0].user_agent" contains "confusio"
EOF
  fi

  "$HURL" --connect-timeout 1 --max-time 5 \
    --variable "host=$HOST" \
    --variable "target=$TARGET" \
    "$TMP"
done < "$MANIFEST"
