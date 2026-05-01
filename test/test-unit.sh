#!/usr/bin/env bash
# Unit test preamble — sequential boot-path checks.
# Backend tests (phases 4+) run in parallel via: $(MAKE) -j test-unit-backends
set -euo pipefail

CONFUSIO_PORT=18080
MOCK_PORT=18081
DELIVERY_TARGET_PORT=18082
CONFUSIO_BIN=$(pwd)/confusio.com
MOCK_GITEA_BIN=$(pwd)/mock-gitea.com
DELIVERY_TARGET_BIN=$(pwd)/mock-target.com
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

wait_port() {
  local name="$1"
  local port="$2"
  local i=0
  while ! (: >/dev/tcp/localhost/"$port") 2>/dev/null; do
    sleep 0.05
    i=$((i + 1))
    [ $i -lt 100 ] || {
      echo "$name did not start in time" >&2
      exit 1
    }
  done
}

wait_http() {
  local name="$1"
  local port="$2"
  local i=0
  while ! curl -sS -o /dev/null --connect-timeout 1 --max-time 1 "http://localhost:$port/" 2>/dev/null; do
    sleep 0.05
    i=$((i + 1))
    [ $i -lt 100 ] || {
      echo "$name did not answer HTTP in time" >&2
      exit 1
    }
  done
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

# run_delivery_phase: start confusio + mock gitea backend + mock delivery target,
# run the hurl file with both {{host}} (confusio) and {{target}} (delivery target) vars.
run_delivery_phase() {
  local hurl_file="$1"; shift
  local tmpdir; tmpdir=$(mktemp -d)
  # Delivery target must run uniprocess (-u) so its global delivery log persists.
  start_isolated sh "$DELIVERY_TARGET_BIN" -u -p "$DELIVERY_TARGET_PORT"; TARGET_PID=$!
  start_isolated sh "$MOCK_GITEA_BIN" -p "$MOCK_PORT"; MOCK_PID=$!
  start_confusio "$tmpdir" "$@"; PID=$!
  trap "kill $PID 2>/dev/null || true; kill $MOCK_PID 2>/dev/null || true; kill $TARGET_PID 2>/dev/null || true; rm -rf $tmpdir" EXIT
  # Wait until confusio is listening before running hurl.
  # synthesize_startup_events fires during .init.lua — before the server accepts
  # connections — so once we can TCP-connect, all startup events have already landed
  # in the delivery target.  The hurl file's opening /reset can then safely clear them.
  wait_port "mock target" "$DELIVERY_TARGET_PORT"
  wait_port "mock gitea" "$MOCK_PORT"
  wait_http "confusio" "$CONFUSIO_PORT"
  # Do not pass --retry here: these hurl files contain non-idempotent webhook POSTs.
  # Retrying a POST after a transient assertion/transport failure records duplicate
  # deliveries in the mock target and turns the next count assertion into a false
  # failure.
  $HURL --connect-timeout 1 --max-time 5 \
    --variable "host=localhost:$CONFUSIO_PORT" \
    --variable "target=localhost:$DELIVERY_TARGET_PORT" \
    "$hurl_file"
  kill $PID 2>/dev/null || true; kill $MOCK_PID 2>/dev/null || true; kill $TARGET_PID 2>/dev/null || true; sleep 0.3
}

MOCK_ARGS="-- gitea http://127.0.0.1:$MOCK_PORT"

# Phase 1: Gitea via CLI flags
run_mock_phase test/gitea-root.hurl $MOCK_ARGS

# Phase 2: Anonymous access (backend_allow_anonymous=true, no Authorization header)
run_mock_phase test/gitea-anon.hurl $MOCK_ARGS

# Phase 3: Checks API (check runs + check suites via Gitea commit statuses)
run_mock_phase test/gitea-checks.hurl $MOCK_ARGS

# Phase 4: Webhook signature verification with HMAC test vectors.
# Secrets are read from 0600-permission files via webhook_secret_file_BACKEND=PATH.
# openssl computes the expected signatures at runtime so the test is never tied
# to a hard-coded pre-computed value.
WH_SECRET="webhooksecret"
WH_BODY="{}"
GITEA_SIG=$(printf '%s' "$WH_BODY" | openssl dgst -sha256 -hmac "$WH_SECRET" | awk '{print $NF}')
BB_SIG="sha256=${GITEA_SIG}"
GB_SIG="sha1=$(printf '%s' "$WH_BODY" | openssl dgst -sha1 -hmac "$WH_SECRET" | awk '{print $NF}')"
LAUNCHPAD_SIG="$GB_SIG"
PAGURE_SIG_256="$GITEA_SIG"
PAGURE_SIG_512=$(printf '%s' "$WH_BODY" | openssl dgst -sha512 -hmac "$WH_SECRET" | awk '{print $NF}')
AZUREDEVOPS_SECRET="fido:$WH_SECRET"
AZUREDEVOPS_BASIC=$(printf '%s' "$AZUREDEVOPS_SECRET" | openssl base64 -A)
GERRIT_BASIC=$(printf '%s' "$WH_SECRET" | openssl base64 -A)
CONFUSIO_TS=$(date +%s)
CONFUSIO_SIG="sha256=$(printf 'v1:%s:%s' "$CONFUSIO_TS" "$WH_BODY" | openssl dgst -sha256 -hmac "$WH_SECRET" | awk '{print $NF}'), v=1, ts=${CONFUSIO_TS}"
# Write secrets to 0600-permission files — never pass raw secrets on the CLI.
WH_SECRET_DIR=$(mktemp -d)
for wh_backend in gitea codeberg gitlab bitbucket bitbucket_datacenter gitbucket launchpad phabricator pagure gerrit onedev kallithea confusio; do
  printf '%s' "$WH_SECRET" > "$WH_SECRET_DIR/$wh_backend.secret"
  chmod 600 "$WH_SECRET_DIR/$wh_backend.secret"
done
printf '%s' "$AZUREDEVOPS_SECRET" > "$WH_SECRET_DIR/azuredevops.secret"
chmod 600 "$WH_SECRET_DIR/azuredevops.secret"
WH_CLI_ARGS="-- webhook_secret_file_gitea=$WH_SECRET_DIR/gitea.secret webhook_secret_file_codeberg=$WH_SECRET_DIR/codeberg.secret webhook_secret_file_gitlab=$WH_SECRET_DIR/gitlab.secret webhook_secret_file_bitbucket=$WH_SECRET_DIR/bitbucket.secret webhook_secret_file_bitbucket_datacenter=$WH_SECRET_DIR/bitbucket_datacenter.secret webhook_secret_file_gitbucket=$WH_SECRET_DIR/gitbucket.secret webhook_secret_file_launchpad=$WH_SECRET_DIR/launchpad.secret webhook_secret_file_phabricator=$WH_SECRET_DIR/phabricator.secret webhook_secret_file_pagure=$WH_SECRET_DIR/pagure.secret webhook_secret_file_azuredevops=$WH_SECRET_DIR/azuredevops.secret webhook_secret_file_gerrit=$WH_SECRET_DIR/gerrit.secret webhook_secret_file_onedev=$WH_SECRET_DIR/onedev.secret webhook_secret_file_kallithea=$WH_SECRET_DIR/kallithea.secret webhook_secret_file_confusio=$WH_SECRET_DIR/confusio.secret"
wh_dir=$(mktemp -d)
start_confusio "$wh_dir" "$WH_CLI_ARGS"; WH_PID=$!
trap "kill $WH_PID 2>/dev/null || true; rm -rf $wh_dir; rm -rf $WH_SECRET_DIR" EXIT
$HURL --retry 10 --retry-interval 200 --connect-timeout 1 --max-time 5 \
  --variable "host=localhost:$CONFUSIO_PORT" \
  --variable "gitea_sig=$GITEA_SIG" \
  --variable "gitlab_tok=$WH_SECRET" \
  --variable "bb_sig=$BB_SIG" \
  --variable "gb_sig=$GB_SIG" \
  --variable "launchpad_sig=$LAUNCHPAD_SIG" \
  --variable "phabricator_sig=$GITEA_SIG" \
  --variable "pagure_sig_256=$PAGURE_SIG_256" \
  --variable "pagure_sig_512=$PAGURE_SIG_512" \
  --variable "azuredevops_basic=$AZUREDEVOPS_BASIC" \
  --variable "gerrit_tok=$WH_SECRET" \
  --variable "gerrit_basic=$GERRIT_BASIC" \
  --variable "onedev_tok=$WH_SECRET" \
  --variable "confusio_sig=$CONFUSIO_SIG" \
  test/webhooks-sig.hurl
kill $WH_PID 2>/dev/null || true; sleep 0.3

# Phase 5: Gitea webhook event normalisers (issues, issue_comment, label, milestone)
run_mock_phase test/gitea-webhooks.hurl $MOCK_ARGS

# Phase 6: Outbound webhook delivery — confusio forwards to the mock delivery target.
# Delivery target runs on DELIVERY_TARGET_PORT (18082); confusio is wired to it via
# webhook_target=URL.  The hurl file uses {{target}} to query the delivery log.
run_delivery_phase test/webhook-delivery.hurl \
  -- gitea "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT"

# Phase 7: Gitea fixture-based delivery tests — every event × action triple.
# Uses fixture files from test/fixtures/webhooks/gitea/ instead of inline payloads.
# Verifies github_event, github_delivery UUID, and confusio User-Agent for each.
run_delivery_phase test/webhook-delivery-gitea.hurl \
  -- gitea "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT"

# Phase 8: Gitea delivery with "confusio" shape — spot-checks X-Confusio-* headers.
# Runs the same fixture files but with webhook_target_shape=confusio to verify the
# alternate header set (X-Confusio-Event/Source/Delivery) instead of X-GitHub-*.
run_delivery_phase test/webhook-delivery-gitea-confusio-shape.hurl \
  -- gitea "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT" \
  "webhook_target_shape=confusio"

# Phase 9: GitLab fixture-based delivery tests — every event × action triple.
# Uses fixture files from test/fixtures/webhooks/gitlab/ instead of inline payloads.
# GitLab backend does not probe the upstream at startup, so the mock URL is unused
# during these tests (only the webhook receiver path is exercised).
run_delivery_phase test/webhook-delivery-gitlab.hurl \
  -- gitlab "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT"

# Phase 10: GitLab delivery with "confusio" shape — spot-checks X-Confusio-* headers.
# Verifies X-Confusio-Source is "gitlab" and X-GitHub-Event is absent.
run_delivery_phase test/webhook-delivery-gitlab-confusio-shape.hurl \
  -- gitlab "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT" \
  "webhook_target_shape=confusio"

# Phase 11: Bitbucket Cloud fixture-based delivery tests — every event × action triple.
# Uses fixture files from test/fixtures/webhooks/bitbucket/ instead of inline payloads.
# Bitbucket Cloud backend does not probe the upstream at startup, so the mock URL is unused
# during these tests (only the webhook receiver path is exercised).
run_delivery_phase test/webhook-delivery-bitbucket.hurl \
  -- bitbucket "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT"

# Phase 12: Bitbucket Cloud delivery with "confusio" shape — spot-checks X-Confusio-* headers.
# Verifies X-Confusio-Source is "bitbucket" and X-GitHub-Event is absent.
run_delivery_phase test/webhook-delivery-bitbucket-confusio-shape.hurl \
  -- bitbucket "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT" \
  "webhook_target_shape=confusio"

# Phase 13: Bitbucket Datacenter fixture-based delivery tests — every event × action triple.
# Uses fixture files from test/fixtures/webhooks/bitbucket_datacenter/ instead of inline payloads.
# Bitbucket Datacenter backend does not probe the upstream at startup.
run_delivery_phase test/webhook-delivery-bitbucket_datacenter.hurl \
  -- bitbucket_datacenter "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT"

# Phase 14: Bitbucket Datacenter delivery with "confusio" shape — spot-checks X-Confusio-* headers.
# Verifies X-Confusio-Source is "bitbucket_datacenter" and X-GitHub-Event is absent.
run_delivery_phase test/webhook-delivery-bitbucket_datacenter-confusio-shape.hurl \
  -- bitbucket_datacenter "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT" \
  "webhook_target_shape=confusio"

# Phase 15: Azure DevOps fixture-based delivery tests — every event type.
# Azure DevOps embeds eventType in the body; no event-type header is required.
run_delivery_phase test/webhook-delivery-azuredevops.hurl \
  -- azuredevops "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT"

# Phase 16: Azure DevOps delivery with "confusio" shape — spot-checks X-Confusio-* headers.
# Verifies X-Confusio-Source is "azuredevops" and X-GitHub-Event is absent.
run_delivery_phase test/webhook-delivery-azuredevops-confusio-shape.hurl \
  -- azuredevops "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT" \
  "webhook_target_shape=confusio"

# Phase 17: Gerrit fixture-based delivery tests — comment-added event.
# Gerrit embeds the event type in the body (payload.type); no event-type header required.
run_delivery_phase test/webhook-delivery-gerrit.hurl \
  -- gerrit "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT"

# Phase 18: Gerrit delivery with "confusio" shape — spot-checks X-Confusio-* headers.
# Verifies X-Confusio-Source is "gerrit" and X-GitHub-Event is absent.
run_delivery_phase test/webhook-delivery-gerrit-confusio-shape.hurl \
  -- gerrit "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT" \
  "webhook_target_shape=confusio"

# Phase 19: Gitblit fixture-based delivery tests — post-receive ref commands.
run_delivery_phase test/webhook-delivery-gitblit.hurl \
  -- gitblit "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT"

# Phase 20: Gitblit delivery with "confusio" shape — spot-checks normalized ref events.
run_delivery_phase test/webhook-delivery-gitblit-confusio-shape.hurl \
  -- gitblit "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT" \
  "webhook_target_shape=confusio"

# Phase 21: GitBucket fixture-based delivery tests — every event × action triple.
# GitBucket uses X-GitHub-Event header (GitHub-compatible format).
run_delivery_phase test/webhook-delivery-gitbucket.hurl \
  -- gitbucket "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT"

# Phase 22: GitBucket delivery with "confusio" shape — spot-checks X-Confusio-* headers.
# Verifies X-Confusio-Source is "gitbucket" and X-GitHub-Event is absent.
run_delivery_phase test/webhook-delivery-gitbucket-confusio-shape.hurl \
  -- gitbucket "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT" \
  "webhook_target_shape=confusio"

# Phase 23: Gogs fixture-based delivery tests — every native event × action triple.
# Gogs uses X-Gogs-Event header to indicate the event type.
run_delivery_phase test/webhook-delivery-gogs.hurl \
  -- gogs "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT"

# Phase 24: Gogs delivery with "confusio" shape — spot-checks X-Confusio-* headers.
# Verifies X-Confusio-Source is "gogs" and X-GitHub-Event is absent.
run_delivery_phase test/webhook-delivery-gogs-confusio-shape.hurl \
  -- gogs "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT" \
  "webhook_target_shape=confusio"

# Phase 25: NotABug fixture-based delivery tests — every native event × action triple.
# NotABug uses X-Gogs-Event header to indicate the event type.
run_delivery_phase test/webhook-delivery-notabug.hurl \
  -- notabug "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT"

# Phase 26: NotABug delivery with "confusio" shape — spot-checks X-Confusio-* headers.
# Verifies X-Confusio-Source is "notabug" and X-GitHub-Event is absent.
run_delivery_phase test/webhook-delivery-notabug-confusio-shape.hurl \
  -- notabug "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT" \
  "webhook_target_shape=confusio"

# Phase 27: Harness fixture-based delivery tests — pipeline and stage events.
# Harness embeds eventType in the body; no event-type header is required.
run_delivery_phase test/webhook-delivery-harness.hurl \
  -- harness "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT"

# Phase 28: Harness delivery with "confusio" shape — spot-checks X-Confusio-* headers.
# Verifies X-Confusio-Source is "harness" and X-GitHub-Event is absent.
run_delivery_phase test/webhook-delivery-harness-confusio-shape.hurl \
  -- harness "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT" \
  "webhook_target_shape=confusio"

# Phase 29: Pagure fixture-based delivery tests — every event type.
# Pagure uses X-Pagure-Event header to indicate the event type.
run_delivery_phase test/webhook-delivery-pagure.hurl \
  -- pagure "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT"

# Phase 30: Pagure delivery with "confusio" shape — spot-checks X-Confusio-* headers.
# Verifies X-Confusio-Source is "pagure" and X-GitHub-Event is absent.
run_delivery_phase test/webhook-delivery-pagure-confusio-shape.hurl \
  -- pagure "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT" \
  "webhook_target_shape=confusio"

# Phase 31: Kallithea fixture-based delivery tests — native body-typed hooks.
run_delivery_phase test/webhook-delivery-kallithea.hurl \
  -- kallithea "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT"

# Phase 32: Kallithea delivery with "confusio" shape — normalized hook envelopes.
run_delivery_phase test/webhook-delivery-kallithea-confusio-shape.hurl \
  -- kallithea "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT" \
  "webhook_target_shape=confusio"

# Phase 33: Forgejo fixture-based delivery tests — every event × action triple.
# Forgejo uses X-Gitea-Event header (API-compatible with Gitea).
run_delivery_phase test/webhook-delivery-forgejo.hurl \
  -- forgejo "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT"

# Phase 34: Forgejo delivery with "confusio" shape — spot-checks X-Confusio-* headers.
# Verifies X-Confusio-Source is "forgejo" and X-GitHub-Event is absent.
run_delivery_phase test/webhook-delivery-forgejo-confusio-shape.hurl \
  -- forgejo "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT" \
  "webhook_target_shape=confusio"

# Phase 35: Codeberg fixture-based delivery tests — every event × action triple.
# Codeberg uses X-Gitea-Event header (API-compatible with Gitea/Forgejo).
run_delivery_phase test/webhook-delivery-codeberg.hurl \
  -- codeberg "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT"

# Phase 36: Codeberg delivery with "confusio" shape — spot-checks X-Confusio-* headers.
# Verifies X-Confusio-Source is "codeberg" and X-GitHub-Event is absent.
run_delivery_phase test/webhook-delivery-codeberg-confusio-shape.hurl \
  -- codeberg "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT" \
  "webhook_target_shape=confusio"

# Phase 37: Launchpad fixture-based delivery tests — every native event family.
# Launchpad uses X-Launchpad-Event-Type to indicate the native event type.
run_delivery_phase test/webhook-delivery-launchpad.hurl \
  -- launchpad "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT"

# Phase 38: OneDev fixture-based delivery tests — native body-typed hooks.
run_delivery_phase test/webhook-delivery-onedev.hurl \
  -- onedev "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT"

# Phase 39: OneDev delivery with "confusio" shape — normalized hook envelopes.
run_delivery_phase test/webhook-delivery-onedev-confusio-shape.hurl \
  -- onedev "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT" \
  "webhook_target_shape=confusio"

# Phase 40: Startup event synthesis — github shape.
# Verifies that confusio synthesizes installation.created and
# installation_repositories.added before accepting connections, and delivers
# both to the configured outbound target.  No /reset is called — the hurl file
# queries the delivery log directly to see the two startup events.
run_delivery_phase test/webhook-delivery-startup.hurl \
  -- gitea "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT"

# Phase 41: Startup event synthesis — confusio shape.
# Same as Phase 40 but with webhook_target_shape=confusio; verifies
# X-Confusio-* headers are used and X-GitHub-Event is absent.
run_delivery_phase test/webhook-delivery-startup-confusio-shape.hurl \
  -- gitea "http://127.0.0.1:$MOCK_PORT" \
  "webhook_target=http://127.0.0.1:$DELIVERY_TARGET_PORT" \
  "webhook_target_shape=confusio"
