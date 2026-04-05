#!/usr/bin/env bash
# Run one backend's hurl test files in parallel against a dedicated server pair.
# Usage: run-backend.sh <mock_bin> <confusio_port> <mock_port> <confusio_args> [hurl_files...]
#
# confusio_args is a single string passed as-is to confusio (e.g. "-- gitea https://...")
# hurl_files are passed together to hurl --jobs so they run in parallel.
set -euo pipefail

case "$1" in /*) MOCK_BIN="$1" ;; *) MOCK_BIN="$(pwd)/$1" ;; esac
CPORT="$2"
MPORT="$3"
CONF_ARGS="$4"
shift 4
HURL_FILES=("$@")

CONFUSIO_BIN="$(pwd)/confusio.com"
HURL="$(pwd)/hurl"

start_isolated() {
  if command -v setsid >/dev/null 2>&1; then
    setsid "$@" &
  else
    "$@" &
  fi
}

tmpdir=$(mktemp -d)
# Kill entire process groups (setsid makes each server a group leader; redbean forks workers)
cleanup() {
  kill -- -"$CPID" 2>/dev/null || kill "$CPID" 2>/dev/null || true
  kill -- -"$MPID" 2>/dev/null || kill "$MPID" 2>/dev/null || true
  rm -rf "$tmpdir"
}
trap cleanup EXIT

# Start mock backend
start_isolated sh "$MOCK_BIN" -p "$MPORT"
MPID=$!

# Start confusio (with optional confusio_args)
if command -v setsid >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  (cd "$tmpdir" && setsid sh "$CONFUSIO_BIN" -p "$CPORT" $CONF_ARGS) &
else
  # shellcheck disable=SC2086
  (cd "$tmpdir" && sh "$CONFUSIO_BIN" -p "$CPORT" $CONF_ARGS) &
fi
CPID=$!

# Run all hurl files in parallel
"$HURL" --retry 20 --retry-interval 300 --connect-timeout 1 --max-time 10 \
  --variable "host=localhost:$CPORT" \
  --jobs "$(nproc)" \
  "${HURL_FILES[@]}"
