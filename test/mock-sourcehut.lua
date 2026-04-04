-- Mock Sourcehut server. Uses git.sr.ht API at /api/.
-- Paths are like /api/~{owner}/repos/{name}.
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

  local REPO =
    '{"id":1,"name":"hello-world","description":"My first repo",' ..
    '"visibility":"public",' ..
    '"created":"2011-01-26T19:01:12Z","updated":"2011-01-26T19:14:43Z",' ..
    '"HEAD":{"name":"refs/heads/main","target":"abc123def456"},' ..
    '"owner":{"canonical_name":"~octocat","name":"octocat"}}'

  local rp = "/api/~octocat/repos/hello-world"

  if path == "/api/version" then
    SetStatus(200, "OK")
    json('{"version":"0.80.2"}')

  -- Authenticated user -----------------------------------------------------
  elseif path == "/api/user" then
    SetStatus(200, "OK")
    json('{"canonical_name":"~octocat","name":"octocat"}')

  -- Repo -------------------------------------------------------------------
  elseif path == rp then
    SetStatus(200, "OK")
    json(REPO)

  -- User repos (via canonical_name) ----------------------------------------
  elseif path == "/api/~octocat/repos" then
    SetStatus(200, "OK")
    json('{"results":[' .. REPO .. '],"total":1,"cursor":null}')

  -- Refs (used for branches AND tags) --------------------------------------
  elseif path == rp .. "/refs" then
    SetStatus(200, "OK")
    json('{"results":[' ..
      '{"name":"refs/heads/main","target":"abc123def456"},' ..
      '{"name":"refs/heads/develop","target":"def456abc123"},' ..
      '{"name":"refs/tags/v1.0","target":"abc123def456"}' ..
      '],"total":3,"cursor":null}')

  -- Commits (log) ----------------------------------------------------------
  elseif path == rp .. "/log/abc123" then
    SetStatus(200, "OK")
    json('{"results":[{"id":"abc123def456","message":"Initial commit",' ..
      '"timestamp":"2011-01-26T19:01:12Z",' ..
      '"author":{"name":"Octocat","email":"octocat@github.com"}}],' ..
      '"total":1,"cursor":null}')

  elseif path == rp .. "/log" then
    SetStatus(200, "OK")
    json('{"results":[{"id":"abc123def456","message":"Initial commit",' ..
      '"timestamp":"2011-01-26T19:01:12Z",' ..
      '"author":{"name":"Octocat","email":"octocat@github.com"}}],' ..
      '"total":1,"cursor":null}')

  -- Contents (raw bytes) ---------------------------------------------------
  elseif path == rp .. "/blob/HEAD/README.md" then
    SetStatus(200, "OK")
    raw("# Hello World\n")

  elseif path:find("^" .. rp:gsub("%-", "%%-") .. "/blob/") then
    SetStatus(200, "OK")
    raw("file content\n")

  else
    SetStatus(404, "Not Found")
  end
end
