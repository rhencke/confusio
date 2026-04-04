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

run_hurl() {
  $HURL --retry 10 --retry-interval 200 --connect-timeout 1 --max-time 5 \
    --variable host=localhost:$CONFUSIO_PORT "$1"
}

# run_phase <hurl_file> [confusio_args...]
# Starts confusio in a temp dir, runs the hurl assertion, then cleans up.
run_phase() {
  local hurl_file="$1"; shift
  local tmpdir
  tmpdir=$(mktemp -d)
  start_confusio "$tmpdir" "$@"
  PID=$!
  trap "kill $PID 2>/dev/null || true; rm -rf $tmpdir" EXIT
  run_hurl "$hurl_file"
  kill $PID 2>/dev/null || true; sleep 0.3
}

# run_mock_phase <hurl_file> [confusio_args...]
# Like run_phase but also starts the mock backend server.
# Set CONFUSIO_CONFIG before calling to write a .confusio.lua config file.
run_mock_phase() {
  local hurl_file="$1"; shift
  local tmpdir
  tmpdir=$(mktemp -d)
  if [ -n "${CONFUSIO_CONFIG:-}" ]; then
    printf '%s\n' "$CONFUSIO_CONFIG" > "$tmpdir/.confusio.lua"
  fi
  start_mock; MOCK_PID=$!
  start_confusio "$tmpdir" "$@"
  PID=$!
  trap "kill $PID 2>/dev/null || true; kill $MOCK_PID 2>/dev/null || true; rm -rf $tmpdir" EXIT
  run_hurl "$hurl_file"
  kill $PID 2>/dev/null || true; kill $MOCK_PID 2>/dev/null || true; sleep 0.3
}

MOCK_ARGS="-- backend=gitea base_url=http://127.0.0.1:$MOCK_PORT"

# --- Phase 1: no config (default behaviour) ---
run_phase test/root.hurl

# --- Phase 2: Gitea backend via CLI flags ---
run_mock_phase test/gitea-root.hurl $MOCK_ARGS

# --- Phase 3: Gitea backend via .confusio.lua config file ---
CONFUSIO_CONFIG="confusio = { backend=\"gitea\", base_url=\"http://127.0.0.1:$MOCK_PORT\" }"
run_mock_phase test/gitea-root.hurl
unset CONFUSIO_CONFIG

# --- Phase 4: Gitea backend with token passthrough ---
run_mock_phase test/gitea-root-auth.hurl $MOCK_ARGS

# --- Phase 5: Repos API (Gitea backend) ---
run_mock_phase test/gitea-repos.hurl $MOCK_ARGS

# --- Phase 6: Extended Repos API (branches, commits, contents, releases, etc.) ---
run_mock_phase test/gitea-repos-ext.hurl $MOCK_ARGS
