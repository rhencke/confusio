#!/usr/bin/env bash
# Integration tests against live gitea.com — requires network access.
#
# TODO: extend to other platforms:
#   sh confusio.com -- gitea https://codeberg.org
set -euo pipefail

if [ "${CONFUSIO_RUN_REAL_PROVIDER_TESTS:-}" != "1" ]; then
  echo "CONFUSIO_RUN_REAL_PROVIDER_TESTS=1 not set — skipping live provider integration tests"
  exit 0
fi

CONFUSIO_PORT=18200
DELIVERY_TARGET_PORT=18202
CONFUSIO_BIN=$(pwd)/confusio.com
DELIVERY_TARGET_BIN=$(pwd)/mock-target.com
HURL=$(pwd)/hurl
GITEA_NATIVE_LIVE_MANIFEST=$(pwd)/test/fixtures/webhooks/gitea/native-delivery-live.tsv
TMPDIR_INT=$(mktemp -d)

PID=
TARGET_PID=

cleanup() {
  if [ -n "${PID:-}" ]; then
    kill "$PID" 2>/dev/null || true
  fi
  if [ -n "${TARGET_PID:-}" ]; then
    kill "$TARGET_PID" 2>/dev/null || true
  fi
  rm -rf "$TMPDIR_INT"
}
trap cleanup EXIT

start_isolated() {
  if command -v setsid >/dev/null 2>&1; then
    setsid "$@" &
  else
    "$@" &
  fi
}

wait_http() {
  local label="$1"
  local url="$2"
  for _i in $(seq 1 150); do
    curl -sf --max-time 1 "$url" >/dev/null 2>&1 && return 0
    sleep 0.2
  done
  echo "timed out waiting for $label at $url" >&2
  return 1
}

start_confusio_live() {
  local target_arg="${1:-}"
  local shape_arg="${2:-}"
  local cmd="sh $CONFUSIO_BIN -p $CONFUSIO_PORT -- gitea https://gitea.com"
  if [ -n "$target_arg" ]; then
    cmd="$cmd $target_arg"
  fi
  if [ -n "$shape_arg" ]; then
    cmd="$cmd $shape_arg"
  fi
  if command -v setsid >/dev/null 2>&1; then
    (cd "$TMPDIR_INT" && setsid $cmd) &
  else
    (cd "$TMPDIR_INT" && $cmd) &
  fi
  PID=$!
  wait_http "confusio" "http://localhost:$CONFUSIO_PORT/"
}

stop_confusio_live() {
  if [ -n "${PID:-}" ]; then
    kill "$PID" 2>/dev/null || true
    PID=
    sleep 0.3
  fi
}

run_live_native_delivery_phase() {
  local shape="${1:-github}"
  local shape_env=()
  local shape_arg=""
  if [ "$shape" = "confusio" ]; then
    shape_env=(GITEA_NATIVE_DELIVERY_SHAPE=confusio)
    shape_arg="webhook_target_shape=confusio"
  fi

  start_isolated sh "$DELIVERY_TARGET_BIN" -u -p "$DELIVERY_TARGET_PORT"; TARGET_PID=$!
  start_confusio_live "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT" "$shape_arg"
  wait_http "mock target" "http://localhost:$DELIVERY_TARGET_PORT/deliveries"

  env STRICT_NATIVE_FIXTURES=1 \
    GITEA_NATIVE_DELIVERY_MANIFEST="$GITEA_NATIVE_LIVE_MANIFEST" \
    "${shape_env[@]}" \
    scripts/run-gitea-native-webhook-deliveries.sh \
    "localhost:$CONFUSIO_PORT" \
    "localhost:$DELIVERY_TARGET_PORT" \
    "$HURL"

  stop_confusio_live
  kill "$TARGET_PID" 2>/dev/null || true
  TARGET_PID=
  sleep 0.3
}

start_confusio_live

# The Gitea backend probes gitea.com at startup to check anonymous-access settings,
# so start_confusio_live polls the root endpoint before handing off to hurl.
./hurl --retry 10 --retry-interval 200 --connect-timeout 5 --max-time 15 \
  --variable host=localhost:$CONFUSIO_PORT test/gitea-root.hurl test/stub-apps.hurl \
  test/integration-graphql.hurl

# Phase 2: auth-gated GraphQL mutation smoke tests.
# Skipped when GITEA_TOKEN is absent (e.g. CI without the secret, anonymous runs).
if [ -n "${GITEA_TOKEN:-}" ]; then
  ./hurl --retry 3 --retry-interval 200 --connect-timeout 5 --max-time 30 \
    --variable host=localhost:$CONFUSIO_PORT \
    --variable gitea_token="$GITEA_TOKEN" \
    test/integration-graphql-mutations.hurl
else
  echo "GITEA_TOKEN not set — skipping authenticated GraphQL mutation integration tests"
fi

stop_confusio_live

run_live_native_delivery_phase github
run_live_native_delivery_phase confusio
