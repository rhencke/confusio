#!/usr/bin/env bash
# Integration tests against live gitea.com — requires network access.
#
# TODO: extend to other platforms:
#   confusio = { backend="gitea", base_url="https://codeberg.org" }
set -euo pipefail

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

TMPDIR_INT=$(mktemp -d)
cat > "$TMPDIR_INT/.confusio.lua" <<'EOF'
confusio = { backend = "gitea", base_url = "https://gitea.com" }
EOF
trap "rm -rf $TMPDIR_INT" EXIT

start_confusio "$TMPDIR_INT"
PID=$!
trap "kill $PID 2>/dev/null || true; rm -rf $TMPDIR_INT" EXIT
$HURL $HURL_RETRY --variable host=localhost:$CONFUSIO_PORT test/gitea-*.hurl
