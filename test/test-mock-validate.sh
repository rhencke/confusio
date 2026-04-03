#!/usr/bin/env bash
# Validates that mock-gitea.com satisfies the same Hurl assertions as the real
# Gitea instance. Run periodically or before updating the mock to catch drift.
set -euo pipefail

MOCK_PORT=18082
MOCK_BIN=$(pwd)/mock-gitea.com
HURL=$(pwd)/hurl
BASE_URL="${1:-https://gitea.com}"

# Assert against real instance first
echo "Checking real instance ($BASE_URL)..."
"$HURL" --variable "host=$(printf '%s' "$BASE_URL" | sed 's|https\?://||')" \
  test/validate/gitea-api-version.hurl

# Start mock and wait for it to be ready
if command -v setsid >/dev/null 2>&1; then
  setsid sh "$MOCK_BIN" -p "$MOCK_PORT" &
else
  sh "$MOCK_BIN" -p "$MOCK_PORT" &
fi
MOCK_PID=$!
trap "kill $MOCK_PID 2>/dev/null || true" EXIT

echo "Checking mock..."
"$HURL" --retry 10 --retry-interval 200 --connect-timeout 1 --max-time 5 \
  --variable "host=127.0.0.1:$MOCK_PORT" \
  test/validate/gitea-api-version.hurl

echo "OK: mock and $BASE_URL both pass assertions in test/validate/gitea-api-version.hurl"
