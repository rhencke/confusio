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
TMPDIR_INT=$(mktemp -d)
trap "rm -rf $TMPDIR_INT" EXIT

START="sh $(pwd)/confusio.com -p $CONFUSIO_PORT -- gitea https://gitea.com"
if command -v setsid >/dev/null 2>&1; then
  (cd "$TMPDIR_INT" && setsid $START) &
else
  (cd "$TMPDIR_INT" && $START) &
fi
PID=$!
trap "kill $PID 2>/dev/null || true; rm -rf $TMPDIR_INT" EXIT

# The Gitea backend probes gitea.com at startup to check anonymous-access settings,
# so the server may not be ready for up to ~10 seconds on a cold network path.
# Poll until the root endpoint responds before handing off to hurl.
for _i in $(seq 1 150); do
  curl -sf --max-time 1 "http://localhost:$CONFUSIO_PORT/" >/dev/null 2>&1 && break
  sleep 0.2
done

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
