#!/usr/bin/env bash
# Unit tests — no real network access required.
set -euo pipefail

CONFUSIO_PORT=18080
MOCK_PORT=18081
CONFUSIO_BIN=$(pwd)/confusio.com
MOCK_BIN=$(pwd)/mock-gitea.com
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

# --- Phase 7: GitLab backend ---
_saved_mock="$MOCK_BIN"
MOCK_BIN="$MOCK_GITLAB_BIN"
run_mock_phase test/gitlab-repos.hurl -- backend=gitlab base_url=http://127.0.0.1:$MOCK_PORT
MOCK_BIN="$_saved_mock"

# --- Phase 8: GitBucket backend ---
_saved_mock="$MOCK_BIN"
MOCK_BIN="$MOCK_GITBUCKET_BIN"
run_mock_phase test/gitbucket-repos.hurl -- backend=gitbucket base_url=http://127.0.0.1:$MOCK_PORT
MOCK_BIN="$_saved_mock"

# --- Phase 9: Bitbucket backend ---
_saved_mock="$MOCK_BIN"
MOCK_BIN="$MOCK_BITBUCKET_BIN"
run_mock_phase test/bitbucket-repos.hurl -- backend=bitbucket base_url=http://127.0.0.1:$MOCK_PORT
MOCK_BIN="$_saved_mock"

# --- Phase 10: Harness backend ---
_saved_mock="$MOCK_BIN"
MOCK_BIN="$MOCK_HARNESS_BIN"
run_mock_phase test/harness-repos.hurl -- backend=harness base_url=http://127.0.0.1:$MOCK_PORT
MOCK_BIN="$_saved_mock"

# --- Phase 11: Pagure backend ---
_saved_mock="$MOCK_BIN"
MOCK_BIN="$MOCK_PAGURE_BIN"
run_mock_phase test/pagure-repos.hurl -- backend=pagure base_url=http://127.0.0.1:$MOCK_PORT
MOCK_BIN="$_saved_mock"

# --- Phase 12: OneDev backend ---
_saved_mock="$MOCK_BIN"
MOCK_BIN="$MOCK_ONEDEV_BIN"
run_mock_phase test/onedev-repos.hurl -- backend=onedev base_url=http://127.0.0.1:$MOCK_PORT
MOCK_BIN="$_saved_mock"

# --- Phase 13: Sourcehut backend ---
_saved_mock="$MOCK_BIN"
MOCK_BIN="$MOCK_SOURCEHUT_BIN"
run_mock_phase test/sourcehut-repos.hurl -- backend=sourcehut base_url=http://127.0.0.1:$MOCK_PORT
MOCK_BIN="$_saved_mock"

# --- Phase 14: Radicle backend ---
_saved_mock="$MOCK_BIN"
MOCK_BIN="$MOCK_RADICLE_BIN"
run_mock_phase test/radicle-repos.hurl -- backend=radicle base_url=http://127.0.0.1:$MOCK_PORT
MOCK_BIN="$_saved_mock"

# --- Phase 15: Bitbucket Datacenter backend ---
_saved_mock="$MOCK_BIN"
MOCK_BIN="$MOCK_BITBUCKET_DATACENTER_BIN"
run_mock_phase test/bitbucket_datacenter-repos.hurl -- backend=bitbucket_datacenter base_url=http://127.0.0.1:$MOCK_PORT
MOCK_BIN="$_saved_mock"
