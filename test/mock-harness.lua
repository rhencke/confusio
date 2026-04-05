-- Mock Harness Code server. Uses Harness Code API at /gateway/code/api/v1/.
-- repo_ref is owner%2Frepo; Redbean Fetch decodes %2F to /, so mock receives plain slashes.
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

  local REPO = '{"id":1,"path":"octocat/hello-world","description":"My first repo",'
    .. '"is_public":true,"default_branch":"main","num_stars":80,"num_forks":9,'
    .. '"git_url":"http://localhost/octocat/hello-world.git"}'

  local base = "/gateway/code/api/v1"
  -- Redbean Fetch decodes %2F → / before sending, so mock sees plain slashes
  local rb = base .. "/repos/octocat/hello-world"

  if path == base then
    SetStatus(200, "OK")
    json('{"version":"1.0.0"}')

  -- Repo -------------------------------------------------------------------
  elseif path == rb then
    SetStatus(200, "OK")
    json(REPO)
  elseif path == base .. "/repos" then
    SetStatus(200, "OK")
    json("[" .. REPO .. "]")

  -- Org / space repos ------------------------------------------------------
  elseif path == base .. "/spaces/testorg/repos" then
    SetStatus(200, "OK")
    json("[" .. REPO .. "]")

  -- Tags -------------------------------------------------------------------
  elseif path == rb .. "/tags" then
    SetStatus(200, "OK")
    json('[{"name":"v1.0","sha":"abc123def456"}]')

  -- Branches ---------------------------------------------------------------
  elseif path == rb .. "/branches/main" then
    SetStatus(200, "OK")
    json('{"name":"main","sha":"abc123def456","is_default":true}')
  elseif path == rb .. "/branches" then
    SetStatus(200, "OK")
    json('[{"name":"main","sha":"abc123def456","is_default":true}]')

  -- Commits ----------------------------------------------------------------
  elseif path == rb .. "/commits/abc123" then
    SetStatus(200, "OK")
    json(
      '{"sha":"abc123def456","message":"Initial commit",'
        .. '"author":{"identity":{"name":"Octocat","email":"octocat@github.com"},'
        .. '"when":"2011-01-26T19:01:12Z"},'
        .. '"committer":{"identity":{"name":"Octocat","email":"octocat@github.com"},'
        .. '"when":"2011-01-26T19:01:12Z"},'
        .. '"parent_shas":[]}'
    )
  elseif path == rb .. "/commits" then
    SetStatus(200, "OK")
    json(
      '[{"sha":"abc123def456","message":"Initial commit",'
        .. '"author":{"identity":{"name":"Octocat","email":"octocat@github.com"},'
        .. '"when":"2011-01-26T19:01:12Z"},'
        .. '"committer":{"identity":{"name":"Octocat","email":"octocat@github.com"},'
        .. '"when":"2011-01-26T19:01:12Z"},'
        .. '"parent_shas":[]}]'
    )

  -- Commit statuses (check/commits) ----------------------------------------
  elseif path == rb .. "/check/commits/abc123" then
    SetStatus(200, "OK")
    json(
      '[{"id":1,"status":"success","check_suite_name":"ci",'
        .. '"started":"2020-01-01T00:00:00Z","ended":"2020-01-01T00:00:00Z"}]'
    )

  -- Contents ---------------------------------------------------------------
  elseif path == rb .. "/content/README.md" then
    SetStatus(200, "OK")
    json(
      '{"type":"file","name":"README.md","path":"README.md","sha":"abc123",'
        .. '"size":13,"encoding":"base64","content":"IyBIZWxsbyBXb3JsZAo="}'
    )
  elseif path:find("^" .. rb:gsub("%-", "%%-") .. "/content/") then
    local file = path:match("^" .. rb:gsub("%-", "%%-") .. "/content/(.+)$") or "file"
    SetStatus(200, "OK")
    json(
      '{"type":"file","name":"'
        .. file
        .. '","path":"'
        .. file
        .. '",'
        .. '"sha":"abc123","size":13,"encoding":"base64","content":"ZmlsZSBjb250ZW50Cg=="}'
    )

  -- Languages --------------------------------------------------------------
  elseif path == rb .. "/languages" then
    SetStatus(200, "OK")
    json('{"JavaScript":80,"Lua":20}')

  -- Forks ------------------------------------------------------------------
  elseif path == rb .. "/forks" then
    SetStatus(200, "OK")
    json("[" .. REPO .. "]")

  -- Deploy keys ------------------------------------------------------------
  elseif path == rb .. "/keys/1" then
    SetStatus(200, "OK")
    json(
      '{"id":1,"identifier":"my key","public_key":"ssh-rsa AAAAB3...",'
        .. '"usage":"read","created":1609459200000}'
    )
  elseif path == rb .. "/keys" then
    SetStatus(200, "OK")
    json(
      '[{"id":1,"identifier":"my key","public_key":"ssh-rsa AAAAB3...",'
        .. '"usage":"read","created":1609459200000}]'
    )

  -- Webhooks ---------------------------------------------------------------
  elseif path == rb .. "/webhooks/1" then
    SetStatus(200, "OK")
    json(
      '{"id":1,"identifier":"web","url":"https://example.com/hook",'
        .. '"enabled":true,"triggers":["push"],'
        .. '"created":1609459200000,"updated":1609459200000}'
    )
  elseif path == rb .. "/webhooks" then
    SetStatus(200, "OK")
    json(
      '[{"id":1,"identifier":"web","url":"https://example.com/hook",'
        .. '"enabled":true,"triggers":["push"],'
        .. '"created":1609459200000,"updated":1609459200000}]'
    )

  -- Users' repos -----------------------------------------------------------
  elseif path == base .. "/spaces/octocat/repos" then
    SetStatus(200, "OK")
    json("[" .. REPO .. "]")

  -- Users ------------------------------------------------------------------
  elseif path == base .. "/user" then
    SetStatus(200, "OK")
    json(
      '{"id":1,"uid":"octocat","display_name":"The Octocat","email":"octocat@github.com",'
        .. '"admin":false,"url":""}'
    )
  else
    SetStatus(404, "Not Found")
  end
end
