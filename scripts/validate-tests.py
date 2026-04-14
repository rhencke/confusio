#!/usr/bin/env python3
"""Report catalog groups with no test coverage for any backend.

Usage:
  ./redbean.com -i scripts/dump-endpoints.lua 2>/dev/null | python3 scripts/validate-tests.py <backend>...

A group has coverage for a backend if either:
  test/<backend>-<group>.hurl  exists (backend-specific), or
  test/stub-<group>.hurl       exists (shared stub fallback).

Groups with neither file are reported to stderr. Exits non-zero if any
gap is found.
"""
import json
import os
import sys

catalog = json.load(sys.stdin)
groups = list(dict.fromkeys(e["group"] for e in catalog))
backends = sys.argv[1:]

gaps = []
for b in backends:
    for g in groups:
        if not os.path.exists(f"test/{b}-{g}.hurl") and not os.path.exists(
            f"test/stub-{g}.hurl"
        ):
            gaps.append(f"{b}/{g}")

if gaps:
    for gap in gaps:
        print(f"ERROR: no test coverage for {gap}", file=sys.stderr)
    sys.exit(1)
