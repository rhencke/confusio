#!/usr/bin/env python3
"""Generate Makefile alias-mock rules from dump-families JSON.

Each family alias becomes one $(eval $(call ALIAS_MOCK_RULE,...)) line
in .make-families.mk, which the Makefile -includes so that mock-<alias>.com
is built from the root family's mock lua rather than a per-alias file.

Usage:
  ./redbean.com -i scripts/dump-families.lua 2>/dev/null | python3 scripts/gen-family-mk.py > .make-families.mk
"""
import json
import sys

families = json.load(sys.stdin)
for family in sorted(families, key=lambda f: f["root"]):
    root = family["root"]
    for alias in sorted(family["aliases"]):
        print(f"$(eval $(call ALIAS_MOCK_RULE,{alias},{root}))")
