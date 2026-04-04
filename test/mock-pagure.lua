-- Mock Pagure server. Uses Pagure REST API at /api/0/.
-- confusio translates Pagure responses to GitHub format.
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
    '{"id":1,"name":"hello-world","fullname":"octocat/hello-world",' ..
    '"namespace":"","user":{"name":"octocat","url_path":"user/octocat"},' ..
    '"description":"My first repo","private":false,"default_branch":"main",' ..
    '"stars":5,"forks_count":2,' ..
    '"date_created":"2011-01-26T19:01:12Z","date_modified":"2011-01-26T19:14:43Z",' ..
    '"url_path":"octocat/hello-world",' ..
    '"full_url":"http://localhost/octocat/hello-world.git",' ..
    '"tags":["lua","api"],"forks":[]}'

  local rp = "/api/0/octocat/hello-world"

  if path == "/api/0/version" then
    SetStatus(200, "OK")
    json('{"version":"5.13.3"}')

  -- whoami -----------------------------------------------------------------
  elseif path == "/api/0/-/whoami" then
    SetStatus(200, "OK")
    json('{"username":"octocat"}')

  -- Repo -------------------------------------------------------------------
  elseif path == rp then
    SetStatus(200, "OK")
    json(REPO)

  -- User repos -------------------------------------------------------------
  elseif path == "/api/0/user/octocat/projects" then
    SetStatus(200, "OK")
    json('{"repos":[' .. REPO .. '],"total_projects":1}')

  -- Org (namespace) repos --------------------------------------------------
  elseif path == "/api/0/projects" then
    SetStatus(200, "OK")
    json('{"projects":[' .. REPO .. '],"total_projects":1}')

  -- Branches ---------------------------------------------------------------
  elseif path == rp .. "/git/branches" then
    SetStatus(200, "OK")
    json('{"branches":["main","develop"],"total_branches":2}')

  -- Commits ----------------------------------------------------------------
  elseif path == rp .. "/commits" then
    SetStatus(200, "OK")
    json('{"commits":[{"id":"abc123def456","message":"Initial commit",' ..
      '"date":"2011-01-26T19:01:12+00:00","date_utc":"2011-01-26T19:01:12Z",' ..
      '"author":{"name":"Octocat","email":"octocat@github.com"}}],' ..
      '"total_commits":1}')

  -- Tags -------------------------------------------------------------------
  elseif path == rp .. "/git/tags" then
    SetStatus(200, "OK")
    json('{"tags":["v1.0","v2.0"]}')

  -- Contents (raw bytes) ---------------------------------------------------
  elseif path == rp .. "/raw/README.md" then
    SetStatus(200, "OK")
    raw("# Hello World\n")

  elseif path:find("^" .. rp:gsub("%-", "%%-") .. "/raw/") then
    SetStatus(200, "OK")
    raw("file content\n")

  -- Users' repos -----------------------------------------------------------
  elseif path:find("^/api/0/user/") then
    SetStatus(200, "OK")
    json('{"repos":[' .. REPO .. '],"total_projects":1}')

  -- Public repos -----------------------------------------------------------
  elseif path == "/api/0/repos" then
    SetStatus(200, "OK")
    json('{"projects":[' .. REPO .. '],"total_projects":1}')

  else
    SetStatus(404, "Not Found")
  end
end
