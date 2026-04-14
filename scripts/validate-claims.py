#!/usr/bin/env python3
"""Validate that CSV support claims agree with actual backend_impl handler presence.

Rules checked for each (backend, endpoint) cell in the CSV:
  y  — backend_impl must contain a handler for this endpoint, UNLESS the handler is
         confusio-native (a complete response synthesized by confusio itself, not the
         backend API — e.g. GET /meta, GET /zen).  Confusio-native handlers return
         real responses for every backend and are exempted from the handler-presence
         requirement.
  n  — backend_impl must NOT contain a handler for this endpoint
         (backend silently implements something the CSV calls unsupported → error)
  ~* — not checked (partial support may or may not have a dedicated handler)

The confusio-native handler set is small and explicit — update it here if catalog
defaults ever change.

Usage:
  ./redbean.com -i scripts/dump-claims.lua <backends...> 2>/dev/null \\
    | python3 scripts/validate-claims.py [csv]

  csv  path to compatibility CSV (default: site/compatibility.csv)

Exits non-zero if any mismatch is found.
"""
import csv
import json
import sys
from pathlib import Path

# Handlers whose catalog defaults are complete confusio-synthesised responses.
# These work for every backend without a per-backend handler, so a y claim is
# accurate even when backend_impl has no entry for them.
CONFUSIO_NATIVE = {"get_meta", "get_octocat", "get_teapot", "get_versions", "get_zen"}

csv_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("site/compatibility.csv")

data = json.load(sys.stdin)
endpoints = data["endpoints"]
backends = data["backends"]

with open(csv_path, newline="") as f:
    reader = csv.DictReader(f)
    csv_providers = [h for h in reader.fieldnames if h != "endpoint"]
    rows = list(reader)

errors = []
for row in rows:
    ep = row["endpoint"]
    # Find the catalog entry for this endpoint row.
    endpoint_info = next(
        (e for e in endpoints if e["method"] + " " + e["path"] == ep),
        None,
    )
    if endpoint_info is None:
        # validate-csv already catches orphan rows; skip here.
        continue
    handler = endpoint_info["handler"]
    for provider in csv_providers:
        if provider not in backends:
            continue
        claim = row.get(provider, "n")
        impl_handlers = set(backends.get(provider, []))
        has_handler = handler in impl_handlers
        if claim == "y" and not has_handler and handler not in CONFUSIO_NATIVE:
            errors.append(
                f"ERROR: {provider} claims 'y' for {ep}"
                f" but backend_impl has no handler '{handler}'"
            )
        elif claim == "n" and has_handler:
            errors.append(
                f"ERROR: {provider} claims 'n' for {ep}"
                f" but backend_impl defines handler '{handler}'"
            )

if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
