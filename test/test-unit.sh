#!/usr/bin/env bash
# Unit tests — no real network access required.
set -euo pipefail

CONFUSIO_PORT=18080
MOCK_PORT=18081
CONFUSIO_BIN=$(pwd)/confusio.com
MOCK_BIN=$(pwd)/mock-gitea.com
HURL=$(pwd)/hurl

start_isolated() {
  local cmd="$*"
  if command -v setsid >/dev/null 2>&1; then
    setsid $cmd &
  else
    $cmd &
  fi
}

start_confusio() {
  local dir="$1"; shift   # working directory
  local args="${*:-}"     # remaining args passed to binary
  local cmd="sh $CONFUSIO_BIN -p $CONFUSIO_PORT $args"
  if command -v setsid >/dev/null 2>&1; then
    (cd "$dir" && setsid $cmd) &
  else
    (cd "$dir" && $cmd) &
  fi
}

start_mock() {
  start_isolated sh "$MOCK_BIN" -p "$MOCK_PORT"
}

# --- Phase 1: no config (default behaviour) ---
TMPDIR1=$(mktemp -d)
trap "rm -rf $TMPDIR1" EXIT
start_confusio "$TMPDIR1"
PID=$!
trap "kill $PID 2>/dev/null || true; rm -rf $TMPDIR1" EXIT
$HURL --retry 10 --retry-interval 200 --connect-timeout 1 --max-time 5 \
  --variable host=localhost:$CONFUSIO_PORT test/root.hurl
kill $PID 2>/dev/null || true; sleep 0.3

# --- Phase 2: Gitea backend via -D CLI flags ---
TMPDIR2=$(mktemp -d)
start_mock
MOCK_PID=$!
start_confusio "$TMPDIR2" "-- backend=gitea base_url=http://127.0.0.1:$MOCK_PORT"
PID=$!
trap "kill $PID 2>/dev/null || true; kill $MOCK_PID 2>/dev/null || true; rm -rf $TMPDIR2" EXIT
$HURL --retry 10 --retry-interval 200 --connect-timeout 1 --max-time 5 \
  --variable host=localhost:$CONFUSIO_PORT test/gitea-root.hurl
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
$HURL --retry 10 --retry-interval 200 --connect-timeout 1 --max-time 5 \
  --variable host=localhost:$CONFUSIO_PORT test/gitea-root.hurl
