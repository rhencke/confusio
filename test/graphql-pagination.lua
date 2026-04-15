-- Unit tests for GraphQL pagination cursor helpers and connection builders.
-- Tests: graphql_page_to_cursor, graphql_cursor_to_page, graphql_cursor_url,
--        graphql_inline_connection, graphql_make_connection, typed wrappers.

-- Redirect /zip/internal/ → internal/ so dofile works outside the zip.
local real_dofile = dofile
dofile = function(path) -- luacheck: globals dofile
  if path:sub(1, 5) == "/zip/" then
    return real_dofile(path:sub(6))
  end
  return real_dofile(path)
end

real_dofile("internal/graphql_translators.lua")

-- Restore dofile so the test runner and any later modules are unaffected.
dofile = real_dofile -- luacheck: globals dofile

-- ---------------------------------------------------------------------------
-- Minimal test harness (mirrors graphql-node-id.lua)
-- ---------------------------------------------------------------------------

local passed = 0
local failed = 0

local function eq(got, expected, label)
  if got == expected then
    passed = passed + 1
  else
    failed = failed + 1
    io.stderr:write(
      string.format("FAIL [%s]: expected %s, got %s\n", label, tostring(expected), tostring(got))
    )
  end
end

local function ok(cond, label)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    io.stderr:write(string.format("FAIL [%s]: condition was false\n", label))
  end
end

local function not_nil(v, label)
  ok(v ~= nil, label)
end

local function is_nil(v, label)
  ok(v == nil, label)
end

-- ---------------------------------------------------------------------------
-- graphql_page_to_cursor / graphql_cursor_to_page
-- ---------------------------------------------------------------------------

-- Basic round-trip: encode page 1 and decode it back.
local c1 = graphql_page_to_cursor(1)
not_nil(c1, "cursor(1) is non-nil")
eq(graphql_cursor_to_page(c1), 1, "round-trip page 1")

-- Round-trip page 5.
local c5 = graphql_page_to_cursor(5)
eq(graphql_cursor_to_page(c5), 5, "round-trip page 5")

-- Round-trip page 100.
local c100 = graphql_page_to_cursor(100)
eq(graphql_cursor_to_page(c100), 100, "round-trip page 100")

-- Different pages produce different cursors.
ok(c1 ~= c5, "cursor(1) ~= cursor(5)")
ok(c5 ~= c100, "cursor(5) ~= cursor(100)")

-- Decoding nil cursor returns nil.
is_nil(graphql_cursor_to_page(nil), "cursor_to_page(nil) is nil")

-- Decoding an empty string returns nil (not valid base64 for a page cursor).
is_nil(graphql_cursor_to_page(""), "cursor_to_page('') is nil")

-- Decoding a random base64 string that is not "page:N" returns nil.
local junk = EncodeBase64("notapage")
is_nil(graphql_cursor_to_page(junk), "cursor_to_page(junk) is nil")

-- Decoding a node ID (wrong format) returns nil.
local node_id = EncodeBase64("Repository:owner/repo")
is_nil(graphql_cursor_to_page(node_id), "cursor_to_page(node_id) is nil")

-- ---------------------------------------------------------------------------
-- graphql_cursor_url
-- ---------------------------------------------------------------------------

-- No existing query string; per_page and page params both provided.
-- First page (page=1) should not append the page parameter.
local url1 = graphql_cursor_url("https://example.com/api/repos", { first = 10 }, {
  per_page = "limit",
  page = "page",
})
eq(url1, "https://example.com/api/repos?limit=10", "cursor_url: page 1 omits page param")

-- After cursor for page 2: page=2 should be appended.
local after2 = graphql_page_to_cursor(1) -- cursor after page 1 → fetch page 2
local url2 = graphql_cursor_url("https://example.com/api/repos", { first = 10, after = after2 }, {
  per_page = "limit",
  page = "page",
})
eq(url2, "https://example.com/api/repos?limit=10&page=2", "cursor_url: page 2 appends page param")

-- Default per_page = 30 when args.first is absent.
local url_default = graphql_cursor_url("https://example.com/api/items", {}, {
  per_page = "per_page",
  page = "page",
})
eq(url_default, "https://example.com/api/items?per_page=30", "cursor_url: default per_page=30")

-- URL already has a query string: use & separator.
local url_qs = graphql_cursor_url(
  "https://example.com/api/issues?state=open",
  { first = 20 },
  { per_page = "limit", page = "page" }
)
eq(
  url_qs,
  "https://example.com/api/issues?state=open&limit=20",
  "cursor_url: & separator with existing QS"
)

-- Omitting per_page key from param_names skips per_page.
local url_no_pp = graphql_cursor_url(
  "https://example.com/api/items",
  { first = 5 },
  { page = "page" }
)
eq(
  url_no_pp,
  "https://example.com/api/items",
  "cursor_url: no per_page key → no params appended on page 1"
)

-- Omitting page key from param_names skips page even on page 2.
local after_p2 = graphql_page_to_cursor(2)
local url_no_pg = graphql_cursor_url(
  "https://example.com/api/items",
  { first = 5, after = after_p2 },
  { per_page = "limit" }
)
eq(
  url_no_pg,
  "https://example.com/api/items?limit=5",
  "cursor_url: no page key → page never appended"
)

-- Malformed cursor treated as page 1 (falls back to default).
local url_bad = graphql_cursor_url(
  "https://example.com/api/items",
  { first = 5, after = "notacursor" },
  { per_page = "limit", page = "page" }
)
eq(
  url_bad,
  "https://example.com/api/items?limit=5",
  "cursor_url: malformed after → page 1, no page param"
)

-- ---------------------------------------------------------------------------
-- graphql_inline_connection
-- ---------------------------------------------------------------------------

local nodes3 = { { id = "a" }, { id = "b" }, { id = "c" } }
local conn3 = graphql_inline_connection("Issue", nodes3)

eq(conn3.__typename, "IssueConnection", "inline_connection __typename")
eq(conn3.totalCount, 3, "inline_connection totalCount")
eq(conn3.pageInfo.__typename, "PageInfo", "inline_connection pageInfo.__typename")
eq(conn3.pageInfo.hasNextPage, false, "inline_connection hasNextPage=false")
eq(conn3.pageInfo.hasPreviousPage, false, "inline_connection hasPreviousPage=false")
is_nil(conn3.pageInfo.startCursor, "inline_connection startCursor=nil")
is_nil(conn3.pageInfo.endCursor, "inline_connection endCursor=nil")
eq(#conn3.nodes, 3, "inline_connection nodes length")
eq(#conn3.edges, 3, "inline_connection edges length")
eq(conn3.edges[1].__typename, "IssueEdge", "inline_connection edge __typename")
eq(conn3.edges[1].cursor, "", "inline_connection edge cursor=''")
eq(conn3.edges[1].node.id, "a", "inline_connection edge node")

-- Empty inline connection.
local conn0 = graphql_inline_connection("Label", {})
eq(conn0.totalCount, 0, "inline_connection empty totalCount")
eq(#conn0.edges, 0, "inline_connection empty edges")

-- ---------------------------------------------------------------------------
-- graphql_make_connection
-- ---------------------------------------------------------------------------

-- Page 1, known total, has_next = true.
local items = { { id = 1 }, { id = 2 }, { id = 3 } }
local mc1 = graphql_make_connection("Issue", items, { first = 3 }, 10, nil)
eq(mc1.__typename, "IssueConnection", "make_connection __typename")
eq(mc1.totalCount, 10, "make_connection totalCount from total arg")
eq(mc1.pageInfo.hasNextPage, true, "make_connection hasNextPage true (3*1<10)")
eq(mc1.pageInfo.hasPreviousPage, false, "make_connection hasPreviousPage false on page 1")
not_nil(mc1.pageInfo.startCursor, "make_connection startCursor non-nil")
not_nil(mc1.pageInfo.endCursor, "make_connection endCursor non-nil")
eq(mc1.pageInfo.startCursor, mc1.pageInfo.endCursor, "make_connection start=end cursor")
eq(#mc1.nodes, 3, "make_connection nodes length")
eq(#mc1.edges, 3, "make_connection edges length")
eq(mc1.edges[1].__typename, "IssueEdge", "make_connection edge __typename")
not_nil(mc1.edges[1].cursor, "make_connection edge cursor non-nil")

-- Page 1, no total, has_next inferred from count == per_page.
local mc_infer = graphql_make_connection("Repository", items, { first = 3 }, nil, nil)
eq(mc_infer.totalCount, 3, "make_connection totalCount from count when no total")
eq(mc_infer.pageInfo.hasNextPage, true, "make_connection hasNextPage inferred (count==per_page)")

-- Page 1, no total, count < per_page → has_next = false.
local mc_last = graphql_make_connection("Repository", items, { first = 10 }, nil, nil)
eq(mc_last.pageInfo.hasNextPage, false, "make_connection hasNextPage false (count<per_page)")

-- Page 1, exact last page (total known, no more pages).
local mc_exact = graphql_make_connection("Issue", items, { first = 3 }, 3, nil)
eq(mc_exact.pageInfo.hasNextPage, false, "make_connection hasNextPage false (page*per==total)")

-- Page 2 (via after cursor): hasPreviousPage = true.
local after_p1 = graphql_page_to_cursor(1)
local mc2 = graphql_make_connection("Issue", items, { first = 3, after = after_p1 }, 10, nil)
eq(mc2.pageInfo.hasPreviousPage, true, "make_connection hasPreviousPage true on page 2")
eq(mc2.pageInfo.hasNextPage, true, "make_connection hasNextPage true on page 2 (6<10)")

-- Empty page: cursors are nil.
local mc_empty = graphql_make_connection("Issue", {}, { first = 10 }, 0, nil)
eq(mc_empty.totalCount, 0, "make_connection empty totalCount")
is_nil(mc_empty.pageInfo.startCursor, "make_connection empty startCursor nil")
is_nil(mc_empty.pageInfo.endCursor, "make_connection empty endCursor nil")
eq(#mc_empty.nodes, 0, "make_connection empty nodes")
eq(#mc_empty.edges, 0, "make_connection empty edges")

-- Backward pagination: returns empty connection, no ctx error needed.
local mc_back = graphql_make_connection("Issue", items, { last = 3 }, 10, nil)
eq(mc_back.__typename, "IssueConnection", "backward pagination returns IssueConnection")
eq(mc_back.totalCount, 0, "backward pagination totalCount=0")
eq(#mc_back.nodes, 0, "backward pagination nodes empty")

-- Backward pagination with ctx: graphql_error is called.
-- We stub graphql_error temporarily to capture the call.
local error_called = false
local real_graphql_error = graphql_error -- luacheck: globals graphql_error
graphql_error = function(_, _) -- luacheck: globals graphql_error
  error_called = true
end
graphql_make_connection("Issue", items, { before = "somecursor" }, 10, {})
graphql_error = real_graphql_error -- luacheck: globals graphql_error
ok(error_called, "make_connection calls graphql_error for before arg with ctx")

-- ---------------------------------------------------------------------------
-- Typed convenience wrappers
-- ---------------------------------------------------------------------------

local wrap_nodes = { { id = "x" } }
local wrap_args = { first = 1 }

local wi = graphql_issues_connection(wrap_nodes, wrap_args, 5, nil)
eq(wi.__typename, "IssueConnection", "graphql_issues_connection typename")
eq(wi.totalCount, 5, "graphql_issues_connection totalCount")

local wp = graphql_prs_connection(wrap_nodes, wrap_args, nil, nil)
eq(wp.__typename, "PullRequestConnection", "graphql_prs_connection typename")

local wr = graphql_repos_connection(wrap_nodes, wrap_args, nil, nil)
eq(wr.__typename, "RepositoryConnection", "graphql_repos_connection typename")

local wu = graphql_users_connection(wrap_nodes, wrap_args, nil, nil)
eq(wu.__typename, "UserConnection", "graphql_users_connection typename")

local wl = graphql_labels_connection(wrap_nodes, wrap_args, nil, nil)
eq(wl.__typename, "LabelConnection", "graphql_labels_connection typename")

local wref = graphql_refs_connection(wrap_nodes, wrap_args, nil, nil)
eq(wref.__typename, "RefConnection", "graphql_refs_connection typename")

-- ---------------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------------

local total = passed + failed
io.stderr:write(string.format("graphql-pagination: %d/%d passed\n", passed, total))
if failed > 0 then
  os.exit(1)
end
