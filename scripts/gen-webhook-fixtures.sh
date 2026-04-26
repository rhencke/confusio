#!/usr/bin/env bash
# Generate webhook fixture files.
#
# Two generation modes:
#
# 1. Cross-backend aliases: test/fixtures/webhooks/gitea/ is the canonical
#    template source (hand-maintained, committed).  Alias backends share the
#    same payload format because they are API-compatible with Gitea.  Their
#    fixture directories are produced by piping each template through jq.
#
#    Generated directories (relative to test_dir):
#      fixtures/webhooks/forgejo/
#
# 2. Within-backend variants: some fixture files are derived from a sibling
#    file in the same backend directory via a small jq transformation.  The
#    source file is hand-maintained and committed; the derived file is
#    gitignored.
#
#    Currently generated (source → derived):
#      <backend>/create.json → <backend>/delete.json
#
#    Backends covered: gitea, gitbucket, gitlab, pagure, azuredevops,
#    bitbucket_datacenter.  (Bitbucket Cloud is omitted — the create/delete
#    payloads have structurally different shapes, not just field value
#    changes.)
#
# Usage:
#   scripts/gen-webhook-fixtures.sh [test_dir]
#
#   test_dir  path to the test/ directory (default: test)

set -euo pipefail

TEST_DIR="${1:-test}"
FIXTURES="$TEST_DIR/fixtures/webhooks"

if [ ! -d "$FIXTURES/gitea" ]; then
  echo "ERROR: template directory not found: $FIXTURES/gitea" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. Within-backend variants: derive delete.json from create.json
#
# Run this BEFORE the cross-backend alias step so that gitea/delete.json
# exists when forgejo is generated from gitea.
#
# Table format: backend|jq-filter
# The filter is applied to <backend>/create.json → <backend>/delete.json.
# ---------------------------------------------------------------------------
while IFS='|' read -r backend filter; do
  src="$FIXTURES/$backend/create.json"
  dst="$FIXTURES/$backend/delete.json"
  if [ ! -f "$src" ]; then
    echo "WARNING: source not found, skipping: $src" >&2
    continue
  fi
  jq "$filter" "$src" > "$dst"
  echo "gen-webhook-fixtures: $backend/delete.json (from create.json)"
done <<'VARIANTS'
gitea|.ref = "old-branch"
gitbucket|.ref = "stale-branch"
gitlab|.before = "95790bf891e76fee5db5ef17d2523a6f6e048239" | .after = "0000000000000000000000000000000000000000" | .ref = "refs/heads/stale-branch" | .checkout_sha = null
pagure|.msg.branch = "refs/heads/stale-branch" | .msg.start_commit = "95790bf891e76fee5db5ef17d2523a6f6e048239" | .msg.end_commit = "0000000000000000000000000000000000000000"
azuredevops|.resource.refUpdates[0].name = "refs/heads/stale-branch" | .resource.refUpdates[0].oldObjectId = "95790bf891e76fee5db5ef17d2523a6f6e048239" | .resource.refUpdates[0].newObjectId = "0000000000000000000000000000000000000000" | .resource.pushId = 3 | .createdDate = "2024-01-15T12:00:00Z"
bitbucket_datacenter|.changes[0].ref.id = "refs/heads/stale-branch" | .changes[0].ref.displayId = "stale-branch" | .changes[0].refId = "refs/heads/stale-branch" | .changes[0].fromHash = "95790bf891e76fee5db5ef17d2523a6f6e048239" | .changes[0].toHash = "0000000000000000000000000000000000000000" | .changes[0].type = "DELETE"
VARIANTS

# ---------------------------------------------------------------------------
# 2. Cross-backend aliases: derive forgejo/ from gitea/
#
# Must run AFTER step 1 so that gitea/delete.json (generated above) is
# present and gets copied into forgejo/ as well.
# ---------------------------------------------------------------------------
for backend in forgejo; do
  out_dir="$FIXTURES/$backend"
  mkdir -p "$out_dir"
  for src in "$FIXTURES/gitea"/*.json; do
    name=$(basename "$src")
    jq '.' "$src" > "$out_dir/$name"
  done
  count=$(ls "$out_dir"/*.json | wc -l | tr -d ' ')
  echo "gen-webhook-fixtures: $backend ($count files)"
done
