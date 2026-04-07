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
local _req_headers, _req_path, _req_params, _req_method

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
end

reset_response()
reset_request()

-- Override Redbean HTTP context built-ins before loading .init.lua.
-- luacheck: push
-- luacheck: globals SetStatus SetHeader Write GetHeader GetPath GetParam GetMethod Route
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
-- luacheck: pop

-- Prevent backend file loading (config.backend will be "" anyway, but be safe).
local _real_dofile = dofile
function dofile(path) -- luacheck: globals dofile
  if path and path:match("^/zip/backends/") then
    return
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

-- GET /repos/{owner}/{repo} — no backend → 404 (no default_fn)
reset_response()
reset_request({ method = "GET", path = "/repos/alice/myrepo" })
OnHttpRequest()
eq(_last_status, 404, "OnHttpRequest: backend endpoint without default → 404")

-- backend_allow_anonymous=false, no Authorization → 401
reset_response()
reset_request({ method = "GET", path = "/" })
backend_allow_anonymous = false
OnHttpRequest()
eq(_last_status, 401, "OnHttpRequest: anon forbidden when backend_allow_anonymous=false → 401")
backend_allow_anonymous = true

-- backend_allow_anonymous=false, with Authorization → proceeds normally
reset_response()
reset_request({ method = "GET", path = "/", headers = { Authorization = "token mytoken" } })
backend_allow_anonymous = false
OnHttpRequest()
eq(
  _last_status,
  200,
  "OnHttpRequest: authorized request allowed when backend_allow_anonymous=false → 200"
)
backend_allow_anonymous = true

-- ============================================================
-- Summary
-- ============================================================

io.write(string.format("\n%d passed, %d failed\n", PASS, FAIL))
if FAIL > 0 then
  os.exit(1)
end
