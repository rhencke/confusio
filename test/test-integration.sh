#!/usr/bin/env bash
# Integration tests against live gitea.com — requires network access.
#
# TODO: extend to other platforms:
#   confusio = { backend="gitea", base_url="https://codeberg.org" }
set -euo pipefail

CONFUSIO_PORT=18080
TMPDIR_INT=$(mktemp -d)
cat > "$TMPDIR_INT/.confusio.lua" <<'EOF'
confusio = { backend = "gitea", base_url = "https://gitea.com" }
EOF
trap "rm -rf $TMPDIR_INT" EXIT

START="sh $(pwd)/confusio.com -p $CONFUSIO_PORT"
if command -v setsid >/dev/null 2>&1; then
  (cd "$TMPDIR_INT" && setsid $START) &
else
  (cd "$TMPDIR_INT" && $START) &
fi
PID=$!
trap "kill $PID 2>/dev/null || true; rm -rf $TMPDIR_INT" EXIT
./hurl --retry 10 --retry-interval 200 --connect-timeout 5 --max-time 15 \
  --variable host=localhost:$CONFUSIO_PORT test/gitea-root.hurl
