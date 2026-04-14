#!/usr/bin/env python3
"""Generate the compatibility matrix HTML from the endpoint catalog and site/compatibility.csv.

Usage:
  python3 scripts/gen-matrix.py [catalog] [csv] [template] [output]

  catalog  path to catalog JSON, or '-' for stdin (default: '-')
  csv      path to compatibility CSV  (default: site/compatibility.csv)
  template path to index.html template (default: site/index.html)
  output   path to write result        (default: stdout)

The template must contain the marker <!-- COMPAT_MATRIX --> where the
generated <table> element will be inserted.

The catalog JSON is produced by: ./redbean.com -i scripts/dump-endpoints.lua
Each entry has: method, path, handler, group, has_default.

The CSV contains support values (y/n/~) keyed by "METHOD /path". Section
headers are derived from the catalog group names; the CSV has no section rows.
"""
import csv
import json
import sys
from pathlib import Path

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


def generate_table(catalog, support, providers):
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


def main():
    catalog_arg  = sys.argv[1] if len(sys.argv) > 1 else "-"
    csv_path     = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("site/compatibility.csv")
    template_path = Path(sys.argv[3]) if len(sys.argv) > 3 else Path("site/index.html")
    output_path  = Path(sys.argv[4]) if len(sys.argv) > 4 else None

    if catalog_arg == "-":
        catalog = json.load(sys.stdin)
    else:
        with open(catalog_arg) as f:
            catalog = json.load(f)

    # Load support values: keyed by "METHOD /path" → {provider: value}
    support = {}
    with open(csv_path, newline="") as f:
        reader = csv.DictReader(f)
        providers = [h for h in reader.fieldnames if h != "endpoint"]
        for row in reader:
            support[row["endpoint"]] = {p: row.get(p, "n") for p in providers}

    table_html = generate_table(catalog, support, providers)
    template = template_path.read_text()
    output = template.replace("<!-- COMPAT_MATRIX -->", table_html, 1)

    if output_path:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(output)
    else:
        sys.stdout.write(output)


if __name__ == "__main__":
    main()
