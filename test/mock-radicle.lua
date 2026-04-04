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

  local REPO =
    '{"rid":"' .. rid .. '",' ..
    '"payloads":{"xyz.radicle.project":{' ..
    '"name":"hello-world","description":"My first repo","defaultBranch":"main"}},' ..
    '"delegates":[{"id":"did:key:z6MkGxABC123"}],' ..
    '"private":false}'

  local rb = "/api/v1/repos/" .. rid

  if path == "/api/v1" then
    SetStatus(200, "OK")
    json('{"service":"radicle-httpd","version":"0.11.0","node":"did:key:z6MkGxABC123"}')

  -- Repos list (user, public) -----------------------------------------------
  elseif path == "/api/v1/repos" then
    SetStatus(200, "OK")
    json('[' .. REPO .. ']')

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
    json('{"id":"abc123def456","message":"Initial commit",' ..
      '"author":{"name":"Octocat","email":"octocat@github.com"},' ..
      '"committer":{"name":"Octocat","email":"octocat@github.com"}}')

  elseif path == rb .. "/commits" then
    SetStatus(200, "OK")
    json('[{"id":"abc123def456","message":"Initial commit",' ..
      '"author":{"name":"Octocat","email":"octocat@github.com"}}]')

  -- Contents (raw bytes) ----------------------------------------------------
  elseif path == rb .. "/blob/HEAD/README.md" then
    SetStatus(200, "OK")
    raw("# Hello World\n")

  elseif path:find("^" .. rb:gsub("%-", "%%-") .. "/blob/") then
    SetStatus(200, "OK")
    raw("file content\n")

  else
    SetStatus(404, "Not Found")
  end
end
