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

  local PROJECT = '{"id":1,"path":"octocat/hello-world","name":"hello-world",'
    .. '"description":"My first repo","public":true,"defaultBranch":"main"}'

  if path == "/~api/server-version" then
    SetStatus(200, "OK")
    json('"10.0.0"')

  -- Project list (used for ID resolution, user repos, org repos, public repos)
  -- Return empty when the query targets an unknown project path.
  elseif path == "/~api/projects" then
    local q = GetParam("query") or ""
    if q ~= "" and not q:find("octocat/hello-world", 1, true) then
      SetStatus(200, "OK")
      json("[]")
    else
      SetStatus(200, "OK")
      json("[" .. PROJECT .. "]")
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
    json(
      '{"hash":"abc123def456","message":"Initial commit",'
        .. '"author":{"name":"Octocat","emailAddress":"octocat@github.com","date":"2011-01-26T19:01:12Z"},'
        .. '"committer":{"name":"Octocat","emailAddress":"octocat@github.com","date":"2011-01-26T19:01:12Z"}}'
    )
  elseif path == "/~api/projects/1/commits" then
    SetStatus(200, "OK")
    json(
      '[{"hash":"abc123def456","message":"Initial commit",'
        .. '"author":{"name":"Octocat","emailAddress":"octocat@github.com","date":"2011-01-26T19:01:12Z"},'
        .. '"committer":{"name":"Octocat","emailAddress":"octocat@github.com","date":"2011-01-26T19:01:12Z"}}]'
    )

  -- Contents ---------------------------------------------------------------
  elseif path:find("^/~api/blobs/1/") then
    SetStatus(200, "OK")
    raw("file content\n")

  -- Issues -----------------------------------------------------------------
  -- GET /~api/issues?query=... — return issue list or empty based on query.
  elseif path == "/~api/issues" then
    local q = GetParam("query") or ""
    if q:find("9999", 1, true) then
      SetStatus(200, "OK")
      json("[]")
    else
      SetStatus(200, "OK")
      json(
        '[{"id":1,"number":1,"title":"Found a bug","state":"Open",'
          .. '"description":"Bug description",'
          .. '"project":{"id":1,"path":"octocat/hello-world"},'
          .. '"submitter":{"id":1,"name":"octocat","fullName":"The Octocat"},'
          .. '"submitDate":"2020-01-01T00:00:00.000+0000",'
          .. '"updateDate":"2020-01-02T00:00:00.000+0000"}]'
      )
    end

  -- Issue comments ---------------------------------------------------------
  elseif path == "/~api/issue-comments" then
    SetStatus(200, "OK")
    json(
      '[{"id":1,"issueId":1,'
        .. '"user":{"id":1,"name":"octocat","fullName":"The Octocat"},'
        .. '"content":"This is a comment","date":"2020-01-01T00:00:00.000+0000"}]'
    )

  -- Users -------------------------------------------------------------------
  elseif path == "/~api/users" then
    SetStatus(200, "OK")
    json('[{"id":1,"name":"octocat","fullName":"The Octocat","email":"octocat@github.com"}]')

  -- Builds (CI) -------------------------------------------------------------
  -- GET /~api/builds?query=... — return builds for known project+commit, else [].
  elseif path == "/~api/builds" then
    local q = GetParam("query") or ""
    if q:find("octocat/hello-world", 1, true) and q:find("abc123", 1, true) then
      SetStatus(200, "OK")
      json(
        '[{"id":1,"number":1,"jobName":"CI Build","status":"SUCCESSFUL",'
          .. '"commitHash":"abc123def456","refName":"refs/heads/main",'
          .. '"project":{"id":1,"path":"octocat/hello-world"}}]'
      )
    else
      SetStatus(200, "OK")
      json("[]")
    end

  -- Interactions ------------------------------------------------------------
  -- OneDev has no native GitHub Interactions API; confusio returns stubs directly.
  -- These routes document what the backend would return if ever proxied.
  elseif
    (
      path == "/orgs/testorg/interaction-limits"
      or path == "/repos/octocat/hello-world/interaction-limits"
      or path == "/user/interaction-limits"
    ) and (GetMethod() == "GET" or GetMethod() == "PUT" or GetMethod() == "DELETE")
  then
    SetStatus(404, "Not Found")

  -- Migrations ----------------------------------------------------------------
  -- OneDev has no GitHub-style org/user migration API; confusio
  -- returns fixed responses without proxying. Routes documented here for reference.
  elseif path:match("^/orgs/[^/]+/migrations") or path:match("^/user/migrations") then
    SetStatus(404, "Not Found")
  else
    SetStatus(404, "Not Found")
  end
end
