#!/usr/bin/env python3
"""Validate provider-family metadata consistency.

Checks that provider_families in .init.lua agrees with:
  - backend files (each alias calls load_family_backend)
  - mock files (no stale test/mock-<alias>.lua for aliases)
  - Makefile <ROOT_UPPER>_FAMILY_ALIASES variable
  - Makefile BACKENDS list (every alias must be present)

Usage:
  ./redbean.com -i scripts/dump-families.lua 2>/dev/null | python3 scripts/validate-providers.py

Exits non-zero if any inconsistency is found.
"""
import json
import os
import re
import sys

families = json.load(sys.stdin)
errors = []

with open("Makefile") as f:
    makefile = f.read()

# Parse BACKENDS (may span continuation lines).
backends_match = re.search(
    r"^BACKENDS\s*=\s*((?:[^\n]*\\\n\s*)*[^\n]+)", makefile, re.MULTILINE
)
backends = set()
if backends_match:
    raw = backends_match.group(1).replace("\\\n", " ")
    backends = set(raw.split())
else:
    errors.append("ERROR: BACKENDS variable not found in Makefile")

for family in families:
    root = family["root"]
    aliases = family["aliases"]
    root_upper = root.upper()

    # Root backend and mock must exist.
    if not os.path.exists(f"backends/{root}.lua"):
        errors.append(f"ERROR: missing backend for family root: backends/{root}.lua")
    if not os.path.exists(f"test/mock-{root}.lua"):
        errors.append(f"ERROR: missing mock for family root: test/mock-{root}.lua")

    for alias in aliases:
        # Alias backend must exist and call load_family_backend.
        backend_path = f"backends/{alias}.lua"
        if not os.path.exists(backend_path):
            errors.append(f"ERROR: missing backend for alias {alias}: {backend_path}")
        else:
            with open(backend_path) as f:
                content = f.read()
            if "load_family_backend" not in content:
                errors.append(
                    f"ERROR: {backend_path} does not call load_family_backend"
                )

        # No stale per-alias mock lua (aliases share the root mock via the Makefile rule).
        if os.path.exists(f"test/mock-{alias}.lua"):
            errors.append(
                f"ERROR: stale mock file test/mock-{alias}.lua"
                f" (aliases use test/mock-{root}.lua via ALIAS_MOCK_RULE)"
            )

        # Every alias must appear in BACKENDS.
        if backends and alias not in backends:
            errors.append(f"ERROR: alias {alias} missing from Makefile BACKENDS")

    # Makefile <ROOT_UPPER>_FAMILY_ALIASES must match provider_families aliases.
    makefile_var = f"{root_upper}_FAMILY_ALIASES"
    var_match = re.search(
        rf"^{makefile_var}\s*:?=\s*(.+)$", makefile, re.MULTILINE
    )
    if not var_match:
        errors.append(f"ERROR: {makefile_var} not found in Makefile")
    else:
        makefile_aliases = set(var_match.group(1).split())
        metadata_aliases = set(aliases)
        for a in metadata_aliases - makefile_aliases:
            errors.append(
                f"ERROR: alias {a} in provider_families but missing from {makefile_var}"
            )
        for a in makefile_aliases - metadata_aliases:
            errors.append(
                f"ERROR: alias {a} in {makefile_var} but missing from provider_families"
            )

if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
