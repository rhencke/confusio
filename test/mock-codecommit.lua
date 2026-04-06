-- Mock AWS CodeCommit server.
-- Responds to CodeCommit REST API v1 paths used by backends/codecommit.lua.
function OnHttpRequest()
  local path = GetPath()
  local method = GetMethod()

  local function json(body)
    SetHeader("Content-Type", "application/json")
    Write(body)
  end

  local REPO_META = '{"repositoryId":"repo-abc123","repositoryName":"hello-world",'
    .. '"repositoryDescription":"My first repository",'
    .. '"defaultBranch":"main",'
    .. '"cloneUrlHttp":"https://git-codecommit.us-east-1.amazonaws.com/v1/repos/hello-world",'
    .. '"cloneUrlSsh":"ssh://git-codecommit.us-east-1.amazonaws.com/v1/repos/hello-world",'
    .. '"accountId":"123456789012",'
    .. '"creationDate":1296072000.0,'
    .. '"lastModifiedDate":1296072000.0}'

  local REPO_SUMMARY = '{"repositoryId":"repo-abc123","repositoryName":"hello-world"}'

  -- List all repositories -------------------------------------------------------
  if path == "/v1/repos" and method == "GET" then
    SetStatus(200, "OK")
    json('{"repositories":[' .. REPO_SUMMARY .. "]}")

  -- Get single repository -------------------------------------------------------
  elseif path == "/v1/repos/hello-world" and method == "GET" then
    SetStatus(200, "OK")
    json('{"repositoryMetadata":' .. REPO_META .. "}")

  -- Unknown repo → CodeCommit returns 400 with RepositoryDoesNotExistException --
  elseif path:match("^/v1/repos/[^/]+$") and method == "GET" then
    SetStatus(400, "Bad Request")
    json('{"__type":"RepositoryDoesNotExistException","message":"Repository does not exist"}')

  -- List branches ---------------------------------------------------------------
  elseif path == "/v1/repos/hello-world/branches" and method == "GET" then
    SetStatus(200, "OK")
    json('{"branches":["main","dev"]}')
  else
    SetStatus(404, "Not Found")
  end
end
