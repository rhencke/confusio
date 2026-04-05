-- Mock Bitbucket Datacenter (Server) server.
-- Uses Bitbucket Server REST API v1 at /rest/api/1.0/.
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

  local REPO = '{"id":1,"slug":"hello-world","name":"Hello World","scmId":"git",'
    .. '"state":"AVAILABLE","forkable":true,"public":true,'
    .. '"project":{"key":"octocat","id":1,"name":"Octocat","type":"PERSONAL","public":true},'
    .. '"links":{"self":[{"href":"http://localhost/projects/octocat/repos/hello-world/browse"}]}}'

  local rb = "/rest/api/1.0/projects/octocat/repos/hello-world"

  if path == "/rest/api/1.0/repos" then
    SetStatus(200, "OK")
    json('{"values":[' .. REPO .. '],"isLastPage":true,"start":0,"limit":25}')

  -- Org repos ---------------------------------------------------------------
  elseif path == "/rest/api/1.0/projects/octocat/repos" then
    SetStatus(200, "OK")
    json('{"values":[' .. REPO .. '],"isLastPage":true,"start":0,"limit":25}')
  elseif path == "/rest/api/1.0/projects/testorg/repos" then
    SetStatus(200, "OK")
    json('{"values":[' .. REPO .. '],"isLastPage":true,"start":0,"limit":25}')

  -- Personal repos ----------------------------------------------------------
  elseif path == "/rest/api/1.0/projects/~octocat/repos" then
    SetStatus(200, "OK")
    json('{"values":[' .. REPO .. '],"isLastPage":true,"start":0,"limit":25}')

  -- Single repo -------------------------------------------------------------
  elseif path == rb then
    SetStatus(200, "OK")
    json(REPO)

  -- Tags --------------------------------------------------------------------
  elseif path == rb .. "/tags" then
    SetStatus(200, "OK")
    json(
      '{"values":[{"id":"refs/tags/v1.0","displayId":"v1.0","type":"TAG",'
        .. '"latestCommit":"abc123def456"}],"isLastPage":true}'
    )

  -- Branches ----------------------------------------------------------------
  elseif path == rb .. "/branches" then
    SetStatus(200, "OK")
    json(
      '{"values":[{"id":"refs/heads/main","displayId":"main","type":"BRANCH",'
        .. '"latestCommit":"abc123def456","isDefault":true}],"isLastPage":true}'
    )

  -- Commits -----------------------------------------------------------------
  elseif path == rb .. "/commits/abc123" then
    SetStatus(200, "OK")
    json(
      '{"id":"abc123def456","displayId":"abc123d","message":"Initial commit",'
        .. '"author":{"name":"Octocat","emailAddress":"octocat@github.com"},'
        .. '"authorTimestamp":1296069672000,"parents":[]}'
    )
  elseif path == rb .. "/commits" then
    SetStatus(200, "OK")
    json(
      '{"values":[{"id":"abc123def456","displayId":"abc123d","message":"Initial commit",'
        .. '"author":{"name":"Octocat","emailAddress":"octocat@github.com"},'
        .. '"authorTimestamp":1296069672000,"parents":[]}],"isLastPage":true}'
    )

  -- Contents ---------------------------------------------------------------
  elseif path == rb .. "/raw/README.md" then
    SetStatus(200, "OK")
    raw("# Hello World\n")
  elseif path:find("^" .. rb:gsub("%-", "%%-") .. "/raw/") then
    SetStatus(200, "OK")
    raw("file content\n")

  -- Forks ------------------------------------------------------------------
  elseif path == rb .. "/forks" then
    SetStatus(200, "OK")
    json('{"values":[],"isLastPage":true}')

  -- Deploy keys (ssh) -------------------------------------------------------
  elseif path == rb .. "/ssh/1" then
    SetStatus(200, "OK")
    json(
      '{"id":1,"key":{"id":1,"text":"ssh-rsa AAAAB3...","label":"my key",'
        .. '"createdDate":1609459200000}}'
    )
  elseif path == rb .. "/ssh" then
    SetStatus(200, "OK")
    json(
      '{"values":[{"id":1,"key":{"id":1,"text":"ssh-rsa AAAAB3...",'
        .. '"label":"my key","createdDate":1609459200000}}],"isLastPage":true}'
    )

  -- Webhooks ----------------------------------------------------------------
  elseif path == rb .. "/webhooks/1" then
    SetStatus(200, "OK")
    json(
      '{"id":1,"name":"web","url":"https://example.com/hook",'
        .. '"events":["repo:refs_changed"],"active":true}'
    )
  elseif path == rb .. "/webhooks" then
    SetStatus(200, "OK")
    json(
      '{"values":[{"id":1,"name":"web","url":"https://example.com/hook",'
        .. '"events":["repo:refs_changed"],"active":true}],"isLastPage":true}'
    )

  -- Users ------------------------------------------------------------------
  elseif path == "/rest/api/1.0/users/octocat" then
    SetStatus(200, "OK")
    json(
      '{"id":1,"name":"octocat","slug":"octocat","displayName":"The Octocat",'
        .. '"emailAddress":"octocat@github.com","type":"NORMAL","active":true}'
    )
  elseif path == "/rest/api/1.0/users" then
    SetStatus(200, "OK")
    json(
      '{"values":[{"id":1,"name":"octocat","slug":"octocat","displayName":"The Octocat",'
        .. '"emailAddress":"octocat@github.com","type":"NORMAL","active":true}],"isLastPage":true}'
    )
  else
    SetStatus(404, "Not Found")
  end
end
