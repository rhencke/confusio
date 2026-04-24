-- Unit tests for all global functions in .init.lua.
-- Run from project root: sh redbean.com -i test/unit-init.lua
-- ============================================================

-- Enable luacov coverage tracing when COVERAGE=1.
-- Requires: make luacov (downloads luacov source to ./luacov/).
if os.getenv("COVERAGE") then
  package.path = "luacov/?.lua;" .. package.path
  require("luacov")
end

-- Stub state for the Redbean HTTP context APIs.
local _last_status, _last_headers, _last_body
local _req_headers, _req_path, _req_params, _req_method, _req_body

local function reset_response()
  _last_status = nil
  _last_headers = {}
  _last_body = ""
end

local function reset_request(opts)
  opts = opts or {}
  _req_headers = opts.headers or {}
  _req_path = opts.path or "/"
  _req_params = opts.params or {}
  _req_method = opts.method or "GET"
  _req_body = opts.body or nil
end

reset_response()
reset_request()

-- Override Redbean HTTP context built-ins before loading .init.lua.
-- luacheck: push
-- luacheck: globals SetStatus SetHeader Write GetHeader GetPath GetParam GetMethod GetBody Route
-- luacheck: globals GetCryptoHash DecodeBase64
SetStatus = function(code, _reason)
  _last_status = code
end
SetHeader = function(k, v)
  _last_headers[k] = v
end
Write = function(s)
  _last_body = _last_body .. tostring(s)
end
GetHeader = function(k)
  return _req_headers[k]
end
GetPath = function()
  return _req_path
end
GetParam = function(k)
  return _req_params[k]
end
GetMethod = function()
  return _req_method
end
Route = function() end
GetBody = function()
  return _req_body
end
-- Stub GetCryptoHash: returns a fixed 32-byte string so unit tests can exercise
-- the signature verification logic without requiring real crypto.  Integration
-- tests that need real HMAC run against the live binary where GetCryptoHash is
-- implemented by Redbean's C layer.
GetCryptoHash = function(_alg, _msg, _key)
  return string.rep("\xaa", 32)
end
-- Stub GetRandomBytes: returns a deterministic byte sequence so make_uuid produces a
-- predictable value in tests.  Byte i = (i * 17) % 256, giving 16 distinct bytes.
GetRandomBytes = function(n) -- luacheck: globals GetRandomBytes
  local t = {}
  for i = 1, n do
    t[i] = string.char((i * 17) % 256)
  end
  return table.concat(t)
end
-- Stub DecodeBase64: identity decode for Basic auth verification tests.
DecodeBase64 = function(s)
  return s
end
-- luacheck: pop

-- Prevent backend file loading (config.backend will be "" anyway, but be safe).
-- Redirect /zip/internal/ to the internal/ directory on the filesystem so unit
-- tests can load internal modules without a Redbean zip.
local _real_dofile = dofile
function dofile(path) -- luacheck: globals dofile
  if path and path:match("^/zip/backends/") then
    return
  end
  if path and path:match("^/zip/internal/") then
    return _real_dofile(path:sub(6))
  end
  return _real_dofile(path)
end

-- Provide one SCRIPTARGS entry so the loop body executes.
-- The dofile stub above silently drops the backend file load.
arg = { "testbackend" } -- luacheck: globals arg

-- Stub os.getenv to return a valid JSON string for CONFUSIO_WEBHOOK_SECRETS so
-- that the env-var loading block in .init.lua (lines 28-30) is exercised by
-- luacov.  Restore immediately after load and clear config.webhook_secrets so
-- subsequent tests that rely on no secret being configured are unaffected.
local _real_getenv = os.getenv
os.getenv = function(k) -- luacheck: globals os
  if k == "CONFUSIO_WEBHOOK_SECRETS" then
    return '{"gitea":"ws_coverage_test"}'
  end
  return _real_getenv(k)
end

-- Load the module under test.
_real_dofile(".init.lua")

-- Verify the env-var block populated config.webhook_secrets.
assert(
  config.webhook_secrets ~= nil, -- luacheck: globals config
  "CONFUSIO_WEBHOOK_SECRETS: config.webhook_secrets should be non-nil after load"
)
assert(
  config.webhook_secrets.gitea == "ws_coverage_test",
  "CONFUSIO_WEBHOOK_SECRETS: gitea secret mismatch: " .. tostring(config.webhook_secrets.gitea)
)

-- Restore os.getenv and clear the coverage-only secret so later tests see a
-- clean config.  (config and app.config reference the same table.)
os.getenv = _real_getenv -- luacheck: globals os
config.webhook_secrets = nil

-- Restore dofile so later tests that call it work normally.
dofile = _real_dofile -- luacheck: globals dofile

-- ============================================================
-- Minimal assertion helpers
-- ============================================================

local PASS, FAIL = 0, 0

local function ok(cond, msg)
  if cond then
    PASS = PASS + 1
    io.write("PASS  " .. msg .. "\n")
  else
    FAIL = FAIL + 1
    io.write("FAIL  " .. msg .. "\n")
  end
end

local function eq(a, b, msg)
  ok(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end

-- ============================================================
-- set_preamble
-- ============================================================

reset_response()
set_preamble(200)
eq(_last_status, 200, "set_preamble(200): status 200")
eq(
  _last_headers["Content-Type"],
  "application/json; charset=utf-8",
  "set_preamble(200): default content-type"
)

reset_response()
set_preamble(404)
eq(_last_status, 404, "set_preamble(404): status 404")

reset_response()
set_preamble(503)
eq(_last_status, 503, "set_preamble(503): status 503")

reset_response()
set_preamble("text/plain")
eq(_last_status, 200, "set_preamble(str): string arg → status 200")
eq(
  _last_headers["Content-Type"],
  "text/plain",
  "set_preamble(str): string arg → custom content-type"
)

reset_response()
set_preamble(201, "text/html")
eq(_last_status, 201, "set_preamble(201, str): status 201")
eq(_last_headers["Content-Type"], "text/html", "set_preamble(201, str): custom content-type")

-- ============================================================
-- respond_json
-- ============================================================

reset_response()
respond_json(200, { foo = "bar" })
eq(_last_status, 200, "respond_json(200, obj): status 200")
ok(_last_body ~= "", "respond_json(200, obj): non-empty body")
ok(
  _last_body:find('"foo"') ~= nil or _last_body:find("foo") ~= nil,
  "respond_json(200, obj): body contains key"
)

reset_response()
respond_json(404, {})
eq(_last_status, 404, "respond_json(404, {}): status 404")

-- ============================================================
-- rewrite_link_header
-- ============================================================

reset_request({
  headers = { Host = "proxy.example.com", ["X-Forwarded-Proto"] = "https" },
  path = "/repos/owner/repo/issues",
})

local mapping = { per_page = "limit", page = "page" }
local up_link = '<https://gitea.example.com/api/v1/repos/owner/repo/issues?limit=30&page=2>; rel="next"'
  .. ', <https://gitea.example.com/api/v1/repos/owner/repo/issues?limit=30&page=5>; rel="last"'
local result = rewrite_link_header(up_link, mapping)
ok(result ~= nil, "rewrite_link_header: non-nil for valid input")
ok(result:find("proxy.example.com") ~= nil, "rewrite_link_header: rewrites host to confusio host")
ok(result:find("https://") ~= nil, "rewrite_link_header: uses X-Forwarded-Proto scheme")
ok(result:find("per_page=30") ~= nil, "rewrite_link_header: translates limit → per_page")
ok(result:find('rel="next"') ~= nil, "rewrite_link_header: preserves rel=next")
ok(result:find('rel="last"') ~= nil, "rewrite_link_header: preserves rel=last")
ok(result:find("gitea.example.com") == nil, "rewrite_link_header: removes upstream host")

-- nil / empty input
ok(rewrite_link_header(nil, mapping) == nil, "rewrite_link_header(nil): returns nil")
ok(rewrite_link_header("", mapping) == nil, "rewrite_link_header(''): returns nil")

-- Unknown params are dropped
local link_unknown =
  '<https://gitea.example.com/api/v1/repos/owner/repo?limit=10&unknown=foo>; rel="next"'
local result_unknown = rewrite_link_header(link_unknown, mapping)
ok(
  result_unknown == nil or result_unknown:find("unknown") == nil,
  "rewrite_link_header: drops unrecognised params"
)

-- Only-unknown params → entry kept but query string stripped
local link_only_unknown = '<https://gitea.example.com/api/v1/repos?unknown=foo>; rel="next"'
local result_only_unknown = rewrite_link_header(link_only_unknown, mapping)
ok(
  result_only_unknown ~= nil,
  "rewrite_link_header: entry kept even when all params are unrecognised"
)
ok(
  result_only_unknown ~= nil and result_only_unknown:find("unknown") == nil,
  "rewrite_link_header: unrecognised param stripped from kept entry"
)

-- Default proto when X-Forwarded-Proto absent
reset_request({ headers = { Host = "localhost:8080" }, path = "/users" })
local result_http = rewrite_link_header(
  '<https://gitea.example.com/api/v1/users?limit=20&page=1>; rel="next"',
  mapping
)
ok(
  result_http ~= nil and result_http:find("http://localhost:8080") ~= nil,
  "rewrite_link_header: defaults to http when no X-Forwarded-Proto"
)

-- ============================================================
-- append_page_params
-- ============================================================

reset_request({ params = {} })
eq(
  append_page_params("https://example.com/api", mapping),
  "https://example.com/api",
  "append_page_params: no params → unchanged"
)

reset_request({ params = { per_page = "50", page = "3" } })
local url_both = append_page_params("https://example.com/api", mapping)
ok(url_both:find("limit=50") ~= nil, "append_page_params: per_page → limit")
ok(url_both:find("page=3") ~= nil, "append_page_params: page passes through")
ok(url_both:find("^https://example.com/api%?") ~= nil, "append_page_params: appends with ?")

reset_request({ params = { per_page = "25" } })
local url_existing = append_page_params("https://example.com/api?existing=1", mapping)
ok(url_existing:find("&limit=25") ~= nil, "append_page_params: uses & when ? already present")
ok(url_existing:find("existing=1") ~= nil, "append_page_params: preserves existing param")

-- page-only mapping (like Sourcehut)
reset_request({ params = { per_page = "10" } })
local url_limit_only = append_page_params("https://example.com/api", { per_page = "limit" })
ok(url_limit_only:find("limit=10") ~= nil, "append_page_params: limit-only mapping works")
ok(url_limit_only:find("page") == nil, "append_page_params: no page key in limit-only mapping")

-- ============================================================
-- make_fetch_opts
-- ============================================================

reset_request({ headers = {} })
ok(make_fetch_opts("token") == nil, "make_fetch_opts: nil when no Authorization header")

reset_request({ headers = { Authorization = "token mytoken123" } })
local opts_tok = make_fetch_opts("token")
ok(opts_tok ~= nil, "make_fetch_opts(token): non-nil when Authorization present")
eq(
  opts_tok.headers["Authorization"],
  "token mytoken123",
  "make_fetch_opts(token): token scheme passthrough"
)

reset_request({ headers = { Authorization = "Bearer mybearer" } })
local opts_bea = make_fetch_opts("bearer")
eq(opts_bea.headers["Authorization"], "Bearer mybearer", "make_fetch_opts(bearer): bearer scheme")

-- basic-colon: empty username prefix
reset_request({ headers = { Authorization = "token mysecret" } })
local opts_bc = make_fetch_opts("basic-colon")
ok(opts_bc ~= nil, "make_fetch_opts(basic-colon): non-nil")
ok(
  opts_bc.headers["Authorization"]:find("^Basic ") ~= nil,
  "make_fetch_opts(basic-colon): Basic prefix"
)

-- basic: raw base64 of the token
reset_request({ headers = { Authorization = "token user:pass" } })
local opts_basic = make_fetch_opts("basic")
ok(opts_basic ~= nil, "make_fetch_opts(basic): non-nil")
ok(
  opts_basic.headers["Authorization"]:find("^Basic ") ~= nil,
  "make_fetch_opts(basic): Basic prefix"
)

-- ============================================================
-- owner_repo_id
-- ============================================================

eq(owner_repo_id("alice", "myrepo"), "alice%2Fmyrepo", "owner_repo_id: basic case")
eq(owner_repo_id("org", "my-repo"), "org%2Fmy-repo", "owner_repo_id: hyphen in repo name")
eq(owner_repo_id("a", "b"), "a%2Fb", "owner_repo_id: single-char segments")

-- ============================================================
-- translate_repo
-- ============================================================

local fake_repo = {
  id = 42,
  name = "myrepo",
  full_name = "alice/myrepo",
  private = false,
  owner = {
    login = "alice",
    id = 1,
    avatar_url = "https://example.com/alice.png",
    url = "https://example.com/alice",
    html_url = "https://example.com/alice",
    type = "User",
  },
  html_url = "https://example.com/alice/myrepo",
  description = "A repo",
  fork = false,
  url = "https://example.com/alice/myrepo",
  ssh_url = "git@example.com:alice/myrepo.git",
  clone_url = "https://example.com/alice/myrepo.git",
  website = "https://alice.example.com",
  size = 100,
  stars_count = 5,
  watchers_count = 3,
  language = "Lua",
  has_issues = true,
  has_wiki = false,
  forks_count = 2,
  archived = false,
  open_issues_count = 1,
  default_branch = "main",
  visibility = "public",
  created = "2024-01-01T00:00:00Z",
  updated = "2024-06-01T00:00:00Z",
  permissions = { admin = true, push = true, pull = true },
}

local tr = translate_repo(fake_repo)
eq(tr.id, 42, "translate_repo: id")
eq(tr.name, "myrepo", "translate_repo: name")
eq(tr.full_name, "alice/myrepo", "translate_repo: full_name")
eq(tr.node_id, "", "translate_repo: node_id is empty string")
eq(tr.owner.login, "alice", "translate_repo: owner.login")
eq(tr.stargazers_count, 5, "translate_repo: stargazers_count from stars_count")
eq(tr.watchers_count, 3, "translate_repo: watchers_count")
eq(tr.forks_count, 2, "translate_repo: forks_count")
eq(tr.homepage, "https://alice.example.com", "translate_repo: homepage from website")
eq(tr.clone_url, "https://example.com/alice/myrepo.git", "translate_repo: clone_url")
eq(tr.ssh_url, "git@example.com:alice/myrepo.git", "translate_repo: ssh_url")
eq(tr.git_url, "git@example.com:alice/myrepo.git", "translate_repo: git_url from ssh_url")
eq(tr.created_at, "2024-01-01T00:00:00Z", "translate_repo: created_at from created")
eq(tr.updated_at, "2024-06-01T00:00:00Z", "translate_repo: updated_at from updated")
eq(tr.pushed_at, "2024-06-01T00:00:00Z", "translate_repo: pushed_at from updated")
eq(tr.disabled, false, "translate_repo: disabled always false")
eq(tr.visibility, "public", "translate_repo: visibility")

-- visibility derived from private flag when not explicit
local tr_priv =
  translate_repo(setmetatable({ private = true, owner = {} }, { __index = fake_repo }))
eq(tr_priv.visibility, "public", "translate_repo: visibility from repo.visibility takes precedence")
local tr_priv2 = translate_repo({
  id = 1,
  name = "x",
  full_name = "a/x",
  private = true,
  owner = {},
  stars_count = 0,
  watchers_count = 0,
  forks_count = 0,
  open_issues_count = 0,
})
eq(tr_priv2.visibility, "private", "translate_repo: visibility derived from private=true")

ok(type(translate_repo(nil)) == "table", "translate_repo(nil): returns empty table")

-- ============================================================
-- translate_user
-- ============================================================

local fake_user = {
  login = "alice",
  id = 1,
  avatar_url = "https://example.com/alice.png",
  html_url = "https://example.com/alice",
  is_admin = false,
  full_name = "Alice Smith",
  email = "alice@example.com",
  location = "Wonderland",
  website = "https://alice.example.com",
  followers_count = 10,
  following_count = 5,
  created = "2024-01-01T00:00:00Z",
}

local tu = translate_user(fake_user)
eq(tu.login, "alice", "translate_user: login")
eq(tu.id, 1, "translate_user: id")
eq(tu.node_id, "", "translate_user: node_id is empty string")
eq(tu.name, "Alice Smith", "translate_user: name from full_name")
eq(tu.email, "alice@example.com", "translate_user: email")
eq(tu.location, "Wonderland", "translate_user: location")
eq(tu.blog, "https://alice.example.com", "translate_user: blog from website")
eq(tu.followers, 10, "translate_user: followers from followers_count")
eq(tu.following, 5, "translate_user: following from following_count")
eq(tu.type, "User", "translate_user: type always User")
eq(tu.site_admin, false, "translate_user: site_admin from is_admin")
eq(tu.created_at, "2024-01-01T00:00:00Z", "translate_user: created_at from created")

-- is_admin=true
local tu_admin = translate_user(setmetatable({ is_admin = true }, { __index = fake_user }))
eq(tu_admin.site_admin, true, "translate_user: site_admin=true when is_admin=true")

-- missing optional counts default to 0
local tu_minimal = translate_user({ login = "bob", id = 2 })
eq(tu_minimal.followers, 0, "translate_user: followers defaults to 0")
eq(tu_minimal.following, 0, "translate_user: following defaults to 0")

ok(type(translate_user(nil)) == "table", "translate_user(nil): returns empty table")

-- ============================================================
-- translate_migration
-- ============================================================

local fake_migration = {
  id = 7,
  node_id = "MDEy1234",
  owner = { login = "alice" },
  guid = "abc-123",
  state = "exported",
  lock_repositories = true,
  exclude_metadata = true,
  exclude_git_data = false,
  exclude_attachments = false,
  exclude_releases = false,
  exclude_owner_projects = false,
  org_metadata_only = false,
  repositories = { { id = 1 } },
  url = "https://example.com/migrations/7",
  created_at = "2024-01-01T00:00:00Z",
  updated_at = "2024-06-01T00:00:00Z",
  archive_url = "https://example.com/migrations/7/archive.tar.gz",
  exclude = { "repositories" },
}
local tm = translate_migration(fake_migration)
eq(tm.id, 7, "translate_migration: id")
eq(tm.node_id, "MDEy1234", "translate_migration: node_id")
eq(tm.owner.login, "alice", "translate_migration: owner")
eq(tm.guid, "abc-123", "translate_migration: guid")
eq(tm.state, "exported", "translate_migration: state")
eq(tm.lock_repositories, true, "translate_migration: lock_repositories")
eq(tm.exclude_metadata, true, "translate_migration: exclude_metadata")
eq(tm.exclude_git_data, false, "translate_migration: exclude_git_data")
eq(tm.exclude_attachments, false, "translate_migration: exclude_attachments")
eq(tm.exclude_releases, false, "translate_migration: exclude_releases")
eq(tm.exclude_owner_projects, false, "translate_migration: exclude_owner_projects")
eq(tm.org_metadata_only, false, "translate_migration: org_metadata_only")
eq(tm.repositories[1].id, 1, "translate_migration: repositories")
eq(tm.url, "https://example.com/migrations/7", "translate_migration: url")
eq(tm.created_at, "2024-01-01T00:00:00Z", "translate_migration: created_at")
eq(tm.updated_at, "2024-06-01T00:00:00Z", "translate_migration: updated_at")
eq(
  tm.archive_url,
  "https://example.com/migrations/7/archive.tar.gz",
  "translate_migration: archive_url"
)
eq(tm.exclude[1], "repositories", "translate_migration: exclude")

local tm_minimal = translate_migration({ id = 1 })
eq(tm_minimal.node_id, "", "translate_migration: node_id defaults to empty string")
eq(tm_minimal.guid, "", "translate_migration: guid defaults to empty string")
eq(tm_minimal.state, "pending", "translate_migration: state defaults to pending")
eq(tm_minimal.lock_repositories, false, "translate_migration: lock_repositories defaults to false")
eq(tm_minimal.url, "", "translate_migration: url defaults to empty string")

ok(type(translate_migration(nil)) == "table", "translate_migration(nil): returns empty table")

-- ============================================================
-- proxy_json
-- ============================================================

reset_response()
proxy_json(nil, true, 200, {}, '{"foo":"bar"}')
eq(_last_status, 200, "proxy_json: success → 200")
ok(_last_body ~= "", "proxy_json: non-empty body on success")

reset_response()
proxy_json(function(r)
  r.extra = true
  return r
end, true, 200, {}, '{"x":1}')
ok(_last_body:find("extra") ~= nil, "proxy_json: translate fn applied")

reset_response()
proxy_json(nil, true, 404, {}, "{}")
eq(_last_status, 404, "proxy_json: upstream non-200 forwarded")

reset_response()
proxy_json(nil, false, nil, nil, nil)
eq(_last_status, 503, "proxy_json: pcall failure → 503")

-- translate returning nil falls back to empty table
reset_response()
proxy_json(function(_r)
  return nil
end, true, 200, {}, '{"x":1}')
eq(_last_status, 200, "proxy_json: nil translate return → still 200")

-- ============================================================
-- proxy_json_paged
-- ============================================================

reset_request({
  headers = { Host = "proxy.example.com", ["X-Forwarded-Proto"] = "http" },
  path = "/user/repos",
})

reset_response()
local paged_link = '<https://gitea.com/api/v1/repos/search?limit=10&page=2>; rel="next"'
proxy_json_paged(
  nil,
  { per_page = "limit", page = "page" },
  true,
  200,
  { Link = paged_link },
  '[{"id":1}]'
)
eq(_last_status, 200, "proxy_json_paged: success → 200")
ok(_last_headers["Link"] ~= nil, "proxy_json_paged: Link header present")
ok(_last_headers["Link"]:find("proxy.example.com") ~= nil, "proxy_json_paged: Link rewrites host")

reset_response()
proxy_json_paged(nil, { per_page = "limit", page = "page" }, true, 200, {}, '[{"id":1}]')
ok(_last_headers["Link"] == nil, "proxy_json_paged: no Link when upstream has none")

reset_response()
proxy_json_paged(nil, { per_page = "limit", page = "page" }, true, 404, {}, "{}")
eq(_last_status, 404, "proxy_json_paged: upstream non-200 forwarded")

reset_response()
proxy_json_paged(nil, { per_page = "limit", page = "page" }, false, nil, nil, nil)
eq(_last_status, 503, "proxy_json_paged: pcall failure → 503")

reset_response()
proxy_json_paged(function(r)
  return { translated = #r }
end, { per_page = "limit", page = "page" }, true, 200, {}, '[{"id":1},{"id":2}]')
eq(_last_status, 200, "proxy_json_paged: translate fn applied")
ok(_last_body:find("translated") ~= nil, "proxy_json_paged: translated body emitted")

-- ============================================================
-- proxy_json_created
-- ============================================================

reset_response()
proxy_json_created(nil, true, 201, {}, '{"id":99}')
eq(_last_status, 201, "proxy_json_created: upstream 201 → 201")

reset_response()
proxy_json_created(nil, true, 200, {}, '{"id":99}')
eq(_last_status, 201, "proxy_json_created: upstream 200 → 201")

reset_response()
proxy_json_created(nil, true, 404, {}, "{}")
eq(_last_status, 404, "proxy_json_created: upstream 404 forwarded")

reset_response()
proxy_json_created(nil, false, nil, nil, nil)
eq(_last_status, 503, "proxy_json_created: pcall failure → 503")

reset_response()
proxy_json_created(function(r)
  r.created = true
  return r
end, true, 201, {}, '{"id":1}')
eq(_last_status, 201, "proxy_json_created: translate fn applied")
ok(_last_body:find("created") ~= nil, "proxy_json_created: translated body emitted")

-- ============================================================
-- proxy_health_check
-- ============================================================

reset_response()
proxy_health_check(true, 200)
eq(_last_status, 200, "proxy_health_check: upstream 200 → 200")
eq(_last_body, "{}", "proxy_health_check: upstream 200 → empty object body")

reset_response()
proxy_health_check(true, 404)
eq(_last_status, 503, "proxy_health_check: upstream non-200 → 503")

reset_response()
proxy_health_check(true, 503)
eq(_last_status, 503, "proxy_health_check: upstream 503 → 503")

reset_response()
proxy_health_check(false, nil)
eq(_last_status, 503, "proxy_health_check: pcall failure → 503")

-- ============================================================
-- proxy_204
-- ============================================================

-- 204-only (also_ok = nil)
reset_response()
proxy_204(nil, true, 204)
eq(_last_status, 204, "proxy_204: upstream 204 → 204")
eq(_last_body, "", "proxy_204: upstream 204 → no body")

reset_response()
proxy_204(nil, true, 404)
eq(_last_status, 404, "proxy_204: upstream 404 forwarded")

reset_response()
proxy_204(nil, false, nil)
eq(_last_status, 503, "proxy_204: pcall failure → 503")

-- also_ok = {200}
reset_response()
proxy_204({ 200 }, true, 200)
eq(_last_status, 204, "proxy_204({200}): upstream 200 → 204")

reset_response()
proxy_204({ 200 }, true, 204)
eq(_last_status, 204, "proxy_204({200}): upstream 204 → 204")

reset_response()
proxy_204({ 200 }, true, 422)
eq(_last_status, 422, "proxy_204({200}): upstream 422 forwarded")

-- also_ok = {202}
reset_response()
proxy_204({ 202 }, true, 202)
eq(_last_status, 204, "proxy_204({202}): upstream 202 → 204")

-- also_ok = {200, 201}
reset_response()
proxy_204({ 200, 201 }, true, 201)
eq(_last_status, 204, "proxy_204({200,201}): upstream 201 → 204")

reset_response()
proxy_204({ 200, 201 }, true, 204)
eq(_last_status, 204, "proxy_204({200,201}): upstream 204 → 204")

reset_response()
proxy_204({ 200, 201 }, false, nil)
eq(_last_status, 503, "proxy_204({200,201}): pcall failure → 503")

-- ============================================================
-- proxy_json_list
-- ============================================================

local function identity_list(x)
  return x
end

reset_response()
proxy_json_list(identity_list, true, 200, {}, '[{"a":1},{"b":2}]')
eq(_last_status, 200, "proxy_json_list: upstream 200 → 200")
ok(
  _last_body == '[{"a":1},{"b":2}]' or _last_body == '[{"b":2},{"a":1}]',
  "proxy_json_list: non-empty array body"
)

reset_response()
proxy_json_list(identity_list, true, 200, {}, "[]")
eq(_last_status, 200, "proxy_json_list: upstream empty array → 200")
eq(_last_body, "[]", "proxy_json_list: upstream empty array → [] body")

reset_response()
proxy_json_list(identity_list, true, 404, {}, "{}")
eq(_last_status, 404, "proxy_json_list: upstream non-200 forwarded")

reset_response()
proxy_json_list(identity_list, false, nil, nil, nil)
eq(_last_status, 503, "proxy_json_list: pcall failure → 503")

reset_response()
proxy_json_list(function(data)
  local out = {}
  for i, x in ipairs(data) do
    out[i] = { v = (x.v or 0) * 2 }
  end
  return out
end, true, 200, {}, '[{"v":3}]')
eq(_last_status, 200, "proxy_json_list: translate applied")
ok(_last_body:find('"v":6') ~= nil, "proxy_json_list: translate doubles value")

-- ============================================================
-- translate_list
-- ============================================================

local tl = translate_list(function(x)
  return x * 2
end, { 1, 2, 3 })
eq(#tl, 3, "translate_list: length preserved")
eq(tl[1], 2, "translate_list: first element doubled")
eq(tl[3], 6, "translate_list: third element doubled")

local tl_empty = translate_list(function(x)
  return x
end, {})
eq(#tl_empty, 0, "translate_list: empty input → empty output")

local tl_nil = translate_list(function(x)
  return x
end, nil)
eq(#tl_nil, 0, "translate_list: nil input → empty output")

-- ============================================================
-- proxy_search_envelope
-- ============================================================

reset_response()
proxy_search_envelope(function(x)
  return { id = x.id * 10 }
end, nil, true, 200, {}, '[{"id":1},{"id":2}]')
eq(_last_status, 200, "proxy_search_envelope(nil container): 200")
ok(_last_body:find('"total_count":2') ~= nil, "proxy_search_envelope(nil container): total_count")
ok(
  _last_body:find('"incomplete_results":false') ~= nil,
  "proxy_search_envelope: incomplete_results false"
)
ok(_last_body:find('"id":10') ~= nil, "proxy_search_envelope: translate_item applied")

reset_response()
proxy_search_envelope(function(x)
  return { v = x.v }
end, "values", true, 200, {}, '{"values":[{"v":7}],"size":1}')
eq(_last_status, 200, "proxy_search_envelope(string container): 200")
ok(
  _last_body:find('"total_count":1') ~= nil,
  "proxy_search_envelope(string container): total_count 1"
)
ok(_last_body:find('"v":7') ~= nil, "proxy_search_envelope(string container): item translated")

reset_response()
proxy_search_envelope(function(x)
  return x
end, nil, true, 200, {}, "[]")
ok(_last_body:find('"items":%[%]') ~= nil, "proxy_search_envelope: empty array → items:[]")

reset_response()
proxy_search_envelope(function(x)
  return x
end, nil, true, 404, {}, "{}")
eq(_last_status, 404, "proxy_search_envelope: upstream non-200 forwarded")

reset_response()
proxy_search_envelope(function(x)
  return x
end, nil, false, nil, nil, nil)
eq(_last_status, 503, "proxy_search_envelope: pcall failure → 503")

-- ============================================================
-- make_proxy_handler
-- ============================================================

local fetch_log = {}
local function fake_fetch(url)
  fetch_log[#fetch_log + 1] = url
  return true, 200, {}, '{"fetched":true}'
end

local ph = make_proxy_handler(fake_fetch)
reset_response()
local handler = ph(nil, function(owner, repo)
  return "https://example.com/" .. owner .. "/" .. repo
end)
handler("alice", "myrepo")
eq(
  fetch_log[#fetch_log],
  "https://example.com/alice/myrepo",
  "make_proxy_handler: url_fn called with handler args"
)
eq(_last_status, 200, "make_proxy_handler: response proxied")

-- translate fn receives handler args too
fetch_log = {}
reset_response()
local handler2 = ph(function(r, owner, repo)
  r.owner_arg = owner
  r.repo_arg = repo
  return r
end, function(owner, repo)
  return "https://example.com/" .. owner .. "/" .. repo
end)
handler2("bob", "testrepo")
eq(
  fetch_log[#fetch_log],
  "https://example.com/bob/testrepo",
  "make_proxy_handler: url_fn receives args"
)
ok(
  _last_body:find("bob") ~= nil and _last_body:find("testrepo") ~= nil,
  "make_proxy_handler: translate fn receives handler args"
)

-- custom proxy_fn (proxy_json_created)
fetch_log = {}
reset_response()
local fake_fetch_201 = function(_url)
  return true, 201, {}, '{"id":7}'
end
local ph_created = make_proxy_handler(fake_fetch_201, proxy_json_created)
local handler3 = ph_created(nil, function()
  return "https://example.com/repos"
end)
handler3()
eq(_last_status, 201, "make_proxy_handler: custom proxy_fn (proxy_json_created) used")

-- ============================================================
-- make_backend_transport
-- ============================================================

do
  -- Stub Fetch for this section so fetch_json doesn't hit the network.
  -- luacheck: push
  -- luacheck: globals Fetch
  local captured_url, captured_opts, stub_ok, stub_status, stub_headers, stub_body

  local function set_fetch_stub(stub_ok_arg, status, headers, body)
    stub_ok = stub_ok_arg
    stub_status = status
    stub_headers = headers
    stub_body = body
    Fetch = function(url, opts)
      captured_url = url
      captured_opts = opts
      if stub_ok then
        return stub_status, stub_headers, stub_body
      else
        error("network error")
      end
    end
  end
  -- luacheck: pop

  -- Returns the four sub-fields.
  local t_tok = make_backend_transport("token", { per_page = "limit", page = "page" })
  ok(type(t_tok.fetch_json) == "function", "make_backend_transport: fetch_json is a function")
  ok(type(t_tok.proxy_handler) == "function", "make_backend_transport: proxy_handler is a function")
  ok(
    type(t_tok.proxy_handler_created) == "function",
    "make_backend_transport: proxy_handler_created is a function"
  )
  ok(
    type(t_tok.proxy_handler_paged) == "function",
    "make_backend_transport: proxy_handler_paged is a function when pages supplied"
  )

  -- Without pages, proxy_handler_paged is nil.
  local t_nopages = make_backend_transport("bearer")
  ok(
    t_nopages.proxy_handler_paged == nil,
    "make_backend_transport: proxy_handler_paged is nil when pages omitted"
  )

  -- fetch_json GET: no method or body modifications.
  reset_request({ headers = { Authorization = "token mytoken" } })
  set_fetch_stub(true, 200, {}, '{"ok":true}')
  captured_url, captured_opts = nil, nil
  local ok2, status2 = t_tok.fetch_json("https://example.com/api/repos")
  ok(ok2, "make_backend_transport fetch_json GET: pcall ok")
  eq(status2, 200, "make_backend_transport fetch_json GET: status 200")
  eq(
    captured_url,
    "https://example.com/api/repos",
    "make_backend_transport fetch_json GET: url forwarded"
  )
  ok(
    captured_opts == nil or captured_opts.method == nil,
    "make_backend_transport fetch_json GET: no method override"
  )
  ok(
    captured_opts == nil
      or captured_opts.headers == nil
      or captured_opts.headers["Content-Type"] == nil,
    "make_backend_transport fetch_json GET: no Content-Type"
  )

  -- fetch_json POST with body: sets method and Content-Type.
  reset_request({ headers = { Authorization = "token mytoken" } })
  set_fetch_stub(true, 201, {}, '{"id":1}')
  captured_opts = nil
  t_tok.fetch_json("https://example.com/api/repos", "POST", '{"name":"foo"}')
  eq(
    captured_opts and captured_opts.method,
    "POST",
    "make_backend_transport fetch_json POST: method set"
  )
  eq(
    captured_opts and captured_opts.body,
    '{"name":"foo"}',
    "make_backend_transport fetch_json POST: body set"
  )
  eq(
    captured_opts and captured_opts.headers and captured_opts.headers["Content-Type"],
    "application/json",
    "make_backend_transport fetch_json POST: Content-Type set"
  )

  -- fetch_json POST without body: method set, no Content-Type.
  reset_request({ headers = { Authorization = "token mytoken" } })
  set_fetch_stub(true, 204, {}, "")
  captured_opts = nil
  t_tok.fetch_json("https://example.com/api/repos", "DELETE")
  eq(
    captured_opts and captured_opts.method,
    "DELETE",
    "make_backend_transport fetch_json DELETE: method set"
  )
  ok(
    captured_opts == nil
      or captured_opts.headers == nil
      or captured_opts.headers["Content-Type"] == nil,
    "make_backend_transport fetch_json DELETE: no Content-Type without body"
  )

  -- fetch_json: auth header forwarded under the requested scheme.
  reset_request({ headers = { Authorization = "token mytoken" } })
  set_fetch_stub(true, 200, {}, "{}")
  captured_opts = nil
  t_tok.fetch_json("https://example.com/api")
  ok(
    captured_opts ~= nil and captured_opts.headers["Authorization"] == "token mytoken",
    "make_backend_transport fetch_json: token auth scheme forwarded"
  )

  reset_request({ headers = { Authorization = "token mybearer" } })
  local t_bearer = make_backend_transport("bearer")
  set_fetch_stub(true, 200, {}, "{}")
  captured_opts = nil
  t_bearer.fetch_json("https://example.com/api")
  ok(
    captured_opts ~= nil and captured_opts.headers["Authorization"] == "Bearer mybearer",
    "make_backend_transport fetch_json: bearer auth scheme forwarded"
  )

  -- fetch_json with no Authorization: opts nil, no header sent.
  reset_request({ headers = {} })
  set_fetch_stub(true, 200, {}, "{}")
  captured_opts = "sentinel"
  t_tok.fetch_json("https://example.com/api")
  ok(captured_opts == nil, "make_backend_transport fetch_json: nil opts when no Authorization")

  -- proxy_handler_paged uses the correct pages mapping.
  reset_request({
    headers = { Host = "proxy.example.com", ["X-Forwarded-Proto"] = "http" },
    path = "/user/repos",
    params = {},
  })
  set_fetch_stub(
    true,
    200,
    { Link = '<https://upstream.example.com/api/repos?limit=10&page=2>; rel="next"' },
    '[{"id":1}]'
  )
  reset_response()
  local paged_h = t_tok.proxy_handler_paged(nil, function()
    return "https://upstream.example.com/api/repos?limit=10"
  end)
  paged_h()
  eq(_last_status, 200, "make_backend_transport proxy_handler_paged: 200 on success")
  ok(
    _last_headers["Link"] ~= nil,
    "make_backend_transport proxy_handler_paged: Link header rewritten"
  )
  ok(
    _last_headers["Link"]:find("per_page=10") ~= nil,
    "make_backend_transport proxy_handler_paged: limit translated to per_page"
  )
end

-- ============================================================
-- OnHttpRequest
-- ============================================================

-- GET / with no backend → default handler returns {}
reset_response()
reset_request({ method = "GET", path = "/" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET / → 200")

-- DELETE /rate_limit — known path, wrong method → 405
reset_response()
reset_request({ method = "DELETE", path = "/rate_limit" })
OnHttpRequest()
eq(_last_status, 405, "OnHttpRequest: wrong method on known path → 405")

-- GET /nonexistent — unknown path → 404
reset_response()
reset_request({ method = "GET", path = "/nonexistent/path/that/does/not/exist" })
OnHttpRequest()
eq(_last_status, 404, "OnHttpRequest: unknown path → 404")

-- GET /zen — built-in, no backend needed
reset_response()
reset_request({ method = "GET", path = "/zen" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /zen → 200")

-- GET /meta — built-in
reset_response()
reset_request({ method = "GET", path = "/meta" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /meta → 200")

-- GET /teapot — 418
reset_response()
reset_request({ method = "GET", path = "/teapot" })
OnHttpRequest()
eq(_last_status, 418, "OnHttpRequest: GET /teapot → 418")

-- GET /rate_limit — default handler
reset_response()
reset_request({ method = "GET", path = "/rate_limit" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /rate_limit → 200")

-- GET /octocat — built-in, no backend needed
reset_response()
reset_request({ method = "GET", path = "/octocat" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /octocat → 200")

-- GET /versions — built-in
reset_response()
reset_request({ method = "GET", path = "/versions" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /versions → 200")

-- GET /issues — default empty_list fallback
reset_response()
reset_request({ method = "GET", path = "/issues" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /issues → 200 (empty_list default)")

-- GET /search/code — default search_empty fallback
reset_response()
reset_request({ method = "GET", path = "/search/code" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /search/code → 200 (search_empty default)")

-- GET /user/interaction-limits — default interaction_limits_empty
reset_response()
reset_request({ method = "GET", path = "/user/interaction-limits" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /user/interaction-limits → 200")
eq(_last_body, "{}", "OnHttpRequest: GET /user/interaction-limits → empty object body")

-- PUT /user/interaction-limits — default interaction_limits_put echoes body
reset_response()
reset_request({
  method = "PUT",
  path = "/user/interaction-limits",
  body = '{"limit":"collaborators_only","expiry":"one_day"}',
})
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: PUT /user/interaction-limits → 200")
ok(
  _last_body:find("collaborators_only") ~= nil,
  "OnHttpRequest: PUT /user/interaction-limits → echoes body"
)

-- DELETE /user/interaction-limits — default interaction_limits_delete returns 204
reset_response()
reset_request({ method = "DELETE", path = "/user/interaction-limits" })
OnHttpRequest()
eq(_last_status, 204, "OnHttpRequest: DELETE /user/interaction-limits → 204")

-- GET /repos/{owner}/{repo} — no backend → 404 (no default_fn)
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo" })
OnHttpRequest()
eq(_last_status, 404, "OnHttpRequest: backend endpoint without default → 404")

-- app.allow_anonymous=false, no Authorization → 401
reset_response()
reset_request({ method = "GET", path = "/" })
app.allow_anonymous = false
OnHttpRequest()
eq(_last_status, 401, "OnHttpRequest: anon forbidden when app.allow_anonymous=false → 401")
app.allow_anonymous = true

-- app.allow_anonymous=false, with Authorization → proceeds normally
reset_response()
reset_request({ method = "GET", path = "/", headers = { Authorization = "token mytoken" } })
app.allow_anonymous = false
OnHttpRequest()
eq(
  _last_status,
  200,
  "OnHttpRequest: authorized request allowed when app.allow_anonymous=false → 200"
)
app.allow_anonymous = true

-- GET /orgs/{org}/code-scanning/alerts — code_scanning_list_empty default → 200
reset_response()
reset_request({ method = "GET", path = "/orgs/myorg/code-scanning/alerts" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /orgs/{org}/code-scanning/alerts → 200 (empty list)")

-- GET /repos/{owner}/{repo}/code-scanning/alerts/{alert_number} — code_scanning_not_implemented default → 501
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/code-scanning/alerts/1" })
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: GET /repos/{owner}/{repo}/code-scanning/alerts/{alert_number} → 501 (not implemented)"
)

-- POST /orgs/{org}/migrations — migrations_not_supported default → 501
reset_response()
reset_request({ method = "POST", path = "/orgs/myorg/migrations" })
OnHttpRequest()
eq(_last_status, 501, "OnHttpRequest: POST /orgs/{org}/migrations → 501 (not supported)")

-- POST /user/migrations — migrations_not_supported default → 501
reset_response()
reset_request({ method = "POST", path = "/user/migrations" })
OnHttpRequest()
eq(_last_status, 501, "OnHttpRequest: POST /user/migrations → 501 (not supported)")

-- GET /orgs/{org}/migrations/{migration_id} — migration_not_found default → 404
reset_response()
reset_request({ method = "GET", path = "/orgs/myorg/migrations/7" })
OnHttpRequest()
eq(
  _last_status,
  404,
  "OnHttpRequest: GET /orgs/{org}/migrations/{migration_id} → 404 (not found)"
)

-- GET /repos/{owner}/{repo}/import — source_import_gone default → 410
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/import" })
OnHttpRequest()
eq(_last_status, 410, "OnHttpRequest: GET /repos/{owner}/{repo}/import → 410 (deprecated)")

-- GET /repos/{owner}/{repo}/pages — pages_not_implemented default → 501
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/pages" })
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: GET /repos/{owner}/{repo}/pages → 501 (pages not implemented)"
)

-- POST /markdown — markdown_not_implemented default → 501
reset_response()
reset_request({ method = "POST", path = "/markdown" })
OnHttpRequest()
eq(_last_status, 501, "OnHttpRequest: POST /markdown → 501 (markdown not implemented)")

-- POST /markdown/raw — markdown_not_implemented default → 501
reset_response()
reset_request({ method = "POST", path = "/markdown/raw" })
OnHttpRequest()
eq(_last_status, 501, "OnHttpRequest: POST /markdown/raw → 501 (markdown not implemented)")

-- Actions default handlers — each function must be hit at least once.

-- actions_not_implemented: GET /enterprises/{enterprise}/actions/cache/retention-limit → 501
reset_response()
reset_request({ method = "GET", path = "/enterprises/myenterprise/actions/cache/retention-limit" })
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: GET /enterprises/{enterprise}/actions/cache/retention-limit → 501 (actions not implemented)"
)

-- actions_runs_empty: GET /repos/{owner}/{repo}/actions/runs → 200 with workflow_runs list
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/actions/runs" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /repos/{owner}/{repo}/actions/runs → 200 (runs empty)")
ok(
  _last_body:find("workflow_runs") ~= nil,
  "OnHttpRequest: GET /repos/{owner}/{repo}/actions/runs → body contains workflow_runs"
)

-- actions_artifacts_empty: GET /repos/{owner}/{repo}/actions/artifacts → 200 with artifacts list
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/actions/artifacts" })
OnHttpRequest()
eq(
  _last_status,
  200,
  "OnHttpRequest: GET /repos/{owner}/{repo}/actions/artifacts → 200 (artifacts empty)"
)
ok(
  _last_body:find("artifacts") ~= nil,
  "OnHttpRequest: GET /repos/{owner}/{repo}/actions/artifacts → body contains artifacts"
)

-- actions_jobs_empty: GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs → 200 with jobs list
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/actions/runs/42/jobs" })
OnHttpRequest()
eq(
  _last_status,
  200,
  "OnHttpRequest: GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs → 200 (jobs empty)"
)
ok(
  _last_body:find('"jobs"') ~= nil,
  "OnHttpRequest: GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs → body contains jobs"
)

-- actions_runners_empty: GET /orgs/{org}/actions/hosted-runners → 200 with runners list
reset_response()
reset_request({ method = "GET", path = "/orgs/myorg/actions/hosted-runners" })
OnHttpRequest()
eq(
  _last_status,
  200,
  "OnHttpRequest: GET /orgs/{org}/actions/hosted-runners → 200 (runners empty)"
)
ok(
  _last_body:find("runners") ~= nil,
  "OnHttpRequest: GET /orgs/{org}/actions/hosted-runners → body contains runners"
)

-- actions_runner_groups_empty: GET /orgs/{org}/actions/runner-groups → 200 with runner_groups list
reset_response()
reset_request({ method = "GET", path = "/orgs/myorg/actions/runner-groups" })
OnHttpRequest()
eq(
  _last_status,
  200,
  "OnHttpRequest: GET /orgs/{org}/actions/runner-groups → 200 (runner groups empty)"
)
ok(
  _last_body:find("runner_groups") ~= nil,
  "OnHttpRequest: GET /orgs/{org}/actions/runner-groups → body contains runner_groups"
)

-- actions_secrets_empty: GET /orgs/{org}/actions/secrets → 200 with secrets list
reset_response()
reset_request({ method = "GET", path = "/orgs/myorg/actions/secrets" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /orgs/{org}/actions/secrets → 200 (secrets empty)")
ok(
  _last_body:find("secrets") ~= nil,
  "OnHttpRequest: GET /orgs/{org}/actions/secrets → body contains secrets"
)

-- actions_variables_empty: GET /orgs/{org}/actions/variables → 200 with variables list
reset_response()
reset_request({ method = "GET", path = "/orgs/myorg/actions/variables" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /orgs/{org}/actions/variables → 200 (variables empty)")
ok(
  _last_body:find("variables") ~= nil,
  "OnHttpRequest: GET /orgs/{org}/actions/variables → body contains variables"
)

-- actions_caches_empty: GET /repos/{owner}/{repo}/actions/caches → 200 with actions_caches list
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/actions/caches" })
OnHttpRequest()
eq(
  _last_status,
  200,
  "OnHttpRequest: GET /repos/{owner}/{repo}/actions/caches → 200 (caches empty)"
)
ok(
  _last_body:find("actions_caches") ~= nil,
  "OnHttpRequest: GET /repos/{owner}/{repo}/actions/caches → body contains actions_caches"
)

-- actions_workflows_empty: GET /repos/{owner}/{repo}/actions/workflows → 200 with workflows list
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/actions/workflows" })
OnHttpRequest()
eq(
  _last_status,
  200,
  "OnHttpRequest: GET /repos/{owner}/{repo}/actions/workflows → 200 (workflows empty)"
)
ok(
  _last_body:find("workflows") ~= nil,
  "OnHttpRequest: GET /repos/{owner}/{repo}/actions/workflows → body contains workflows"
)

-- licenses_not_implemented: GET /licenses → 501
reset_response()
reset_request({ method = "GET", path = "/licenses" })
OnHttpRequest()
eq(_last_status, 501, "OnHttpRequest: GET /licenses → 501 (licenses not implemented)")

-- licenses_not_implemented: GET /licenses/{license} → 501
reset_response()
reset_request({ method = "GET", path = "/licenses/mit" })
OnHttpRequest()
eq(_last_status, 501, "OnHttpRequest: GET /licenses/{license} → 501 (licenses not implemented)")

-- licenses_not_implemented: GET /repos/{owner}/{repo}/license → 501
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/license" })
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: GET /repos/{owner}/{repo}/license → 501 (licenses not implemented)"
)

-- dependency_graph_not_implemented: GET /repos/{owner}/{repo}/dependency-graph/compare/{basehead} → 501
reset_response()
reset_request({
  method = "GET",
  path = "/repos/alice/myrepo/dependency-graph/compare/main...feature",
})
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: GET /repos/{owner}/{repo}/dependency-graph/compare/{basehead} → 501 (dependency graph not implemented)"
)

-- dependency_graph_not_implemented: GET /repos/{owner}/{repo}/dependency-graph/sbom → 501
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/dependency-graph/sbom" })
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: GET /repos/{owner}/{repo}/dependency-graph/sbom → 501 (dependency graph not implemented)"
)

-- dependency_graph_not_implemented: POST /repos/{owner}/{repo}/dependency-graph/snapshots → 501
reset_response()
reset_request({ method = "POST", path = "/repos/alice/myrepo/dependency-graph/snapshots" })
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: POST /repos/{owner}/{repo}/dependency-graph/snapshots → 501 (dependency graph not implemented)"
)

-- git_not_implemented: any git database route → 501
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/git/blobs/abc123" })
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: GET /repos/{owner}/{repo}/git/blobs/{file_sha} → 501 (git database not implemented)"
)

-- greedy param trie walk: route with {ref+} matches multi-segment ref
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/git/ref/heads/main" })
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: GET /repos/{owner}/{repo}/git/ref/{ref+} with multi-segment ref → 501"
)

-- checks_post_check_runs: POST /repos/{owner}/{repo}/check-runs → 201 with id/head_sha/name/status/output
reset_response()
reset_request({
  method = "POST",
  path = "/repos/alice/myrepo/check-runs",
  body = '{"head_sha":"abc123","name":"my-check","status":"in_progress"}',
})
OnHttpRequest()
eq(_last_status, 201, "OnHttpRequest: POST /repos/{owner}/{repo}/check-runs → 201")
ok(
  _last_body:find('"head_sha"') ~= nil,
  "OnHttpRequest: POST /repos/{owner}/{repo}/check-runs → body has head_sha"
)
ok(
  _last_body:find('"output"') ~= nil,
  "OnHttpRequest: POST /repos/{owner}/{repo}/check-runs → body has output"
)

-- checks_get_check_run: GET /repos/{owner}/{repo}/check-runs/{check_run_id} → 200
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/check-runs/42" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /repos/{owner}/{repo}/check-runs/{check_run_id} → 200")
ok(
  _last_body:find('"id"') ~= nil,
  "OnHttpRequest: GET /repos/{owner}/{repo}/check-runs/{check_run_id} → body has id"
)

-- checks_patch_check_run: PATCH /repos/{owner}/{repo}/check-runs/{check_run_id} → 200
reset_response()
reset_request({ method = "PATCH", path = "/repos/alice/myrepo/check-runs/42" })
OnHttpRequest()
eq(
  _last_status,
  200,
  "OnHttpRequest: PATCH /repos/{owner}/{repo}/check-runs/{check_run_id} → 200"
)

-- checks_get_check_run_annotations: GET /repos/{owner}/{repo}/check-runs/{check_run_id}/annotations → 200 []
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/check-runs/42/annotations" })
OnHttpRequest()
eq(
  _last_status,
  200,
  "OnHttpRequest: GET /repos/{owner}/{repo}/check-runs/{check_run_id}/annotations → 200"
)
eq(
  _last_body,
  "[]",
  "OnHttpRequest: GET /repos/{owner}/{repo}/check-runs/{check_run_id}/annotations → body is []"
)

-- checks_post_check_run_rerequest: POST /repos/{owner}/{repo}/check-runs/{check_run_id}/rerequest → 201
reset_response()
reset_request({ method = "POST", path = "/repos/alice/myrepo/check-runs/42/rerequest" })
OnHttpRequest()
eq(
  _last_status,
  201,
  "OnHttpRequest: POST /repos/{owner}/{repo}/check-runs/{check_run_id}/rerequest → 201"
)

-- checks_get_commit_check_runs: GET /repos/{owner}/{repo}/commits/{ref}/check-runs → 200 empty
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/commits/abc123/check-runs" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /repos/{owner}/{repo}/commits/{ref}/check-runs → 200")
ok(
  _last_body:find('"check_runs"') ~= nil,
  "OnHttpRequest: GET /repos/{owner}/{repo}/commits/{ref}/check-runs → body has check_runs"
)

-- checks_post_check_suites: POST /repos/{owner}/{repo}/check-suites → 201
reset_response()
reset_request({
  method = "POST",
  path = "/repos/alice/myrepo/check-suites",
  body = '{"head_sha":"abc123"}',
})
OnHttpRequest()
eq(_last_status, 201, "OnHttpRequest: POST /repos/{owner}/{repo}/check-suites → 201")
ok(
  _last_body:find('"head_sha"') ~= nil,
  "OnHttpRequest: POST /repos/{owner}/{repo}/check-suites → body has head_sha"
)

-- checks_patch_check_suites_preferences: PATCH /repos/{owner}/{repo}/check-suites/preferences → 200
reset_response()
reset_request({
  method = "PATCH",
  path = "/repos/alice/myrepo/check-suites/preferences",
  body = "{}",
})
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: PATCH /repos/{owner}/{repo}/check-suites/preferences → 200")
ok(
  _last_body:find('"preferences"') ~= nil,
  "OnHttpRequest: PATCH /repos/{owner}/{repo}/check-suites/preferences → body has preferences"
)

-- checks_get_check_suite: GET /repos/{owner}/{repo}/check-suites/{check_suite_id} → 200
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/check-suites/7" })
OnHttpRequest()
eq(
  _last_status,
  200,
  "OnHttpRequest: GET /repos/{owner}/{repo}/check-suites/{check_suite_id} → 200"
)
ok(
  _last_body:find('"repository"') ~= nil,
  "OnHttpRequest: GET /repos/{owner}/{repo}/check-suites/{check_suite_id} → body has repository"
)

-- checks_get_check_suite_check_runs: GET /repos/{owner}/{repo}/check-suites/{check_suite_id}/check-runs → 200 empty
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/check-suites/7/check-runs" })
OnHttpRequest()
eq(
  _last_status,
  200,
  "OnHttpRequest: GET /repos/{owner}/{repo}/check-suites/{check_suite_id}/check-runs → 200"
)
ok(
  _last_body:find('"check_runs"') ~= nil,
  "OnHttpRequest: GET /repos/{owner}/{repo}/check-suites/{check_suite_id}/check-runs → body has check_runs"
)

-- checks_post_check_suite_rerequest: POST /repos/{owner}/{repo}/check-suites/{check_suite_id}/rerequest → 201
reset_response()
reset_request({ method = "POST", path = "/repos/alice/myrepo/check-suites/7/rerequest" })
OnHttpRequest()
eq(
  _last_status,
  201,
  "OnHttpRequest: POST /repos/{owner}/{repo}/check-suites/{check_suite_id}/rerequest → 201"
)

-- checks_get_commit_check_suites: GET /repos/{owner}/{repo}/commits/{ref}/check-suites → 200 empty
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/commits/abc123/check-suites" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /repos/{owner}/{repo}/commits/{ref}/check-suites → 200")
ok(
  _last_body:find('"check_suites"') ~= nil,
  "OnHttpRequest: GET /repos/{owner}/{repo}/commits/{ref}/check-suites → body has check_suites"
)

-- GET /orgs/{org}/dependabot/alerts — dependabot_list_empty default → 200
reset_response()
reset_request({ method = "GET", path = "/orgs/myorg/dependabot/alerts" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /orgs/{org}/dependabot/alerts → 200 (empty list)")

-- GET /repos/{owner}/{repo}/dependabot/alerts/{alert_number} — dependabot_not_implemented default → 501
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/dependabot/alerts/1" })
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: GET /repos/{owner}/{repo}/dependabot/alerts/{alert_number} → 501 (dependabot not implemented)"
)

-- GET /orgs/{org}/projectsV2 — projects_list_empty default → 200
reset_response()
reset_request({ method = "GET", path = "/orgs/myorg/projectsV2" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /orgs/{org}/projectsV2 → 200 (empty list)")

-- GET /orgs/{org}/projectsV2/{project_number} — projects_not_implemented default → 501
reset_response()
reset_request({ method = "GET", path = "/orgs/myorg/projectsV2/1" })
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: GET /orgs/{org}/projectsV2/{project_number} → 501 (projects not implemented)"
)

-- GET /orgs/{org}/secret-scanning/alerts — secret_scanning_list_empty default → 200
reset_response()
reset_request({ method = "GET", path = "/orgs/myorg/secret-scanning/alerts" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /orgs/{org}/secret-scanning/alerts → 200 (empty list)")

-- GET /repos/{owner}/{repo}/secret-scanning/alerts/{alert_number} — secret_scanning_not_implemented default → 501
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo/secret-scanning/alerts/1" })
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: GET /repos/{owner}/{repo}/secret-scanning/alerts/{alert_number} → 501 (not implemented)"
)

-- POST /gists — gists_not_implemented default → 501
reset_response()
reset_request({ method = "POST", path = "/gists" })
OnHttpRequest()
eq(_last_status, 501, "OnHttpRequest: POST /gists → 501 (gists not supported)")

-- POST /repos/{owner}/{repo}/issues/{issue_number}/reactions — reactions_not_implemented default → 501
reset_response()
reset_request({ method = "POST", path = "/repos/alice/myrepo/issues/1/reactions" })
OnHttpRequest()
eq(
  _last_status,
  501,
  "OnHttpRequest: POST /repos/{owner}/{repo}/issues/{issue_number}/reactions → 501 (reactions not supported)"
)

-- GET /events — activity_list_empty default → 200 []
reset_response()
reset_request({ method = "GET", path = "/events" })
OnHttpRequest()
eq(_last_status, 200, "OnHttpRequest: GET /events → 200 (activity list empty)")
eq(_last_body, "[]", "OnHttpRequest: GET /events → body is []")

-- GET /feeds — activity_not_implemented default → 501
reset_response()
reset_request({ method = "GET", path = "/feeds" })
OnHttpRequest()
eq(_last_status, 501, "OnHttpRequest: GET /feeds → 501 (activity not implemented)")

-- ============================================================
-- b:build() strip patterns (alias feature gaps)
-- ============================================================

do
  local _saved_rest = app.backend.rest

  -- b:build(strip) with explicit strip patterns excludes matching REST keys.
  app.backend.rest = {}
  local bt = make_backend_builder()
  bt:rest("get_package_info", function() end)
  bt:rest("list_actions_runs", function() end)
  bt:rest("get_repo", function() end)
  bt:build({ "_package", "_actions_" })
  ok(app.backend.rest["get_package_info"] == nil, "b:build(strip): strips _package keys")
  ok(app.backend.rest["list_actions_runs"] == nil, "b:build(strip): strips _actions_ keys")
  ok(app.backend.rest["get_repo"] ~= nil, "b:build(strip): preserves non-matching keys")

  -- b:build() without strip registers all REST keys.
  app.backend.rest = {}
  local bt2 = make_backend_builder()
  bt2:rest("get_package_info", function() end)
  bt2:rest("get_repo", function() end)
  bt2:build()
  ok(
    app.backend.rest["get_package_info"] ~= nil,
    "b:build(): without strip, all keys are registered"
  )

  app.backend.rest = _saved_rest
end

-- ============================================================
-- app context
-- ============================================================

ok(type(app) == "table", "app: is a table")
ok(app.config == config, "app.config: same object as global config")
ok(type(app.backend) == "table", "app.backend: is a table")
ok(type(app.backend.rest) == "table", "app.backend.rest: is a table")
ok(type(app.backend.graphql) == "table", "app.backend.graphql: is a table")
ok(type(app.backend.capabilities) == "table", "app.backend.capabilities: is a table")
ok(type(app.backend.webhooks) == "table", "app.backend.webhooks: is a table")
ok(type(app.allow_anonymous) == "boolean", "app.allow_anonymous: is a boolean")
ok(app.allow_anonymous == true, "app.allow_anonymous: default true (no backend loaded)")
ok(type(app.route_match) == "function", "app.route_match: bound router lookup installed on app")
ok(
  type(app.path_known) == "function",
  "app.path_known: bound path-existence check installed on app"
)

-- make_app: constructs independent context from a given config table.
do
  local test_cfg = { backend = "test", base_url = "https://test.example.com" }
  local test_app = make_app(test_cfg)
  ok(test_app.config == test_cfg, "make_app: config is the supplied table")
  ok(type(test_app.backend) == "table", "make_app: backend is a table")
  ok(type(test_app.backend.rest) == "table", "make_app: backend.rest is a table")
  ok(type(test_app.backend.graphql) == "table", "make_app: backend.graphql is a table")
  ok(type(test_app.backend.capabilities) == "table", "make_app: backend.capabilities is a table")
  ok(type(test_app.backend.webhooks) == "table", "make_app: backend.webhooks is a table")
  ok(test_app.allow_anonymous == true, "make_app: allow_anonymous defaults to true")
  ok(test_app ~= app, "make_app: returns a new independent table each call")
end

-- ============================================================
-- make_backend_builder
-- ============================================================

do
  local saved_rest = app.backend.rest
  local saved_capabilities = app.backend.capabilities
  local saved_webhooks = app.backend.webhooks
  local saved_resolvers = graphql_resolvers -- luacheck: globals graphql_resolvers
  local saved_anon = app.allow_anonymous

  local function restore()
    app.backend.rest = saved_rest
    app.backend.capabilities = saved_capabilities
    app.backend.webhooks = saved_webhooks
    graphql_resolvers = saved_resolvers -- luacheck: globals graphql_resolvers
    app.allow_anonymous = saved_anon
  end

  -- factory returns a builder table with the expected methods
  local b = make_backend_builder()
  ok(type(b) == "table", "make_backend_builder: returns a table")
  ok(type(b.rest) == "function", "make_backend_builder: has rest method")
  ok(type(b.graphql) == "function", "make_backend_builder: has graphql method")
  ok(type(b.capability) == "function", "make_backend_builder: has capability method")
  ok(type(b.webhook) == "function", "make_backend_builder: has webhook method")
  ok(
    type(b.set_allow_anonymous) == "function",
    "make_backend_builder: has set_allow_anonymous method"
  )
  ok(type(b.build) == "function", "make_backend_builder: has build method")

  -- registration methods return self for chaining
  local b2 = make_backend_builder()
  ok(b2:rest("get_foo", function() end) == b2, "builder:rest: returns self")
  ok(b2:graphql("Query.foo", function() end) == b2, "builder:graphql: returns self")
  ok(b2:capability("repos", {}) == b2, "builder:capability: returns self")
  ok(b2:webhook("push", function() end) == b2, "builder:webhook: returns self")
  ok(b2:set_allow_anonymous(true) == b2, "builder:set_allow_anonymous: returns self")

  -- build() populates app.backend.rest, graphql_resolvers, app.backend.capabilities,
  -- and app.backend.webhooks
  app.backend.rest = {}
  app.backend.capabilities = {}
  app.backend.webhooks = {}
  graphql_resolvers = {} -- luacheck: globals graphql_resolvers
  app.allow_anonymous = true

  local get_fn = function() end
  local gql_fn = function() end
  local cap_repos = { get = function() end, list = function() end }
  local push_fn = function() end
  local b3 = make_backend_builder()
  b3:rest("get_repo", get_fn)
  b3:graphql("Query.viewer", gql_fn)
  b3:capability("repos", cap_repos)
  b3:webhook("push", push_fn)
  b3:set_allow_anonymous(false)
  b3:build()

  eq(app.backend.rest["get_repo"], get_fn, "builder:build: registers REST handler")
  eq(graphql_resolvers["Query.viewer"], gql_fn, "builder:build: registers GraphQL resolver") -- luacheck: globals graphql_resolvers
  eq(app.backend.capabilities["repos"], cap_repos, "builder:build: registers capability module")
  eq(app.backend.webhooks["push"], push_fn, "builder:build: registers webhook event handler")
  eq(app.allow_anonymous, false, "builder:build: sets allow_anonymous")

  -- build() without set_allow_anonymous leaves allow_anonymous unchanged
  app.backend.rest = {}
  app.backend.capabilities = {}
  app.allow_anonymous = true
  local b4 = make_backend_builder()
  b4:rest("get_root", function() end)
  b4:build()
  ok(
    app.allow_anonymous == true,
    "builder:build: does not change allow_anonymous when not declared"
  )

  -- build(strip) excludes REST keys matching any pattern but NOT capabilities or webhooks
  app.backend.rest = {}
  app.backend.capabilities = {}
  app.backend.webhooks = {}
  local cap_issues = { get = function() end }
  local push_fn2 = function() end
  local b5 = make_backend_builder()
  b5:rest("get_repo", function() end)
  b5:rest("get_package_info", function() end)
  b5:rest("list_actions_runs", function() end)
  b5:capability("issues", cap_issues)
  b5:webhook("push", push_fn2)
  b5:build({ "_package", "_actions_" })
  ok(app.backend.rest["get_repo"] ~= nil, "builder:build(strip): keeps non-matching key")
  ok(app.backend.rest["get_package_info"] == nil, "builder:build(strip): strips _package key")
  ok(app.backend.rest["list_actions_runs"] == nil, "builder:build(strip): strips _actions_ key")
  eq(
    app.backend.capabilities["issues"],
    cap_issues,
    "builder:build(strip): capabilities are not stripped"
  )
  eq(
    app.backend.webhooks["push"],
    push_fn2,
    "builder:build(strip): webhook handlers are not stripped"
  )

  -- two builders are independent and do not share state
  app.backend.rest = {}
  app.backend.capabilities = {}
  local ba = make_backend_builder()
  ba:rest("get_foo", function() end)
  ba:capability("repos", { get = function() end })
  local bb = make_backend_builder()
  bb:rest("get_bar", function() end)
  bb:capability("users", { get = function() end })
  ba:build()
  ok(app.backend.rest["get_foo"] ~= nil, "make_backend_builder: builders are independent (a built)")
  ok(
    app.backend.rest["get_bar"] == nil,
    "make_backend_builder: builders are independent (b not yet built)"
  )
  ok(
    app.backend.capabilities["repos"] ~= nil,
    "make_backend_builder: capability builders independent (a built)"
  )
  ok(
    app.backend.capabilities["users"] == nil,
    "make_backend_builder: capability builders independent (b not yet built)"
  )
  bb:build()
  ok(app.backend.rest["get_bar"] ~= nil, "make_backend_builder: builders are independent (b built)")
  ok(
    app.backend.capabilities["users"] ~= nil,
    "make_backend_builder: capability builders independent (b built)"
  )

  restore()
end

-- ============================================================
-- cap_err
-- ============================================================

do
  local e = cap_err(404, "not found")
  ok(type(e) == "table", "cap_err: returns a table")
  eq(e.status, 404, "cap_err: status field set")
  eq(e.message, "not found", "cap_err: message field set")

  local e0 = cap_err(0, "network error")
  eq(e0.status, 0, "cap_err: status 0 for network errors")
end

-- ============================================================
-- cap_fetch
-- ============================================================

do
  local function make_mock_fetch(ok_val, status_val, headers_val, body_val)
    return function(_url, _method, _body)
      return ok_val, status_val, headers_val, body_val
    end
  end

  -- success: 200 with valid JSON
  local fetch_ok = make_mock_fetch(true, 200, {}, '{"name":"hello"}')
  local data, err = cap_fetch(fetch_ok, "https://example.com/api/repo")
  ok(data ~= nil, "cap_fetch: success returns non-nil data")
  ok(err == nil, "cap_fetch: success returns nil err")
  eq(data.name, "hello", "cap_fetch: decoded JSON field")

  -- network error (ok=false)
  local fetch_net_err = make_mock_fetch(false, 0, nil, nil)
  local d2, e2 = cap_fetch(fetch_net_err, "https://example.com/api/repo")
  ok(d2 == nil, "cap_fetch: network error returns nil data")
  ok(e2 ~= nil, "cap_fetch: network error returns non-nil err")
  eq(e2.status, 0, "cap_fetch: network error status is 0")

  -- non-2xx status
  local fetch_404 = make_mock_fetch(true, 404, {}, '{"message":"Not Found"}')
  local d3, e3 = cap_fetch(fetch_404, "https://example.com/api/repo")
  ok(d3 == nil, "cap_fetch: 404 returns nil data")
  ok(e3 ~= nil, "cap_fetch: 404 returns non-nil err")
  eq(e3.status, 404, "cap_fetch: 404 err status is 404")

  -- invalid JSON body
  local fetch_bad_json = make_mock_fetch(true, 200, {}, "not json {{{")
  local d4, e4 = cap_fetch(fetch_bad_json, "https://example.com/api/repo")
  ok(d4 == nil, "cap_fetch: bad JSON returns nil data")
  ok(e4 ~= nil, "cap_fetch: bad JSON returns non-nil err")
  eq(e4.status, 200, "cap_fetch: bad JSON err status is the HTTP status")
end

-- ============================================================
-- cap_fetch_paged
-- ============================================================

do
  local function make_mock_fetch(ok_val, status_val, headers_val, body_val)
    return function(_url, _method, _body)
      return ok_val, status_val, headers_val, body_val
    end
  end

  -- success: returns (data, headers, nil)
  local fetch_ok =
    make_mock_fetch(true, 200, { Link = '<https://x.com?page=2>; rel="next"' }, "[1,2,3]")
  local data, hdrs, err = cap_fetch_paged(fetch_ok, "https://example.com/api/list")
  ok(data ~= nil, "cap_fetch_paged: success returns non-nil data")
  ok(hdrs ~= nil, "cap_fetch_paged: success returns non-nil headers")
  ok(err == nil, "cap_fetch_paged: success returns nil err")
  ok(hdrs["Link"] ~= nil, "cap_fetch_paged: Link header present")

  -- missing headers → empty table
  local fetch_no_hdrs = make_mock_fetch(true, 200, nil, "[]")
  local d2, h2, e2 = cap_fetch_paged(fetch_no_hdrs, "https://example.com/api/list")
  ok(d2 ~= nil, "cap_fetch_paged: no headers → data still returned")
  ok(type(h2) == "table", "cap_fetch_paged: no headers → empty table")
  ok(e2 == nil, "cap_fetch_paged: no headers → nil err")

  -- network error: returns (nil, nil, err)
  local fetch_net_err = make_mock_fetch(false, 0, nil, nil)
  local d3, h3, e3 = cap_fetch_paged(fetch_net_err, "https://example.com/api/list")
  ok(d3 == nil, "cap_fetch_paged: network error returns nil data")
  ok(h3 == nil, "cap_fetch_paged: network error returns nil headers")
  ok(e3 ~= nil, "cap_fetch_paged: network error returns non-nil err")
  eq(e3.status, 0, "cap_fetch_paged: network error err.status is 0")

  -- non-2xx: returns (nil, nil, err)
  local fetch_403 = make_mock_fetch(true, 403, {}, '{"message":"Forbidden"}')
  local d4, h4, e4 = cap_fetch_paged(fetch_403, "https://example.com/api/list")
  ok(d4 == nil, "cap_fetch_paged: 403 returns nil data")
  ok(h4 == nil, "cap_fetch_paged: 403 returns nil headers")
  eq(e4.status, 403, "cap_fetch_paged: 403 err.status is 403")
end

-- ============================================================
-- cap_rest_respond
-- ============================================================

do
  -- success with translate
  reset_response()
  cap_rest_respond({ id = 1, x = "a" }, nil, function(d)
    return { id = d.id }
  end)
  eq(_last_status, 200, "cap_rest_respond: success → 200")
  ok(_last_body:find('"id"') ~= nil, "cap_rest_respond: body contains translated field")
  ok(_last_body:find('"x"') == nil, "cap_rest_respond: translate removes unwanted field")

  -- success without translate
  reset_response()
  cap_rest_respond({ v = 42 }, nil, nil)
  eq(_last_status, 200, "cap_rest_respond: no translate → 200")

  -- network error → 503
  reset_response()
  cap_rest_respond(nil, cap_err(0, "connection refused"), nil)
  eq(_last_status, 503, "cap_rest_respond: network error → 503")

  -- upstream 404 → 404
  reset_response()
  cap_rest_respond(nil, cap_err(404, "not found"), nil)
  eq(_last_status, 404, "cap_rest_respond: upstream 404 → 404")

  -- upstream 403 → 403
  reset_response()
  cap_rest_respond(nil, cap_err(403, "forbidden"), nil)
  eq(_last_status, 403, "cap_rest_respond: upstream 403 → 403")
end

-- ============================================================
-- cap_rest_created
-- ============================================================

do
  -- success → 201
  reset_response()
  cap_rest_created({ id = 99 }, nil, nil)
  eq(_last_status, 201, "cap_rest_created: success → 201")

  -- network error → 503
  reset_response()
  cap_rest_created(nil, cap_err(0, "timeout"), nil)
  eq(_last_status, 503, "cap_rest_created: network error → 503")

  -- upstream 422 → 422
  reset_response()
  cap_rest_created(nil, cap_err(422, "unprocessable"), nil)
  eq(_last_status, 422, "cap_rest_created: upstream 422 → 422")
end

-- ============================================================
-- cap_rest_204
-- ============================================================

do
  -- ok → 204
  reset_response()
  cap_rest_204(true, nil)
  eq(_last_status, 204, "cap_rest_204: ok → 204")

  -- network error → 503
  reset_response()
  cap_rest_204(nil, cap_err(0, "connection reset"))
  eq(_last_status, 503, "cap_rest_204: network error → 503")

  -- upstream 404 → 404
  reset_response()
  cap_rest_204(nil, cap_err(404, "repo not found"))
  eq(_last_status, 404, "cap_rest_204: upstream 404 → 404")
end

-- ============================================================
-- cap_rest_paged
-- ============================================================

do
  local PAGES = { per_page = "limit", page = "page" }

  -- need a Host header for rewrite_link_header
  reset_request({ headers = { Host = "proxy.example.com" }, path = "/repos" })

  -- success with Link header → 200 + rewritten Link
  reset_response()
  local hdrs_with_link = { Link = '<https://gitea.com/api/v1/repos?limit=30&page=2>; rel="next"' }
  cap_rest_paged({ { id = 1 } }, hdrs_with_link, nil, PAGES, nil)
  eq(_last_status, 200, "cap_rest_paged: success → 200")
  ok(_last_headers["Link"] ~= nil, "cap_rest_paged: Link header rewritten")
  ok(
    _last_headers["Link"]:find("proxy.example.com") ~= nil,
    "cap_rest_paged: Link rewritten to proxy host"
  )

  -- success without Link header → 200, no Link
  reset_response()
  cap_rest_paged({ { id = 1 } }, {}, nil, PAGES, nil)
  eq(_last_status, 200, "cap_rest_paged: no upstream Link → 200")
  ok(_last_headers["Link"] == nil, "cap_rest_paged: no Link header when none upstream")

  -- success with translate
  reset_response()
  cap_rest_paged({ { raw = true } }, {}, nil, PAGES, function(items)
    return translate_list(function(i)
      return { translated = i.raw }
    end, items)
  end)
  eq(_last_status, 200, "cap_rest_paged: translate applied")

  -- network error → 503
  reset_response()
  cap_rest_paged(nil, nil, cap_err(0, "network down"), PAGES, nil)
  eq(_last_status, 503, "cap_rest_paged: network error → 503")

  -- upstream 401 → 401
  reset_response()
  cap_rest_paged(nil, nil, cap_err(401, "unauthorized"), PAGES, nil)
  eq(_last_status, 401, "cap_rest_paged: upstream 401 → 401")
end

-- ============================================================
-- make_webhook_receiver
-- ============================================================

ok(type(make_webhook_receiver) == "function", "make_webhook_receiver: exported as global function")
ok(type(app.webhook_receiver) == "function", "app.webhook_receiver: installed on app by .init.lua")

do
  -- Helper: call app.webhook_receiver() with stubbed HTTP context and return status.
  local function call_webhook(opts)
    reset_request(opts)
    reset_response()
    app.webhook_receiver()
    return _last_status
  end

  -- 404 for unknown backend
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/notabackend",
      headers = { ["Content-Type"] = "application/json" },
      body = "{}",
    }),
    404,
    "webhook_receiver: unknown backend → 404"
  )

  -- 404 for trailing path segment
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/gitea/extra",
      headers = { ["Content-Type"] = "application/json" },
      body = "{}",
    }),
    404,
    "webhook_receiver: extra path segment → 404"
  )

  -- 405 for non-POST method
  eq(
    call_webhook({
      method = "GET",
      path = "/webhooks/gitea",
      headers = { ["Content-Type"] = "application/json" },
      body = "{}",
    }),
    405,
    "webhook_receiver: non-POST → 405"
  )

  -- 400 for wrong Content-Type
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/gitea",
      headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
      body = "",
    }),
    400,
    "webhook_receiver: non-JSON Content-Type → 400"
  )

  -- 400 for missing Content-Type
  eq(
    call_webhook({ method = "POST", path = "/webhooks/gitea", headers = {}, body = "{}" }),
    400,
    "webhook_receiver: missing Content-Type → 400"
  )

  -- With no secret configured (trust-the-network) and no handlers, 422
  -- because no event-type header is set for gitea.
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/gitea",
      headers = { ["Content-Type"] = "application/json" },
      body = "{}",
    }),
    422,
    "webhook_receiver: no X-Gitea-Event header → 422 missing event"
  )

  -- 422 when event-type header present but no handler registered
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/gitea",
      headers = {
        ["Content-Type"] = "application/json",
        ["X-Gitea-Event"] = "push",
      },
      body = "{}",
    }),
    422,
    "webhook_receiver: known event header but no handler → 422"
  )

  -- 200 when handler is registered and succeeds
  local saved_webhooks = app.backend.webhooks
  app.backend.webhooks = {
    push = function(_payload)
      return { event = "push" }, nil
    end,
  }
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/gitea",
      headers = {
        ["Content-Type"] = "application/json",
        ["X-Gitea-Event"] = "push",
      },
      body = '{"ref":"refs/heads/main"}',
    }),
    200,
    "webhook_receiver: registered handler succeeds → 200"
  )

  -- 422 when handler returns nil (normalisation failed)
  app.backend.webhooks = {
    push = function(_payload)
      return nil, "bad payload"
    end,
  }
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/gitea",
      headers = {
        ["Content-Type"] = "application/json",
        ["X-Gitea-Event"] = "push",
      },
      body = '{"ref":"refs/heads/main"}',
    }),
    422,
    "webhook_receiver: handler returns nil → 422"
  )

  -- 401 when secret is configured and X-Gitea-Signature is absent.
  -- (GetCryptoHash stub returns aaa…; absent header → verify_signature returns false.)
  app.backend.webhooks = {}
  local saved_config = app.config
  app.config = { backend = "gitea", base_url = "", webhook_secrets = { gitea = "mysecret" } }
  eq(
    call_webhook({
      method = "POST",
      path = "/webhooks/gitea",
      headers = { ["Content-Type"] = "application/json" },
      body = "{}",
    }),
    401,
    "webhook_receiver: secret set but no signature header → 401"
  )
  app.config = saved_config

  app.backend.webhooks = saved_webhooks

  -- make_dispatcher routes /webhooks/* to the receiver, bypassing auth.
  -- Simulate allow_anonymous=false with no Authorization header: a REST path
  -- gets 401, but a webhook path is handled by webhook_receiver (not blocked).
  local saved_anon = app.allow_anonymous
  app.allow_anonymous = false
  -- REST path with no auth → 401
  reset_request({ method = "GET", path = "/repos/alice/myrepo", headers = {}, body = nil })
  reset_response()
  OnHttpRequest()
  eq(_last_status, 401, "dispatcher: REST path with no auth and allow_anonymous=false → 401")

  -- Webhook path with no auth header → reaches webhook_receiver (not blocked by auth gate).
  -- It gets 422 because no event-type header is set, which proves auth was bypassed.
  reset_request({
    method = "POST",
    path = "/webhooks/gitea",
    headers = { ["Content-Type"] = "application/json" },
    body = "{}",
  })
  reset_response()
  OnHttpRequest()
  eq(_last_status, 422, "dispatcher: /webhooks/* bypasses auth gate (allow_anonymous=false)")

  app.allow_anonymous = saved_anon
end

-- ============================================================
-- verify_signature: comprehensive per-backend tests
--
-- Covers all 24 backends in KNOWN_BACKENDS.  For each:
--   (a) trust-the-network (no secret configured) → not 401
--   (b) valid credential/signature → not 401
--   (c) bad credential/signature → 401
--   (d) missing header/token → 401
-- Pagure gets extra cases for its dual-header scheme.
-- Kallithea gets extra cases for its body-embedded secret.
-- codecommit/sourcehut/launchpad get both trust-the-network
-- and "secret configured → always 401" cases.
-- ============================================================
do
  -- GetCryptoHash stub always returns 32 bytes of 0xaa.
  -- to_hex() converts that to 64 lowercase 'a' characters.
  local STUB_HEX = string.rep("aa", 32)
  local SECRET = "mysecret"

  -- Call the webhook receiver for `backend` with the given extra headers and
  -- body.  `secrets` controls app.config.webhook_secrets.
  local function call_sig(backend, extra_headers, body, secrets)
    local saved_config = app.config
    app.config = {
      backend = "testbackend",
      base_url = "",
      webhook_secrets = secrets or {},
    }
    local h = { ["Content-Type"] = "application/json" }
    for k, v in pairs(extra_headers or {}) do
      h[k] = v
    end
    reset_request({
      method = "POST",
      path = "/webhooks/" .. backend,
      headers = h,
      body = body or "{}",
    })
    reset_response()
    app.webhook_receiver()
    local status = _last_status
    app.config = saved_config
    return status
  end

  -- Convenience wrappers
  local function no_secret(backend, hdrs, body)
    return call_sig(backend, hdrs, body, {})
  end
  local function with_secret(backend, hdrs, body)
    return call_sig(backend, hdrs, body, { [backend] = SECRET })
  end

  -- ── HMAC-SHA256 / no prefix: gitea family (X-Gitea-Signature)
  for _, be in ipairs({ "gitea", "forgejo", "codeberg", "notabug" }) do
    ok(no_secret(be, {}) ~= 401, "verify_signature " .. be .. ": no secret → not 401")
    ok(
      with_secret(be, { ["X-Gitea-Signature"] = STUB_HEX }) ~= 401,
      "verify_signature " .. be .. ": valid X-Gitea-Signature → not 401"
    )
    eq(
      with_secret(be, { ["X-Gitea-Signature"] = "deadbeef" }),
      401,
      "verify_signature " .. be .. ": bad X-Gitea-Signature → 401"
    )
    eq(with_secret(be, {}), 401, "verify_signature " .. be .. ": missing X-Gitea-Signature → 401")
  end

  -- ── HMAC-SHA256 / no prefix: gogs (X-Gogs-Signature)
  ok(no_secret("gogs", {}) ~= 401, "verify_signature gogs: no secret → not 401")
  ok(
    with_secret("gogs", { ["X-Gogs-Signature"] = STUB_HEX }) ~= 401,
    "verify_signature gogs: valid X-Gogs-Signature → not 401"
  )
  eq(
    with_secret("gogs", { ["X-Gogs-Signature"] = "deadbeef" }),
    401,
    "verify_signature gogs: bad X-Gogs-Signature → 401"
  )
  eq(with_secret("gogs", {}), 401, "verify_signature gogs: missing X-Gogs-Signature → 401")

  -- ── Verbatim shared token: gitlab (X-Gitlab-Token)
  ok(no_secret("gitlab", {}) ~= 401, "verify_signature gitlab: no secret → not 401")
  ok(
    with_secret("gitlab", { ["X-Gitlab-Token"] = SECRET }) ~= 401,
    "verify_signature gitlab: valid X-Gitlab-Token → not 401"
  )
  eq(
    with_secret("gitlab", { ["X-Gitlab-Token"] = "wrongtoken" }),
    401,
    "verify_signature gitlab: bad X-Gitlab-Token → 401"
  )
  eq(with_secret("gitlab", {}), 401, "verify_signature gitlab: missing X-Gitlab-Token → 401")

  -- ── HMAC-SHA256 / sha256= prefix: bitbucket + bitbucket_datacenter (X-Hub-Signature)
  for _, be in ipairs({ "bitbucket", "bitbucket_datacenter" }) do
    ok(no_secret(be, {}) ~= 401, "verify_signature " .. be .. ": no secret → not 401")
    ok(
      with_secret(be, { ["X-Hub-Signature"] = "sha256=" .. STUB_HEX }) ~= 401,
      "verify_signature " .. be .. ": valid X-Hub-Signature sha256= → not 401"
    )
    eq(
      with_secret(be, { ["X-Hub-Signature"] = "sha256=deadbeef" }),
      401,
      "verify_signature " .. be .. ": bad X-Hub-Signature → 401"
    )
    eq(with_secret(be, {}), 401, "verify_signature " .. be .. ": missing X-Hub-Signature → 401")
  end

  -- ── HMAC-SHA1 / sha1= prefix: gitbucket (X-Hub-Signature)
  ok(no_secret("gitbucket", {}) ~= 401, "verify_signature gitbucket: no secret → not 401")
  ok(
    with_secret("gitbucket", { ["X-Hub-Signature"] = "sha1=" .. STUB_HEX }) ~= 401,
    "verify_signature gitbucket: valid X-Hub-Signature sha1= → not 401"
  )
  eq(
    with_secret("gitbucket", { ["X-Hub-Signature"] = "sha1=deadbeef" }),
    401,
    "verify_signature gitbucket: bad X-Hub-Signature → 401"
  )
  eq(
    with_secret("gitbucket", {}),
    401,
    "verify_signature gitbucket: missing X-Hub-Signature → 401"
  )

  -- ── HMAC-SHA256 / no prefix: phabricator (X-Phabricator-Webhook-Signature)
  ok(no_secret("phabricator", {}) ~= 401, "verify_signature phabricator: no secret → not 401")
  ok(
    with_secret("phabricator", { ["X-Phabricator-Webhook-Signature"] = STUB_HEX }) ~= 401,
    "verify_signature phabricator: valid X-Phabricator-Webhook-Signature → not 401"
  )
  eq(
    with_secret("phabricator", { ["X-Phabricator-Webhook-Signature"] = "deadbeef" }),
    401,
    "verify_signature phabricator: bad X-Phabricator-Webhook-Signature → 401"
  )
  eq(
    with_secret("phabricator", {}),
    401,
    "verify_signature phabricator: missing X-Phabricator-Webhook-Signature → 401"
  )

  -- ── Pagure: dual-header scheme (X-Pagure-Signature-256 / X-Pagure-Signature)
  -- Prefers SHA-256; falls back to SHA-512; both must verify when both present.
  ok(no_secret("pagure", {}) ~= 401, "verify_signature pagure: no secret → not 401")
  ok(
    with_secret("pagure", { ["X-Pagure-Signature-256"] = STUB_HEX }) ~= 401,
    "verify_signature pagure: valid sig256 only → not 401"
  )
  ok(
    with_secret("pagure", { ["X-Pagure-Signature"] = STUB_HEX }) ~= 401,
    "verify_signature pagure: valid sig512 only → not 401"
  )
  ok(with_secret("pagure", {
    ["X-Pagure-Signature-256"] = STUB_HEX,
    ["X-Pagure-Signature"] = STUB_HEX,
  }) ~= 401, "verify_signature pagure: both sig256+sig512 valid → not 401")
  eq(
    with_secret("pagure", { ["X-Pagure-Signature-256"] = "bad" }),
    401,
    "verify_signature pagure: bad sig256 → 401"
  )
  eq(
    with_secret("pagure", { ["X-Pagure-Signature"] = "bad" }),
    401,
    "verify_signature pagure: bad sig512 → 401"
  )
  eq(
    with_secret("pagure", {
      ["X-Pagure-Signature-256"] = STUB_HEX,
      ["X-Pagure-Signature"] = "bad",
    }),
    401,
    "verify_signature pagure: sig256 valid but sig512 bad → 401"
  )
  eq(with_secret("pagure", {}), 401, "verify_signature pagure: no signature headers → 401")

  -- ── Verbatim shared token: harness (X-Harness-Token)
  ok(no_secret("harness", {}) ~= 401, "verify_signature harness: no secret → not 401")
  ok(
    with_secret("harness", { ["X-Harness-Token"] = SECRET }) ~= 401,
    "verify_signature harness: valid X-Harness-Token → not 401"
  )
  eq(
    with_secret("harness", { ["X-Harness-Token"] = "bad" }),
    401,
    "verify_signature harness: bad X-Harness-Token → 401"
  )
  eq(with_secret("harness", {}), 401, "verify_signature harness: missing X-Harness-Token → 401")

  -- ── Bearer token: onedev (Authorization: Bearer <secret>)
  ok(no_secret("onedev", {}) ~= 401, "verify_signature onedev: no secret → not 401")
  ok(
    with_secret("onedev", { ["Authorization"] = "Bearer " .. SECRET }) ~= 401,
    "verify_signature onedev: valid Bearer token → not 401"
  )
  ok(
    with_secret("onedev", { ["Authorization"] = "bearer " .. SECRET }) ~= 401,
    "verify_signature onedev: Bearer scheme is case-insensitive → not 401"
  )
  eq(
    with_secret("onedev", { ["Authorization"] = "Bearer badtoken" }),
    401,
    "verify_signature onedev: bad Bearer token → 401"
  )
  eq(
    with_secret("onedev", { ["Authorization"] = "Basic " .. SECRET }),
    401,
    "verify_signature onedev: non-Bearer scheme → 401"
  )
  eq(with_secret("onedev", {}), 401, "verify_signature onedev: missing Authorization → 401")

  -- ── Verbatim Authorization header: radicle (raw token, no prefix)
  ok(no_secret("radicle", {}) ~= 401, "verify_signature radicle: no secret → not 401")
  ok(
    with_secret("radicle", { ["Authorization"] = SECRET }) ~= 401,
    "verify_signature radicle: valid Authorization → not 401"
  )
  eq(
    with_secret("radicle", { ["Authorization"] = "bad" }),
    401,
    "verify_signature radicle: bad Authorization → 401"
  )
  eq(with_secret("radicle", {}), 401, "verify_signature radicle: missing Authorization → 401")

  -- ── Verbatim Authorization header: gerrit (same scheme as radicle)
  ok(no_secret("gerrit", {}) ~= 401, "verify_signature gerrit: no secret → not 401")
  ok(
    with_secret("gerrit", { ["Authorization"] = SECRET }) ~= 401,
    "verify_signature gerrit: valid Authorization → not 401"
  )
  eq(
    with_secret("gerrit", { ["Authorization"] = "bad" }),
    401,
    "verify_signature gerrit: bad Authorization → 401"
  )
  eq(with_secret("gerrit", {}), 401, "verify_signature gerrit: missing Authorization → 401")

  -- ── Verbatim shared token: gitblit (X-Gitblit-Token)
  ok(no_secret("gitblit", {}) ~= 401, "verify_signature gitblit: no secret → not 401")
  ok(
    with_secret("gitblit", { ["X-Gitblit-Token"] = SECRET }) ~= 401,
    "verify_signature gitblit: valid X-Gitblit-Token → not 401"
  )
  eq(
    with_secret("gitblit", { ["X-Gitblit-Token"] = "bad" }),
    401,
    "verify_signature gitblit: bad X-Gitblit-Token → 401"
  )
  eq(with_secret("gitblit", {}), 401, "verify_signature gitblit: missing X-Gitblit-Token → 401")

  -- ── Verbatim shared token: rhodecode (X-RhodeCode-Signature)
  ok(no_secret("rhodecode", {}) ~= 401, "verify_signature rhodecode: no secret → not 401")
  ok(
    with_secret("rhodecode", { ["X-RhodeCode-Signature"] = SECRET }) ~= 401,
    "verify_signature rhodecode: valid X-RhodeCode-Signature → not 401"
  )
  eq(
    with_secret("rhodecode", { ["X-RhodeCode-Signature"] = "bad" }),
    401,
    "verify_signature rhodecode: bad X-RhodeCode-Signature → 401"
  )
  eq(
    with_secret("rhodecode", {}),
    401,
    "verify_signature rhodecode: missing X-RhodeCode-Signature → 401"
  )

  -- ── Verbatim shared token: sourceforge (X-Sourceforge-Webhook-Secret)
  ok(no_secret("sourceforge", {}) ~= 401, "verify_signature sourceforge: no secret → not 401")
  ok(
    with_secret("sourceforge", { ["X-Sourceforge-Webhook-Secret"] = SECRET }) ~= 401,
    "verify_signature sourceforge: valid X-Sourceforge-Webhook-Secret → not 401"
  )
  eq(
    with_secret("sourceforge", { ["X-Sourceforge-Webhook-Secret"] = "bad" }),
    401,
    "verify_signature sourceforge: bad X-Sourceforge-Webhook-Secret → 401"
  )
  eq(
    with_secret("sourceforge", {}),
    401,
    "verify_signature sourceforge: missing X-Sourceforge-Webhook-Secret → 401"
  )

  -- ── Verbatim shared token: tuleap (X-Tuleap-Webhook-Secret)
  ok(no_secret("tuleap", {}) ~= 401, "verify_signature tuleap: no secret → not 401")
  ok(
    with_secret("tuleap", { ["X-Tuleap-Webhook-Secret"] = SECRET }) ~= 401,
    "verify_signature tuleap: valid X-Tuleap-Webhook-Secret → not 401"
  )
  eq(
    with_secret("tuleap", { ["X-Tuleap-Webhook-Secret"] = "bad" }),
    401,
    "verify_signature tuleap: bad X-Tuleap-Webhook-Secret → 401"
  )
  eq(
    with_secret("tuleap", {}),
    401,
    "verify_signature tuleap: missing X-Tuleap-Webhook-Secret → 401"
  )

  -- ── Azure DevOps: Authorization: Basic <creds> (DecodeBase64 is identity stub)
  -- SECRET = "mysecret"; DecodeBase64("mysecret") = "mysecret" (identity), so
  -- "Basic mysecret" is the valid credential when secret = "mysecret".
  ok(no_secret("azuredevops", {}) ~= 401, "verify_signature azuredevops: no secret → not 401")
  ok(
    with_secret("azuredevops", { ["Authorization"] = "Basic " .. SECRET }) ~= 401,
    "verify_signature azuredevops: valid Basic creds → not 401"
  )
  ok(
    with_secret("azuredevops", { ["Authorization"] = "basic " .. SECRET }) ~= 401,
    "verify_signature azuredevops: Basic scheme is case-insensitive → not 401"
  )
  eq(
    with_secret("azuredevops", { ["Authorization"] = "Basic badcreds" }),
    401,
    "verify_signature azuredevops: bad Basic creds → 401"
  )
  eq(
    with_secret("azuredevops", { ["Authorization"] = "Bearer " .. SECRET }),
    401,
    "verify_signature azuredevops: non-Basic scheme → 401"
  )
  eq(
    with_secret("azuredevops", {}),
    401,
    "verify_signature azuredevops: missing Authorization → 401"
  )

  -- ── Kallithea: body-embedded secret (exception to verify-before-parse rule)
  ok(no_secret("kallithea", {}) ~= 401, "verify_signature kallithea: no secret → not 401")
  ok(
    with_secret("kallithea", {}, '{"secret":"' .. SECRET .. '"}') ~= 401,
    "verify_signature kallithea: secret in root JSON field → not 401"
  )
  ok(
    with_secret("kallithea", {}, '{"data":{"secret":"' .. SECRET .. '"}}') ~= 401,
    "verify_signature kallithea: secret in data.secret JSON field → not 401"
  )
  eq(
    with_secret("kallithea", {}, '{"secret":"bad"}'),
    401,
    "verify_signature kallithea: bad body secret → 401"
  )
  eq(
    with_secret("kallithea", {}, '{"event":"push"}'),
    401,
    "verify_signature kallithea: no secret field in body → 401"
  )
  eq(
    with_secret("kallithea", {}, "not-valid-json"),
    401,
    "verify_signature kallithea: invalid JSON body → 401"
  )

  -- ── Trust-the-network-only backends: codecommit, sourcehut, launchpad
  -- These use asymmetric/platform-managed schemes not yet implemented.
  -- No secret → accepted; any secret configured → always rejected.
  for _, be in ipairs({ "codecommit", "sourcehut", "launchpad" }) do
    ok(
      no_secret(be, {}) ~= 401,
      "verify_signature " .. be .. ": no secret (trust-the-network) → not 401"
    )
    eq(
      call_sig(be, {}, nil, { [be] = SECRET }),
      401,
      "verify_signature " .. be .. ": secret configured (unimplemented scheme) → 401"
    )
  end

  -- ── Confusio-normalized: X-Confusio-Signature-256, HMAC-SHA256 + timestamp
  -- Header format: "sha256=<hex>, v=1, ts=<unix>"
  -- HMAC basestring: "v1:<ts>:<body>"  Replay window: 300 seconds.
  ok(no_secret("confusio", {}) ~= 401, "verify_signature confusio: no secret → not 401")

  -- Valid: current timestamp, correct stub HMAC hex.
  -- Using os.time() so the timestamp is within the replay window when the test runs.
  local confusio_now = os.time()
  local confusio_valid_hdr = "sha256=" .. STUB_HEX .. ", v=1, ts=" .. tostring(confusio_now)
  ok(
    with_secret("confusio", { ["X-Confusio-Signature-256"] = confusio_valid_hdr }) ~= 401,
    "verify_signature confusio: valid X-Confusio-Signature-256 (current ts) → not 401"
  )

  -- Stale past timestamp (January 2001): outside replay window.
  local confusio_stale_past = "sha256=" .. STUB_HEX .. ", v=1, ts=980000000"
  eq(
    with_secret("confusio", { ["X-Confusio-Signature-256"] = confusio_stale_past }),
    401,
    "verify_signature confusio: stale past timestamp → 401 (replay rejected)"
  )

  -- Stale future timestamp (year 5138): outside replay window.
  local confusio_stale_future = "sha256=" .. STUB_HEX .. ", v=1, ts=99999999999"
  eq(
    with_secret("confusio", { ["X-Confusio-Signature-256"] = confusio_stale_future }),
    401,
    "verify_signature confusio: stale future timestamp → 401 (replay rejected)"
  )

  -- Bad HMAC (current timestamp but wrong hex): rejected even with fresh ts.
  local confusio_bad_hmac = "sha256=deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
    .. ", v=1, ts="
    .. tostring(confusio_now)
  eq(
    with_secret("confusio", { ["X-Confusio-Signature-256"] = confusio_bad_hmac }),
    401,
    "verify_signature confusio: bad HMAC hex → 401"
  )

  -- Missing header.
  eq(with_secret("confusio", {}), 401, "verify_signature confusio: missing header → 401")

  -- Malformed header: missing v=1.
  local confusio_no_v = "sha256=" .. STUB_HEX .. ", ts=" .. tostring(confusio_now)
  eq(
    with_secret("confusio", { ["X-Confusio-Signature-256"] = confusio_no_v }),
    401,
    "verify_signature confusio: header missing v=1 → 401"
  )

  -- Malformed header: missing ts.
  local confusio_no_ts = "sha256=" .. STUB_HEX .. ", v=1"
  eq(
    with_secret("confusio", { ["X-Confusio-Signature-256"] = confusio_no_ts }),
    401,
    "verify_signature confusio: header missing ts → 401"
  )
end

-- ============================================================
-- sign_github / sign_confusio
-- ============================================================

do
  -- GetCryptoHash stub returns 32 bytes of 0xaa → hex is 64 'a' chars.
  local STUB_HEX = string.rep("aa", 32)
  local SECRET = "mysecret"
  local BODY = '{"action":"opened"}'

  -- ── sign_github ──────────────────────────────────────────

  ok(type(sign_github) == "function", "sign_github: exported as global function")

  -- No secret → both return values are nil.
  local s256, s1 = sign_github(nil, BODY)
  ok(s256 == nil, "sign_github(nil): sha256 value is nil")
  ok(s1 == nil, "sign_github(nil): sha1 value is nil")

  s256, s1 = sign_github("", BODY)
  ok(s256 == nil, "sign_github(''): sha256 value is nil")
  ok(s1 == nil, "sign_github(''): sha1 value is nil")

  -- With secret → returns "sha256=<hex>" and "sha1=<hex>".
  s256, s1 = sign_github(SECRET, BODY)
  eq(s256, "sha256=" .. STUB_HEX, "sign_github: sha256 value has correct prefix and hex")
  eq(s1, "sha1=" .. STUB_HEX, "sign_github: sha1 value has correct prefix and hex")

  -- Return values are strings (header-value ready).
  ok(type(s256) == "string", "sign_github: sha256 return is a string")
  ok(type(s1) == "string", "sign_github: sha1 return is a string")

  -- ── sign_confusio ─────────────────────────────────────────

  ok(type(sign_confusio) == "function", "sign_confusio: exported as global function")

  -- No secret → returns nil.
  ok(sign_confusio(nil, BODY, 1700000000) == nil, "sign_confusio(nil): returns nil")
  ok(sign_confusio("", BODY, 1700000000) == nil, "sign_confusio(''): returns nil")

  -- With secret → returns "sha256=<hex>, v=1, ts=<ts>".
  local TS = 1700000000
  local csig = sign_confusio(SECRET, BODY, TS)
  ok(type(csig) == "string", "sign_confusio: return is a string")
  eq(csig, "sha256=" .. STUB_HEX .. ", v=1, ts=1700000000", "sign_confusio: header value format")

  -- Timestamp appears verbatim in the returned header value.
  local ts_val = csig:match(", ts=(%d+)$")
  eq(tonumber(ts_val), TS, "sign_confusio: ts field matches supplied timestamp")

  -- Different timestamps produce different basestrings (stub ignores input, but
  -- verify the ts field in the header value changes as expected).
  local r1 = sign_confusio(SECRET, BODY, 1000)
  local r2 = sign_confusio(SECRET, BODY, 9999)
  ok(r1:match(", ts=1000$") ~= nil, "sign_confusio: ts=1000 appears in header")
  ok(r2:match(", ts=9999$") ~= nil, "sign_confusio: ts=9999 appears in header")

  -- v=1 is present in the header value.
  ok(csig:find(", v=1,", 1, true) ~= nil, "sign_confusio: v=1 field present in header value")
end

-- ============================================================
-- make_internal_event
-- ============================================================

ok(type(make_internal_event) == "function", "make_internal_event: exported as global function")

do
  -- All required fields present → table with correct keys.
  local ev = make_internal_event({
    event = "issues",
    action = "opened",
    provider = "gitea",
    raw = { action = "opened" },
    data = { issue = { id = 1 } },
  })
  eq(ev.event, "issues", "make_internal_event: event field")
  eq(ev.action, "opened", "make_internal_event: action field")
  eq(ev.provider, "gitea", "make_internal_event: provider field")
  eq(type(ev.raw), "table", "make_internal_event: raw is a table")
  eq(type(ev.data), "table", "make_internal_event: data is a table")
  eq(ev.timestamp, "", "make_internal_event: timestamp defaults to empty string")
  ok(ev.raw_action == nil, "make_internal_event: raw_action absent for known action")

  -- With explicit timestamp → preserved.
  local ev2 = make_internal_event({
    event = "push",
    action = "",
    provider = "gitlab",
    timestamp = "2024-01-15T10:00:00Z",
    raw = {},
    data = {},
  })
  eq(ev2.timestamp, "2024-01-15T10:00:00Z", "make_internal_event: explicit timestamp preserved")

  -- Unknown action → action == "unknown" and raw_action set.
  local ev3 = make_internal_event({
    event = "issues",
    action = "unknown",
    raw_action = "some_new_action",
    provider = "gitea",
    raw = { action = "some_new_action" },
    data = {},
  })
  eq(ev3.action, "unknown", "make_internal_event: action == 'unknown' preserved")
  eq(ev3.raw_action, "some_new_action", "make_internal_event: raw_action preserved")

  -- Missing optional fields default gracefully.
  local ev4 = make_internal_event({ event = "label", action = "created", provider = "gitea" })
  eq(ev4.timestamp, "", "make_internal_event: missing timestamp defaults to ''")
  eq(type(ev4.raw), "table", "make_internal_event: missing raw defaults to {}")
  eq(type(ev4.data), "table", "make_internal_event: missing data defaults to {}")
end

-- ============================================================
-- webhook_receiver: unknown-action sidecar header
-- ============================================================

do
  local function call_webhook_full(opts)
    reset_request(opts)
    reset_response()
    app.webhook_receiver()
    return _last_status, _last_headers
  end

  local saved_webhooks = app.backend.webhooks

  -- Known action: no X-Confusio-Raw-Action header on 200.
  app.backend.webhooks = {
    issues = function(payload)
      return make_internal_event({
        event = "issues",
        action = "opened",
        provider = "gitea",
        raw = payload,
        data = {},
      })
    end,
  }
  local status1, hdrs1 = call_webhook_full({
    method = "POST",
    path = "/webhooks/gitea",
    headers = { ["Content-Type"] = "application/json", ["X-Gitea-Event"] = "issues" },
    body = '{"action":"opened"}',
  })
  eq(status1, 200, "webhook_receiver: known action → 200")
  ok(
    hdrs1["X-Confusio-Raw-Action"] == nil,
    "webhook_receiver: known action → no X-Confusio-Raw-Action"
  )

  -- Unknown action: X-Confusio-Raw-Action set with raw action string.
  app.backend.webhooks = {
    issues = function(payload)
      return make_internal_event({
        event = "issues",
        action = "unknown",
        raw_action = payload.action,
        provider = "gitea",
        raw = payload,
        data = {},
      })
    end,
  }
  local status2, hdrs2 = call_webhook_full({
    method = "POST",
    path = "/webhooks/gitea",
    headers = { ["Content-Type"] = "application/json", ["X-Gitea-Event"] = "issues" },
    body = '{"action":"pinned"}',
  })
  eq(status2, 200, "webhook_receiver: unknown action → still 200")
  eq(
    hdrs2["X-Confusio-Raw-Action"],
    "pinned",
    "webhook_receiver: unknown action → X-Confusio-Raw-Action set"
  )

  -- Unknown action but raw_action not set: no header emitted.
  app.backend.webhooks = {
    issues = function(payload)
      return make_internal_event({
        event = "issues",
        action = "unknown",
        provider = "gitea",
        raw = payload,
        data = {},
      })
    end,
  }
  local status3, hdrs3 = call_webhook_full({
    method = "POST",
    path = "/webhooks/gitea",
    headers = { ["Content-Type"] = "application/json", ["X-Gitea-Event"] = "issues" },
    body = '{"action":"pinned"}',
  })
  eq(status3, 200, "webhook_receiver: unknown action without raw_action → 200")
  ok(
    hdrs3["X-Confusio-Raw-Action"] == nil,
    "webhook_receiver: action=unknown, no raw_action → no header"
  )

  app.backend.webhooks = saved_webhooks
end

-- ============================================================
-- make_uuid / iso8601 / now_iso8601 (internal/util.lua)
-- ============================================================

-- make_uuid: format validation with the deterministic GetRandomBytes stub.
-- Stub returns bytes [17, 34, 51, 68, 85, 102, 119, 136, 153, 170, 187, 204, 221, 238, 255, 16].
-- byte 7 (119 = 0x77) → (0x77 & 0x0f) | 0x40 = 0x47
-- byte 9 (153 = 0x99) → (0x99 & 0x3f) | 0x80 = 0x99
-- Expected UUID: "11223344-5566-4788-99aa-bbccddeeff10"
local uuid1 = make_uuid() -- luacheck: globals make_uuid
eq(#uuid1, 36, "make_uuid: length is 36")
eq(uuid1:sub(9, 9), "-", "make_uuid: dash at position 9")
eq(uuid1:sub(14, 14), "-", "make_uuid: dash at position 14")
eq(uuid1:sub(19, 19), "-", "make_uuid: dash at position 19")
eq(uuid1:sub(24, 24), "-", "make_uuid: dash at position 24")
eq(uuid1:sub(15, 15), "4", "make_uuid: version nibble is 4")
ok(
  uuid1:sub(20, 20):match("[89ab]") ~= nil,
  "make_uuid: variant nibble is 8, 9, a, or b (got " .. uuid1:sub(20, 20) .. ")"
)
ok(
  uuid1:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil,
  "make_uuid: matches xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx pattern"
)
eq(uuid1, "11223344-5566-4788-99aa-bbccddeeff10", "make_uuid: deterministic from stub")

-- make_uuid: two successive calls return the same value when the stub is deterministic.
local uuid2 = make_uuid()
eq(uuid1, uuid2, "make_uuid: stub is deterministic — same bytes → same UUID")

-- iso8601: known epoch values.
local ts0 = iso8601(0) -- luacheck: globals iso8601
eq(ts0, "1970-01-01T00:00:00Z", "iso8601(0): Unix epoch")
local ts1 = iso8601(1000000000)
eq(ts1, "2001-09-09T01:46:40Z", "iso8601(1000000000): known timestamp")
local ts2 = iso8601(1714003200)
eq(ts2, "2024-04-25T00:00:00Z", "iso8601(1714003200): 2024-04-25T00:00:00Z")

-- iso8601: format shape — 20 characters, ends with Z.
eq(#ts0, 20, "iso8601: length is 20")
eq(ts0:sub(20, 20), "Z", "iso8601: ends with Z")
eq(ts0:sub(5, 5), "-", "iso8601: first dash after year")
eq(ts0:sub(8, 8), "-", "iso8601: second dash after month")
eq(ts0:sub(11, 11), "T", "iso8601: T separator")
eq(ts0:sub(14, 14), ":", "iso8601: first colon")
eq(ts0:sub(17, 17), ":", "iso8601: second colon")

-- now_iso8601: returns a 20-character ISO 8601 string matching the current minute.
local now_str = now_iso8601() -- luacheck: globals now_iso8601
eq(#now_str, 20, "now_iso8601: length is 20")
ok(
  now_str:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$") ~= nil,
  "now_iso8601: matches yyyy-mm-ddThh:mm:ssZ pattern"
)
-- Verify it's within 5 seconds of os.time().
local expected_prefix = iso8601(os.time()):sub(1, 16)
eq(now_str:sub(1, 16), expected_prefix, "now_iso8601: within same minute as os.time()")

-- ============================================================
-- outbox_store_event / outbox_get_event / outbox_create_delivery /
-- outbox_get_delivery / outbox_list_deliveries_for_event /
-- outbox_list_deliveries_for_target / outbox_update_delivery /
-- outbox_pending_retries / outbox_prune (internal/outbox.lua)
-- ============================================================

-- luacheck: globals outbox_store_event outbox_get_event outbox_create_delivery
-- luacheck: globals outbox_get_delivery outbox_list_deliveries_for_event
-- luacheck: globals outbox_list_deliveries_for_target outbox_update_delivery
-- luacheck: globals outbox_pending_retries outbox_prune

-- Note: the GetRandomBytes stub is deterministic, so make_uuid() always returns the
-- same UUID.  All tests operate on a single event/delivery at a time.  We use
-- outbox_get_event / outbox_get_delivery to retrieve the canonical record after
-- each create, and exercise update/prune sequentially in lifecycle order.

-- outbox_store_event: stores an event and returns a record.
local ob_ev = outbox_store_event("gitea", "push", { ref = "refs/heads/main" })
ok(ob_ev ~= nil, "outbox_store_event: returns non-nil")
ok(ob_ev.event_id ~= nil, "outbox_store_event: event_id is set")
eq(#ob_ev.event_id, 36, "outbox_store_event: event_id is 36 chars (UUID)")
eq(ob_ev.backend, "gitea", "outbox_store_event: backend stored")
eq(ob_ev.event_type, "push", "outbox_store_event: event_type stored")
eq(ob_ev.payload.ref, "refs/heads/main", "outbox_store_event: payload stored")
ok(ob_ev.received_at ~= nil, "outbox_store_event: received_at is set")
eq(#ob_ev.received_at, 20, "outbox_store_event: received_at is 20-char ISO 8601")

local ob_ev_id = ob_ev.event_id

-- outbox_get_event: retrieves stored event by id.
local ob_got_ev = outbox_get_event(ob_ev_id)
ok(ob_got_ev ~= nil, "outbox_get_event: found stored event")
eq(ob_got_ev.event_id, ob_ev_id, "outbox_get_event: event_id matches")
eq(ob_got_ev.event_type, "push", "outbox_get_event: event_type matches")

-- outbox_get_event: returns nil for unknown id.
ok(
  outbox_get_event("00000000-0000-4000-8000-000000000000") == nil,
  "outbox_get_event: nil for unknown id"
)

-- outbox_create_delivery: creates a delivery record for (event, target).
local ob_tgt_id = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
local ob_del = outbox_create_delivery(ob_ev_id, ob_tgt_id)
ok(ob_del ~= nil, "outbox_create_delivery: returns non-nil")
ok(ob_del.delivery_id ~= nil, "outbox_create_delivery: delivery_id is set")
eq(#ob_del.delivery_id, 36, "outbox_create_delivery: delivery_id is UUID")
eq(ob_del.event_id, ob_ev_id, "outbox_create_delivery: event_id stored")
eq(ob_del.target_id, ob_tgt_id, "outbox_create_delivery: target_id stored")
eq(ob_del.status, "pending", "outbox_create_delivery: initial status is pending")
eq(ob_del.attempt_count, 0, "outbox_create_delivery: attempt_count starts at 0")
ok(ob_del.next_attempt_at == nil, "outbox_create_delivery: next_attempt_at starts nil")
ok(ob_del.last_http_status == nil, "outbox_create_delivery: last_http_status starts nil")
ok(ob_del.last_error == nil, "outbox_create_delivery: last_error starts nil")
ok(ob_del.created_at ~= nil, "outbox_create_delivery: created_at is set")
ok(ob_del.updated_at ~= nil, "outbox_create_delivery: updated_at is set")

local ob_del_id = ob_del.delivery_id

-- outbox_get_delivery: retrieves a delivery by id.
local ob_got_del = outbox_get_delivery(ob_del_id)
ok(ob_got_del ~= nil, "outbox_get_delivery: found stored delivery")
eq(ob_got_del.delivery_id, ob_del_id, "outbox_get_delivery: delivery_id matches")

-- outbox_get_delivery: returns nil for unknown id.
ok(
  outbox_get_delivery("00000000-0000-4000-8000-000000000000") == nil,
  "outbox_get_delivery: nil for unknown id"
)

-- outbox_list_deliveries_for_event: returns deliveries for the event.
local ob_evdels = outbox_list_deliveries_for_event(ob_ev_id)
ok(#ob_evdels >= 1, "outbox_list_deliveries_for_event: at least 1 delivery for event")
eq(ob_evdels[1].event_id, ob_ev_id, "outbox_list_deliveries_for_event: delivery event_id matches")

-- outbox_list_deliveries_for_event: empty for unknown event.
local ob_evdels_empty = outbox_list_deliveries_for_event("00000000-0000-4000-8000-000000000000")
eq(#ob_evdels_empty, 0, "outbox_list_deliveries_for_event: empty for unknown event_id")

-- outbox_list_deliveries_for_target: returns deliveries for target.
local ob_tgtdels = outbox_list_deliveries_for_target(ob_tgt_id)
ok(#ob_tgtdels >= 1, "outbox_list_deliveries_for_target: at least 1 delivery for target")
eq(
  ob_tgtdels[1].target_id,
  ob_tgt_id,
  "outbox_list_deliveries_for_target: delivery target_id matches"
)

-- outbox_list_deliveries_for_target: empty for unknown target.
local ob_tgtdels_empty = outbox_list_deliveries_for_target("00000000-0000-4000-8000-000000000000")
eq(#ob_tgtdels_empty, 0, "outbox_list_deliveries_for_target: empty for unknown target_id")

-- outbox_update_delivery: updates allowed fields and bumps updated_at.
local ob_upd = outbox_update_delivery(ob_del_id, {
  status = "retrying",
  attempt_count = 1,
  next_attempt_at = "2000-01-01T00:00:00Z", -- past timestamp for pending_retries test below
  last_http_status = 503,
  last_error = "Service Unavailable",
})
ok(ob_upd ~= nil, "outbox_update_delivery: returns non-nil")
eq(ob_upd.status, "retrying", "outbox_update_delivery: status updated")
eq(ob_upd.attempt_count, 1, "outbox_update_delivery: attempt_count updated")
eq(
  ob_upd.next_attempt_at,
  "2000-01-01T00:00:00Z",
  "outbox_update_delivery: next_attempt_at updated"
)
eq(ob_upd.last_http_status, 503, "outbox_update_delivery: last_http_status updated")
eq(ob_upd.last_error, "Service Unavailable", "outbox_update_delivery: last_error updated")
ok(ob_upd.updated_at ~= nil, "outbox_update_delivery: updated_at is set")

-- outbox_update_delivery: partial update (only status).
local ob_partial = outbox_update_delivery(ob_del_id, { status = "retrying" })
ok(ob_partial ~= nil, "outbox_update_delivery: partial update returns non-nil")
eq(ob_partial.status, "retrying", "outbox_update_delivery: partial status preserved")
eq(
  ob_partial.attempt_count,
  1,
  "outbox_update_delivery: attempt_count unchanged after partial update"
)

-- outbox_update_delivery: returns nil for unknown delivery_id.
local ob_upd_miss =
  outbox_update_delivery("00000000-0000-4000-8000-000000000000", { status = "failed" })
ok(ob_upd_miss == nil, "outbox_update_delivery: nil for unknown id")

-- outbox_pending_retries: delivery with status=retrying and past next_attempt_at is returned.
-- (ob_del is currently retrying with next_attempt_at in the past.)
local ob_retries = outbox_pending_retries()
local ob_found_retry = false
for _, d in ipairs(ob_retries) do
  if d.delivery_id == ob_del_id then
    ob_found_retry = true
  end
end
ok(ob_found_retry, "outbox_pending_retries: delivery with past next_attempt_at included")

-- outbox_pending_retries: delivery with future next_attempt_at is not returned.
outbox_update_delivery(ob_del_id, { next_attempt_at = "2099-01-01T00:00:00Z" })
local ob_retries2 = outbox_pending_retries()
local ob_found_future = false
for _, d in ipairs(ob_retries2) do
  if d.delivery_id == ob_del_id then
    ob_found_future = true
  end
end
ok(not ob_found_future, "outbox_pending_retries: delivery with future next_attempt_at excluded")

-- outbox_pending_retries: delivery with status=pending is not returned.
outbox_update_delivery(ob_del_id, { status = "pending", next_attempt_at = "2000-01-01T00:00:00Z" })
local ob_retries3 = outbox_pending_retries()
local ob_found_pending = false
for _, d in ipairs(ob_retries3) do
  if d.delivery_id == ob_del_id then
    ob_found_pending = true
  end
end
ok(not ob_found_pending, "outbox_pending_retries: delivery with status=pending not included")

-- outbox_prune: removes events (and their deliveries) older than max_age_seconds.
-- Use max_age_seconds=-1 so the cutoff is 1 second in the future; all events
-- received "now" have received_at strictly less than that cutoff and are pruned.
outbox_prune(-1)
ok(outbox_get_event(ob_ev_id) == nil, "outbox_prune: event removed when cutoff is future")
ok(outbox_get_delivery(ob_del_id) == nil, "outbox_prune: delivery removed with its event")

-- outbox_prune: fresh events survive a large max_age prune.
local ob_ev2 = outbox_store_event("gitlab", "tag_push", { ref = "refs/tags/v1.0" })
outbox_prune(3600)
ok(
  outbox_get_event(ob_ev2.event_id) ~= nil,
  "outbox_prune: fresh event survives prune with large max_age"
)

-- ============================================================
-- target_create / target_get / target_list / target_update /
-- target_delete / target_get_secret (internal/targets.lua)
-- ============================================================

-- luacheck: globals target_create target_get target_list target_update target_delete target_get_secret

-- Note: the GetRandomBytes stub is deterministic, so make_uuid() always returns the
-- same UUID.  All tests therefore operate on a single target_id (the one assigned
-- by target_create), exercising create → get → update → delete lifecycle in order.

-- target_create: basic creation with all fields.
local ta = target_create({
  url = "https://example.com/hook",
  events = { "push" },
  shape = "confusio",
  secret = "s3cr3t",
})
ok(ta ~= nil, "target_create: returns non-nil")
ok(ta.target_id ~= nil, "target_create: target_id is set")
eq(#ta.target_id, 36, "target_create: target_id is 36 chars (UUID)")
eq(ta.url, "https://example.com/hook", "target_create: url is stored")
eq(ta.status, "active", "target_create: default status is active")
eq(ta.shape, "confusio", "target_create: shape is set")
eq(ta.events[1], "push", "target_create: events stored")
ok(ta.created_at ~= nil, "target_create: created_at is set")
ok(ta.updated_at ~= nil, "target_create: updated_at is set")
-- secret must not be in the public record.
ok(ta.secret == nil, "target_create: secret is not in public record")

-- target_create: defaults for events and shape when omitted (re-creates same id; overwrites).
local tb_events_check = target_create({ url = "https://b.example.com/hook" })
eq(tb_events_check.events[1], "*", 'target_create: events defaults to ["*"]')
eq(tb_events_check.shape, "github", "target_create: shape defaults to github")

-- target_get_secret: returns the raw secret for the stored target (now has no secret after overwrite).
-- Restore a known target with secret so we can test get_secret accurately.
local ts = target_create({ url = "https://secret.example.com/hook", secret = "s3cr3t" })
local ts_id = ts.target_id
local s1 = target_get_secret(ts_id)
eq(s1, "s3cr3t", "target_get_secret: returns stored secret")

-- target_get: returns public record for existing active target (check before overwriting).
local g1 = target_get(ts_id)
ok(g1 ~= nil, "target_get: found active target")
eq(g1.target_id, ts_id, "target_get: target_id matches")
eq(g1.url, "https://secret.example.com/hook", "target_get: url matches")
ok(g1.secret == nil, "target_get: no secret in public record")

-- target_get_secret: returns nil for a target with no secret.
-- Note: make_uuid is deterministic in tests so this re-uses ts_id, overwriting the store.
local tnosec = target_create({ url = "https://nosec.example.com/hook" })
ok(target_get_secret(tnosec.target_id) == nil, "target_get_secret: returns nil when no secret")

-- target_get_secret: returns nil for an unknown target_id.
ok(
  target_get_secret("00000000-0000-4000-8000-000000000000") == nil,
  "target_get_secret: nil for unknown id"
)

-- target_get: returns nil for unknown id.
ok(target_get("00000000-0000-4000-8000-000000000000") == nil, "target_get: nil for unknown id")

-- target_list: returns at least the targets we created (excludes deleted by default).
local list0 = target_list()
ok(#list0 >= 1, "target_list: at least 1 active target")
ok(list0[1].secret == nil, "target_list: no secret in listed records")

-- Verify the ts target is present in the list.
local found_ts = false
for _, entry in ipairs(list0) do
  if entry.target_id == ts_id then
    found_ts = true
  end
end
ok(found_ts, "target_list: created target appears in list")

-- target_list: filter by status=active.
local list_active = target_list({ status = "active" })
ok(#list_active >= 1, "target_list(active): returns active targets")

-- target_update: update url and shape.
local upd1 = target_update(ts_id, { url = "https://new.example.com/hook", shape = "github" })
ok(upd1 ~= nil, "target_update: returns non-nil for valid update")
eq(upd1.url, "https://new.example.com/hook", "target_update: url is updated")
eq(upd1.shape, "github", "target_update: shape is updated")
ok(upd1.secret == nil, "target_update: no secret in public update record")

-- target_update: update status to paused.
local upd2 = target_update(ts_id, { status = "paused" })
ok(upd2 ~= nil, "target_update(paused): returns non-nil")
eq(upd2.status, "paused", "target_update(paused): status is paused")

-- target_update: restore to active.
target_update(ts_id, { status = "active" })

-- target_update: set secret.
target_update(ts_id, { secret = "newsecret" })
eq(target_get_secret(ts_id), "newsecret", "target_update: secret is updated")

-- target_update: remove secret with false.
target_update(ts_id, { secret = false })
ok(target_get_secret(ts_id) == nil, "target_update(secret=false): secret removed")

-- target_update: status "deleted" is ignored (must use target_delete).
local before_status = target_get(ts_id).status
target_update(ts_id, { status = "deleted" })
eq(target_get(ts_id).status, before_status, "target_update: status=deleted is ignored")

-- target_update: returns nil for unknown id.
local upd_miss = target_update("00000000-0000-4000-8000-000000000000", { url = "https://x.com/" })
ok(upd_miss == nil, "target_update: nil for unknown id")

-- target_delete: soft-deletes a target.
local del1 = target_delete(ts_id)
ok(del1 == true, "target_delete: returns true on success")

-- target_get returns nil for deleted target.
ok(target_get(ts_id) == nil, "target_get: nil for deleted target")

-- target_list excludes deleted targets by default.
local list_after_del = target_list()
local found_deleted = false
for _, entry in ipairs(list_after_del) do
  if entry.target_id == ts_id then
    found_deleted = true
  end
end
ok(not found_deleted, "target_list: deleted target excluded from default list")

-- target_list with status=deleted includes deleted targets.
local list_deleted = target_list({ status = "deleted" })
local found_in_deleted = false
for _, entry in ipairs(list_deleted) do
  if entry.target_id == ts_id then
    found_in_deleted = true
  end
end
ok(found_in_deleted, "target_list(deleted): includes deleted target")

-- target_delete: returns nil when already deleted.
local del2 = target_delete(ts_id)
ok(del2 == nil, "target_delete: nil when already deleted")

-- target_delete: returns nil for unknown id.
local del_miss = target_delete("00000000-0000-4000-8000-000000000000")
ok(del_miss == nil, "target_delete: nil for unknown id")

-- target_update: returns nil for a deleted target.
local upd_del = target_update(ts_id, { url = "https://x.com/" })
ok(upd_del == nil, "target_update: nil for deleted target")

-- ============================================================
-- targets_api (internal/targets_api.lua)
-- ============================================================

ok(type(make_targets_api) == "function", "make_targets_api: exported as global function") -- luacheck: globals make_targets_api

do
  -- Helper: call the targets API with a fake request and return status + decoded body.
  local function call_api(opts)
    reset_request(opts)
    reset_response()
    app.targets_api() -- luacheck: globals app
    local body = _last_body ~= "" and pcall(DecodeJson, _last_body) and DecodeJson(_last_body)
      or nil
    return _last_status, body
  end

  -- Helper: call and return raw body string (for 204 empty body or error checks).
  local function call_api_raw(opts)
    reset_request(opts)
    reset_response()
    app.targets_api()
    return _last_status, _last_body
  end

  local AUTH = { Authorization = "Bearer admin-token" }

  -- ── 401 when Authorization header is missing ─────────────────

  local s401, b401 = call_api({
    method = "POST",
    path = "/webhooks/targets",
    headers = {},
    body = '{"url":"https://a.example.com/hook"}',
  })
  eq(s401, 401, "targets_api: missing auth → 401")
  eq(b401 and b401.error, "unauthorized", "targets_api: missing auth → error=unauthorized")

  -- ── POST /webhooks/targets: create a target ──────────────────

  local s_create, b_create = call_api({
    method = "POST",
    path = "/webhooks/targets",
    headers = AUTH,
    body = '{"url":"https://api.example.com/hook","events":["push"],"shape":"confusio"}',
  })
  eq(s_create, 201, "targets_api POST: 201 on create")
  ok(b_create ~= nil, "targets_api POST: body is non-nil")
  ok(b_create and b_create.target_id ~= nil, "targets_api POST: target_id in response")
  eq(b_create and b_create.url, "https://api.example.com/hook", "targets_api POST: url in response")
  eq(b_create and b_create.status, "active", "targets_api POST: status is active")
  eq(b_create and b_create.shape, "confusio", "targets_api POST: shape in response")
  ok(b_create and b_create.secret == nil, "targets_api POST: secret not in response")

  -- ── POST: missing url → 400 ──────────────────────────────────

  local s_no_url, b_no_url = call_api({
    method = "POST",
    path = "/webhooks/targets",
    headers = AUTH,
    body = '{"events":["push"]}',
  })
  eq(s_no_url, 400, "targets_api POST: missing url → 400")
  eq(
    b_no_url and b_no_url.error,
    "invalid_request",
    "targets_api POST: missing url → invalid_request"
  )

  -- ── POST: invalid url → 400 ──────────────────────────────────

  local s_bad_url, b_bad_url = call_api({
    method = "POST",
    path = "/webhooks/targets",
    headers = AUTH,
    body = '{"url":"not-a-url"}',
  })
  eq(s_bad_url, 400, "targets_api POST: invalid url → 400")
  eq(b_bad_url and b_bad_url.error, "invalid_url", "targets_api POST: invalid url → invalid_url")

  -- ── POST: mixed wildcard events → 400 ────────────────────────

  local s_bad_ev, b_bad_ev = call_api({
    method = "POST",
    path = "/webhooks/targets",
    headers = AUTH,
    body = '{"url":"https://x.example.com/hook","events":["*","push"]}',
  })
  eq(s_bad_ev, 400, "targets_api POST: mixed wildcard → 400")
  eq(
    b_bad_ev and b_bad_ev.error,
    "invalid_filter",
    "targets_api POST: mixed wildcard → invalid_filter"
  )

  -- ── POST: invalid shape → 400 ────────────────────────────────

  local s_bad_shape, b_bad_shape = call_api({
    method = "POST",
    path = "/webhooks/targets",
    headers = AUTH,
    body = '{"url":"https://x.example.com/hook","shape":"unknown"}',
  })
  eq(s_bad_shape, 400, "targets_api POST: invalid shape → 400")
  eq(
    b_bad_shape and b_bad_shape.error,
    "invalid_request",
    "targets_api POST: invalid shape → invalid_request"
  )

  -- Capture the target_id from a successful create for subsequent tests.
  -- (GetRandomBytes stub is deterministic so all make_uuid calls return the same ID.)
  local api_target_id = b_create and b_create.target_id

  -- ── GET /webhooks/targets: list ───────────────────────────────

  local s_list, b_list = call_api({
    method = "GET",
    path = "/webhooks/targets",
    headers = AUTH,
  })
  eq(s_list, 200, "targets_api GET list: 200")
  ok(b_list and type(b_list.targets) == "table", "targets_api GET list: targets array present")
  ok(b_list and b_list.next_cursor == nil, "targets_api GET list: next_cursor is null")

  -- ── GET /webhooks/targets/{id}: get single target ─────────────

  local s_get, b_get = call_api({
    method = "GET",
    path = "/webhooks/targets/" .. (api_target_id or "x"),
    headers = AUTH,
  })
  eq(s_get, 200, "targets_api GET single: 200")
  eq(b_get and b_get.target_id, api_target_id, "targets_api GET single: target_id matches")
  eq(b_get and b_get.circuit, "closed", "targets_api GET single: circuit field present")
  ok(
    b_get and b_get.circuit_open_until == nil,
    "targets_api GET single: circuit_open_until is null"
  )
  eq(b_get and b_get.consecutive_failures, 0, "targets_api GET single: consecutive_failures is 0")
  ok(b_get and b_get.secret == nil, "targets_api GET single: no secret in response")

  -- ── GET /webhooks/targets/{id}: not found → 404 ──────────────

  local s_nf, b_nf = call_api({
    method = "GET",
    path = "/webhooks/targets/00000000-0000-4000-8000-000000000000",
    headers = AUTH,
  })
  eq(s_nf, 404, "targets_api GET single: unknown id → 404")
  eq(
    b_nf and b_nf.error,
    "target_not_found",
    "targets_api GET single: unknown id → target_not_found"
  )

  -- ── PATCH /webhooks/targets/{id}: partial update ──────────────

  local s_patch, b_patch = call_api({
    method = "PATCH",
    path = "/webhooks/targets/" .. (api_target_id or "x"),
    headers = AUTH,
    body = '{"status":"paused","shape":"github"}',
  })
  eq(s_patch, 200, "targets_api PATCH: 200 on update")
  eq(b_patch and b_patch.status, "paused", "targets_api PATCH: status updated to paused")
  eq(b_patch and b_patch.shape, "github", "targets_api PATCH: shape updated to github")
  eq(b_patch and b_patch.circuit, "closed", "targets_api PATCH: circuit field present in response")

  -- ── PATCH: invalid status → 400 ──────────────────────────────

  local s_bad_st, b_bad_st = call_api({
    method = "PATCH",
    path = "/webhooks/targets/" .. (api_target_id or "x"),
    headers = AUTH,
    body = '{"status":"deleted"}',
  })
  eq(s_bad_st, 400, "targets_api PATCH: status=deleted → 400")
  eq(
    b_bad_st and b_bad_st.error,
    "invalid_status",
    "targets_api PATCH: status=deleted → invalid_status"
  )

  -- ── PATCH: not found → 404 ───────────────────────────────────

  local s_patch_nf, b_patch_nf = call_api({
    method = "PATCH",
    path = "/webhooks/targets/00000000-0000-4000-8000-000000000000",
    headers = AUTH,
    body = '{"status":"active"}',
  })
  eq(s_patch_nf, 404, "targets_api PATCH: unknown id → 404")
  eq(
    b_patch_nf and b_patch_nf.error,
    "target_not_found",
    "targets_api PATCH: unknown id → target_not_found"
  )

  -- ── DELETE /webhooks/targets/{id} ────────────────────────────

  local s_del, body_del = call_api_raw({
    method = "DELETE",
    path = "/webhooks/targets/" .. (api_target_id or "x"),
    headers = AUTH,
  })
  eq(s_del, 204, "targets_api DELETE: 204 on success")
  eq(body_del, "", "targets_api DELETE: empty body")

  -- ── DELETE: already deleted → 404 ────────────────────────────

  local s_del2, b_del2 = call_api({
    method = "DELETE",
    path = "/webhooks/targets/" .. (api_target_id or "x"),
    headers = AUTH,
  })
  eq(s_del2, 404, "targets_api DELETE: already deleted → 404")
  eq(
    b_del2 and b_del2.error,
    "target_not_found",
    "targets_api DELETE: already deleted → target_not_found"
  )

  -- ── GET: deleted target → 404 ────────────────────────────────

  local s_get_del, b_get_del = call_api({
    method = "GET",
    path = "/webhooks/targets/" .. (api_target_id or "x"),
    headers = AUTH,
  })
  eq(s_get_del, 404, "targets_api GET: deleted target → 404")
  eq(
    b_get_del and b_get_del.error,
    "target_not_found",
    "targets_api GET: deleted target → target_not_found"
  )

  -- ── Unknown path under /webhooks/targets/ → 404 ──────────────

  local s_unk, _ = call_api({
    method = "GET",
    path = "/webhooks/targets/abc/extra",
    headers = AUTH,
  })
  eq(s_unk, 404, "targets_api: unrecognised sub-path → 404")

  -- ── Method not allowed ────────────────────────────────────────

  local s_mna, _ = call_api({
    method = "PUT",
    path = "/webhooks/targets",
    headers = AUTH,
  })
  eq(s_mna, 405, "targets_api: PUT /webhooks/targets → 405")
end

-- ============================================================
-- fanout_body / fanout_dispatch (internal/fanout.lua)
-- ============================================================

-- luacheck: globals fanout_body fanout_dispatch

-- fanout_body: github shape — re-encodes payload at root level.
local fb_github = fanout_body("gitea", "push", { ref = "refs/heads/main" }, "github")
ok(type(fb_github) == "string", "fanout_body github: returns string")
local fb_github_dec = DecodeJson(fb_github)
ok(fb_github_dec ~= nil, "fanout_body github: valid JSON")
eq(fb_github_dec.ref, "refs/heads/main", "fanout_body github: payload field at root")
ok(fb_github_dec.source == nil, "fanout_body github: no source wrapper field")
ok(fb_github_dec.event == nil, "fanout_body github: no event wrapper field")

-- fanout_body: confusio shape — wraps in {source, event, payload} envelope.
local fb_confusio = fanout_body("gitea", "push", { ref = "refs/heads/main" }, "confusio")
ok(type(fb_confusio) == "string", "fanout_body confusio: returns string")
local fb_confusio_dec = DecodeJson(fb_confusio)
ok(fb_confusio_dec ~= nil, "fanout_body confusio: valid JSON")
eq(fb_confusio_dec.source, "gitea", "fanout_body confusio: source field")
eq(fb_confusio_dec.event, "push", "fanout_body confusio: event field")
ok(fb_confusio_dec.payload ~= nil, "fanout_body confusio: payload field present")
eq(
  fb_confusio_dec.payload.ref,
  "refs/heads/main",
  "fanout_body confusio: payload nested under payload key"
)

-- fanout_body: unknown shape falls back to github behaviour.
local fb_unknown = fanout_body("gitea", "push", { ref = "refs/heads/main" }, "unknown")
local fb_unknown_dec = DecodeJson(fb_unknown)
ok(fb_unknown_dec ~= nil, "fanout_body unknown shape: valid JSON")
eq(fb_unknown_dec.ref, "refs/heads/main", "fanout_body unknown shape: falls back to github")

-- fanout_dispatch: set up a target with wildcard subscription.
-- Note: the GetRandomBytes stub is deterministic, so make_uuid() always returns the
-- same UUID.  Previous test sections may have left multiple copies of that UUID
-- in the target _order list.  After the targets_api section the record is deleted,
-- so creating a new target here reactivates it.  target_list() returns one copy
-- per entry in _order, which can be > 1.  All assertions use >= 1 for counts.
local fd_target = target_create({ url = "https://fd-test.example.com/hook", events = { "*" } })
ok(fd_target ~= nil, "fanout_dispatch setup: target created")

local fd_ev, fd_dels = fanout_dispatch("gitea", "push", { ref = "refs/heads/main" })
ok(fd_ev ~= nil, "fanout_dispatch: returns event record")
ok(fd_ev.event_id ~= nil, "fanout_dispatch: event_id is set")
eq(fd_ev.backend, "gitea", "fanout_dispatch: event backend stored")
eq(fd_ev.event_type, "push", "fanout_dispatch: event type stored")
ok(type(fd_dels) == "table", "fanout_dispatch: returns deliveries table")
ok(#fd_dels >= 1, "fanout_dispatch: at least one delivery for wildcard target")
eq(fd_dels[1].event_id, fd_ev.event_id, "fanout_dispatch: delivery event_id matches event")
eq(fd_dels[1].target_id, fd_target.target_id, "fanout_dispatch: delivery target_id matches target")
eq(fd_dels[1].status, "pending", "fanout_dispatch: delivery status is pending")

-- fanout_dispatch: event type filtering — update target to "issues" only.
target_update(fd_target.target_id, { events = { "issues" } })

local fd_ev2, fd_dels2 = fanout_dispatch("gitea", "push", { ref = "refs/heads/main" })
ok(fd_ev2 ~= nil, "fanout_dispatch filtered: event stored even with no matching targets")
eq(#fd_dels2, 0, "fanout_dispatch filtered: push not delivered to issues-only target")

-- fanout_dispatch: matching event IS delivered to filtered target.
local fd_ev3, fd_dels3 = fanout_dispatch("gitea", "issues", { action = "opened" })
ok(fd_ev3 ~= nil, "fanout_dispatch match: event stored")
ok(#fd_dels3 >= 1, "fanout_dispatch match: issues event delivered to issues target")
eq(fd_dels3[1].target_id, fd_target.target_id, "fanout_dispatch match: correct target_id")

-- fanout_dispatch: deleted target receives no deliveries.
target_delete(fd_target.target_id)
local _, fd_dels4 = fanout_dispatch("gitea", "push", { ref = "refs/heads/main" })
eq(#fd_dels4, 0, "fanout_dispatch deleted: deleted target receives no deliveries")

-- ============================================================
-- deliver_attempt (internal/deliver.lua)
-- ============================================================

-- luacheck: globals deliver_attempt

-- Setup: create a target and use fanout_dispatch to get a delivery record.
-- (The fanout section left fd_target deleted; recreate it.)
local da_target = target_create({
  url = "https://da-test.example.com/hook",
  events = { "*" },
  secret = "test-secret",
})
ok(da_target ~= nil, "deliver_attempt setup: target created")

local _, da_dels = fanout_dispatch("gitea", "push", { ref = "refs/heads/main" })
ok(#da_dels >= 1, "deliver_attempt setup: at least one delivery created")
local da_del_id = da_dels[1].delivery_id

-- deliver_attempt: unknown delivery_id returns error without touching the outbox.
local da_err_ok, da_err_status, da_err_msg = deliver_attempt("00000000-0000-4000-8000-000000000000")
ok(da_err_ok == false, "deliver_attempt unknown id: ok is false")
ok(da_err_status == nil, "deliver_attempt unknown id: http_status is nil")
ok(da_err_msg ~= nil, "deliver_attempt unknown id: error message set")

-- Mock Fetch to intercept outbound HTTP calls.  We capture the last call's
-- url and opts so tests can verify headers are set correctly.
local _da_last_url = nil
local _da_last_opts = nil
local _da_mock_status = 200
local _da_mock_error = nil
local _real_Fetch = Fetch
Fetch = function(url, opts) -- luacheck: globals Fetch
  _da_last_url = url
  _da_last_opts = opts
  if _da_mock_error ~= nil then
    error(_da_mock_error)
  end
  return _da_mock_status, {}, "{}"
end

-- deliver_attempt: 200 → status "delivered".
_da_mock_status = 200
local da_ok1, da_s1, da_e1 = deliver_attempt(da_del_id)
ok(da_ok1 == true, "deliver_attempt 200: ok is true")
eq(da_s1, 200, "deliver_attempt 200: http_status is 200")
ok(da_e1 == nil, "deliver_attempt 200: no error")
local da_del1 = outbox_get_delivery(da_del_id)
eq(da_del1.status, "delivered", "deliver_attempt 200: delivery status is delivered")
eq(da_del1.last_http_status, 200, "deliver_attempt 200: last_http_status recorded")
eq(da_del1.attempt_count, 1, "deliver_attempt 200: attempt_count incremented to 1")

-- Verify the request was POSTed to the correct URL with expected headers.
eq(_da_last_url, "https://da-test.example.com/hook", "deliver_attempt: posts to target url")
ok(_da_last_opts ~= nil, "deliver_attempt: opts passed to Fetch")
eq(_da_last_opts.method, "POST", "deliver_attempt: method is POST")
ok(_da_last_opts.body ~= nil, "deliver_attempt: body is set")
ok(_da_last_opts.headers ~= nil, "deliver_attempt: headers table present")
eq(
  _da_last_opts.headers["Content-Type"],
  "application/json",
  "deliver_attempt: Content-Type is application/json"
)
eq(
  _da_last_opts.headers["X-GitHub-Event"],
  "push",
  "deliver_attempt github shape: X-GitHub-Event header set"
)
eq(
  _da_last_opts.headers["X-GitHub-Delivery"],
  da_del_id,
  "deliver_attempt github shape: X-GitHub-Delivery is delivery_id"
)
-- Secret was set so signatures should be present.
ok(
  _da_last_opts.headers["X-Hub-Signature-256"] ~= nil,
  "deliver_attempt github shape: X-Hub-Signature-256 present"
)
ok(
  _da_last_opts.headers["X-Hub-Signature"] ~= nil,
  "deliver_attempt github shape: X-Hub-Signature present"
)

-- deliver_attempt: 503 → status "retrying" with next_attempt_at set.
_da_mock_status = 503
local da_ok2, da_s2, da_e2 = deliver_attempt(da_del_id)
ok(da_ok2 == false, "deliver_attempt 503: ok is false")
eq(da_s2, 503, "deliver_attempt 503: http_status is 503")
ok(da_e2 ~= nil, "deliver_attempt 503: error message set")
local da_del2 = outbox_get_delivery(da_del_id)
eq(da_del2.status, "retrying", "deliver_attempt 503: status is retrying")
eq(da_del2.last_http_status, 503, "deliver_attempt 503: last_http_status is 503")
eq(da_del2.attempt_count, 2, "deliver_attempt 503: attempt_count is 2")
ok(da_del2.next_attempt_at ~= nil, "deliver_attempt 503: next_attempt_at is set")

-- deliver_attempt: 429 (Too Many Requests) → status "retrying".
_da_mock_status = 429
local da_ok3, da_s3, _ = deliver_attempt(da_del_id)
ok(da_ok3 == false, "deliver_attempt 429: ok is false")
eq(da_s3, 429, "deliver_attempt 429: http_status is 429")
local da_del3 = outbox_get_delivery(da_del_id)
eq(da_del3.status, "retrying", "deliver_attempt 429: status is retrying")

-- deliver_attempt: 422 (client error) → status "failed".
_da_mock_status = 422
local da_ok4, da_s4, da_e4 = deliver_attempt(da_del_id)
ok(da_ok4 == false, "deliver_attempt 422: ok is false")
eq(da_s4, 422, "deliver_attempt 422: http_status is 422")
ok(da_e4 ~= nil, "deliver_attempt 422: error message set")
local da_del4 = outbox_get_delivery(da_del_id)
eq(da_del4.status, "failed", "deliver_attempt 422: status is failed")
eq(da_del4.last_http_status, 422, "deliver_attempt 422: last_http_status is 422")

-- deliver_attempt: network error → status "retrying", http_status nil.
_da_mock_status = 200
_da_mock_error = "connection refused"
local da_ok5, da_s5, da_e5 = deliver_attempt(da_del_id)
ok(da_ok5 == false, "deliver_attempt network error: ok is false")
ok(da_s5 == nil, "deliver_attempt network error: http_status is nil")
ok(da_e5 ~= nil, "deliver_attempt network error: error message set")
local da_del5 = outbox_get_delivery(da_del_id)
eq(da_del5.status, "retrying", "deliver_attempt network error: status is retrying")
-- outbox_update_delivery uses partial-update semantics: passing last_http_status=nil
-- is a no-op, so the previous value is preserved.  Only check that status is correct.
ok(da_del5.last_error ~= nil, "deliver_attempt network error: last_error records the message")
_da_mock_error = nil

-- deliver_attempt: confusio shape target uses Confusio headers.
target_update(da_target.target_id, { shape = "confusio" })
_da_mock_status = 200
local da_ok6, _, _ = deliver_attempt(da_del_id)
ok(da_ok6 == true, "deliver_attempt confusio shape: ok is true")
ok(
  _da_last_opts.headers["X-Confusio-Event"] ~= nil,
  "deliver_attempt confusio shape: X-Confusio-Event present"
)
eq(
  _da_last_opts.headers["X-Confusio-Event"],
  "push",
  "deliver_attempt confusio shape: X-Confusio-Event is push"
)
eq(
  _da_last_opts.headers["X-Confusio-Source"],
  "gitea",
  "deliver_attempt confusio shape: X-Confusio-Source is backend"
)
ok(
  _da_last_opts.headers["X-Confusio-Signature-256"] ~= nil,
  "deliver_attempt confusio shape: X-Confusio-Signature-256 present"
)
ok(
  _da_last_opts.headers["X-Hub-Signature-256"] == nil,
  "deliver_attempt confusio shape: no github signature header"
)

-- Restore Fetch.
Fetch = _real_Fetch

-- deliver_attempt: deleted target → "failed" without making any network call.
target_delete(da_target.target_id)
-- Reset delivery to pending so we can test the deleted-target path.
outbox_update_delivery(da_del_id, { status = "pending", attempt_count = 0 })
local da_ok7, da_s7, da_e7 = deliver_attempt(da_del_id)
ok(da_ok7 == false, "deliver_attempt deleted target: ok is false")
ok(da_s7 == nil, "deliver_attempt deleted target: http_status is nil")
ok(da_e7 ~= nil, "deliver_attempt deleted target: error message set")
local da_del7 = outbox_get_delivery(da_del_id)
eq(da_del7.status, "failed", "deliver_attempt deleted target: status is failed")

-- ============================================================
-- deliveries_api (internal/deliveries_api.lua)
-- ============================================================

-- luacheck: globals make_deliveries_api outbox_list_all_deliveries

ok(type(make_deliveries_api) == "function", "make_deliveries_api: exported as global function")
ok(
  type(outbox_list_all_deliveries) == "function",
  "outbox_list_all_deliveries: exported as global function"
)

do
  -- Helper: call the deliveries API with a fake request and return status + decoded body.
  local function call_dapi(opts)
    reset_request(opts)
    reset_response()
    app.deliveries_api() -- luacheck: globals app
    local s_ok, decoded = pcall(DecodeJson, _last_body ~= "" and _last_body or "null")
    return _last_status, s_ok and decoded or nil
  end

  local AUTH = { Authorization = "Bearer admin-token" }

  -- ── 401 when Authorization header is missing ─────────────────

  local s401, b401 = call_dapi({ method = "GET", path = "/webhooks/deliveries", headers = {} })
  eq(s401, 401, "deliveries_api: missing auth → 401")
  eq(b401 and b401.error, "unauthorized", "deliveries_api: missing auth → error=unauthorized")

  -- ── Set up a fresh event + delivery for the remaining tests ──

  local dapi_ev = outbox_store_event("gitea", "push", { ref = "refs/heads/main" })
  ok(dapi_ev ~= nil, "deliveries_api setup: event stored")
  local dapi_target =
    target_create({ url = "https://dapi-test.example.com/hook", events = { "*" } })
  ok(dapi_target ~= nil, "deliveries_api setup: target created")
  local dapi_del = outbox_create_delivery(dapi_ev.event_id, dapi_target.target_id)
  ok(dapi_del ~= nil, "deliveries_api setup: delivery created")

  -- ── outbox_list_all_deliveries ───────────────────────────────

  local all_dels = outbox_list_all_deliveries()
  ok(type(all_dels) == "table", "outbox_list_all_deliveries: returns a table")
  ok(#all_dels >= 1, "outbox_list_all_deliveries: at least one delivery present")

  -- ── GET /webhooks/deliveries → 200 with array ────────────────

  local s_list, b_list =
    call_dapi({ method = "GET", path = "/webhooks/deliveries", headers = AUTH })
  eq(s_list, 200, "deliveries_api GET list: 200")
  ok(type(b_list) == "table", "deliveries_api GET list: response is a table (array)")

  -- ── GET /webhooks/deliveries/{id} → 200 with delivery object ─

  local s_get, b_get = call_dapi({
    method = "GET",
    path = "/webhooks/deliveries/" .. dapi_del.delivery_id,
    headers = AUTH,
  })
  eq(s_get, 200, "deliveries_api GET single: 200")
  eq(
    b_get and b_get.delivery_id,
    dapi_del.delivery_id,
    "deliveries_api GET single: delivery_id matches"
  )
  eq(b_get and b_get.event_id, dapi_ev.event_id, "deliveries_api GET single: event_id present")
  eq(
    b_get and b_get.target_id,
    dapi_target.target_id,
    "deliveries_api GET single: target_id present"
  )
  ok(b_get and b_get.status ~= nil, "deliveries_api GET single: status field present")
  ok(b_get and b_get.created_at ~= nil, "deliveries_api GET single: created_at field present")

  -- ── GET /webhooks/deliveries/nonexistent → 404 ───────────────

  local s_nf, b_nf = call_dapi({
    method = "GET",
    path = "/webhooks/deliveries/00000000-0000-4000-8000-000000000000",
    headers = AUTH,
  })
  eq(s_nf, 404, "deliveries_api GET single: unknown id → 404")
  eq(
    b_nf and b_nf.error,
    "delivery_not_found",
    "deliveries_api GET single: unknown id → delivery_not_found"
  )

  -- ── GET /webhooks/events/{event_id}/deliveries → 200 ─────────

  local s_ev, b_ev = call_dapi({
    method = "GET",
    path = "/webhooks/events/" .. dapi_ev.event_id .. "/deliveries",
    headers = AUTH,
  })
  eq(s_ev, 200, "deliveries_api GET event deliveries: 200")
  ok(type(b_ev) == "table", "deliveries_api GET event deliveries: response is array")
  ok(#b_ev >= 1, "deliveries_api GET event deliveries: at least one delivery")
  eq(
    b_ev[1] and b_ev[1].event_id,
    dapi_ev.event_id,
    "deliveries_api GET event deliveries: event_id matches"
  )

  -- ── GET /webhooks/events/nonexistent/deliveries → 404 ────────

  local s_ev_nf, b_ev_nf = call_dapi({
    method = "GET",
    path = "/webhooks/events/00000000-0000-4000-8000-000000000000/deliveries",
    headers = AUTH,
  })
  eq(s_ev_nf, 404, "deliveries_api GET event deliveries: unknown event → 404")
  eq(
    b_ev_nf and b_ev_nf.error,
    "event_not_found",
    "deliveries_api GET event deliveries: unknown event → event_not_found"
  )

  -- ── GET /webhooks/targets/{target_id}/deliveries → 200 ───────

  local s_tgt, b_tgt = call_dapi({
    method = "GET",
    path = "/webhooks/targets/" .. dapi_target.target_id .. "/deliveries",
    headers = AUTH,
  })
  eq(s_tgt, 200, "deliveries_api GET target deliveries: 200")
  ok(type(b_tgt) == "table", "deliveries_api GET target deliveries: response is array")
  ok(#b_tgt >= 1, "deliveries_api GET target deliveries: at least one delivery")
  eq(
    b_tgt[1] and b_tgt[1].target_id,
    dapi_target.target_id,
    "deliveries_api GET target deliveries: target_id matches"
  )

  -- ── GET /webhooks/targets/nonexistent/deliveries → 404 ───────

  local s_tgt_nf, b_tgt_nf = call_dapi({
    method = "GET",
    path = "/webhooks/targets/00000000-0000-4000-8000-000000000000/deliveries",
    headers = AUTH,
  })
  eq(s_tgt_nf, 404, "deliveries_api GET target deliveries: unknown target → 404")
  eq(
    b_tgt_nf and b_tgt_nf.error,
    "target_not_found",
    "deliveries_api GET target deliveries: unknown target → target_not_found"
  )

  -- ── Non-GET method → 405 ─────────────────────────────────────

  local s_mna, _ = call_dapi({ method = "POST", path = "/webhooks/deliveries", headers = AUTH })
  eq(s_mna, 405, "deliveries_api: POST /webhooks/deliveries → 405")

  -- ── Unknown sub-path → 404 ───────────────────────────────────

  local s_unk, _ =
    call_dapi({ method = "GET", path = "/webhooks/deliveries/abc/extra", headers = AUTH })
  eq(s_unk, 404, "deliveries_api: unrecognised sub-path → 404")
end

-- ============================================================
-- Summary
-- ============================================================

io.write(string.format("\n%d passed, %d failed\n", PASS, FAIL))
if FAIL > 0 then
  os.exit(1)
end
