#!/usr/bin/env bash
# Unit tests — no real network access required.
set -euo pipefail

CONFUSIO_PORT=18080
MOCK_PORT=18081
CONFUSIO_BIN=$(pwd)/confusio.com
MOCK_GITEA_BIN=$(pwd)/mock-gitea.com
MOCK_GITLAB_BIN=$(pwd)/mock-gitlab.com
MOCK_GITBUCKET_BIN=$(pwd)/mock-gitbucket.com
MOCK_BITBUCKET_BIN=$(pwd)/mock-bitbucket.com
MOCK_HARNESS_BIN=$(pwd)/mock-harness.com
MOCK_PAGURE_BIN=$(pwd)/mock-pagure.com
MOCK_ONEDEV_BIN=$(pwd)/mock-onedev.com
MOCK_SOURCEHUT_BIN=$(pwd)/mock-sourcehut.com
MOCK_RADICLE_BIN=$(pwd)/mock-radicle.com
MOCK_BITBUCKET_DATACENTER_BIN=$(pwd)/mock-bitbucket_datacenter.com
HURL=$(pwd)/hurl

MOCK_ARGS="-- backend=gitea base_url=http://127.0.0.1:$MOCK_PORT"

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

for phase_file in test/phase-*.sh; do
  MOCK_BIN=$MOCK_GITEA_BIN
  unset CONFUSIO_CONFIG
  # shellcheck source=/dev/null
  source "$phase_file"
done
