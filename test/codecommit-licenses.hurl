# Licenses API assertions — CodeCommit backend.
# CodeCommit, Gerrit, Gitblit, Harness, Kallithea, Launchpad, OneDev, Pagure,
# Phabricator, Radicle, RhodeCode, SourceForge, Sourcehut, and Tuleap have no
# license template API and no accessible license file endpoint — all return 501.

# GET /licenses — not supported
GET http://{{host}}/licenses

HTTP 501

# GET /licenses/{license} — not supported
GET http://{{host}}/licenses/mit

HTTP 501

# GET /repos/{owner}/{repo}/license — not supported
GET http://{{host}}/repos/octocat/hello-world/license

HTTP 501
