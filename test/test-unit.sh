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
  start_isolated sh "$MOCK_GITEA_BIN" -p "$MOCK_PORT"; MOCK_PID=$!
  start_confusio "$tmpdir" "$@"; PID=$!
  trap "kill $PID 2>/dev/null || true; kill $MOCK_PID 2>/dev/null || true; rm -rf $tmpdir" EXIT
  run_hurl "$hurl_file"
  kill $PID 2>/dev/null || true; kill $MOCK_PID 2>/dev/null || true; sleep 0.3
}

MOCK_ARGS="-- gitea http://127.0.0.1:$MOCK_PORT"

# Phase 1: Gitea via CLI flags
run_mock_phase test/gitea-root.hurl $MOCK_ARGS

# Phase 2: Anonymous access (backend_allow_anonymous=true, no Authorization header)
run_mock_phase test/gitea-anon.hurl $MOCK_ARGS

# Phase 3: Checks API (check runs + check suites via Gitea commit statuses)
run_mock_phase test/gitea-checks.hurl $MOCK_ARGS

# Phase 4: Webhook signature verification with HMAC test vectors.
# CONFUSIO_WEBHOOK_SECRETS configures secrets; openssl computes the expected signatures
# at runtime so the test is never tied to a hard-coded pre-computed value.
WH_SECRET="webhooksecret"
WH_BODY="{}"
GITEA_SIG=$(printf '%s' "$WH_BODY" | openssl dgst -sha256 -hmac "$WH_SECRET" | awk '{print $NF}')
BB_SIG="sha256=${GITEA_SIG}"
GB_SIG="sha1=$(printf '%s' "$WH_BODY" | openssl dgst -sha1 -hmac "$WH_SECRET" | awk '{print $NF}')"
CONFUSIO_TS=$(date +%s)
CONFUSIO_SIG="sha256=$(printf 'v1:%s:%s' "$CONFUSIO_TS" "$WH_BODY" | openssl dgst -sha256 -hmac "$WH_SECRET" | awk '{print $NF}'), v=1, ts=${CONFUSIO_TS}"
WH_SECRETS_JSON="{\"gitea\":\"$WH_SECRET\",\"gitlab\":\"$WH_SECRET\",\"bitbucket\":\"$WH_SECRET\",\"gitbucket\":\"$WH_SECRET\",\"confusio\":\"$WH_SECRET\"}"
wh_dir=$(mktemp -d)
export CONFUSIO_WEBHOOK_SECRETS="$WH_SECRETS_JSON"
start_confusio "$wh_dir"; WH_PID=$!
trap "kill $WH_PID 2>/dev/null || true; unset CONFUSIO_WEBHOOK_SECRETS; rm -rf $wh_dir" EXIT
$HURL --retry 10 --retry-interval 200 --connect-timeout 1 --max-time 5 \
  --variable "host=localhost:$CONFUSIO_PORT" \
  --variable "gitea_sig=$GITEA_SIG" \
  --variable "gitlab_tok=$WH_SECRET" \
  --variable "bb_sig=$BB_SIG" \
  --variable "gb_sig=$GB_SIG" \
  --variable "confusio_sig=$CONFUSIO_SIG" \
  test/webhooks-sig.hurl
kill $WH_PID 2>/dev/null || true; sleep 0.3
unset CONFUSIO_WEBHOOK_SECRETS
