-- Unit tests for GraphQL pagination cursor helpers and connection builders.
-- Tests: graphql_page_to_cursor, graphql_cursor_to_page, graphql_cursor_url,
--        graphql_inline_connection, graphql_make_connection, typed wrappers.
-- Loaded by test/unit-graphql.lua; relies on shared state from the driver.

-- Globals provided by the driver (test/unit-graphql.lua):
-- luacheck: globals ok eq PASS FAIL

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
-- graphql_page_to_cursor with item index (item-level cursors)
-- ---------------------------------------------------------------------------

-- Item-level cursor is non-nil and decodes to the correct page.
local ci1_1 = graphql_page_to_cursor(1, 1)
not_nil(ci1_1, "cursor(1,1) is non-nil")
eq(graphql_cursor_to_page(ci1_1), 1, "cursor(1,1) decodes to page 1")

local ci3_5 = graphql_page_to_cursor(3, 5)
eq(graphql_cursor_to_page(ci3_5), 3, "cursor(3,5) decodes to page 3")

-- Same page, different item indices → different cursors.
local ci1_2 = graphql_page_to_cursor(1, 2)
ok(ci1_1 ~= ci1_2, "cursor(1,1) ~= cursor(1,2)")

-- Different pages, same item index → different cursors.
local ci2_1 = graphql_page_to_cursor(2, 1)
ok(ci1_1 ~= ci2_1, "cursor(1,1) ~= cursor(2,1)")

-- Item-level cursor on page N differs from page-only cursor for page N.
-- (graphql_page_to_cursor(1) encodes "page:1"; graphql_page_to_cursor(1,1) encodes "page:1:1")
ok(graphql_page_to_cursor(1) ~= graphql_page_to_cursor(1, 1), "page-only ~= item-level cursor")

-- Page-only cursors (old format) still decode correctly alongside item-level.
eq(graphql_cursor_to_page(graphql_page_to_cursor(7)), 7, "page-only cursor(7) still decodes")
eq(
  graphql_cursor_to_page(graphql_page_to_cursor(7, 3)),
  7,
  "item-level cursor(7,3) decodes to page 7"
)

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

-- Item-level after cursor: page number is extracted; :M suffix is ignored for URL building.
-- after: cursor(page:2:5) means "items after item 5 on page 2" → fetch page 3 (same as page-only).
local url_item_after = graphql_cursor_url(
  "https://example.com/api/repos",
  { first = 10, after = graphql_page_to_cursor(2, 5) },
  { per_page = "limit", page = "page" }
)
eq(
  url_item_after,
  "https://example.com/api/repos?limit=10&page=3",
  "cursor_url: item-level after cursor(2,5) → page 3"
)

-- Item-level before cursor: page extracted correctly; before(3,5) → page 2.
local url_item_before = graphql_cursor_url(
  "https://example.com/api/issues",
  { last = 10, before = graphql_page_to_cursor(3, 5) },
  { per_page = "limit", page = "page" }
)
eq(
  url_item_before,
  "https://example.com/api/issues?limit=10&page=2",
  "cursor_url: item-level before cursor(3,5) → page 2"
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
-- Item-level cursors: start and end cursors differ for multi-item pages.
ok(
  mc1.pageInfo.startCursor ~= mc1.pageInfo.endCursor,
  "make_connection start≠end cursor (item-level)"
)
-- Both cursors decode to the same page number.
eq(
  graphql_cursor_to_page(mc1.pageInfo.startCursor),
  graphql_cursor_to_page(mc1.pageInfo.endCursor),
  "make_connection start/end on same page"
)
eq(#mc1.nodes, 3, "make_connection nodes length")
eq(#mc1.edges, 3, "make_connection edges length")
eq(mc1.edges[1].__typename, "IssueEdge", "make_connection edge __typename")
not_nil(mc1.edges[1].cursor, "make_connection edge cursor non-nil")
-- Each edge has a distinct item-level cursor.
ok(mc1.edges[1].cursor ~= mc1.edges[2].cursor, "make_connection edge cursors are distinct")
ok(mc1.edges[1].cursor == mc1.pageInfo.startCursor, "make_connection first edge is startCursor")
ok(mc1.edges[3].cursor == mc1.pageInfo.endCursor, "make_connection last edge is endCursor")

-- Single-item page: startCursor and endCursor are identical (only one edge).
local single_item = { { id = 42 } }
local mc_single = graphql_make_connection("Issue", single_item, { first = 10 }, 1, nil)
not_nil(mc_single.pageInfo.startCursor, "make_connection single-item startCursor non-nil")
not_nil(mc_single.pageInfo.endCursor, "make_connection single-item endCursor non-nil")
eq(
  mc_single.pageInfo.startCursor,
  mc_single.pageInfo.endCursor,
  "make_connection single-item start=end cursor"
)
ok(
  mc_single.edges[1].cursor == mc_single.pageInfo.startCursor,
  "make_connection single-item edge is startCursor"
)

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

-- ---------------------------------------------------------------------------
-- Backward pagination: graphql_cursor_url
-- ---------------------------------------------------------------------------

-- last: N with known total → URL for the computed last page.
local before_total_url = graphql_cursor_url(
  "https://example.com/api/issues",
  { last = 10 },
  { per_page = "limit", page = "page" },
  25 -- total; last_page = ceil(25/10) = 3
)
eq(
  before_total_url,
  "https://example.com/api/issues?limit=10&page=3",
  "cursor_url backward: last+total → last page URL"
)

-- last: N with total that is an exact multiple → last_page = total/N (no remainder).
local before_exact_url = graphql_cursor_url(
  "https://example.com/api/issues",
  { last = 10 },
  { per_page = "limit", page = "page" },
  20 -- total; last_page = ceil(20/10) = 2
)
eq(
  before_exact_url,
  "https://example.com/api/issues?limit=10&page=2",
  "cursor_url backward: last+exact total → last page URL"
)

-- last: N without total → fallback to page 1 (no page param).
local before_nototal_url = graphql_cursor_url(
  "https://example.com/api/issues",
  { last = 10 },
  { per_page = "limit", page = "page" }
)
eq(
  before_nototal_url,
  "https://example.com/api/issues?limit=10",
  "cursor_url backward: last without total → page 1"
)

-- before: cursor(P) where P > 1 → page P-1.
local before_c3_url = graphql_cursor_url(
  "https://example.com/api/issues",
  { last = 10, before = graphql_page_to_cursor(3) },
  { per_page = "limit", page = "page" }
)
eq(
  before_c3_url,
  "https://example.com/api/issues?limit=10&page=2",
  "cursor_url backward: before cursor(3) → page 2"
)

-- before: cursor(2) → page 1 (no page param because page == 1).
local before_c2_url = graphql_cursor_url(
  "https://example.com/api/issues",
  { last = 10, before = graphql_page_to_cursor(2) },
  { per_page = "limit", page = "page" }
)
eq(
  before_c2_url,
  "https://example.com/api/issues?limit=10",
  "cursor_url backward: before cursor(2) → page 1"
)

-- before: cursor(1) → clamps to page 1 (make_connection handles the empty case).
local before_c1_url = graphql_cursor_url(
  "https://example.com/api/issues",
  { last = 5, before = graphql_page_to_cursor(1) },
  { per_page = "limit", page = "page" }
)
eq(
  before_c1_url,
  "https://example.com/api/issues?limit=5",
  "cursor_url backward: before cursor(1) → clamped to page 1"
)

-- before: malformed cursor → clamps to page 1.
local before_bad_url = graphql_cursor_url(
  "https://example.com/api/issues",
  { before = "notacursor" },
  { per_page = "limit", page = "page" }
)
eq(
  before_bad_url,
  "https://example.com/api/issues?limit=30",
  "cursor_url backward: malformed before → page 1, default per_page"
)

-- ---------------------------------------------------------------------------
-- Backward pagination: graphql_make_connection
-- ---------------------------------------------------------------------------

local items10 = {}
for i = 1, 10 do
  items10[i] = { id = i }
end

-- last: N with known total → last page, correct totalCount and flags.
-- ceil(25/10) = 3; page 3 * 10 = 30 >= 25 → hasNextPage false.
local mc_last_known = graphql_make_connection("Issue", items10, { last = 10 }, 25, nil)
eq(mc_last_known.__typename, "IssueConnection", "backward last+total: typename")
eq(mc_last_known.totalCount, 25, "backward last+total: totalCount from total")
eq(mc_last_known.pageInfo.hasNextPage, false, "backward last+total: hasNextPage false (last page)")
eq(
  mc_last_known.pageInfo.hasPreviousPage,
  true,
  "backward last+total: hasPreviousPage true (page 3 > 1)"
)
not_nil(mc_last_known.pageInfo.startCursor, "backward last+total: startCursor non-nil")
not_nil(mc_last_known.pageInfo.endCursor, "backward last+total: endCursor non-nil")
-- Item-level: 10-item page produces distinct start/end cursors.
ok(
  mc_last_known.pageInfo.startCursor ~= mc_last_known.pageInfo.endCursor,
  "backward last+total: startCursor≠endCursor (item-level, 10 items)"
)
ok(
  mc_last_known.edges[1].cursor == mc_last_known.pageInfo.startCursor,
  "backward last+total: first edge is startCursor"
)
ok(
  mc_last_known.edges[10].cursor == mc_last_known.pageInfo.endCursor,
  "backward last+total: last edge is endCursor"
)
eq(#mc_last_known.nodes, 10, "backward last+total: nodes length")
eq(#mc_last_known.edges, 10, "backward last+total: edges length")
eq(mc_last_known.edges[1].__typename, "IssueEdge", "backward last+total: edge typename")

-- last: N with total = N (single page) → page 1, hasPreviousPage false.
local mc_last_single = graphql_make_connection("Issue", items10, { last = 10 }, 10, nil)
eq(mc_last_single.pageInfo.hasNextPage, false, "backward single-page: hasNextPage false")
eq(
  mc_last_single.pageInfo.hasPreviousPage,
  false,
  "backward single-page: hasPreviousPage false (page 1)"
)

-- last: N without total → fallback to page 1; count < per_page → hasNextPage false.
local mc_last_nototal = graphql_make_connection("Issue", items, { last = 5 }, nil, nil)
-- items has 3 entries, per_page = 5; 3 < 5 → hasNextPage false (heuristic).
eq(
  mc_last_nototal.pageInfo.hasNextPage,
  false,
  "backward no-total: hasNextPage false (count<per_page)"
)
eq(
  mc_last_nototal.pageInfo.hasPreviousPage,
  false,
  "backward no-total: hasPreviousPage false (page 1 fallback)"
)
eq(mc_last_nototal.totalCount, 3, "backward no-total: totalCount from count")

-- last: N without total and count == per_page → hasNextPage true (heuristic).
local mc_last_full = graphql_make_connection("Issue", items, { last = 3 }, nil, nil)
eq(
  mc_last_full.pageInfo.hasNextPage,
  true,
  "backward no-total count==per_page: hasNextPage true (heuristic)"
)

-- before: cursor(P) where P > 1 → page P-1.
-- before: cursor(3) → page 2; hasPreviousPage = true (page 2 > 1).
local mc_before3 =
  graphql_make_connection("Issue", items, { last = 3, before = graphql_page_to_cursor(3) }, 10, nil)
eq(mc_before3.__typename, "IssueConnection", "backward before(3): typename")
eq(mc_before3.totalCount, 10, "backward before(3): totalCount from total")
eq(
  mc_before3.pageInfo.hasNextPage,
  true,
  "backward before(3): hasNextPage true (cursor page exists)"
)
eq(
  mc_before3.pageInfo.hasPreviousPage,
  true,
  "backward before(3): hasPreviousPage true (page 2 > 1)"
)
eq(#mc_before3.nodes, 3, "backward before(3): nodes length")
not_nil(mc_before3.pageInfo.startCursor, "backward before(3): startCursor non-nil")
-- Item-level: 3-item page produces distinct cursors.
ok(
  mc_before3.pageInfo.startCursor ~= mc_before3.pageInfo.endCursor,
  "backward before(3): startCursor≠endCursor (3 items)"
)
ok(
  mc_before3.edges[1].cursor == mc_before3.pageInfo.startCursor,
  "backward before(3): first edge is startCursor"
)
ok(
  mc_before3.edges[3].cursor == mc_before3.pageInfo.endCursor,
  "backward before(3): last edge is endCursor"
)

-- before: cursor(2) → page 1; hasPreviousPage false.
local mc_before2 =
  graphql_make_connection("Issue", items, { last = 3, before = graphql_page_to_cursor(2) }, 10, nil)
eq(mc_before2.pageInfo.hasNextPage, true, "backward before(2): hasNextPage true")
eq(mc_before2.pageInfo.hasPreviousPage, false, "backward before(2): hasPreviousPage false (page 1)")

-- before: cursor(1) → empty (nothing exists before page 1).
local mc_before1 =
  graphql_make_connection("Issue", items, { last = 3, before = graphql_page_to_cursor(1) }, 10, nil)
eq(mc_before1.totalCount, 10, "backward before(1): totalCount preserved")
eq(#mc_before1.nodes, 0, "backward before(1): nodes empty")
eq(#mc_before1.edges, 0, "backward before(1): edges empty")
eq(mc_before1.pageInfo.hasNextPage, true, "backward before(1): hasNextPage true (page 1 exists)")
eq(mc_before1.pageInfo.hasPreviousPage, false, "backward before(1): hasPreviousPage false")
is_nil(mc_before1.pageInfo.startCursor, "backward before(1): startCursor nil")

-- before: malformed cursor → empty (can't determine position).
local mc_bad_before = graphql_make_connection("Issue", items, { before = "notacursor" }, 10, nil)
eq(#mc_bad_before.nodes, 0, "backward malformed before: nodes empty")
eq(
  mc_bad_before.pageInfo.hasNextPage,
  false,
  "backward malformed before: hasNextPage false (position unknown)"
)
eq(
  mc_bad_before.pageInfo.hasPreviousPage,
  false,
  "backward malformed before: hasPreviousPage false"
)

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
