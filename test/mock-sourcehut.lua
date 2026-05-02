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

  local REPO = '{"id":1,"name":"hello-world","description":"My first repo",'
    .. '"visibility":"public",'
    .. '"created":"2011-01-26T19:01:12Z","updated":"2011-01-26T19:14:43Z",'
    .. '"HEAD":{"name":"refs/heads/main","target":"abc123def456"},'
    .. '"owner":{"canonical_name":"~octocat","name":"octocat"}}'

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
    json(
      '{"results":['
        .. '{"name":"refs/heads/main","target":"abc123def456"},'
        .. '{"name":"refs/heads/develop","target":"def456abc123"},'
        .. '{"name":"refs/tags/v1.0","target":"abc123def456"}'
        .. '],"total":3,"cursor":null}'
    )

  -- Commits (log) ----------------------------------------------------------
  elseif path == rp .. "/log/abc123" then
    SetStatus(200, "OK")
    json(
      '{"results":[{"id":"abc123def456","message":"Initial commit",'
        .. '"timestamp":"2011-01-26T19:01:12Z",'
        .. '"author":{"name":"Octocat","email":"octocat@github.com"}}],'
        .. '"total":1,"cursor":null}'
    )
  elseif path == rp .. "/log" then
    SetStatus(200, "OK")
    json(
      '{"results":[{"id":"abc123def456","message":"Initial commit",'
        .. '"timestamp":"2011-01-26T19:01:12Z",'
        .. '"author":{"name":"Octocat","email":"octocat@github.com"}}],'
        .. '"total":1,"cursor":null}'
    )

  -- Contents (raw bytes) ---------------------------------------------------
  elseif path == rp .. "/blob/HEAD/README.md" then
    SetStatus(200, "OK")
    raw("# Hello World\n")
  elseif path:find("^" .. rp:gsub("%-", "%%-") .. "/blob/") then
    SetStatus(200, "OK")
    raw("file content\n")

  -- Webhooks ---------------------------------------------------------------
  elseif path == rp .. "/webhooks/1" and GetMethod() == "DELETE" then
    SetStatus(204, "No Content")
  elseif path == rp .. "/webhooks/1" and GetMethod() == "PUT" then
    SetStatus(200, "OK")
    json(
      '{"id":1,"url":"https://example.com/updated-hook",'
        .. '"events":["REPO_UPDATE","GIT_POST_RECEIVE"],"enabled":true}'
    )
  elseif path == rp .. "/webhooks/1" then
    SetStatus(200, "OK")
    json(
      '{"id":1,"url":"https://example.com/hook",' .. '"events":["GIT_POST_RECEIVE"],"enabled":true}'
    )
  elseif path == rp .. "/webhooks" and GetMethod() == "POST" then
    SetStatus(201, "Created")
    json(
      '{"id":2,"url":"https://example.com/new-hook",'
        .. '"events":["GIT_POST_RECEIVE","PATCHSET_RECEIVED"],"enabled":true}'
    )
  elseif path == rp .. "/webhooks" then
    SetStatus(200, "OK")
    json(
      '{"results":[{"id":1,"url":"https://example.com/hook",'
        .. '"events":["GIT_POST_RECEIVE"],"enabled":true}],'
        .. '"total":1,"cursor":null}'
    )

  -- todo.sr.ht Issues (tracker) --------------------------------------------
  -- Paths: /api/~octocat/trackers/hello-world/tickets[/{id}[/events]]
  elseif path == "/api/~octocat/trackers/hello-world/tickets" then
    SetStatus(200, "OK")
    json(
      '{"results":[{"id":1,"created":"2020-01-01T00:00:00+00:00",'
        .. '"updated":"2020-01-02T00:00:00+00:00",'
        .. '"title":"Found a bug","body":"Bug description",'
        .. '"status":"reported",'
        .. '"submitter":{"canonical_name":"~octocat","name":"octocat"}}],'
        .. '"total":1,"next":null}'
    )
  elseif path == "/api/~octocat/trackers/hello-world/tickets/1" then
    SetStatus(200, "OK")
    json(
      '{"id":1,"created":"2020-01-01T00:00:00+00:00",'
        .. '"updated":"2020-01-02T00:00:00+00:00",'
        .. '"title":"Found a bug","body":"Bug description",'
        .. '"status":"reported",'
        .. '"submitter":{"canonical_name":"~octocat","name":"octocat"}}'
    )
  elseif path == "/api/~octocat/trackers/hello-world/tickets/9999" then
    SetStatus(404, "Not Found")
    json('{"errors":[{"field":"ticket","reason":"not found"}]}')
  elseif path == "/api/~octocat/trackers/hello-world/tickets/1/events" then
    SetStatus(200, "OK")
    json(
      '{"results":[{"id":1,"created":"2020-01-03T00:00:00+00:00",'
        .. '"event_type":["comment"],'
        .. '"comment":{"id":1,"created":"2020-01-03T00:00:00+00:00",'
        .. '"text":"This is a comment",'
        .. '"author":{"canonical_name":"~octocat","name":"octocat"}}}],'
        .. '"total":1,"next":null}'
    )

  -- builds.sr.ht Jobs (checks) -------------------------------------------------
  -- GET /api/jobs?filter[tags]=...
  elseif path == "/api/jobs" then
    SetStatus(200, "OK")
    json(
      '{"results":['
        .. '{"id":42,"status":"success","note":"ci/test",'
        .. '"created":"2011-01-26T19:01:12Z","updated":"2011-01-26T19:14:43Z",'
        .. '"tags":{"git.sr.ht/~octocat/hello-world":"abc123"}},'
        .. '{"id":43,"status":"running","note":"ci/lint",'
        .. '"created":"2011-01-26T19:01:12Z","updated":"2011-01-26T19:01:12Z",'
        .. '"tags":{"git.sr.ht/~octocat/hello-world":"abc123"}}'
        .. '],"total":2,"cursor":null}'
    )

  -- Migrations ----------------------------------------------------------------
  -- Sourcehut has no GitHub-style org/user migration API; confusio
  -- returns fixed responses without proxying. Routes documented here for reference.
  elseif path:match("^/orgs/[^/]+/migrations") or path:match("^/user/migrations") then
    SetStatus(404, "Not Found")
  else
    SetStatus(404, "Not Found")
  end
end
