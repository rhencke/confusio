-- Mock OneDev server. Uses OneDev REST API at /~api/.
-- Projects are identified by integer ID; confusio resolves owner/repo → ID via query.
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

  local PROJECT =
    '{"id":1,"path":"octocat/hello-world","name":"hello-world",' ..
    '"description":"My first repo","public":true,"defaultBranch":"main"}'

  if path == "/~api/server-version" then
    SetStatus(200, "OK")
    json('"10.0.0"')

  -- Project list (used for ID resolution, user repos, org repos, public repos)
  -- Return empty when the query targets an unknown project path.
  elseif path == "/~api/projects" then
    local q = GetParam("query") or ""
    if q ~= "" and not q:find("octocat/hello-world", 1, true) then
      SetStatus(200, "OK")
      json('[]')
    else
      SetStatus(200, "OK")
      json('[' .. PROJECT .. ']')
    end

  -- Single project ---------------------------------------------------------
  elseif path == "/~api/projects/1" then
    SetStatus(200, "OK")
    json(PROJECT)

  -- Tags -------------------------------------------------------------------
  elseif path == "/~api/projects/1/tags" then
    SetStatus(200, "OK")
    json('[{"name":"v1.0","commitHash":"abc123def456"}]')

  -- Branches ---------------------------------------------------------------
  elseif path == "/~api/projects/1/branches" then
    SetStatus(200, "OK")
    json('[{"name":"main","commitHash":"abc123def456"}]')

  -- Commits ----------------------------------------------------------------
  elseif path == "/~api/projects/1/commits/abc123" then
    SetStatus(200, "OK")
    json('{"hash":"abc123def456","message":"Initial commit",' ..
      '"author":{"name":"Octocat","emailAddress":"octocat@github.com","date":"2011-01-26T19:01:12Z"},' ..
      '"committer":{"name":"Octocat","emailAddress":"octocat@github.com","date":"2011-01-26T19:01:12Z"}}')

  elseif path == "/~api/projects/1/commits" then
    SetStatus(200, "OK")
    json('[{"hash":"abc123def456","message":"Initial commit",' ..
      '"author":{"name":"Octocat","emailAddress":"octocat@github.com","date":"2011-01-26T19:01:12Z"},' ..
      '"committer":{"name":"Octocat","emailAddress":"octocat@github.com","date":"2011-01-26T19:01:12Z"}}]')

  -- Contents ---------------------------------------------------------------
  elseif path:find("^/~api/blobs/1/") then
    SetStatus(200, "OK")
    raw("file content\n")

  else
    SetStatus(404, "Not Found")
  end
end
