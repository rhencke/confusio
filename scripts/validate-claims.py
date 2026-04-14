#!/usr/bin/env python3
"""Validate that CSV support claims agree with actual backend_impl handler presence.

Rules checked for each (backend, endpoint) cell in the CSV:
  y  — backend_impl must contain a handler for this endpoint
         (claims native support but falls through to a stub → error)
  n  — backend_impl must NOT contain a handler for this endpoint
         (backend silently implements something the CSV calls unsupported → error)
  ~* — not checked (partial support may or may not have a dedicated handler)

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

csv_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("site/compatibility.csv")

data = json.load(sys.stdin)
endpoints = data["endpoints"]
backends = data["backends"]

# Build handler → endpoint lookup from catalog.
handler_to_ep = {e["handler"]: e["method"] + " " + e["path"] for e in endpoints}

with open(csv_path, newline="") as f:
    reader = csv.DictReader(f)
    csv_providers = [h for h in reader.fieldnames if h != "endpoint"]
    rows = list(reader)

errors = []
for row in rows:
    ep = row["endpoint"]
    # Find the handler name for this endpoint row.
    handler = next(
        (e["handler"] for e in endpoints if e["method"] + " " + e["path"] == ep),
        None,
    )
    if handler is None:
        # validate-csv already catches orphan rows; skip here.
        continue
    for provider in csv_providers:
        claim = row.get(provider, "n")
        impl_handlers = set(backends.get(provider, []))
        has_handler = handler in impl_handlers
        if claim == "y" and not has_handler:
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
