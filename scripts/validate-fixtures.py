#!/usr/bin/env python3
"""Validate webhook fixture files against delivery hurl declarations and catalog.

For each backend that has a webhook-delivery-<backend>.hurl file:
  - Every file,fixtures/webhooks/<backend>/<name>.json reference in the hurl file
    must have a corresponding file in test/fixtures/webhooks/<backend>/.
  - Every fixture file must either be referenced by a delivery hurl file or map
    to a webhook event family in the coverage catalog.
  - Every hurl-declared webhook event and normalized confusio shape assertion
    must match the coverage catalog.

Usage:
  python3 scripts/validate-fixtures.py [test_dir] [catalog_json]

  test_dir  path to the test directory (default: test)
  catalog_json  webhook catalog JSON from scripts/dump-webhook-catalog.lua

Exits non-zero if any fixture is missing, undeclared by both hurl and catalog,
or if hurl/docs shape metadata drifts away from the catalog.
"""
import json
import re
import sys
from pathlib import Path

test_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("test")
catalog_path = Path(sys.argv[2]) if len(sys.argv) > 2 else None
fixtures_root = test_dir / "fixtures" / "webhooks"

# Pattern matching "file,fixtures/webhooks/<backend>/<filename>.json;"
FILE_REF_RE = re.compile(r"file,fixtures/webhooks/([^/]+)/([^;]+\.json);")
EVENT_HEADER_RE = re.compile(r"^X-GitHub-Event:\s*(\S+)\s*$")
CONFUSIO_EVENT_RE = re.compile(r'jsonpath "\$\[0\]\.confusio_event" == "([^"]+)"')
NORMALIZED_TYPE_RE = re.compile(r'jsonpath "\$\[0\]\.body_json\.type" == "([^"]+)"')

FILENAME_EVENT_ALIASES = {
    "advsec-code-alert": "code_scanning_alert",
    "advsec-dependency-alert": "dependabot_alert",
    "advsec-secret-alert": "secret_scanning_alert",
    "build.complete": "workflow_run",
    "commit_comment": "pull_request_review_comment",
    "deployment-approval": "deployment_review",
    "deployment-completed": "deployment_status",
    "deployment-started": "deployment",
    "git.pullrequest": "pull_request",
    "pipeline_execution": "workflow_run",
    "pull-request": "pull_request",
    "pull_request_approved": "pull_request_review",
    "pull_request_comment": "pull_request_review_comment",
    "pull_request_rejected": "pull_request_review",
    "stage_execution": "workflow_job",
    "wiki": "gollum",
    "workitem": "issues",
    "issue": "issues",
}

errors = []

catalog = None
catalog_events = {}
catalog_providers = set()
normalized_bases = {}
events_by_normalized_base = {}

if catalog_path is not None:
    catalog = json.loads(catalog_path.read_text())
    catalog_providers = set(catalog.get("providers", []))
    for event in catalog.get("events", []):
        name = event["name"]
        catalog_events[name] = event
        base = event["normalized_base"]
        normalized_bases[name] = base
        events_by_normalized_base.setdefault(base, []).append(event)


def event_actions(event_name):
    event = catalog_events.get(event_name)
    if not event:
        return set()
    return set(event.get("actions", []))


def match_normalized_type(value):
    best_base = None
    for base in events_by_normalized_base:
        if value == base or value.startswith(base + "."):
            if best_base is None or len(base) > len(best_base):
                best_base = base
    if best_base is None:
        return None, None
    if value == best_base:
        return best_base, ""
    return best_base, value[len(best_base) + 1 :]


def fixture_catalog_event(filename):
    stem = filename.removesuffix(".json")
    for prefix in sorted(FILENAME_EVENT_ALIASES, key=len, reverse=True):
        if (
            stem == prefix
            or stem.startswith(prefix + "-")
            or stem.startswith(prefix + ".")
            or stem.startswith(prefix + "_")
        ):
            return FILENAME_EVENT_ALIASES[prefix]
    for event_name in sorted(catalog_events, key=len, reverse=True):
        if stem == event_name or stem.startswith(event_name + "-"):
            return event_name
    return None


def validate_catalog_event(backend, event_name, source):
    if catalog is None:
        return
    if not event_name:
        return
    if backend in {"delivery", "startup"}:
        return
    if backend not in catalog_providers:
        errors.append(f"UNKNOWN provider: {backend}  ({source})")
    if event_name not in catalog_events:
        errors.append(f"UNKNOWN webhook event: {event_name}  ({source})")


def validate_normalized_type(value, source):
    if catalog is None:
        return
    base, action = match_normalized_type(value)
    if base is None:
        # Some provider-native no-analog events are still delivered in confusio
        # shape.  They are not part of the GitHub coverage catalog yet.
        return
    catalog_action_sets = [set(event.get("actions", [])) for event in events_by_normalized_base[base]]
    if all(actions == {""} for actions in catalog_action_sets):
        return
    if not any(action in actions for actions in catalog_action_sets):
        errors.append(f"UNKNOWN normalized action: {value}  ({source})")


# Find all primary delivery hurl files (exclude confusio-shape variants).
hurl_files = sorted(test_dir.glob("webhook-delivery-*.hurl"))

if not hurl_files:
    print("ERROR: no webhook-delivery-*.hurl files found under", test_dir, file=sys.stderr)
    sys.exit(1)

all_declared = {}

for hurl_file in hurl_files:
    # Extract backend name from filename: webhook-delivery-<backend>.hurl
    hurl_backend = hurl_file.stem[len("webhook-delivery-"):]
    if hurl_backend.endswith("-confusio-shape"):
        hurl_backend = hurl_backend[: -len("-confusio-shape")]
    fixture_dir = fixtures_root / hurl_backend

    content = hurl_file.read_text().splitlines()
    declared = set()
    current_event = None
    current_fixture = None
    current_fixture_backend = None

    for line_no, line in enumerate(content, start=1):
        source = f"{hurl_file.name}:{line_no}"
        header_match = EVENT_HEADER_RE.match(line.strip())
        if header_match:
            current_event = header_match.group(1)

        file_match = FILE_REF_RE.search(line)
        if file_match:
            current_fixture_backend, filename = file_match.groups()
            current_fixture = filename
            declared.add(filename)
            all_declared.setdefault(current_fixture_backend, set()).add(filename)
            validate_catalog_event(current_fixture_backend, current_event or "", source)
            if current_fixture_backend != hurl_backend and hurl_backend not in {"delivery", "startup"}:
                errors.append(
                    f"BACKEND mismatch: {source} references {current_fixture_backend}/{filename}"
                    f" from {hurl_file.name}"
                )

        confusio_event_match = CONFUSIO_EVENT_RE.search(line)
        if confusio_event_match:
            validate_catalog_event(
                current_fixture_backend or hurl_backend,
                confusio_event_match.group(1),
                source,
            )

        normalized_type_match = NORMALIZED_TYPE_RE.search(line)
        if normalized_type_match:
            validate_normalized_type(normalized_type_match.group(1), source)

        if line.startswith("POST ") or line.startswith("GET "):
            current_event = None
            current_fixture = None
            current_fixture_backend = None

    # Gather actual fixture files on disk.
    if fixture_dir.is_dir():
        actual = {f.name for f in fixture_dir.iterdir() if f.suffix == ".json"}
    else:
        actual = set()

    missing = sorted(declared - actual)
    extra = sorted(actual - declared)

    for name in missing:
        errors.append(
            f"MISSING fixture: test/fixtures/webhooks/{hurl_backend}/{name}"
            f"  (declared in {hurl_file.name} but file does not exist)"
        )
    for name in extra:
        event_name = fixture_catalog_event(name)
        if catalog is not None and event_name is None:
            errors.append(
                f"EXTRA fixture: test/fixtures/webhooks/{hurl_backend}/{name}"
                f"  (file exists but is not referenced in {hurl_file.name}"
                " and does not map to a catalog event)"
            )

if catalog is not None:
    for fixture_dir in sorted(p for p in fixtures_root.iterdir() if p.is_dir()):
        backend = fixture_dir.name
        if backend not in catalog_providers:
            errors.append(f"UNKNOWN fixture provider: test/fixtures/webhooks/{backend}")
            continue
        for fixture in sorted(fixture_dir.glob("*.json")):
            if fixture.name in all_declared.get(backend, set()):
                continue
            event_name = fixture_catalog_event(fixture.name)
            if event_name is None:
                errors.append(
                    f"EXTRA fixture: test/fixtures/webhooks/{backend}/{fixture.name}"
                    "  (file exists but does not map to a catalog event)"
                )

if errors:
    for msg in errors:
        print(msg, file=sys.stderr)
    sys.exit(1)

print("validate-fixtures OK")
