#!/usr/bin/env python3
"""Validate that every row in compatibility.csv corresponds to a catalog endpoint.

Usage:
  ./redbean.com -i scripts/dump-endpoints.lua 2>/dev/null | python3 scripts/validate-csv.py [csv]

  csv  path to compatibility CSV (default: site/compatibility.csv)

Exits non-zero if any CSV endpoint is not found in the catalog.
"""
import csv
import json
import sys
from pathlib import Path

csv_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("site/compatibility.csv")

catalog = json.load(sys.stdin)
catalog_eps = {e["method"] + " " + e["path"] for e in catalog}

with open(csv_path, newline="") as f:
    reader = csv.DictReader(f)
    providers = [h for h in reader.fieldnames if h != "endpoint"]
    csv_eps = [row["endpoint"] for row in reader]

orphans = [ep for ep in csv_eps if ep not in catalog_eps]
if orphans:
    for ep in orphans:
        print(f"ERROR: CSV row not in catalog: {ep}", file=sys.stderr)
    sys.exit(1)
