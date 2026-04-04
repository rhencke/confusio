-- Mock Azure DevOps server.
-- Responds to ADO Git REST API paths used by backends/azuredevops.lua.
-- config.base_url = http://localhost:{port}
-- GitHub {owner}/{repo} maps to ADO project/repository.
function OnHttpRequest()
  local path   = GetPath()
  local method = GetMethod()

  local function json(body)
    SetHeader("Content-Type", "application/json")
    Write(body)
  end

  -- ADO-format repository object.
  -- id is a GUID used by delete_repo and get_repo_hooks to resolve the repo.
  local REPO_ID = "repo-abc123"
  local REPO =
    '{"id":"' .. REPO_ID .. '","name":"hello-world",' ..
    '"defaultBranch":"refs/heads/main",' ..
    '"remoteUrl":"http://localhost/octocat/hello-world.git",' ..
    '"isPrivate":false,"isDisabled":false,"size":1024,' ..
    '"project":{"id":"proj-abc123","name":"octocat","description":"Test project"}}'

  local ORG_REPO =
    '{"id":"repo-org-123","name":"org-repo",' ..
    '"defaultBranch":"refs/heads/main",' ..
    '"remoteUrl":"http://localhost/testorg/org-repo.git",' ..
    '"isPrivate":false,"isDisabled":false,"size":0,' ..
    '"project":{"id":"proj-testorg","name":"testorg","description":""}}'

  -- ADO-format commit object.
  local COMMIT =
    '{"commitId":"abc123def456","comment":"Initial commit",' ..
    '"author":{"name":"Octocat","email":"octocat@github.com","date":"2011-01-26T19:01:12Z"},' ..
    '"committer":{"name":"Octocat","email":"octocat@github.com","date":"2011-01-26T19:01:12Z"}}'

  local rb = "/octocat/_apis/git/repositories/hello-world"

  -- Connection health check ---------------------------------------------------
  if path == "/_apis/connectionData" then
    SetStatus(200, "OK")
    json('{"locationServiceData":{}}')

  -- All repos (get_user_repos: GET /_apis/git/repositories) ------------------
  elseif path == "/_apis/git/repositories" then
    SetStatus(200, "OK")
    json('{"count":1,"value":[' .. REPO .. ']}')

  -- Project repos (get_org_repos / get_users_repos) --------------------------
  elseif path == "/octocat/_apis/git/repositories" and method == "GET" then
    SetStatus(200, "OK")
    json('{"count":1,"value":[' .. REPO .. ']}')

  elseif path == "/testorg/_apis/git/repositories" and method == "GET" then
    SetStatus(200, "OK")
    json('{"count":1,"value":[' .. ORG_REPO .. ']}')

  -- POST new repo (post_org_repos / post_user_repos) -------------------------
  elseif path == "/octocat/_apis/git/repositories" or
         path == "/default/_apis/git/repositories" then
    SetStatus(201, "Created")
    json(REPO)

  -- Single repo (get_repo / patch_repo) --------------------------------------
  elseif path == rb and (method == "GET" or method == "PATCH") then
    SetStatus(200, "OK")
    json(REPO)

  -- Delete repo by resolved ID (delete_repo second step) --------------------
  elseif path == "/octocat/_apis/git/repositories/" .. REPO_ID and method == "DELETE" then
    SetStatus(204, "No Content")

  -- Refs — branches and tags (filter param distinguishes) -------------------
  elseif path == rb .. "/refs" then
    local filter = GetParam("filter") or ""
    if filter:find("^heads") then
      SetStatus(200, "OK")
      json('{"count":1,"value":[{"name":"refs/heads/main","objectId":"abc123def456"}]}')
    elseif filter == "tags" then
      SetStatus(200, "OK")
      json('{"count":1,"value":[{"name":"refs/tags/v1.0","objectId":"abc123def456"}]}')
    else
      SetStatus(200, "OK")
      json('{"count":0,"value":[]}')
    end

  -- Commits ------------------------------------------------------------------
  elseif path == rb .. "/commits" then
    SetStatus(200, "OK")
    json('{"count":1,"value":[' .. COMMIT .. ']}')

  elseif path == rb .. "/commits/abc123" then
    SetStatus(200, "OK")
    json(COMMIT)

  -- File contents (readme + arbitrary paths) --------------------------------
  elseif path == rb .. "/items" then
    SetStatus(200, "OK")
    Write("Hello World\n")

  -- Forks -------------------------------------------------------------------
  elseif path == rb .. "/forks/octocat" then
    SetStatus(200, "OK")
    json('{"count":1,"value":[' .. REPO .. ']}')

  elseif path == rb .. "/forks" and method == "POST" then
    SetStatus(201, "Created")
    json(REPO)

  -- Webhooks subscriptions (get_repo_hooks second step) --------------------
  elseif path == "/_apis/hooks/subscriptions" then
    SetStatus(200, "OK")
    json('{"count":1,"value":[' ..
      '{"id":1,"status":"enabled","eventType":"git.push",' ..
      '"consumerInputs":{"url":"https://example.com/hook"},' ..
      '"createdDate":"2020-01-01T00:00:00Z","modifiedDate":"2020-01-01T00:00:00Z"}' ..
      ']}')

  else
    SetStatus(404, "Not Found")
  end
end
