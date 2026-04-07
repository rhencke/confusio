-- Mock Gitblit server. Uses Gitblit HTTP/JSON RPC at /rpc with ?req= dispatch.
-- Repository names follow the pattern "owner/repo.git".
function OnHttpRequest()
  local path = GetPath()
  local method = GetMethod()
  local req = GetParam("req") or ""
  local name = GetParam("name") or ""

  local function json(body)
    SetHeader("Content-Type", "application/json")
    Write(body)
  end

  local REPO = '{"name":"octocat/hello-world.git","description":"My first repository",'
    .. '"HEAD":"refs/heads/main","defaultBranch":"main",'
    .. '"lastChange":"2011-01-26T19:01:12Z","hasCommits":true}'

  local USER = '{"name":"octocat","displayName":"The Octocat",'
    .. '"emailAddress":"octocat@github.com","disabled":false}'

  -- Interactions ---------------------------------------------------------------
  -- Gitblit has no native GitHub Interactions API; confusio returns stubs directly.
  -- These routes document what the backend would return if ever proxied.
  if
    (
      path == "/orgs/testorg/interaction-limits"
      or path == "/repos/octocat/hello-world/interaction-limits"
      or path == "/user/interaction-limits"
    ) and (method == "GET" or method == "PUT" or method == "DELETE")
  then
    SetStatus(404, "Not Found")
    return
  end

  if path ~= "/rpc" then
    SetStatus(404, "Not Found")
    return
  end

  if req == "LIST_REPOSITORIES" then
    SetStatus(200, "OK")
    json('{"octocat/hello-world.git":' .. REPO .. "}")
  elseif req == "GET_REPOSITORY" then
    if name == "octocat/hello-world.git" then
      SetStatus(200, "OK")
      json(REPO)
    else
      -- Gitblit returns an empty object for unknown repos
      SetStatus(200, "OK")
      json("{}")
    end
  elseif req == "LIST_USERS" then
    SetStatus(200, "OK")
    json("[" .. USER .. "]")
  elseif req == "GET_USER" then
    if name == "octocat" then
      SetStatus(200, "OK")
      json(USER)
    else
      SetStatus(200, "OK")
      json("{}")
    end
  else
    SetStatus(400, "Bad Request")
  end
end
