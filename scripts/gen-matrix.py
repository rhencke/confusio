#!/usr/bin/env python3
"""Generate the compatibility matrix HTML from the endpoint catalog and site/compatibility.csv.

Usage:
  python3 scripts/gen-matrix.py [catalog] [csv] [template] [output]
  python3 scripts/gen-matrix.py --webhook-markdown [catalog] [csv]
  python3 scripts/gen-matrix.py --update-webhook-docs [catalog] [csv] [doc]
  python3 scripts/gen-matrix.py --check-webhook-docs [catalog] [csv] [doc]

  catalog  path to catalog JSON, or '-' for stdin (default: '-')
  csv      path to compatibility CSV  (default: site/compatibility.csv)
  template path to index.html template (default: site/index.html)
  output   path to write result        (default: stdout)

The template must contain the marker <!-- COMPAT_MATRIX --> where the
generated REST endpoint <table> element will be inserted, and the marker
<!-- WEBHOOK_MATRIX --> where the webhook events <table> will be inserted.

The catalog JSON is produced by: ./redbean.com -i scripts/dump-endpoints.lua
Each entry has: method, path, handler, group, has_default, is_webhook_event.

Entries with is_webhook_event=true use method "webhook" and path "event/action"
(e.g. "webhook issues/opened").  They are rendered in a separate table keyed
by event type (the segment before "/"), with the action as the row label.

The CSV contains support values (y/n/~) keyed by "METHOD /path". Section
headers are derived from the catalog group names; the CSV has no section rows.
"""
import csv
import json
import sys
from pathlib import Path

WEBHOOK_DOCS_START = "<!-- WEBHOOK_ACTION_SUPPORT_START -->"
WEBHOOK_DOCS_END = "<!-- WEBHOOK_ACTION_SUPPORT_END -->"

PROVIDER_NAMES = {
    "azuredevops":         "Azure DevOps",
    "bitbucket":           "Bitbucket",
    "bitbucket_datacenter":"Bitbucket DC",
    "codeberg":            "Codeberg",
    "forgejo":             "Forgejo",
    "gerrit":              "Gerrit",
    "gitblit":             "GitBlit",
    "gitbucket":           "GitBucket",
    "gitea":               "Gitea",
    "gitlab":              "GitLab",
    "gogs":                "Gogs",
    "harness":             "Harness",
    "kallithea":           "Kallithea",
    "launchpad":           "Launchpad",
    "notabug":             "NotABug",
    "onedev":              "OneDev",
    "pagure":              "Pagure",
    "phabricator":         "Phabricator",
    "radicle":             "Radicle",
    "rhodecode":           "RhodeCode",
    "sourceforge":         "SourceForge",
    "sourcehut":           "Sourcehut",
    "codecommit":          "CodeCommit",
    "tuleap":              "Tuleap",
}

GROUP_NAMES = {
    "graphql":              "GraphQL",
    "meta":                 "Meta",
    "gitignore":            "Gitignore",
    "licenses":             "Licenses",
    "rate-limit":           "Rate Limits",
    "gists":                "Gists",
    "activity":             "Activity",
    "repos":                "Repositories",
    "repos-ext":            "Repo Content & Metadata",
    "releases":             "Releases",
    "reactions":            "Reactions",
    "teams":                "Teams",
    "security-advisories":  "Security Advisories",
    "issues":               "Issues",
    "pulls":                "Pull Requests",
    "users":                "Users",
    "search":               "Search",
    "apps":                 "GitHub Apps",
    "checks":               "Checks",
    "code-scanning":        "Code Scanning",
    "secret-scanning":      "Secret Scanning",
    "dependabot":           "Dependabot",
    "dependency-graph":     "Dependency Graph",
    "projects":             "Projects",
    "packages":             "Packages",
    "interactions":         "Interaction Limits",
    "migrations":           "Migrations",
    "pages":                "Pages",
    "markdown":             "Markdown",
    "actions":              "Actions",
    "git":                  "Git Database",
}

# Human-readable names for webhook event types (the segment before "/" in the path).
WEBHOOK_EVENT_NAMES = {
    "commit_comment":               "Commit Comments",
    "create":                       "Create",
    "delete":                       "Delete",
    "discussion":                   "Discussions",
    "discussion_comment":           "Discussion Comments",
    "fork":                         "Fork",
    "issues":                       "Issues",
    "issue_comment":                "Issue Comments",
    "label":                        "Labels",
    "merge_group":                  "Merge Group",
    "milestone":                    "Milestones",
    "pull_request":                 "Pull Requests",
    "pull_request_review":          "PR Reviews",
    "pull_request_review_comment":  "PR Review Comments",
    "push":                         "Push",
    "repository":                   "Repository",
    "status":                       "Commit Status",
    "workflow_run":                 "Workflow Run",
    "workflow_job":                 "Workflow Job",
}


def webhook_event_name(event):
    return WEBHOOK_EVENT_NAMES.get(event, event.replace("_", " ").title())


def make_cell(val):
    val = val.strip()
    if val == "y":
        return '<td class="yes">&#x2705;</td>'
    if val == "n":
        return '<td class="no">&#x274C;</td>'
    # partial: bare "~" or "~explanation text"
    explanation = val[1:].strip() if val.startswith("~") else ""
    if explanation:
        return f'<td class="partial" title="{explanation}" tabindex="0">&#x26A0;&#xFE0F;</td>'
    return '<td class="partial">&#x26A0;&#xFE0F;</td>'


def markdown_escape(value):
    return value.replace("\\", "\\\\").replace("|", "\\|").replace("\n", " ")


def make_markdown_cell(val):
    val = val.strip()
    if val == "y":
        return "✓"
    if val == "n":
        return "✗"
    explanation = val[1:].strip() if val.startswith("~") else ""
    if explanation:
        return "~ (" + markdown_escape(explanation) + ")"
    return "~"


def load_catalog(catalog_arg):
    if catalog_arg == "-":
        return json.load(sys.stdin)
    with open(catalog_arg) as f:
        return json.load(f)


def load_support(csv_path):
    support = {}
    with open(csv_path, newline="") as f:
        reader = csv.DictReader(f)
        providers = [h for h in reader.fieldnames if h != "endpoint"]
        for row in reader:
            support[row["endpoint"]] = {p: row.get(p, "n") for p in providers}
    return support, providers


def generate_table(catalog, support, providers):
    """Generate the REST endpoint compatibility table (non-webhook entries)."""
    num_cols = len(providers) + 1  # +1 for the endpoint column

    # thead
    header_cells = ["<th>Endpoint</th>"]
    for p in providers:
        header_cells.append(f"<th>{PROVIDER_NAMES.get(p, p)}</th>")
    thead = "      <thead>\n        <tr>" + "".join(header_cells) + "</tr>\n      </thead>"

    # tbody — iterate catalog in group order, injecting section headers on group change
    tbody_rows = []
    current_group = None
    for entry in catalog:
        if entry.get("is_webhook_event"):
            continue
        group = entry["group"]
        if group != current_group:
            section = GROUP_NAMES.get(group, group)
            tbody_rows.append(
                f'        <tr><td colspan="{num_cols}" class="section-hdr">{section}</td></tr>'
            )
            current_group = group
        endpoint = entry["method"] + " " + entry["path"]
        row = support.get(endpoint, {})
        cells = [f'<td class="ep">{endpoint}</td>']
        for p in providers:
            val = row.get(p, "n")
            cells.append(make_cell(val))
        tbody_rows.append("        <tr>" + "".join(cells) + "</tr>")

    tbody = "      <tbody>\n" + "\n".join(tbody_rows) + "\n      </tbody>"
    return f"    <table>\n{thead}\n{tbody}\n    </table>"


def generate_webhook_table(catalog, support, providers):
    """Generate the webhook event compatibility table.

    Rows come from catalog entries with is_webhook_event=true.  Their path is
    "event/action" (e.g. "issues/opened").  Section headers group by the event
    type (before "/"); the row label shows only the action (after "/").

    The CSV key for each entry is "webhook event/action" (method + " " + path).
    """
    num_cols = len(providers) + 1  # +1 for the action column

    # thead
    header_cells = ["<th>Action</th>"]
    for p in providers:
        header_cells.append(f"<th>{PROVIDER_NAMES.get(p, p)}</th>")
    thead = "      <thead>\n        <tr>" + "".join(header_cells) + "</tr>\n      </thead>"

    tbody_rows = []
    current_event = None
    for entry in catalog:
        if not entry.get("is_webhook_event"):
            continue
        path = entry["path"]  # e.g. "issues/opened"
        if "/" in path:
            event, action = path.split("/", 1)
        else:
            event, action = path, ""

        if event != current_event:
            section = webhook_event_name(event)
            tbody_rows.append(
                f'        <tr><td colspan="{num_cols}" class="section-hdr">{section}</td></tr>'
            )
            current_event = event

        csv_key = entry["method"] + " " + path  # e.g. "webhook issues/opened"
        row = support.get(csv_key, {})
        label = action if action else path
        cells = [f'<td class="ep">{label}</td>']
        for p in providers:
            val = row.get(p, "n")
            cells.append(make_cell(val))
        tbody_rows.append("        <tr>" + "".join(cells) + "</tr>")

    tbody = "      <tbody>\n" + "\n".join(tbody_rows) + "\n      </tbody>"
    return f"    <table>\n{thead}\n{tbody}\n    </table>"


def generate_webhook_markdown_table(catalog, support, providers):
    """Generate the Markdown webhook action support matrix used in docs/webhooks.md."""
    headers = ["Event", "Action"] + [PROVIDER_NAMES.get(p, p) for p in providers]
    lines = [
        "| " + " | ".join(headers) + " |",
        "|" + "|".join(["---"] * len(headers)) + "|",
    ]

    current_event = None
    for entry in catalog:
        if not entry.get("is_webhook_event"):
            continue
        path = entry["path"]
        if "/" in path:
            event, action = path.split("/", 1)
        else:
            event, action = path, ""

        event_cell = ""
        if event != current_event:
            event_cell = webhook_event_name(event)
            current_event = event

        csv_key = entry["method"] + " " + path
        row = support.get(csv_key, {})
        cells = [event_cell, "`" + markdown_escape(action or path) + "`"]
        for p in providers:
            cells.append(make_markdown_cell(row.get(p, "n")))
        lines.append("| " + " | ".join(cells) + " |")

    return "\n".join(lines) + "\n"


def replace_webhook_docs_matrix(doc_text, matrix):
    start = doc_text.find(WEBHOOK_DOCS_START)
    end = doc_text.find(WEBHOOK_DOCS_END)
    if start == -1 or end == -1 or end < start:
        raise SystemExit("webhook docs markers not found")
    end += len(WEBHOOK_DOCS_END)
    replacement = WEBHOOK_DOCS_START + "\n" + matrix.rstrip() + "\n" + WEBHOOK_DOCS_END
    return doc_text[:start] + replacement + doc_text[end:]


def main():
    if len(sys.argv) > 1 and sys.argv[1] in {
        "--webhook-markdown",
        "--update-webhook-docs",
        "--check-webhook-docs",
    }:
        command = sys.argv[1]
        catalog_arg = sys.argv[2] if len(sys.argv) > 2 else "-"
        csv_path = Path(sys.argv[3]) if len(sys.argv) > 3 else Path("site/compatibility.csv")
        doc_path = Path(sys.argv[4]) if len(sys.argv) > 4 else Path("docs/webhooks.md")

        catalog = load_catalog(catalog_arg)
        support, providers = load_support(csv_path)
        matrix = generate_webhook_markdown_table(catalog, support, providers)

        if command == "--webhook-markdown":
            sys.stdout.write(matrix)
            return

        doc_text = doc_path.read_text()
        updated = replace_webhook_docs_matrix(doc_text, matrix)
        if command == "--check-webhook-docs":
            if updated != doc_text:
                raise SystemExit("docs/webhooks.md webhook action support matrix is stale")
            return

        doc_path.write_text(updated)
        return

    catalog_arg  = sys.argv[1] if len(sys.argv) > 1 else "-"
    csv_path     = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("site/compatibility.csv")
    template_path = Path(sys.argv[3]) if len(sys.argv) > 3 else Path("site/index.html")
    output_path  = Path(sys.argv[4]) if len(sys.argv) > 4 else None

    catalog = load_catalog(catalog_arg)
    support, providers = load_support(csv_path)

    rest_table_html    = generate_table(catalog, support, providers)
    webhook_table_html = generate_webhook_table(catalog, support, providers)

    template = template_path.read_text()
    output = template.replace("<!-- COMPAT_MATRIX -->", rest_table_html, 1)
    output = output.replace("<!-- WEBHOOK_MATRIX -->", webhook_table_html, 1)

    if output_path:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(output)
    else:
        sys.stdout.write(output)


if __name__ == "__main__":
    main()
