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

-- Load the module under test.
_real_dofile(".init.lua")

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
ok(type(app.allow_anonymous) == "boolean", "app.allow_anonymous: is a boolean")
ok(app.allow_anonymous == true, "app.allow_anonymous: default true (no backend loaded)")

-- make_app: constructs independent context from a given config table.
do
  local test_cfg = { backend = "test", base_url = "https://test.example.com" }
  local test_app = make_app(test_cfg)
  ok(test_app.config == test_cfg, "make_app: config is the supplied table")
  ok(type(test_app.backend) == "table", "make_app: backend is a table")
  ok(type(test_app.backend.rest) == "table", "make_app: backend.rest is a table")
  ok(type(test_app.backend.graphql) == "table", "make_app: backend.graphql is a table")
  ok(type(test_app.backend.capabilities) == "table", "make_app: backend.capabilities is a table")
  ok(test_app.allow_anonymous == true, "make_app: allow_anonymous defaults to true")
  ok(test_app ~= app, "make_app: returns a new independent table each call")
end

-- ============================================================
-- make_backend_builder
-- ============================================================

do
  local saved_rest = app.backend.rest
  local saved_capabilities = app.backend.capabilities
  local saved_resolvers = graphql_resolvers -- luacheck: globals graphql_resolvers
  local saved_anon = app.allow_anonymous

  local function restore()
    app.backend.rest = saved_rest
    app.backend.capabilities = saved_capabilities
    graphql_resolvers = saved_resolvers -- luacheck: globals graphql_resolvers
    app.allow_anonymous = saved_anon
  end

  -- factory returns a builder table with the expected methods
  local b = make_backend_builder()
  ok(type(b) == "table", "make_backend_builder: returns a table")
  ok(type(b.rest) == "function", "make_backend_builder: has rest method")
  ok(type(b.graphql) == "function", "make_backend_builder: has graphql method")
  ok(type(b.capability) == "function", "make_backend_builder: has capability method")
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
  ok(b2:set_allow_anonymous(true) == b2, "builder:set_allow_anonymous: returns self")

  -- build() populates app.backend.rest, graphql_resolvers, and app.backend.capabilities
  app.backend.rest = {}
  app.backend.capabilities = {}
  graphql_resolvers = {} -- luacheck: globals graphql_resolvers
  app.allow_anonymous = true

  local get_fn = function() end
  local gql_fn = function() end
  local cap_repos = { get = function() end, list = function() end }
  local b3 = make_backend_builder()
  b3:rest("get_repo", get_fn)
  b3:graphql("Query.viewer", gql_fn)
  b3:capability("repos", cap_repos)
  b3:set_allow_anonymous(false)
  b3:build()

  eq(app.backend.rest["get_repo"], get_fn, "builder:build: registers REST handler")
  eq(graphql_resolvers["Query.viewer"], gql_fn, "builder:build: registers GraphQL resolver") -- luacheck: globals graphql_resolvers
  eq(app.backend.capabilities["repos"], cap_repos, "builder:build: registers capability module")
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

  -- build(strip) excludes REST keys matching any pattern but NOT capabilities
  app.backend.rest = {}
  app.backend.capabilities = {}
  local cap_issues = { get = function() end }
  local b5 = make_backend_builder()
  b5:rest("get_repo", function() end)
  b5:rest("get_package_info", function() end)
  b5:rest("list_actions_runs", function() end)
  b5:capability("issues", cap_issues)
  b5:build({ "_package", "_actions_" })
  ok(app.backend.rest["get_repo"] ~= nil, "builder:build(strip): keeps non-matching key")
  ok(app.backend.rest["get_package_info"] == nil, "builder:build(strip): strips _package key")
  ok(app.backend.rest["list_actions_runs"] == nil, "builder:build(strip): strips _actions_ key")
  eq(
    app.backend.capabilities["issues"],
    cap_issues,
    "builder:build(strip): capabilities are not stripped"
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
-- Summary
-- ============================================================

io.write(string.format("\n%d passed, %d failed\n", PASS, FAIL))
if FAIL > 0 then
  os.exit(1)
end
