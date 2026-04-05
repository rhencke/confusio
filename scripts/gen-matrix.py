#!/usr/bin/env python3
"""Generate the compatibility matrix HTML from site/compatibility.csv.

Usage:
  python3 scripts/gen-matrix.py [csv] [template] [output]

  csv      path to compatibility CSV  (default: site/compatibility.csv)
  template path to index.html template (default: site/index.html)
  output   path to write result        (default: stdout)

The template must contain the marker <!-- COMPAT_MATRIX --> where the
generated <table> element will be inserted.
"""
import csv
import sys
from pathlib import Path

PROVIDER_NAMES = {
    "azuredevops":         "Azure DevOps",
    "bitbucket":           "Bitbucket",
    "bitbucket_datacenter":"Bitbucket DC",
    "codeberg":            "Codeberg",
    "forgejo":             "Forgejo",
    "gerrit":              "Gerrit",
    "gitbucket":           "Gitbucket",
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
        return f'<td class="partial" title="{explanation}">&#x26A0;&#xFE0F;</td>'
    return '<td class="partial">&#x26A0;&#xFE0F;</td>'


def generate_table(rows, providers):
    num_cols = len(providers) + 1  # +1 for the endpoint column

    # thead
    header_cells = ["<th>Endpoint</th>"]
    for p in providers:
        header_cells.append(f"<th>{PROVIDER_NAMES.get(p, p)}</th>")
    thead = "      <thead>\n        <tr>" + "".join(header_cells) + "</tr>\n      </thead>"

    # tbody
    tbody_rows = []
    for row in rows:
        endpoint = row["endpoint"]
        if endpoint.startswith("## "):
            section = endpoint[3:]
            tbody_rows.append(
                f'        <tr><td colspan="{num_cols}" class="section-hdr">{section}</td></tr>'
            )
        else:
            cells = [f'<td class="ep">{endpoint}</td>']
            for p in providers:
                val = row.get(p, "n")
                cells.append(make_cell(val))
            tbody_rows.append("        <tr>" + "".join(cells) + "</tr>")

    tbody = "      <tbody>\n" + "\n".join(tbody_rows) + "\n      </tbody>"
    return f"    <table>\n{thead}\n{tbody}\n    </table>"


def main():
    csv_path      = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("site/compatibility.csv")
    template_path = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("site/index.html")
    output_path   = Path(sys.argv[3]) if len(sys.argv) > 3 else None

    with open(csv_path, newline="") as f:
        reader = csv.DictReader(f)
        providers = [h for h in reader.fieldnames if h != "endpoint"]
        rows = [r for r in reader]

    table_html = generate_table(rows, providers)
    template = template_path.read_text()
    output = template.replace("<!-- COMPAT_MATRIX -->", table_html, 1)

    if output_path:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(output)
    else:
        sys.stdout.write(output)


if __name__ == "__main__":
    main()
