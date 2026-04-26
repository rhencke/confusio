#!/usr/bin/env bash
# Generate webhook fixture directories for Gitea-family alias backends.
#
# test/fixtures/webhooks/gitea/ is the canonical template source (hand-maintained,
# committed).  Alias backends share the same payload format because they are
# API-compatible with Gitea.  Their fixture directories are produced by piping
# each template through jq — an identity transform for now, but jq makes
# per-backend field overrides straightforward to add later.
#
# Generated directories (relative to test_dir):
#   fixtures/webhooks/forgejo/
#
# Usage:
#   scripts/gen-webhook-fixtures.sh [test_dir]
#
#   test_dir  path to the test/ directory (default: test)

set -euo pipefail

TEST_DIR="${1:-test}"
TEMPLATE_DIR="$TEST_DIR/fixtures/webhooks/gitea"

if [ ! -d "$TEMPLATE_DIR" ]; then
  echo "ERROR: template directory not found: $TEMPLATE_DIR" >&2
  exit 1
fi

for backend in forgejo; do
  out_dir="$TEST_DIR/fixtures/webhooks/$backend"
  mkdir -p "$out_dir"
  for src in "$TEMPLATE_DIR"/*.json; do
    name=$(basename "$src")
    jq '.' "$src" > "$out_dir/$name"
  done
  count=$(ls "$out_dir"/*.json | wc -l | tr -d ' ')
  echo "gen-webhook-fixtures: $backend ($count files)"
done
