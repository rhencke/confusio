# 15 — Compatibility Site Integration for GraphQL Coverage Reporting

## What this document covers

The GitHub Pages compatibility matrix at `site/index.html` visualises REST endpoint
support per backend.  GraphQL support is a new axis: not every backend supports the same
GraphQL fields, and the existing row-per-endpoint / column-per-backend table does not
naturally express field-level GraphQL capability.  This document specifies what changes
to the CSV, `gen-matrix.py`, `site/index.html`, and the CI pipeline are needed to surface
GraphQL coverage without disrupting the existing REST matrix.

## Current site architecture recap

```
site/compatibility.csv          ← support values: one row per REST endpoint,
                                    one column per backend
scripts/gen-matrix.py           ← reads catalog JSON + CSV → HTML <table>
site/index.html                 ← template: <!-- COMPAT_MATRIX --> placeholder
_site/index.html                ← generated output (not committed)
.github/workflows/pages.yml     ← CI: generate + deploy _site/
```

The catalog (`scripts/dump-endpoints.lua` → `endpoints[]`) drives row order and section
headers.  `validate-csv.py` checks every CSV row exists in the catalog.  `validate-tests.py`
checks every catalog group has test coverage.

## What GraphQL adds

GraphQL support is a single catalog entry (`POST /graphql`) inside the new `"graphql"`
section group.  This entry deserves a row in the compatibility matrix just like every REST
endpoint.  The support values express the **overall GraphQL capability** of each backend,
not individual field support (which is too fine-grained for the matrix).

## CSV changes

### One new row: `POST /graphql`

```csv
POST /graphql,y,~,~,y,n,y,n,n,y,y,y,y,n,n,n,y,n,~,n,n,n,n,~,n
```

Columns follow the existing order: azuredevops, bitbucket, bitbucket_datacenter, codeberg,
codecommit, forgejo, gerrit, gitblit, gitbucket, gitea, gitlab, gogs, harness, kallithea,
launchpad, notabug, onedev, pagure, phabricator, radicle, rhodecode, sourceforge,
sourcehut, tuleap.

Support values for `POST /graphql`:

| Backend | Value | Explanation |
|---|---|---|
| gitea | `y` | Full Phase 1 — viewer, repository, issues, PRs, releases, search |
| forgejo | `y` | Inherits gitea |
| codeberg | `y` | Inherits gitea |
| notabug | `y` | Inherits gitea (minus gitignore fields) |
| gogs | `~` | Inherits gitea; no releases, no packages |
| gitlab | `y` | Full Phase 1 |
| gitbucket | `y` | GitHub-compatible API; full Phase 1 |
| bitbucket | `~` | `~no labels, no reactions; commit email always empty` |
| bitbucket_datacenter | `~` | `~no viewer; repository and issues work` |
| azuredevops | `~` | `~repository only; no issues, no viewer` |
| sourcehut | `~` | `~repository only; issues/PRs absent` |
| pagure | `~` | `~repository and issues; no pull requests` |
| gerrit | `~` | `~repository scalar fields only` |
| codecommit | `n` | — |
| harness | `n` | — |
| kallithea | `n` | — |
| launchpad | `~` | `~issues only; no repository scalar fields` |
| onedev | `n` | — |
| phabricator | `n` | — |
| radicle | `n` | — |
| rhodecode | `n` | — |
| sourceforge | `n` | — |
| tuleap | `n` | — |

**Initial commit value**: all backends start as `~` (partial) when GraphQL is first
shipped, reflecting Phase 1 coverage.  Backends are upgraded to `y` once their
resolver registration is complete and `<backend>-graphql.hurl` passes.

### Why one row, not per-field rows

The existing matrix has one row per REST endpoint because REST endpoints are discrete,
enumerable, and independently implementable.  GraphQL fields are not: a single
`POST /graphql` request can exercise dozens of fields at once, and the schema has ~3 500
fields.  A per-field matrix would have 3 500 rows — unusable.

The single-row summary communicates the most actionable information: "can this client use
`POST /graphql` against this backend to get useful results?"  Per-field detail lives in
[14-backend-feasibility.md](14-backend-feasibility.md).

### Tooltip convention for GraphQL partial values

The existing `~explanation` convention carries the explanation text as an HTML tooltip on
the `⚠️` cell.  GraphQL partial values follow the same convention:

```csv
~no labels, no reactions; commit email always empty
```

The `make_cell` function in `gen-matrix.py` already handles the tooltip — no code changes
needed.

## `gen-matrix.py` changes

### New group name mapping

`GROUP_NAMES` in `gen-matrix.py` needs one new entry:

```python
"graphql": "GraphQL",
```

This renders the section header as **GraphQL** in the table, appearing after the existing
REST sections (section order follows `endpoint_sections` in `internal/catalog.lua`).

### No other changes

`gen-matrix.py` reads the catalog and CSV generically.  `POST /graphql` is just another
row in the CSV and another entry in the catalog JSON.  The table generation loop handles
it without modification.

## `site/index.html` changes

### Legend update

The current legend reads:

```html
✅ Supported · ⚠️ Partial · ❌ Unsupported (returns 404 or 501)
```

No change is needed.  For the `POST /graphql` row, `✅` means the backend has full Phase 1
resolver coverage and `⚠️` means partial coverage (some fields return `null`).  This is
consistent with the REST interpretation.

### Optional: GraphQL section callout

A short paragraph below the legend can link to the design docs and note that GraphQL
support is in beta:

```html
<p style="margin-top:0.5rem; color:var(--text-muted); font-size:0.85rem;">
  The <strong>GraphQL</strong> row (at the bottom) reflects <code>POST /graphql</code>
  support. ⚠️ means partial field coverage — see the
  <a href="https://github.com/rhencke/confusio/tree/main/docs/graphql/">design docs</a>
  for per-backend detail.
</p>
```

This addition is optional and can be deferred until Phase 1 ships.

## `validate-csv.py` — no changes

`validate-csv.py` checks that every CSV row key (`METHOD /path`) exists in the catalog.
Once `POST /graphql` is in `endpoint_sections`, the catalog includes it and the validator
passes.

## `validate-tests.py` — no changes

`validate-tests.py` requires `test/<backend>-graphql.hurl` or `test/stub-graphql.hurl`
for every backend.  `test/stub-graphql.hurl` (defined in [13-testing.md](13-testing.md))
covers all backends as the fallback.  No structural change needed.

## `validate-claims.py` — GraphQL exemption

`validate-claims.py` cross-checks CSV `y` claims against `backend_impl` entries.
`POST /graphql` is handled by `graphql_handler` (in `graphql_executor.lua`), not by a
`backend_impl` key.  It follows the same pattern as the five `CONFUSIO_NATIVE` handlers
that are exempt from the presence check.

The `CONFUSIO_NATIVE` set in `scripts/validate-claims.lua` gains one new entry:

```lua
-- internal/graphql_executor.lua registers graphql_handler as the fixed
-- default for POST /graphql; backends only populate graphql_resolvers.
local CONFUSIO_NATIVE = {
  get_meta          = true,
  get_octocat       = true,
  get_teapot        = true,
  get_versions      = true,
  get_zen           = true,
  graphql_request   = true,   -- ← new
}
```

With this exemption, a `y` claim for `POST /graphql` is valid for any backend that has
resolver coverage, without requiring a `backend_impl.graphql_request` key.

## CI pipeline changes

The `pages.yml` workflow generates the site by running `gen-matrix.py`.  No workflow
changes are needed: the script already reads the catalog dynamically and the new
`"graphql": "GraphQL"` entry in `GROUP_NAMES` is a Python-only change, not a workflow
change.

```yaml
# .github/workflows/pages.yml — existing, unchanged
- name: Generate compatibility matrix
  run: |
    mkdir -p _site
    cp -r site/. _site/
    python3 scripts/gen-matrix.py site/compatibility.csv site/index.html _site/index.html
```

Wait — the current `pages.yml` invocation passes positional args in the wrong order for
the current `gen-matrix.py` signature (`catalog csv template output`).  The script reads
catalog from stdin when the first arg is `"-"` and from a file otherwise.  The workflow
passes `site/compatibility.csv` as the first arg (the catalog position) — this would fail
unless the script is called with the catalog on stdin or the arg order matches.

**Actual current call in `pages.yml`**:
```bash
python3 scripts/gen-matrix.py site/compatibility.csv site/index.html _site/index.html
```

This passes the CSV as the catalog arg.  Looking at the Makefile:
```makefile
./redbean.com -i scripts/dump-endpoints.lua 2>/dev/null | \
  python3 scripts/gen-matrix.py - site/compatibility.csv site/index.html _site/index.html
```

The `pages.yml` call is divergent from the Makefile invocation.  This pre-existing
discrepancy is not introduced by GraphQL support; it should be fixed as a separate
cleanup, but it is noted here so it is not confused with any GraphQL-related change.

## Summary of file changes

| File | Change |
|---|---|
| `site/compatibility.csv` | Add row `POST /graphql` with per-backend values |
| `scripts/gen-matrix.py` | Add `"graphql": "GraphQL"` to `GROUP_NAMES` |
| `scripts/validate-claims.lua` | Add `graphql_request = true` to `CONFUSIO_NATIVE` |
| `site/index.html` | Optional: add GraphQL callout paragraph |
| `internal/catalog.lua` | Add `"graphql"` section (already specified in [04-executor.md](04-executor.md)) |

No changes to: `pages.yml`, `validate-csv.py`, `validate-tests.py`, `Makefile`.

## When to land the CSV row

The `POST /graphql` CSV row is added **when Phase 1 ships** — when
`internal/graphql_executor.lua` exists and the Gitea backend has resolver coverage.  Until
then, the row would claim `y` for gitea but the handler would not exist, which
`validate-claims` would catch (before the exemption is in place).

The correct order:

1. Implement `graphql_executor.lua` and gitea resolver registration.
2. Add `graphql_request = true` to `CONFUSIO_NATIVE` in `validate-claims.lua`.
3. Add the `POST /graphql` row to `site/compatibility.csv`.
4. Add `"graphql": "GraphQL"` to `GROUP_NAMES` in `gen-matrix.py`.
5. Run `make validate-csv validate-claims validate-tests` — all pass.
6. Commit everything together.
