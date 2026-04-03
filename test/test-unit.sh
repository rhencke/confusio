#!/usr/bin/env bash
# Unit tests — no real network access required.
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

# --- Phase 1: no config (default behaviour) ---
TMPDIR1=$(mktemp -d)
trap "rm -rf $TMPDIR1" EXIT
start_confusio "$TMPDIR1"
PID=$!
trap "kill $PID 2>/dev/null || true; rm -rf $TMPDIR1" EXIT
$HURL $HURL_RETRY --variable host=localhost:$CONFUSIO_PORT test/default-*.hurl
kill $PID 2>/dev/null || true; sleep 0.3

# --- Phase 2: Gitea backend via CLI flags ---
TMPDIR2=$(mktemp -d)
start_mock
MOCK_PID=$!
start_confusio "$TMPDIR2" "-- backend=gitea base_url=http://127.0.0.1:$MOCK_PORT"
PID=$!
trap "kill $PID 2>/dev/null || true; kill $MOCK_PID 2>/dev/null || true; rm -rf $TMPDIR2" EXIT
$HURL $HURL_RETRY --variable host=localhost:$CONFUSIO_PORT test/gitea-*.hurl
kill $PID 2>/dev/null || true; kill $MOCK_PID 2>/dev/null || true; sleep 0.3

# --- Phase 3: Gitea backend via .confusio.lua config file ---
TMPDIR3=$(mktemp -d)
cat > "$TMPDIR3/.confusio.lua" <<EOF
confusio = { backend="gitea", base_url="http://127.0.0.1:$MOCK_PORT" }
EOF
start_mock
MOCK_PID=$!
start_confusio "$TMPDIR3"
PID=$!
trap "kill $PID 2>/dev/null || true; kill $MOCK_PID 2>/dev/null || true; rm -rf $TMPDIR3" EXIT
$HURL $HURL_RETRY --variable host=localhost:$CONFUSIO_PORT test/gitea-*.hurl
