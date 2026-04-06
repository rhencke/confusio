# Link header rewrite assertions — Gitea backend.
# The mock returns upstream Link URLs (upstream.example.com); confusio must rewrite
# them to point at itself, translating Gitea param names to GitHub param names.

# GET /user/repos — Link header is present and rewritten to confusio's own URL
GET http://{{host}}/user/repos

HTTP 200
[Asserts]
# Upstream URL must not leak through
header "Link" not contains "upstream.example.com"
# Confusio's own host must appear
header "Link" contains "http://{{host}}/user/repos"
# Gitea's "limit" param must be translated to GitHub's "per_page"
header "Link" not contains "limit="
header "Link" contains "per_page=1"
# Pagination pages must survive
header "Link" contains "page=2"
header "Link" contains "page=5"
# Both rel types must be present
header "Link" contains "rel=\"next\""
header "Link" contains "rel=\"last\""
