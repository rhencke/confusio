#!/usr/bin/env python3
"""Validate webhook fixture files against delivery hurl declarations.

For each backend that has a webhook-delivery-<backend>.hurl file:
  - Every file,fixtures/webhooks/<backend>/<name>.json reference in the hurl file
    must have a corresponding file in test/fixtures/webhooks/<backend>/.
  - Every file in test/fixtures/webhooks/<backend>/ must be referenced in the
    hurl file (no orphaned fixture files).

Usage:
  python3 scripts/validate-fixtures.py [test_dir]

  test_dir  path to the test directory (default: test)

Exits non-zero if any fixture is missing or undeclared.
"""
import re
import sys
from pathlib import Path

test_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("test")
fixtures_root = test_dir / "fixtures" / "webhooks"

# Pattern matching "file,fixtures/webhooks/<backend>/<filename>.json;"
FILE_REF_RE = re.compile(r"file,fixtures/webhooks/([^/]+)/([^;]+\.json);")

errors = []

# Find all primary delivery hurl files (exclude confusio-shape variants).
hurl_files = sorted(test_dir.glob("webhook-delivery-*.hurl"))
hurl_files = [f for f in hurl_files if "confusio-shape" not in f.name]

if not hurl_files:
    print("ERROR: no webhook-delivery-*.hurl files found under", test_dir, file=sys.stderr)
    sys.exit(1)

for hurl_file in hurl_files:
    # Extract backend name from filename: webhook-delivery-<backend>.hurl
    backend = hurl_file.stem[len("webhook-delivery-"):]
    fixture_dir = fixtures_root / backend

    content = hurl_file.read_text()
    declared = set()
    for _backend_ref, filename in FILE_REF_RE.findall(content):
        declared.add(filename)

    # Gather actual fixture files on disk.
    if fixture_dir.is_dir():
        actual = {f.name for f in fixture_dir.iterdir() if f.suffix == ".json"}
    else:
        actual = set()

    missing = sorted(declared - actual)
    extra = sorted(actual - declared)

    for name in missing:
        errors.append(
            f"MISSING fixture: test/fixtures/webhooks/{backend}/{name}"
            f"  (declared in {hurl_file.name} but file does not exist)"
        )
    for name in extra:
        errors.append(
            f"EXTRA fixture: test/fixtures/webhooks/{backend}/{name}"
            f"  (file exists but not referenced in {hurl_file.name})"
        )

if errors:
    for msg in errors:
        print(msg, file=sys.stderr)
    sys.exit(1)

print("validate-fixtures OK")
