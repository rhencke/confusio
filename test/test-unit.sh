#!/usr/bin/env bash
# Unit test preamble — sequential boot-path checks.
# Backend tests (phases 4+) run in parallel via: $(MAKE) -j test-unit-backends
set -euo pipefail

CONFUSIO_PORT=18080
MOCK_PORT=18081
CONFUSIO_BIN=$(pwd)/confusio.com
MOCK_GITEA_BIN=$(pwd)/mock-gitea.com
HURL=$(pwd)/hurl

start_isolated() {
  if command -v setsid >/dev/null 2>&1; then
    setsid "$@" &
  else
    "$@" &
  fi
}

start_confusio() {
  local dir="$1"; shift
  local args="${*:-}"
  local cmd="sh $CONFUSIO_BIN -p $CONFUSIO_PORT $args"
  if command -v setsid >/dev/null 2>&1; then
    (cd "$dir" && setsid $cmd) &
  else
    (cd "$dir" && $cmd) &
  fi
}

run_hurl() {
  $HURL --retry 10 --retry-interval 200 --connect-timeout 1 --max-time 5 \
    --variable host=localhost:$CONFUSIO_PORT "$1"
}

run_phase() {
  local hurl_file="$1"; shift
  local tmpdir; tmpdir=$(mktemp -d)
  start_confusio "$tmpdir" "$@"; PID=$!
  trap "kill $PID 2>/dev/null || true; rm -rf $tmpdir" EXIT
  run_hurl "$hurl_file"
  kill $PID 2>/dev/null || true; sleep 0.3
}

run_mock_phase() {
  local hurl_file="$1"; shift
  local tmpdir; tmpdir=$(mktemp -d)
  if [ -n "${CONFUSIO_CONFIG:-}" ]; then
    printf '%s\n' "$CONFUSIO_CONFIG" > "$tmpdir/.confusio.lua"
  fi
  start_isolated sh "$MOCK_GITEA_BIN" -p "$MOCK_PORT"; MOCK_PID=$!
  start_confusio "$tmpdir" "$@"; PID=$!
  trap "kill $PID 2>/dev/null || true; kill $MOCK_PID 2>/dev/null || true; rm -rf $tmpdir" EXIT
  run_hurl "$hurl_file"
  kill $PID 2>/dev/null || true; kill $MOCK_PID 2>/dev/null || true; sleep 0.3
}

MOCK_ARGS="-- backend=gitea base_url=http://127.0.0.1:$MOCK_PORT"

# Phase 1: no config
run_phase test/root.hurl

# Phase 2: Gitea via CLI flags
run_mock_phase test/gitea-root.hurl $MOCK_ARGS

# Phase 3: Gitea via .confusio.lua config file
CONFUSIO_CONFIG="confusio = { backend=\"gitea\", base_url=\"http://127.0.0.1:$MOCK_PORT\" }"
run_mock_phase test/gitea-root.hurl
unset CONFUSIO_CONFIG
