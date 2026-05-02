-- Mock Radicle server. Uses Radicle HTTP API at /api/v1/.
-- Repos are identified by RID; owner param is ignored in routing.
function OnHttpRequest()
  local path = GetPath()

  local function json(body)
    SetHeader("Content-Type", "application/json")
    Write(body)
  end

  local function raw(body)
    SetHeader("Content-Type", "text/plain")
    Write(body)
  end

  -- Use a simple RID for testing
  local rid = "testrid"

  local REPO = '{"rid":"'
    .. rid
    .. '",'
    .. '"payloads":{"xyz.radicle.project":{'
    .. '"name":"hello-world","description":"My first repo","defaultBranch":"main"}},'
    .. '"delegates":[{"id":"did:key:z6MkGxABC123"}],'
    .. '"private":false}'

  local WEBHOOK_REPO = '{"rid":"rad:z3gqcJUoA1n9HaHKufZs1","name":"hello-world",'
    .. '"description":"My first repo","default_branch":"main",'
    .. '"web_url":"https://radicle.example/nodes/z6MkGxABC123/rad:z3gqcJUoA1n9HaHKufZs1",'
    .. '"clone_url":"rad://rad:z3gqcJUoA1n9HaHKufZs1",'
    .. '"owner":{"id":"did:key:z6MkGxABC123","alias":"octocat"}}'

  local WEBHOOK_USER = '{"id":"did:key:z6MkAlice","alias":"alice",'
    .. '"name":"Alice Example","email":"alice@example.com"}'

  local WEBHOOK_FIXTURES = {
    push = '{"request":"trigger","version":1,"event_type":"push",'
      .. '"event_id":"radicle-push-1","occurred_at":"2024-01-15T10:05:00Z",'
      .. '"repository":'
      .. WEBHOOK_REPO
      .. ',"pusher":'
      .. WEBHOOK_USER
      .. ',"ref":"refs/heads/main","branch":"main",'
      .. '"before":"1111111111111111111111111111111111111111",'
      .. '"after":"2222222222222222222222222222222222222222",'
      .. '"commits":[{"id":"2222222222222222222222222222222222222222",'
      .. '"message":"Update README","timestamp":"2024-01-15T10:05:00Z",'
      .. '"url":"https://radicle.example/nodes/z6MkGxABC123/rad:z3gqcJUoA1n9HaHKufZs1/commits/2222222222222222222222222222222222222222",'
      .. '"author":{"name":"Alice Example","email":"alice@example.com"}}]}',
    create = '{"request":"trigger","version":1,"event_type":"push",'
      .. '"event_id":"radicle-ref-create-1","occurred_at":"2024-01-15T10:04:00Z",'
      .. '"repository":'
      .. WEBHOOK_REPO
      .. ',"pusher":'
      .. WEBHOOK_USER
      .. ',"ref":"refs/heads/feature/radicle-fixtures",'
      .. '"branch":"feature/radicle-fixtures",'
      .. '"before":"0000000000000000000000000000000000000000",'
      .. '"after":"3333333333333333333333333333333333333333",'
      .. '"commits":[{"id":"3333333333333333333333333333333333333333",'
      .. '"message":"Start Radicle fixture work","timestamp":"2024-01-15T10:04:00Z",'
      .. '"url":"https://radicle.example/nodes/z6MkGxABC123/rad:z3gqcJUoA1n9HaHKufZs1/commits/3333333333333333333333333333333333333333",'
      .. '"author":{"name":"Alice Example","email":"alice@example.com"}}]}',
    delete = '{"request":"trigger","version":1,"event_type":"push",'
      .. '"event_id":"radicle-ref-delete-1","occurred_at":"2024-01-15T10:06:00Z",'
      .. '"repository":'
      .. WEBHOOK_REPO
      .. ',"pusher":'
      .. WEBHOOK_USER
      .. ',"ref":"refs/heads/feature/radicle-fixtures",'
      .. '"branch":"feature/radicle-fixtures",'
      .. '"before":"3333333333333333333333333333333333333333",'
      .. '"after":"0000000000000000000000000000000000000000","commits":[]}',
    ["tag-create"] = '{"request":"trigger","version":1,"event_type":"push",'
      .. '"event_id":"radicle-tag-create-1","occurred_at":"2024-01-15T11:00:00Z",'
      .. '"repository":'
      .. WEBHOOK_REPO
      .. ',"pusher":'
      .. WEBHOOK_USER
      .. ',"ref":"refs/tags/v1.0.0","tag":"v1.0.0",'
      .. '"before":"0000000000000000000000000000000000000000",'
      .. '"after":"2222222222222222222222222222222222222222","commits":[]}',
    ["tag-delete"] = '{"request":"trigger","version":1,"event_type":"push",'
      .. '"event_id":"radicle-tag-delete-1","occurred_at":"2024-01-15T11:05:00Z",'
      .. '"repository":'
      .. WEBHOOK_REPO
      .. ',"pusher":'
      .. WEBHOOK_USER
      .. ',"ref":"refs/tags/v1.0.0","tag":"v1.0.0",'
      .. '"before":"2222222222222222222222222222222222222222",'
      .. '"after":"0000000000000000000000000000000000000000","commits":[]}',
    ["patch-created"] = '{"request":"trigger","version":1,"event_type":"patch",'
      .. '"event_id":"radicle-patch-created-1","occurred_at":"2024-01-15T10:30:00Z",'
      .. '"repository":'
      .. WEBHOOK_REPO
      .. ',"sender":'
      .. WEBHOOK_USER
      .. ',"action":"created","patch":{"id":"patches/1","number":1,'
      .. '"title":"Add checkout flow","description":"Implement checkout flow.",'
      .. '"state":"open","target_branch":"main",'
      .. '"base":"1111111111111111111111111111111111111111",'
      .. '"head":"4444444444444444444444444444444444444444",'
      .. '"url":"https://radicle.example/nodes/z6MkGxABC123/rad:z3gqcJUoA1n9HaHKufZs1/patches/1",'
      .. '"author":'
      .. WEBHOOK_USER
      .. ',"created_at":"2024-01-15T10:30:00Z",'
      .. '"updated_at":"2024-01-15T10:30:00Z"}}',
    ["patch-updated"] = '{"request":"trigger","version":1,"event_type":"patch",'
      .. '"event_id":"radicle-patch-updated-1","occurred_at":"2024-01-15T10:50:00Z",'
      .. '"repository":'
      .. WEBHOOK_REPO
      .. ',"sender":'
      .. WEBHOOK_USER
      .. ',"action":"updated","patch":{"id":"patches/1","number":1,'
      .. '"title":"Add checkout flow","description":"Implement checkout flow and tests.",'
      .. '"state":"open","target_branch":"main",'
      .. '"base":"1111111111111111111111111111111111111111",'
      .. '"head":"5555555555555555555555555555555555555555",'
      .. '"url":"https://radicle.example/nodes/z6MkGxABC123/rad:z3gqcJUoA1n9HaHKufZs1/patches/1",'
      .. '"author":'
      .. WEBHOOK_USER
      .. ',"created_at":"2024-01-15T10:30:00Z",'
      .. '"updated_at":"2024-01-15T10:50:00Z",'
      .. '"revisions":[{"id":"4444444444444444444444444444444444444444",'
      .. '"created_at":"2024-01-15T10:30:00Z"},'
      .. '{"id":"5555555555555555555555555555555555555555",'
      .. '"created_at":"2024-01-15T10:50:00Z"}]}}',
  }

  local rb = "/api/v1/repos/" .. rid
  local webhook_fixture = path:match("^" .. rb:gsub("%-", "%%-") .. "/webhook%-fixtures/([^/]+)$")

  if path == "/api/v1" then
    SetStatus(200, "OK")
    json('{"service":"radicle-httpd","version":"0.11.0","node":"did:key:z6MkGxABC123"}')

  -- Repos list (user, public) -----------------------------------------------
  elseif path == "/api/v1/repos" then
    SetStatus(200, "OK")
    json("[" .. REPO .. "]")

  -- Single repo -------------------------------------------------------------
  elseif path == rb then
    SetStatus(200, "OK")
    json(REPO)

  -- Tags --------------------------------------------------------------------
  elseif path == rb .. "/tags" then
    SetStatus(200, "OK")
    json('[{"name":"v1.0","oid":"abc123def456"}]')

  -- Branches ----------------------------------------------------------------
  elseif path == rb .. "/branches" then
    SetStatus(200, "OK")
    json('[{"name":"main","head":"abc123def456"}]')

  -- Commits -----------------------------------------------------------------
  elseif path == rb .. "/commits/abc123" then
    SetStatus(200, "OK")
    json(
      '{"id":"abc123def456","message":"Initial commit",'
        .. '"author":{"name":"Octocat","email":"octocat@github.com"},'
        .. '"committer":{"name":"Octocat","email":"octocat@github.com"}}'
    )
  elseif path == rb .. "/commits" then
    SetStatus(200, "OK")
    json(
      '[{"id":"abc123def456","message":"Initial commit",'
        .. '"author":{"name":"Octocat","email":"octocat@github.com"}}]'
    )

  -- Contents (raw bytes) ----------------------------------------------------
  elseif path == rb .. "/blob/HEAD/README.md" then
    SetStatus(200, "OK")
    raw("# Hello World\n")
  elseif path:find("^" .. rb:gsub("%-", "%%-") .. "/blob/") then
    SetStatus(200, "OK")
    raw("file content\n")

  -- Webhook fixtures -------------------------------------------------------
  elseif WEBHOOK_FIXTURES[webhook_fixture] then
    SetStatus(200, "OK")
    json(WEBHOOK_FIXTURES[webhook_fixture])

  -- Migrations ----------------------------------------------------------------
  -- Radicle has no GitHub-style org/user migration API; confusio
  -- returns fixed responses without proxying. Routes documented here for reference.
  elseif path:match("^/orgs/[^/]+/migrations") or path:match("^/user/migrations") then
    SetStatus(404, "Not Found")
  else
    SetStatus(404, "Not Found")
  end
end
